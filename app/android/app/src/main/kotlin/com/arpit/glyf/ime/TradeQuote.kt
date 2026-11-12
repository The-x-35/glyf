package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * The trade panel's numbers, kept out of the view so they are tested
 * (TradeQuoteTest): what is asked of the server's /uniswap and /flash
 * routes, how their answers read, and what the one button says. The quote
 * here is Uniswap's, NEAR Intents' across chains (POST /near/quote), or the
 * price an order waits on; the app asks again at signing, so nothing shown
 * is signed. Mirrors TradeSurface.swift.
 */
object TradeQuote {

    /** A swap's live quote: what comes back, both sides in dollars, or the
     *  server's refusal in one short line. */
    data class Quote(val out: Double? = null, val inUsd: Double? = null, val outUsd: Double? = null,
                     val error: String? = null)

    /** The one button: its words, whether it is greyed, and whether a tap
     *  opens the app's Wallet page to connect one first. [red]: Guard
     *  stopped a NEAR Intents send and the button is a red "Send anyway"
     *  (the hand-off then says anyway=1). */
    data class Go(val title: String, val blocked: Boolean, val connect: Boolean, val red: Boolean = false)

    /** What a swap's quote asks POST /uniswap/quote; null when there is
     *  nothing to ask (a problem, or no amount yet). "buy 0.1 eth" asks the
     *  other way round: what 0.1 ETH costs. */
    fun body(i: TradeIntent): JSONObject? {
        if (i.kind != TradeIntent.Kind.SWAP || TradeEdit.problem(i) != null || i.chainName == "solana") return null
        val reversed = i.buyAmount != null
        val amount = (if (reversed) i.buyAmount else i.amount) ?: return null
        val buyChain = i.buyChain ?: i.chainName
        val sellRef = i.sellAddress ?: i.sell
        val buyRef = i.buyAddress ?: i.buy
        val b = JSONObject()
            .put("chain", if (reversed) buyChain else i.chainName)
            .put("sell", if (reversed) buyRef else sellRef)
            .put("buy", if (reversed) sellRef else buyRef)
            .put("amount", amount)
        if (buyChain != i.chainName) b.put("buyChain", if (reversed) i.chainName else buyChain)
        return b
    }

    /** The server's answer to [body], the sides put back when it was asked reversed. */
    fun read(ok: Boolean, json: JSONObject?, reversed: Boolean): Quote {
        if (!ok || json == null || !json.has("amountOut")) return Quote(error = shortError(json?.opt("error") as? String))
        val inUsd = num(json.opt("sellUsd")) ?: num(json.optJSONObject("sell")?.opt("usd"))
        val outUsd = num(json.opt("buyUsd")) ?: num(json.optJSONObject("buy")?.opt("usd"))
        return Quote(num(json.opt("amountOut")), if (reversed) outUsd else inUsd, if (reversed) inUsd else outUsd)
    }

    /** A Solana swap's quote from Jupiter's prices for both sides ([usd]
     *  the dollars per token, the panel's RatesStore); the app asks Jupiter
     *  for the real order before anything is signed. Null until both
     *  prices are known. */
    fun jupiter(i: TradeIntent, usd: (String) -> Double?): Quote? {
        val reversed = i.buyAmount != null
        val n = TradeIntent.number(((if (reversed) i.buyAmount else i.amount) ?: return null).replace(",", "")) ?: return null
        fun price(s: String) = if (s in TradeEdit.stables) 1.0 else usd(s)
        val sell = price(i.sell)?.takeIf { it > 0 } ?: return null
        val buy = price(i.buy)?.takeIf { it > 0 } ?: return null
        // Forward: what n of the sell side gets. Reversed: what n of the buy
        // side costs, in the sell side.
        val out = if (reversed) n * buy / sell else n * sell / buy
        val dollars = n * if (reversed) buy else sell
        return Quote(out, dollars, dollars)
    }

    /** One short line from the server's words. */
    fun shortError(raw: String?): String {
        if (raw.isNullOrEmpty()) return "No quote right now"
        if (raw.length <= 60) return raw
        return raw.take(57) + "…"
    }

    /** What one [symbol] is worth in USDC on [chain], asked of POST
     *  /uniswap/quote: an order's market price. [address] is the picked
     *  contract, when there is one. */
    fun priceBody(chain: String, symbol: String, address: String?): JSONObject =
        JSONObject().put("chain", chain).put("sell", TradeIntent.baseStocks[symbol.uppercase(Locale.US)] ?: address ?: symbol)
            .put("buy", "USDC").put("amount", "1")

    /** A Base share's price, from Flash's own listing (GET /flash/search):
     *  some shares, Tesla's among them, have no Uniswap pool on Base, and
     *  Flash trades them anyway. */
    fun sharePrice(json: JSONObject?, address: String): Double? {
        val rows: JSONArray = json?.optJSONArray("results") ?: json?.optJSONArray("assets")
            ?: json?.optJSONArray("tokens") ?: return null
        for (k in 0 until rows.length()) {
            val row = rows.optJSONObject(k) ?: continue
            if ((row.opt("address") as? String)?.lowercase(Locale.US) == address.lowercase(Locale.US)) return num(row.opt("price"))
        }
        return null
    }

    /** GET /evm/balances: whole tokens held, by symbol (the gas coin as ETH). */
    fun balances(json: JSONObject?): Map<String, Double>? {
        val rows = json?.optJSONArray("balances") ?: return null
        val out = mutableMapOf<String, Double>()
        for (k in 0 until rows.length()) {
            val row = rows.optJSONObject(k) ?: continue
            val symbol = (row.opt("symbol") as? String ?: "").uppercase(Locale.US)
            out[if (symbol == "NATIVE") "ETH" else symbol] = num(row.opt("amount")) ?: num(row.opt("balance")) ?: 0.0
        }
        return out
    }

    /** The wallet knows what's held and it's short of what's spent. */
    fun short(i: TradeIntent, held: Double?, quoteOut: Double?, nearIn: Double? = null): Boolean {
        if (i.chainName == "solana" || held == null) return false
        if (!(TradeEdit.sells(i) || i.amountIsUSD || i.buyAmount != null || i.kind == TradeIntent.Kind.TWAP)) return false
        if (i.amount == null && i.buyAmount == null) return held <= 0
        // A NEAR Intents send spends what the quote says it costs.
        val spend = (if (nearSend(i)) nearIn else if (i.buyAmount != null) quoteOut else TradeIntent.number(i.amount)) ?: return false
        return spend > held + 1e-12
    }

    /** What the button says first: no wallet, then what's wrong, then the
     *  trade. A send waits for its address ([resolved], what its name points
     *  at; the typed address as is) and never goes to a name that didn't
     *  resolve ([resolveProblem]). */
    fun go(i: TradeIntent, wallet: String?, asking: Boolean, quote: Quote?, held: Double?,
           resolved: String? = null, resolveProblem: String? = null, near: NearQuote? = null): Go {
        // NEAR Intents: a block outranks everything and says what to fix; a
        // lookalike may be the person's own new address, so it offers a red
        // "Send anyway" once nothing else stops the send.
        val alert = alert(i, near, resolveProblem)
        if (alert != null && alert.block && alert.fix != null) return Go(alert.fix, true, false)
        val anyway = alert != null && alert.block
        // A chain Glyf can't sign on (Bitcoin, NEAR…) needs no wallet: the app
        // shows the deposit address to pay from any wallet.
        val signs = i.chainName == "solana" || i.chainName in TradeIntent.evmChains
        if (signs && wallet.isNullOrEmpty()) {
            val title = if (anyway) "Send anyway" else "Connect ${TradeIntent.walletName(i.chainName)}"
            return Go(title, blocked = false, connect = true, red = anyway)
        }
        val isSwap = i.kind == TradeIntent.Kind.SWAP
        val quotes = quotes(i)
        fun stop(title: String) = Go(if (anyway) "Send anyway" else title, true, false)
        TradeEdit.problem(i)?.let { return stop(it) }
        if (i.awaitingPrice) return stop(if (asking) "Getting the price" else "No price yet")
        if (quotes) quote?.error?.let { return stop(it) }
        if (short(i, held, quote?.out, near?.amountIn)) return stop(if (i.isNear) haveText(i, held) else "Not enough ${display(i.sell)}")
        if (anyway) {
            val waits = (quotes && asking) || (i.kind == TradeIntent.Kind.SEND && (resolved == null || resolveProblem != null))
            return Go("Send anyway", blocked = waits, connect = false, red = !waits)
        }
        val title = when (i.kind) {
            TradeIntent.Kind.SWAP -> quote?.inUsd?.let { "Swap ≈ ${dollars(it)}" } ?: "Swap"
            TradeIntent.Kind.LIMIT -> "Place limit order"
            TradeIntent.Kind.STOP -> "Place stop buy"
            TradeIntent.Kind.STOP_LOSS -> "Place stop-loss"
            TradeIntent.Kind.TAKE_PROFIT -> "Place take profit"
            TradeIntent.Kind.BRACKET -> "Set bracket"
            TradeIntent.Kind.TRAILING_STOP -> "Set trailing stop"
            TradeIntent.Kind.TWAP -> "Start TWAP"
            TradeIntent.Kind.BRIDGE -> "Move to ${TradeIntent.chainLabels[i.toChain ?: ""] ?: TradeIntent.capitalized(i.toChain ?: "")}"
            // What's sent is what arrives (a NEAR Intents send may pay in another coin).
            TradeIntent.Kind.SEND -> resolveProblem
                ?: if (resolved == null) "Looking up ${i.to ?: ""}" else "Send ${i.amount ?: ""} ${display(i.buy)}"
        }
        if (i.kind == TradeIntent.Kind.SEND) return Go(title, resolved == null || resolveProblem != null || (quotes && asking), false)
        return Go(title, quotes && asking, false)
    }

    /** What the app is handed (glyf://open?path=trade?…): the trade's own
     *  words and its title, for the Trade screen to quote again and sign. */
    fun handOff(i: TradeIntent, resolved: String? = null, anyway: Boolean = false): Map<String, String> {
        var q = i.query + ("title" to i.title)
        if (i.kind == TradeIntent.Kind.SEND && resolved != null) q = q + ("address" to resolved)
        // Guard stopped it and the person tapped Send anyway.
        if (anyway) q = q + ("anyway" to "1")
        return q
    }

    /** Where a hand-off goes in the app: a Solana send to the existing
     *  Phantom send (path pay), everything else to the Trade screen, which
     *  asks MetaMask (or Phantom for a Flash order on Solana). */
    fun destination(query: Map<String, String>): Pair<String, Map<String, String>> =
        TradeIntent.phantomSend(query)?.let { "pay" to it } ?: ("trade" to query)

    /** A send's rows under its amount: To (the name, or the address short)
     *  and, for a name, the Address it points at once GET /names/resolve has
     *  answered ([resolved]; "Not found" with a [problem], "…" until then). */
    fun sendRows(i: TradeIntent, resolved: String?, problem: String?): List<Pair<String, String>> {
        val to = i.to ?: ""
        val rows = mutableListOf("To" to TradeIntent.shortRecipient(to))
        if (TradeIntent.isName(to)) rows.add("Address" to (resolved?.let { Smart.shortAddress(it) } ?: if (problem == null) "…" else "Not found"))
        return rows
    }

    /** What a typed token search asks Uniswap's list (GET /uniswap/tokens);
     *  null when nothing is asked: no words yet, or Solana (Jupiter's tokens
     *  come from the phone's own short list there). */
    fun tokenSearchPath(chain: String, query: String): String? {
        val q = query.trim()
        // Uniswap's token list is for its own chains.
        if (q.isEmpty() || chain !in TradeIntent.uniswapReach) return null
        return "/uniswap/tokens?chain=$chain&q=${java.net.URLEncoder.encode(q, "UTF-8")}&limit=40"
    }

    /** The picker's rows for a search: what the phone already has that
     *  matches, then what Uniswap's list answered, once each. */
    fun searchRows(known: List<TokenPick>, server: List<TokenPick>, query: String): List<TokenPick> =
        TradeEdit.merge(TradeEdit.filter(TradeEdit.merge(known, server), query), server)

    /** The strip's name for the panel. */
    fun headerTitle(kind: TradeIntent.Kind): String = when (kind) {
        TradeIntent.Kind.SWAP -> "Swap"
        TradeIntent.Kind.LIMIT -> "Limit order"
        TradeIntent.Kind.STOP -> "Stop buy"
        TradeIntent.Kind.STOP_LOSS -> "Stop-loss"
        TradeIntent.Kind.TAKE_PROFIT -> "Take profit"
        TradeIntent.Kind.BRACKET -> "Bracket"
        TradeIntent.Kind.TRAILING_STOP -> "Trailing stop"
        TradeIntent.Kind.TWAP -> "TWAP"
        TradeIntent.Kind.BRIDGE -> "Bridge"
        TradeIntent.Kind.SEND -> "Send"
    }

    /** The top card's key: You pay on a swap, else what the order does. */
    fun topKey(i: TradeIntent): String = when (i.kind) {
        TradeIntent.Kind.SWAP -> "You pay"
        TradeIntent.Kind.SEND -> "Send"
        TradeIntent.Kind.BRIDGE -> "Move"
        TradeIntent.Kind.TWAP -> "Spend"
        else -> if (TradeEdit.sells(i)) "Sell" else "Buy"
    }

    /** "4,426,585.96", "0.011253": grouped, with as many places as matter. */
    fun amount(v: Double): String {
        val f = java.text.NumberFormat.getNumberInstance(Locale.US)
        f.maximumFractionDigits = if (v >= 1000) 2 else if (v >= 1) 4 else 6
        f.minimumFractionDigits = 0
        return f.format(v)
    }

    /** "$1,234", "$12.50" (PayPanelView's dollars). */
    fun dollars(v: Double): String {
        val f = java.text.NumberFormat.getCurrencyInstance(Locale.US)
        f.maximumFractionDigits = if (v >= 100) 0 else 2
        return f.format(v)
    }

    /** Dollars as the panel says them; a dust amount isn't "$0.00". */
    fun approx(v: Double): String = if (v > 0 && v < 0.01) "< $0.01" else "≈ " + dollars(v)

    fun display(symbol: String): String = if (symbol == "CBBTC") "cbBTC" else symbol

    fun num(any: Any?): Double? = when (any) {
        is Number -> any.toDouble()
        is String -> TradeIntent.number(any)
        else -> null
    }

    // MARK: NEAR Intents (TradeSurface.swift's NEAR panel)

    /** The panel quotes it as it changes: a swap, or a NEAR Intents send. */
    fun quotes(i: TradeIntent): Boolean = i.kind == TradeIntent.Kind.SWAP || i.isNear

    /** A NEAR Intents send: what arrives is set, what pays is quoted. */
    fun nearSend(i: TradeIntent): Boolean = i.kind == TradeIntent.Kind.SEND && i.isNear

    /** What NEAR Intents' quote asks POST /near/quote, dry: no refund
     *  address, so 1Click makes no deposit address for a preview. A send
     *  asks for exactly what the recipient gets. The recipient (with the
     *  ones paid before, [recent]) lets Guard check it. The app asks again
     *  with both before anything is signed. Null with no amount or a
     *  problem. */
    fun nearBody(i: TradeIntent, recent: List<String> = emptyList()): JSONObject? {
        if (!i.isNear || TradeEdit.problem(i) != null) return null
        val amount = i.amount ?: return null
        val b = JSONObject()
            .put("sell", i.sellAddress ?: i.sell).put("sellChain", i.chainName)
            .put("buy", i.buyAddress ?: i.buy).put("buyChain", i.buyChain ?: i.chainName)
            .put("amount", amount)
            .put("exact", if (i.kind == TradeIntent.Kind.SEND) "out" else "in")
            .put("slippage", 1)
        i.to?.let { to ->
            b.put("recipient", to)
            b.put("recent", JSONArray(recent.take(20)))
        }
        return b
    }

    /** What stops or questions a NEAR Intents trade, for the line over the
     *  button: a name with no account, or Guard's worst check. [fix] is the
     *  button's words when it blocks; null there means "Send anyway" (a
     *  lookalike may be the person's own new address). */
    data class Alert(val text: String, val block: Boolean, val fix: String?)

    fun alert(i: TradeIntent, near: NearQuote?, resolveProblem: String?): Alert? {
        if (!i.isNear) return null
        if (i.kind == TradeIntent.Kind.SEND && resolveProblem != null) {
            return Alert(resolveProblem, true, if (TradeIntent.isName(i.to)) "Check the name" else "Check the address")
        }
        val level = near?.guardLevel ?: return null
        val text = near.guardText ?: if (level == "block") "Guard stopped this" else "Take a look first"
        if (level != "block") return Alert(text, false, null)
        return when (near.guardId) {
            "lookalike" -> Alert(text, true, null)
            "no-account" -> Alert(text, true, "Check the name")
            else -> Alert(text, true, "Check the address")
        }
    }

    /** "You have 2.10 USDC", or "No USDC on Base": what's held, when it's
     *  short of a NEAR Intents trade. */
    fun haveText(i: TradeIntent, held: Double?): String {
        val symbol = display(i.sell)
        val have = held ?: return "Not enough $symbol"
        if (have <= 0) return "No $symbol on ${TradeIntent.label(i.chainName)}"
        val shown = if (i.sell in TradeEdit.stables) String.format(Locale.US, "%.2f", have) else amount(have)
        return "You have $shown $symbol"
    }

    /** The strip's name for the panel: who carries it sits in the header
     *  for a NEAR Intents trade ("Swap via NEAR Intents"), so the rows stay
     *  short. */
    fun headerTitle(i: TradeIntent): String {
        if (!i.isNear) return headerTitle(i.kind)
        val kind = if (i.kind == TradeIntent.Kind.SWAP && i.sell == i.buy) "Move" else headerTitle(i.kind)
        return "$kind via NEAR Intents"
    }

    /** The strip's header mark: NEAR's N for a NEAR Intents trade. */
    fun headerIcon(i: TradeIntent): String = if (i.isNear) SponsorMenu.Sponsor.NEAR.screenId else "trend"

    /** One row of a NEAR send's values. [red] for a name Guard stops, [check]
     *  for a name NEAR says is there. */
    data class Row(val id: String, val label: String, val value: String, val tap: Boolean = false,
                   val bold: Boolean = false, val red: Boolean = false, val check: Boolean = false)

    /** A NEAR send's rows under what arrives: To (a name as typed, an
     *  address shortened), You pay (≈ the cost and its chain; a tap picks
     *  another chain) and Arrives, whose time moves to the card's line when
     *  an alert takes the room. */
    fun nearSendRows(i: TradeIntent, near: NearQuote?, asking: Boolean, resolved: String?, resolveProblem: String?): List<Row> {
        val to = i.to ?: ""
        val name = TradeIntent.isName(to)
        val alert = alert(i, near, resolveProblem)
        val rows = mutableListOf(Row("to", "To", if (name) to else Smart.shortAddress(to), red = alert?.block == true,
            check = name && resolved != null && resolveProblem == null))
        val pay = near?.amountIn?.let { "≈ ${amount(it)} ${display(i.sell)}" } ?: if (asking) "…" else display(i.sell)
        rows.add(Row("pay", "You pay", "$pay · ${TradeIntent.label(i.chainName)}", tap = true, bold = true))
        if (alert == null) rows.add(Row("arrives", "Arrives", near?.time ?: if (asking) "…" else "—"))
        return rows
    }

    /** A row's value at the largest size from 15 down to 11 (half points)
     *  that fits one line, else on two lines; never cut with "…". Pure:
     *  `measure(text, size)` is the text's width at that size, in the unit
     *  of [width]. Returns (size, lines). */
    fun rowFit(text: String, width: Double, measure: (String, Double) -> Double): Pair<Double, Int> {
        var s = 15.0
        while (s >= 11.0 - 0.001) {
            if (measure(text, s) <= width) return s to 1
            s -= 0.5
        }
        // Wrapped at any character (an address has no spaces): two lines
        // hold a little under twice the room.
        s = 15.0
        while (s > 11.0 + 0.001) {
            if (measure(text, s) <= width * 2 * 0.94) return s to 2
            s -= 0.5
        }
        return 11.0 to 2
    }
}

/** What POST /near/quote said, as the trade panel shows it (TradeIntent.swift's
 *  NearQuote). Pure, so NearIntentTest pins how an answer reads. */
data class NearQuote(
    val amountIn: Double? = null,
    val amountOut: Double? = null,
    val inUsd: Double? = null,
    val outUsd: Double? = null,
    val seconds: Int? = null,
    /** Guard's worst finding: "warn" or "block", with its words. */
    val guardLevel: String? = null,
    val guardText: String? = null,
    /** Which check it was ("lookalike", "no-account", "chain-mismatch"…). */
    val guardId: String? = null,
    /** The server's words when there's no quote. */
    val error: String? = null,
) {
    /** "~32 s", "~2 min". */
    val time: String?
        get() {
            val s = seconds ?: return null
            if (s <= 0) return null
            return if (s < 90) "~$s s" else "~${TradeIntent.rounded(s / 60.0).toInt()} min"
        }

    companion object {
        fun read(ok: Boolean, json: JSONObject?): NearQuote {
            val out = TradeQuote.num(json?.opt("amountOut"))
            if (!ok || json == null || json.opt("ok") == false || out == null) {
                val words = json?.opt("error") as? String
                return NearQuote(error = if (words.isNullOrEmpty()) "No quote right now" else words)
            }
            val checks = json.optJSONObject("guard")?.optJSONArray("checks")
            var level: String? = null
            var text: String? = null
            var id: String? = null
            // A block outranks a warning; "ok" says nothing.
            for (want in listOf("block", "warn")) {
                val c = (0 until (checks?.length() ?: 0)).mapNotNull { checks!!.optJSONObject(it) }
                    .firstOrNull { it.opt("level") == want } ?: continue
                level = want
                text = c.opt("text") as? String
                id = c.opt("id") as? String
                break
            }
            if (level == null) (json.optJSONObject("guard")?.opt("level") as? String)?.takeIf { it != "ok" }?.let { level = it }
            return NearQuote(
                amountIn = TradeQuote.num(json.opt("amountIn")), amountOut = out,
                inUsd = TradeQuote.num(json.opt("amountInUsd")), outUsd = TradeQuote.num(json.opt("amountOutUsd")),
                seconds = TradeQuote.num(json.opt("timeSeconds"))?.let { TradeIntent.rounded(it).toInt() },
                guardLevel = level, guardText = text, guardId = id,
            )
        }
    }
}

