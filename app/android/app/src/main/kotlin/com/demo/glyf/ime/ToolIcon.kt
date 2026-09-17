package com.demo.glyf.ime

import android.content.Context
import android.graphics.Canvas
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

    private fun dp(v: Float) = v * resources.displayMetrics.density * scale

    override fun onDraw(c: Canvas) {
        p.strokeWidth = dp(1.6f)
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
            "settings", "gear" -> {
                p.strokeWidth = dp(2.2f)
                c.drawCircle(cx, cy, dp(3.1f), p)
                for (i in 0 until 6) {
                    val a = Math.toRadians(i * 60.0)
                    val r1 = dp(5.4f)
                    val r2 = dp(7.4f)
                    c.drawLine(
                        cx + (r1 * Math.cos(a)).toFloat(), cy + (r1 * Math.sin(a)).toFloat(),
                        cx + (r2 * Math.cos(a)).toFloat(), cy + (r2 * Math.sin(a)).toFloat(), p)
                }
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
            "translate" -> {
                val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = p.color; alpha = p.alpha
                    textAlign = Paint.Align.CENTER
                    typeface = Typeface.DEFAULT_BOLD
                }
                t.textSize = dp(11f)
                c.drawText("A", cx - dp(3.4f), cy + dp(0.6f), t)
                t.textSize = dp(9.5f)
                c.drawText("文", cx + dp(3.8f), cy + dp(6.4f), t)
            }
            "notes" -> {
                c.drawRoundRect(cx - dp(6.4f), cy - dp(7f), cx + dp(6.4f), cy + dp(7f),
                    dp(2.4f), dp(2.4f), p)
                c.drawLine(cx - dp(3.4f), cy - dp(2.6f), cx + dp(3.4f), cy - dp(2.6f), p)
                c.drawLine(cx - dp(3.4f), cy + dp(0.8f), cx + dp(3.4f), cy + dp(0.8f), p)
            }
            "rewrite", "bolt" -> {
                // A wand: the stick, and the sparkle it leaves.
                c.drawLine(cx - dp(6.4f), cy + dp(6.4f), cx + dp(2.4f), cy - dp(2.4f), p)
                sparkle(c, cx + dp(4.6f), cy - dp(4.6f), dp(3.4f))
                sparkle(c, cx - dp(3.6f), cy - dp(5.6f), dp(1.8f))
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
            "shorthand" -> {
                c.drawLine(cx - dp(7f), cy - dp(4f), cx + dp(1f), cy - dp(4f), p)
                c.drawLine(cx - dp(7f), cy + dp(0.4f), cx - dp(1f), cy + dp(0.4f), p)
                c.drawLine(cx - dp(7f), cy + dp(4.8f), cx - dp(2.4f), cy + dp(4.8f), p)
                c.drawLine(cx + dp(4.4f), cy - dp(0.6f), cx + dp(4.4f), cy + dp(7f), p)
                c.drawLine(cx + dp(0.6f), cy + dp(3.2f), cx + dp(8.2f), cy + dp(3.2f), p)
            }
            "keys" -> {
                c.drawRoundRect(cx - dp(8.6f), cy - dp(5.6f), cx + dp(8.6f), cy + dp(5.6f),
                    dp(2f), dp(2f), p)
                for (row in 0 until 2) for (col in 0 until 4) {
                    c.drawCircle(cx - dp(4.8f) + col * dp(3.2f), cy - dp(2.2f) + row * dp(2.8f),
                        dp(0.7f), fill)
                }
                c.drawLine(cx - dp(3.4f), cy + dp(3f), cx + dp(3.4f), cy + dp(3f), p)
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
            "pay" -> {
                c.drawRoundRect(cx - dp(8.4f), cy - dp(5.8f), cx + dp(8.4f), cy + dp(5.8f),
                    dp(2f), dp(2f), p)
                c.drawLine(cx - dp(8.4f), cy - dp(2f), cx + dp(8.4f), cy - dp(2f), p)
                c.drawLine(cx - dp(5.6f), cy + dp(2.8f), cx - dp(1.6f), cy + dp(2.8f), p)
            }
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
            "vault" to "Vault", "calendar" to "Calendar", "clipboard" to "Clipboard", "emoji" to "Emoji",
            "ask" to "Ask Glyf", "dictation" to "Voice", "glyfs" to "My glyfs",
            "shorthand" to "Shorthand", "keys" to "Keys", "pay" to "Pay",
            "settings" to "Settings",
        )
    }
}
