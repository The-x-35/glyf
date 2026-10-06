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
 * box, then a dot that swells with the voice, the words as they are heard
 * (one line, the newest in view) and Done.
 */
@SuppressLint("ViewConstructor")
class DictationStripView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    onCancel: () -> Unit,
    onDone: () -> Unit,
) : LinearLayout(ctx) {

    private val dot = LevelDot(ctx)
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
        addView(dot, LayoutParams(dp(24), dp(24)).apply { leftMargin = dp(10) })
        line.apply {
            Glass.style(this, 17f, Glass.REGULAR, palette.inkSoft)
            text = "Listening…"
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.START
            setPadding(dp(8), 0, dp(10), 0)
            setTag(R.id.qa_id, "dictation:words")
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

    /** What has been heard so far. */
    fun words(text: String) {
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

    /** The brand's dot; while it listens, its halo breathes and swells with the voice. */
    private class LevelDot(ctx: Context) : View(ctx) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Glass.accentPrimary }
        private var loud = 0f
        private var shown = 0f

        var live = true
            set(value) { field = value; invalidate() }

        fun level(rmsDb: Float) {
            loud = maxOf(loud, ((rmsDb + 2f) / 12f).coerceIn(0f, 1f))
        }

        override fun onDraw(c: Canvas) {
            val d = resources.displayMetrics.density
            val cx = width / 2f
            val cy = height / 2f
            val core = 4.5f * d
            if (live) {
                shown += (loud - shown) * 0.3f
                loud *= 0.9f
                val t = (SystemClock.uptimeMillis() % 1600L) / 1600f
                val breath = 0.5f - 0.5f * kotlin.math.cos(t * 2f * Math.PI.toFloat())
                paint.alpha = 56
                c.drawCircle(cx, cy, core + (minOf(cx, cy) - core) * maxOf(shown, 0.35f * breath), paint)
                postInvalidateOnAnimation()
            }
            paint.alpha = if (live) 255 else 140
            c.drawCircle(cx, cy, core, paint)
        }
    }
}
