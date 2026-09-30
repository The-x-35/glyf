package com.demo.glyf.ime

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View

/**
 * Monochrome tool glyphs, canvas-drawn so they tint with the keyboard (the
 * SF Symbol equivalent; emoji cannot be tinted). One drawing per tool id, the
 * same ids the strip and the g menu use on both platforms.
 */
class ToolIcon(ctx: Context, private val kind: String, tint: Int) : View(ctx) {

    private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = tint
        alpha = 205
    }
    private val fill = Paint(p).apply { style = Paint.Style.FILL }

    /** Drawings are sized for a 20dp glyph; bigger tiles scale them up. */
    var scale = 1f
        set(value) { field = value; invalidate() }

    /** The stroke in dp at scale 1 (1.6 regular; iOS medium and semibold
     *  symbols draw heavier). */
    var weight = 1.6f
        set(value) { field = value; invalidate() }

    /** Drawn in the tint itself, not the softer 80% the strip's tools use:
     *  an accent glyph beside words matches the accent around it. */
    var solid = false
        set(value) {
            field = value
            p.alpha = if (value) 255 else 205
            fill.alpha = p.alpha
            invalidate()
        }

    /** Recolour (the chosen tab is full ink, the rest are grey). */
    fun setTint(color: Int) {
        p.color = color
        p.alpha = if (Color.alpha(color) == 255) 205 else Color.alpha(color)
        fill.color = p.color
        fill.alpha = p.alpha
        invalidate()
    }

    private fun dp(v: Float) = v * resources.displayMetrics.density * scale

    override fun onDraw(c: Canvas) {
        p.strokeWidth = dp(weight)
        val cx = width / 2f
        val cy = height / 2f
        when (kind) {
            "search" -> {
                c.drawCircle(cx - dp(1.5f), cy - dp(1.5f), dp(5.2f), p)
                c.drawLine(cx + dp(2.4f), cy + dp(2.4f), cx + dp(6.4f), cy + dp(6.4f), p)
            }
            "clipboard" -> {
                c.drawRoundRect(cx - dp(6f), cy - dp(6.4f), cx + dp(6f), cy + dp(7.6f),
                    dp(2.4f), dp(2.4f), p)
                c.drawRoundRect(cx - dp(3f), cy - dp(8.6f), cx + dp(3f), cy - dp(4.8f),
                    dp(1.6f), dp(1.6f), p)
            }
            "vault" -> {
                c.drawRoundRect(cx - dp(7.6f), cy - dp(5.6f), cx + dp(7.6f), cy + dp(5.6f),
                    dp(2.4f), dp(2.4f), p)
                c.drawCircle(cx - dp(3.6f), cy - dp(0.6f), dp(1.8f), p)
                c.drawLine(cx + dp(1f), cy - dp(2f), cx + dp(5f), cy - dp(2f), p)
                c.drawLine(cx + dp(1f), cy + dp(1.6f), cx + dp(5f), cy + dp(1.6f), p)
            }
            // SF gearshape: a toothed wheel round a hole.
            "settings", "gear" -> {
                val gear = Path()
                val teeth = 8
                for (i in 0 until teeth * 4) {
                    val a = Math.toRadians(i * 360.0 / (teeth * 4) - 90)
                    val r = if ((i / 2) % 2 == 0) dp(8f) else dp(6.3f)
                    val x = cx + (r * Math.cos(a)).toFloat()
                    val y = cy + (r * Math.sin(a)).toFloat()
                    if (i == 0) gear.moveTo(x, y) else gear.lineTo(x, y)
                }
                gear.close()
                c.drawPath(gear, p)
                c.drawCircle(cx, cy, dp(2.6f), p)
            }
            "dictation", "mic" -> {
                c.drawRoundRect(cx - dp(2.6f), cy - dp(8f), cx + dp(2.6f), cy + dp(1f),
                    dp(2.6f), dp(2.6f), p)
                c.drawArc(RectF(cx - dp(5.6f), cy - dp(4f), cx + dp(5.6f), cy + dp(4.4f)),
                    15f, 150f, false, p)
                c.drawLine(cx, cy + dp(4.4f), cx, cy + dp(7.6f), p)
            }
            "emoji" -> {
                c.drawCircle(cx, cy, dp(7f), p)
                c.drawCircle(cx - dp(2.6f), cy - dp(2f), dp(1f), fill)
                c.drawCircle(cx + dp(2.6f), cy - dp(2f), dp(1f), fill)
                c.drawArc(cx - dp(3.6f), cy - dp(1.4f), cx + dp(3.6f), cy + dp(4.4f),
                    25f, 130f, false, p)
            }
            // SF translate: two speech bubbles, A and 文.
            "translate" -> {
                val back = RectF(cx - dp(8.4f), cy - dp(8f), cx + dp(1.6f), cy + dp(1f))
                c.drawRoundRect(back, dp(2.2f), dp(2.2f), p)
                val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = p.color; alpha = p.alpha
                    textAlign = Paint.Align.CENTER
                    typeface = Glass.font(context, Glass.SEMIBOLD)
                }
                t.textSize = dp(7.4f)
                c.drawText("A", back.centerX(), back.centerY() + dp(2.6f), t)
                val front = RectF(cx - dp(1.6f), cy - dp(1.4f), cx + dp(8.6f), cy + dp(7.6f))
                // The 文 is cut out of the front bubble, in a layer of its own.
                val layer = c.saveLayer(front, null)
                c.drawRoundRect(front, dp(2.2f), dp(2.2f), fill)
                val cut = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.CLEAR)
                    textAlign = Paint.Align.CENTER
                    typeface = Glass.font(context, Glass.SEMIBOLD)
                    textSize = dp(7f)
                }
                c.drawText("文", front.centerX(), front.centerY() + dp(2.5f), cut)
                c.restoreToCount(layer)
            }
            "notes" -> {
                c.drawRoundRect(cx - dp(6.4f), cy - dp(7f), cx + dp(6.4f), cy + dp(7f),
                    dp(2.4f), dp(2.4f), p)
                c.drawLine(cx - dp(3.4f), cy - dp(2.6f), cx + dp(3.4f), cy - dp(2.6f), p)
                c.drawLine(cx - dp(3.4f), cy + dp(0.8f), cx + dp(3.4f), cy + dp(0.8f), p)
            }
            "rewrite" -> {
                // A wand: the stick, and the sparkle it leaves.
                c.drawLine(cx - dp(6.4f), cy + dp(6.4f), cx + dp(2.4f), cy - dp(2.4f), p)
                sparkle(c, cx + dp(4.6f), cy - dp(4.6f), dp(3.4f))
                sparkle(c, cx - dp(3.6f), cy - dp(5.6f), dp(1.8f))
            }
            // An envelope: Temp mail.
            "tempmail" -> {
                c.drawRoundRect(cx - dp(7.6f), cy - dp(5.6f), cx + dp(7.6f), cy + dp(5.6f),
                    dp(2f), dp(2f), p)
                val flap = Path().apply {
                    moveTo(cx - dp(6.6f), cy - dp(4.4f))
                    lineTo(cx, cy + dp(0.6f))
                    lineTo(cx + dp(6.6f), cy - dp(4.4f))
                }
                c.drawPath(flap, p)
            }
            // A cross about 11dp across (its round ends included): the way a
            // strip chip is waved off.
            "close" -> {
                c.drawLine(cx - dp(4.7f), cy - dp(4.7f), cx + dp(4.7f), cy + dp(4.7f), p)
                c.drawLine(cx + dp(4.7f), cy - dp(4.7f), cx - dp(4.7f), cy + dp(4.7f), p)
            }
            // A lightning bolt, the vault's New shorthand (iOS bolt).
            "bolt" -> {
                val path = Path().apply {
                    moveTo(cx + dp(1.8f), cy - dp(8f))
                    lineTo(cx - dp(5.4f), cy + dp(1.4f))
                    lineTo(cx - dp(0.2f), cy + dp(1.4f))
                    lineTo(cx - dp(1.8f), cy + dp(8f))
                    lineTo(cx + dp(5.4f), cy - dp(1.4f))
                    lineTo(cx + dp(0.2f), cy - dp(1.4f))
                    close()
                }
                c.drawPath(path, p)
            }
            "ask" -> {
                sparkle(c, cx - dp(1.2f), cy + dp(1.2f), dp(6.4f))
                sparkle(c, cx + dp(5.2f), cy - dp(5.2f), dp(2.6f))
            }
            "glyfs" -> {
                val s = dp(5.6f)
                val g = dp(1.6f)
                for (dx in listOf(-1, 1)) for (dy in listOf(-1, 1)) {
                    val x = cx + dx * (g / 2 + s / 2)
                    val y = cy + dy * (g / 2 + s / 2)
                    c.drawRoundRect(x - s / 2, y - s / 2, x + s / 2, y + s / 2, dp(1.6f), dp(1.6f), p)
                }
            }
            "back" -> {
                c.drawLine(cx - dp(6.4f), cy, cx + dp(6.4f), cy, p)
                c.drawLine(cx - dp(6.4f), cy, cx - dp(1.6f), cy - dp(4.8f), p)
                c.drawLine(cx - dp(6.4f), cy, cx - dp(1.6f), cy + dp(4.8f), p)
            }
            "edit" -> {
                val path = Path().apply {
                    moveTo(cx + dp(3.6f), cy - dp(6.8f))
                    lineTo(cx + dp(6.8f), cy - dp(3.6f))
                    lineTo(cx - dp(3.6f), cy + dp(6.8f))
                    lineTo(cx - dp(6.8f), cy + dp(6.8f))
                    lineTo(cx - dp(6.8f), cy + dp(3.6f))
                    close()
                }
                c.drawPath(path, p)
            }
            "calendar" -> {
                c.drawRoundRect(cx - dp(7.4f), cy - dp(6.2f), cx + dp(7.4f), cy + dp(7.4f),
                    dp(2.4f), dp(2.4f), p)
                c.drawLine(cx - dp(7.4f), cy - dp(2.2f), cx + dp(7.4f), cy - dp(2.2f), p)
                c.drawLine(cx - dp(3.6f), cy - dp(8.4f), cx - dp(3.6f), cy - dp(4.6f), p)
                c.drawLine(cx + dp(3.6f), cy - dp(8.4f), cx + dp(3.6f), cy - dp(4.6f), p)
                for (row in 0..1) for (col in -1..1) {
                    c.drawCircle(cx + col * dp(3.8f), cy + dp(1.4f) + row * dp(3.2f), dp(0.9f), fill)
                }
            }
            // A call link: a camera, the way Calendar marks a video call.
            "video" -> {
                c.drawRoundRect(cx - dp(8.4f), cy - dp(5f), cx + dp(2.8f), cy + dp(5f),
                    dp(2.2f), dp(2.2f), p)
                val path = Path().apply {
                    moveTo(cx + dp(3.6f), cy - dp(1.4f)); lineTo(cx + dp(8.4f), cy - dp(4.4f))
                    lineTo(cx + dp(8.4f), cy + dp(4.4f)); lineTo(cx + dp(3.6f), cy + dp(1.4f)); close()
                }
                c.drawPath(path, p)
            }
            // The emoji board's tabs, after Apple's emoji keyboard.
            "clock" -> {
                c.drawCircle(cx, cy, dp(7f), p)
                c.drawLine(cx, cy - dp(4.2f), cx, cy, p)
                c.drawLine(cx, cy, cx + dp(3f), cy + dp(1.8f), p)
            }
            "bear" -> {
                c.drawCircle(cx, cy + dp(1f), dp(6.2f), p)
                c.drawCircle(cx - dp(5f), cy - dp(4.6f), dp(2.2f), p)
                c.drawCircle(cx + dp(5f), cy - dp(4.6f), dp(2.2f), p)
                c.drawCircle(cx - dp(2.2f), cy - dp(0.2f), dp(0.9f), fill)
                c.drawCircle(cx + dp(2.2f), cy - dp(0.2f), dp(0.9f), fill)
                c.drawOval(RectF(cx - dp(2f), cy + dp(1.8f), cx + dp(2f), cy + dp(4.6f)), p)
            }
            "food" -> {
                // A cup with a straw beside a burger, Apple's Food & Drink.
                c.drawLine(cx - dp(7f), cy - dp(3f), cx - dp(1.4f), cy - dp(3f), p)
                c.drawLine(cx - dp(6.4f), cy - dp(3f), cx - dp(5.6f), cy + dp(7f), p)
                c.drawLine(cx - dp(2f), cy - dp(3f), cx - dp(2.8f), cy + dp(7f), p)
                c.drawLine(cx - dp(4.4f), cy - dp(3f), cx - dp(3f), cy - dp(8f), p)
                c.drawArc(RectF(cx - dp(0.4f), cy - dp(1f), cx + dp(7.6f), cy + dp(6f)), 180f, 180f, false, p)
                c.drawLine(cx - dp(0.4f), cy + dp(4f), cx + dp(7.6f), cy + dp(4f), p)
                c.drawLine(cx - dp(0.4f), cy + dp(6.6f), cx + dp(7.6f), cy + dp(6.6f), p)
            }
            "ball" -> {
                c.drawCircle(cx, cy, dp(7f), p)
                val path = Path().apply {
                    for (i in 0 until 5) {
                        val a = Math.toRadians(-90.0 + i * 72.0)
                        val x = cx + (dp(2.6f) * Math.cos(a)).toFloat()
                        val y = cy + (dp(2.6f) * Math.sin(a)).toFloat()
                        if (i == 0) moveTo(x, y) else lineTo(x, y)
                    }
                    close()
                }
                c.drawPath(path, fill)
                for (i in 0 until 5) {
                    val a = Math.toRadians(-90.0 + i * 72.0)
                    c.drawLine(cx + (dp(2.6f) * Math.cos(a)).toFloat(), cy + (dp(2.6f) * Math.sin(a)).toFloat(),
                        cx + (dp(7f) * Math.cos(a)).toFloat(), cy + (dp(7f) * Math.sin(a)).toFloat(), p)
                }
            }
            "car" -> {
                c.drawRoundRect(cx - dp(7.6f), cy - dp(1.6f), cx + dp(7.6f), cy + dp(4.4f), dp(2f), dp(2f), p)
                val roof = Path().apply {
                    moveTo(cx - dp(5f), cy - dp(1.6f)); lineTo(cx - dp(3.2f), cy - dp(6f))
                    lineTo(cx + dp(3.2f), cy - dp(6f)); lineTo(cx + dp(5f), cy - dp(1.6f))
                }
                c.drawPath(roof, p)
                c.drawCircle(cx - dp(4.2f), cy + dp(5.8f), dp(1.6f), fill)
                c.drawCircle(cx + dp(4.2f), cy + dp(5.8f), dp(1.6f), fill)
            }
            "bulb" -> {
                c.drawArc(RectF(cx - dp(5.4f), cy - dp(8f), cx + dp(5.4f), cy + dp(2.8f)), 140f, 260f, false, p)
                c.drawLine(cx - dp(2.8f), cy + dp(2f), cx - dp(2.4f), cy + dp(4.6f), p)
                c.drawLine(cx + dp(2.8f), cy + dp(2f), cx + dp(2.4f), cy + dp(4.6f), p)
                c.drawLine(cx - dp(2.6f), cy + dp(4.8f), cx + dp(2.6f), cy + dp(4.8f), p)
                c.drawLine(cx - dp(1.8f), cy + dp(7.2f), cx + dp(1.8f), cy + dp(7.2f), p)
            }
            "heart" -> {
                val path = Path().apply {
                    moveTo(cx, cy + dp(6.4f))
                    cubicTo(cx - dp(9f), cy, cx - dp(5f), cy - dp(8f), cx, cy - dp(3f))
                    cubicTo(cx + dp(5f), cy - dp(8f), cx + dp(9f), cy, cx, cy + dp(6.4f))
                    close()
                }
                c.drawPath(path, p)
            }
            "flag" -> {
                c.drawLine(cx - dp(5.6f), cy - dp(7.6f), cx - dp(5.6f), cy + dp(7.6f), p)
                val path = Path().apply {
                    moveTo(cx - dp(5.6f), cy - dp(7f))
                    quadTo(cx - dp(1f), cy - dp(9f), cx + dp(1.8f), cy - dp(6.4f))
                    quadTo(cx + dp(4.6f), cy - dp(4f), cx + dp(7f), cy - dp(6f))
                    lineTo(cx + dp(7f), cy + dp(1f))
                    quadTo(cx + dp(4.6f), cy + dp(3f), cx + dp(1.8f), cy + dp(0.6f))
                    quadTo(cx - dp(1f), cy - dp(2f), cx - dp(5.6f), cy)
                }
                c.drawPath(path, p)
            }
            "sticker" -> {
                // A rounded square with its corner peeling, and a smile.
                val s = dp(15f); val r = s * 0.24f; val fold = s * 0.36f
                val x0 = cx - s / 2; val y0 = cy - s / 2
                val path = Path().apply {
                    moveTo(x0 + r, y0); lineTo(x0 + s - r, y0)
                    quadTo(x0 + s, y0, x0 + s, y0 + r); lineTo(x0 + s, y0 + s - fold)
                    lineTo(x0 + s - fold, y0 + s); lineTo(x0 + r, y0 + s)
                    quadTo(x0, y0 + s, x0, y0 + s - r); lineTo(x0, y0 + r)
                    quadTo(x0, y0, x0 + r, y0); close()
                    moveTo(x0 + s, y0 + s - fold)
                    quadTo(x0 + s - fold * 0.95f, y0 + s - fold * 0.95f, x0 + s - fold, y0 + s)
                    moveTo(x0 + s * 0.28f, y0 + s * 0.56f)
                    quadTo(x0 + s * 0.42f, y0 + s * 0.78f, x0 + s * 0.60f, y0 + s * 0.62f)
                }
                c.drawPath(path, p)
                c.drawCircle(x0 + s * 0.34f, y0 + s * 0.36f, dp(1f), fill)
                c.drawCircle(x0 + s * 0.60f, y0 + s * 0.36f, dp(1f), fill)
            }
            // The board's GIFs tab, and the menu's GIFs tile that opens it.
            "gif", "gifs" -> {
                p.strokeWidth = dp(1.4f)
                c.drawRoundRect(cx - dp(9f), cy - dp(5.4f), cx + dp(9f), cy + dp(5.4f), dp(2.4f), dp(2.4f), p)
                val t = Paint(fill).apply {
                    textSize = dp(7.8f); textAlign = Paint.Align.CENTER
                    typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                }
                c.drawText("GIF", cx, cy + dp(2.8f), t)
            }
            "flame" -> {
                val path = Path().apply {
                    moveTo(cx, cy + dp(7.4f))
                    cubicTo(cx - dp(6f), cy + dp(7.4f), cx - dp(6.4f), cy - dp(0.6f), cx - dp(1.6f), cy - dp(7.6f))
                    cubicTo(cx - dp(0.8f), cy - dp(3.6f), cx + dp(1.6f), cy - dp(2.4f), cx + dp(2.4f), cy - dp(4.2f))
                    cubicTo(cx + dp(6.6f), cy - dp(0.4f), cx + dp(6f), cy + dp(7.4f), cx, cy + dp(7.4f))
                    close()
                }
                c.drawPath(path, p)
            }
            "star" -> {
                val path = Path()
                for (i in 0 until 10) {
                    val a = Math.toRadians(-90.0 + i * 36.0)
                    val rr = if (i % 2 == 0) dp(7.6f) else dp(3.2f)
                    val x = cx + (rr * Math.cos(a)).toFloat(); val y = cy + (rr * Math.sin(a)).toFloat()
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                path.close()
                c.drawPath(path, p)
            }
            "delete" -> {
                // Apple's backspace: a tag pointing left with a cross in it.
                val path = Path().apply {
                    moveTo(cx - dp(9f), cy); lineTo(cx - dp(4f), cy - dp(6.4f))
                    lineTo(cx + dp(8.4f), cy - dp(6.4f)); lineTo(cx + dp(8.4f), cy + dp(6.4f))
                    lineTo(cx - dp(4f), cy + dp(6.4f)); close()
                }
                c.drawPath(path, p)
                c.drawLine(cx - dp(0.6f), cy - dp(2.6f), cx + dp(4.6f), cy + dp(2.6f), p)
                c.drawLine(cx + dp(4.6f), cy - dp(2.6f), cx - dp(0.6f), cy + dp(2.6f), p)
            }
            "pay" -> {
                c.drawRoundRect(cx - dp(8.4f), cy - dp(5.8f), cx + dp(8.4f), cy + dp(5.8f),
                    dp(2f), dp(2f), p)
                c.drawLine(cx - dp(8.4f), cy - dp(2f), cx + dp(8.4f), cy - dp(2f), p)
                c.drawLine(cx - dp(5.6f), cy + dp(2.8f), cx - dp(1.6f), cy + dp(2.8f), p)
            }
            // SF chevron.left: the strip's way back inside a panel.
            "chevron" -> {
                c.drawLine(cx + dp(2.6f), cy - dp(6.6f), cx - dp(3.6f), cy, p)
                c.drawLine(cx - dp(3.6f), cy, cx + dp(2.6f), cy + dp(6.6f), p)
            }
            // SF chevron.right: a row that goes somewhere.
            "chevronright" -> {
                c.drawLine(cx - dp(2.6f), cy - dp(6.6f), cx + dp(3.6f), cy, p)
                c.drawLine(cx + dp(3.6f), cy, cx - dp(2.6f), cy + dp(6.6f), p)
            }
            // SF play.rectangle: the YouTube tab.
            "playrect" -> {
                c.drawRoundRect(cx - dp(8.4f), cy - dp(6f), cx + dp(8.4f), cy + dp(6f), dp(2.4f), dp(2.4f), p)
                val tri = Path().apply {
                    moveTo(cx - dp(2f), cy - dp(3.2f)); lineTo(cx - dp(2f), cy + dp(3.2f))
                    lineTo(cx + dp(3.4f), cy); close()
                }
                c.drawPath(tri, fill)
            }
            // SF map: a folded map, three panels.
            "map" -> {
                val m = Path().apply {
                    moveTo(cx - dp(8.4f), cy - dp(5.6f)); lineTo(cx - dp(3f), cy - dp(7.6f))
                    lineTo(cx + dp(3f), cy - dp(5.6f)); lineTo(cx + dp(8.4f), cy - dp(7.6f))
                    lineTo(cx + dp(8.4f), cy + dp(5.6f)); lineTo(cx + dp(3f), cy + dp(7.6f))
                    lineTo(cx - dp(3f), cy + dp(5.6f)); lineTo(cx - dp(8.4f), cy + dp(7.6f)); close()
                }
                c.drawPath(m, p)
                c.drawLine(cx - dp(3f), cy - dp(7.6f), cx - dp(3f), cy + dp(5.6f), p)
                c.drawLine(cx + dp(3f), cy - dp(5.6f), cx + dp(3f), cy + dp(7.6f), p)
            }
            // SF person.crop.circle: the Contacts tab.
            "personcircle" -> {
                c.drawCircle(cx, cy, dp(8.2f), p)
                c.drawCircle(cx, cy - dp(2.2f), dp(2.9f), p)
                c.drawArc(RectF(cx - dp(5.4f), cy + dp(2.4f), cx + dp(5.4f), cy + dp(11.4f)), 200f, 140f, false, p)
            }
            // SF character.bubble: a speech bubble holding an A (Translate).
            "bubble" -> {
                val b = Path().apply {
                    addRoundRect(RectF(cx - dp(8f), cy - dp(7.4f), cx + dp(8f), cy + dp(4.6f)), dp(3.2f), dp(3.2f), Path.Direction.CW)
                    moveTo(cx - dp(4.6f), cy + dp(4.6f)); lineTo(cx - dp(5.4f), cy + dp(8.2f)); lineTo(cx - dp(1.4f), cy + dp(4.6f))
                }
                c.drawPath(b, p)
                val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = p.color; alpha = p.alpha
                    textAlign = Paint.Align.CENTER
                    typeface = Glass.font(context, Glass.SEMIBOLD)
                    textSize = dp(9.5f)
                }
                c.drawText("A", cx, cy + dp(2f), t)
            }
            // SF clock: a recent search.
            "clock" -> {
                c.drawCircle(cx, cy, dp(7.6f), p)
                c.drawLine(cx, cy, cx, cy - dp(4.4f), p)
                c.drawLine(cx, cy, cx + dp(3.2f), cy + dp(1.8f), p)
            }
            // SF arrow.up.right: what is trending.
            "trend" -> {
                c.drawLine(cx - dp(5.4f), cy + dp(5.4f), cx + dp(5.4f), cy - dp(5.4f), p)
                c.drawLine(cx + dp(5.4f), cy - dp(5.4f), cx - dp(1.8f), cy - dp(5.4f), p)
                c.drawLine(cx + dp(5.4f), cy - dp(5.4f), cx + dp(5.4f), cy + dp(1.8f), p)
            }
            // SF envelope: an email.
            "envelope" -> {
                c.drawRoundRect(cx - dp(8f), cy - dp(5.8f), cx + dp(8f), cy + dp(5.8f), dp(2f), dp(2f), p)
                val flap = Path().apply {
                    moveTo(cx - dp(7f), cy - dp(4.6f)); lineTo(cx, cy + dp(0.8f)); lineTo(cx + dp(7f), cy - dp(4.6f))
                }
                c.drawPath(flap, p)
            }
            // SF play.square.stack: the menu's GIFs, a square with play on a stack.
            "playstack" -> {
                c.drawRoundRect(cx - dp(6.4f), cy - dp(5f), cx + dp(7.6f), cy + dp(8.4f), dp(2.4f), dp(2.4f), p)
                c.drawLine(cx - dp(4.4f), cy - dp(7.4f), cx + dp(5.6f), cy - dp(7.4f), p)
                val tri = Path().apply {
                    moveTo(cx - dp(1.4f), cy - dp(1.4f)); lineTo(cx - dp(1.4f), cy + dp(4.8f))
                    lineTo(cx + dp(3.8f), cy + dp(1.7f)); close()
                }
                c.drawPath(tri, fill)
            }
            // SF slider.horizontal.3: three rails, a knob on each.
            "sliders" -> {
                for ((dy, kx) in listOf(-5f to 2.6f, 0f to -2.8f, 5f to 1f)) {
                    c.drawLine(cx - dp(7.4f), cy + dp(dy), cx + dp(7.4f), cy + dp(dy), p)
                    c.drawCircle(cx + dp(kx), cy + dp(dy), dp(1.9f), fill)
                }
            }
            // SF arrow.up: move a strip tool a place up.
            "arrowup" -> {
                c.drawLine(cx, cy + dp(6.4f), cx, cy - dp(6.4f), p)
                c.drawLine(cx, cy - dp(6.4f), cx - dp(4.8f), cy - dp(1.6f), p)
                c.drawLine(cx, cy - dp(6.4f), cx + dp(4.8f), cy - dp(1.6f), p)
            }
            // SF arrow.clockwise: the act panel's Try again.
            "retry" -> {
                val r = dp(6.6f)
                c.drawArc(android.graphics.RectF(cx - r, cy - r + dp(0.6f), cx + r, cy + r + dp(0.6f)),
                    -30f, 300f, false, p)
                val tipX = cx + dp(0.8f); val tipY = cy - r + dp(0.6f)
                c.drawLine(tipX, tipY, tipX - dp(3.6f), tipY - dp(3.4f), p)
                c.drawLine(tipX, tipY, tipX - dp(3.6f), tipY + dp(3.4f), p)
            }
            // SF line.3.horizontal: the clipboard's All.
            "lines" -> {
                for (dy in listOf(-5f, 0f, 5f)) c.drawLine(cx - dp(7f), cy + dp(dy), cx + dp(7f), cy + dp(dy), p)
            }
            // SF textformat: "Aa", the clipboard's Text.
            "textformat" -> {
                val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = p.color; alpha = p.alpha
                    textAlign = Paint.Align.CENTER
                    typeface = Glass.font(context, Glass.SEMIBOLD)
                    textSize = dp(14f)
                }
                c.drawText("Aa", cx, cy + dp(5f), t)
            }
            // SF link: two chain links, on the slant.
            "link" -> {
                c.save()
                c.rotate(-45f, cx, cy)
                val w = dp(8.4f); val h = dp(5.2f); val r = h / 2
                c.drawRoundRect(cx - w - dp(0.6f), cy - h / 2, cx + dp(1.4f), cy + h / 2, r, r, p)
                c.drawRoundRect(cx - dp(1.4f), cy - h / 2, cx + w + dp(0.6f), cy + h / 2, r, r, p)
                c.restore()
            }
            // SF photo: a frame, a sun and a hill.
            "photo" -> {
                c.drawRoundRect(cx - dp(8f), cy - dp(6.4f), cx + dp(8f), cy + dp(6.4f), dp(2.2f), dp(2.2f), p)
                c.drawCircle(cx - dp(3.2f), cy - dp(2.2f), dp(1.5f), fill)
                val hill = Path().apply {
                    moveTo(cx - dp(8f), cy + dp(4.6f))
                    lineTo(cx - dp(2.4f), cy + dp(0.4f))
                    lineTo(cx + dp(1.2f), cy + dp(3f))
                    lineTo(cx + dp(4f), cy + dp(0.6f))
                    lineTo(cx + dp(8f), cy + dp(4f))
                }
                c.drawPath(hill, p)
            }
            // SF pin / pin.slash: a pushpin, upright; slashed to unpin.
            "pin", "pinslash" -> {
                val head = Path().apply {
                    moveTo(cx - dp(4f), cy - dp(7.6f)); lineTo(cx + dp(4f), cy - dp(7.6f))
                    lineTo(cx + dp(3f), cy - dp(1.6f)); lineTo(cx + dp(5.6f), cy + dp(1.6f))
                    lineTo(cx - dp(5.6f), cy + dp(1.6f)); lineTo(cx - dp(3f), cy - dp(1.6f)); close()
                }
                c.drawPath(head, p)
                c.drawLine(cx, cy + dp(1.6f), cx, cy + dp(8f), p)
                if (kind == "pinslash") c.drawLine(cx - dp(7.6f), cy - dp(7.6f), cx + dp(7.6f), cy + dp(7.6f), p)
            }
            // SF trash: a bin with its lid.
            "trash" -> {
                c.drawLine(cx - dp(7.4f), cy - dp(5f), cx + dp(7.4f), cy - dp(5f), p)
                c.drawLine(cx - dp(2.4f), cy - dp(7.6f), cx + dp(2.4f), cy - dp(7.6f), p)
                c.drawLine(cx - dp(2.4f), cy - dp(7.6f), cx - dp(2.4f), cy - dp(5f), p)
                c.drawLine(cx + dp(2.4f), cy - dp(7.6f), cx + dp(2.4f), cy - dp(5f), p)
                val bin = Path().apply {
                    moveTo(cx - dp(5.8f), cy - dp(5f)); lineTo(cx - dp(5f), cy + dp(7.4f))
                    lineTo(cx + dp(5f), cy + dp(7.4f)); lineTo(cx + dp(5.8f), cy - dp(5f))
                }
                c.drawPath(bin, p)
                c.drawLine(cx - dp(1.8f), cy - dp(1.8f), cx - dp(1.6f), cy + dp(4.4f), p)
                c.drawLine(cx + dp(1.8f), cy - dp(1.8f), cx + dp(1.6f), cy + dp(4.4f), p)
            }
            // SF hand.raised, reduced: an open palm.
            "hand" -> {
                val palm = Path().apply {
                    moveTo(cx - dp(5f), cy + dp(1f))
                    lineTo(cx - dp(5f), cy - dp(4.6f))
                    moveTo(cx - dp(1.8f), cy - dp(1f)); lineTo(cx - dp(1.8f), cy - dp(7.4f))
                    moveTo(cx + dp(1.4f), cy - dp(1f)); lineTo(cx + dp(1.4f), cy - dp(7f))
                    moveTo(cx + dp(4.6f), cy - dp(0.4f)); lineTo(cx + dp(4.6f), cy - dp(5.4f))
                }
                c.drawPath(palm, p)
                c.drawArc(RectF(cx - dp(6.6f), cy - dp(4f), cx + dp(6.2f), cy + dp(8.4f)), 0f, 180f, false, p)
            }
            // The detail kinds (iOS DetailKind symbols): person, at, phone,
            // house, the rupee, wallet.bifold, and tag.
            "person" -> {
                c.drawCircle(cx, cy - dp(3.4f), dp(3.4f), p)
                c.drawArc(RectF(cx - dp(7f), cy + dp(1.6f), cx + dp(7f), cy + dp(13.6f)), 180f, 180f, false, p)
            }
            "at" -> {
                val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = p.color; alpha = p.alpha
                    textAlign = Paint.Align.CENTER
                    typeface = Glass.font(context, Glass.MEDIUM)
                    textSize = dp(19f)
                }
                c.drawText("@", cx, cy + dp(6.6f), t)
            }
            "phone" -> {
                val handset = Path().apply {
                    moveTo(cx - dp(5.6f), cy - dp(7.4f))
                    lineTo(cx - dp(2.4f), cy - dp(7.6f))
                    lineTo(cx - dp(1.2f), cy - dp(3.4f))
                    lineTo(cx - dp(3.2f), cy - dp(1.8f))
                    quadTo(cx - dp(1f), cy + dp(2.4f), cx + dp(2f), cy + dp(3.2f))
                    lineTo(cx + dp(3.6f), cy + dp(1.2f))
                    lineTo(cx + dp(7.6f), cy + dp(2.6f))
                    lineTo(cx + dp(7.4f), cy + dp(5.8f))
                    quadTo(cx + dp(6.4f), cy + dp(8f), cx + dp(3.4f), cy + dp(7.4f))
                    quadTo(cx - dp(6.4f), cy + dp(3.6f), cx - dp(7.6f), cy - dp(4.6f))
                    quadTo(cx - dp(7.6f), cy - dp(7.2f), cx - dp(5.6f), cy - dp(7.4f))
                    close()
                }
                c.drawPath(handset, p)
            }
            "house" -> {
                val roof = Path().apply {
                    moveTo(cx - dp(8f), cy - dp(0.6f)); lineTo(cx, cy - dp(7.6f)); lineTo(cx + dp(8f), cy - dp(0.6f))
                }
                c.drawPath(roof, p)
                val walls = Path().apply {
                    moveTo(cx - dp(5.8f), cy - dp(2.4f)); lineTo(cx - dp(5.8f), cy + dp(7f))
                    lineTo(cx + dp(5.8f), cy + dp(7f)); lineTo(cx + dp(5.8f), cy - dp(2.4f))
                }
                c.drawPath(walls, p)
                c.drawRoundRect(cx - dp(1.8f), cy + dp(2f), cx + dp(1.8f), cy + dp(7f), dp(0.8f), dp(0.8f), p)
            }
            "rupee" -> {
                c.drawLine(cx - dp(5f), cy - dp(6.8f), cx + dp(5f), cy - dp(6.8f), p)
                c.drawLine(cx - dp(5f), cy - dp(3f), cx + dp(5f), cy - dp(3f), p)
                c.drawArc(RectF(cx - dp(7.6f), cy - dp(6.8f), cx + dp(1.4f), cy + dp(0.8f)), -90f, 180f, false, p)
                c.drawLine(cx - dp(3.2f), cy + dp(0.8f), cx + dp(4.4f), cy + dp(7.6f), p)
                c.drawLine(cx - dp(5f), cy + dp(0.8f), cx - dp(3.2f), cy + dp(0.8f), p)
            }
            "wallet" -> {
                c.drawRoundRect(cx - dp(8f), cy - dp(6f), cx + dp(8f), cy + dp(6.4f), dp(2.6f), dp(2.6f), p)
                c.drawRoundRect(cx + dp(1.6f), cy - dp(2.2f), cx + dp(8f), cy + dp(2.8f), dp(1.6f), dp(1.6f), p)
                c.drawCircle(cx + dp(4.6f), cy + dp(0.3f), dp(0.9f), fill)
            }
            "tag" -> {
                val body = Path().apply {
                    moveTo(cx - dp(7.6f), cy - dp(7.6f)); lineTo(cx - dp(0.6f), cy - dp(7.6f))
                    lineTo(cx + dp(7.8f), cy + dp(0.8f)); lineTo(cx + dp(0.8f), cy + dp(7.8f))
                    lineTo(cx - dp(7.6f), cy - dp(0.6f)); close()
                }
                c.drawPath(body, p)
                c.drawCircle(cx - dp(3.8f), cy - dp(3.8f), dp(1.2f), fill)
            }
            // SF plus, for "Add".
            "plus" -> {
                c.drawLine(cx - dp(7f), cy, cx + dp(7f), cy, p)
                c.drawLine(cx, cy - dp(7f), cx, cy + dp(7f), p)
            }
            // A game controller: a rounded body, a cross on the left, two buttons.
            "games" -> {
                c.drawRoundRect(cx - dp(9f), cy - dp(5.6f), cx + dp(9f), cy + dp(5.6f),
                    dp(5.6f), dp(5.6f), p)
                c.drawLine(cx - dp(6f), cy, cx - dp(2f), cy, p)
                c.drawLine(cx - dp(4f), cy - dp(2f), cx - dp(4f), cy + dp(2f), p)
                c.drawCircle(cx + dp(3.2f), cy + dp(1f), dp(1f), fill)
                c.drawCircle(cx + dp(5.6f), cy - dp(1.4f), dp(1f), fill)
            }
        }
    }

    /** The glyph as a drawable [size] px square, to lead a line of text (a
     *  TextView's start drawable), so the line stays one view. */
    fun asDrawable(size: Int): android.graphics.drawable.Drawable {
        layout(0, 0, size, size)
        val icon = this
        return object : android.graphics.drawable.Drawable() {
            override fun draw(c: Canvas) {
                c.save()
                c.translate(bounds.left.toFloat(), bounds.top.toFloat())
                icon.draw(c)
                c.restore()
            }
            override fun getIntrinsicWidth() = size
            override fun getIntrinsicHeight() = size
            override fun setAlpha(alpha: Int) {}
            override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {}
            override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    /** A four-pointed star, the sparkle in Ask and Rewrite. */
    private fun sparkle(c: Canvas, x: Float, y: Float, r: Float) {
        val k = r * 0.28f
        val path = Path().apply {
            moveTo(x, y - r)
            quadTo(x + k, y - k, x + r, y)
            quadTo(x + k, y + k, x, y + r)
            quadTo(x - k, y + k, x - r, y)
            quadTo(x - k, y - k, x, y - r)
            close()
        }
        c.drawPath(path, fill)
    }

    companion object {
        /** Every tool, in the website's order first; titles as the grid shows them. */
        val TOOLS = listOf(
            "search" to "Search", "rewrite" to "Rewrite", "translate" to "Translate",
            "vault" to "Vault", "calendar" to "Calendar", "tempmail" to "Temp mail",
            "clipboard" to "Clipboard", "gifs" to "GIFs",
            "ask" to "Ask Glyf", "dictation" to "Voice", "glyfs" to "My glyfs",
            "pay" to "Pay", "games" to "Games", "settings" to "Settings",
        )

        /** Tools that were folded into another (user, 2026-09-29): Emoji has
         *  its own key, so the menu offers GIFs; Keys said what My glyfs
         *  says; Shorthand lives in the vault. */
        private val RETIRED = mapOf("emoji" to "gifs", "keys" to "glyfs", "shorthand" to "vault")

        /** The tool a saved id stands for now: an order or a strip saved
         *  before still finds its tools. */
        fun canonical(id: String): String = RETIRED[id] ?: id
    }
}
