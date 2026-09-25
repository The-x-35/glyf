package com.demo.glyf.ime

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View

/**
 * The Glyf key's letter: Inter Bold's "g", the letter tryglyf.com's keyboard
 * draws on its g key (the app icon's is the SemiBold cut of the same design),
 * drawn from its outline so no font or image ships. The same numbers as
 * iOS's GlyfMark.swift: change one, change both.
 */
object GlyfMark {
    /** The letter's ink is this wide for each unit of its height. */
    const val G_ASPECT = 0.6891f
    /** The ink's height and its bowl per unit of type size: the site sizes
     *  the letter as type and centres the bowl, the tail hanging below. */
    const val INK_PER_EM = 0.7686f
    const val BOWL_PER_EM = 0.5527f
    val VIOLET = Color.rgb(0x7C, 0x5C, 0xFF)
    val INK = Color.rgb(18, 18, 20)
    /** The key's face: the site's near-black, black on a dark sheet. */
    val FACE_LIGHT = Color.rgb(0x1D, 0x1D, 0x1F)
    val FACE_DARK = Color.BLACK

    /** The g's ink box filling [h] from ([x], [y]), y down. */
    fun gPath(x: Float, y: Float, h: Float): Path {
        val path = Path()
        fun m(px: Float, py: Float) = path.moveTo(x + px * h, y + py * h)
        fun l(px: Float, py: Float) = path.lineTo(x + px * h, y + py * h)
        fun q(cx: Float, cy: Float, px: Float, py: Float) = path.quadTo(x + cx * h, y + cy * h, x + px * h, y + py * h)
        fun z() = path.close()
        // Inter 4, wght 700, opsz 14: the outline, normalised to its ink box.
        m(0.3451f, 1.0000f)
        q(0.2564f, 1.0000f, 0.1905f, 0.9776f)
        q(0.1246f, 0.9552f, 0.0832f, 0.9158f)
        q(0.0418f, 0.8764f, 0.0261f, 0.8256f)
        l(0.1899f, 0.7803f)
        q(0.1989f, 0.8000f, 0.2175f, 0.8187f)
        q(0.2361f, 0.8375f, 0.2672f, 0.8495f)
        q(0.2983f, 0.8615f, 0.3444f, 0.8615f)
        q(0.4172f, 0.8615f, 0.4589f, 0.8280f)
        q(0.5007f, 0.7946f, 0.5007f, 0.7241f)
        l(0.5007f, 0.5934f)
        l(0.4858f, 0.5934f)
        q(0.4730f, 0.6220f, 0.4489f, 0.6486f)
        q(0.4247f, 0.6751f, 0.3856f, 0.6921f)
        q(0.3465f, 0.7091f, 0.2889f, 0.7091f)
        q(0.2089f, 0.7091f, 0.1433f, 0.6715f)
        q(0.0777f, 0.6339f, 0.0389f, 0.5571f)
        q(0.0000f, 0.4803f, 0.0000f, 0.3629f)
        q(0.0000f, 0.2427f, 0.0396f, 0.1621f)
        q(0.0792f, 0.0814f, 0.1449f, 0.0407f)
        q(0.2107f, 0.0000f, 0.2894f, 0.0000f)
        q(0.3494f, 0.0000f, 0.3899f, 0.0202f)
        q(0.4303f, 0.0403f, 0.4555f, 0.0702f)
        q(0.4806f, 0.1001f, 0.4937f, 0.1284f)
        l(0.5015f, 0.1284f)
        l(0.5015f, 0.0089f)
        l(0.6891f, 0.0089f)
        l(0.6891f, 0.7133f)
        q(0.6891f, 0.8092f, 0.6449f, 0.8730f)
        q(0.6007f, 0.9368f, 0.5231f, 0.9684f)
        q(0.4456f, 1.0000f, 0.3451f, 1.0000f)
        z()
        m(0.3484f, 0.5642f)
        q(0.3975f, 0.5642f, 0.4315f, 0.5402f)
        q(0.4655f, 0.5161f, 0.4834f, 0.4707f)
        q(0.5013f, 0.4252f, 0.5013f, 0.3618f)
        q(0.5013f, 0.2985f, 0.4835f, 0.2516f)
        q(0.4658f, 0.2048f, 0.4318f, 0.1787f)
        q(0.3977f, 0.1527f, 0.3484f, 0.1527f)
        q(0.2986f, 0.1527f, 0.2645f, 0.1796f)
        q(0.2303f, 0.2065f, 0.2129f, 0.2535f)
        q(0.1955f, 0.3005f, 0.1955f, 0.3618f)
        q(0.1955f, 0.4235f, 0.2131f, 0.4691f)
        q(0.2306f, 0.5147f, 0.2647f, 0.5395f)
        q(0.2989f, 0.5642f, 0.3484f, 0.5642f)
        z()
        return path
    }

    /** The key's width for a height (41 by 30 on the strip). */
    fun keyWidth(h: Float) = Math.round(h * 1.367f).toFloat()
}

/** The strip's first key, as tryglyf.com draws it and a little taller: a
 *  black pill, the white g centred on its bowl, the violet dot 18% down and
 *  20% in from the right, at the letter's shoulder (a faint ring on a dark
 *  sheet). While the menu is open it is a plain ✕ in the strip's ink. */
class GlyfKeyView(ctx: Context, private val keyHeight: Float) : View(ctx) {
    var closing = false
        set(value) { field = value; invalidate() }
    var dark = false
        set(value) { field = value; invalidate() }
    var ink = GlyfMark.INK
        set(value) { field = value; invalidate() }

    private val face = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; color = Color.argb(46, 255, 255, 255)
        strokeWidth = 0.5f * ctx.resources.displayMetrics.density
    }
    private val letter = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
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
        face.color = if (dark) GlyfMark.FACE_DARK else GlyfMark.FACE_LIGHT
        c.drawRoundRect(key, h / 3f, h / 3f, face)
        if (dark) c.drawRoundRect(key, h / 3f, h / 3f, ring)
        val size = h * 0.617f
        val ink = size * GlyfMark.INK_PER_EM
        val bowl = size * GlyfMark.BOWL_PER_EM
        c.drawPath(GlyfMark.gPath(key.centerX() - ink * GlyfMark.G_ASPECT / 2f, key.centerY() - bowl / 2f, ink), letter)
        val d = h * 0.2f
        c.drawCircle(key.right - w * 0.2f - d / 2f, key.top + h * 0.18f + d / 2f, d / 2f, dot)
    }
}

/** Just the white g, centred a little left of the middle so a corner dot
 *  keeps its room (the act panel's working key). */
class GlyfLetterView(ctx: Context, private val letterHeight: Float) : View(ctx) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    override fun onDraw(c: Canvas) {
        val gh = letterHeight
        val gw = gh * GlyfMark.G_ASPECT
        c.drawPath(GlyfMark.gPath((width - gw) / 2f - gh * 0.037f, (height - gh) / 2f, gh), paint)
    }
}
