package com.demo.glyf.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
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
    }

    var mode = Mode.LETTERS
    var kContext = KContext.TEXT
    var shifted = false
    var numberRow = false
    var isDark = false
    var keyTheme = "glass"
    var themeBg = ""          // "" | color:#RRGGBB | grad:<id>
    var keyBorders = false
    var themeDim = 0f
    var bindings: Map<String, String> = emptyMap()

    /// Colored/gradient backdrop = dark chrome (white ink), like iOS.
    private val chromeDark get() = isDark || themeBg.isNotEmpty()

    companion object {
        /** §6.5: a bound LETTER fires at 320ms; the space bar waits longer so
         *  a glide can still start (SpaceGesture.HOLD_MS). */
        const val BOUND_HOLD_MS = 320L

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

    private fun keyFill(isPressed: Boolean): Int = when {
        (keyTheme == "glass" || themeBg.isNotEmpty()) && chromeDark ->
            if (isPressed) Color.argb(102, 255, 255, 255)
            else Color.argb(if (themeBg.isNotEmpty()) 61 else 36, 255, 255, 255)
        keyTheme == "glass" ->
            if (isPressed) Color.argb(235, 255, 255, 255) else Color.argb(148, 255, 255, 255)
        chromeDark ->
            if (isPressed) Color.rgb(140, 140, 148) else Color.rgb(107, 107, 112)
        else ->
            if (isPressed) Color.rgb(237, 237, 240) else Color.WHITE
    }

    private fun ink(): Int = if (chromeDark) Color.WHITE else Color.rgb(18, 18, 20)
    private fun hairline(): Int = when {
        keyBorders && chromeDark -> Color.argb(120, 255, 255, 255)
        keyBorders -> Color.argb(78, 0, 0, 0)
        chromeDark -> Color.argb(26, 255, 255, 255)
        else -> Color.argb(20, 0, 0, 0)
    }

    fun backdrop(): Int =
        if (isDark) Color.rgb(28, 28, 30) else Color.rgb(209, 212, 217)

    // MARK: measurement + drawing

    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val w = MeasureSpec.getSize(widthSpec)
        val rowsH = dp(if (numberRow && mode == Mode.LETTERS) 216f + 42f else 216f)
        setMeasuredDimension(w, rowsH.toInt())
    }

    override fun onDraw(canvas: Canvas) {
        keyRects.clear()
        if (rows.isEmpty()) rebuild()
        val hGap = dp(6f)
        val vGap = dp(10f)
        val side = dp(3f)
        val availW = width - side * 2
        val isPad = kContext.isPad
        val unitW = if (isPad) (availW - 2 * hGap - dp(80f)) / 3f
                    else (availW - 9 * hGap) / 10f
        val rowH = height / rows.size.toFloat()
        val keyH = min(rowH - vGap, if (isPad) dp(52f) else Float.MAX_VALUE)
        val radius = dp(9.5f)
        keyPitchPx = unitW + hGap
        rowPitchPx = rowH

        rows.forEachIndexed { r, row ->
            val fixedUnits = row.filter { it.units > 0 }.sumOf { it.units.toDouble() }.toFloat()
            val gaps = (row.size - 1) * hGap
            val hasFlex = row.any { it.units < 0 }
            val fixedWidth = fixedUnits * unitW + gaps
            val flexW = maxOf(unitW, availW - fixedWidth)
            val rowW = if (hasFlex) availW else fixedWidth
            var x = side + (availW - rowW) / 2f
            val y = r * rowH + vGap / 2f

            for (key in row) {
                val w = if (key.units < 0) flexW else key.units * unitW
                val rect = RectF(x, y, x + w, y + keyH)
                keyRects.add(key to rect)

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
                    shadowPaint.color = Color.argb(if (keyTheme == "glass") 26 else 56, 0, 0, 0)
                    val drop = RectF(rect.left, rect.top + dp(1f),
                        rect.right, rect.bottom + dp(1f))
                    canvas.drawRoundRect(drop, radius, radius, shadowPaint)
                    keyPaint.color = keyFill(isPressed)
                }
                canvas.drawRoundRect(rect, radius, radius, keyPaint)
                strokePaint.color = hairline()
                strokePaint.strokeWidth = if (keyBorders) dp(1.1f) else 1f
                canvas.drawRoundRect(rect, radius, radius, strokePaint)

                if (!trackpadLook) {
                    drawFace(canvas, key, rect)
                    key.char?.let { c ->
                        if (bindings.containsKey(c)) {
                            canvas.drawCircle(rect.right - dp(8f), rect.top + dp(8f), dp(2.5f), dotPaint)
                        }
                    }
                }
                x += w + hGap
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
            keyPaint.color = if (isDark) Color.rgb(107, 107, 112) else Color.WHITE
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
                textPaint.textSize = dp(21f)
                display(key)
            }
            key.id == "space" -> {
                // The brand watermark must read on EVERY theme (§5) — keyed
                // to chrome darkness, not just system dark mode.
                textPaint.textSize = dp(12f)
                textPaint.color = if (chromeDark) Color.argb(150, 255, 255, 255)
                                  else Color.argb(105, 40, 40, 46)
                "glyf"
            }
            key.id == "delete" -> { textPaint.textSize = dp(16f); "⌫" }
            key.id == "emojikey" -> { drawSmiley(canvas, rect); return }
            key.id.startsWith("mode:") -> {
                textPaint.textSize = dp(13f)
                key.id.removePrefix("mode:")
            }
            else -> ""
        }
        canvas.drawText(label, rect.centerX(),
            rect.centerY() + textPaint.textSize * 0.36f, textPaint)
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
                val char = hit.first.char
                val glyfId = char?.let { bindings[it] }
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
