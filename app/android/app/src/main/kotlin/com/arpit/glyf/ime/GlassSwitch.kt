package com.arpit.glyf.ime

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.View

/**
 * iOS 26's switch (UISwitch, as the keyboard's Settings rows wear it): a 63
 * by 28 track, a white capsule thumb that slides, the track in the ink when
 * on (Glass.controlOn) and a soft grey when off. The row it sits in flips
 * it; [onChange] hears the new value.
 */
class GlassSwitch(ctx: Context, initial: Boolean, private val onChange: (Boolean) -> Unit) : View(ctx) {

    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    var isOn = initial
        private set

    /** 0 off … 1 on, for the slide. */
    private var t = if (initial) 1f else 0f
    private val track = Paint(Paint.ANTI_ALIAS_FLAG)
    private val thumb = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        setShadowLayer(dp(2f), 0f, dp(1.5f), Color.argb(46, 0, 0, 0))
    }
    /** iOS's off track: a grey laid over the card it sits on. */
    private val offTrack = blend(Glass.surfaceCard, Color.rgb(120, 120, 128), if (Glass.dark) 0.32f else 0.16f)

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null) // the thumb's shadow
        contentDescription = "Switch"
        isSelected = initial
        setOnClickListener { set(!isOn, animated = true) }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(dp(63f).toInt(), dp(28f).toInt())
    }

    fun set(on: Boolean, animated: Boolean) {
        if (on == isOn) return
        isOn = on
        isSelected = on
        onChange(on)
        if (!animated) { t = if (on) 1f else 0f; invalidate(); return }
        ValueAnimator.ofFloat(t, if (on) 1f else 0f).apply {
            duration = 200
            addUpdateListener { t = it.animatedValue as Float; invalidate() }
        }.start()
    }

    override fun onDraw(c: Canvas) {
        val h = height.toFloat()
        val w = width.toFloat()
        track.color = blend(offTrack, Glass.controlOn, t)
        c.drawRoundRect(RectF(0f, 0f, w, h), h / 2, h / 2, track)
        // The capsule thumb, 2 in from the track's edge.
        val th = h - dp(4f)
        val tw = dp(38f)
        val x = dp(2f) + (w - dp(4f) - tw) * t
        c.drawRoundRect(RectF(x, dp(2f), x + tw, dp(2f) + th), th / 2, th / 2, thumb)
    }

    private fun blend(a: Int, b: Int, k: Float) = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * k).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * k).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * k).toInt())
}
