package com.arpit.glyf.ime

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * A g menu sponsor's own panel (Uniswap, Definitive): SponsorMenu.entries
 * as inset-grouped rows, the way iOS's shell lists them (GlyfShell's
 * sponsorScreen). Every row opens something; nothing runs on the tap that
 * opened the panel. Definitive's chain is a two-way switch, Base or Solana.
 */
object SponsorPanel {

    fun fill(ctx: Context, rows: ShellRows, sponsor: SponsorMenu.Sponsor, typed: String,
             onOption: (SponsorMenu.Option) -> Unit, onChain: (String) -> Unit) {
        for (entry in SponsorMenu.entries(sponsor, typed, SponsorMenu.flashChain)) {
            when (entry) {
                is SponsorMenu.Entry.Header -> rows.header(entry.title)
                is SponsorMenu.Entry.Row -> rows.row(ShellRows.Row(entry.title, detail = entry.detail,
                    leading = leading(ctx, entry.icon), qaId = "sponsor:${entry.option.id}") { onOption(entry.option) })
                SponsorMenu.Entry.ChainPicker -> rows.row(ShellRows.Row("Chain", chevron = false,
                    trailing = segmented(ctx, SponsorMenu.FLASH_CHAINS, SponsorMenu.flashChain, onChain),
                    qaId = "sponsor:chain"))
            }
        }
        rows.flush()
    }

    private fun dp(ctx: Context, v: Float) = Math.round(v * ctx.resources.displayMetrics.density)

    /** "chain:base" is the chain's mark; anything else a line glyph in the
     *  rows' grey chip. */
    fun leading(ctx: Context, icon: String): View {
        if (icon.startsWith("chain:")) return ChainMarkView(ctx, icon.removePrefix("chain:"))
        return FrameLayout(ctx).apply {
            background = Glass.card(ctx, fill = Glass.fillField, radius = 7f)
            addView(TradeGlyph(ctx, icon, Glass.textPrimary).apply { scale = 0.85f },
                FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        }
    }

    /** Base | Solana, the picked one on a card. */
    private fun segmented(ctx: Context, chains: List<String>, picked: String, onPick: (String) -> Unit): View {
        val track = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            background = Glass.pill(Glass.fillSoft)
            setPadding(dp(ctx, 2f), dp(ctx, 2f), dp(ctx, 2f), dp(ctx, 2f))
        }
        for (chain in chains) {
            track.addView(TextView(ctx).apply {
                text = TradeIntent.chainLabels[chain] ?: chain
                Glass.style(this, 13f, if (chain == picked) Glass.SEMIBOLD else Glass.REGULAR,
                    if (chain == picked) Glass.textPrimary else Glass.textSecondary)
                gravity = Gravity.CENTER
                setPadding(dp(ctx, 12f), 0, dp(ctx, 12f), 0)
                if (chain == picked) background = Glass.pill(Glass.surfaceCard)
                setTag(com.arpit.glyf.R.id.qa_id, "sponsor:chain:$chain")
                setOnClickListener { if (chain != picked) onPick(chain) }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(ctx, 26f)))
        }
        return track
    }

    /** The g menu's top row: one card per sponsor, its mark and its name,
     *  the tiles' own fill and corners (GlyfShell.buildSponsorRow). */
    fun card(ctx: Context, sponsor: SponsorMenu.Sponsor, onTap: () -> Unit): View = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        background = GradientDrawable().apply { cornerRadius = dp(ctx, 14f).toFloat(); setColor(Glass.surfaceCard) }
        contentDescription = sponsor.title
        setTag(com.arpit.glyf.R.id.qa_id, "shell:sponsor:${sponsor.id}")
        addView(SponsorMarkView(ctx, sponsor), LinearLayout.LayoutParams(dp(ctx, 26f), dp(ctx, 26f)).apply { rightMargin = dp(ctx, 8f) })
        addView(TextView(ctx).apply {
            text = sponsor.title
            Glass.style(this, 13f, Glass.SEMIBOLD)
            maxLines = 1
        })
        setOnClickListener { onTap() }
    }
}
