package com.arpit.glyf.ime

import org.json.JSONObject
import java.util.Locale
import kotlin.math.max

/** What the trade panel lets a person change (TradeEdit.swift's TradeField). */
enum class TradeField(val id: String) {
    /** What's spent or bought, in the unit [TradeEdit.amountUnit] says. */
    AMOUNT("amount"),
    /** A limit, a trigger, or a bracket's take-profit, in dollars. */
    PRICE("price"),
    /** A bracket's stop-loss, in dollars. */
    STOP_PRICE("stopPrice"),
    /** A trailing stop's distance, in percent. */
    TRAIL("trail"),
    /** A TWAP's length, in days (0.5 = 12 hours). */
    DURATION("duration"),
}

/** A token the picker offers: from GET /uniswap/tokens, or the built-in
 *  few when that can't be had. */
data class TokenPick(
    val symbol: String,
    val name: String,
    val address: String? = null,
    val decimals: Int? = null,
    val logo: String? = null,
    val native: Boolean = false,
) {
    companion object {
        fun fromJson(json: JSONObject): TokenPick? {
            val symbol = json.optString("symbol", "").takeIf { it.isNotEmpty() && !json.isNull("symbol") } ?: return null
            fun str(k: String) = if (json.has(k) && !json.isNull(k)) json.opt(k) as? String else null
            return TokenPick(symbol, str("name") ?: symbol, str("address"),
                (json.opt("decimals") as? Number)?.toInt(), str("logoURI"),
                json.opt("native") as? Boolean ?: false)
        }
    }
}

/**
 * What the trade panel lets a person change, and how each change lands on
 * the trade (TradePanelView). Pure, so the mapping is tested
 * (TradeEditTest): the panel only shows and asks. The twin of
 * TradeEdit.swift, rule for rule. Every function returns a new trade; the
 * one passed in is never changed.
 */
object TradeEdit {

    enum class Side { SELL, BUY }

    /** The unit the amount is typed in. */
    sealed class AmountUnit {
        /** Dollars of what's bought ("$20 of ETH"). */
        object Dollars : AmountUnit()
        /** Whole tokens of what's spent. */
        data class Spend(val symbol: String) : AmountUnit()
        /** Whole tokens of what comes back ("buy 0.1 ETH"). */
        data class Receive(val symbol: String) : AmountUnit()
    }

    val stables = setOf("USDC", "USDT", "DAI")

    // MARK: what's on the panel

    /** A Flash order on what's held sells it; one paid in dollars buys. */
    fun sells(i: TradeIntent): Boolean = when (i.kind) {
        TradeIntent.Kind.SWAP, TradeIntent.Kind.BRIDGE, TradeIntent.Kind.SEND, TradeIntent.Kind.STOP_LOSS,
        TradeIntent.Kind.TAKE_PROFIT, TradeIntent.Kind.TRAILING_STOP -> true
        TradeIntent.Kind.BRACKET -> i.buyAmount == null && !i.amountIsUSD
        TradeIntent.Kind.LIMIT -> i.sell !in stables
        else -> false
    }

    /** The asset an order is about (the side that isn't dollars). */
    fun asset(i: TradeIntent): String {
        if (i.kind == TradeIntent.Kind.SWAP || i.kind == TradeIntent.Kind.BRIDGE || i.kind == TradeIntent.Kind.SEND) return i.sell
        return if (sells(i)) i.sell else i.buy
    }

    fun amountUnit(i: TradeIntent): AmountUnit {
        if (i.amountIsUSD) return AmountUnit.Dollars
        if (i.buyAmount != null) return AmountUnit.Receive(i.buy)
        if (i.kind == TradeIntent.Kind.TWAP) return AmountUnit.Dollars
        if (!sells(i) && i.kind in listOf(TradeIntent.Kind.LIMIT, TradeIntent.Kind.STOP, TradeIntent.Kind.BRACKET))
            return AmountUnit.Dollars
        return AmountUnit.Spend(i.sell)
    }

    /** The fields the panel shows, top to bottom after the amount. */
    fun fields(i: TradeIntent): List<TradeField> = when (i.kind) {
        TradeIntent.Kind.LIMIT, TradeIntent.Kind.STOP, TradeIntent.Kind.STOP_LOSS,
        TradeIntent.Kind.TAKE_PROFIT -> listOf(TradeField.AMOUNT, TradeField.PRICE)
        TradeIntent.Kind.BRACKET -> listOf(TradeField.AMOUNT, TradeField.PRICE, TradeField.STOP_PRICE)
        TradeIntent.Kind.TRAILING_STOP -> listOf(TradeField.AMOUNT, TradeField.TRAIL)
        TradeIntent.Kind.TWAP -> listOf(TradeField.AMOUNT, TradeField.DURATION)
        TradeIntent.Kind.SWAP, TradeIntent.Kind.BRIDGE, TradeIntent.Kind.SEND -> listOf(TradeField.AMOUNT)
    }

    /** The row's name for a field. */
    fun label(field: TradeField, i: TradeIntent): String = when (field) {
        TradeField.AMOUNT -> when (val u = amountUnit(i)) {
            AmountUnit.Dollars -> "Amount in $"
            is AmountUnit.Spend -> "Amount in ${u.symbol}"
            is AmountUnit.Receive -> "${u.symbol} to get"
        }
        TradeField.PRICE -> when (i.kind) {
            TradeIntent.Kind.LIMIT -> if (sells(i)) "Sell at" else "Buy at"
            TradeIntent.Kind.STOP -> "Buy above"
            TradeIntent.Kind.STOP_LOSS -> "Sell below"
            TradeIntent.Kind.TAKE_PROFIT -> "Sell above"
            TradeIntent.Kind.BRACKET -> "Take profit"
            else -> "Price"
        }
        TradeField.STOP_PRICE -> "Stop-loss"
        TradeField.TRAIL -> "Trail"
        TradeField.DURATION -> "Over"
    }

    /** The text the editor opens with. */
    fun value(field: TradeField, i: TradeIntent): String = when (field) {
        TradeField.AMOUNT -> i.buyAmount ?: i.amount ?: ""
        TradeField.PRICE -> i.price ?: ""
        TradeField.STOP_PRICE -> i.stopPrice ?: ""
        TradeField.TRAIL -> i.trailPercent ?: ""
        TradeField.DURATION -> i.durationSeconds?.let {
            TradeIntent.trimmed(TradeIntent.rounded(it.toDouble() / 86_400 * 1000) / 1000)
        } ?: ""
    }

    /** How a field reads on the panel. */
    fun shown(field: TradeField, i: TradeIntent): String = when (field) {
        TradeField.AMOUNT -> {
            val v = value(TradeField.AMOUNT, i)
            when {
                v.isEmpty() -> if (sells(i)) "All" else "0"
                amountUnit(i) == AmountUnit.Dollars -> "$$v"
                else -> v
            }
        }
        TradeField.PRICE -> i.price?.let { TradeIntent.dollars(it) } ?: "—"
        TradeField.STOP_PRICE -> i.stopPrice?.let { TradeIntent.dollars(it) } ?: "—"
        TradeField.TRAIL -> i.trailPercent?.let { "$it%" } ?: "—"
        TradeField.DURATION -> duration(i.durationSeconds)
    }

    /** "1 day", "12 hours", "2 weeks". */
    fun duration(seconds: Int?): String {
        val s = seconds ?: return "—"
        if (s <= 0) return "—"
        if (s % (7 * 86_400) == 0) { val w = s / (7 * 86_400); return if (w == 1) "1 week" else "$w weeks" }
        if (s % 86_400 == 0) { val d = s / 86_400; return if (d == 1) "1 day" else "$d days" }
        val h = max(1, TradeIntent.rounded(s / 3600.0).toInt()); return if (h == 1) "1 hour" else "$h hours"
    }

    // MARK: changes

    /** Digits and one point, as an amount field takes them ("1,5" → "1.5"). */
    fun cleanNumber(text: String): String {
        val out = StringBuilder()
        var point = false
        for (ch in text.replace(',', '.')) {
            if (ch in '0'..'9') out.append(ch)
            else if (ch == '.' && !point) { point = true; out.append(ch) }
        }
        var s = out.toString()
        if (s.startsWith(".")) s = "0$s"
        // "007" is 7; "0.5" stays.
        while (s.length > 1 && s.startsWith("0") && !s.startsWith("0.")) s = s.drop(1)
        return s.take(18)
    }

    /** The typed text set on the trade. An empty amount on a sell means
     *  everything held; an empty price stays unset. */
    fun apply(field: TradeField, text: String, intent: TradeIntent): TradeIntent {
        val i = intent.copy()
        val clean = cleanNumber(text)
        val number = TradeIntent.number(clean)?.let { if (it > 0) clean else null }
        when (field) {
            TradeField.AMOUNT -> when (amountUnit(i)) {
                is AmountUnit.Receive -> { i.buyAmount = number; i.amount = null }
                else -> i.amount = number
            }
            TradeField.PRICE -> { i.price = number; i.pricePercent = null }
            TradeField.STOP_PRICE -> { i.stopPrice = number; i.stopPercent = null }
            TradeField.TRAIL -> i.trailPercent = number
            TradeField.DURATION -> i.durationSeconds = TradeIntent.number(number)?.let {
                max(3600, TradeIntent.rounded(it * 86_400).toInt())
            }
        }
        return i
    }

    /** Why the trade can't go as set, in one short line; null when it can. */
    fun problem(i: TradeIntent): String? {
        if (i.kind == TradeIntent.Kind.SWAP) {
            if ((i.buyChain ?: i.chainName) == i.chainName && i.sell == i.buy &&
                (i.sellAddress ?: i.sell) == (i.buyAddress ?: i.buy)) return "Pick two different tokens"
            return null
        }
        fun positive(s: String?) = (TradeIntent.number(s) ?: 0.0) > 0
        when (i.kind) {
            TradeIntent.Kind.LIMIT, TradeIntent.Kind.STOP, TradeIntent.Kind.STOP_LOSS, TradeIntent.Kind.TAKE_PROFIT ->
                if (!positive(i.price) && i.pricePercent == null) return "Set a price"
            TradeIntent.Kind.BRACKET -> {
                if ((!positive(i.price) && i.pricePercent == null) || (!positive(i.stopPrice) && i.stopPercent == null))
                    return "Set both prices"
                val tp = TradeIntent.number(i.price); val sl = TradeIntent.number(i.stopPrice)
                if (tp != null && sl != null && tp <= sl) return "Take profit must be above the stop-loss"
            }
            TradeIntent.Kind.TRAILING_STOP -> {
                val p = TradeIntent.number(i.trailPercent)
                if (p == null || p < 0.5 || p > 50) return "Trail between 0.5% and 50%"
            }
            TradeIntent.Kind.TWAP -> {
                if (!positive(i.amount)) return "Enter an amount"
                if ((i.durationSeconds ?: 0) < 3600) return "At least an hour"
            }
            TradeIntent.Kind.BRIDGE -> {
                if (!positive(i.amount)) return "Enter an amount"
                if (i.toChain == null || i.toChain == i.chainName) return "Pick another chain"
            }
            TradeIntent.Kind.SEND -> if (!positive(i.amount)) return "Enter an amount"
            else -> {}
        }
        return null
    }

    /** A token picked for [side]. A Flash order changes its asset (both
     *  sides of a bridge), keeping the dollar side. */
    fun pick(token: TokenPick, side: Side, intent: TradeIntent): TradeIntent {
        val i = intent.copy()
        val symbol = if (token.symbol.uppercase(Locale.US) == "CBBTC") "CBBTC" else token.symbol
        val address = if (token.native) null else token.address
        if (i.kind == TradeIntent.Kind.BRIDGE || i.kind == TradeIntent.Kind.SEND) {
            i.sell = symbol; i.buy = symbol
            i.sellAddress = address; i.buyAddress = address
            return i
        }
        if (i.kind != TradeIntent.Kind.SWAP) {
            // The asset side changes; a dollar coin picked as the asset
            // flips nothing, it just can't be the asset.
            if (sells(i)) {
                i.sell = symbol; i.sellAddress = address
                if (symbol in stables && i.buy in stables) { i.buy = TradeIntent.stableFor(symbol); i.buyAddress = null }
            } else {
                i.buy = symbol; i.buyAddress = address
                if (symbol in stables && i.sell in stables) { i.sell = TradeIntent.stableFor(symbol); i.sellAddress = null }
            }
            return i
        }
        val sameChain = (i.buyChain ?: i.chainName) == i.chainName
        when (side) {
            // Picking what's on the other side swaps the two, as Uniswap's app does.
            Side.SELL -> {
                if (symbol == i.buy && sameChain) return flip(i)
                i.sell = symbol; i.sellAddress = address
            }
            Side.BUY -> {
                if (symbol == i.sell && sameChain) return flip(i)
                i.buy = symbol; i.buyAddress = address
            }
        }
        // A picked token is spent or bought by count, not dollars.
        i.amountIsUSD = false
        return i
    }

    /** An order whose asset changed: its prices were the old asset's, so
     *  they go back to the starters' distances from the new market
     *  (SponsorMenu.starter), filled once the panel has the new price. */
    fun repriced(intent: TradeIntent, was: TradeIntent): TradeIntent {
        if (intent.kind == TradeIntent.Kind.SWAP || asset(intent) == asset(was)) return intent
        val i = intent.copy()
        when (i.kind) {
            TradeIntent.Kind.LIMIT -> { i.price = null; i.pricePercent = if (sells(i)) 5.0 else -5.0 }
            TradeIntent.Kind.STOP -> { i.price = null; i.pricePercent = 5.0 }
            TradeIntent.Kind.STOP_LOSS -> { i.price = null; i.pricePercent = -10.0 }
            TradeIntent.Kind.TAKE_PROFIT -> { i.price = null; i.pricePercent = 10.0 }
            TradeIntent.Kind.BRACKET -> {
                i.price = null; i.pricePercent = 10.0
                i.stopPrice = null; i.stopPercent = -10.0
            }
            else -> {}
        }
        // An amount of the old coin isn't an amount of the new one.
        if (sells(i) && i.kind != TradeIntent.Kind.BRIDGE && i.kind != TradeIntent.Kind.SEND) i.amount = null
        return i
    }

    /** You pay and You get trade places; the amount stays what's typed. */
    fun flip(intent: TradeIntent): TradeIntent {
        val i = intent.copy(sell = intent.buy, buy = intent.sell,
            sellAddress = intent.buyAddress, buyAddress = intent.sellAddress)
        val to = i.buyChain
        if (to != null && to != i.chainName) {
            val from = i.chainName
            i.chain = to
            i.buyChain = from
        }
        i.buyAmount?.let { i.amount = it; i.buyAmount = null }
        i.amountIsUSD = false
        return i
    }

    /** The chains a trade of this kind can be on. */
    fun chains(i: TradeIntent): List<String> = when (i.kind) {
        TradeIntent.Kind.SWAP -> SponsorMenu.SWAP_CHAINS
        // A send stays where its name points: Solana for a .sol name or
        // SOL, any of MetaMask's chains otherwise.
        TradeIntent.Kind.SEND -> if (i.chainName == "solana") listOf("solana") else SponsorMenu.SWAP_CHAINS
        else -> FLASH_CHAINS
    }

    /** Flash's chains that this server also has an EVM node for, Solana too. */
    val FLASH_CHAINS = listOf("base", "solana", "ethereum", "arbitrum", "optimism")

    /** The chain picked for [side] (a swap's You get side makes it
     *  cross-chain; a bridge's buy side is where it lands). Tokens that
     *  don't exist on the new chain fall back to its gas coin. */
    fun pickChain(chain: String, side: Side, intent: TradeIntent): TradeIntent {
        val i = intent.copy()
        if (i.kind == TradeIntent.Kind.BRIDGE && side == Side.BUY) {
            i.toChain = if (chain == i.chainName) null else chain
            return i
        }
        if (i.kind == TradeIntent.Kind.SWAP && side == Side.BUY) {
            i.buyChain = if (chain == i.chainName) null else chain
            i.buyAddress = null
            return i
        }
        val was = i.chainName
        i.chain = chain
        if (i.kind == TradeIntent.Kind.SWAP && i.buyChain == chain) i.buyChain = null
        if (i.kind == TradeIntent.Kind.BRIDGE && i.toChain == chain) i.toChain = SponsorMenu.bridgeTarget(chain)
        // Addresses belong to the chain they were picked on.
        i.sellAddress = null
        if (i.kind != TradeIntent.Kind.SWAP || i.buyChain == null) i.buyAddress = null
        val toSolana = chain == "solana"
        val fromSolana = was == "solana"
        if (toSolana != fromSolana) {
            val gas = if (toSolana) "SOL" else "ETH"
            if (toSolana) {
                val allowed = setOf("SOL", "USDC", "USDT")
                if (i.sell !in allowed) i.sell = gas
                if (i.buy !in allowed) i.buy = gas
            } else {
                if (i.sell == "SOL") i.sell = gas
                if (i.buy == "SOL") i.buy = gas
            }
            if (i.sell == i.buy) i.buy = TradeIntent.stableFor(i.sell)
            if (i.kind == TradeIntent.Kind.BRIDGE) i.buy = i.sell
        }
        return i
    }

    // MARK: picker rows

    /** The picker's rows before the server answers (or when it can't):
     *  the coins every chain here has. */
    fun builtIn(chain: String): List<TokenPick> {
        if (chain == "solana") return listOf(TokenPick("SOL", "Solana", native = true),
            TokenPick("USDC", "USD Coin"), TokenPick("USDT", "Tether USD"))
        val rows = mutableListOf(TokenPick("ETH", "Ether", native = true), TokenPick("USDC", "USD Coin"))
        if (chain != "base" && chain != "unichain") rows.add(TokenPick("USDT", "Tether USD"))
        rows.add(TokenPick("WETH", "Wrapped Ether"))
        if (chain != "unichain") rows.add(TokenPick("DAI", "Dai Stablecoin"))
        rows.add(if (chain == "base") TokenPick("cbBTC", "Coinbase Wrapped BTC") else TokenPick("WBTC", "Wrapped BTC"))
        return rows
    }

    /** The rows matching what's typed: an exact symbol, then symbols that
     *  start with it, then names that do, then anything containing it; a
     *  pasted address matches its own row. */
    fun filter(rows: List<TokenPick>, query: String): List<TokenPick> {
        val q = query.trim().lowercase(Locale.US).replace("$", "")
        if (q.isEmpty()) return rows
        if (q.startsWith("0x")) return rows.filter { it.address?.lowercase(Locale.US) == q }
        fun score(t: TokenPick): Int? {
            val s = t.symbol.lowercase(Locale.US); val n = t.name.lowercase(Locale.US)
            return when {
                s == q -> 0
                s.startsWith(q) -> 1
                n.startsWith(q) -> 2
                s.contains(q) || n.contains(q) -> 3
                else -> null
            }
        }
        return rows.withIndex().mapNotNull { (idx, t) -> score(t)?.let { Triple(it, idx, t) } }
            .sortedWith(compareBy({ it.first }, { it.second }))
            .map { it.third }
    }

    /** Server rows after the built-in ones, without repeating a symbol the
     *  built-in list already has unless the address differs. */
    fun merge(first: List<TokenPick>, more: List<TokenPick>): List<TokenPick> {
        val out = first.toMutableList()
        for (t in more) {
            val dup = out.any {
                it.symbol.uppercase(Locale.US) == t.symbol.uppercase(Locale.US) &&
                    (it.address == null || it.address.lowercase(Locale.US) == t.address?.lowercase(Locale.US))
            }
            if (!dup) out.add(t)
        }
        // Server rows carry logos and addresses: they fill in the built-in ones.
        for (k in out.indices) {
            val t = out[k]
            if (t.logo != null && t.address != null) continue
            val better = more.firstOrNull { it.symbol.uppercase(Locale.US) == t.symbol.uppercase(Locale.US) } ?: continue
            out[k] = t.copy(logo = t.logo ?: better.logo,
                address = if (t.native) t.address else t.address ?: better.address)
        }
        return out
    }
}
