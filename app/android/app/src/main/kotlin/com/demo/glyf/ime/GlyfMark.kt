package com.demo.glyf.ime

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View

/**
 * The Glyf mark, exactly as the app icon draws it: the icon's "g" (Inter
 * SemiBold at text size, 99.3% of the icon's letter) and the violet dot above
 * its right shoulder, drawn from the outline so no font or image ships. The
 * same numbers as iOS's GlyfMark.swift: change one, change both.
 */
object GlyfMark {
    /** The letter's ink is this wide for each unit of its height. */
    const val G_ASPECT = 0.6699f
    /** Where the icon puts the dot, in heights of the letter: its centre
     *  1.0379 right of the letter's left edge and 0.4927 above its top,
     *  0.3276 across. Dot top to letter foot, the mark is 1.6565 tall. */
    const val DOT_X = 1.0379f
    const val DOT_Y = 0.4927f
    const val DOT_SIZE = 0.3276f
    const val MARK_HEIGHT = 1.6565f
    val VIOLET = Color.rgb(0x7C, 0x5C, 0xFF)
    /** The icon's black. */
    val INK = Color.rgb(0x17, 0x18, 0x1C)

    /** The g's ink box filling [h] from ([x], [y]), y down. */
    fun gPath(x: Float, y: Float, h: Float): Path {
        val path = Path()
        fun m(px: Float, py: Float) = path.moveTo(x + px * h, y + py * h)
        fun l(px: Float, py: Float) = path.lineTo(x + px * h, y + py * h)
        fun q(cx: Float, cy: Float, px: Float, py: Float) = path.quadTo(x + cx * h, y + cy * h, x + px * h, y + py * h)
        fun z() = path.close()
        // Inter 4, wght 600, opsz 14: the outline, normalised to its ink box.
        m(0.3374f, 1.0000f)
        q(0.2520f, 1.0000f, 0.1889f, 0.9784f)
        q(0.1258f, 0.9568f, 0.0855f, 0.9195f)
        q(0.0452f, 0.8822f, 0.0273f, 0.8355f)
        l(0.1674f, 0.7854f)
        q(0.1786f, 0.8052f, 0.1985f, 0.8260f)
        q(0.2184f, 0.8468f, 0.2519f, 0.8606f)
        q(0.2855f, 0.8744f, 0.3370f, 0.8744f)
        q(0.4139f, 0.8744f, 0.4600f, 0.8386f)
        q(0.5062f, 0.8027f, 0.5062f, 0.7265f)
        l(0.5062f, 0.5919f)
        l(0.4926f, 0.5919f)
        q(0.4801f, 0.6177f, 0.4567f, 0.6448f)
        q(0.4333f, 0.6718f, 0.3936f, 0.6902f)
        q(0.3539f, 0.7087f, 0.2926f, 0.7087f)
        q(0.2109f, 0.7087f, 0.1445f, 0.6702f)
        q(0.0781f, 0.6316f, 0.0390f, 0.5546f)
        q(0.0000f, 0.4775f, 0.0000f, 0.3622f)
        q(0.0000f, 0.2455f, 0.0393f, 0.1647f)
        q(0.0787f, 0.0839f, 0.1452f, 0.0420f)
        q(0.2118f, 0.0000f, 0.2937f, 0.0000f)
        q(0.3566f, 0.0000f, 0.3973f, 0.0210f)
        q(0.4379f, 0.0419f, 0.4621f, 0.0716f)
        q(0.4863f, 0.1013f, 0.4990f, 0.1265f)
        l(0.5078f, 0.1265f)
        l(0.5078f, 0.0089f)
        l(0.6699f, 0.0089f)
        l(0.6699f, 0.7214f)
        q(0.6699f, 0.8158f, 0.6267f, 0.8777f)
        q(0.5835f, 0.9396f, 0.5083f, 0.9698f)
        q(0.4332f, 1.0000f, 0.3374f, 1.0000f)
        z()
        m(0.3386f, 0.5782f)
        q(0.3929f, 0.5782f, 0.4304f, 0.5523f)
        q(0.4679f, 0.5264f, 0.4874f, 0.4776f)
        q(0.5070f, 0.4287f, 0.5070f, 0.3606f)
        q(0.5070f, 0.2932f, 0.4876f, 0.2428f)
        q(0.4683f, 0.1924f, 0.4308f, 0.1642f)
        q(0.3933f, 0.1359f, 0.3386f, 0.1359f)
        q(0.2829f, 0.1359f, 0.2451f, 0.1654f)
        q(0.2073f, 0.1949f, 0.1882f, 0.2455f)
        q(0.1691f, 0.2961f, 0.1691f, 0.3606f)
        q(0.1691f, 0.4261f, 0.1884f, 0.4752f)
        q(0.2078f, 0.5242f, 0.2455f, 0.5512f)
        q(0.2833f, 0.5782f, 0.3386f, 0.5782f)
        z()
        return path
    }

    /** The key's width for a height (41 by 30 on the strip). */
    fun keyWidth(h: Float) = Math.round(h * 1.367f).toFloat()

    /** Draws the icon's mark in [box]: the letter centred across it and the
     *  whole mark (dot top to letter foot) centred down it, as on the icon. */
    fun drawMark(c: Canvas, box: RectF, margin: Float, letter: Paint, dot: Paint) {
        val h = (box.height() - margin * 2) / MARK_HEIGHT
        val x = box.centerX() - h * G_ASPECT / 2f
        val y = box.centerY() - h * MARK_HEIGHT / 2f + h * (MARK_HEIGHT - 1f)
        c.drawPath(gPath(x, y, h), letter)
        c.drawCircle(x + h * DOT_X, y - h * DOT_Y, h * DOT_SIZE / 2f, dot)
    }
}

/** The strip's first key: a pill holding the app icon's mark, in the icon's
 *  colours: its black with the letter white on a light sheet, and on a dark
 *  sheet the icon itself, white with its black g. While the menu is open it
 *  is a plain ✕ in the strip's ink. */
class GlyfKeyView(ctx: Context, private val keyHeight: Float) : View(ctx) {
    var closing = false
        set(value) { field = value; invalidate() }
    var dark = false
        set(value) { field = value; invalidate() }
    var ink = GlyfMark.INK
        set(value) { field = value; invalidate() }

    private val face = Paint(Paint.ANTI_ALIAS_FLAG)
    private val letter = Paint(Paint.ANTI_ALIAS_FLAG)
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = GlyfMark.VIOLET }
    private val cross = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND
        strokeWidth = 1.8f * ctx.resources.displayMetrics.density
    }

    override fun onDraw(c: Canvas) {
        val h = minOf(keyHeight, height.toFloat())
        val w = GlyfMark.keyWidth(h)
        val left = (width - w) / 2f
        val top = (height - h) / 2f
        if (closing) {
            val r = h * 0.3f
            val cx = width / 2f; val cy = height / 2f
            cross.color = ink
            c.drawLine(cx - r, cy - r, cx + r, cy + r, cross)
            c.drawLine(cx - r, cy + r, cx + r, cy - r, cross)
            return
        }
        val key = RectF(left, top, left + w, top + h)
        face.color = if (dark) Color.WHITE else GlyfMark.INK
        letter.color = if (dark) GlyfMark.INK else Color.WHITE
        c.drawRoundRect(key, h / 3f, h / 3f, face)
        GlyfMark.drawMark(c, key, h * 0.083f, letter, dot)
    }
}

/** The icon's mark in white on the act panel's black working key. */
class GlyfMarkView(ctx: Context, private val margin: Float) : View(ctx) {
    private val letter = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = GlyfMark.VIOLET }
    override fun onDraw(c: Canvas) {
        GlyfMark.drawMark(c, RectF(0f, 0f, width.toFloat(), height.toFloat()), margin, letter, dot)
    }
}
