package com.arpit.glyf.ime

import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * A trade said in plain words at the end of a message, read on the phone
 * with no model: a swap goes to Uniswap (Jupiter on Solana), an order that
 * waits for a price to Definitive's Flash, a send to an ENS (.eth) or SNS
 * (.sol) name or an address. The keyboard only shows what it read; the app quotes it again and the person's own wallet app (MetaMask
 * or Phantom) signs. The keyboard never holds a key (SPEC §1.5).
 * The twin of TradeIntent.swift and TradeRecurring.swift, rule for rule.
 */
data class TradeIntent(
    var kind: Kind,
    /** The number typed; null means everything held ("sell my eth"). */
    var amount: String? = null,
    /** The amount is dollars of what's bought ("$50 of eth"). */
    var amountIsUSD: Boolean = false,
    /** What is spent (a swap's sell side, the asset an order sells). */
    var sell: String,
    /** What comes back. */
    var buy: String,
    var chain: String? = null,
    var toChain: String? = null,
    /** The trigger or limit, in dollars (a bracket's take-profit). */
    var price: String? = null,
    /** A bracket's stop-loss. */
    var stopPrice: String? = null,
    var trailPercent: String? = null,
    var durationSeconds: Int? = null,
    /** "buy 0.1 eth": the amount wanted back, not the amount spent. */
    var buyAmount: String? = null,
    /** A DCA as typed: each buy, its unit and how many (amount is the total). */
    var slice: Slice? = null,
    /** A g menu starter (SponsorMenu.starter): the trigger is this many
     *  percent from the market (-10 = 10% under), set as [price] once the
     *  trade panel has the price. Never read from words. */
    var pricePercent: Double? = null,
    /** The same for a bracket's stop-loss. */
    var stopPercent: Double? = null,
    /** A token picked in the panel by its contract (GET /uniswap/tokens),
     *  sent beside the symbol so a lookalike symbol can't stand in. */
    var sellAddress: String? = null,
    var buyAddress: String? = null,
    /** A swap whose You get side is on another chain ("swap 50 usdc on base
     *  to eth on arbitrum"): Uniswap's cross-chain route. Null = same chain. */
    var buyChain: String? = null,
    /** A buy repeated on a schedule ("dca $20 in eth each month"), placed
     *  as this one Flash TWAP. */
    var plan: RecurringPlan? = null,
    /** A send's recipient as typed: vitalik.eth, arpit.sol, or 0x… (the
     *  name is lowercased; the panel looks up its address before anything
     *  is signed). */
    var to: String? = null,
) {

    enum class Kind(val raw: String) {
        /** Uniswap, now: "swap 0.05 eth to usdc on base", "buy $20 of eth". */
        SWAP("swap"),
        /** Flash: a buy or sell at a price ("buy eth at 2800"). */
        LIMIT("limit"),
        /** Flash: buy when the price breaks up through a level. */
        STOP("stop"),
        /** Flash: sell when the price falls to a level. */
        STOP_LOSS("stop-loss"),
        /** Flash: sell when the price rises to a level. */
        TAKE_PROFIT("take-profit"),
        /** Flash: a take-profit and a stop-loss together. */
        BRACKET("bracket"),
        /** Flash: a stop that follows the price up by a percentage. */
        TRAILING_STOP("trailing-stop"),
        /** Flash: one order spread over time. */
        TWAP("twap"),
        /** Flash: the same token moved to another chain. */
        BRIDGE("bridge"),
        /** A send to an ENS or SNS name, or an address: "send 5 usdc to
         *  vitalik.eth". MetaMask sends it on Ethereum chains, Phantom on
         *  Solana (a .sol name, or SOL itself). */
        SEND("send");

        companion object {
            fun of(raw: String): Kind? = values().firstOrNull { it.raw == raw }
        }
    }

    data class Slice(val amount: String, val unit: String, val count: Int)

    /** A starter whose price waits on the market's. */
    val awaitingPrice: Boolean
        get() = (pricePercent != null && price == null) || (stopPercent != null && stopPrice == null)

    /** What a buy order buys, with the amount typed: "$10 of TSLA", "0.1 ETH". */
    private val buyText: String
        get() {
            val a = amount
            if (amountIsUSD && a != null) return "$$a of $buy"
            buyAmount?.let { return "$it $buy" }
            return buy
        }

    /** What a sell order sells: "0.5 ETH", or the token when it's all of it. */
    private val sellText: String get() = amount?.let { "$it $sell" } ?: sell

    /** Who carries it out, as the strip says it. */
    val venue: String
        get() = when (kind) {
            // Solana has no Uniswap pools here: Jupiter swaps there.
            Kind.SWAP -> if (chainName == "solana") "Jupiter" else "Uniswap"
            Kind.SEND -> walletName(chainName)
            else -> "Flash"
        }

    /** The chain it lands on: Base unless the words named one. */
    val chainName: String get() = chain ?: "base"

    val chainLabel: String get() = chainLabels[chainName] ?: capitalized(chainName)

    private val amountText: String
        get() {
            val a = amount
            if (a == null && buyAmount != null) return "$buyAmount $buy"
            if (a == null) return "all $sell"
            return if (amountIsUSD) "$$a of $buy" else "$a $sell"
        }

    /** The chip's words: "Swap 0.05 ETH → USDC", "Stop-loss ETH at $3,000". */
    val title: String
        get() = when (kind) {
            Kind.SWAP -> {
                val bc = buyChain
                when {
                    amountIsUSD -> "Buy $amountText"
                    buyAmount != null -> "Buy $amountText with $sell"
                    bc != null && bc != chainName ->
                        "Swap $amountText → $buy on ${chainLabels[bc] ?: capitalized(bc)}"
                    else -> "Swap $amountText → $buy"
                }
            }
            Kind.LIMIT -> if (sell == "USDC" || sell == "USDT") "Buy $buyText at ${dollars(price)}"
                else "Sell $sellText at ${dollars(price)}"
            Kind.STOP -> "Buy $buyText above ${dollars(price)}"
            Kind.STOP_LOSS -> "Stop-loss $sellText at ${dollars(price)}"
            Kind.TAKE_PROFIT -> "Take profit $sellText at ${dollars(price)}"
            Kind.BRACKET -> "$sell TP ${dollars(price)} · SL ${dollars(stopPrice)}"
            Kind.TRAILING_STOP -> "Trail $sell by ${trailPercent ?: ""}%"
            Kind.TWAP -> twapTitle()
            Kind.BRIDGE -> "Move $amountText to ${chainLabels[toChain ?: ""] ?: capitalized(toChain ?: "")}"
            Kind.SEND -> "Send $amountText to ${to?.let { shortRecipient(it) } ?: ""}"
        }

    private fun twapTitle(): String {
        planTitle?.let { return it }
        // As typed while it still adds up; an edited amount reads as a total.
        val s = slice
        val each = s?.amount?.let { number(it) }
        val total = number(amount ?: "")
        if (s != null && each != null && total != null && abs(each * s.count - total) < 0.000001) {
            val span = if (s.count == 1) "for 1 ${s.unit}" else "for ${s.count} ${s.unit}s"
            return "Buy $${s.amount} of $buy every ${s.unit} $span"
        }
        return "Buy ${if (amountIsUSD) "$${amount ?: ""}" else amountText} of $buy ${span(durationSeconds)}"
    }

    /** Under the title: where and through whom. */
    val detail: String
        get() {
            val bc = buyChain
            return when {
                kind == Kind.BRIDGE -> "$chainLabel → ${chainLabels[toChain ?: ""] ?: ""} · Flash"
                kind == Kind.SWAP && bc != null && bc != chainName ->
                    "$chainLabel → ${chainLabels[bc] ?: capitalized(bc)} · Uniswap"
                else -> "$chainLabel · $venue"
            }
        }

    /** The app's words for it (glyf://open?path=trade?…). */
    val query: Map<String, String>
        get() {
            val q = linkedMapOf("kind" to kind.raw, "sell" to sell, "buy" to buy, "chain" to chainName)
            amount?.let { q["amount"] = it }
            if (amountIsUSD) q["usd"] = "1"
            toChain?.let { q["toChain"] = it }
            price?.let { q["price"] = it }
            stopPrice?.let { q["stopPrice"] = it }
            trailPercent?.let { q["trail"] = it }
            durationSeconds?.let { q["duration"] = it.toString() }
            buyAmount?.let { q["buyAmount"] = it }
            sellAddress?.let { q["sellAddress"] = it }
            buyAddress?.let { q["buyAddress"] = it }
            buyChain?.let { if (it != chainName) q["buyChain"] = it }
            to?.let { q["to"] = it }
            return q
        }

    // MARK: recurring (TradeRecurring.swift)

    /** The trade panel's Over row for a plan, while the order is still the
     *  one the plan made (an amount or length changed in the panel ends it). */
    val planOverRow: Pair<String, String>?
        get() {
            val p = plan ?: return null
            val every = number(p.every) ?: return null
            if (kind != Kind.TWAP || amount != trimmed(every * p.placed) ||
                durationSeconds != min(RecurringPlan.FLASH_MAX_SECONDS,
                    max(RecurringPlan.FLASH_MIN_SECONDS, p.placed * p.period.seconds * p.interval))) return null
            val span = span(durationSeconds).replace("over ", "")
            if (!p.capped) return "Over" to "$span · ${p.cadence}"
            val unit = p.period.raw
            val part = if (p.placed == 1) "$unit 1 of ${p.periods}" else "${unit}s 1–${p.placed} of ${p.periods}"
            return "Over · Flash max" to "$span · $part"
        }

    /** The chip's words for a plan: "DCA $20 of ETH monthly". */
    val planTitle: String?
        get() {
            val p = plan ?: return null
            val cadence = if (p.interval == 1) p.period.adverb else "every ${p.interval} ${p.period.raw}s"
            return "DCA $${p.every} of $buy $cadence"
        }

    companion object {

        val chainLabels = mapOf(
            "base" to "Base", "ethereum" to "Ethereum", "arbitrum" to "Arbitrum", "optimism" to "Optimism",
            "polygon" to "Polygon", "unichain" to "Unichain", "solana" to "Solana",
        )

        /** Swift's `capitalized`: each word's first letter up, the rest down. */
        fun capitalized(s: String): String = s.split(" ").joinToString(" ") { w ->
            w.lowercase(Locale.US).replaceFirstChar { it.titlecase(Locale.US) }
        }

        /** Who signs a trade on [chain], as the app names it: always the
         *  person's own wallet app, Phantom on Solana and MetaMask elsewhere. */
        fun walletName(chain: String?): String = if (chain == "solana") "Phantom" else "MetaMask"

        /** A number as Swift's Double(_:) reads one: digits, one point, an
         *  optional exponent; never "1d", "NaN" or hex. */
        fun number(s: String?): Double? {
            if (s.isNullOrEmpty()) return null
            if (!Regex("""[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?""").matches(s)) return null
            return s.toDoubleOrNull()
        }

        /** Swift's rounded(): halves away from zero. */
        fun rounded(v: Double): Double = if (v >= 0) floor(v + 0.5) else ceil(v - 0.5)

        fun dollars(price: String?): String {
            val v = number(price) ?: return "$${price ?: ""}"
            val f = java.text.NumberFormat.getNumberInstance(Locale.US)
            f.maximumFractionDigits = if (v < 10) 4 else 2
            f.minimumFractionDigits = 0
            return "$" + f.format(v)
        }

        fun span(seconds: Int?): String {
            val s = seconds ?: return ""
            if (s % (7 * 86_400) == 0) { val w = s / (7 * 86_400); return if (w == 1) "over a week" else "over $w weeks" }
            if (s % 86_400 == 0) { val d = s / 86_400; return if (d == 1) "over a day" else "over $d days" }
            val h = max(1, s / 3600); return if (h == 1) "over an hour" else "over $h hours"
        }

        // MARK: reading

        /** Tokens the words may name. Only these: "swap shifts with sam" is
         *  not a trade. */
        val symbols = mapOf(
            "eth" to "ETH", "ether" to "ETH", "weth" to "WETH", "usdc" to "USDC", "usdt" to "USDT", "dai" to "DAI",
            "wbtc" to "WBTC", "btc" to "WBTC", "bitcoin" to "WBTC", "cbbtc" to "CBBTC", "uni" to "UNI", "link" to "LINK",
            "aave" to "AAVE", "op" to "OP", "arb" to "ARB", "pol" to "POL", "matic" to "POL", "aero" to "AERO",
            "degen" to "DEGEN", "sol" to "SOL", "solana" to "SOL", "pepe" to "PEPE", "ldo" to "LDO",
            "aapl" to "AAPL", "apple" to "AAPL", "tsla" to "TSLA", "tesla" to "TSLA", "nvda" to "NVDA", "nvidia" to "NVDA",
            "msft" to "MSFT", "microsoft" to "MSFT", "googl" to "GOOGL", "google" to "GOOGL", "alphabet" to "GOOGL",
            "amzn" to "AMZN", "amazon" to "AMZN", "meta" to "META",
        )

        /** Tokenized shares on Base (the "…c" shares, the deepest there:
         *  Uniswap and Flash both trade them against USDC), by ticker. Arpit,
         *  2026-11-07: "if I type $Apple on the keyboard, I should see the
         *  option to buy on Uniswap through Base". */
        val baseStocks = mapOf(
            "AAPL" to "0xb200000000000000000000C2e324d24d7eEcd1fb",
            "TSLA" to "0xb2000000000000000000001e800a7f5189430cd0",
            "NVDA" to "0xb20000000000000000000078ee7ce2fe4908108c",
            "MSFT" to "0xb200000000000000000000ab99cfa739e253872b",
            "GOOGL" to "0xb2000000000000000000002d0ba3164cc74f58b7",
            "AMZN" to "0xb200000000000000000000d9192b6b456483c2e8",
            "META" to "0xb2000000000000000000008bc8786b856e61707c",
        )

        /** A share's ticker from what a price chip or a token list calls it
         *  ("AAPLx", "AAPLon", "AAPLc", "aapl"), when Base has it. */
        fun baseStock(name: String): String? {
            var t = name.uppercase(Locale.US).replace("$", "")
            for (suffix in listOf("ON", "X", "C")) {
                if (baseStocks[t] == null && t.endsWith(suffix)) t = t.dropLast(suffix.length)
            }
            return if (baseStocks[t] == null) null else t
        }

        val chains = mapOf(
            "base" to "base", "ethereum" to "ethereum", "eth mainnet" to "ethereum", "mainnet" to "ethereum",
            "arbitrum" to "arbitrum", "arb" to "arbitrum", "optimism" to "optimism", "op" to "optimism",
            "polygon" to "polygon", "unichain" to "unichain", "solana" to "solana",
        )

        private const val SYM = """\$?(eth|ether|weth|usdc|usdt|dai|wbtc|btc|bitcoin|cbbtc|uni|link|aave|op|arb|pol|matic|aero|degen|sol|solana|pepe|ldo|aapl|apple|tsla|tesla|nvda|nvidia|msft|microsoft|googl|google|alphabet|amzn|amazon|meta)"""
        private const val NUM = """(\d+(?:[.,]\d+)?(?:k)?)"""
        private const val CHAIN_PART = """(?:\s+on\s+(base|ethereum|eth mainnet|mainnet|arbitrum|arb|optimism|op|polygon|unichain|solana))?"""
        private const val CHAIN_WORD = """(base|ethereum|eth mainnet|mainnet|arbitrum|arb|optimism|op|unichain|polygon|solana)"""
        private const val END = """\s*[.!]?\s*$"""
        /** Where a command may begin: the start, or after a sentence ends. */
        private const val START = """(?:^|[.!?\n]\s*|\b(?:pls|please|glyf|hey glyf)[,:]?\s+)"""

        private val triggers = listOf("swap", "convert", "trade", "buy", "sell", "stop", "take profit", "tp ", "trail",
            "dca", "move", "bridge", "send", "pay", "transfer", "protect", "limit", "invest", "stack", "put")

        fun parse(text: String): TradeIntent? {
            val t = text.takeLast(200)
            if (t.length < 8) return null
            // Cheap test first: every pattern has one of these words.
            val lower = t.lowercase(Locale.US)
            if (triggers.none { lower.contains(it) }) return null
            // A schedule longer than Flash's 30-day TWAP is a recurring plan.
            val spread = twap(t)?.takeIf { (it.durationSeconds ?: 0) <= RecurringPlan.FLASH_MAX_SECONDS }
            val r = bracket(t) ?: orders(t) ?: spread ?: recurring(t) ?: bridgeMove(t) ?: send(t) ?: swap(t) ?: return null
            // A share trades on Base, by its address there.
            baseStocks[r.sell]?.let { r.sellAddress = it; r.chain = "base" }
            baseStocks[r.buy]?.let { r.buyAddress = it; r.chain = "base" }
            return r
        }

        // "swap 0.05 eth to usdc on base", "sell 0.1 eth", "buy 20 usdc of eth"
        private fun swap(t: String): TradeIntent? {
            // "swap 50 usdc on base to eth on arbitrum": each side on its chain.
            match(START + """(?:swap|convert|trade|exchange|bridge)\s+""" + NUM + """\s+""" + SYM +
                """\s+(?:on|from)\s+""" + CHAIN_WORD + """\s+(?:to|for|into)\s+""" + SYM + """\s+on\s+""" + CHAIN_WORD + END, t)?.let { m ->
                val sell = symbol(m[2]); val from = chains[m[3]!!.lowercase(Locale.US)]
                val buy = symbol(m[4]); val to = chains[m[5]!!.lowercase(Locale.US)]
                if (sell != null && from != null && buy != null && to != null && from != "solana" && to != "solana") {
                    val i = TradeIntent(Kind.SWAP, amount = amount(m[1]), sell = sell, buy = buy, chain = from)
                    if (to != from) i.buyChain = to else if (sell == buy) return null
                    return i
                }
            }
            match(START + """(?:swap|convert|trade|exchange)\s+(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|""" + NUM + """\s+)?""" +
                SYM + """\s+(?:to|for|into)\s+""" + SYM + CHAIN_PART + END, t)?.let { m ->
                return swapOf(m[1], m[2]!!, m[3]!!, m[4])
            }
            // "buy $50 of eth", "buy $50 worth of eth with usdt"
            match(START + """buy\s+\$""" + NUM + """\s+(?:of|worth\s+of|in)\s+""" + SYM +
                """(?:\s+(?:with|using)\s+""" + SYM + ")?" + CHAIN_PART + END, t)?.let { m ->
                val buy = symbol(m[2])!!
                val i = TradeIntent(Kind.SWAP, amount = amount(m[1]), sell = symbol(m[3]) ?: stableFor(buy), buy = buy,
                    chain = chain(m[4], buy))
                i.amountIsUSD = true
                return if (i.sell == i.buy) null else i
            }
            // "buy 0.1 eth (with usdc)"
            match(START + """buy\s+""" + NUM + """\s+""" + SYM + """(?:\s+(?:with|using)\s+""" + SYM + ")?" + CHAIN_PART + END, t)?.let { m ->
                val buy = symbol(m[2])!!
                val sell = symbol(m[3]) ?: stableFor(buy)
                // The amount is what comes back: the app works out what it costs.
                val i = TradeIntent(Kind.SWAP, sell = sell, buy = buy, chain = chain(m[4], buy))
                i.buyAmount = amount(m[1])
                return if (i.sell == i.buy) null else i
            }
            // "sell 0.1 eth (for usdc)", "sell my eth"
            match(START + """sell\s+(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|""" + NUM + """\s+)?""" + SYM +
                """(?:\s+(?:for|to|into)\s+""" + SYM + ")?" + CHAIN_PART + END, t)?.let { m ->
                val sell = symbol(m[2])!!
                return swapOf(m[1], m[2]!!, m[3] ?: stableFor(sell).lowercase(Locale.US), m[4])
            }
            return null
        }

        private fun swapOf(a: String?, s: String, b: String, c: String?): TradeIntent? {
            val sell = symbol(s) ?: return null
            val buy = symbol(b) ?: return null
            if (sell == buy) return null
            if ((sell == "SOL") != (buy == "SOL")) return null   // a swap stays on one chain
            return TradeIntent(Kind.SWAP, amount = amount(a), sell = sell, buy = buy, chain = chain(c, sell))
        }

        // Orders that wait for a price, all Flash.
        private fun orders(t: String): TradeIntent? {
            val held = """(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|""" + NUM + """\s+)?"""
            val price = """\$?""" + NUM
            // "sell my eth if it drops below 3000", "sell 0.1 eth when it falls to $3,000"
            match(START + """sell\s+""" + held + SYM + """\s+(?:if|when|once|whenever|every\s+time|each\s+time)\s+(?:it|the\s+price|price|""" +
                SYM + """)(?:\s+is|['’]s)?\s+(?:(?:drops?|falls?|goes|dips?|gets)\s+)?(?:below|under|to|beneath)\s+""" + price + CHAIN_PART + END, t)?.let { m ->
                return order(Kind.STOP_LOSS, m[1], m[2]!!, m[4], m[5])
            }
            // "stop loss my eth at 3000", "stop-loss eth 3000", "sl eth at 3000"
            match(START + """(?:set\s+(?:a\s+)?)?(?:stop[- ]?loss|sl)\s+(?:on\s+|for\s+)?""" + held + SYM +
                """\s+(?:at\s+|@\s*|to\s+)?""" + price + CHAIN_PART + END, t)?.let { m ->
                return order(Kind.STOP_LOSS, m[1], m[2]!!, m[3], m[4])
            }
            // "sell my eth if it hits 4500", "sell eth when it reaches $4,500"
            match(START + """sell\s+""" + held + SYM + """\s+(?:if|when|once)\s+(?:it|the\s+price|price|""" + SYM +
                """)\s+(?:hits|reaches|goes\s+(?:above|over|to)|rises\s+(?:above|over|to)|gets\s+to|crosses|is\s+(?:above|over)|touches)\s+""" +
                price + CHAIN_PART + END, t)?.let { m ->
                return order(Kind.TAKE_PROFIT, m[1], m[2]!!, m[4], m[5])
            }
            // "take profit eth at 4500", "tp my eth 4500"
            match(START + """(?:set\s+(?:a\s+)?)?(?:take[- ]?profit|tp)\s+(?:on\s+|for\s+)?""" + held + SYM +
                """\s+(?:at\s+|@\s*|to\s+)?""" + price + CHAIN_PART + END, t)?.let { m ->
                return order(Kind.TAKE_PROFIT, m[1], m[2]!!, m[3], m[4])
            }
            // "sell 0.1 eth at 4000" (a limit sell)
            match(START + """(?:limit\s+)?sell\s+""" + held + SYM + """\s+(?:at|@)\s*""" + price + CHAIN_PART + END, t)?.let { m ->
                return order(Kind.LIMIT, m[1], m[2]!!, m[3], m[4])
            }
            // "buy eth if it drops to 2800", "buy $100 of eth if it dips below 2800"
            match(START + """buy\s+(?:\$""" + NUM + """\s+(?:of|worth\s+of)\s+|""" + NUM + """\s+)?""" + SYM +
                """\s+(?:if|when|once|whenever|every\s+time|each\s+time)\s+(?:it|the\s+price|price)(?:\s+is|['’]s)?\s+(?:(?:drops?|falls?|dips?|goes|gets)\s+)?(?:below|under|to)\s+""" +
                price + CHAIN_PART + END, t)?.let { m ->
                return buyOrder(Kind.LIMIT, m[1], m[2], m[3]!!, m[4], m[5])
            }
            // "buy $100 of eth at 2800", "limit buy eth at 2800"
            match(START + """(?:limit\s+)?buy\s+(?:\$""" + NUM + """\s+(?:of|worth\s+of)\s+|""" + NUM + """\s+)?""" + SYM +
                """\s+(?:at|@)\s*""" + price + CHAIN_PART + END, t)?.let { m ->
                return buyOrder(Kind.LIMIT, m[1], m[2], m[3]!!, m[4], m[5])
            }
            // "buy eth if it breaks 4000", "buy eth when it goes above 4000"
            match(START + """buy\s+(?:\$""" + NUM + """\s+(?:of|worth\s+of)\s+|""" + NUM + """\s+)?""" + SYM +
                """\s+(?:if|when|once)\s+(?:it|the\s+price|price)\s+(?:breaks(?:\s+above)?|goes\s+(?:above|over)|crosses|rises\s+(?:above|over)|is\s+above)\s+""" +
                price + CHAIN_PART + END, t)?.let { m ->
                return buyOrder(Kind.STOP, m[1], m[2], m[3]!!, m[4], m[5])
            }
            // "trail my eth by 5%", "trailing stop eth 5%"
            match(START + """(?:set\s+(?:a\s+)?)?(?:trail(?:ing\s+stop)?|trailing)\s+(?:on\s+|for\s+)?""" + held + SYM +
                """\s+(?:by\s+|at\s+|with\s+)?""" + NUM + """\s?%""" + CHAIN_PART + END, t)?.let { m ->
                return trailing(m[1], m[2]!!, m[3], m[4])
            }
            // "protect my eth with a 5% trail"
            match(START + """protect\s+""" + held + SYM + """\s+with\s+(?:a\s+)?""" + NUM + """\s?%\s+trail(?:ing\s+stop)?""" +
                CHAIN_PART + END, t)?.let { m ->
                return trailing(m[1], m[2]!!, m[3], m[4])
            }
            return null
        }

        // "buy 0.1 eth tp 4500 sl 3000", "my eth: take profit 4500, stop loss 3000"
        private fun bracket(t: String): TradeIntent? {
            val tp = """(?:tp|take[- ]?profit)(?:\s+at)?\s+\$?""" + NUM
            val sl = """(?:sl|stop[- ]?loss|stop)(?:\s+at)?\s+\$?""" + NUM
            val joiner = """\s*(?:,|and|&|\+)?\s*"""
            match(START + """buy\s+(?:\$""" + NUM + """\s+(?:of|worth\s+of)\s+|""" + NUM + """\s+)?""" + SYM +
                """[,:]?\s+""" + tp + joiner + sl + CHAIN_PART + END, t)?.let { m ->
                val asset = symbol(m[3]) ?: return null
                val i = TradeIntent(Kind.BRACKET, amount = amount(m[1] ?: m[2]), sell = stableFor(asset), buy = asset,
                    chain = chain(m[6], asset), price = amount(m[4]), stopPrice = amount(m[5]))
                i.amountIsUSD = m[1] != null
                if (!i.amountIsUSD && m[2] != null) { i.buyAmount = amount(m[2]); i.amount = null }
                return sane(i)
            }
            match(START + """(?:(?:set\s+)?(?:a\s+)?bracket\s+(?:on\s+)?)?(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|""" + NUM + """\s+)?""" +
                SYM + """[,:]?\s+""" + tp + joiner + sl + CHAIN_PART + END, t)?.let { m ->
                val asset = symbol(m[2]) ?: return null
                return sane(TradeIntent(Kind.BRACKET, amount = amount(m[1]), sell = asset, buy = stableFor(asset),
                    chain = chain(m[5], asset), price = amount(m[3]), stopPrice = amount(m[4])))
            }
            return null
        }

        private fun word(said: String) = Regex("""\b""" + said + """\b""", RegexOption.IGNORE_CASE)

        // "buy $20 of eth every day for a week", "dca $50 into eth weekly for 4 weeks",
        // "buy $100 of eth over a day"
        private fun twap(text: String): TradeIntent? {
            // Autocorrect makes "every day" "everyday"; people say "daily" too.
            var t = text
            for ((said, meant) in listOf("everyday" to "every day", "daily" to "every day", "weekly" to "every week",
                    "hourly" to "every hour")) {
                t = word(said).replace(t, meant)
            }
            val units = """(hour|day|week)s?"""
            match(START + """(?:buy|dca)\s+\$""" + NUM + """\s+(?:of|worth\s+of|into|in)\s+""" + SYM +
                """\s+(?:every|each|a|per)\s+""" + units + """(?:\s+for\s+(a|an|one|two|three|four|five|six|seven|\d+)\s+""" +
                units + ")?" + CHAIN_PART + END, t)?.let { m ->
                val each = number(amount(m[1])) ?: return null
                val asset = symbol(m[2]) ?: return null
                val unit = seconds(m[3]!!)
                val span = m[4]?.let { count(it) * seconds(m[5] ?: m[3]!!) } ?: (7 * unit)
                val slices = max(1, span / unit)
                val i = TradeIntent(Kind.TWAP, amount = trimmed(each * slices), sell = stableFor(asset), buy = asset,
                    chain = chain(m[6], asset))
                i.amountIsUSD = true
                i.durationSeconds = span
                // What was typed, not the total: "$5 of ETH every hour for 2 hours".
                i.slice = Slice(trimmed(each), m[3]!!.lowercase(Locale.US), slices)
                return i
            }
            match(START + """(?:buy|dca)\s+\$""" + NUM + """\s+(?:of|worth\s+of|into|in)\s+""" + SYM +
                """\s+over\s+(a|an|one|two|three|four|five|six|seven|\d+)\s+""" + units + CHAIN_PART + END, t)?.let { m ->
                val asset = symbol(m[2]) ?: return null
                val i = TradeIntent(Kind.TWAP, amount = amount(m[1]), sell = stableFor(asset), buy = asset,
                    chain = chain(m[5], asset))
                i.amountIsUSD = true
                i.durationSeconds = count(m[3]!!) * seconds(m[4]!!)
                return i
            }
            return null
        }

        // "move 50 usdc from base to arbitrum", "bridge 0.1 eth from ethereum to base"
        private fun bridgeMove(t: String): TradeIntent? {
            val c = """(base|ethereum|mainnet|arbitrum|arb|optimism|op|polygon|unichain|solana)"""
            val m = match(START + """(?:move|bridge|send)\s+""" + NUM + """\s+""" + SYM + """\s+from\s+""" + c +
                """\s+to\s+""" + c + END, t) ?: return null
            val asset = symbol(m[2]) ?: return null
            val from = chains[m[3]!!.lowercase(Locale.US)] ?: return null
            val to = chains[m[4]!!.lowercase(Locale.US)] ?: return null
            if (from == to) return null
            val i = TradeIntent(Kind.BRIDGE, amount = amount(m[1]), sell = asset, buy = asset, chain = from)
            i.toChain = to
            return i
        }

        // "send 20 usdc to vitalik.eth", "pay arpit.sol 5 usdc", "send 0.01 eth to 0x12…"
        private fun send(t: String): TradeIntent? {
            val who = """([a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:eth|sol)|0x[0-9a-fA-F]{40})"""
            var m = match(START + """(?:send|pay|transfer)\s+""" + NUM + """\s+""" + SYM + """\s+to\s+""" + who + CHAIN_PART + END, t)
            if (m == null) {
                match(START + """(?:send|pay)\s+""" + who + """\s+""" + NUM + """\s+""" + SYM + CHAIN_PART + END, t)?.let { n ->
                    m = listOf(n[0], n[2], n[3], n[1], n[4])
                }
            }
            val g = m ?: return null
            val asset = symbol(g[2]) ?: return null
            val to = g[3] ?: return null
            if (baseStocks[asset] != null) return null
            val address = to.startsWith("0x") || to.startsWith("0X")
            val name = to.lowercase(Locale.US)
            // A .sol name is Solana's, and SOL only moves there: Phantom sends
            // it, and Phantom's send here carries SOL or USDC.
            val onSolana = name.endsWith(".sol") || asset == "SOL"
            if (onSolana && (address || asset !in listOf("SOL", "USDC"))) return null
            val i = TradeIntent(Kind.SEND, amount = amount(g[1]), sell = asset, buy = asset,
                chain = if (onSolana) "solana" else chain(g[4], asset))
            if (i.chain == "solana" && !onSolana) return null
            i.to = if (address) to else name
            return if (i.amount == null) null else i
        }

        /** A send's recipient on the strip: a name as typed, an address short. */
        fun shortRecipient(to: String): String {
            if (!to.startsWith("0x") || to.length <= 12) return to
            return to.take(6) + "…" + to.takeLast(4)
        }

        /** Whether [to] is a name to look up (not an address already). */
        fun isName(to: String?): Boolean = to != null && (to.endsWith(".eth") || to.endsWith(".sol"))

        /** A send on Solana (a .sol name, or SOL to a name) goes through the
         *  app's existing Phantom send (glyf://open?path=pay), with the address
         *  the name resolved to; everything else is the Trade screen's, which
         *  asks MetaMask. Null when it isn't a Solana send. */
        fun phantomSend(query: Map<String, String>): Map<String, String>? {
            if (query["kind"] != "send" || query["chain"] != "solana") return null
            val to = query["address"] ?: return null
            val amount = query["amount"] ?: return null
            val token = (query["sell"] ?: "").uppercase(Locale.US)
            val (mint, decimals) = when (token) {
                "SOL" -> "So11111111111111111111111111111111111111112" to 9
                "USDC" -> "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" to 6
                else -> return null
            }
            return mapOf("kind" to "send", "to" to to, "amount" to amount, "token" to token,
                "mint" to mint, "symbol" to token, "decimals" to decimals.toString())
        }

        /** What GET /names/resolve said, as the address for [chain] or the
         *  reason there is none: (address, problem). */
        fun recipient(name: String, chain: String, ok: Boolean, answer: org.json.JSONObject?): Pair<String?, String?> {
            if (!ok) {
                if (answer != null && answer.has("found") && !answer.optBoolean("found", true)) return null to "$name isn’t registered"
                return null to "Couldn’t look up $name"
            }
            val addresses = answer?.optJSONObject("addresses")
            // TradeIntent's chain names are the server's, Unichain aside (an
            // ENS name sets no Unichain record; its Ethereum one is the same account).
            fun record(k: String) = (addresses?.opt(k) as? String)?.takeIf { it.isNotEmpty() }
            val own = record(chain)
            val found = if (chain == "solana") own else (own ?: record("ethereum"))
            val solana = chain == "solana"
            val none = if (solana) "$name has no Solana address" else "$name has no Ethereum address"
            if (found == null) return null to none
            val shape = if (solana) Regex("""^[1-9A-HJ-NP-Za-km-z]{32,44}$""") else Regex("""^0x[0-9a-fA-F]{40}$""")
            if (!shape.matches(found)) return null to none
            return found to null
        }

        // "dca $20 in eth each month", "dca 20$ eth weekly", "invest 100 usdc in
        // sol monthly", "buy $50 of btc every week for 3 months".
        fun recurring(text: String): TradeIntent? {
            var t = text.takeLast(200)
            val lower = t.lowercase(Locale.US)
            if (listOf("dca", "invest", "buy", "stack", "put", "auto").none { lower.contains(it) }) return null
            // Two-week words first: "bi-weekly" holds "weekly".
            for ((said, meant) in listOf("bi-?weekly" to "every 2 weeks", "fortnightly" to "every 2 weeks",
                    "every other (day|week|month)" to "every 2 \$1s",
                    "everyday" to "every day", "daily" to "every day", "weekly" to "every week",
                    "hourly" to "every hour", "monthly" to "every month")) {
                t = word(said).replace(t, meant)
            }
            val n = """(\d+(?:[.,]\d+)?k?)"""
            val sym = """(eth|ether|weth|wbtc|btc|bitcoin|cbbtc|uni|link|aave|op|arb|pol|matic|aero|degen|sol|solana|pepe|ldo)"""
            val words = """(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+)"""
            val unit = """(hour|day|week|month|year)s?"""
            val pattern = """(?:^|[.!?\n]\s*|\b(?:pls|please|glyf|hey glyf)[,:]?\s+)""" +
                """(?:(?:set\s+up\s+(?:a\s+)?)?(?:dca|auto[- ]?buy|recurring\s+buy|invest|stack|put|buy))\s+""" +
                """(?:\$\s?""" + n + "|" + n + """\s?(?:\$|usd\b|dollars?\b|bucks\b|(usdc|usdt|dai)\b))""" +
                """(?:\s+(?:of|worth\s+of|into|in|on))?\s+""" + sym +
                """\s+(?:every|each|a|per)\s+(?:""" + words + """\s+)?(hour|day|week|month)s?""" +
                """(?:\s+for\s+(?:the\s+next\s+)?""" + words + """\s+""" + unit + ")?" +
                """(?:\s+on\s+(base|ethereum|mainnet|arbitrum|optimism|polygon|unichain|solana))?""" +
                """\s*[.!]?\s*$"""
            val m = match(pattern, t) ?: return null
            val each = number(amount(m[1] ?: m[2])) ?: return null
            val asset = symbol(m[4]) ?: return null
            val period = RecurringPlan.Period.of((m[6] ?: "").lowercase(Locale.US)) ?: return null
            val interval = m[5]?.let { bigNumber(it) } ?: 1
            var periods: Int? = null
            val howMany = m[7]
            val span = m[8]?.lowercase(Locale.US)
            if (howMany != null && span != null) {
                val spanSeconds = bigNumber(howMany) *
                    (if (span == "year") 365 * 86_400 else RecurringPlan.Period.of(span)?.seconds ?: 86_400)
                // "every week for 3 months": 13 weeks; "monthly for a year": 12.
                val step = period.seconds * interval
                periods = if (span == "year" && period == RecurringPlan.Period.MONTH) bigNumber(howMany) * 12 / interval
                    else max(1, rounded(spanSeconds.toDouble() / step.toDouble()).toInt())
            }
            return recurringBuy(each, asset, symbol(m[3]), period, interval, periods, m[9])
        }

        /** Builds the Flash TWAP for a plan of [periods] buys of [every] dollars. */
        fun recurringBuy(every: Double, asset: String, spend: String? = null,
                         period: RecurringPlan.Period, interval: Int = 1,
                         periods: Int?, chain: String?): TradeIntent? {
            if (!(every > 0 && every <= 1_000_000 && interval >= 1 && interval <= 12 &&
                    symbols.values.contains(asset) && asset !in listOf("USDC", "USDT", "DAI"))) return null
            val step = period.seconds * interval
            val total = max(1, min(periods ?: period.defaultCount, 520))
            val fits = max(1, RecurringPlan.FLASH_MAX_SECONDS / step)
            val placed = min(total, fits)
            val duration = min(RecurringPlan.FLASH_MAX_SECONDS, max(RecurringPlan.FLASH_MIN_SECONDS, placed * step))
            val sell = spend?.takeIf { it in listOf("USDC", "USDT", "DAI") } ?: stableFor(asset)
            val on = chain?.let { c -> chains[c.lowercase(Locale.US)] ?: (if (chainLabels[c] != null) c else null) }
                ?: (if (asset == "SOL") "solana" else null)
            val i = TradeIntent(Kind.TWAP, amount = trimmed(every * placed), sell = sell, buy = asset, chain = on)
            i.amountIsUSD = true
            i.durationSeconds = duration
            i.plan = RecurringPlan(trimmed(every), period, interval, total, placed)
            return i
        }

        // MARK: helpers

        private fun order(kind: Kind, a: String?, s: String, p: String?, c: String?): TradeIntent? {
            val asset = symbol(s) ?: return null
            if (asset in listOf("USDC", "USDT", "DAI")) return null
            return sane(TradeIntent(kind, amount = amount(a), sell = asset, buy = stableFor(asset),
                chain = chain(c, asset), price = amount(p)))
        }

        private fun buyOrder(kind: Kind, usd: String?, qty: String?, s: String, p: String?, c: String?): TradeIntent? {
            val asset = symbol(s) ?: return null
            if (asset in listOf("USDC", "USDT", "DAI")) return null
            val i = TradeIntent(kind, amount = amount(usd), sell = stableFor(asset), buy = asset,
                chain = chain(c, asset), price = amount(p))
            i.amountIsUSD = usd != null
            if (usd == null && qty != null) i.buyAmount = amount(qty)
            return sane(i)
        }

        private fun trailing(a: String?, s: String, percent: String?, c: String?): TradeIntent? {
            val asset = symbol(s) ?: return null
            val p = number(amount(percent)) ?: return null
            if (p < 0.5 || p > 50) return null
            val i = TradeIntent(Kind.TRAILING_STOP, amount = amount(a), sell = asset, buy = stableFor(asset),
                chain = chain(c, asset))
            i.trailPercent = trimmed(p)
            return i
        }

        /** A take-profit has to sit above the stop. */
        private fun sane(i: TradeIntent): TradeIntent? {
            number(i.price)?.let { if (it <= 0) return null }
            if (i.kind == Kind.BRACKET) {
                val tp = number(i.price); val sl = number(i.stopPrice)
                if (tp != null && sl != null && tp <= sl) return null
            }
            return i
        }

        fun symbol(word: String?): String? = word?.let { symbols[it.lowercase(Locale.US)] }

        /** What a token is priced against: USDC, or ETH for a stablecoin. */
        fun stableFor(symbol: String): String = if (symbol in listOf("USDC", "USDT", "DAI")) "ETH" else "USDC"

        private fun chain(word: String?, token: String): String? {
            if (baseStocks[token] != null) return "base"
            if (word != null) chains[word.lowercase(Locale.US)]?.let { return it }
            return if (token == "SOL") "solana" else null
        }

        /** "1,000" and "1.5k" as plain numbers; "3,000" with a comma is thousands. */
        fun amount(raw: String?): String? {
            var s = raw?.lowercase(Locale.US) ?: return null
            if (s.isEmpty()) return null
            var scale = 1.0
            if (s.endsWith("k")) { scale = 1000.0; s = s.dropLast(1) }
            if (s.contains(",") && s.split(",").last().length == 3) s = s.replace(",", "")
            s = s.replace(",", ".")
            val v = number(s) ?: return null
            if (v <= 0) return null
            return trimmed(v * scale)
        }

        fun trimmed(v: Double): String {
            if (v == rounded(v)) return v.toLong().toString()
            var s = String.format(Locale.US, "%.8f", v)
            while (s.endsWith("0")) s = s.dropLast(1)
            return s
        }

        private fun seconds(unit: String): Int = when (unit.lowercase(Locale.US)) {
            "hour" -> 3600
            "week" -> 7 * 86_400
            else -> 86_400
        }

        private val countWords = mapOf("a" to 1, "an" to 1, "one" to 1, "two" to 2, "three" to 3, "four" to 4,
            "five" to 5, "six" to 6, "seven" to 7)

        private fun count(word: String): Int = countWords[word.lowercase(Locale.US)] ?: word.toIntOrNull() ?: 1

        private fun bigNumber(word: String): Int =
            (countWords + mapOf("eight" to 8, "nine" to 9, "ten" to 10, "eleven" to 11, "twelve" to 12))[word.lowercase(Locale.US)]
                ?: word.toIntOrNull() ?: 1

        /** Capture groups of the last match, null where a group didn't take part. */
        private fun match(pattern: String, text: String): List<String?>? {
            val m = Regex(pattern, RegexOption.IGNORE_CASE).findAll(text).lastOrNull() ?: return null
            return (0..m.groupValues.lastIndex).map { m.groups[it]?.value }
        }
    }
}

/**
 * A buy repeated on a schedule ("dca $20 in eth each month", "invest 100
 * usdc in sol monthly", "buy $50 of btc every week for 3 months"), read on
 * the phone and placed as one Definitive Flash TWAP. Flash runs a TWAP for
 * 10 minutes to 30 days; a plan longer than that is placed as its first 30
 * days, and the panel says how much of the plan it covers ("1 of 12 months").
 */
data class RecurringPlan(
    /** Dollars spent each period. */
    val every: String,
    val period: Period,
    /** Periods between buys ("every 2 weeks" = 2). */
    val interval: Int = 1,
    /** How many buys the plan has. */
    val periods: Int,
    /** How many of them this one Flash order covers. */
    val placed: Int,
) {
    enum class Period(val raw: String, val seconds: Int, val adverb: String, val defaultCount: Int) {
        HOUR("hour", 3600, "hourly", 24),
        DAY("day", 86_400, "daily", 7),
        WEEK("week", 7 * 86_400, "weekly", 4),
        MONTH("month", 30 * 86_400, "monthly", 12);

        companion object {
            fun of(raw: String): Period? = values().firstOrNull { it.raw == raw }
        }
    }

    val capped: Boolean get() = placed < periods

    /** "$20 monthly", "$50 every 2 weeks". */
    val cadence: String
        get() = if (interval == 1) "$$every ${period.adverb}" else "$$every every $interval ${period.raw}s"

    /** What the panel shows under the amount: "$20 monthly · 12 months". */
    val summary: String get() = "$cadence · ${count(periods * interval, period.raw)}"

    /** Said only when Flash can't hold the whole plan. */
    val capNote: String?
        get() = if (capped) "Flash runs 30 days at most · $placed of $periods ${period.raw}s" else null

    companion object {
        /** Flash's longest TWAP. */
        const val FLASH_MAX_SECONDS = 30 * 86_400
        /** Flash's shortest (the quote API's floor). */
        const val FLASH_MIN_SECONDS = 300

        fun count(n: Int, unit: String): String = if (n == 1) "1 $unit" else "$n ${unit}s"
    }
}
