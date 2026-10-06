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
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

/**
 * Paying without leaving the chat — the website's wallet panel on the real
 * keyboard, jup.ag-simple, the twin of PaySurface.swift: balance up top,
 * the amount in whichever asset the wallet holds, Private by MagicBlock
 * for USDC, one blue button. The panel types its own digits, and the one
 * hop left is the button: a flash of Glyf on the way into Phantom.
 */
@SuppressLint("ViewConstructor", "UseSwitchCompatOrMaterialCode", "SetTextI18n")
class PayPanelView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    private val backendURL: String,
    private val walletAddress: String?,
    private val intent: Intent,
    private val onHandOff: (Map<String, String>) -> Unit,
    private val onConnect: () -> Unit,
    private val onToast: (String) -> Unit,
    private val onClose: () -> Unit,
    /** The copy, read on the Paste tap (the IME may read it while shown). */
    private val clipText: () -> String?,
) : FrameLayout(ctx) {

    sealed class Intent {
        data class Send(val to: String?, val amount: String?, val token: String?) : Intent()
        data class Buy(val mint: String, val symbol: String, val price: String?) : Intent()
    }

    data class Asset(val mint: String, var symbol: String, val decimals: Int, val amount: Double)

    companion object {
        const val WSOL = "So11111111111111111111111111111111111111112"
        const val USDC = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        private val pool = Executors.newFixedThreadPool(2)

        /** "2,741,737", "13.5T", "0.0821": a figure a panel can hold. */
        fun compact(v: Double): String {
            fun short(x: Double, s: String): String {
                var t = if (x >= 100) "%.0f".format(x) else "%.1f".format(x)
                if (t.endsWith(".0")) t = t.dropLast(2)
                return t + s
            }
            if (v >= 1e12) return short(v / 1e12, "T")
            if (v >= 1e9) return short(v / 1e9, "B")
            if (v >= 1e6) return short(v / 1e6, "M")
            if (v >= 1e5) return short(v / 1e3, "K")
            val whole = v.toLong()
            if (v >= 1000) return "%,d".format(whole)
            if (v >= 1) return trimZeros("%.2f".format(v))
            return trimZeros("%.6f".format(v))
        }

        private fun trimZeros(s: String): String {
            var t = s
            if (t.contains('.')) {
                t = t.trimEnd('0')
                if (t.endsWith('.')) t = t.dropLast(1)
            }
            return t
        }

        /** One dot, digits only, nine characters at most. */
        fun cleanAmount(text: String): String {
            val out = StringBuilder()
            var dot = false
            for (ch in text.replace(',', '.')) {
                if (ch.isDigit()) out.append(ch)
                else if (ch == '.' && !dot) { dot = true; out.append(ch) }
            }
            return out.toString().take(9)
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val connected = !walletAddress.isNullOrEmpty()
    private val isBuy = intent is Intent.Buy
    private var to: String? = (intent as? Intent.Send)?.to
    private var amount = cleanAmount((intent as? Intent.Send)?.amount ?: "")
    private var paying = if ((intent as? Intent.Send)?.token?.uppercase() == "SOL")
        Asset(WSOL, "SOL", 9, 0.0) else if (isBuy) Asset(WSOL, "SOL", 9, 0.0)
        else Asset(USDC, "USDC", 6, 0.0)
    private var assets = mutableListOf(Asset(WSOL, "SOL", 9, 0.0), Asset(USDC, "USDC", 6, 0.0))
    private var isPrivate = false
    private var editing = false
    private var quote: String? = null
    private var targetDecimals: Int? = null
    private var quoteToken = 0
    /** Jupiter's answer in whole tokens of what's bought, and whether one is
     *  on its way. */
    private var quoteOut: Double? = null
    private var quoting = false
    /** The wallet answered: zeros are facts only then. */
    private var balanceKnown = false
    /** A buy's pay token list is open where "You get" was. */
    private var picking = false
    /** Room for the line under a buy's button (iOS: 236pt and up). */
    private var tall = false

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val now = h >= dp(236)
        if (now != tall) { tall = now; post { render() } }
    }

    private val blue = Color.rgb(0x0A, 0x84, 0xFF)
    private val green = Color.rgb(0x34, 0xC7, 0x59)

    private val header = LinearLayout(ctx)
    private val title = TextView(ctx)
    private val balance = TextView(ctx)
    private val amountRow = LinearLayout(ctx)
    private val amountText = TextView(ctx)
    private val unitText = TextView(ctx)
    private val toCol = LinearLayout(ctx)
    private val toName = TextView(ctx)
    private val toDetail = TextView(ctx)
    private val assetsScroll = HorizontalScrollView(ctx)
    private val assetsRow = LinearLayout(ctx)
    private val privateRow = LinearLayout(ctx)
    private val privateBy = TextView(ctx)
    private val privateSwitch = Switch(ctx)
    private val meta = TextView(ctx)
    private val go = TextView(ctx)
    private val lead = TextView(ctx)
    private val cta = TextView(ctx)
    private val pad = LinearLayout(ctx)
    private val body = LinearLayout(ctx)
    // Buy, laid out the way jup.ag does it (Arpit, 2026-10-06: "we need to
    // improve the buy ui a lot ... check jupiter jup.ag and make a proper ui
    // for this"): what you pay, what you get, one button saying what's next.
    private val payCard = LinearLayout(ctx)
    private val payHeld = TextView(ctx)
    private val payAmount = TextView(ctx)
    private val payUsd = TextView(ctx)
    private val payToken = TextView(ctx)
    private val getCard = LinearLayout(ctx)
    private val getAmount = TextView(ctx)
    private val getUsd = TextView(ctx)
    private val getToken = TextView(ctx)
    private val shareButtons = mutableListOf<View>()

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun soft(a: Int, c: Int) =
        Color.argb(a, Color.red(c), Color.green(c), Color.blue(c))

    init {
        setBackgroundColor(palette.board)
        body.orientation = LinearLayout.VERTICAL
        body.setPadding(dp(10), dp(4), dp(10), dp(8))
        addView(body, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        build()
        render()
        if (connected) loadAssets()
        if (intent is Intent.Buy) tokenMeta(intent.mint) { _, decimals ->
            targetDecimals = decimals
            requote()
        }
    }

    // MARK: build

    private fun chipBg(on: Boolean) = GradientDrawable().apply {
        cornerRadius = dp(13).toFloat()
        setColor(if (on) palette.ink else palette.card)
    }

    private fun cardBg() = GradientDrawable().apply {
        cornerRadius = dp(12).toFloat()
        setColor(palette.card)
    }

    private fun build() {
        header.orientation = LinearLayout.HORIZONTAL
        header.gravity = Gravity.CENTER_VERTICAL
        header.addView(TextView(context).apply {
            text = "✕"; textSize = 16f; setTextColor(palette.inkSoft)
            setPadding(dp(6), dp(2), dp(10), dp(2))
            setTag(com.arpit.glyf.R.id.qa_id, "pay:close")
            contentDescription = "Close"
            setOnClickListener { onClose() }
        })
        title.textSize = 15f
        title.typeface = Typeface.DEFAULT_BOLD
        title.setTextColor(palette.ink)
        title.text = if (intent is Intent.Buy) "Buy ${intent.symbol}" else "Send"
        header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        balance.textSize = 11.5f
        balance.setTextColor(palette.inkSoft)
        header.addView(balance)
        body.addView(header, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(30)))
        if (isBuy) buildBuy()

        amountRow.orientation = LinearLayout.HORIZONTAL
        amountRow.gravity = Gravity.CENTER_VERTICAL
        amountRow.background = cardBg()
        amountRow.setPadding(dp(12), 0, dp(12), 0)
        amountRow.setTag(com.arpit.glyf.R.id.qa_id, "pay:amountrow")
        amountRow.setOnClickListener { beginAmount() }
        amountText.textSize = 21f
        amountText.typeface = Typeface.DEFAULT_BOLD
        amountText.setTextColor(palette.ink)
        amountRow.addView(amountText)
        unitText.textSize = 12.5f
        unitText.typeface = Typeface.DEFAULT_BOLD
        unitText.setTextColor(palette.inkSoft)
        unitText.setPadding(dp(6), 0, 0, 0)
        amountRow.addView(unitText, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        toCol.orientation = LinearLayout.VERTICAL
        toCol.gravity = Gravity.END
        toName.textSize = 13f
        toName.typeface = Typeface.DEFAULT_BOLD
        toName.setTextColor(palette.ink)
        toName.gravity = Gravity.END
        toDetail.textSize = 11f
        toDetail.setTextColor(palette.inkSoft)
        toDetail.gravity = Gravity.END
        toCol.addView(toName)
        toCol.addView(toDetail)
        amountRow.addView(toCol)
        body.addView(amountRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(44)).apply { topMargin = dp(2) })

        assetsRow.orientation = LinearLayout.HORIZONTAL
        assetsScroll.isHorizontalScrollBarEnabled = false
        assetsScroll.addView(assetsRow)
        body.addView(assetsScroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(30)).apply { topMargin = dp(6) })

        privateRow.orientation = LinearLayout.HORIZONTAL
        privateRow.gravity = Gravity.CENTER_VERTICAL
        privateRow.background = cardBg()
        privateRow.setPadding(dp(12), 0, dp(6), 0)
        privateRow.addView(TextView(context).apply {
            text = "Private"; textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(palette.ink)
        })
        privateBy.textSize = 11.5f
        privateBy.setTextColor(palette.inkSoft)
        privateBy.setPadding(dp(8), 0, 0, 0)
        privateRow.addView(privateBy, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        privateSwitch.setTag(com.arpit.glyf.R.id.qa_id, "pay:private")
        privateSwitch.setOnCheckedChangeListener { _, on ->
            if (isPrivate != on) { isPrivate = on; render() }
        }
        privateRow.addView(privateSwitch)
        body.addView(privateRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(36)).apply { topMargin = dp(6) })

        meta.textSize = 11.5f
        meta.setTextColor(palette.inkSoft)
        meta.gravity = Gravity.CENTER
        body.addView(meta, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(18)).apply { topMargin = dp(4) })

        pad.orientation = LinearLayout.VERTICAL
        body.addView(pad, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).apply { topMargin = dp(4) })
        buildPad()

        lead.textSize = 13.5f
        lead.setTextColor(palette.inkSoft)
        lead.gravity = Gravity.CENTER
        lead.setPadding(dp(16), dp(14), dp(16), dp(6))
        body.addView(lead, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        cta.textSize = 14.5f
        cta.typeface = Typeface.DEFAULT_BOLD
        cta.setTextColor(Color.WHITE)
        cta.gravity = Gravity.CENTER
        cta.background = GradientDrawable().apply { cornerRadius = dp(12).toFloat(); setColor(blue) }
        body.addView(cta, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(42)).apply {
            topMargin = dp(10); leftMargin = dp(40); rightMargin = dp(40)
        })

        go.textSize = 15f
        go.typeface = Typeface.DEFAULT_BOLD
        go.setTextColor(Color.WHITE)
        go.gravity = Gravity.CENTER
        go.background = GradientDrawable().apply { cornerRadius = dp(12).toFloat(); setColor(blue) }
        go.setTag(com.arpit.glyf.R.id.qa_id, "pay:go")
        go.setOnClickListener { goIfReady() }
        body.addView(go, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(42)).apply { topMargin = dp(6) })
    }

    private fun pill() = GradientDrawable().apply {
        cornerRadius = dp(16).toFloat()
        setColor(soft(20, palette.ink))
    }

    private fun label(text: String, size: Float, bold: Boolean, color: Int) = TextView(context).apply {
        this.text = text; textSize = size; setTextColor(color)
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    /** You pay (amount, its dollars, the token, the balance with Half and
     *  Max) over You get (Jupiter's quote, its dollars, the rate). */
    private fun buildBuy() {
        fun card(view: LinearLayout, id: String) {
            view.orientation = LinearLayout.VERTICAL
            view.background = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(palette.card) }
            view.setPadding(dp(12), dp(7), dp(10), dp(8))
            view.setTag(com.arpit.glyf.R.id.qa_id, id)
        }
        card(payCard, "pay:paycard")
        payCard.setOnClickListener { if (editing) endAmount() else beginAmount() }
        val top = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        top.addView(label("You pay", 12f, true, palette.inkSoft),
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        payHeld.textSize = 11.5f
        payHeld.setTextColor(palette.inkSoft)
        top.addView(payHeld)
        for ((title, share) in listOf("HALF" to 0.5, "MAX" to 1.0)) {
            top.addView(label(title, 10.5f, true, palette.inkSoft).apply {
                background = pill()
                setPadding(dp(8), dp(2), dp(8), dp(2))
                setTag(com.arpit.glyf.R.id.qa_id, "pay:${title.lowercase()}")
                shareButtons.add(this)
                setOnClickListener { takePercent(share); requote(); render() }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { leftMargin = dp(6) })
        }
        payCard.addView(top)
        val payRow = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val payCol = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        payAmount.textSize = 22f
        payAmount.typeface = Typeface.DEFAULT_BOLD
        payAmount.maxLines = 1
        payCol.addView(payAmount)
        payUsd.textSize = 11.5f
        payUsd.setTextColor(palette.inkSoft)
        payCol.addView(payUsd)
        payRow.addView(payCol, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        payToken.textSize = 14f
        payToken.typeface = Typeface.DEFAULT_BOLD
        payToken.background = pill()
        payToken.setPadding(dp(12), dp(6), dp(10), dp(6))
        payToken.setTag(com.arpit.glyf.R.id.qa_id, "pay:token")
        payToken.setOnClickListener {
            if (editing) endAmount() else { picking = !picking; render() }
        }
        payRow.addView(payToken)
        payCard.addView(payRow)
        body.addView(payCard, 1, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(2) })

        card(getCard, "pay:getcard")
        getCard.addView(label("You get", 12f, true, palette.inkSoft))
        val getRow = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val getCol = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        getAmount.textSize = 22f
        getAmount.typeface = Typeface.DEFAULT_BOLD
        getAmount.maxLines = 1
        getCol.addView(getAmount)
        getUsd.textSize = 11.5f
        getUsd.setTextColor(palette.inkSoft)
        getUsd.maxLines = 1
        getCol.addView(getUsd)
        getRow.addView(getCol, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        getToken.textSize = 14f
        getToken.typeface = Typeface.DEFAULT_BOLD
        getToken.setTextColor(palette.ink)
        getToken.background = pill()
        getToken.setPadding(dp(12), dp(5), dp(12), dp(5))
        getRow.addView(getToken)
        getCard.addView(getRow)
        body.addView(getCard, 2, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(6) })
    }

    private fun glyph(a: Asset) = when (a.mint) { WSOL -> "◎ "; USDC -> "$ "; else -> "" }

    private fun dollars(v: Double): String {
        val f = java.text.NumberFormat.getCurrencyInstance(java.util.Locale.US)
        f.maximumFractionDigits = if (v >= 100) 0 else 2
        return f.format(v)
    }

    private fun dollarsOf(a: Asset, v: Double?): Double? = when {
        v == null -> null
        a.mint == USDC -> v
        a.mint == WSOL -> RatesStore.cryptoUsd("SOL")?.let { v * it }
        else -> null
    }

    /** SOL keeps a sliver back for fees. */
    private fun spendable() = if (paying.mint == WSOL) (paying.amount - 0.005).coerceAtLeast(0.0) else paying.amount

    /** The two cards and the button: the button says what's missing before
     *  it says Buy. */
    private fun renderBuy() {
        val buy = intent as? Intent.Buy ?: return
        val value = amountValue
        payAmount.text = if (amount.isEmpty()) "0" else amount
        payAmount.setTextColor(if (value == null) palette.inkSoft else palette.ink)
        val unit = buy.price?.filter { it.isDigit() || it == '.' }?.toDoubleOrNull()
        // No dollar price for what's paid (SOL's is only fetched for a
        // $sol): the quote's worth stands in, which is the same money.
        val paid = dollarsOf(paying, value) ?: quoteOut?.let { out -> unit?.let { out * it } }
        payUsd.text = paid?.let { "≈ ${dollars(it)}" }
            ?: if (value == null && !editing) "Tap to type an amount" else ""
        payToken.text = if (editing) "Done" else "${glyph(paying)}${paying.symbol} ▾"
        payToken.setTextColor(if (editing) blue else palette.ink)
        // The pad has its own 25%, 50% and Max: one set on screen.
        for (b in shareButtons) b.visibility = if (editing) View.GONE else View.VISIBLE
        payHeld.text = when {
            !connected -> ""
            balanceKnown -> "${glyph(paying)}${compact(paying.amount)}"
            else -> "…"
        }
        getToken.text = buy.symbol
        val out = quoteOut
        getAmount.text = out?.let { compact(it) } ?: if (value != null && quoting) "…" else "0"
        getAmount.setTextColor(if (out != null) palette.ink else palette.inkSoft)
        val line = mutableListOf<String>()
        if (value != null && out == null && !quoting) line.add("No price right now")
        if (out != null && unit != null) line.add("≈ ${dollars(out * unit)}")
        buy.price?.let { line.add("1 ${buy.symbol} = $it") }
        getUsd.text = line.joinToString(" · ")
        val short = value != null && balanceKnown && value > spendable() + 1e-9
        go.text = when {
            value == null -> "Enter an amount"
            short -> "Not enough ${paying.symbol}"
            else -> "Buy " + (paid?.let { "≈ ${dollars(it)} of " } ?: "") + buy.symbol
        }
        go.alpha = if (value == null || short) 0.45f else 1f
    }

    /** The panel's own digits, shown while the amount is typed. */
    private fun buildPad() {
        val rows = listOf(listOf("1", "2", "3", "4", "5"), listOf("6", "7", "8", "9", "0"),
                          listOf("25%", "50%", "Max", ".", "⌫"))
        for (row in rows) {
            val line = LinearLayout(context)
            line.orientation = LinearLayout.HORIZONTAL
            for (key in row) {
                val b = TextView(context)
                b.text = key
                b.textSize = if (key.length > 1 && key != "⌫") 12.5f else 18f
                b.gravity = Gravity.CENTER
                b.setTextColor(palette.ink)
                b.background = GradientDrawable().apply {
                    cornerRadius = dp(9).toFloat(); setColor(palette.key)
                }
                b.setTag(com.arpit.glyf.R.id.qa_id, "pay:key:$key")
                b.setOnClickListener { padTap(key) }
                line.addView(b, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f).apply {
                    leftMargin = dp(3); rightMargin = dp(3)
                })
            }
            pad.addView(line, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).apply {
                topMargin = dp(3); bottomMargin = dp(3)
            })
        }
    }

    private fun padTap(key: String) {
        when (key) {
            "⌫" -> if (amount.isNotEmpty()) amount = amount.dropLast(1)
            "25%" -> takePercent(0.25)
            "50%" -> takePercent(0.5)
            "Max" -> takePercent(1.0)
            else -> amount = cleanAmount(amount + key)
        }
        requote()
        render()
    }

    private fun takePercent(share: Double) {
        var held = paying.amount
        if (paying.mint == WSOL) held = (held - 0.005).coerceAtLeast(0.0)
        if (held <= 0) { onToast("Nothing to take a share of yet"); return }
        val places = if (paying.mint == USDC) 2 else minOf(6, paying.decimals)
        val factor = Math.pow(10.0, places.toDouble())
        amount = trimZeros("%.${places}f".format(Math.floor(held * share * factor) / factor))
    }

    // MARK: state

    private val amountValue: Double?
        get() = amount.toDoubleOrNull()?.takeIf { it > 0 }

    private fun beginAmount() {
        if (!formReady() || editing) return
        editing = true
        render()
    }

    private fun endAmount() {
        if (!editing) return
        editing = false
        render()
    }

    private fun formReady() = connected

    private fun pasteAddress() {
        val copied = clipText() ?: ""
        val p = Smart.payment(copied)
        if (p == null) { onToast("Copy a Solana wallet address first"); return }
        if (p.first == walletAddress) { onToast("That’s your own wallet"); return }
        to = p.first
        val asked = p.second ?: Smart.amountAsked(copied)
        if (asked != null) {
            amount = cleanAmount(asked.first)
            paying = assets.firstOrNull {
                it.mint == (if (asked.second == "SOL") WSOL else USDC)
            } ?: paying
        }
        render()
    }

    private fun goIfReady() {
        if (editing) { endAmount(); if (amountValue == null) return }
        if (!isBuy && to == null) {
            // Send with nowhere to send: try the clipboard right here.
            pasteAddress()
            if (to == null) return
        }
        val value = amountValue ?: run { beginAmount(); return }
        if (isBuy && balanceKnown && value > spendable() + 1e-9) {
            onToast("Not enough ${paying.symbol}")
            return
        }
        val query = mutableMapOf<String, String>()
        when (intent) {
            is Intent.Send -> {
                val address = to ?: return
                query += mapOf("kind" to "send", "to" to address, "amount" to amount,
                    "mint" to paying.mint, "symbol" to paying.symbol,
                    "decimals" to paying.decimals.toString())
                if (isPrivate && paying.mint == USDC) query["private"] = "1"
            }
            is Intent.Buy -> {
                query += mapOf("kind" to "buy", "mint" to intent.mint, "symbol" to intent.symbol,
                    "amount" to amount, "sellMint" to paying.mint,
                    "sellSymbol" to paying.symbol, "sellDecimals" to paying.decimals.toString())
            }
        }
        onHandOff(query)
    }

    // MARK: what the wallet holds (through the app's relay)

    private fun loadAssets() {
        val address = walletAddress ?: return
        rpc("getBalance", JSONArray().put(address).put(JSONObject().put("commitment", "confirmed"))) { result ->
            val lamports = (result as? JSONObject)?.opt("value") as? Number ?: return@rpc
            balanceKnown = true
            upsert(Asset(WSOL, "SOL", 9, lamports.toDouble() / 1e9))
        }
        rpc("getTokenAccountsByOwner", JSONArray().put(address)
            .put(JSONObject().put("programId", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"))
            .put(JSONObject().put("encoding", "jsonParsed").put("commitment", "confirmed"))) { result ->
            val accounts = (result as? JSONObject)?.optJSONArray("value") ?: return@rpc
            val held = mutableListOf<Triple<String, Int, Double>>()
            for (i in 0 until accounts.length()) {
                val info = accounts.optJSONObject(i)?.optJSONObject("account")
                    ?.optJSONObject("data")?.optJSONObject("parsed")?.optJSONObject("info") ?: continue
                val mint = info.optString("mint")
                val tokenAmount = info.optJSONObject("tokenAmount") ?: continue
                val ui = tokenAmount.optDouble("uiAmount", 0.0)
                if (mint.isEmpty() || ui <= 0) continue
                held.add(Triple(mint, tokenAmount.optInt("decimals", 6), ui))
            }
            for ((mint, decimals, ui) in held.sortedByDescending { it.third }.take(8)) {
                if (mint == USDC) { upsert(Asset(mint, "USDC", decimals, ui)); continue }
                upsert(Asset(mint, Smart.shortAddress(mint), decimals, ui))
                tokenMeta(mint) { symbol, _ ->
                    if (symbol != null) assets.firstOrNull { it.mint == mint }?.let {
                        upsert(it.copy(symbol = symbol).let { c -> Asset(c.mint, c.symbol, c.decimals, c.amount) })
                    }
                }
            }
        }
    }

    private fun upsert(asset: Asset) {
        val i = assets.indexOfFirst { it.mint == asset.mint }
        if (i >= 0) assets[i] = asset else assets.add(asset)
        fun rank(x: Asset) = when (x.mint) { WSOL -> 0; USDC -> 1; else -> 2 }
        assets.sortWith(compareBy({ rank(it) }, { -it.amount }))
        assets.firstOrNull { it.mint == paying.mint }?.let { paying = it }
        render()
    }

    private fun tokenMeta(mint: String, done: (String?, Int?) -> Unit) {
        http("GET", "$backendURL/rates/token?mint=$mint", null) { obj ->
            val token = obj?.optJSONObject("token")
            done(token?.optString("symbol")?.takeIf { it.isNotEmpty() },
                 token?.optInt("decimals", -1)?.takeIf { it >= 0 })
        }
    }

    private fun rpc(method: String, params: JSONArray, done: (Any?) -> Unit) {
        http("POST", "$backendURL/wallet/rpc",
             JSONObject().put("method", method).put("params", params)) { obj ->
            done(obj?.opt("result"))
        }
    }

    /** Jupiter's keyless price for the typed amount, debounced by token. */
    private fun requote() {
        if (intent !is Intent.Buy) return
        val token = ++quoteToken
        val value = amountValue
        if (value == null) { quote = null; quoteOut = null; quoting = false; return }
        quoting = true
        main.postDelayed({
            if (token != quoteToken) return@postDelayed
            val units = (value * Math.pow(10.0, paying.decimals.toDouble())).toLong()
            if (units <= 0) return@postDelayed
            val url = "https://api.jup.ag/swap/v2/order?inputMint=${paying.mint}" +
                "&outputMint=${URLEncoder.encode(intent.mint, "UTF-8")}&amount=$units"
            http("GET", url, null, raw = true) { obj ->
                if (token != quoteToken) return@http
                quoting = false
                val out = obj?.optString("outAmount")?.toDoubleOrNull()
                val decimals = targetDecimals
                quoteOut = if (out != null && decimals != null) out / Math.pow(10.0, decimals.toDouble()) else null
                quote = quoteOut?.let { "≈ ${compact(it)} ${intent.symbol}" }
                render()
            }
        }, 400)
    }

    /** `raw` skips the `ok` envelope (Jupiter's own API). */
    private fun http(method: String, url: String, body: JSONObject?, raw: Boolean = false,
                     done: (JSONObject?) -> Unit) {
        pool.execute {
            var conn: HttpURLConnection? = null
            val obj = try {
                conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    connectTimeout = 5000
                    readTimeout = 8000
                    if (!raw) BackendClient.bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
                    if (body != null) {
                        doOutput = true
                        setRequestProperty("content-type", "application/json")
                        outputStream.bufferedWriter().use { it.write(body.toString()) }
                    }
                }
                val parsed = JSONObject(conn.inputStream.bufferedReader().readText())
                if (raw || parsed.optBoolean("ok")) parsed else null
            } catch (e: Exception) {
                android.util.Log.w("GlyfKB", "pay $url: $e")
                null
            } finally {
                conn?.disconnect()
            }
            main.post { done(obj) }
        }
    }

    // MARK: render

    private fun render() {
        val form = formReady() && !editing
        val needsConnect = !connected

        header.visibility = View.VISIBLE
        balance.visibility = if (form || editing) View.VISIBLE else View.GONE
        amountRow.visibility = if (form || editing) View.VISIBLE else View.GONE
        assetsScroll.visibility = if (form) View.VISIBLE else View.GONE
        privateRow.visibility =
            if (form && !isBuy && paying.mint == USDC) View.VISIBLE else View.GONE
        meta.visibility =
            if (form && privateRow.visibility != View.VISIBLE) View.VISIBLE else View.GONE
        go.visibility = if (form) View.VISIBLE else View.GONE
        pad.visibility = if (editing) View.VISIBLE else View.GONE
        lead.visibility = if (needsConnect) View.VISIBLE else View.GONE
        cta.visibility = lead.visibility

        if (needsConnect) {
            lead.text = "Connect Phantom once in the app; after that you pay right here."
            cta.text = "Connect Phantom"
            cta.setTag(com.arpit.glyf.R.id.qa_id, "pay:connect")
            cta.setOnClickListener { onConnect() }
        }

        val shownAmount = if (amount.isEmpty()) "0" else amount
        amountText.text = if (paying.mint == USDC) "$$shownAmount" else shownAmount
        unitText.text = if (isBuy) "of ${paying.symbol}" else paying.symbol
        when (intent) {
            is Intent.Send -> {
                if (to != null) {
                    toName.text = "Wallet"
                    toName.setTextColor(palette.ink)
                    toDetail.text = Smart.shortAddress(to ?: "")
                } else {
                    // The slot itself asks, the way the website's panel does.
                    toName.text = "Paste address"
                    toName.setTextColor(blue)
                    toDetail.text = "from the chat"
                }
                meta.text = "Phantom signs · nothing moves without you"
                go.text = if (isPrivate && paying.mint == USDC) "Send privately" else "Send"
            }
            is Intent.Buy -> {
                toName.text = quote ?: intent.symbol
                toDetail.text = intent.price?.let {
                    if (quote != null) "1 ${intent.symbol} = $it" else it
                } ?: ""
                meta.text = "Best route via Jupiter · Phantom signs"
                go.text = "Buy"
            }
        }
        privateBy.text = if (isPrivate) "≈0.002 SOL + 0.1% · off-chain" else "by MagicBlock"
        privateSwitch.isChecked = isPrivate
        privateSwitch.thumbTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
        privateSwitch.trackTintList = android.content.res.ColorStateList.valueOf(
            if (isPrivate) green else soft(60, palette.inkSoft))
        go.alpha = if (amountValue != null && (isBuy || to != null)) 1f else 0.45f

        // Balance in the header: "$12.40 USDC · ◎ 0.2".
        val usdcHeld = assets.firstOrNull { it.mint == USDC }?.amount ?: 0.0
        val solHeld = assets.firstOrNull { it.mint == WSOL }?.amount ?: 0.0
        balance.text = if (connected) "$${compact(usdcHeld)} USDC · ◎ ${compact(solHeld)}" else ""

        assetsRow.removeAllViews()
        if (form) for (asset in assets) {
            val on = asset.mint == paying.mint
            val b = TextView(context)
            val held = if (asset.amount > 0) " ${compact(asset.amount)}" else ""
            b.text = "${asset.symbol}$held"
            b.textSize = 12f
            b.typeface = Typeface.DEFAULT_BOLD
            b.setTextColor(if (on) palette.board else palette.ink)
            b.background = chipBg(on)
            b.gravity = Gravity.CENTER
            b.setPadding(dp(10), 0, dp(10), 0)
            b.setTag(com.arpit.glyf.R.id.qa_id, "pay:asset:${asset.symbol}")
            b.setOnClickListener {
                paying = asset
                if (asset.mint != USDC) isPrivate = false
                requote()
                render()
            }
            assetsRow.addView(b, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, dp(26)).apply { rightMargin = dp(6) })
        }

        // While typing, the amount row doubles as the display and the pad
        // fills the key area; Done is the row itself. Otherwise the
        // recipient slot is its own tap: paste (or re-paste) the address.
        if (editing) {
            amountRow.setOnClickListener { endAmount() }
            toCol.setOnClickListener { endAmount() }
            toName.text = "Done"
            toName.setTextColor(blue)
            toDetail.text = ""
        } else {
            amountRow.setOnClickListener { beginAmount() }
            toCol.setTag(com.arpit.glyf.R.id.qa_id, "pay:to")
            toCol.setOnClickListener { if (isBuy) beginAmount() else pasteAddress() }
        }

        // A buy is its two cards: the token list only when its pill is
        // tapped, and the header's balance moves into You pay.
        if (isBuy) {
            // The strip names the buy, as on iOS: no header in the panel.
            header.visibility = View.GONE
            meta.visibility = if (form && tall) View.VISIBLE else View.GONE
            amountRow.visibility = View.GONE
            balance.visibility = View.GONE
            payCard.visibility = if (form || editing) View.VISIBLE else View.GONE
            getCard.visibility = if (form && !picking) View.VISIBLE else View.GONE
            assetsScroll.visibility = if (form && picking) View.VISIBLE else View.GONE
            if (picking) for (i in 0 until assetsRow.childCount) {
                val b = assetsRow.getChildAt(i)
                val asset = assets.getOrNull(i) ?: continue
                b.setOnClickListener {
                    paying = asset
                    picking = false
                    requote()
                    render()
                }
            }
            renderBuy()
        }
    }
}
