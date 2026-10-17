package com.arpit.glyf.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import com.arpit.glyf.ime.typing.GlideDecoder
import com.arpit.glyf.ime.typing.GlidePoint
import kotlin.math.abs
import kotlin.math.min

/** Inter, straight from the Flutter bundle — ONE typeface on both
 *  platforms (§5.4). Null → system font, nothing breaks. */
private var cachedInter: android.graphics.Typeface? = null
fun interFace(context: Context): android.graphics.Typeface? {
    cachedInter?.let { return it }
    return try {
        android.graphics.Typeface.createFromAsset(
            context.assets, "flutter_assets/assets/fonts/Inter-Variable.ttf")
            .also { cachedInter = it }
    } catch (_: Exception) { null }
}

/**
 * The key grid, canvas-drawn (one view, zero per-key inflation — the
 * Android mirror of the iOS KeyboardView). Carries the same design
 * language: glass/classic themes, dark variant, bound-key accent dots,
 * press previews, Apple-standard proportions.
 */
@SuppressLint("ViewConstructor")
class GlyfKeyboardView(
    context: Context,
    private val listener: Listener,
) : View(context) {

    interface Listener {
        fun onKey(id: String, char: String?)
        fun onBoundKeyHeld(char: String, glyfId: String)
        /** Space held still until the ring closed — the AI launches, finger
         *  still down. */
        fun onSpaceHoldOpenBar()
        /** Space-bar glide; moves are grapheme clusters, negative = left. */
        fun onCursorGlideBegan()
        fun onCursorMove(graphemes: Int)
        fun onCursorGlideEnded()
        /** Gboard's gesture delete: sliding left from delete selects this many
         *  whole words before the cursor (0 clears the selection). */
        fun onDeleteWordsPreview(count: Int)
        /** The finger lifted after a gesture delete: remove what is selected. */
        fun onDeleteWordsCommit(count: Int)
        /** Whether a held key may run what it is bound to right now. While
         *  the keys type into Glyf's own fields, or into a password, a hold
         *  is the letter's own (its accents). iOS: kbBindingsLive. */
        fun bindingsLive(): Boolean = true
        /** Glide typing (Arpit, 2026-10-07: "implement glide typing, like
         *  glide over keyboard to type"): whether a glide may start now, the
         *  word to float over the finger, and the lift. iOS kbGlide*. */
        fun glideAllowed(): Boolean = false
        fun onGlideMoved(points: List<GlidePoint>, layout: GlideDecoder.Layout): String? = null
        fun onGlideEnded(points: List<GlidePoint>, layout: GlideDecoder.Layout) {}
    }

    /** The key the app's tour is waiting for; drawn with a pulsing ring. */
    var tourKey: String? = null
        set(value) { field = value; invalidate() }

    var mode = Mode.LETTERS
    var kContext = KContext.TEXT
    /** Caps lock: shift tapped twice quickly (iOS and Gboard). While it is
     *  on, typing never turns shift off; only shift itself does. */
    var capsLock = false
        set(value) { field = value; if (value) shifted = true; invalidate() }
    var shifted = false
        set(value) { field = value || capsLock }
    private var lastShiftTap = 0L

    /** A tap on shift: a second tap within 350 ms locks capitals, a tap
     *  while locked unlocks, otherwise shift toggles. */
    fun shiftTapped(now: Long = android.os.SystemClock.uptimeMillis()) {
        when {
            capsLock -> { capsLock = false; shifted = false }
            now - lastShiftTap < 350 -> capsLock = true
            else -> shifted = !shifted
        }
        lastShiftTap = if (capsLock) 0L else now
        invalidate()
    }
    var numberRow = false
    var isDark = false
    var keyTheme = "site"
    var themeBg = ""          // "" | color:#RRGGBB | grad:<id>
    var keyBorders = false
    var themeDim = 0f
    /** The picked keyboard theme (the "skin" setting, docs/THEMES.md), or
     *  null for today's look. It recolours the keys, paints the board, sets
     *  the key-face font and the key sounds; it never moves a size (§0.1). */
    var skin: KeyboardThemes.Theme? = null
        set(value) {
            if (field !== value) {
                field = value
                paletteCache = null
                skinFaceFor = null
                themeSound.use(value?.soundPack ?: "system")
            }
            invalidate()
        }
    /** Theme sounds may play (the "skinSound" setting); off, a theme keeps
     *  today's click. */
    var skinSound = true
    /** The theme's light or dark half, as Appearance picks. */
    private val sv: KeyboardThemes.Variant? get() = skin?.variant(isDark)
    var bindings: Map<String, String> = emptyMap()
    /** The field's return action (EditorInfo IME_ACTION_*), or 0 for a plain
     *  return: go, search, send and done draw iOS's blue key. */
    var returnAction = 0
        set(value) { field = value; invalidate() }

    /** Solid keys with a hard bottom edge: the website look and every colour
     *  theme, which are the same keyboard in another colour (mirrors
     *  Glass.solidLook on iOS). */
    private val solidLook get() = keyTheme == "site" || themeBg.isNotEmpty()

    /** Chrome darkness follows the ink the palette chose. */
    private val chromeDark get() = if (skin != null) isDark else if (solidLook) palette().darkChrome else isDark

    /**
     * One board colour builds the whole keyboard, the way Gboard derives a
     * theme from its seed — the Kotlin twin of Glass.KeyPalette (iOS) and
     * KeyPalette (Dart). Feeding it the website's board reproduces the
     * website's palette, so themes and the default look share one path.
     */
    class KeyPalette(
        val board: Int,
        val key: Int,
        val keyPressed: Int,
        val fn: Int,
        val fnPressed: Int,
        val ink: Int,
        val inkSoft: Int,
        val edge: Int,
        val card: Int,
        val darkChrome: Boolean,
    ) {
        companion object {
            /**
             * A theme's palette for what surrounds the keys (the strip's
             * suggestions, the panels, the emoji board): its board, the
             * strip's ink (checked against every board stop, §5.3) and cards
             * a shade off the board, so text reads on either. The keys draw
             * from the theme itself.
             */
            fun fromSkin(v: KeyboardThemes.Variant, dark: Boolean): KeyPalette {
                val board = v.board[0]
                val card = if (dark) blend(board, Color.WHITE, 0.08f) else blend(board, Color.WHITE, 0.72f)
                val ink = v.stripText
                val pressed = blend(card, ink, 0.14f)
                return KeyPalette(board = board, key = card, keyPressed = pressed,
                    fn = card, fnPressed = pressed, ink = ink,
                    inkSoft = blend(ink, board, if (dark) 0.40f else 0.42f),
                    edge = Color.TRANSPARENT, card = card, darkChrome = dark)
            }

            /** Every colour from one board colour: colour themes. */
            fun fromBoard(board: Int): KeyPalette {
                val light = luminance(board) > 0.34f
                val key = if (light) Color.WHITE else blend(board, Color.WHITE, 0.185f)
                val fn = if (light) blend(board, Color.BLACK, 0.14f)
                         else blend(board, Color.WHITE, 0.12f)
                val ink = if (light) tinted(board, 0.10f, 0.12f) else tinted(board, 0.04f, 0.965f)
                return KeyPalette(
                    board = board,
                    key = key,
                    keyPressed = if (light) blend(key, board, 0.55f) else blend(key, Color.WHITE, 0.11f),
                    fn = fn,
                    fnPressed = if (light) blend(fn, Color.WHITE, 0.18f) else blend(fn, Color.WHITE, 0.08f),
                    ink = ink,
                    inkSoft = blend(ink, board, if (light) 0.42f else 0.40f),
                    edge = Color.argb(if (light) 61 else 179, 0, 0, 0),
                    card = if (light) Color.WHITE else blend(board, Color.WHITE, 0.065f),
                    darkChrome = !light,
                )
            }

            /**
             * iOS's keyboard on the system sheet (GlassTokens.swift), the
             * default look on both phones (Arpit, 2026-09-30: "i need it
             * similar in everything as a brand identity it is"): the sheet
             * #E2E4E8 with white keys in light, #1B1B1D with #404041 keys in
             * dark, every key one colour (iOS 26's), black or white glyphs,
             * a press darkened 14% towards the glyph, and no edge under them.
             */
            fun ios(dark: Boolean): KeyPalette {
                val board = if (dark) Color.rgb(0x1B, 0x1B, 0x1D) else Color.rgb(0xE2, 0xE4, 0xE8)
                val key = if (dark) Color.rgb(0x40, 0x40, 0x41) else Color.WHITE
                val ink = if (dark) Color.WHITE else Color.BLACK
                val pressed = blend(key, ink, 0.14f)
                return KeyPalette(board = board, key = key, keyPressed = pressed,
                    fn = key, fnPressed = pressed, ink = ink,
                    inkSoft = blend(ink, board, if (dark) 0.40f else 0.42f),
                    edge = Color.TRANSPARENT, card = key, darkChrome = dark)
            }

            /**
             * Gboard's default look, which follows the phone's own colours
             * (Material You). Measured against Gboard on the emulator: the
             * function keys are exactly system_accent2_100 (light) and
             * system_accent2_700 (dark); letters are white on a board a fifth
             * of the way from neutral1_50 to neutral1_100 in light, and in
             * dark the board and keys sit just above neutral1_900.
             */
            fun gboardDefault(ctx: Context, dark: Boolean): KeyPalette {
                fun sys(name: String): Int {
                    val id = ctx.resources.getIdentifier(name, "color", "android")
                    return ctx.resources.getColor(id, null)
                }
                return if (!dark) {
                    val board = blend(sys("system_neutral1_50"), sys("system_neutral1_100"), 0.2f)
                    val fn = sys("system_accent2_100")
                    val ink = sys("system_neutral1_900")
                    KeyPalette(board = board, key = Color.WHITE,
                        keyPressed = blend(Color.WHITE, fn, 0.6f), fn = fn,
                        fnPressed = blend(fn, ink, 0.12f), ink = ink,
                        inkSoft = blend(ink, board, 0.42f),
                        edge = Color.TRANSPARENT, card = Color.WHITE, darkChrome = false)
                } else {
                    val n900 = sys("system_neutral1_900")
                    val n800 = sys("system_neutral1_800")
                    val board = blend(n900, n800, 0.2f)
                    val key = extrapolate(n900, n800, 1.2f)
                    val fn = sys("system_accent2_700")
                    val ink = sys("system_neutral1_100")
                    KeyPalette(board = board, key = key,
                        keyPressed = blend(key, Color.WHITE, 0.12f), fn = fn,
                        fnPressed = blend(fn, Color.WHITE, 0.12f), ink = ink,
                        inkSoft = blend(ink, board, 0.40f),
                        edge = Color.TRANSPARENT, card = key, darkChrome = true)
                }
            }

            private fun extrapolate(a: Int, b: Int, t: Float) = Color.rgb(
                (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt().coerceIn(0, 255),
                (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt().coerceIn(0, 255),
                (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt().coerceIn(0, 255))

            fun luminance(c: Int) = (0.2126f * Color.red(c) + 0.7152f * Color.green(c) +
                0.0722f * Color.blue(c)) / 255f

            fun blend(a: Int, b: Int, t: Float): Int {
                val k = t.coerceIn(0f, 1f)
                return Color.rgb(
                    (Color.red(a) + (Color.red(b) - Color.red(a)) * k).toInt(),
                    (Color.green(a) + (Color.green(b) - Color.green(a)) * k).toInt(),
                    (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * k).toInt())
            }

            /** Near-black / near-white carrying a trace of the board's hue. */
            private fun tinted(board: Int, maxSat: Float, value: Float): Int {
                val hsv = FloatArray(3)
                Color.colorToHSV(board, hsv)
                hsv[1] = minOf(hsv[1], maxSat)
                hsv[2] = value
                return Color.HSVToColor(hsv)
            }
        }
    }

    private var paletteCache: Pair<String, KeyPalette>? = null

    fun palette(): KeyPalette {
        val cacheKey = "$themeBg|$isDark|$keyTheme|$themeDim|${skin?.id}"
        paletteCache?.let { if (it.first == cacheKey) return it.second }
        sv?.let { v ->
            return KeyPalette.fromSkin(v, isDark).also { paletteCache = cacheKey to it }
        }
        // The default look is iOS's keyboard (it was Gboard's, the phone's
        // own colours, until 2026-09-30). Picked colour themes are still
        // built from their seed.
        val made = if (keyTheme == "site" && themeBg.isEmpty()) KeyPalette.ios(isDark)
        else KeyPalette.fromBoard(paletteSeed())
        paletteCache = cacheKey to made
        return made
    }

    /** The colour a theme is built from: the pick, a gradient's middle, or
     *  the website's own board. */
    private fun paletteSeed(): Int {
        if (themeBg.startsWith("color:#")) {
            try {
                return dimmed(Color.parseColor(themeBg.removePrefix("color:")), themeDim)
            } catch (_: Exception) {}
        }
        if (themeBg.startsWith("grad:")) {
            GRADIENTS[themeBg.removePrefix("grad:")]?.let {
                return KeyPalette.blend(dimmed(it[0], themeDim), dimmed(it[1], themeDim), 0.5f)
            }
        }
        return if (isDark) SITE_BOARD_DARK else SITE_BOARD_LIGHT
    }

    companion object {
        /** §6.5: a bound LETTER fires at 320ms; the space bar waits longer so
         *  a glide can still start (SpaceGesture.HOLD_MS). */
        const val BOUND_HOLD_MS = 320L
        /** How long delete is held before it starts repeating. */
        const val DELETE_REPEAT_DELAY_MS = 400L
        /** Gboard's default key long-press delay. */
        const val DIGIT_HOLD_MS = 300L
        /** Travel from where the finger landed, in key widths, that makes a
         *  touch on a letter a glide (iOS KeyboardView.glideStart). */
        const val GLIDE_START = 0.7f
        /** The floating word is worked out this often while gliding. */
        const val GLIDE_DECODE_MS = 90L
        /** How long a point stays in the glide's ribbon. */
        const val TRAIL_LIFE_MS = 450L

        /** A tablet's row height from its width (an iPad's 66 at 768 dp,
         *  88 at 1024), between AOSP's sw600 and sw768 keyboards. */
        fun tabletPitchDp(screenWidthDp: Float) = (0.086f * screenWidthDp).coerceIn(56f, 88f)

        /** How wide a tablet's keyboard grows: letter keys no wider than 1.5
         *  times their height (Gboard splits beyond that), centred. */
        fun tabletContentDp(screenWidthDp: Float): Float {
            val pitch = tabletPitchDp(screenWidthDp)
            return minOf(screenWidthDp, 10f * (1.5f * 0.8f * pitch + 0.11f * pitch) + 13f)
        }

        /** The website's two board colours (--kb). */
        val SITE_BOARD_LIGHT = Color.rgb(0xD5, 0xD8, 0xDE)
        val SITE_BOARD_DARK = Color.rgb(0x1F, 0x1F, 0x22)

        /// Gradient ids — same pairs as the Flutter previews and iOS.
        val GRADIENTS: Map<String, IntArray> = mapOf(
            "dusk" to intArrayOf(Color.rgb(124, 92, 255), Color.rgb(236, 106, 222)),
            "ocean" to intArrayOf(Color.rgb(61, 139, 255), Color.rgb(65, 224, 200)),
            "ember" to intArrayOf(Color.rgb(255, 120, 71), Color.rgb(255, 197, 61)),
            "forest" to intArrayOf(Color.rgb(31, 169, 104), Color.rgb(155, 225, 93)),
        )

        fun dimmed(color: Int, dim: Float): Int {
            val k = 1f - dim
            return Color.rgb(
                (Color.red(color) * k).toInt(),
                (Color.green(color) * k).toInt(),
                (Color.blue(color) * k).toInt())
        }
    }

    private var backdropCache: Pair<String, ThemeBackdrop>? = null

    /** Backdrop drawable for the whole IME when a theme is painted. */
    fun themedBackdrop(): android.graphics.drawable.Drawable? {
        skin?.let { t ->
            // The board, its gradient and its texture (Android only, §0.3),
            // behind the strip, the keys and the navigation inset.
            val key = "${t.id}|$isDark"
            backdropCache?.let { if (it.first == key) return it.second }
            return ThemeBackdrop(t, isDark, density).also { backdropCache = key to it }
        }
        if (themeBg.startsWith("color:#") && themeBg.length >= 13) {
            return try {
                android.graphics.drawable.ColorDrawable(
                    dimmed(Color.parseColor(themeBg.removePrefix("color:")), themeDim))
            } catch (_: Exception) { null }
        }
        if (themeBg.startsWith("grad:")) {
            val pair = GRADIENTS[themeBg.removePrefix("grad:")] ?: return null
            return android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                intArrayOf(dimmed(pair[0], themeDim), dimmed(pair[1], themeDim)))
        }
        return null
    }

    private var rows: List<List<Key>> = emptyList()
    private val keyRects = mutableListOf<Pair<Key, RectF>>()
    /** The row each of [keyRects] sits in. */
    private val keyRowOf = mutableListOf<Int>()
    /** The rows or the size changed since the keys were last placed. */
    private var keysDirty = true

    /** Every key where it is now: placed again first if the rows changed
     *  since, so a touch right after ?123 lands on the new keys. */
    private fun placed(): List<Pair<Key, RectF>> {
        if (keysDirty || keyRects.isEmpty()) layoutKeys()
        return keyRects
    }

    /** A key's rectangle in this view, for the tour's coach. */
    fun keyRect(id: String): RectF? = placed().firstOrNull { it.first.id == id }?.second?.let { RectF(it) }

    /** Each key's id and its rectangle in this view, for the debug dump. */
    fun keyBounds(): List<Pair<String, RectF>> = placed().map { (k, r) -> k.id to RectF(r) }

    /** Each key's id and its centre on screen, for the debug state dump. */
    fun keyCenters(): List<Pair<String, IntArray>> {
        val loc = IntArray(2).also { getLocationOnScreen(it) }
        return placed().map { (k, r) ->
            k.id to intArrayOf(loc[0] + r.centerX().toInt(), loc[1] + r.centerY().toInt())
        }
    }
    /** Key-center spacing across a row and between rows, in px — the typing
     *  engine's grid (shared/typing/FORMAT.md "Scoring"). */
    private var keyPitchPx = 1f
    private var rowPitchPx = 1.44f
    private var downX = 0f
    private var downY = 0f

    /** Where the last letter tap landed from its key's center, in key widths. */
    var lastTapOffset: FloatArray? = null
        private set

    /** Row spacing in key widths, for the engine's key geometry. */
    val rowPitch: Float get() = if (keyPitchPx > 1f) rowPitchPx / keyPitchPx else 1.44f

    private val keyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 1f
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7C5CFF")
    }

    private var pressed: Key? = null
    private var pressedRect: RectF? = null
    private val handler2 = Handler(Looper.getMainLooper())
    private var longPressFired = false
    private var deleteRepeats = 0
    /** Words selected by sliding left from delete; 0 when not sliding. */
    private var deleteWords = 0
    /** Non-null while a finger is on the space bar. */
    private var spaceGesture: SpaceGesture? = null
    private var spaceSlidAway = false
    /** Apple's trackpad look: faces blank while the cursor glides. */
    private var trackpadLook = false
    /** §5.3 charge ring — contracts onto the held key over the threshold. */
    private var chargeRect: RectF? = null
    private var chargeProgress = 0f
    private var chargeAnimator: android.animation.ValueAnimator? = null
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#7C5CFF")
    }
    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    fun rebuild() {
        rows = KeyboardLayout.rows(mode, numberRow && mode == Mode.LETTERS, kContext)
        keysDirty = true
        requestLayout()
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        keysDirty = true
    }

    // MARK: palette (mirrors GlassTokens)

    private val accent = Color.parseColor("#7C5CFF")

    private fun keyFill(isPressed: Boolean, isFn: Boolean = false): Int = when {
        solidLook -> palette().let {
            if (isFn) (if (isPressed) it.fnPressed else it.fn)
            else (if (isPressed) it.keyPressed else it.key)
        }
        keyTheme == "glass" && chromeDark ->
            if (isPressed) Color.argb(102, 255, 255, 255) else Color.argb(36, 255, 255, 255)
        keyTheme == "glass" ->
            if (isPressed) Color.argb(235, 255, 255, 255) else Color.argb(148, 255, 255, 255)
        chromeDark ->
            if (isPressed) Color.rgb(140, 140, 148) else Color.rgb(107, 107, 112)
        else ->
            if (isPressed) Color.rgb(237, 237, 240) else Color.WHITE
    }

    private fun ink(): Int =
        if (solidLook) palette().ink else if (chromeDark) Color.WHITE else Color.rgb(18, 18, 20)
    private fun hairline(): Int = when {
        keyBorders && chromeDark -> Color.argb(120, 255, 255, 255)
        keyBorders -> Color.argb(78, 0, 0, 0)
        chromeDark -> Color.argb(26, 255, 255, 255)
        else -> Color.argb(20, 0, 0, 0)
    }

    /** The board. The Glass look's translucent keys sit on the sheet iOS
     *  draws under every keyboard, #E2E4E8 / #1B1B1D, as they do there. */
    fun backdrop(): Int =
        sv?.board?.get(0) ?: if (solidLook) palette().board
        else if (isDark) Color.rgb(0x1B, 0x1B, 0x1D) else Color.rgb(0xE2, 0xE4, 0xE8)

    // MARK: measurement + drawing

    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val w = MeasureSpec.getSize(widthSpec)
        // iOS's key region (KeyMetrics): four rows of 54, or 56 on a phone
        // 414 wide or more, and 0.78 of a row more with the number row (every
        // page shares it, so 123 and ABC never change the height). A phone on
        // its side, a tablet and a small screen size their rows by the screen
        // (rowPitchDp). A digit pad keeps its four rows.
        val numbers = numberRow && !kContext.isPad
        val pitch = rowPitchDp(w)
        val rowsH = if (sideways) pitch * 4 + (if (numbers) 32f else 0f)
                    else pitch * 4 + (if (numbers) pitch * 0.78f else 0f)
        setMeasuredDimension(w, dp(rowsH).toInt())
    }

    /** Where every key goes for the current rows and size. Drawing and
     *  touch both read what this leaves in [keyRects]. */
    /** A phone (not a tablet) held sideways. */
    private val sideways: Boolean
        get() = resources.configuration.let {
            it.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE &&
                it.smallestScreenWidthDp < 600
        }

    /** A tablet or an unfolded foldable: 600 dp or more each way. */
    private val tablet: Boolean get() = resources.configuration.smallestScreenWidthDp >= 600

    /** Row height in dp for a view [w] px wide, every Android screen (Gboard
     *  and AOSP LatinIME scale by the screen; Glyf keeps iOS's proportions):
     *  iOS's 54, 56 from Plus/Max widths, eased in from 402 dp so the 411 dp
     *  most Android phones have isn't a cliff; a tablet's from its width; a
     *  phone on its side from its height; and never so tall that the strip,
     *  the keys and the bar under them take more than half the screen. */
    private fun rowPitchDp(w: Int): Float {
        val cfg = resources.configuration
        val hDp = cfg.screenHeightDp.toFloat().takeIf { it > 0 } ?: 800f
        val pitch = when {
            sideways -> (0.10f * hDp).coerceIn(34f, 40f)
            tablet -> tabletPitchDp(cfg.screenWidthDp.toFloat())
            else -> 54f + 2f * ((w / density - 402f) / 12f).coerceIn(0f, 1f)
        }
        if (sideways) return pitch
        val rows = 4f + (if (numberRow && !kContext.isPad) 0.78f else 0f)
        val room = 0.5f * hDp - 50f - 54f
        return minOf(pitch, maxOf(44f, room / rows))
    }

    private fun layoutKeys() {
        keyRects.clear()
        keyRowOf.clear()
        if (rows.isEmpty()) rows = KeyboardLayout.rows(mode, numberRow && mode == Mode.LETTERS, kContext)
        if (rows.isEmpty() || width == 0 || height == 0) return
        keysDirty = false
        // iOS's grid (KeyboardLayout.frames): Apple's constant margins and
        // gaps, ten columns (three on a pad), keys with units < 0 sharing
        // what the fixed ones leave.
        val isPad = kContext.isPad
        val rowH = height / rows.size.toFloat()
        // A tablet's gaps grow with its rows (AOSP's sw600 proportions).
        val hGap = if (tablet && !isPad) rowH * 0.11f else dp(if (isPad) 6.5f else 6f)
        val margin = dp(if (isPad) 5.5f else 6.5f)
        // A digit pad on a tablet keeps a phone pad's width, centred.
        val padW = if (isPad && tablet) minOf(width - margin * 2, dp(480f)) else width - margin * 2
        val inset = (width - margin * 2 - padW) / 2f
        val availW = padW
        val columns = if (isPad) 3f else 10f
        val pitch = (availW + hGap) / columns
        val unitW = pitch - hGap
        // Short rows (a phone on its side) close the gap up.
        val vGap = if (tablet && !isPad) rowH * 0.2f else if (rowH / density < 45f) dp(8f) else dp(11f)
        val keyH = if (isPad) min(rowH, dp(rowPitchDp(width))) - dp(6f) else rowH - vGap
        val gapV = rowH - keyH
        keyPitchPx = pitch
        rowPitchPx = rowH

        rows.forEachIndexed { r, row ->
            val fixedUnits = row.filter { it.units > 0 }.sumOf { it.units.toDouble() }.toFloat()
            val flexCount = row.count { it.units < 0 }
            val flexUnits = if (flexCount > 0) maxOf(1f, columns - fixedUnits) / flexCount else 0f
            val rowUnits = if (flexCount > 0) columns else fixedUnits
            val rowW = rowUnits * pitch - hGap
            var x = margin + inset + (availW - rowW) / 2f
            val y = r * rowH + gapV / 2f
            for (key in row) {
                val units = if (key.units < 0) flexUnits else key.units
                val block = units * pitch - hGap
                // shift, delete and the mode key sit at 1.35 letters, which
                // leaves the wider gap iOS draws beside them.
                val w = if (key.sideKey) unitW * 1.35f else block
                val left = if (key.gapLeading) x + block - w else x
                keyRects.add(key to RectF(left, y, left + w, y + keyH))
                keyRowOf.add(r)
                x += units * pitch
            }
        }
        // The letters' centres in key widths, for the glide decoder; null on
        // a symbol layer or a digit pad, where there is no glide typing.
        glideLayout = if (mode == Mode.LETTERS && !isPad) GlideDecoder.Layout.of(
            keyRects.mapNotNull { (k, r) ->
                val c = k.char?.singleOrNull()?.takeIf { it in 'a'..'z' } ?: return@mapNotNull null
                Triple(c, r.centerX(), r.centerY())
            }, pitch) else null
    }

    /** The key a touch belongs to. Gboard's and Apple's keyboards have no
     *  dead space: a finger in the gap between keys or rows, or in the
     *  margin beside the outermost key, types the nearest key of the row
     *  it landed in (each row owns its share of the height, gaps included).
     *  Dropping those touches was the "missing keys" at speed (iOS KeyHit). */
    private fun keyAt(x: Float, y: Float): Pair<Key, RectF>? {
        val keys = placed()
        if (keys.isEmpty()) return null
        keys.firstOrNull { it.second.contains(x, y) }?.let { return it }
        val band = if (rowPitchPx > 1f) (y / rowPitchPx).toInt().coerceIn(0, keyRowOf.last()) else 0
        var best: Pair<Key, RectF>? = null
        var bestDistance = Float.MAX_VALUE
        for ((i, placedKey) in keys.withIndex()) {
            if (keyRowOf[i] != band) continue
            val r = placedKey.second
            val dx = maxOf(r.left - x, 0f, x - r.right)
            val dy = maxOf(r.top - y, 0f, y - r.bottom)
            val d = dx * dx + dy * dy
            if (d < bestDistance) { bestDistance = d; best = placedKey }
        }
        return best
    }

    /** iOS's blue return: the field's action is go, search, send or done. */
    private val primaryReturn get() = returnAction == android.view.inputmethod.EditorInfo.IME_ACTION_GO ||
        returnAction == android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH ||
        returnAction == android.view.inputmethod.EditorInfo.IME_ACTION_SEND ||
        returnAction == android.view.inputmethod.EditorInfo.IME_ACTION_DONE

    /** The iOS look: flat keys of one colour, no edge under them. */
    private val iosLook get() = keyTheme == "site" && themeBg.isEmpty()

    override fun onDraw(canvas: Canvas) {
        val keys = placed()
        // iOS's keys: 9.5 corners on every key (Glass.radiusKey).
        val radius = dp(9.5f)
        val v = sv
        dotPaint.color = v?.boundDot ?: accent
        if (v != null) themeFaces.use(skin, isDark)
        // A theme's glows only while animations are on (Reduce Motion, §4.1).
        val glows = v != null && v.shadow.radius > 0 && android.provider.Settings.Global.getFloat(
            context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f

        for ((i, placedKey) in keys.withIndex()) {
            val (key, rect) = placedKey
            // A glide lights the key under the finger: the fill, no balloon.
            val isPressed = (pressed?.id == key.id && pressedRect == rect) || (glideLit != null && glideLit === rect)
            if (key.bare) {
                // Apple's pad function keys have no cap; a press shows one.
                if (isPressed && !key.disabled) {
                    keyPaint.color = v?.function?.fill ?: keyFill(false)
                    canvas.drawRoundRect(rect, radius, radius, keyPaint)
                }
                if (!trackpadLook) drawFace(canvas, key, rect)
                continue
            }
            val bound = key.char != null && bindings.containsKey(key.char)
            val glowKey = keyTheme == "glow" && bound && !isPressed && themeBg.isEmpty()
            val blue = key.id == "return" && primaryReturn
            var roundCap = false
            // GPU-painted shadow: offset round-rect (the crisp 1dp iOS
            // drop). Glow keys get a soft accent halo from two stacked
            // translucent rects — no blur layers, no CPU rendering.
            if (v != null) {
                // A theme: its edge or glow under the key, then the class's
                // face (shared/themes/styles.py): fill, texture, light and
                // the theme's ornament. A round cap brings its own shadow.
                val cls = skinClass(key)
                val face = v.style.face(cls)
                roundCap = face.round
                faceFill = skinFill(key, v, isPressed)
                if (!roundCap) drawSkinShadow(canvas, rect, radius, v.shadow, glows)
                themeFaces.drawKey(canvas, rect, radius, face, faceFill, v, cls, ornamentOn(key, cls), keyFace())
            } else if (glowKey) {
                shadowPaint.color = Color.argb(34, 124, 92, 255)
                val halo2 = RectF(rect.left - dp(2f), rect.top,
                    rect.right + dp(2f), rect.bottom + dp(4.5f))
                canvas.drawRoundRect(halo2, radius + dp(2f), radius + dp(2f), shadowPaint)
                shadowPaint.color = Color.argb(70, 124, 92, 255)
                val halo1 = RectF(rect.left, rect.top + dp(1f),
                    rect.right, rect.bottom + dp(2.5f))
                canvas.drawRoundRect(halo1, radius, radius, shadowPaint)
                keyPaint.color = if (isDark) Color.rgb(92, 87, 122)
                                 else Color.rgb(246, 244, 255)
            } else if (blue) {
                // Apple's #007AFF (#0A84FF dark), 18% darker pressed.
                val base = if (isDark) Color.rgb(10, 132, 255) else Color.rgb(0, 122, 255)
                keyPaint.color = if (isPressed) KeyPalette.blend(base, Color.BLACK, 0.18f) else base
            } else {
                // iOS 26: every key one colour, flat. Other looks keep the
                // website's hard 2dp edge under each key.
                val fn = !iosLook && solidLook && when {
                    key.id == "emojikey" || key.id == "space" -> false
                    key.char != null -> false
                    else -> true
                }
                if (!iosLook) {
                    val lift = if (solidLook) dp(2f) else dp(1f)
                    shadowPaint.color =
                        if (solidLook) palette().edge
                        else Color.argb(if (keyTheme == "glass") 26 else 56, 0, 0, 0)
                    val drop = RectF(rect.left, rect.top + lift,
                        rect.right, rect.bottom + lift)
                    canvas.drawRoundRect(drop, radius, radius, shadowPaint)
                }
                keyPaint.color = keyFill(isPressed, fn)
            }
            if (v == null) canvas.drawRoundRect(rect, radius, radius, keyPaint)
            else if (!roundCap) drawSkinFace(canvas, key, rect, radius, v)
            if (tourKey != null && key.id == tourKey) {
                // One second per pulse, redrawn a frame at a time while
                // the tour waits on this key.
                val phase = (android.os.SystemClock.uptimeMillis() % 1400) / 700f
                val a = if (phase < 1f) 1f - phase * 0.75f else 0.25f + (phase - 1f) * 0.75f
                strokePaint.color = Color.argb((255 * a).toInt(), 0x7C, 0x5C, 0xFF)
                strokePaint.strokeWidth = dp(2.5f)
                val ring = RectF(rect).apply { inset(-dp(3f), -dp(3f)) }
                canvas.drawRoundRect(ring, radius + dp(3f), radius + dp(3f), strokePaint)
                postInvalidateDelayed(32)
            }
            if (v == null && (keyBorders || !solidLook)) {
                strokePaint.color = hairline()
                strokePaint.strokeWidth = if (keyBorders) dp(1.1f) else 1f
                canvas.drawRoundRect(rect, radius, radius, strokePaint)
            }

            if (!trackpadLook) {
                drawFace(canvas, key, rect)
                key.char?.let { c ->
                    if (bindings.containsKey(c)) {
                        canvas.drawCircle(rect.right - dp(8f), rect.top + dp(8f), dp(2.5f), dotPaint)
                    }
                }
            }
        }

        chargeRect?.let { rect ->
            // 1.18× → 1× over the hold, fading in fast; stays closed once
            // armed. A wide key (the space bar) starts as far outside itself
            // as a letter does, not 18% of its width past each end (iOS).
            val out = 0.18f * (1f - chargeProgress)
            val sx = 1f + out * min(1f, dp(40f) / maxOf(rect.width(), 1f))
            val sy = 1f + out
            val hw = rect.width() * sx / 2f
            val hh = rect.height() * sy / 2f
            ringPaint.strokeWidth = dp(2f)
            ringPaint.alpha = (255 * min(1f, chargeProgress * 4f)).toInt()
            canvas.drawRoundRect(
                RectF(rect.centerX() - hw, rect.centerY() - hh, rect.centerX() + hw, rect.centerY() + hh),
                radius * sx, radius * sy, ringPaint)
        }

        // Press preview: Apple's key callout, the twin of iOS
        // KeyView.showPreview (measured on Apple's keyboard, 2026-10-17).
        val p = pressed
        val pr = pressedRect
        if (p?.char != null && p.char.length == 1 && !p.pad && pr != null && !longPressFired && !trackpadLook) {
            drawCallout(canvas, p, pr, radius)
        }

        // The accent popup (iOS AccentPopup): a card over the held key with
        // the option under the finger lit.
        val box = accentBox
        val options = accentOptions
        if (box != null && options != null) {
            shadowPaint.color = Color.argb(28, 0, 0, 0)
            canvas.drawRoundRect(RectF(box.left - dp(2f), box.top, box.right + dp(2f), box.bottom + dp(5f)),
                dp(10f), dp(10f), shadowPaint)
            shadowPaint.color = Color.argb(46, 0, 0, 0)
            canvas.drawRoundRect(RectF(box.left, box.top + dp(2f), box.right, box.bottom + dp(3f)),
                dp(9f), dp(9f), shadowPaint)
            keyPaint.color = v?.popupFill ?: if (solidLook) palette().card
                             else if (isDark) Color.rgb(107, 107, 112) else Color.WHITE
            canvas.drawRoundRect(box, dp(8f), dp(8f), keyPaint)
            textPaint.textSize = dp(22f)
            textPaint.typeface = keyFace()
            for ((i, option) in options.withIndex()) {
                val left = box.left + dp(4f) + accentSlot(i) * accentCell
                val cell = RectF(left, box.top + dp(6f), left + accentCell, box.bottom - dp(6f))
                if (i == accentIndex) {
                    keyPaint.color = v?.returnPrimary?.fill ?: accent
                    canvas.drawRoundRect(cell, dp(7f), dp(7f), keyPaint)
                }
                textPaint.color = if (i == accentIndex) (v?.returnPrimary?.glyph ?: Color.WHITE)
                                  else (v?.popupText ?: ink())
                canvas.drawText(option, cell.centerX(), cell.centerY() + textPaint.textSize * 0.36f, textPaint)
            }
        }
        drawGlideTrail(canvas)
    }

    private fun display(key: Key): String {
        val c = key.char ?: return ""
        return if (shifted) c.uppercase() else c
    }

    private val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val calloutPath = android.graphics.Path()

    /** How far above its own top this view may draw: down through every
     *  parent that lets children overflow (the root lets a top-row key's
     *  callout rise over the strip), stopping at the first that clips. */
    private fun roomAbove(): Float {
        var room = 0f
        var v: View = this
        while (true) {
            room += v.top - v.scrollY
            val parent = v.parent as? android.view.ViewGroup ?: break
            if (parent.clipChildren) break
            v = parent
        }
        return room
    }

    /** Apple's key callout: one shape grown out of the key, never a box
     *  floating over it. The bulb is the key's width plus 12 a side with 12
     *  top corners, its top 69 above the key's top; the sides fall straight
     *  to 15 above the key, then an S-curve meets the key's sides 5 below
     *  its top. The key's own fill, no border, no shadow; the letter 1.5
     *  times the key's, its baseline 20.7 above the key. An edge key keeps
     *  that edge straight and leans the bulb inward. Measured on 45-tall
     *  keys and 43-tall ones (bulb 66.7 above, baseline 20); where the top edge leaves
     *  too little room the neck then the bulb get shorter. */
    private fun drawCallout(canvas: Canvas, key: Key, k: RectF, r: Float) {
        val s = k.height() / dp(45f)
        val corner = dp(12f)
        val room = maxOf(0f, k.top + roomAbove() - dp(1f))
        val h = k.height() / density
        val fullRise = dp(69f - (45f - h) * 1.15f)
        val baselineRise = dp(20.7f - (45f - h) * 0.35f)
        var bulbRise = fullRise
        var neckTopRise = dp(15f) * s
        val neckDrop = dp(5f) * s
        if (bulbRise > room) {
            neckTopRise -= min(bulbRise - room, dp(6f) * s)
            bulbRise = room
        }
        val bulbTop = k.top - bulbRise
        val neckTop = k.top - neckTopRise
        val neckBottom = k.top + neckDrop
        var bx0 = k.centerX() - (k.width() + dp(24f)) / 2
        var bx1 = k.centerX() + (k.width() + dp(24f)) / 2
        var straightLeft = false
        var straightRight = false
        if (bx0 < dp(1f)) {
            straightLeft = true; bx0 = k.left; bx1 = k.right + dp(21.5f)
        } else if (bx1 > width - dp(1f)) {
            straightRight = true; bx1 = k.right; bx0 = k.left - dp(21.5f)
        }
        val half = (neckBottom - neckTop) / 2
        val path = calloutPath
        path.reset()
        path.moveTo(k.left, k.bottom - r)
        if (!straightLeft) {
            path.lineTo(k.left, neckBottom)
            path.cubicTo(k.left, neckBottom - half, bx0, neckTop + half, bx0, neckTop)
        }
        path.lineTo(bx0, bulbTop + corner)
        path.arcTo(RectF(bx0, bulbTop, bx0 + 2 * corner, bulbTop + 2 * corner), 180f, 90f)
        path.lineTo(bx1 - corner, bulbTop)
        path.arcTo(RectF(bx1 - 2 * corner, bulbTop, bx1, bulbTop + 2 * corner), 270f, 90f)
        if (!straightRight) {
            path.lineTo(bx1, neckTop)
            path.cubicTo(bx1, neckTop + half, k.right, neckBottom - half, k.right, neckBottom)
        }
        path.lineTo(k.right, k.bottom - r)
        path.arcTo(RectF(k.right - 2 * r, k.bottom - 2 * r, k.right, k.bottom), 0f, 90f)
        path.lineTo(k.left + r, k.bottom)
        path.arcTo(RectF(k.left, k.bottom - 2 * r, k.left + 2 * r, k.bottom), 90f, 90f)
        path.close()
        // A theme draws it in the letter face's fill and texture (never
        // round); the shape stays.
        val v = sv
        if (v != null) {
            themeFaces.drawCallout(canvas, path, v.style.letter, v.letter.fill)
            setLegend(v.style.legend, v.letter.fill)
        } else {
            keyPaint.color = if (solidLook) palette().key else if (isDark) Color.rgb(107, 107, 112) else Color.WHITE
            canvas.drawPath(path, keyPaint)
            legendOn = null
        }

        // The key's own letter size (drawFace), half again; a shortened
        // bulb takes a smaller one.
        val letter = (0.51f * k.height() / density).coerceIn(20f, 30f)
        val keySize = dp(if (shifted) letter * 20f / 22f else letter)
        val fit = min(1f, (neckTop - bulbTop) / (fullRise - dp(15f) * s))
        textPaint.color = v?.keyText ?: ink()
        textPaint.typeface = keyFace()
        textPaint.letterSpacing = 0f
        textPaint.textSize = keySize * 1.5f * maxOf(0.82f, fit)
        legendText(canvas, display(key), (bx0 + bx1) / 2, bulbTop + (fullRise - baselineRise) * fit)
    }

    private fun drawFace(canvas: Canvas, key: Key, rect: RectF) {
        // Greyed: the phone pad's digits behind +*#, as Apple draws them.
        val base = sv?.let { skinInk(key, it) } ?: ink()
        val ink = if (key.disabled) withAlpha(base, 0.35f) else base
        faceInk = ink
        textPaint.color = ink
        textPaint.typeface = keyFace()
        textPaint.letterSpacing = 0f
        // The theme's legend (engraved, letterpress, foil, glow) on the
        // keys it draws a face for; a pad's and a capless key's stay ink.
        val v = sv
        if (v != null && !key.bare && !key.pad && !key.disabled)
            setLegend(if (key.id == "return") v.style.returnLegend else v.style.legend, faceFill)
        else legendOn = null
        when (key.id) {
            "shift" -> { glyphLegend(canvas, rect) { drawShift(canvas, rect) }; return }
            "return" -> { glyphLegend(canvas, rect) { drawReturn(canvas, rect) }; return }
            "delete" -> { glyphLegend(canvas, rect) { drawDelete(canvas, rect, big = key.pad) }; return }
            "emojikey" -> { glyphLegend(canvas, rect) { drawSmiley(canvas, rect) }; return }
        }
        if (key.pad) { drawPadFace(canvas, key, rect, ink); return }
        val label: String = when {
            key.char != null && key.char.length > 1 -> {
                // ".com": Apple sets it like a word, never in capitals.
                textPaint.textSize = dp(17f)
                key.char
            }
            key.char != null -> {
                // Same optical size as the iOS build (a letter fills about
                // half the key's height), so the two keyboards are twins —
                // and, like the system keyboards, capitals are drawn smaller
                // (22:25 on iOS) so both cases read as one size. Taller keys
                // (a tablet) take bigger letters, up to 30.
                val letter = (0.51f * rect.height() / density).coerceIn(20f, 30f)
                textPaint.textSize = dp(if (shifted) letter * 20f / 22f else letter)
                display(key)
            }
            key.id == "space" -> {
                // The "glyf" watermark: the key's glyph colour at 40%, in
                // Inter whatever the theme (the brand, §0.5).
                textPaint.textSize = dp(13.5f)
                textPaint.color = withAlpha(ink, 0.40f)
                textPaint.typeface = interFace(context)
                "glyf"
            }
            key.id.startsWith("mode:") -> {
                // Apple's "123" and "ABC" at 18pt, "#+=" at 13pt.
                val m = key.id.removePrefix("mode:")
                textPaint.textSize = dp(if (m == "#+=") 12f else 16f)
                m
            }
            else -> ""
        }
        val y = rect.centerY() + textPaint.textSize * 0.36f
        // The space bar's "glyf" stays plain, centred and readable.
        if (key.id == "space") canvas.drawText(label, rect.centerX(), y, textPaint)
        else legendText(canvas, label, rect.centerX(), y)
    }

    /** Apple's pad faces: digits with their letters under them, the
     *  phone pad's symbols, "pause" and "wait", and its +*# and 123. */
    private fun drawPadFace(canvas: Canvas, key: Key, rect: RectF, ink: Int) {
        val c = key.char
        val title = key.title
        when {
            key.id.startsWith("mode:") -> {
                val m = key.id.removePrefix("mode:")
                textPaint.textSize = dp(if (m == "+*#") 20.5f else 19f)
                if (m == "+*#") textPaint.letterSpacing = 0.14f
                canvas.drawText(m, rect.centerX(), rect.centerY() + dp(6f) * 0.9f, textPaint)
                textPaint.letterSpacing = 0f
            }
            title != null -> {
                textPaint.textSize = dp(15f)
                canvas.drawText(title, rect.centerX(), rect.centerY() + textPaint.textSize * 0.36f, textPaint)
            }
            c != null && c.length == 1 && c[0].isDigit() -> {
                textPaint.textSize = dp(20f)
                val sub = key.subtitle
                // Apple: a digit's baseline 2.7 below the middle, its letters 18 below.
                canvas.drawText(c, rect.centerX(), rect.centerY() + dp(2.5f), textPaint)
                if (sub != null) {
                    textPaint.textSize = dp(8.5f)
                    textPaint.typeface = Glass.font(context, Glass.SEMIBOLD)
                    textPaint.letterSpacing = 0.22f
                    canvas.drawText(sub, rect.centerX(), rect.centerY() + dp(16f), textPaint)
                    textPaint.letterSpacing = 0f
                    textPaint.typeface = keyFace()
                }
            }
            c != null && c.isNotEmpty() -> {
                // "*", "#" and "+" at 30pt, a separator a little higher.
                textPaint.textSize = dp(if (c in listOf("*", "#", "+")) 27f else 20f)
                canvas.drawText(c, rect.centerX(), rect.centerY() + textPaint.textSize * 0.36f, textPaint)
            }
        }
    }

    private fun withAlpha(c: Int, a: Float) =
        Color.argb((a * 255).toInt(), Color.red(c), Color.green(c), Color.blue(c))

    /** The digit a held top-row letter types, or null. Nothing is drawn for
     *  it (iOS shows no hints); the hold still types it. */
    private fun holdDigit(key: Key): String? {
        if (mode != Mode.LETTERS || numberRow) return null
        val c = key.char ?: return null
        if (bindings.containsKey(c)) return null
        val i = "qwertyuiop".indexOf(c)
        return if (i < 0) null else ((i + 1) % 10).toString()
    }

    /** SF face.smiling at iOS's size, outline, in the glyph colour. */
    private fun drawSmiley(canvas: Canvas, rect: RectF) {
        glyphPaint.color = faceInk
        glyphPaint.style = Paint.Style.STROKE
        glyphPaint.strokeWidth = glyphK * dp(1.35f)
        val cx = rect.centerX(); val cy = rect.centerY()
        canvas.drawCircle(cx, cy, dp(8.6f), glyphPaint)
        // The eyes in the same paint, so a theme's legend inks them too.
        glyphPaint.style = Paint.Style.FILL
        canvas.drawOval(cx - dp(3.9f), cy - dp(3.6f), cx - dp(2.3f), cy - dp(0.9f), glyphPaint)
        canvas.drawOval(cx + dp(2.3f), cy - dp(3.6f), cx + dp(3.9f), cy - dp(0.9f), glyphPaint)
        glyphPaint.style = Paint.Style.STROKE
        canvas.drawArc(cx - dp(4.4f), cy - dp(1.6f), cx + dp(4.4f), cy + dp(5f),
            20f, 140f, false, glyphPaint)
    }

    /** SF shift (light): an outlined arrow, filled while shifted. */
    private fun drawShift(canvas: Canvas, rect: RectF) {
        val cx = rect.centerX(); val cy = rect.centerY()
        val w = dp(9f); val stem = dp(4f)
        val path = android.graphics.Path().apply {
            moveTo(cx, cy - dp(7.5f))            // apex
            lineTo(cx + w, cy + dp(1f))
            lineTo(cx + stem, cy + dp(1f))
            lineTo(cx + stem, cy + dp(7.5f))
            lineTo(cx - stem, cy + dp(7.5f))
            lineTo(cx - stem, cy + dp(1f))
            lineTo(cx - w, cy + dp(1f))
            close()
        }
        glyphPaint.color = faceInk
        glyphPaint.strokeWidth = glyphK * dp(1.3f)
        glyphPaint.style = if (shifted) Paint.Style.FILL_AND_STROKE else Paint.Style.STROKE
        canvas.drawPath(path, glyphPaint)
        if (capsLock) {
            // iOS's caps lock: the filled arrow with a bar under it.
            glyphPaint.style = Paint.Style.FILL
            canvas.drawRect(cx - stem, cy + dp(9.5f), cx + stem, cy + dp(11.5f), glyphPaint)
        }
    }

    /** SF delete.left (light): a tag pointing left with a cross in it;
     *  Apple's pads draw a bigger one. */
    private fun drawDelete(canvas: Canvas, rect: RectF, big: Boolean) {
        val k = if (big) 1.2f else 1f
        val cx = rect.centerX() + dp(0.5f) * k; val cy = rect.centerY()
        val path = android.graphics.Path().apply {
            moveTo(cx - dp(10.5f) * k, cy)
            lineTo(cx - dp(5f) * k, cy - dp(7.5f) * k)
            lineTo(cx + dp(9f) * k, cy - dp(7.5f) * k)
            quadTo(cx + dp(10.5f) * k, cy - dp(7.5f) * k, cx + dp(10.5f) * k, cy - dp(6f) * k)
            lineTo(cx + dp(10.5f) * k, cy + dp(6f) * k)
            quadTo(cx + dp(10.5f) * k, cy + dp(7.5f) * k, cx + dp(9f) * k, cy + dp(7.5f) * k)
            lineTo(cx - dp(5f) * k, cy + dp(7.5f) * k)
            close()
        }
        glyphPaint.color = faceInk
        glyphPaint.style = Paint.Style.STROKE
        glyphPaint.strokeWidth = glyphK * dp(1.3f)
        canvas.drawPath(path, glyphPaint)
        val x0 = cx + dp(0.4f) * k; val r = dp(3.1f) * k
        canvas.drawLine(x0 - r, cy - r, x0 + r, cy + r, glyphPaint)
        canvas.drawLine(x0 + r, cy - r, x0 - r, cy + r, glyphPaint)
    }

    /** Return, as iOS draws it for the field: its ⏎ glyph, or on the blue
     *  key a white arrow (go), magnifier (search), up arrow (send) or
     *  check (done); a chevron for next. */
    private fun drawReturn(canvas: Canvas, rect: RectF) {
        val cx = rect.centerX(); val cy = rect.centerY()
        glyphPaint.style = Paint.Style.STROKE
        glyphPaint.color = if (primaryReturn && sv == null) Color.WHITE else faceInk
        when (returnAction) {
            android.view.inputmethod.EditorInfo.IME_ACTION_GO -> {
                glyphPaint.strokeWidth = glyphK * dp(1.9f)
                canvas.drawLine(cx - dp(7.5f), cy, cx + dp(7.5f), cy, glyphPaint)
                canvas.drawLine(cx + dp(7.5f), cy, cx + dp(1.8f), cy - dp(5.8f), glyphPaint)
                canvas.drawLine(cx + dp(7.5f), cy, cx + dp(1.8f), cy + dp(5.8f), glyphPaint)
            }
            android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH -> {
                glyphPaint.strokeWidth = glyphK * dp(1.6f)
                canvas.drawCircle(cx - dp(1.5f), cy - dp(1.5f), dp(6f), glyphPaint)
                canvas.drawLine(cx + dp(3f), cy + dp(3f), cx + dp(7.8f), cy + dp(7.8f), glyphPaint)
            }
            android.view.inputmethod.EditorInfo.IME_ACTION_SEND -> {
                glyphPaint.strokeWidth = glyphK * dp(1.9f)
                canvas.drawLine(cx, cy + dp(7.5f), cx, cy - dp(7.5f), glyphPaint)
                canvas.drawLine(cx, cy - dp(7.5f), cx - dp(5.8f), cy - dp(1.8f), glyphPaint)
                canvas.drawLine(cx, cy - dp(7.5f), cx + dp(5.8f), cy - dp(1.8f), glyphPaint)
            }
            android.view.inputmethod.EditorInfo.IME_ACTION_DONE -> {
                glyphPaint.strokeWidth = glyphK * dp(1.9f)
                val tick = android.graphics.Path().apply {
                    moveTo(cx - dp(6.8f), cy + dp(0.4f))
                    lineTo(cx - dp(2.2f), cy + dp(5.2f))
                    lineTo(cx + dp(7f), cy - dp(5.6f))
                }
                canvas.drawPath(tick, glyphPaint)
            }
            android.view.inputmethod.EditorInfo.IME_ACTION_NEXT -> {
                glyphPaint.strokeWidth = glyphK * dp(1.4f)
                canvas.drawLine(cx - dp(2.8f), cy - dp(7.5f), cx + dp(3.6f), cy, glyphPaint)
                canvas.drawLine(cx + dp(3.6f), cy, cx - dp(2.8f), cy + dp(7.5f), glyphPaint)
            }
            else -> {
                // SF return (light): down from the top right, then left to an arrowhead.
                glyphPaint.strokeWidth = glyphK * dp(1.3f)
                val path = android.graphics.Path().apply {
                    moveTo(cx + dp(8f), cy - dp(6.5f))
                    lineTo(cx + dp(8f), cy + dp(1.5f))
                    quadTo(cx + dp(8f), cy + dp(3.5f), cx + dp(6f), cy + dp(3.5f))
                    lineTo(cx - dp(8f), cy + dp(3.5f))
                }
                canvas.drawPath(path, glyphPaint)
                val head = android.graphics.Path().apply {
                    moveTo(cx - dp(4f), cy - dp(0.5f))
                    lineTo(cx - dp(8f), cy + dp(3.5f))
                    lineTo(cx - dp(4f), cy + dp(7.5f))
                }
                canvas.drawPath(head, glyphPaint)
            }
        }
    }

    // MARK: touch

    /** The finger being followed, or -1. Fast two-thumb typing puts the next
     *  finger down before the last one lifts: the held key types right then,
     *  as if lifted, and the new finger takes over (LatinIME's way), so no
     *  letter is lost. */
    private var activePointer = -1
    /** Where the followed finger is now. */
    private var lastX = 0f

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                // A press whose lift never came (the keys were covered
                // mid-press) is over once a new one starts.
                if (pressed != null || spaceGesture != null || accentOptions != null || glideActive) touchCancel()
                activePointer = event.getPointerId(0)
                touchDown(event.x, event.y, event.eventTime)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (activePointer >= 0 && !handOver(event)) return true
                // The key just typed may have put a panel over the keys.
                if (!isShown) return true
                val i = event.actionIndex
                activePointer = event.getPointerId(i)
                touchDown(event.getX(i), event.getY(i), event.eventTime)
            }
            MotionEvent.ACTION_MOVE -> {
                val i = event.findPointerIndex(activePointer)
                if (i >= 0) {
                    // A glide wants every sample the batch holds, not only
                    // the last: the decoder reads the path's shape.
                    if (glideActive || glideEligible()) {
                        for (h in 0 until event.historySize) {
                            touchMove(event.getHistoricalX(i, h), event.getHistoricalY(i, h), event.getHistoricalEventTime(h))
                        }
                    }
                    touchMove(event.getX(i), event.getY(i), event.eventTime)
                }
            }
            MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP -> {
                // A finger that was never followed (it landed mid-glide)
                // types nothing when it lifts.
                val i = event.actionIndex
                if (event.getPointerId(i) == activePointer) {
                    activePointer = -1
                    touchUp(event.getX(i), event.getY(i), event.eventTime)
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                activePointer = -1
                touchCancel()
            }
        }
        return true
    }

    /** A new finger landed while [activePointer] holds a key. That key is
     *  typed now and the new finger is followed instead; true when it is.
     *  A key in the middle of its own gesture keeps the touch: a space
     *  glide, a delete slide or repeat, the accent popup. */
    private fun handOver(event: MotionEvent): Boolean {
        val gliding = spaceGesture?.phase == SpaceGesture.Phase.GLIDING
        val deleting = pressed?.id == "delete" && (deleteWords > 0 || longPressFired)
        if (accentOptions != null || gliding || deleting || glideActive) return false
        val i = event.findPointerIndex(activePointer)
        activePointer = -1
        if (i >= 0) touchUp(event.getX(i), event.getY(i), event.eventTime)
        else touchUp(lastX, downY, event.eventTime)
        return true
    }

    private fun touchDown(x: Float, y: Float, time: Long) {
        val (key, rect) = keyAt(x, y) ?: return
        // A greyed key (the number pad's empty corner, the digits behind the
        // phone pad's symbols) takes no touch at all.
        if (key.disabled) return
        pressed = key
        pressedRect = rect
        downX = x
        downY = y
        lastX = x
        longPressFired = false
        spaceSlidAway = false
        glideDownTime = time
        glideOK = canGlide(key)
        // Click + haptic on DOWN, like Apple/Gboard; a theme's pack has a
        // sound for the space bar, delete and return.
        pressFeedback(when (key.id) { "space", "delete", "return" -> key.id; else -> "letter" })
        if (key.id == "space") {
            val gesture = SpaceGesture(x / density, y / density, time)
            spaceGesture = gesture
            // The same purple ring a glyf key shows, from the first moment
            // (Arpit, 2026-09-30: "the space bar should also have that purple
            // thing on pressing like other glyf keys"); it closes exactly
            // when the AI launches.
            startCharge(rect, SpaceGesture.HOLD_MS)
            handler2.postDelayed({ perform(gesture.holdElapsed()) }, SpaceGesture.HOLD_MS)
            invalidate()
            return
        }
        if (key.id == "delete") {
            // Gboard's delete: one character on the tap, then held it
            // repeats and speeds up; slid left it selects whole words.
            deleteRepeats = 0
            deleteWords = 0
            handler2.postDelayed(object : Runnable {
                override fun run() {
                    if (deleteWords > 0) return
                    longPressFired = true
                    deleteRepeats++
                    listener.onKey("delete", null)
                    handler2.postDelayed(this, if (deleteRepeats > 12) 40L else 80L)
                }
            }, DELETE_REPEAT_DELAY_MS)
            invalidate()
            return
        }
        if (key.id == "return" && returnAction == android.view.inputmethod.EditorInfo.IME_ACTION_SEND) {
            // Return sends here; held, it's a new line in the message
            // (Gboard's hold-enter; 2026-10-08).
            handler2.postDelayed({
                longPressFired = true
                pressFeedback()
                invalidate()
                listener.onKey("newline", null)
            }, BOUND_HOLD_MS + 80)
            invalidate()
            return
        }
        val char = key.char
        // A binding rests while the keys type into Glyf's own fields or a
        // password: the hold is then the letter's own.
        val glyfId = char?.let { bindings[it] }?.takeIf { listener.bindingsLive() }
        val digit = holdDigit(key)
        val accents = if (char == null || kContext.isPad) emptyList()
                      else KeyboardLayout.accents[char].orEmpty()
        when {
            char != null && glyfId != null -> {
                startCharge(rect, BOUND_HOLD_MS)
                handler2.postDelayed({
                    longPressFired = true
                    stopCharge()
                    invalidate()
                    listener.onBoundKeyHeld(char, glyfId)
                }, BOUND_HOLD_MS)
            }
            char != null && accents.isNotEmpty() -> handler2.postDelayed({
                openAccents(char, rect, digit, accents)
            }, DIGIT_HOLD_MS)
            digit != null -> handler2.postDelayed({
                longPressFired = true
                pressFeedback()
                listener.onKey(digit, digit)
                invalidate()
            }, DIGIT_HOLD_MS)
        }
        invalidate()
    }

    private fun touchMove(x: Float, y: Float, time: Long) {
        lastX = x
        if (glideActive) {
            glideMoved(x, y, time)
            return
        }
        // A letter the finger leaves at speed is the start of a word, not a
        // slip off the key: past the threshold the touch glides.
        if (glideEligible() && keyPitchPx > 1f &&
            Math.hypot((x - downX).toDouble(), (y - downY).toDouble()) >= GLIDE_START * keyPitchPx) {
            beginGlide(x, y, time)
            return
        }
        if (accentOptions != null) {
            trackAccent(x)
            return
        }
        if (pressed?.id == "delete") {
            val step = keyPitchPx * 0.8f
            val words = if (keyPitchPx > 1f) ((downX - x - step * 0.5f) / step)
                .toInt().coerceAtLeast(0) else 0
            if (words > 0 || deleteWords > 0) {
                if (words != deleteWords) {
                    if (deleteWords == 0) handler2.removeCallbacksAndMessages(null)
                    deleteWords = words
                    longPressFired = true
                    listener.onDeleteWordsPreview(words)
                }
            }
            return
        }
        val gesture = spaceGesture ?: return
        val rect = pressedRect
        val xDp = x / density
        // Leaving the bar vertically before any swipe or hold is a
        // cancel, like every other key. Once armed or gliding, the
        // whole keyboard is the trackpad.
        if (gesture.isUndecided(time) && rect != null &&
            abs(xDp - gesture.startX) <= SpaceGesture.SWIPE_SLOP &&
            !RectF(rect).apply { inset(-dp(14f), -dp(16f)) }.contains(x, y)) {
            handler2.removeCallbacksAndMessages(null)
            gesture.cancelled()
            spaceGesture = null
            spaceSlidAway = true
            pressed = null; pressedRect = null
            stopCharge()
            invalidate()
            return
        }
        perform(gesture.moved(xDp, y / density, time))
    }

    private fun touchUp(x: Float, y: Float, time: Long) {
        handler2.removeCallbacksAndMessages(null)
        stopCharge()
        if (glideActive) {
            pressed = null; pressedRect = null; spaceGesture = null
            longPressFired = false; spaceSlidAway = false
            glideEnded(x, y, time)
            return
        }
        val gesture = spaceGesture
        val key = pressed
        val rect = pressedRect
        val picked = accentOptions?.getOrNull(accentIndex)
        pressed = null
        pressedRect = null
        spaceGesture = null
        closeAccents()
        invalidate()
        if (picked != null) {
            // The popup's pick, typed as it shows (already in capitals when
            // shifted); where it was touched means nothing to the engine.
            longPressFired = false
            listener.onKey(picked, picked)
            return
        }
        if (key?.id == "delete" && (deleteWords > 0 || longPressFired)) {
            // A slide that came back to nothing deletes nothing.
            if (deleteWords > 0 || deleteRepeats == 0) listener.onDeleteWordsCommit(deleteWords)
            deleteWords = 0
            longPressFired = false
            return
        }
        when {
            gesture != null -> {
                // The lift carries travel no MOVE reported (fast
                // flicks, batched input): apply it before deciding.
                perform(gesture.moved(x / density, y / density, time))
                perform(gesture.ended(time))
            }
            spaceSlidAway -> Unit
            key != null && !longPressFired -> {
                lastTapOffset = if (key.char != null && rect != null && keyPitchPx > 1f)
                    floatArrayOf((downX - rect.centerX()) / keyPitchPx, (downY - rect.centerY()) / keyPitchPx)
                else null
                listener.onKey(key.id, key.char?.let { if (shifted) it.uppercase() else it })
                lastTapOffset = null
            }
        }
        longPressFired = false
        spaceSlidAway = false
    }

    private fun touchCancel() {
        handler2.removeCallbacksAndMessages(null)
        spaceGesture?.let { perform(it.cancelled()) }
        spaceGesture = null
        pressed = null; pressedRect = null; longPressFired = false; spaceSlidAway = false
        if (glideActive) {
            glideActive = false
            glideLit = null
            fadeGlideTrail()
        }
        closeAccents()
        stopCharge()
        invalidate()
    }

    // MARK: glide typing (Arpit, 2026-10-07: "its guesses needs to be perfect too")

    /** The letters' centres in key widths; null off the letter layer. */
    private var glideLayout: GlideDecoder.Layout? = null
    /** Whether the touch that just landed may become a glide. */
    private var glideOK = false
    private var glideActive = false
    private var glideDownTime = 0L
    private val glidePath = ArrayList<GlidePoint>()
    private var glideDecodedAt = -GLIDE_DECODE_MS
    /** The key under a gliding finger, lit without a balloon. */
    private var glideLit: RectF? = null
    /** The ribbon: the finger's last [TRAIL_LIFE_MS], newest last (x, y, ms). */
    private val trailX = ArrayList<Float>()
    private val trailY = ArrayList<Float>()
    private val trailT = ArrayList<Long>()
    private var trailAlpha = 1f
    private var trailFade: android.animation.ValueAnimator? = null
    /** The word floating over the finger, and where the finger was. */
    private var glideWord: String? = null
    private var glideWordX = 0f
    private var glideWordY = 0f
    private val trailPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val glideTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val trailPath = android.graphics.Path()

    /** A letter on the letter layer, with glide typing on and a field that
     *  takes it. Space keeps its own gestures; pads and symbols have none. */
    private fun canGlide(key: Key): Boolean {
        if (glideLayout == null || mode != Mode.LETTERS || kContext.isPad || key.pad) return false
        val c = key.char?.singleOrNull() ?: return false
        if (c !in 'a'..'z') return false
        return listener.glideAllowed()
    }

    /** The finger is still on the letter it landed on, nothing fired yet. */
    private fun glideEligible(): Boolean =
        glideOK && pressed != null && !longPressFired && accentOptions == null && spaceGesture == null

    private fun glidePoint(x: Float, y: Float, time: Long) =
        GlidePoint(x / keyPitchPx, y / keyPitchPx, time / 1000.0)

    private fun beginGlide(x: Float, y: Float, time: Long) {
        // The hold, the accents and a bound key's run are off for this touch.
        handler2.removeCallbacksAndMessages(null)
        stopCharge()
        pressed = null
        pressedRect = null
        glideActive = true
        glidePath.clear()
        glidePath.add(glidePoint(downX, downY, glideDownTime))
        trailFade?.cancel()
        trailFade = null
        trailAlpha = 1f
        trailX.clear(); trailY.clear(); trailT.clear()
        trailX.add(downX); trailY.add(downY); trailT.add(glideDownTime)
        glideWord = null
        glideDecodedAt = -GLIDE_DECODE_MS
        glideMoved(x, y, time)
    }

    private fun glideMoved(x: Float, y: Float, time: Long) {
        glidePath.add(glidePoint(x, y, time))
        // A point on top of the last one would bend the ribbon's edge.
        val n = trailX.size
        if (n > 0 && Math.hypot((x - trailX[n - 1]).toDouble(), (y - trailY[n - 1]).toDouble()) < dp(1.5f)) {
            trailT[n - 1] = time
        } else {
            trailX.add(x); trailY.add(y); trailT.add(time)
        }
        while (trailT.size > 2 && time - trailT[0] > TRAIL_LIFE_MS) {
            trailX.removeAt(0); trailY.removeAt(0); trailT.removeAt(0)
        }
        glideLit = keyAt(x, y)?.takeIf { it.first.char != null }?.second
        glideWordX = x
        glideWordY = y
        // The word so far, worked out a few times a second, not per sample.
        val layout = glideLayout
        if (layout != null && time - glideDecodedAt >= GLIDE_DECODE_MS) {
            glideDecodedAt = time
            glideWord = listener.onGlideMoved(ArrayList(glidePath), layout)
        }
        invalidate()
    }

    private fun glideEnded(x: Float, y: Float, time: Long) {
        glidePath.add(glidePoint(x, y, time))
        glideActive = false
        glideLit = null
        fadeGlideTrail()
        invalidate()
        val layout = glideLayout ?: return
        listener.onGlideEnded(ArrayList(glidePath), layout)
    }

    /** The finger lifted: the ribbon and the word fade together. */
    private fun fadeGlideTrail() {
        trailFade?.cancel()
        trailFade = android.animation.ValueAnimator.ofFloat(1f, 0f).apply {
            duration = 220
            addUpdateListener {
                trailAlpha = it.animatedValue as Float
                invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    if (glideActive || trailFade !== animation) return
                    trailX.clear(); trailY.clear(); trailT.clear()
                    glideWord = null
                    trailFade = null
                    invalidate()
                }
            })
            start()
        }
    }

    /** A tapering ribbon in the accent colour, 7 dp at the finger, and the
     *  word the finger is spelling in a pill above it (iOS GlideTrail). */
    private fun drawGlideTrail(canvas: Canvas) {
        val n = trailX.size
        if (n == 0 || trailAlpha <= 0f) return
        val now = trailT[n - 1]
        val head = dp(7f)
        trailPaint.color = accent
        trailPaint.alpha = (255 * 0.6f * trailAlpha).toInt()
        if (n > 1) {
            trailPath.reset()
            val lx = FloatArray(n); val ly = FloatArray(n); val rx = FloatArray(n); val ry = FloatArray(n)
            for (i in 0 until n) {
                val pi = maxOf(i - 1, 0); val ni = minOf(i + 1, n - 1)
                var dx = trailX[ni] - trailX[pi]; var dy = trailY[ni] - trailY[pi]
                val len = Math.hypot(dx.toDouble(), dy.toDouble()).toFloat()
                if (len < 0.01f) { dx = 1f; dy = 0f } else { dx /= len; dy /= len }
                val age = ((now - trailT[i]).toFloat() / TRAIL_LIFE_MS).coerceIn(0f, 1f)
                val along = i.toFloat() / (n - 1)
                val half = maxOf(dp(0.5f), head / 2f * minOf(along, 1f - age))
                lx[i] = trailX[i] - dy * half; ly[i] = trailY[i] + dx * half
                rx[i] = trailX[i] + dy * half; ry[i] = trailY[i] - dx * half
            }
            trailPath.moveTo(lx[0], ly[0])
            for (i in 1 until n) trailPath.lineTo(lx[i], ly[i])
            for (i in n - 1 downTo 0) trailPath.lineTo(rx[i], ry[i])
            trailPath.close()
            canvas.drawPath(trailPath, trailPaint)
            canvas.drawCircle(trailX[n - 1], trailY[n - 1], head / 2f, trailPaint)
        }
        val word = glideWord
        if (word.isNullOrEmpty()) return
        glideTextPaint.typeface = Glass.font(context, Glass.SEMIBOLD)
        glideTextPaint.textSize = dp(20f)
        glideTextPaint.color = sv?.popupText ?: ink()
        glideTextPaint.alpha = (255 * trailAlpha).toInt()
        val w = maxOf(dp(44f), glideTextPaint.measureText(word) + dp(28f))
        val h = dp(40f)
        val bx = (glideWordX - w / 2f).coerceIn(dp(2f), maxOf(dp(2f), width - dp(2f) - w))
        // 62 above the finger; under the strip's top edge for the top row.
        val by = maxOf(-top.toFloat() + dp(2f), glideWordY - dp(62f) - h / 2f)
        val pill = RectF(bx, by, bx + w, by + h)
        shadowPaint.color = Color.argb((40 * trailAlpha).toInt(), 0, 0, 0)
        canvas.drawRoundRect(RectF(bx - dp(1f), by + dp(1f), bx + w + dp(1f), by + h + dp(4f)), dp(13f), dp(13f), shadowPaint)
        keyPaint.color = sv?.popupFill ?: if (solidLook) palette().key else if (isDark) Color.rgb(107, 107, 112) else Color.WHITE
        keyPaint.alpha = (255 * trailAlpha).toInt()
        canvas.drawRoundRect(pill, dp(12f), dp(12f), keyPaint)
        keyPaint.alpha = 255
        strokePaint.color = hairline()
        strokePaint.strokeWidth = 1f
        canvas.drawRoundRect(pill, dp(12f), dp(12f), strokePaint)
        canvas.drawText(word, pill.centerX(), pill.centerY() + glideTextPaint.textSize * 0.36f, glideTextPaint)
    }

    // MARK: accents (iOS AccentPopup: hold, slide to pick, lift to type)

    private var accentOptions: List<String>? = null
    private var accentIndex = 0
    private var accentBox: RectF? = null
    private var accentCell = 0f
    /** Laid out right to left, so the first option still sits over a key
     *  near the right edge. */
    private var accentReversed = false
    /** Where the finger was when the popup opened: it picks nothing until
     *  it has really moved, so a still hold keeps the first option. */
    private var accentOriginX = 0f
    private var accentMoved = false

    /** Which cell, left to right, option [i] is drawn in. */
    private fun accentSlot(i: Int): Int {
        val n = accentOptions?.size ?: 0
        return if (accentReversed) n - 1 - i else i
    }

    /** The held key's options over it: the letter, then iOS's accents for
     *  it. A top-row letter showing its number offers that number first,
     *  picked unless the finger moves, so a still hold still types it. */
    private fun openAccents(base: String, rect: RectF, digit: String?, accents: List<String>) {
        // Shift makes capitals of the letters, as on iOS.
        fun caps(t: String) = if (shifted && t.length == 1) t.uppercase() else t
        val options = listOfNotNull(digit) + (listOf(base) + accents).map(::caps)
        longPressFired = true
        val n = options.size
        val cell = min(dp(40f), (width - dp(16f)) / n)
        val w = cell * n + dp(8f)
        val h = dp(52f)
        val edge = dp(4f)
        // The first option straight over the key, the rest running away
        // from the nearer edge; squeezed in where neither way fits.
        val rightward = rect.centerX() - cell / 2f - edge
        val leftward = rect.centerX() + cell / 2f + edge - w
        accentReversed = rightward + w > width - edge &&
            (leftward >= edge || rect.centerX() > width / 2f)
        val x = (if (accentReversed) leftward else rightward)
            .coerceIn(edge, maxOf(edge, width - w - edge))
        // Above the key, reaching up over the strip for the top row (the
        // keyboard's own layout lets this view draw there).
        val y = maxOf(-top.toFloat() + dp(2f), rect.top - h - dp(6f))
        accentOptions = options
        accentIndex = 0
        accentCell = cell
        accentBox = RectF(x, y, x + w, y + h)
        accentOriginX = lastX
        accentMoved = false
        pressFeedback()
        invalidate()
    }

    private fun trackAccent(x: Float) {
        val box = accentBox ?: return
        val n = accentOptions?.size ?: return
        if (!accentMoved && abs(x - accentOriginX) < accentCell / 2f) return
        accentMoved = true
        val slot = ((x - box.left - dp(4f)) / accentCell).toInt().coerceIn(0, n - 1)
        val i = if (accentReversed) n - 1 - slot else slot
        if (i != accentIndex) {
            accentIndex = i
            invalidate()
        }
    }

    private fun closeAccents() {
        accentOptions = null
        accentBox = null
        accentIndex = 0
    }

    // MARK: space bar outcomes (SpaceGesture decides, the view performs)

    private fun perform(effects: List<SpaceGesture.Effect>) {
        for (effect in effects) when (effect) {
            SpaceGesture.Effect.BeginGlide -> {
                handler2.removeCallbacksAndMessages(null)
                stopCharge()
                pressed = null
                trackpadLook = true
                thresholdHaptic()
                android.util.Log.d("GlyfKB", "space glide began")
                listener.onCursorGlideBegan()
                invalidate()
            }
            is SpaceGesture.Effect.MoveCursor -> listener.onCursorMove(effect.graphemes)
            SpaceGesture.Effect.EndGlide -> {
                trackpadLook = false
                android.util.Log.d("GlyfKB", "space glide ended")
                listener.onCursorGlideEnded()
                invalidate()
            }
            SpaceGesture.Effect.OpenBar -> {
                stopCharge()
                pressed = null
                thresholdHaptic()
                android.util.Log.d("GlyfKB", "space hold → AI")
                listener.onSpaceHoldOpenBar()
                invalidate()
            }
            SpaceGesture.Effect.TypeSpace -> listener.onKey("space", null)
        }
    }

    private fun startCharge(rect: RectF, durationMs: Long, delayMs: Long = 0) {
        chargeAnimator?.cancel()
        chargeRect = rect
        chargeProgress = 0f
        chargeAnimator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            startDelay = delayMs
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener {
                chargeProgress = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun stopCharge() {
        chargeAnimator?.cancel()
        chargeAnimator = null
        chargeRect = null
    }

    private fun thresholdHaptic() {
        if (!hapticsOn) return
        performHapticFeedback(
            if (android.os.Build.VERSION.SDK_INT >= 34)
                android.view.HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE
            else android.view.HapticFeedbackConstants.LONG_PRESS)
    }

    init {
        // FULL GPU rendering (no software layer): shadows are painted as
        // offset round-rects below — the same crisp 1dp drop iOS uses
        // (keyShadowRadius is 0 there too). Software layers redrew the
        // whole board on the CPU for every key press.
        // Inter (bundled with the Flutter app) ≈ SF metrics — key faces
        // match the iOS keyboard instead of falling back to Roboto.
        interFace(context)?.let { textPaint.typeface = it }
        isHapticFeedbackEnabled = true
    }

    var hapticsOn = true
    var clicksOn = true

    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private val themeSound by lazy { ThemeSound(context.applicationContext) }

    fun pressFeedback(role: String = "letter") {
        if (hapticsOn) {
            performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP)
        }
        if (clicksOn) {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            // A theme's own sound (§4.2): with the ringer on and theme sounds
            // allowed; otherwise, or while its samples load, today's click.
            val pack = skin?.soundPack ?: "system"
            val themed = skinSound && pack != "system" &&
                audio?.ringerMode == android.media.AudioManager.RINGER_MODE_NORMAL &&
                themeSound.let { it.use(pack); it.play(role) }
            if (!themed) audio?.playSoundEffect(android.media.AudioManager.FX_KEYPRESS_STANDARD, 0.6f)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        themeSound.release()
    }

    // MARK: themes (docs/THEMES.md): colours per key class, never a size

    /** The glyph colour the face being drawn uses (drawShift and the rest). */
    private var faceInk = Color.BLACK

    /** Stroke weight for shift, delete, return and emoji (§5.4). */
    private val glyphK get() = when (skin?.glyphStyle) { "light" -> 0.8f; "bold" -> 1.25f; else -> 1f }

    private var skinFaceFor: String? = null
    private var skinFace: android.graphics.Typeface? = null

    /** The key-face font: the theme's, at today's sizes, else Inter. */
    private fun keyFace(): android.graphics.Typeface? {
        val t = skin ?: return interFace(context)
        if (skinFaceFor != t.id) {
            skinFace = ThemeFonts.face(context, t.font)
            skinFaceFor = t.id
        }
        return skinFace ?: interFace(context)
    }

    /** letter, function, space or return (§5.1). A theme's one accent is
     *  its return, so every return wears it (iOS KeyView.isPrimaryReturn). */
    private fun skinClass(key: Key): String = when {
        key.id == "return" -> "return"
        key.id == "space" -> "space"
        key.bare -> "function"
        key.char != null -> "letter"
        else -> "function"
    }

    private fun skinOverride(key: Key, v: KeyboardThemes.Variant) = when (key.id) {
        "shift" -> v.shift
        "delete" -> v.delete
        else -> null
    }

    private fun skinFill(key: Key, v: KeyboardThemes.Variant, pressed: Boolean): Int {
        skinOverride(key, v)?.let { return if (pressed) it.pressed else it.fill }
        val f = when (skinClass(key)) {
            "letter" -> v.letter
            "space" -> v.space
            "return" -> return if (pressed) v.returnPrimary.pressed else v.returnPrimary.fill
            else -> v.function
        }
        return if (pressed) f.pressed else f.fill
    }

    private fun skinInk(key: Key, v: KeyboardThemes.Variant): Int {
        // A pad's capless keys sit on the board: the strip's ink reads there.
        if (key.bare) return v.stripText
        skinOverride(key, v)?.let { return it.glyph }
        return when (skinClass(key)) {
            "letter", "space" -> v.keyText
            "return" -> v.returnPrimary.glyph
            else -> v.functionGlyph
        }
    }

    private val skinRect = RectF()

    /** The theme's edge (1dp down, radius 0) or glow (soft, round the key):
     *  both in the gaps, neither moves the key. */
    private fun drawSkinShadow(canvas: Canvas, rect: RectF, radius: Float, s: KeyboardThemes.Shadow, glows: Boolean) {
        if (s.alpha <= 0f) return
        val dy = dp(s.offsetY.toFloat())
        if (s.radius == 0) {
            if (s.offsetY == 0) return
            shadowPaint.color = withAlpha(s.color, s.alpha)
            skinRect.set(rect.left, rect.top + dy, rect.right, rect.bottom + dy)
            canvas.drawRoundRect(skinRect, radius, radius, shadowPaint)
            return
        }
        if (!glows) return
        for (i in s.radius downTo 1) {
            val grow = dp(i.toFloat())
            shadowPaint.color = withAlpha(s.color, s.alpha * 0.45f * (1f - (i - 1f) / s.radius))
            skinRect.set(rect.left - grow, rect.top - grow + dy, rect.right + grow, rect.bottom + grow + dy)
            canvas.drawRoundRect(skinRect, radius + grow, radius + grow, shadowPaint)
        }
    }

    /** Over a themed key's face: the theme's 1dp border (or, when it has
     *  none, the Borders switch's), stroked inside the key's bounds. */
    private fun drawSkinFace(canvas: Canvas, key: Key, rect: RectF, radius: Float, v: KeyboardThemes.Variant) {
        val cls = skinClass(key)
        val b = v.border
        strokePaint.color = when {
            b != null -> if (cls in b.appliesTo) b.color else return
            keyBorders -> hairline()
            else -> return
        }
        strokePaint.strokeWidth = dp((b?.width ?: 1).toFloat())
        val half = strokePaint.strokeWidth / 2f
        skinRect.set(rect.left + half, rect.top + half, rect.right - half, rect.bottom - half)
        canvas.drawRoundRect(skinRect, radius - half, radius - half, strokePaint)
    }

    // MARK: theme legends (shared/themes/styles.py; tools/theme_mock.py's legendText)

    private val themeFaces by lazy { ThemeFaces(context, density) }
    /** The fill of the face being drawn (its light or dark decides the
     *  hairline of an engraved legend). */
    private var faceFill = Color.WHITE
    /** The legend style for the face being drawn; null is plain ink. */
    private var legendOn: KeyboardThemes.Legend? = null
    private var legendLight = false
    private val legendBounds = android.graphics.Rect()

    private fun setLegend(lg: KeyboardThemes.Legend, fill: Int) {
        legendOn = if (lg.style == "ink") null else lg
        legendLight = ThemeFaces.luminance(fill) > 0.45
    }

    /** What letters and glyphs are ornaments named by: letter, space,
     *  return, shift, delete, or function for the other function keys. */
    private fun ornamentOn(key: Key, cls: String) = when {
        cls == "letter" -> "letter"
        key.id == "space" || key.id == "return" || key.id == "shift" || key.id == "delete" -> key.id
        else -> "function"
    }

    /** The hairline an engraved, letterpress or foil legend sits on: light
     *  under it on a light key, dark over it on a dark one (foil: always
     *  dark, over). 0 when the style has none. */
    private fun hairColor(lg: KeyboardThemes.Legend): Int = when (lg.style) {
        "engraved", "letterpress" -> if (legendLight) Color.argb(191, 255, 255, 255) else Color.argb(153, 0, 0, 0)
        "foil" -> Color.argb(115, 0, 0, 0)
        else -> 0
    }

    private fun hairOffset(lg: KeyboardThemes.Legend): Float =
        if (lg.style != "foil" && legendLight) dp(0.7f) else -dp(0.6f)

    private fun glowColor(lg: KeyboardThemes.Legend, ink: Int): Int {
        val g = lg.glow
        val c = if (g == null || g == "self") ink else try { Color.parseColor(g) } catch (_: Exception) { ink }
        return withAlpha(c, 0.9f)
    }

    /** A legend's text in the theme's style, at today's size and place. */
    private fun legendText(canvas: Canvas, s: String, x: Float, y: Float) {
        val lg = legendOn
        if (lg == null) { canvas.drawText(s, x, y, textPaint); return }
        val ink = textPaint.color
        val hair = hairColor(lg)
        if (hair != 0) {
            textPaint.color = hair
            canvas.drawText(s, x, y + hairOffset(lg), textPaint)
            textPaint.color = ink
        }
        when (lg.style) {
            "letterpress" -> textPaint.setShadowLayer(ThemeFaces.shadowRadius(dp(0.6f)), 0f, 0f, withAlpha(ink, 0.55f))
            "glow" -> textPaint.setShadowLayer(ThemeFaces.shadowRadius(dp(6f)), 0f, 0f, glowColor(lg, ink))
            "foil" -> lg.foil?.let {
                textPaint.getTextBounds(s, 0, s.length, legendBounds)
                textPaint.shader = themeFaces.foil(y + legendBounds.top, y + legendBounds.bottom, it)
            }
        }
        canvas.drawText(s, x, y, textPaint)
        if (lg.style == "glow") canvas.drawText(s, x, y, textPaint)
        textPaint.clearShadowLayer()
        textPaint.shader = null
    }

    /** Shift, delete, return and the smiley in the theme's legend: [draw]
     *  strokes in [faceInk] with [glyphPaint]. */
    private inline fun glyphLegend(canvas: Canvas, rect: RectF, draw: () -> Unit) {
        val lg = legendOn
        if (lg == null) { draw(); return }
        val ink = faceInk
        val hair = hairColor(lg)
        if (hair != 0) {
            faceInk = hair
            canvas.save()
            canvas.translate(0f, hairOffset(lg))
            draw()
            canvas.restore()
            faceInk = ink
        }
        when (lg.style) {
            "letterpress" -> glyphPaint.setShadowLayer(ThemeFaces.shadowRadius(dp(0.6f)), 0f, 0f, withAlpha(ink, 0.55f))
            "glow" -> glyphPaint.setShadowLayer(ThemeFaces.shadowRadius(dp(6f)), 0f, 0f, glowColor(lg, ink))
            "foil" -> lg.foil?.let {
                glyphPaint.shader = themeFaces.foil(rect.centerY() - dp(8f), rect.centerY() + dp(8f), it)
            }
        }
        draw()
        if (lg.style == "glow") draw()
        glyphPaint.clearShadowLayer()
        glyphPaint.shader = null
    }
}
