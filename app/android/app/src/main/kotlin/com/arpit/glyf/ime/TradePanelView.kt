package com.arpit.glyf.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * A trade, set in the keyboard before it's signed: Uniswap swaps and
 * Definitive's Flash orders on one panel over the keys, the twin of
 * TradeSurface.swift in the Android Buy panel's look (PayPanelView's You pay
 * / You get cards, 2026-10-06). Every value is tapped to change: the amount
 * and prices on the panel's own digits, tokens from a list (Uniswap's, or
 * an address pasted from the clipboard), chains from a list with their own
 * marks. One card per side, an order's values as rows, one button. The
 * quote is the server's (/uniswap/quote, /flash/search, /near/quote for
 * NEAR Intents across chains) or Jupiter's prices on Solana; the button
 * hands the trade to the app, which asks MetaMask or Phantom. The keyboard
 * holds no key and signs nothing (SPEC §1.5).
 */
@SuppressLint("ViewConstructor", "SetTextI18n")
class TradePanelView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    private val backendURL: String,
    /** The connected MetaMask's address (shared settings `evmAddress`). */
    private val evmAddress: String?,
    /** The connected Phantom's address (shared settings `walletAddress`). */
    private val solanaAddress: String?,
    start: TradeIntent,
    /** The trade as set, for the app: glyf://open?path=trade?… */
    private val onHandOff: (Map<String, String>) -> Unit,
    /** No wallet for this chain yet: the app's Wallet page. */
    private val onConnect: () -> Unit,
    private val onToast: (String) -> Unit,
    /** The strip's name for the panel and its mark (TradeQuote.headerIcon),
     *  when the name changes. */
    private val onTitle: (String, String) -> Unit,
    /** The copy, read on the Paste address tap. */
    private val clipText: () -> String?,
    /** A token search is being typed (true): the letter keys come up under
     *  the panel's search strip; false: back to the panel's own height. */
    private val onSearching: (Boolean) -> Unit = {},
    /** Recipients the app last paid through NEAR Intents (shared settings
     *  `nearRecent`), sent with a NEAR quote so Guard can spot a lookalike. */
    private val nearRecent: List<String> = emptyList(),
) : FrameLayout(ctx), StripField {

    var intent: TradeIntent = start
        private set

    /** What the panel shows: the trade, a value being typed, or a picker. */
    private sealed class Mode {
        object Panel : Mode()
        data class Number(val field: TradeField) : Mode()
        data class Tokens(val side: TradeEdit.Side) : Mode()
        data class Chains(val side: TradeEdit.Side) : Mode()
        /** A token search typed with the keyboard's keys (iOS's .search). */
        data class Search(val side: TradeEdit.Side) : Mode()
    }

    /** The search strip while it takes the keys (GlyfIME feeds it). */
    val typing: StripField? get() = if (mode is Mode.Search) this else null

    // StripField: the search's words; Return goes back to the list.
    override val stripText: String get() = searchText
    override fun setStripText(text: String) = searchChanged(text)
    override fun endStrip() {
        (mode as? Mode.Search)?.let { setMode(Mode.Tokens(it.side)) }
    }

    /** The strip's name as last said: told again only when the kind changes. */
    private var shownTitle = TradeQuote.headerTitle(start)

    private var mode: Mode = Mode.Panel
    private var typed = ""

    private val main = Handler(Looper.getMainLooper())
    private val blue = Color.rgb(0x0A, 0x84, 0xFF)

    // Live numbers.
    private var quote: TradeQuote.Quote? = null
    /** NEAR Intents' answer (time, what's paid for a send, Guard's words). */
    private var near: NearQuote? = null
    /** Earn's answer (its words, vault, APY, time), in Earn mode. */
    private var earn: EarnQuote? = null
    private var earnError: String? = null
    private var marketPrice: Double? = null
    private var asking = true
    private var serial = 0
    /** Whole tokens held by symbol, per chain, once /evm/balances answers. */
    private val held = mutableMapOf<String, Map<String, Double>>()
    /** A send's recipient: the address its name points at on the send's
     *  chain (GET /names/resolve), once looked up; the typed address as is. */
    private var resolved: String? = null
    /** The name points nowhere (or nowhere on this chain), or the lookup
     *  failed: the button says which, and nothing is handed on. */
    private var resolveProblem: String? = null
    /** The "name|chain" last asked, so a token change doesn't ask again. */
    private var resolvedFor: String? = null
    /** Picker rows per chain (server answer merged over the built-in few). */
    private val tokenRows = mutableMapOf<String, List<TokenPick>>()
    /** Logos and addresses of tokens on the panel, by "chain|SYMBOL". */
    private val known = mutableMapOf<String, TokenPick>()
    /** The token search as typed, its rows, and whether the server is asked. */
    private var searchText = ""
    private var searchResults: List<TokenPick> = emptyList()
    private var searchLoading = false
    private var searchSerial = 0

    private val isSwap get() = intent.kind == TradeIntent.Kind.SWAP
    /** The panel quotes it as it changes: a swap, or a NEAR Intents send. */
    private val quotes get() = TradeQuote.quotes(intent)
    private val nearSend get() = TradeQuote.nearSend(intent)
    /** Earn mode: idle coins into a vault, or back out (NEAR Intents Earn). */
    private val isEarn get() = intent.kind == TradeIntent.Kind.EARN
    private val red = Color.rgb(0xFF, 0x3B, 0x30)
    private val amber get() = if (palette.darkChrome) Color.rgb(0xFF, 0xC2, 0x47) else Color.rgb(0xB8, 0x73, 0x00)
    private val buyChain get() = intent.buyChain ?: intent.chainName
    private val wallet: String? get() = if (intent.chainName == "solana") solanaAddress else evmAddress
    /** The side a Flash order's token pill changes (its asset). */
    private val assetSide get() = if (TradeEdit.sells(intent)) TradeEdit.Side.SELL else TradeEdit.Side.BUY

    private val body = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(ctx).apply {
        isVerticalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_NEVER
        addView(body)
    }

    companion object {
        private val pool = Executors.newFixedThreadPool(2)
        /** GET /near/earn/vaults, read once a session (everything out has no quote). */
        private var vaultList: JSONObject? = null
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun soft(a: Int, c: Int) = Color.argb(a, Color.red(c), Color.green(c), Color.blue(c))

    init {
        setBackgroundColor(palette.board)
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        render()
        loadBalances(intent.chainName)
        loadLive()
        prefetchTokens(intent.chainName)
    }

    // MARK: building blocks

    private fun label(text: String, size: Float, bold: Boolean, color: Int) = TextView(context).apply {
        this.text = text; textSize = size; setTextColor(color); maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun card() = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        background = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(palette.card) }
        setPadding(dp(12), dp(7), dp(10), dp(8))
    }

    private fun pill() = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(soft(20, palette.ink)) }

    private fun wrap() = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    private fun full(h: Int = LinearLayout.LayoutParams.WRAP_CONTENT, top: Int = 0) =
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, h).apply { topMargin = top }

    /** A chain's mark and name, ▾ when there is another to pick. */
    private fun chainPill(chain: String, qa: String, enabled: Boolean, onTap: () -> Unit) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = pill()
        setPadding(dp(6), dp(2), dp(8), dp(2))
        setTag(com.arpit.glyf.R.id.qa_id, qa)
        addView(ChainMarkView(context, chain), LinearLayout.LayoutParams(dp(14), dp(14)).apply { rightMargin = dp(5) })
        addView(label((TradeIntent.chainLabels[chain] ?: TradeIntent.capitalized(chain)) + if (enabled) " ▾" else "",
            11.5f, true, palette.ink))
        if (enabled) setOnClickListener { onTap() }
    }

    /** A token: its logo and symbol on a soft pill, ▾ when it can change. */
    private fun tokenPill(symbol: String, logo: String?, qa: String, onTap: (() -> Unit)?, compact: Boolean = false) =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = pill()
            setPadding(dp(5), dp(4), dp(if (onTap != null && !compact) 10 else 9), dp(4))
            setTag(com.arpit.glyf.R.id.qa_id, qa)
            contentDescription = TradeQuote.display(symbol)
            val d = dp(if (compact) 18 else 20)
            addView(TokenLogoView(context, symbol, logo), LinearLayout.LayoutParams(d, d).apply { rightMargin = dp(6) })
            addView(label(TradeQuote.display(symbol) + if (onTap != null && !compact) " ▾" else "",
                if (compact) 13f else 14f, true, palette.ink))
            if (onTap != null) setOnClickListener { onTap() }
        }

    /** A token's logo URL on [chain], from the rows the server sent. */
    private fun logo(symbol: String, chain: String): String? =
        known["$chain|${symbol.uppercase()}"]?.logo
            ?: tokenRows[chain]?.firstOrNull { it.symbol.equals(symbol, ignoreCase = true) }?.logo
            // A coin no token list here carries (BTC, ZEC, NEAR…): its own picture, not a letter.
            ?: TradeIntent.coinLogos[symbol.uppercase()]

    /** One side: its key and chain, the amount (a tap types it) and its
     *  token, a line under them. */
    private fun sideCard(key: String, chain: String, chainEnabled: Boolean, onChain: () -> Unit,
                         amount: String, placeholder: Boolean, onAmount: (() -> Unit)?,
                         token: String, onToken: (() -> Unit)?, sub: String, id: String): View {
        val tokenLogo = logo(token, chain)
        val c = card()
        c.setTag(com.arpit.glyf.R.id.qa_id, "trade:$id")
        val top = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        top.addView(label(key, 12f, true, palette.inkSoft), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        top.addView(chainPill(chain, "trade:$id:chain", chainEnabled, onChain))
        c.addView(top)
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val col = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        col.addView(label(amount, 22f, true, if (placeholder) palette.inkSoft else palette.ink).apply {
            setTag(com.arpit.glyf.R.id.qa_id, "trade:$id:amount")
        })
        col.addView(label(sub, 11.5f, false, palette.inkSoft))
        if (onAmount != null) col.setOnClickListener { onAmount() }
        row.addView(col, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(tokenPill(token, tokenLogo, "trade:$id:token", onToken))
        c.addView(row, full(top = dp(2)))
        return c
    }

    // MARK: render

    private fun render() {
        body.removeAllViews()
        body.setPadding(dp(10), dp(4), dp(10), dp(8))
        when (val m = mode) {
            Mode.Panel -> renderPanel()
            is Mode.Number -> renderNumber(m.field)
            is Mode.Tokens -> renderTokens(m.side)
            is Mode.Chains -> renderChains(m.side)
            is Mode.Search -> renderSearch(m.side)
        }
    }

    private fun renderPanel() {
        val i = intent
        val q = quote
        val top = if (isSwap) i.sell else TradeEdit.asset(i)
        val chains = TradeEdit.chains(i).size > 1
        if (isSwap) {
            val reversed = i.buyAmount != null
            val payAmount = if (reversed) q?.out?.let { "≈ " + TradeQuote.amount(it) } ?: if (asking) "…" else "0"
                else TradeEdit.shown(TradeField.AMOUNT, i)
            val paySub = mutableListOf<String>()
            q?.inUsd?.let { paySub.add(TradeQuote.approx(it)) }
            balance(i.sell, i.chainName)?.takeIf { it > 0 }?.let { paySub.add("Balance ${PayPanelView.compact(it)}") }
            body.addView(sideCard("You pay", i.chainName, chains, { openChains(TradeEdit.Side.SELL) },
                payAmount, (if (reversed) q?.out == null else TradeEdit.value(TradeField.AMOUNT, i).isEmpty()),
                if (reversed) null else ({ begin(TradeField.AMOUNT) }),
                i.sell, { openTokens(TradeEdit.Side.SELL) }, paySub.joinToString(" · "), "paycard"), full(top = dp(2)))
            // ⇅ between the cards: You pay and You get trade places.
            body.addView(label("⇅", 15f, true, palette.ink).apply {
                gravity = Gravity.CENTER
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(palette.key) }
                setTag(com.arpit.glyf.R.id.qa_id, "trade:flip")
                contentDescription = "Flip"
                setOnClickListener { flip() }
            }, LinearLayout.LayoutParams(dp(28), dp(28)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = -dp(6); bottomMargin = -dp(6) })
            val getAmount = i.buyAmount ?: q?.out?.let { TradeQuote.amount(it) } ?: if (asking && i.amount != null) "…" else "0"
            body.addView(sideCard("You get", buyChain, true, { openChains(TradeEdit.Side.BUY) },
                getAmount, i.buyAmount == null && q?.out == null,
                if (reversed) ({ begin(TradeField.AMOUNT) }) else null,
                i.buy, { openTokens(TradeEdit.Side.BUY) }, getSub(q), "getcard"), full())
        } else {
            val sub = mutableListOf<String>()
            val market = marketPrice
            if (nearSend) {
                q?.outUsd?.let { sub.add(TradeQuote.approx(it)) }
                // The line over the button took the Arrives row: the time rides here.
                if (alert() != null) near?.time?.let { sub.add(it) }
            } else if (isEarn) {
                // What the coins are worth (the vault's share count never
                // shows) and how long it takes, as a swap's card says it.
                sub.addAll(TradeQuote.earnCardLine(i, quote, earn))
            } else if (market != null) sub.add("${TradeQuote.display(top)} ${TradeQuote.dollars(market)}") else if (asking) sub.add("…")
            if (TradeEdit.sells(i)) balance(top, i.chainName)?.takeIf { it > 0 }?.let { sub.add("Balance ${PayPanelView.compact(it)}") }
            // Phantom's send here takes SOL or USDC as read; no picker for it.
            // A NEAR Intents send keeps the coin typed (its chain decides it).
            val tokenPicks = !(i.kind == TradeIntent.Kind.SEND && (i.chainName == "solana" || i.isNear)) && !isEarn
            // A NEAR send's card is what arrives, where: the chain it's paid
            // from is a row below.
            val cardChain = if (nearSend) i.buyChain ?: i.chainName else i.chainName
            body.addView(sideCard(TradeQuote.topKey(i), cardChain, chains && !nearSend, { openChains(TradeEdit.Side.SELL) },
                TradeEdit.shown(TradeField.AMOUNT, i), TradeEdit.value(TradeField.AMOUNT, i).isEmpty(),
                { begin(TradeField.AMOUNT) }, top, if (tokenPicks) ({ openTokens(assetSide) }) else null,
                sub.joinToString(" · "), "paycard"), full(top = dp(2)))
            renderRows()
        }
        // Over the button: what Guard (or the name lookup) found, red when it
        // stops the trade, amber when it only asks for a look.
        alert()?.let { a ->
            val ink = if (a.block) red else amber
            val line = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), 0, dp(4), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "trade:alert")
            }
            line.addView(AlertMark(context, a.block, ink), LinearLayout.LayoutParams(dp(15), dp(15)).apply { rightMargin = dp(5) })
            line.addView(TextView(context).apply {
                text = a.text
                textSize = 13f
                maxLines = 2
                ellipsize = null
                setTextColor(ink)
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            body.addView(line, full(top = dp(7)))
        }
        // Earn's line over the button: 1Click's word on yield, on one line,
        // 13 down to 11 sp if it must (EarnQuote.noticeSize), so the amount's
        // card keeps its room; two lines only when even 11 is too wide.
        if (isEarn && alert() == null) {
            body.addView(NoticeText(context).apply {
                setTextColor(palette.inkSoft)
                setPadding(dp(4), 0, dp(4), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "trade:notice")
            }, full(top = dp(7)))
        }
        val go = if (isEarn) TradeQuote.earnGo(i, TradeIntent.missingWallet(i, evmAddress, solanaAddress, null), asking, earn, earnError)
            else TradeQuote.go(i, wallet, asking, quote, balance(i.sell, i.chainName), resolved, resolveProblem, near)
        body.addView(label(go.title, 15f, true, if (go.blocked) palette.inkSoft else Color.WHITE).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(if (go.blocked) soft(if (palette.darkChrome) 26 else 16, palette.ink) else if (go.red) red else blue)
            }
            setTag(com.arpit.glyf.R.id.qa_id, "trade:go")
            setOnClickListener { go(go) }
        }, full(dp(42), dp(8)))
    }

    /** You get's line: ≈ dollars, and NEAR Intents' time ("≈ $19.88 · ~32 s";
     *  NEAR Intents is in the header). An error speaks on the button. */
    private fun getSub(q: TradeQuote.Quote?): String {
        if (q?.error != null) return ""
        val parts = listOfNotNull(q?.outUsd?.let { TradeQuote.approx(it) },
            if (intent.isNear) near?.time else null)
        return parts.joinToString(" · ")
    }

    private fun alert(): TradeQuote.Alert? = TradeQuote.alert(intent, near, resolveProblem)

    /** A NEAR send's rows: To (ticked once NEAR says the name is there, red
     *  when Guard stops it), You pay (tap to pay from another chain) and
     *  Arrives; at least 36dp each, values fitted, never cut. */
    private fun renderNearRows(rows: List<TradeQuote.Row> = TradeQuote.nearSendRows(intent, near, asking, resolved, resolveProblem)) {
        val c = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(palette.card) }
        }
        for ((k, r) in rows.withIndex()) {
            if (k > 0) c.addView(View(context).apply { setBackgroundColor(soft(40, palette.ink)) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1).apply { leftMargin = dp(12) })
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = dp(36)
                setPadding(dp(12), dp(4), dp(12), dp(4))
                setTag(com.arpit.glyf.R.id.qa_id, "trade:row:${r.id}")
                if (r.tap) setOnClickListener { openChains(TradeEdit.Side.SELL) }
            }
            row.addView(label(r.label, 13.5f, false, palette.inkSoft).apply { ellipsize = null },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                    .apply { rightMargin = dp(16) })
            row.addView(RowValue(context, r.value).apply {
                setTextColor(if (r.red) red else palette.ink)
                if (r.bold) typeface = Typeface.DEFAULT_BOLD
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (r.check) row.addView(TickMark(context), LinearLayout.LayoutParams(dp(14), dp(14)).apply { leftMargin = dp(5) })
            c.addView(row, full())
        }
        body.addView(c, full(top = dp(6)))
    }

    /** An order's values under the asset: one row each, tap to change. */
    private fun renderRows() {
        val i = intent
        if (nearSend) { renderNearRows(); return }
        if (isEarn) { renderNearRows(TradeQuote.earnRows(i, earn, asking)); return }
        data class Spec(val id: String, var label: String, var value: String, val tap: () -> Unit)
        val specs = TradeEdit.fields(i).filter { it != TradeField.AMOUNT }.map { f ->
            Spec(f.id, TradeEdit.label(f, i), TradeEdit.shown(f, i)) { begin(f) }
        }.toMutableList()
        if (i.kind == TradeIntent.Kind.BRIDGE) {
            specs.add(Spec("toChain", "To", TradeIntent.chainLabels[i.toChain ?: ""] ?: "") { openChains(TradeEdit.Side.BUY) })
        }
        if (i.kind == TradeIntent.Kind.SEND) {
            for ((l, v) in TradeQuote.sendRows(i, resolved, resolveProblem)) specs.add(Spec(l.lowercase(), l, v) {})
        }
        // A recurring buy: the Over row says how much of the plan this Flash
        // order holds (Flash runs 30 days at most).
        i.planOverRow?.let { (l, v) -> specs.firstOrNull { it.id == TradeField.DURATION.id }?.let { it.label = l; it.value = v } }
        if (specs.isEmpty()) return
        val c = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(palette.card) }
        }
        for ((k, s) in specs.withIndex()) {
            if (k > 0) c.addView(View(context).apply { setBackgroundColor(soft(40, palette.ink)) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1).apply { leftMargin = dp(12) })
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), 0, dp(12), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "trade:row:${s.id}")
                setOnClickListener { s.tap() }
            }
            row.addView(label(s.label, 13.5f, false, palette.inkSoft), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(label(s.value, 14.5f, true, palette.ink))
            c.addView(row, full(dp(36)))
        }
        body.addView(c, full(top = dp(6)))
    }

    /** A value being typed: its name, the figure and Done over the panel's
     *  own digits (the Buy panel's pad). */
    private fun renderNumber(field: TradeField) {
        val strip = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val col = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        col.addView(label(TradeEdit.label(field, intent), 12.5f, true, palette.inkSoft))
        val placeholder = if (field == TradeField.AMOUNT && TradeEdit.sells(intent) && intent.kind != TradeIntent.Kind.BRIDGE &&
            intent.kind != TradeIntent.Kind.SEND) "All" else "0"
        col.addView(label(typed.ifEmpty { placeholder }, 19f, true, if (typed.isEmpty()) palette.inkSoft else palette.ink).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), 0, dp(10), 0)
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat(); setColor(palette.key)
                setStroke(dp(2) / 2 + 1, Color.rgb(0x7C, 0x5C, 0xFF))
            }
            setTag(com.arpit.glyf.R.id.qa_id, "trade:value")
        }, full(dp(36), dp(2)))
        strip.addView(col, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        strip.addView(label("Done", 14f, true, palette.board).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(palette.ink) }
            setPadding(dp(16), 0, dp(16), 0)
            setTag(com.arpit.glyf.R.id.qa_id, "trade:done")
            setOnClickListener { endEditing() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply { leftMargin = dp(8); topMargin = dp(16) })
        body.addView(strip, full(dp(58)))
        val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf(".", "0", "⌫"))
        for (r in rows) {
            val line = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
            for (key in r) {
                line.addView(TextView(context).apply {
                    text = key
                    textSize = if (key == "⌫") 20f else 23f
                    gravity = Gravity.CENTER
                    setTextColor(palette.ink)
                    if (key != "." && key != "⌫") background = GradientDrawable().apply { cornerRadius = dp(8).toFloat(); setColor(palette.key) }
                    setTag(com.arpit.glyf.R.id.qa_id, "trade:key:$key")
                    setOnClickListener { padTap(key) }
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f).apply { leftMargin = dp(3); rightMargin = dp(3) })
            }
            body.addView(line, full(dp(40), dp(5)))
        }
    }

    /** ‹ and a name over a picker's list. */
    private fun pickerHeader(title: String) {
        val head = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        head.addView(label("‹", 22f, false, palette.ink).apply {
            setPadding(dp(4), 0, dp(12), dp(2))
            setTag(com.arpit.glyf.R.id.qa_id, "trade:back")
            contentDescription = "Back"
            setOnClickListener { setMode(Mode.Panel) }
        })
        head.addView(label(title, 15f, true, palette.ink))
        body.addView(head, full(dp(34)))
    }

    private fun listRow(id: String, onTap: () -> Unit) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), 0, dp(12), 0)
        setTag(com.arpit.glyf.R.id.qa_id, id)
        setOnClickListener { onTap() }
    }

    private fun renderTokens(side: TradeEdit.Side) {
        val chain = chainOf(side)
        pickerHeader("Tokens on ${TradeIntent.chainLabels[chain] ?: TradeIntent.capitalized(chain)}")
        val current = if (side == TradeEdit.Side.SELL || !isSwap) (if (isSwap) intent.sell else TradeEdit.asset(intent)) else intent.buy
        // A tap on the field types a search on the letter keys.
        body.addView(InlineField(context, "Search or paste address").apply {
            show(searchText)
            setTag(com.arpit.glyf.R.id.qa_id, "trade:search")
            setOnClickListener { setMode(Mode.Search(side)) }
        }, full(dp(38), dp(2)))
        val list = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(palette.card) }
        }
        // A contract from the chat: whatever Uniswap lists at that address.
        if (chain in TradeIntent.uniswapReach) list.addView(listRow("trade:paste") { pasteToken(side) }.apply {
            addView(label("Paste address", 15f, true, blue), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(label("from the chat", 12f, false, palette.inkSoft))
        }, full(dp(44)))
        val rows = pickerTokens(side)
        for (t in rows.take(60)) {
            if (list.childCount > 0) list.addView(View(context).apply { setBackgroundColor(soft(40, palette.ink)) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1).apply { leftMargin = dp(12) })
            list.addView(listRow("trade:tokenrow:${t.symbol}") { picked(t, side) }.apply {
                addView(TokenLogoView(context, t.symbol, t.logo ?: logo(t.symbol, chain)),
                    LinearLayout.LayoutParams(dp(28), dp(28)).apply { rightMargin = dp(10) })
                val names = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
                names.addView(label(TradeQuote.display(t.symbol), 15f, true, palette.ink))
                names.addView(label(t.name, 11.5f, false, palette.inkSoft))
                addView(names, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                balance(t.symbol, chain)?.takeIf { it > 0 }?.let { addView(label(PayPanelView.compact(it), 13f, false, palette.inkSoft)) }
                addView(label(if (t.symbol.equals(current, ignoreCase = true)) "✓" else "", 15f, true, blue).apply { gravity = Gravity.END },
                    LinearLayout.LayoutParams(dp(24), LinearLayout.LayoutParams.WRAP_CONTENT))
            }, full(dp(46)))
        }
        if (rows.isEmpty()) list.addView(label(if (searchLoading) "Searching…" else "No tokens match", 13f, false, palette.inkSoft).apply {
            gravity = Gravity.CENTER
        }, full(dp(44)))
        body.addView(list, full(top = dp(6)))
    }

    /** The search strip over the letter keys: the words and Done, then the
     *  best four tokens as pills (iOS's results row). */
    private fun renderSearch(side: TradeEdit.Side) {
        val chain = chainOf(side)
        body.setPadding(dp(10), dp(6), dp(10), dp(4))
        val top = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        top.addView(InlineField(context, "Search or paste address").apply {
            show(searchText)
            active = true
            setTag(com.arpit.glyf.R.id.qa_id, "trade:searchfield")
        }, LinearLayout.LayoutParams(0, dp(36), 1f))
        top.addView(label("Done", 14f, true, palette.board).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(palette.ink) }
            setPadding(dp(16), 0, dp(16), 0)
            setTag(com.arpit.glyf.R.id.qa_id, "trade:searchdone")
            setOnClickListener { endStrip() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply { leftMargin = dp(8) })
        body.addView(top, full(dp(38)))
        val results = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val list = pickerTokens(side).take(4)
        if (list.isEmpty() && searchText.isNotEmpty()) {
            results.addView(label(if (searchLoading) "Searching…" else "No tokens match", 13f, false, palette.inkSoft))
        }
        for (t in list) {
            results.addView(tokenPill(t.symbol, t.logo ?: logo(t.symbol, chain), "trade:result:${t.symbol}", { picked(t, side) }, compact = true),
                LinearLayout.LayoutParams(0, dp(32), 1f).apply { rightMargin = dp(6) })
        }
        // Keep the grid even: blanks fill a short row.
        if (list.isNotEmpty()) for (k in list.size until 4) results.addView(View(context), LinearLayout.LayoutParams(0, dp(32), 1f))
        body.addView(results, full(dp(40), dp(6)))
    }

    /** The rows the picker lists now: all of the chain's, or the search's. */
    private fun pickerTokens(side: TradeEdit.Side): List<TokenPick> {
        val chain = chainOf(side)
        val all = tokenRows[chain] ?: TradeEdit.builtIn(chain)
        if (searchText.isEmpty()) return all
        return searchResults.ifEmpty { TradeEdit.filter(all, searchText) }
    }

    /** The search changed: this phone's rows at once, Uniswap's list a
     *  moment after the last letter (not per key). */
    private fun searchChanged(text: String) {
        val side = (mode as? Mode.Search)?.side ?: return
        val chain = chainOf(side)
        searchText = text
        searchResults = TradeEdit.filter(tokenRows[chain] ?: TradeEdit.builtIn(chain), text)
        val n = ++searchSerial
        searchLoading = false
        if (TradeQuote.tokenSearchPath(chain, text) != null) {
            searchLoading = true
            main.postDelayed({ if (n == searchSerial) searchTokens(chain, text, n) }, 250)
        }
        render()
    }

    private fun searchTokens(chain: String, query: String, n: Int) {
        val path = TradeQuote.tokenSearchPath(chain, query) ?: run { searchLoading = false; render(); return }
        http("GET", path, null) { _, obj ->
            val arr = obj?.optJSONArray("tokens")
            val rows = if (arr == null) emptyList()
                else (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.let { j -> TokenPick.fromJson(j) } }
            tokenRows[chain] = TradeEdit.merge(tokenRows[chain] ?: TradeEdit.builtIn(chain), rows)
            for (t in rows) known.getOrPut("$chain|${t.symbol.uppercase()}") { t }
            if (n != searchSerial) return@http
            searchLoading = false
            searchResults = TradeQuote.searchRows(tokenRows[chain] ?: emptyList(), rows, query)
            render()
        }
    }

    private fun renderChains(side: TradeEdit.Side) {
        pickerHeader(if (side == TradeEdit.Side.BUY && isSwap) "You get on" else if (nearSend) "Pay from" else "Chain")
        val current = when {
            intent.kind == TradeIntent.Kind.BRIDGE && side == TradeEdit.Side.BUY -> intent.toChain
            side == TradeEdit.Side.BUY && isSwap -> buyChain
            else -> intent.chainName
        }
        val list = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(palette.card) }
        }
        for ((k, chain) in TradeEdit.chains(intent).withIndex()) {
            if (k > 0) list.addView(View(context).apply { setBackgroundColor(soft(40, palette.ink)) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1).apply { leftMargin = dp(44) })
            list.addView(listRow("trade:chainrow:$chain") { pickedChain(chain, side) }.apply {
                addView(ChainMarkView(context, chain), LinearLayout.LayoutParams(dp(22), dp(22)).apply { rightMargin = dp(10) })
                addView(label(TradeIntent.chainLabels[chain] ?: TradeIntent.capitalized(chain), 15f, false, palette.ink),
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                addView(label(if (chain == current) "✓" else "", 15f, true, blue))
            }, full(dp(44)))
        }
        body.addView(list, full(top = dp(2)))
    }

    // MARK: changes

    private fun setMode(m: Mode) {
        val was = mode
        mode = m
        if ((was is Mode.Search) != (m is Mode.Search)) onSearching(m is Mode.Search)
        render()
        scroll.scrollTo(0, 0)
    }

    private fun begin(field: TradeField) {
        typed = TradeEdit.value(field, intent)
        setMode(Mode.Number(field))
    }

    /** Done: the value is set and the trade quoted again. */
    fun endEditing() {
        if (mode !is Mode.Number) return
        setMode(Mode.Panel)
        requote()
    }

    private fun padTap(key: String) {
        val field = (mode as? Mode.Number)?.field ?: return
        typed = if (key == "⌫") typed.dropLast(1) else TradeEdit.cleanNumber(typed + key)
        intent = TradeEdit.apply(field, typed, intent)
        render()
    }

    private fun chainOf(side: TradeEdit.Side) = if (side == TradeEdit.Side.BUY && isSwap) buyChain else intent.chainName

    private fun openTokens(side: TradeEdit.Side) {
        searchText = ""
        searchResults = emptyList()
        setMode(Mode.Tokens(side))
        prefetchTokens(chainOf(side))
        loadBalances(chainOf(side))
    }

    private fun openChains(side: TradeEdit.Side) {
        if (TradeEdit.chains(intent).size < 2) return
        setMode(Mode.Chains(side))
    }

    private fun flip() {
        intent = TradeEdit.flip(intent)
        quote = null
        near = null
        loadBalances(intent.chainName)
        requote()
    }

    private fun picked(token: TokenPick, side: TradeEdit.Side) {
        known["${chainOf(side)}|${token.symbol.uppercase()}"] = token
        val was = intent
        intent = TradeEdit.repriced(TradeEdit.pick(token, if (isSwap) side else assetSide, intent), was)
        quote = null
        near = null
        if (!isSwap) { marketPrice = null; asking = true }
        setMode(Mode.Panel)
        loadLive()
    }

    private fun pickedChain(chain: String, side: TradeEdit.Side) {
        val was = intent
        intent = TradeEdit.repriced(TradeEdit.pickChain(chain, side, intent), was)
        quote = null
        near = null
        if (!isSwap && side == TradeEdit.Side.SELL) { marketPrice = null; asking = true }
        setMode(Mode.Panel)
        loadBalances(intent.chainName)
        prefetchTokens(chain)
        loadLive()
    }

    /** A 0x address on the clipboard: the token Uniswap knows there. */
    private fun pasteToken(side: TradeEdit.Side) {
        val copied = clipText()?.trim().orEmpty()
        val address = Regex("""0x[0-9a-fA-F]{40}""").find(copied)?.value
        if (address == null) { onToast("Copy a token's address first"); return }
        val chain = chainOf(side)
        http("GET", "/uniswap/tokens?chain=$chain&q=$address&limit=5", null) { _, obj ->
            val t = obj?.optJSONArray("tokens")?.optJSONObject(0)?.let { TokenPick.fromJson(it) }
            if (t == null) { onToast("Uniswap doesn't list that token on ${TradeIntent.chainLabels[chain] ?: chain}"); return@http }
            tokenRows[chain] = TradeEdit.merge(tokenRows[chain] ?: TradeEdit.builtIn(chain), listOf(t))
            picked(t, side)
        }
    }

    private fun go(g: TradeQuote.Go) {
        if (g.connect) { onConnect(); return }
        if (g.blocked) return
        onHandOff(TradeQuote.handOff(intent, resolved, anyway = g.red))
    }

    // MARK: live numbers

    private fun loadLive() {
        val title = TradeQuote.headerTitle(intent)
        if (title != shownTitle) { shownTitle = title; onTitle(title, TradeQuote.headerIcon(intent)) }
        when {
            isSwap -> requote()
            intent.kind == TradeIntent.Kind.SEND -> { resolve(); if (intent.isNear) requote() else price(intent.sell) }
            isEarn -> requote()
            else -> price(TradeEdit.asset(intent))
        }
        render()
    }

    /** The address a send goes to, shown (shortened) before anything is
     *  signed. A name is looked up for the send's chain: an ENS name's own
     *  record there, else its Ethereum one; a .sol name's Solana owner.
     *  Nothing found means nothing is sent. */
    private fun resolve() {
        val to = intent.to
        if (to == null) { resolved = null; resolveProblem = "No one to send to"; return }
        if (!TradeIntent.isName(to)) { resolved = to; resolveProblem = null; resolvedFor = null; return }
        // A NEAR Intents send is looked up where it lands, not where it's paid.
        val chain = if (intent.isNear) intent.buyChain ?: intent.chainName else intent.chainName
        val key = "$to|$chain"
        if (key == resolvedFor) return
        resolvedFor = key
        resolved = null
        resolveProblem = null
        http("GET", "/names/resolve?name=" + java.net.URLEncoder.encode(to, "UTF-8"), null) { ok, obj ->
            if (resolvedFor != key) return@http
            val (address, problem) = TradeIntent.recipient(to, chain, ok, obj)
            resolved = address
            resolveProblem = problem
            render()
        }
    }

    private fun balance(symbol: String, chain: String): Double? {
        val map = held[chain] ?: return null
        return map[symbol.uppercase()] ?: 0.0
    }

    private fun loadBalances(chain: String) {
        val address = evmAddress
        if (chain !in TradeIntent.uniswapReach || held[chain] != null || address.isNullOrEmpty()) return
        http("GET", "/evm/balances?chain=$chain&address=$address", null) { _, obj ->
            TradeQuote.balances(obj)?.let { held[chain] = it; render() }
        }
    }

    /** A quote shortly after the last change (typing doesn't ask per key). */
    private fun requote() {
        if (!quotes) {
            if (intent.awaitingPrice) price(TradeEdit.asset(intent))
            render()
            return
        }
        val n = ++serial
        asking = true
        quote = null
        near = null
        earn = null
        earnError = null
        render()
        main.postDelayed({ if (n == serial) ask(n) }, 300)
    }

    private fun ask(n: Int) {
        val i = intent
        if (i.kind == TradeIntent.Kind.EARN) { earnQuote(i, n); return }
        if (i.isNear) { nearQuote(i, n); return }
        if (i.chainName == "solana") { jupiter(n); return }
        val body = TradeQuote.body(i)
        if (body == null) { asking = false; render(); return }
        http("POST", "/uniswap/quote", body) { ok, obj ->
            if (n != serial) return@http
            asking = false
            quote = TradeQuote.read(ok, obj, i.buyAmount != null)
            render()
        }
    }

    /** NEAR Intents' quote (POST /near/quote), dry: a preview the app asks
     *  again for, with a refund address, before anything is signed. */
    private fun nearQuote(i: TradeIntent, n: Int) {
        val body = TradeQuote.nearBody(i, nearRecent)
        if (body == null) { asking = false; render(); return }
        http("POST", "/near/quote", body) { ok, obj ->
            if (n != serial) return@http
            val q = NearQuote.read(ok, obj)
            asking = false
            near = if (q.error == null) q else null
            quote = TradeQuote.Quote(q.amountOut, q.inUsd, q.outUsd, q.error?.let { TradeQuote.shortError(it) })
            render()
        }
    }

    /** Earn's preview (POST /near/earn/quote, dry). Everything out has no
     *  amount to price: the vault's own row (GET /near/earn/vaults). */
    private fun earnQuote(i: TradeIntent, n: Int) {
        if (i.earnOut && i.amount == null) {
            fun take(list: JSONObject?) {
                if (n != serial) return
                asking = false
                earn = EarnQuote.vault(i.earnVault, list)
                render()
            }
            vaultList?.let { take(it); return }
            http("GET", "/near/earn/vaults", null) { ok, obj ->
                if (ok && obj?.optJSONArray("vaults") != null) vaultList = obj
                take(if (ok) obj else null)
            }
            return
        }
        val body = TradeQuote.earnBody(i)
        if (body == null) { asking = false; render(); return }
        http("POST", "/near/earn/quote", body) { ok, obj ->
            if (n != serial) return@http
            val q = EarnQuote.of(ok, obj)
            asking = false
            earn = if (q.error == null) q else null
            earnError = q.error?.let { TradeQuote.shortError(it) }
            quote = if (q.error == null) TradeQuote.Quote(null, TradeQuote.num(obj?.opt("amountInUsd")),
                TradeQuote.num(obj?.opt("amountOutUsd"))) else null
            render()
        }
    }

    /** A Solana swap: Jupiter's prices for both sides, as the Buy panel has them. */
    private fun jupiter(n: Int) {
        val i = intent
        fun take() {
            if (n != serial || !asking) return
            val q = TradeQuote.jupiter(i) { RatesStore.cryptoUsd(it) } ?: return
            asking = false
            quote = q
            render()
        }
        for (s in listOf(i.sell, i.buy)) if (s !in TradeEdit.stables && RatesStore.cryptoUsd(s) == null)
            RatesStore.ensureToken(backendURL, s) { main.post { take() } }
        take()
        main.postDelayed({
            if (n == serial && asking) { asking = false; quote = TradeQuote.Quote(error = "Jupiter has no price right now"); render() }
        }, 8000)
    }

    private fun price(symbol: String) {
        if (symbol in TradeEdit.stables) { marketPrice = 1.0; asking = false; fill(); render(); return }
        TradeIntent.baseStocks[symbol.uppercase()]?.let { address ->
            http("GET", "/flash/search?chain=base&query=${symbol.uppercase()}&limit=8", null) { _, obj ->
                asking = false
                marketPrice = TradeQuote.sharePrice(obj, address)
                fill(); render()
            }
            return
        }
        if (symbol == "SOL" || intent.chainName == "solana") { jupiterPrice(symbol); return }
        val address = tokenRows[intent.chainName]?.firstOrNull { it.symbol.equals(symbol, true) }?.address
        http("POST", "/uniswap/quote", TradeQuote.priceBody(intent.chainName, symbol, address)) { ok, obj ->
            val p = if (ok) TradeQuote.num(obj?.opt("amountOut")) else null
            if (p == null && intent.awaitingPrice) { jupiterPrice(symbol); return@http }
            asking = false
            marketPrice = p
            fill(); render()
        }
    }

    private fun jupiterPrice(symbol: String) {
        fun take() {
            if (!asking) return
            asking = false
            marketPrice = RatesStore.cryptoUsd(symbol)
            fill(); render()
        }
        if (RatesStore.cryptoUsd(symbol) != null) { take(); return }
        RatesStore.ensureToken(backendURL, symbol) { main.post { take() } }
        main.postDelayed({ take() }, 8000)
    }

    /** A starter's price, set from the market's once it is known. */
    private fun fill() {
        val m = marketPrice ?: return
        if (intent.awaitingPrice) intent = SponsorMenu.priced(intent, m)
    }

    private fun prefetchTokens(chain: String) {
        if (tokenRows[chain] == null) tokenRows[chain] = TradeEdit.builtIn(chain)
        // Uniswap's token list is for its own chains.
        if (chain !in TradeIntent.uniswapReach || (tokenRows[chain]?.size ?: 0) > 8) return
        http("GET", "/uniswap/tokens?chain=$chain&q=&limit=40", null) { _, obj ->
            val arr = obj?.optJSONArray("tokens") ?: return@http
            val rows = (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.let { j -> TokenPick.fromJson(j) } }
            tokenRows[chain] = TradeEdit.merge(TradeEdit.builtIn(chain), rows)
            for (t in rows) known.getOrPut("$chain|${t.symbol.uppercase()}") { t }
            render()
        }
    }

    /** GET or POST JSON to the server's trading routes, with the session;
     *  the object whatever the status, and whether it was a 2xx; on the
     *  main thread. Nothing here signs. */
    private fun http(method: String, path: String, body: JSONObject?, done: (Boolean, JSONObject?) -> Unit) {
        pool.execute {
            var conn: HttpURLConnection? = null
            var ok = false
            val obj = try {
                conn = (URL(backendURL + path).openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    connectTimeout = 6000
                    readTimeout = 15000
                    BackendClient.session(this)
                    if (body != null) {
                        doOutput = true
                        setRequestProperty("content-type", "application/json")
                        outputStream.bufferedWriter().use { it.write(body.toString()) }
                    }
                }
                ok = conn.responseCode in 200..299
                val stream = if (ok) conn.inputStream else conn.errorStream
                stream?.bufferedReader()?.readText()?.let { JSONObject(it) }
            } catch (e: Exception) {
                android.util.Log.w("GlyfKB", "trade $path: $e")
                null
            } finally {
                conn?.disconnect()
            }
            main.post { if (isAttachedToWindow) done(ok, obj) }
        }
    }
}

/** Over a NEAR trade's button: an octagon (red, Guard stops it) or a
 *  triangle (amber, a look first), with its "!" (iOS's
 *  exclamationmark.octagon.fill / exclamationmark.triangle.fill). */
@SuppressLint("ViewConstructor")
private class AlertMark(ctx: Context, private val block: Boolean, private val ink: Int) : View(ctx) {
    private val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)

    override fun onDraw(c: android.graphics.Canvas) {
        val s = minOf(width, height).toFloat()
        val x0 = (width - s) / 2f
        val y0 = (height - s) / 2f
        val shape = android.graphics.Path()
        if (block) {
            for (k in 0 until 8) {
                val a = Math.PI / 8 + k * Math.PI / 4
                val x = x0 + s / 2 + (s / 2 * Math.cos(a)).toFloat()
                val y = y0 + s / 2 + (s / 2 * Math.sin(a)).toFloat()
                if (k == 0) shape.moveTo(x, y) else shape.lineTo(x, y)
            }
        } else {
            shape.moveTo(x0 + s / 2, y0 + s * 0.06f); shape.lineTo(x0 + s, y0 + s * 0.94f); shape.lineTo(x0, y0 + s * 0.94f)
        }
        shape.close()
        p.style = android.graphics.Paint.Style.FILL
        p.color = ink
        c.drawPath(shape, p)
        // The "!": a bar and a dot, in the board's white.
        p.color = Color.WHITE
        val mid = x0 + s / 2
        val top = y0 + s * if (block) 0.24f else 0.36f
        c.drawRoundRect(android.graphics.RectF(mid - s * 0.06f, top, mid + s * 0.06f, y0 + s * 0.64f), s * 0.06f, s * 0.06f, p)
        c.drawCircle(mid, y0 + s * 0.78f, s * 0.07f, p)
    }
}

/** After a NEAR name the network says is there: a green disc with a tick
 *  (iOS's checkmark.circle.fill). */
private class TickMark(ctx: Context) : View(ctx) {
    private val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)

    override fun onDraw(c: android.graphics.Canvas) {
        val s = minOf(width, height).toFloat()
        val x0 = (width - s) / 2f
        val y0 = (height - s) / 2f
        p.style = android.graphics.Paint.Style.FILL
        p.color = Color.rgb(0x34, 0xC7, 0x59)
        c.drawCircle(x0 + s / 2, y0 + s / 2, s / 2, p)
        p.style = android.graphics.Paint.Style.STROKE
        p.strokeWidth = s * 0.12f
        p.strokeCap = android.graphics.Paint.Cap.ROUND
        p.strokeJoin = android.graphics.Paint.Join.ROUND
        p.color = Color.WHITE
        val tick = android.graphics.Path().apply {
            moveTo(x0 + s * 0.28f, y0 + s * 0.52f); lineTo(x0 + s * 0.44f, y0 + s * 0.67f); lineTo(x0 + s * 0.72f, y0 + s * 0.36f)
        }
        c.drawPath(tick, p)
    }
}

/** A NEAR send's row value, fitted (TradeQuote.rowFit): smaller rather
 *  than cut, then on two lines, never with "…". */
@SuppressLint("ViewConstructor")
private class RowValue(ctx: Context, private val value: String) : TextView(ctx) {
    init {
        text = value
        textSize = 15f
        maxLines = 2
        ellipsize = null
        gravity = Gravity.END or Gravity.CENTER_VERTICAL
        // Two lines break between words ("Gauntlet" whole, never
        // hyphenated); an address, one long word, between characters.
        if (value.contains(' ') && android.os.Build.VERSION.SDK_INT >= 23)
            hyphenationFrequency = android.text.Layout.HYPHENATION_FREQUENCY_NONE
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val room = (MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight).toDouble()
        if (MeasureSpec.getMode(widthMeasureSpec) != MeasureSpec.UNSPECIFIED && room > 0) {
            val scale = resources.displayMetrics.scaledDensity
            val probe = android.text.TextPaint(paint)
            val (size, lines) = TradeQuote.rowFit(value, room) { t, sp ->
                probe.textSize = (sp * scale).toFloat()
                probe.measureText(t).toDouble()
            }
            if (textSize != (size * scale).toFloat()) setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, size.toFloat())
            if (maxLines != lines) maxLines = lines
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}

/** Earn's notice (EarnQuote.NOTICE): one line at the largest size from 13 to
 *  11 sp that fits, else 13 sp on two lines; never "…". */
private class NoticeText(ctx: Context) : TextView(ctx) {
    init {
        text = EarnQuote.NOTICE
        textSize = EarnQuote.NOTICE_FULL.toFloat()
        maxLines = 2
        ellipsize = null
        if (android.os.Build.VERSION.SDK_INT >= 28) typeface = Typeface.create(Typeface.DEFAULT, 500, false)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val room = (MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight).toDouble()
        if (MeasureSpec.getMode(widthMeasureSpec) != MeasureSpec.UNSPECIFIED && room > 0) {
            val scale = resources.displayMetrics.scaledDensity
            val probe = android.text.TextPaint(paint)
            val size = EarnQuote.noticeSize(room) { sp ->
                probe.textSize = (sp * scale).toFloat()
                probe.measureText(EarnQuote.NOTICE).toDouble()
            }
            val sp = size ?: EarnQuote.NOTICE_FULL
            val lines = if (size != null) 1 else 2
            if (textSize != (sp * scale).toFloat()) setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, sp.toFloat())
            if (maxLines != lines) maxLines = lines
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}
