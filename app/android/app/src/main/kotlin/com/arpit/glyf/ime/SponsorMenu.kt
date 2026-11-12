package com.arpit.glyf.ime

/**
 * The g menu's top row: the apps Glyf trades through: Uniswap swaps (with
 * Jupiter for Solana) and Definitive's Flash orders. A tap on one opens its
 * own panel listing everything it does; nothing runs on the tap itself
 * (Arpit, 2026-11-06: "any icon, should not trigger a thing by default. It
 * should show all the options"). Pure, so SponsorMenuTest pins which icons
 * show, what each panel lists and what each option puts up. The twin of
 * SponsorMenu.swift.
 */
object SponsorMenu {

    enum class Sponsor(val id: String, val title: String) {
        UNISWAP("uniswap", "Uniswap"),
        DEFINITIVE("definitive", "Definitive");

        /** The panel's screen id, as iOS's shell names it. */
        val screenId: String get() = "sponsor:$id"

        companion object {
            fun of(screenId: String): Sponsor? {
                if (!screenId.startsWith("sponsor:")) return null
                val id = screenId.removePrefix("sponsor:")
                return values().firstOrNull { it.id == id }
            }
        }
    }

    /** One thing a panel can do. */
    sealed class Option {
        /** Uniswap: the swap typed, or the starter on Base. */
        object Swap : Option()
        /** Uniswap: the starter swap on this chain. */
        data class SwapOn(val chain: String) : Option()
        /** Uniswap's panel, Solana: Jupiter's swap (the keyboard's Buy panel). */
        object Jupiter : Option()
        /** Definitive: the Flash order already typed. */
        object Typed : Option()
        /** Definitive: a starter of this kind on the chain picked. */
        data class Order(val kind: TradeIntent.Kind) : Option()
        /** Definitive: the app's Ethereum wallet, where Flash orders wait. */
        object OpenOrders : Option()

        /** The row's target id. */
        val id: String
            get() = when (this) {
                Swap -> "swap"
                is SwapOn -> "swap:$chain"
                Jupiter -> "jupiter"
                Typed -> "typed"
                is Order -> "order:${kind.raw}"
                OpenOrders -> "orders"
            }

        companion object {
            fun of(id: String): Option? = when (id) {
                "swap" -> Swap
                "jupiter" -> Jupiter
                "typed" -> Typed
                "orders" -> OpenOrders
                else -> when {
                    id.startsWith("swap:") -> id.removePrefix("swap:").takeIf { it in SWAP_CHAINS }?.let { SwapOn(it) }
                    id.startsWith("order:") -> TradeIntent.Kind.of(id.removePrefix("order:"))
                        ?.takeIf { it in ORDER_KINDS }?.let { Order(it) }
                    else -> null
                }
            }
        }
    }

    /** A row of a sponsor's panel. */
    sealed class Entry {
        data class Header(val title: String) : Entry()
        data class Row(val option: Option, val title: String, val detail: String?, val icon: String) : Entry()
        /** Definitive: Base or Solana. */
        object ChainPicker : Entry()
    }

    /** What a tap on an option does. */
    sealed class Action {
        /** The trade panel, with this trade on it, as if it had been typed. */
        data class Trade(val intent: TradeIntent) : Action()
        /** One hop to the app. */
        data class OpenApp(val path: String) : Action()
        /** The keyboard's Buy panel, swapping on Solana through Jupiter. */
        object SolanaSwap : Action()
    }

    /** Every chain Glyf swaps on through Uniswap (the server's EVM chains). */
    val SWAP_CHAINS = listOf("base", "ethereum", "arbitrum", "optimism", "unichain")
    /** Flash's chains the keyboard offers. */
    val FLASH_CHAINS = listOf("base", "solana")
    /** Flash's order types, in the panel's order. */
    val ORDER_KINDS = listOf(
        TradeIntent.Kind.LIMIT, TradeIntent.Kind.STOP, TradeIntent.Kind.STOP_LOSS, TradeIntent.Kind.TAKE_PROFIT,
        TradeIntent.Kind.BRACKET, TradeIntent.Kind.TRAILING_STOP, TradeIntent.Kind.TWAP, TradeIntent.Kind.BRIDGE,
    )

    /** The chain the Definitive panel trades on; Base until Solana is
     *  picked. Kept while the keyboard process lives. */
    var flashChain = "base"

    /** Uniswap and Definitive, in the g menu's order. */
    val sponsors: List<Sponsor> = Sponsor.values().toList()

    // MARK: panels

    /** A sponsor's panel. [typed] is the text before the cursor. */
    fun entries(sponsor: Sponsor, typed: String, flashChain: String = "base"): List<Entry> = when (sponsor) {
        Sponsor.UNISWAP -> {
            val swap = typedSwap(typed) ?: starterSwap("base")
            val rows = mutableListOf<Entry>(
                Entry.Row(Option.Swap, "Swap", swapDetail(swap), "swaparrows"),
                Entry.Header("Chains"),
            )
            rows += SWAP_CHAINS.map { Entry.Row(Option.SwapOn(it), TradeIntent.chainLabels[it] ?: TradeIntent.capitalized(it), null, "chain:$it") }
            rows.add(Entry.Row(Option.Jupiter, "Solana", "Jupiter", "chain:solana"))
            rows
        }
        Sponsor.DEFINITIVE -> {
            val rows = mutableListOf<Entry>(Entry.ChainPicker, Entry.Header("Orders"))
            typedOrder(typed)?.let { rows.add(Entry.Row(Option.Typed, it.title, null, "textcursor")) }
            rows += ORDER_KINDS.map { Entry.Row(Option.Order(it), orderTitle(it), orderDetail(it, flashChain), orderIcon(it)) }
            rows.add(Entry.Row(Option.OpenOrders, "Open orders", null, "list"))
            rows
        }
    }

    /** "USDC → ETH", "0.05 ETH → USDC", "Buy $20 of ETH". */
    fun swapDetail(t: TradeIntent): String = t.title.removePrefix("Swap ")

    fun orderTitle(kind: TradeIntent.Kind): String = when (kind) {
        TradeIntent.Kind.LIMIT -> "Limit buy"
        TradeIntent.Kind.STOP -> "Stop buy"
        TradeIntent.Kind.STOP_LOSS -> "Stop-loss"
        TradeIntent.Kind.TAKE_PROFIT -> "Take profit"
        TradeIntent.Kind.BRACKET -> "Bracket"
        TradeIntent.Kind.TRAILING_STOP -> "Trailing stop"
        TradeIntent.Kind.TWAP -> "TWAP"
        TradeIntent.Kind.BRIDGE -> "Bridge"
        else -> TradeIntent.capitalized(kind.raw)
    }

    /** How far from the price each starter sits, as the row says it. */
    fun orderDetail(kind: TradeIntent.Kind, chain: String): String? = when (kind) {
        TradeIntent.Kind.LIMIT -> "−5%"
        TradeIntent.Kind.STOP -> "+5%"
        TradeIntent.Kind.STOP_LOSS -> "−10%"
        TradeIntent.Kind.TAKE_PROFIT -> "+10%"
        TradeIntent.Kind.BRACKET -> "±10%"
        TradeIntent.Kind.TRAILING_STOP -> "10%"
        TradeIntent.Kind.TWAP -> "$20 · 1 day"
        TradeIntent.Kind.BRIDGE -> {
            val to = bridgeTarget(chain)
            "→ ${TradeIntent.chainLabels[to] ?: TradeIntent.capitalized(to)}"
        }
        else -> null
    }

    /** ToolIcon glyphs standing in for iOS's SF Symbols. */
    fun orderIcon(kind: TradeIntent.Kind): String = when (kind) {
        TradeIntent.Kind.LIMIT -> "scope"
        TradeIntent.Kind.STOP -> "arrowupright"
        TradeIntent.Kind.STOP_LOSS -> "arrowdownright"
        TradeIntent.Kind.TAKE_PROFIT -> "flag"
        TradeIntent.Kind.BRACKET -> "updown"
        TradeIntent.Kind.TRAILING_STOP -> "downtrend"
        TradeIntent.Kind.TWAP -> "clockarrow"
        TradeIntent.Kind.BRIDGE -> "swaparrows"
        else -> "circle"
    }

    // MARK: options

    fun action(option: Option, typed: String, flashChain: String = "base"): Action? = when (option) {
        Option.Swap -> Action.Trade(typedSwap(typed) ?: starterSwap("base"))
        is Option.SwapOn -> Action.Trade(starterSwap(option.chain))
        Option.Jupiter -> Action.SolanaSwap
        Option.Typed -> typedOrder(typed)?.let { Action.Trade(it) }
        is Option.Order -> starter(option.kind, flashChain)?.let { Action.Trade(it) }
        Option.OpenOrders -> Action.OpenApp("evm-wallet")
    }

    /** A swap typed at the end of the message. */
    fun typedSwap(typed: String): TradeIntent? =
        TradeIntent.parse(typed)?.takeIf { it.kind == TradeIntent.Kind.SWAP }

    /** A Flash order typed at the end of the message. */
    fun typedOrder(typed: String): TradeIntent? = TradeIntent.parse(typed)?.takeIf { it.venue == "Flash" }

    /** A small swap, 10 USDC to ETH, on [chain]. */
    fun starterSwap(chain: String): TradeIntent = TradeIntent.parse("swap 10 usdc to eth on $chain")!!

    fun bridgeTarget(chain: String): String = if (chain == "solana") "base" else "arbitrum"

    /** A Flash starter of [kind]: ETH on Base, SOL on Solana. A buy spends
     *  $20 of USDC; a stop-loss, take-profit, bracket or trail guards what
     *  is held. Read from the words a person would type, so it is the trade
     *  the chip would show. Orders that wait on a price carry it as a
     *  distance from the market ([TradeIntent.pricePercent]), set once the
     *  trade panel has the price. */
    fun starter(kind: TradeIntent.Kind, chain: String): TradeIntent? {
        val solana = chain == "solana"
        val a = if (solana) "sol" else "eth"
        val on = if (solana) " on solana" else ""
        var pct: Double? = null
        var stopPct: Double? = null
        val words = when (kind) {
            TradeIntent.Kind.LIMIT -> { pct = -5.0; "buy $20 of $a at 1$on" }
            TradeIntent.Kind.STOP -> { pct = 5.0; "buy $20 of $a if it breaks 1$on" }
            TradeIntent.Kind.STOP_LOSS -> { pct = -10.0; "stop-loss my $a at 1$on" }
            TradeIntent.Kind.TAKE_PROFIT -> { pct = 10.0; "take profit my $a at 1$on" }
            TradeIntent.Kind.BRACKET -> { pct = 10.0; stopPct = -10.0; "my $a tp 2 sl 1$on" }
            TradeIntent.Kind.TRAILING_STOP -> "trail my $a by 10%$on"
            TradeIntent.Kind.TWAP -> "buy $20 of $a over a day$on"
            TradeIntent.Kind.BRIDGE -> "move 10 usdc from $chain to ${bridgeTarget(chain)}"
            else -> return null
        }
        val t = TradeIntent.parse(words)?.takeIf { it.kind == kind } ?: return null
        if (pct != null) { t.price = null; t.pricePercent = pct }
        if (stopPct != null) { t.stopPrice = null; t.stopPercent = stopPct }
        return t
    }

    /** A starter's prices set from the market's: [TradeIntent.pricePercent]
     *  and [TradeIntent.stopPercent] away from it, rounded the way people
     *  say prices. */
    fun priced(intent: TradeIntent, market: Double): TradeIntent {
        if (market <= 0) return intent
        val t = intent.copy()
        t.pricePercent?.let { t.price = roundPrice(market * (1 + it / 100)); t.pricePercent = null }
        t.stopPercent?.let { t.stopPrice = roundPrice(market * (1 + it / 100)); t.stopPercent = null }
        return t
    }

    /** $3,180 not $3,183.42; $142 not $142.37; cents under $100. */
    fun roundPrice(v: Double): String {
        val step = when { v >= 1000 -> 10.0; v >= 100 -> 1.0; v >= 1 -> 0.01; else -> 0.0001 }
        val r = TradeIntent.rounded(v / step) * step
        // Two decimals at most below $100, so 0.1 steps don't print 141.70000001.
        return if (step < 1) TradeIntent.trimmed(TradeIntent.rounded(r * 10_000) / 10_000) else TradeIntent.trimmed(r)
    }
}
