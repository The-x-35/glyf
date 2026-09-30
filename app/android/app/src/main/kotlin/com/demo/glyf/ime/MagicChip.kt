package com.demo.glyf.ime

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SweepGradient
import android.view.animation.AnimationUtils
import android.view.animation.LinearInterpolator
import android.widget.LinearLayout
import kotlin.math.abs
import kotlin.math.pow

/**
 * The strip's chip, dressed as magic (user, 2026-09-30: "i need the strip to
 * have a colourful glowy border so it feels like its magic, all types of
 * strips"): a 1.5dp border and a soft glow around it, one sweep of violet,
 * magenta, pink, amber and cyan that turns once every 4 s while the chip
 * shows, the glow fading in as the chip arrives. With animations off the
 * colours stand still. Every chip the strip shows is one of these (a sum,
 * money, a saved detail, the model's ask, a paste, a plan, a booking, Send,
 * Buy); word suggestions stay plain. iOS twin: the strip chip's border.
 *
 * One animator turns the shader's matrix and redraws this chip alone, 30
 * times a second (a slow turn looks as smooth as at 60); nothing is made per
 * frame. The glow is fainter strokes of the same sweep, each wider than the
 * last (a blur would need a software layer), drawn outside the chip only:
 * its parent must not clip children or padding.
 */
class MagicChip(ctx: Context, dark: Boolean) : LinearLayout(ctx) {

    private val density = resources.displayMetrics.density
    private val radius = 12f * density
    private val box = RectF()
    private val inner = RectF()
    private val spin = Matrix()
    private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = BORDER * density
    }
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private var sweep: SweepGradient? = null

    /** The card is glass (Arpit, 2026-09-30: "we should make the suggestion
     *  strip glassy"), as iOS's: a frosted face the sheet shows through,
     *  Glyf's colours drifting faintly through it, a sheen over its top half
     *  and a bright rim just inside the border, where light catches the edge
     *  of a pane. The colours inside run in a band, not round the middle as
     *  the border's do: turned round a point, they pinched to a spot. */
    private val face = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Glass.white(if (dark) 0.10f else 0.55f)
    }
    private val facePath = Path()
    private val wash = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        alpha = ((if (dark) 0.14f else 0.10f) * 255).toInt()
    }
    private val washPath = Path()
    private val drift = Matrix()
    /** One run of the colours through the card: half as long again as it. */
    private var washPeriod = 1f
    private val sheen = Paint(Paint.ANTI_ALIAS_FLAG)
    private val sheenPath = Path()
    private val sheenTop = Glass.white(if (dark) 0.12f else 0.6f)
    private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = density
    }
    private val rimBox = RectF()
    private val rimTop = Glass.white(if (dark) 0.32f else 0.95f)
    private val rimFoot = Glass.white(if (dark) 0.05f else 0.3f)

    /** The glow's strokes, innermost first, as on iOS: each reaches a step
     *  further out and is fainter, so where they overlap the glow falls off
     *  with the square of the distance, to nothing at the spread, from its
     *  strength at the edge (40% on a light board, 55% on a dark one). */
    private val ringAlphas = FloatArray(RINGS).also { a ->
        val strength = if (dark) 0.55f else 0.40f
        var through = 1f   // what the wider, outer strokes already leave clear
        for (k in RINGS - 1 downTo 0) {
            val seen = strength * 0.85f * (1f - (k + 0.5f) / RINGS).pow(2)
            a[k] = 1f - (1f - seen) / through
            through *= 1f - a[k]
        }
    }

    /** Degrees the colours have turned (and had at the last redraw), how far
     *  the colours inside have drifted (a share of one run), and how far the
     *  glow has come in. */
    private var turn = 0f
    private var drawnTurn = 0f
    private var flow = 0f
    private var flowSince = 0L
    private var shown = 0f
    private var since = 0L
    private var counted = false

    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = TURN_MS
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            ticks++
            turn = it.animatedFraction * 360f
            val now = AnimationUtils.currentAnimationTimeMillis()
            // One run to the left every 6 s, and round again.
            flow = ((now - flowSince) % FLOW_MS) / FLOW_MS.toFloat()
            val t = ((now - since) / FADE_MS).coerceIn(0f, 1f)
            val fading = t < 1f || shown < 1f
            shown = 1f - (1f - t) * (1f - t)   // easing out, as iOS's fade
            val moved = abs(turn - drawnTurn)
            if (!fading && moved < STEP && moved < 360f - STEP) return@addUpdateListener
            drawnTurn = turn
            spinShader()
            invalidate()
        }
    }

    init {
        setWillNotDraw(false)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        box.set(0f, 0f, w.toFloat(), h.toFloat())
        val half = BORDER * density / 2
        inner.set(half, half, w - half, h - half)
        sweep = SweepGradient(w / 2f, h / 2f, COLORS, null).also {
            border.shader = it
            glow.shader = it
        }
        fun inside(path: Path, inset: Float) {
            path.reset()
            val r = maxOf(0f, radius - inset)
            path.addRoundRect(RectF(inset, inset, w - inset, h - inset), r, r, Path.Direction.CW)
        }
        // The face 1dp in, under the border; the wash and the sheen too, so
        // their clipped edges stay under the border's colours; the rim's 1dp
        // line just inside the border.
        inside(facePath, density)
        inside(washPath, density)
        inside(sheenPath, density)
        val rimInset = (BORDER + 0.5f) * density
        rimBox.set(rimInset, rimInset, w - rimInset, h - rimInset)
        washPeriod = maxOf(1f, Math.round(w * 1.5f).toFloat())
        // One run of the colours, repeating: sliding by a run loops.
        wash.shader = LinearGradient(0f, 0f, washPeriod, 0f, COLORS, null, Shader.TileMode.REPEAT)
        sheen.shader = LinearGradient(0f, 0f, 0f, h * 0.6f, sheenTop, Glass.white(0f), Shader.TileMode.CLAMP)
        rim.shader = LinearGradient(0f, rimInset, 0f, h - rimInset, rimTop, rimFoot, Shader.TileMode.CLAMP)
        spinShader()
    }

    /** The sweep, turned about the chip's middle. It starts at twelve
     *  o'clock, as iOS's conic gradient does (Android's starts at three).
     *  The colours inside slide left along their band. */
    private fun spinShader() {
        val s = sweep ?: return
        spin.setRotate(turn - 90f, width / 2f, height / 2f)
        s.setLocalMatrix(spin)
        drift.setTranslate(-flow * washPeriod, 0f)
        wash.shader?.setLocalMatrix(drift)
    }

    override fun onDraw(c: Canvas) {
        drawn++
        if (sweep != null && shown > 0f) {
            // The glow, outside the chip only (the face is glass: a glow
            // under it would show through as a band inside the edge): rings
            // of the sweep, each from half a dp under the border out to its
            // reach, the widest the faintest.
            for (k in 0 until RINGS) {
                val reach = SPREAD * density * (k + 1) / RINGS
                val centre = (reach - 0.5f * density) / 2f
                glow.strokeWidth = reach + 0.5f * density
                glow.alpha = (255 * ringAlphas[k] * shown).toInt()
                c.drawRoundRect(box.left - centre, box.top - centre, box.right + centre, box.bottom + centre,
                    radius + centre, radius + centre, glow)
            }
        }
        // Face, wash, sheen, rim, then the border over their edge.
        c.drawPath(facePath, face)
        c.save()
        c.clipPath(washPath)
        c.drawRect(box, wash)
        c.restore()
        c.save()
        c.clipPath(sheenPath)
        c.drawRect(box, sheen)
        c.restore()
        val rr = maxOf(0f, radius - (BORDER + 0.5f) * density)
        c.drawRoundRect(rimBox, rr, rr, rim)
        if (sweep != null) {
            val r = radius - BORDER * density / 2
            c.drawRoundRect(inner, r, r, border)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        play()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        count(false)
        super.onDetachedFromWindow()
    }

    /** The strip hidden, the keyboard gone: the colours rest until back. */
    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        if (isVisible) play() else rest()
    }

    private fun play() {
        if (!isAttachedToWindow) return
        if (!ValueAnimator.areAnimatorsEnabled()) {
            // Animations off: the colours stand still and the glow is simply there.
            animator.cancel()
            count(false)
            turn = 0f
            flow = 0f
            shown = 1f
            spinShader()
            invalidate()
            return
        }
        // The fade is the chip's arrival, not every return to view.
        if (since == 0L) since = AnimationUtils.currentAnimationTimeMillis()
        if (flowSince == 0L) flowSince = since
        when {
            animator.isPaused -> animator.resume()
            !animator.isStarted -> animator.start()
        }
        count(true)
    }

    private fun rest() {
        if (animator.isStarted) animator.pause()
        count(false)
    }

    private fun count(on: Boolean) {
        if (on == counted) return
        counted = on
        turning += if (on) 1 else -1
    }

    companion object {
        /** The border's width and the glow's reach, in dp. */
        private const val BORDER = 1.5f
        const val SPREAD = 6f
        /** Strokes that make the glow (iOS's six bands). */
        private const val RINGS = 6
        private const val TURN_MS = 4000L
        /** One run of the colours inside drifts past in this long. */
        private const val FLOW_MS = 6000L
        private const val FADE_MS = 250f
        /** Degrees turned between redraws: 30 a second. */
        private const val STEP = 360f / (TURN_MS / 1000f * 30f)
        private val COLORS = intArrayOf(
            Color.rgb(0x7C, 0x5C, 0xFF), Color.rgb(0xD3, 0x5C, 0xFF), Color.rgb(0xFF, 0x5C, 0x8A),
            Color.rgb(0xFF, 0xB5, 0x47), Color.rgb(0x3C, 0xC8, 0xFF), Color.rgb(0x7C, 0x5C, 0xFF))

        /** Chips whose colours are turning right now (the scenarios check
         *  they all stop when the keyboard goes). */
        var turning = 0
            private set
        /** Animator frames and redraws so far, all chips (the scenarios
         *  check the colours turn about 30 times a second). */
        var ticks = 0L
            private set
        var drawn = 0L
            private set
    }
}
