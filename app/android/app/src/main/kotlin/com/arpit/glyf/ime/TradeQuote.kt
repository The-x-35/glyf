package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * The trade panel's numbers, kept out of the view so they are tested
 * (TradeQuoteTest): what is asked of the server's /uniswap and /flash
 * routes, how their answers read, and what the one button says. The quote
 * here is Uniswap's (or the price an order waits on); the app asks again
 * at signing, so nothing shown is signed. Mirrors TradeSurface.swift.
 */
object TradeQuote {

    /** A swap's live quote: what comes back, both sides in dollars, or the
     *  server's refusal in one short line. */
    data class Quote(val out: Double? = null, val inUsd: Double? = null, val outUsd: Double? = null,
                     val error: String? = null)

    /** The one button: its words, whether it is greyed, and whether a tap
     *  opens the app's Wallet page to connect one first. */
    data class Go(val title: String, val blocked: Boolean, val connect: Boolean)

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
    fun short(i: TradeIntent, held: Double?, quoteOut: Double?): Boolean {
        if (i.chainName == "solana" || held == null) return false
        if (!(TradeEdit.sells(i) || i.amountIsUSD || i.buyAmount != null || i.kind == TradeIntent.Kind.TWAP)) return false
        if (i.amount == null && i.buyAmount == null) return held <= 0
        val spend = (if (i.buyAmount != null) quoteOut else TradeIntent.number(i.amount)) ?: return false
        return spend > held + 1e-12
    }

    /** What the button says first: no wallet, then what's wrong, then the
     *  trade. A send waits for its address ([resolved], what its name points
     *  at; the typed address as is) and never goes to a name that didn't
     *  resolve ([resolveProblem]). */
    fun go(i: TradeIntent, wallet: String?, asking: Boolean, quote: Quote?, held: Double?,
           resolved: String? = null, resolveProblem: String? = null): Go {
        if (wallet.isNullOrEmpty()) return Go("Connect ${TradeIntent.walletName(i.chainName)}", blocked = false, connect = true)
        val isSwap = i.kind == TradeIntent.Kind.SWAP
        TradeEdit.problem(i)?.let { return Go(it, true, false) }
        if (i.awaitingPrice) return Go(if (asking) "Getting the price" else "No price yet", true, false)
        if (isSwap) quote?.error?.let { return Go(it, true, false) }
        if (short(i, held, quote?.out)) return Go("Not enough ${display(i.sell)}", true, false)
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
            TradeIntent.Kind.SEND -> resolveProblem
                ?: if (resolved == null) "Looking up ${i.to ?: ""}" else "Send ${i.amount ?: ""} ${display(i.sell)}"
        }
        if (i.kind == TradeIntent.Kind.SEND) return Go(title, resolved == null || resolveProblem != null, false)
        return Go(title, isSwap && asking, false)
    }

    /** What the app is handed (glyf://open?path=trade?…): the trade's own
     *  words and its title, for the Trade screen to quote again and sign. */
    fun handOff(i: TradeIntent, resolved: String? = null): Map<String, String> {
        val q = i.query + ("title" to i.title)
        return if (i.kind == TradeIntent.Kind.SEND && resolved != null) q + ("address" to resolved) else q
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
        if (q.isEmpty() || chain == "solana") return null
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
}
