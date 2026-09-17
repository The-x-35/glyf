package com.demo.glyf.ime

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
    }

    var mode = Mode.LETTERS
    var kContext = KContext.TEXT
    var shifted = false
    var numberRow = false
    var isDark = false
    var keyTheme = "site"
    var themeBg = ""          // "" | color:#RRGGBB | grad:<id>
    var keyBorders = false
    var themeDim = 0f
    var bindings: Map<String, String> = emptyMap()

    /** Solid keys with a hard bottom edge: the website look and every colour
     *  theme, which are the same keyboard in another colour (mirrors
     *  Glass.solidLook on iOS). */
    private val solidLook get() = keyTheme == "site" || themeBg.isNotEmpty()

    /** Chrome darkness follows the ink the palette chose. */
    private val chromeDark get() = if (solidLook) palette().darkChrome else isDark

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
            /** Every colour from one board colour: colour themes. */
            fun fromBoard(board: Int): KeyPalette {
                val light = luminance(board) > 0.34f
                val key = if (light) Color.WHITE else blend(board, Color.WHITE, 0.185f)
                val fn = if (light) blend(board, Color.BLACK, 0.14f)
                         else blend(board, Color.WHITE, 0.07f)
                val ink = if (light) tinted(board, 0.10f, 0.12f) else tinted(board, 0.04f, 0.965f)
                return KeyPalette(
                    board = board,
                    key = key,
                    keyPressed = if (light) blend(key, board, 0.55f) else blend(key, Color.WHITE, 0.11f),
                    fn = fn,
                    fnPressed = if (light) blend(fn, Color.WHITE, 0.18f) else blend(fn, Color.WHITE, 0.06f),
                    ink = ink,
                    inkSoft = blend(ink, board, if (light) 0.42f else 0.40f),
                    edge = Color.argb(if (light) 61 else 179, 0, 0, 0),
                    card = if (light) Color.WHITE else blend(board, Color.WHITE, 0.065f),
                    darkChrome = !light,
                )
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
        val cacheKey = "$themeBg|$isDark|$keyTheme|$themeDim"
        paletteCache?.let { if (it.first == cacheKey) return it.second }
        // The default look on Android 12+ is Gboard's: the phone's own colours.
        // Picked colour themes are still built from their seed.
        val made = if (keyTheme == "site" && themeBg.isEmpty() && Build.VERSION.SDK_INT >= 31)
            KeyPalette.gboardDefault(context, isDark)
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

        /** Row height in dp, measured off Gboard. */
        const val ROW_PITCH = 59f

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

    /** Backdrop drawable for the whole IME when a theme is painted. */
    fun themedBackdrop(): android.graphics.drawable.Drawable? {
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
        requestLayout()
        invalidate()
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

    fun backdrop(): Int =
        if (solidLook) palette().board
        else if (isDark) Color.rgb(28, 28, 30) else Color.rgb(209, 212, 217)

    // MARK: measurement + drawing

    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val w = MeasureSpec.getSize(widthSpec)
        // Gboard's rows are 59dp, not the iPhone's 54 — measured on a 427dp
        // emulator: four rows of keys are 236dp there.
        val rowsH = dp(if (numberRow && mode == Mode.LETTERS) ROW_PITCH * 5 else ROW_PITCH * 4)
        setMeasuredDimension(w, rowsH.toInt())
    }

    override fun onDraw(canvas: Canvas) {
        keyRects.clear()
        if (rows.isEmpty()) rebuild()
        val hGap = dp(6f)
        val vGap = dp(12f)
        val side = dp(5f)   // Gboard's margin
        val availW = width - side * 2
        val isPad = kContext.isPad
        // Ten columns across the row, exactly as Gboard lays them out: a key
        // is its share of the pitch minus one gap, so 1.5-column keys come
        // out 57dp wide instead of 54.
        val columns = if (isPad) 3f else 10f
        val padInset = if (isPad) dp(80f) else 0f
        val pitch = (availW - padInset + hGap) / columns
        val unitW = pitch - hGap
        val rowH = height / rows.size.toFloat()
        val keyH = min(rowH - vGap, if (isPad) dp(52f) else Float.MAX_VALUE)
        // Gboard's keys: 6dp corners, and ?123 and enter as pills.
        val radius = dp(6f)
        keyPitchPx = pitch
        rowPitchPx = rowH

        rows.forEachIndexed { r, row ->
            val fixedUnits = row.filter { it.units > 0 }.sumOf { it.units.toDouble() }.toFloat()
            val hasFlex = row.any { it.units < 0 }
            val flexUnits = maxOf(1f, columns - fixedUnits)
            val rowUnits = if (hasFlex) columns else fixedUnits
            val rowW = rowUnits * pitch - hGap
            var x = side + (availW - rowW) / 2f
            val y = r * rowH + vGap / 2f

            for (key in row) {
                val units = if (key.units < 0) flexUnits else key.units
                val w = units * pitch - hGap
                val rect = RectF(x, y, x + w, y + keyH)
                keyRects.add(key to rect)
                val lastRow = r == rows.lastIndex && !isPad
                val pill = lastRow && (key.id == "return" || key.id.startsWith("mode:"))
                val radius = if (pill) keyH / 2f else radius

                val isPressed = pressed?.id == key.id && pressedRect == rect
                val bound = key.char != null && bindings.containsKey(key.char)
                val glowKey = keyTheme == "glow" && bound && !isPressed && themeBg.isEmpty()
                // GPU-painted shadow: offset round-rect (the crisp 1dp iOS
                // drop). Glow keys get a soft accent halo from two stacked
                // translucent rects — no blur layers, no CPU rendering.
                if (glowKey) {
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
                } else {
                    // The website draws a hard 2dp edge under each key, not a
                    // blur: an offset round-rect in the palette's edge colour.
                    // Gboard's roles: the emoji key wears the letter colour,
                    // the bottom row's punctuation wears the function colour.
                    val fn = solidLook && when {
                        key.id == "emojikey" || key.id == "space" -> false
                        key.char != null -> lastRow
                        else -> true
                    }
                    val lift = if (solidLook) dp(2f) else dp(1f)
                    shadowPaint.color =
                        if (solidLook) palette().edge
                        else Color.argb(if (keyTheme == "glass") 26 else 56, 0, 0, 0)
                    val drop = RectF(rect.left, rect.top + lift,
                        rect.right, rect.bottom + lift)
                    canvas.drawRoundRect(drop, radius, radius, shadowPaint)
                    keyPaint.color = keyFill(isPressed, fn)
                }
                canvas.drawRoundRect(rect, radius, radius, keyPaint)
                if (keyBorders || !solidLook) {
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
                x += units * pitch
            }
        }

        chargeRect?.let { rect ->
            // 1.18× → 1× over the hold, fading in fast; stays closed once armed.
            val scale = 1.18f - 0.18f * chargeProgress
            val hw = rect.width() * scale / 2f
            val hh = rect.height() * scale / 2f
            ringPaint.strokeWidth = dp(2f)
            ringPaint.alpha = (255 * min(1f, chargeProgress * 4f)).toInt()
            canvas.drawRoundRect(
                RectF(rect.centerX() - hw, rect.centerY() - hh, rect.centerX() + hw, rect.centerY() + hh),
                radius * scale, radius * scale, ringPaint)
        }

        // Press preview balloon (chars only).
        val p = pressed
        val pr = pressedRect
        if (p?.char != null && pr != null && !longPressFired && !trackpadLook) {
            val bw = pr.width() * 1.55f
            val bh = pr.height() * 1.3f
            var bx = pr.centerX() - bw / 2
            bx = bx.coerceIn(dp(2f), width - bw - dp(2f))
            val by = (pr.top - bh - dp(4f)).coerceAtLeast(-dp(20f))
            val balloon = RectF(bx, by, bx + bw, by + bh)
            // Painted two-layer drop (GPU) instead of a blur shadow layer.
            shadowPaint.color = Color.argb(28, 0, 0, 0)
            canvas.drawRoundRect(RectF(bx - dp(2f), by, bx + bw + dp(2f), by + bh + dp(5f)),
                dp(14f), dp(14f), shadowPaint)
            shadowPaint.color = Color.argb(46, 0, 0, 0)
            canvas.drawRoundRect(RectF(bx, by + dp(2f), bx + bw, by + bh + dp(3f)),
                dp(12f), dp(12f), shadowPaint)
            keyPaint.color = if (solidLook) palette().key
                             else if (isDark) Color.rgb(107, 107, 112) else Color.WHITE
            canvas.drawRoundRect(balloon, dp(12f), dp(12f), keyPaint)
            textPaint.color = ink()
            textPaint.textSize = dp(30f)
            canvas.drawText(display(p), balloon.centerX(),
                balloon.centerY() + dp(10f), textPaint)
        }
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

    private fun drawFace(canvas: Canvas, key: Key, rect: RectF) {
        textPaint.color = ink()
        when (key.id) {
            "shift" -> { drawShift(canvas, rect); return }
            "return" -> { drawReturn(canvas, rect); return }
        }
        val label: String = when {
            key.char != null -> {
                // Same optical size as the iOS build (a letter fills about
                // half the key's height), so the two keyboards are twins.
                textPaint.textSize = dp(23f)
                display(key)
            }
            key.id == "space" -> {
                // The brand watermark must read on EVERY theme (§5) — keyed
                // to chrome darkness, not just system dark mode.
                textPaint.textSize = dp(13.5f)
                textPaint.color = if (chromeDark) Color.argb(150, 255, 255, 255)
                                  else Color.argb(105, 40, 40, 46)
                "glyf"
            }
            key.id == "delete" -> { textPaint.textSize = dp(18f); "⌫" }
            key.id == "emojikey" -> { drawSmiley(canvas, rect); return }
            key.id.startsWith("mode:") -> {
                textPaint.textSize = dp(15f)
                key.id.removePrefix("mode:")
            }
            else -> ""
        }
        canvas.drawText(label, rect.centerX(),
            rect.centerY() + textPaint.textSize * 0.36f, textPaint)
        // Gboard's number hints on the top row: the digit a hold types. Keys
        // that hold a glyf show their dot instead, and keep their hold.
        val digit = holdDigit(key)
        if (digit != null) {
            val size = textPaint.textSize
            textPaint.textSize = dp(10.5f)
            textPaint.color = Color.argb(150, Color.red(ink()), Color.green(ink()), Color.blue(ink()))
            canvas.drawText(digit, rect.right - dp(7f), rect.top + dp(13f), textPaint)
            textPaint.textSize = size
        }
    }

    /** The digit a held top-row letter types, or null. */
    private fun holdDigit(key: Key): String? {
        if (mode != Mode.LETTERS || numberRow) return null
        val c = key.char ?: return null
        if (bindings.containsKey(c)) return null
        val i = "qwertyuiop".indexOf(c)
        return if (i < 0) null else ((i + 1) % 10).toString()
    }

    /** Outline smiley — the emoji glyph can't tint with themes. */
    private fun drawSmiley(canvas: Canvas, rect: RectF) {
        glyphPaint.color = ink()
        glyphPaint.style = Paint.Style.STROKE
        glyphPaint.strokeWidth = dp(1.5f)
        val cx = rect.centerX(); val cy = rect.centerY()
        canvas.drawCircle(cx, cy, dp(7f), glyphPaint)
        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ink() }
        canvas.drawCircle(cx - dp(2.6f), cy - dp(2f), dp(1f), dot)
        canvas.drawCircle(cx + dp(2.6f), cy - dp(2f), dp(1f), dot)
        canvas.drawArc(cx - dp(3.6f), cy - dp(1.5f), cx + dp(3.6f), cy + dp(4.4f),
            25f, 130f, false, glyphPaint)
    }

    /** Apple-weight shift arrow: outline normally, filled while shifted. */
    private fun drawShift(canvas: Canvas, rect: RectF) {
        val cx = rect.centerX(); val cy = rect.centerY()
        val w = dp(9f); val stem = dp(4f)
        val path = android.graphics.Path().apply {
            moveTo(cx, cy - dp(7f))            // apex
            lineTo(cx + w, cy + dp(1f))
            lineTo(cx + stem, cy + dp(1f))
            lineTo(cx + stem, cy + dp(7f))
            lineTo(cx - stem, cy + dp(7f))
            lineTo(cx - stem, cy + dp(1f))
            lineTo(cx - w, cy + dp(1f))
            close()
        }
        glyphPaint.color = ink()
        glyphPaint.strokeWidth = dp(1.4f)
        glyphPaint.style = if (shifted) Paint.Style.FILL_AND_STROKE else Paint.Style.STROKE
        canvas.drawPath(path, glyphPaint)
    }

    /** Return: down-then-left hooked arrow, stroke-drawn. */
    private fun drawReturn(canvas: Canvas, rect: RectF) {
        val cx = rect.centerX(); val cy = rect.centerY()
        glyphPaint.color = ink()
        glyphPaint.style = Paint.Style.STROKE
        glyphPaint.strokeWidth = dp(1.7f)
        val path = android.graphics.Path().apply {
            moveTo(cx + dp(6f), cy - dp(6f))
            lineTo(cx + dp(6f), cy + dp(3f))
            lineTo(cx - dp(6f), cy + dp(3f))
        }
        canvas.drawPath(path, glyphPaint)
        val head = android.graphics.Path().apply {
            moveTo(cx - dp(2.5f), cy - dp(0.5f))
            lineTo(cx - dp(6f), cy + dp(3f))
            lineTo(cx - dp(2.5f), cy + dp(6.5f))
        }
        canvas.drawPath(head, glyphPaint)
    }

    // MARK: touch

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val hit = keyRects.firstOrNull { it.second.contains(event.x, event.y) }
                    ?: return true
                pressed = hit.first
                pressedRect = hit.second
                downX = event.x
                downY = event.y
                longPressFired = false
                spaceSlidAway = false
                pressFeedback() // click + haptic on DOWN, like Apple/Gboard
                if (hit.first.id == "space") {
                    val gesture = SpaceGesture(event.x / density, event.y / density, event.eventTime)
                    spaceGesture = gesture
                    // Held back 100ms so an ordinary tap never flashes the ring;
                    // it closes exactly when the AI launches.
                    startCharge(hit.second, SpaceGesture.HOLD_MS - 100, delayMs = 100)
                    handler2.postDelayed({ perform(gesture.holdElapsed()) }, SpaceGesture.HOLD_MS)
                    invalidate()
                    return true
                }
                if (hit.first.id == "delete") {
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
                    return true
                }
                val char = hit.first.char
                val glyfId = char?.let { bindings[it] }
                val digit = holdDigit(hit.first)
                if (digit != null) {
                    handler2.postDelayed({
                        longPressFired = true
                        pressFeedback()
                        listener.onKey(digit, digit)
                        invalidate()
                    }, DIGIT_HOLD_MS)
                }
                if (glyfId != null) {
                    startCharge(hit.second, BOUND_HOLD_MS)
                    handler2.postDelayed({
                        longPressFired = true
                        stopCharge()
                        invalidate()
                        listener.onBoundKeyHeld(char, glyfId)
                    }, BOUND_HOLD_MS)
                }
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                if (pressed?.id == "delete") {
                    val step = keyPitchPx * 0.8f
                    val words = if (keyPitchPx > 1f) ((downX - event.x - step * 0.5f) / step)
                        .toInt().coerceAtLeast(0) else 0
                    if (words > 0 || deleteWords > 0) {
                        if (words != deleteWords) {
                            if (deleteWords == 0) handler2.removeCallbacksAndMessages(null)
                            deleteWords = words
                            longPressFired = true
                            listener.onDeleteWordsPreview(words)
                        }
                    }
                    return true
                }
                val gesture = spaceGesture ?: return true
                val rect = pressedRect
                val xDp = event.x / density
                // Leaving the bar vertically before any swipe or hold is a
                // cancel, like every other key. Once armed or gliding, the
                // whole keyboard is the trackpad.
                if (gesture.isUndecided(event.eventTime) && rect != null &&
                    abs(xDp - gesture.startX) <= SpaceGesture.SWIPE_SLOP &&
                    !RectF(rect).apply { inset(-dp(14f), -dp(16f)) }.contains(event.x, event.y)) {
                    handler2.removeCallbacksAndMessages(null)
                    gesture.cancelled()
                    spaceGesture = null
                    spaceSlidAway = true
                    pressed = null; pressedRect = null
                    stopCharge()
                    invalidate()
                    return true
                }
                perform(gesture.moved(xDp, event.y / density, event.eventTime))
            }
            MotionEvent.ACTION_UP -> {
                handler2.removeCallbacksAndMessages(null)
                stopCharge()
                val gesture = spaceGesture
                val key = pressed
                pressed = null
                pressedRect = null
                spaceGesture = null
                invalidate()
                if (key?.id == "delete" && (deleteWords > 0 || longPressFired)) {
                    // A slide that came back to nothing deletes nothing.
                    if (deleteWords > 0 || deleteRepeats == 0) listener.onDeleteWordsCommit(deleteWords)
                    deleteWords = 0
                    longPressFired = false
                    return true
                }
                when {
                    gesture != null -> {
                        // The lift carries travel no MOVE reported (fast
                        // flicks, batched input): apply it before deciding.
                        perform(gesture.moved(event.x / density, event.y / density, event.eventTime))
                        perform(gesture.ended(event.eventTime))
                    }
                    spaceSlidAway -> Unit
                    key != null && !longPressFired -> {
                        val rect = keyRects.firstOrNull { it.first.id == key.id }?.second
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
            MotionEvent.ACTION_CANCEL -> {
                handler2.removeCallbacksAndMessages(null)
                spaceGesture?.let { perform(it.cancelled()) }
                spaceGesture = null
                pressed = null; pressedRect = null; longPressFired = false; spaceSlidAway = false
                stopCharge()
                invalidate()
            }
        }
        return true
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

    fun pressFeedback() {
        if (hapticsOn) {
            performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP)
        }
        if (clicksOn) {
            (context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager)
                ?.playSoundEffect(android.media.AudioManager.FX_KEYPRESS_STANDARD, 0.6f)
        }
    }
}
