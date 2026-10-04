package com.arpit.glyf.ime

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.os.SystemClock

/**
 * The website's coach on the keyboard: a pulsing ring around the one thing
 * to tap and a purple label with a point toward it (.kb-coach). Drawn in the
 * keyboard's overlay, so it never takes a touch or moves a key.
 */
class TourCoachOverlay(private val density: Float) : Drawable() {

    /** In the overlay host's coordinates. */
    var target: RectF? = null
        set(value) { field = value; invalidateSelf() }
    var label: String = ""
        set(value) { field = value; invalidateSelf() }

    private val accent = Color.rgb(0x7C, 0x5C, 0xFF)
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2.5f * density
        color = accent
    }
    private val pill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = accent
        setShadowLayer(7f * density, 0f, 3f * density, Color.argb(110, 0x7C, 0x5C, 0xFF))
    }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 13f * density
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val started = SystemClock.uptimeMillis()
    private val tick = Runnable { invalidateSelf() }

    override fun draw(canvas: Canvas) {
        val r = target ?: return
        val d = density
        // The ring breathes once every 1.5s, like the website's.
        val phase = ((SystemClock.uptimeMillis() - started) % 1500) / 750f
        val a = if (phase < 1f) 1f - phase * 0.7f else 0.3f + (phase - 1f) * 0.7f
        ring.alpha = (255 * a).toInt()
        // Along the top edge a ring outside the target would be cut off, so
        // it hugs the target's own outline there.
        val onStrip = r.top < 6 * d
        val inset = if (onStrip) 1.25f * d else -3f * d
        val box = RectF(r).apply { inset(inset, inset) }
        val radius = if (onStrip) minOf(box.height() / 2, 12 * d) else minOf(9 * d, box.height() / 2)
        canvas.drawRoundRect(box, radius, radius, ring)

        if (label.isNotEmpty()) {
            val w = text.measureText(label) + 22 * d
            val h = 26 * d
            val point = 5 * d
            val gap = 5 * d
            val hostW = bounds.width().toFloat()
            val above = !onStrip && r.top - gap - point - h >= 0
            val x = (r.centerX() - w / 2).coerceIn(6 * d, maxOf(6 * d, hostW - w - 6 * d))
            val y = if (above) r.top - gap - point - h else r.bottom + gap + point
            canvas.drawRoundRect(RectF(x, y, x + w, y + h), h / 2, h / 2, pill)
            val ax = r.centerX().coerceIn(x + 10 * d, x + w - 10 * d)
            val p = Path()
            if (above) {
                p.moveTo(ax - 5.5f * d, y + h - 0.5f); p.lineTo(ax, y + h + point); p.lineTo(ax + 5.5f * d, y + h - 0.5f)
            } else {
                p.moveTo(ax - 5.5f * d, y + 0.5f); p.lineTo(ax, y - point); p.lineTo(ax + 5.5f * d, y + 0.5f)
            }
            p.close()
            canvas.drawPath(p, pill)
            canvas.drawText(label, x + w / 2, y + h / 2 - (text.descent() + text.ascent()) / 2, text)
        }
        unscheduleSelf(tick)
        scheduleSelf(tick, SystemClock.uptimeMillis() + 33)
    }

    fun stop() {
        unscheduleSelf(tick)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
