package com.arpit.glyf.ime

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Rows of an inset-grouped list, the way iOS's keyboard draws them (GlyfShell
 * ShellCell, itself the way Settings draws one): the rows of a group share
 * one rounded card 12dp in from the panel's edges, a hairline runs between
 * them from where the words start, a section's title sits above its group in
 * small capitals, and the whole row answers a tap.
 */
class ShellRows(private val ctx: Context, private val body: LinearLayout,
                /** 44 in Glyf's look; 52 in the Glass look, where every row
                 *  has room for a second line (iOS twoLineHeight). */
                private val rowH: Float = ROW_H) {

    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Float) = Math.round(v * density)

    companion object {
        const val ROW_H = 44f
        const val TWO_LINE_H = 52f
        const val HEADER_H = 32f
        const val FOOTER_H = 32f
        /** Between two groups when no title separates them. */
        const val GROUP_GAP = 10f
        const val SIDE = 12f
        const val TEXT_X = 16f
        const val RADIUS = 12f
    }

    /** A row of the current group: what it shows and what it does. */
    class Row(
        val title: String,
        /** A tool's glyph in the grey chip at the start, or null. */
        val glyph: String? = null,
        /** A letter in the chip instead of a glyph (";" for shorthand). */
        val letter: String? = null,
        /** Grey words at the right, beside the chevron. */
        val detail: String? = null,
        /** A chevron at the end: the row goes somewhere. */
        val chevron: Boolean = true,
        /** A control at the end instead (a switch), laid out by the row. */
        val trailing: View? = null,
        /** Grey words under the title (the Glass look's vault: a detail's
         *  value, what a shortcut types out). */
        val subtitle: String? = null,
        val qaId: String? = null,
        val titleColor: Int? = null,
        val centered: Boolean = false,
        val onTap: (() -> Unit)? = null,
    )

    private var pending = mutableListOf<Row>()
    private var afterHeader = false
    private var anyAbove = false

    /** A section's title over the group that follows. */
    fun header(title: String) {
        flush()
        body.addView(TextView(ctx).apply {
            text = title.uppercase()
            Glass.style(this, 13f, Glass.REGULAR, Glass.textSecondary)
            letterSpacing = 0.03f
            gravity = Gravity.BOTTOM
            setPadding(dp(SIDE + TEXT_X), 0, dp(SIDE + TEXT_X), dp(6f))
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(HEADER_H)))
        afterHeader = true
        anyAbove = true
    }

    /** A quiet line under a group, centred (iOS .info). */
    fun footer(text: String, qaId: String? = null) {
        flush()
        body.addView(TextView(ctx).apply {
            this.text = text
            Glass.style(this, 13f, Glass.REGULAR, Glass.textSecondary)
            gravity = Gravity.CENTER
            qaId?.let { setTag(com.arpit.glyf.R.id.qa_id, it) }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(FOOTER_H)))
        afterHeader = false
        anyAbove = true
    }

    fun row(row: Row) { pending.add(row) }

    /** Ends the group: its rows go in as one card. */
    fun flush() {
        if (pending.isEmpty()) return
        val gapTop = when {
            afterHeader -> 0f
            anyAbove -> GROUP_GAP
            else -> 6f
        }
        for ((i, r) in pending.withIndex()) {
            val first = i == 0
            val last = i == pending.lastIndex
            body.addView(rowView(r, first, last), LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(rowH)).apply {
                leftMargin = dp(SIDE); rightMargin = dp(SIDE)
                if (first) topMargin = dp(gapTop)
            })
        }
        pending = mutableListOf()
        afterHeader = false
        anyAbove = true
    }

    private fun cardFill(first: Boolean, last: Boolean, color: Int) = GradientDrawable().apply {
        val r = RADIUS * density
        val top = if (first) r else 0f
        val bottom = if (last) r else 0f
        cornerRadii = floatArrayOf(top, top, top, top, bottom, bottom, bottom, bottom)
        setColor(color)
    }

    private fun rowView(r: Row, first: Boolean, last: Boolean): View {
        val row = FrameLayout(ctx)
        // A finger on a row darkens its card a touch, as Settings does.
        row.background = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_pressed),
                cardFill(first, last, blend(Glass.surfaceCard, Glass.textPrimary, 0.08f)))
            addState(intArrayOf(), cardFill(first, last, Glass.surfaceCard))
        }
        r.qaId?.let { row.setTag(com.arpit.glyf.R.id.qa_id, it) }
        r.onTap?.let { tap -> row.setOnClickListener { tap() } }
        val line = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(TEXT_X), 0, dp(TEXT_X), 0)
        }
        var textX = TEXT_X
        if (r.glyph != null || r.letter != null) {
            val chip = FrameLayout(ctx).apply {
                background = Glass.card(ctx, fill = Glass.fillField, radius = 7f)
            }
            if (r.glyph != null) chip.addView(ToolIcon(ctx, r.glyph, Glass.textPrimary).apply {
                solid = true; weight = 1.7f; scale = 0.78f
            }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            else chip.addView(TextView(ctx).apply {
                text = r.letter
                Glass.style(this, 14f, Glass.BOLD, Glass.accentPrimary)
                gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            line.addView(chip, LinearLayout.LayoutParams(dp(28f), dp(28f)).apply { rightMargin = dp(12f) })
            textX += 28f + 12f
        }
        val title = TextView(ctx).apply {
            text = r.title
            Glass.style(this, 15f, Glass.REGULAR, r.titleColor ?: Glass.textPrimary)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            if (r.centered) gravity = Gravity.CENTER
        }
        if (r.subtitle == null) {
            line.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        } else {
            // iOS's two lines: the title's top 8 down the row, the value's 28.
            val pair = FrameLayout(ctx)
            pair.addView(title, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(19f)).apply {
                topMargin = dp(8f)
            })
            title.gravity = Gravity.CENTER_VERTICAL
            pair.addView(TextView(ctx).apply {
                text = r.subtitle
                Glass.style(this, 15f, Glass.REGULAR, Glass.textSecondary)
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_VERTICAL
            }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(18f)).apply {
                topMargin = dp(27f)
            })
            line.addView(pair, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        }
        if (r.detail != null) line.addView(TextView(ctx).apply {
            text = r.detail
            Glass.style(this, 15f, Glass.REGULAR, Glass.textSecondary)
            maxLines = 1
            gravity = Gravity.END
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(10f) })
        if (r.trailing != null) {
            line.addView(r.trailing, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(8f) })
        } else if (r.chevron && r.onTap != null) {
            line.addView(ToolIcon(ctx, "chevronright", Glass.withAlpha(Glass.textSecondary, 0.55f)).apply {
                weight = 2.1f; scale = 0.72f
                setTint(Glass.withAlpha(Glass.textSecondary, 0.55f))
            }, LinearLayout.LayoutParams(dp(14f), dp(20f)).apply { leftMargin = dp(8f) })
        }
        row.addView(line, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT))
        if (!last) row.addView(View(ctx).apply { setBackgroundColor(Glass.strokeSeparator) },
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, maxOf(1, dp(0.5f)), Gravity.BOTTOM)
                .apply { leftMargin = dp(textX) })
        return row
    }

    private fun blend(a: Int, b: Int, t: Float) = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt())
}
