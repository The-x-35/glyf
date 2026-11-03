package com.arpit.glyf.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.SystemClock
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.arpit.glyf.R

/**
 * The strip while the keyboard listens (Arpit, 2026-10-06: "the mic should
 * work inside keyboard"), laid out as the Glyf bar is: ✕ in the g key's
 * box, then a level meter that moves with the voice, the words as they are
 * heard (one line, the newest in view; a tap there stops, as Done does)
 * and Done.
 */
@SuppressLint("ViewConstructor")
class DictationStripView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    onCancel: () -> Unit,
    onDone: () -> Unit,
) : LinearLayout(ctx) {

    private val dot = LevelBars(ctx)
    private val line = TextView(ctx)
    private val done = TextView(ctx)

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setTag(R.id.qa_id, "strip:dictation")
        // The bar's close: the g pill's box, 52 by 34 at 5 in, fillSoft with 10 corners.
        addView(FrameLayout(ctx).apply {
            background = Glass.card(ctx, Glass.fillSoft, radius = 10f)
            setTag(R.id.qa_id, "dictation:close")
            contentDescription = "Cancel"
            addView(ToolIcon(ctx, "close", Glass.textPrimary).apply {
                solid = true; weight = 1.9f; scale = 1.15f
            }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            setOnClickListener { onCancel() }
        }, LayoutParams(dp(52), dp(34)).apply { leftMargin = dp(5) })
        addView(dot, LayoutParams(dp(26), dp(24)).apply { leftMargin = dp(10) })
        line.apply {
            Glass.style(this, 17f, Glass.REGULAR, palette.inkSoft)
            text = "Listening…"
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.START
            setPadding(dp(8), 0, dp(10), 0)
            setTag(R.id.qa_id, "dictation:words")
            setOnClickListener { onDone() }
        }
        addView(line, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        // The pay panel's Done: the ink as a pill, the board's colour on it.
        done.apply {
            text = "Done"
            Glass.style(this, 14f, Glass.SEMIBOLD, palette.board)
            gravity = Gravity.CENTER
            setPadding(dp(16), 0, dp(16), 0)
            background = Glass.pill(palette.ink)
            setTag(R.id.qa_id, "dictation:done")
            setOnClickListener { onDone() }
        }
        addView(done, LayoutParams(LayoutParams.WRAP_CONTENT, dp(34)).apply { rightMargin = dp(6) })
    }

    /** The recognizer is ready: say so until the first words come. */
    fun ready() {
        if (heardAny) return
        line.text = "Speak now"
    }

    private var heardAny = false

    /** What has been heard so far. */
    fun words(text: String) {
        heardAny = true
        line.text = text
        line.setTextColor(palette.ink)
    }

    /** The voice's loudness as the recognizer gives it, about -2 to 10 dB. */
    fun level(rmsDb: Float) = dot.level(rmsDb)

    /** Done was tapped or the person went quiet: the last words are coming. */
    fun stopping() {
        dot.live = false
        done.isEnabled = false
        done.alpha = 0.4f
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    /** Five bars in the brand's violet, as Gboard's and iOS's voice meters
     *  are: they breathe while it listens and rise with the voice; when
     *  it's finishing they settle to dots. */
    private class LevelBars(ctx: Context) : View(ctx) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Glass.accentPrimary }
        private var loud = 0f
        private var shown = 0f
        private val shape = floatArrayOf(0.55f, 0.8f, 1f, 0.8f, 0.55f)

        var live = true
            set(value) { field = value; invalidate() }

        fun level(rmsDb: Float) {
            loud = maxOf(loud, ((rmsDb + 2f) / 12f).coerceIn(0f, 1f))
        }

        override fun onDraw(c: Canvas) {
            val d = resources.displayMetrics.density
            val bar = 3f * d
            val gap = (width - bar * shape.size) / (shape.size - 1)
            val cy = height / 2f
            val floor = bar
            val t = (SystemClock.uptimeMillis() % 1200L) / 1200f
            if (live) {
                shown += (loud - shown) * 0.35f
                loud *= 0.88f
            }
            paint.alpha = if (live) 255 else 120
            for (i in shape.indices) {
                // Each bar a little behind the one before, so the row ripples.
                val wave = 0.5f - 0.5f * kotlin.math.cos((t - i * 0.12f) * 2f * Math.PI.toFloat())
                val amount = if (live) maxOf(shown, 0.18f * wave) * shape[i] else 0f
                val h = floor + (height - floor) * amount
                val x = i * (bar + gap)
                c.drawRoundRect(x, cy - h / 2, x + bar, cy + h / 2, bar / 2, bar / 2, paint)
            }
            if (live) postInvalidateOnAnimation()
        }
    }
}
