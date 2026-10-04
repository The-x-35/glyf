package com.arpit.glyf.ime

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextUtils
import android.view.Gravity
import android.widget.TextView

/**
 * iOS's InlineEditor as the Android keyboard draws it: a field the keys type
 * into (a keyboard can't raise a keyboard of its own), on the key colour
 * with a hairline edge that turns the accent's while it takes the typing,
 * grey words while empty, the end of long text kept in view, and a
 * blinking accent caret after the text. [glyph] leads it in the accent (a
 * detail's kind), as iOS's symbol does.
 */
class InlineField(ctx: Context, placeholder: String, glyph: String? = null) : TextView(ctx) {

    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    /** The keys type into this one. */
    var active = false
        set(value) {
            field = value
            paintEdge()
            if (value) blink.start() else blink.cancel()
            invalidate()
        }

    /** The corners; the Ask bar's prompt is fully round (half its height). */
    var radiusDp = 12f
        set(value) { field = value; paintEdge() }

    /** Room kept at the end for a control drawn over the field (Ask's send). */
    var trailingDp = 12f
        set(value) {
            field = value
            setPadding(paddingLeft, 0, (value * density).toInt(), 0)
        }

    private var caretAlpha = 1f
    private val caret = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Glass.accentPrimary }
    private val blink = ValueAnimator.ofFloat(1f, 0.15f).apply {
        duration = 550
        repeatMode = ValueAnimator.REVERSE
        repeatCount = ValueAnimator.INFINITE
        addUpdateListener { caretAlpha = it.animatedValue as Float; invalidate() }
    }

    init {
        hint = placeholder
        Glass.style(this, 15f)
        setHintTextColor(Glass.textSecondary)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.START
        gravity = Gravity.CENTER_VERTICAL
        val lead = if (glyph != null) 36f else 12f
        if (glyph != null) {
            setCompoundDrawablesRelativeWithIntrinsicBounds(
                ToolIcon(ctx, glyph, Glass.accentPrimary).apply {
                    solid = true; weight = 2f; scale = 0.8f
                }.asDrawable(dp(22f).toInt()), null, null, null)
            // The mark 10 in from the edge, the words from 36.
            compoundDrawablePadding = dp(lead - 10f - 22f).toInt()
            setPadding(dp(10f).toInt(), 0, dp(12f).toInt(), 0)
        } else setPadding(dp(lead).toInt(), 0, dp(12f).toInt(), 0)
        paintEdge()
    }

    /** What is typed, on one line: a new line reads as a return mark. */
    fun show(text: String) {
        this.text = text.replace("\n", " ⏎ ")
        invalidate()
    }

    private fun paintEdge() {
        background = Glass.card(context, radius = radiusDp,
            stroke = if (active) Glass.strokeFocus else Glass.strokeHairline, strokeDp = 1f)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!active) return
        val start = compoundPaddingLeft.toFloat()
        val textW = if (text.isNullOrEmpty()) 0f else (layout?.getLineWidth(0) ?: 0f)
        val x = minOf(start + textW + (if (textW > 0) dp(2f) else 0f), width - totalPaddingRight - dp(2f))
        caret.alpha = (caretAlpha * 255).toInt()
        canvas.drawRoundRect(RectF(x, dp(7f), x + dp(2f), height - dp(7f)), dp(1f), dp(1f), caret)
    }

    override fun onDetachedFromWindow() {
        blink.cancel()
        super.onDetachedFromWindow()
    }
}
