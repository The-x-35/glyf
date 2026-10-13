package com.arpit.glyf.ime

import org.json.JSONArray
import kotlin.math.pow

/**
 * The website's smart strip, on Android: while you type, the keyboard notices
 * an arithmetic expression, a sentence about to need a detail you saved, or a
 * payment address, and offers exactly one chip for it. The twin of
 * Smart.swift on iOS, rule for rule. Pure logic; user text is never run as code.
 */
object Smart {

    data class Field(val kind: String, val label: String, val value: String) {
        /** Its label, or its kind's name when saved without one. */
        val title: String get() = label.trim().ifEmpty {
            when (kind) {
                "name" -> "Name"; "email" -> "Email"; "phone" -> "Phone"
                "address" -> "Address"; "wallet" -> "Wallet address"; "link" -> "Link"
                "social" -> "Social"; "bio" -> "Bio"; else -> "Detail"
            }
        }
    }

    sealed class Chip {
        /** "3480/4" -> " = 870"; `hasEquals` when the "=" is already typed. */
        data class Calc(val result: String, val hasEquals: Boolean) : Chip() {
            /** The sum as typed, so the strip reads "2+5 = 7" (kept out of equality). */
            var expression: String = ""
        }
        /** "my upi id is " -> the saved UPI. */
        data class Vault(val field: Field) : Chip()
        /** More than one saved detail of the kind the sentence (or an empty
         *  form field) asks for: two emails, a home and a work address; or
         *  an email with a temp address beside it ([temp]). One part of the
         *  chip for each, and a tap on a part types it (Arpit, 2026-10-01:
         *  "if i added 2 mail ids i should see both, and i should also see
         *  a temp mail option"). Smart.swift's `.details`. [typed] is the
         *  start of a detail already typed ("ar", "123 Mar"): a part's tap
         *  puts the whole detail in its place (completions). */
        data class Details(val fields: List<Field>, val temp: Boolean, val typed: String = "") : Chip()
        /** A measurement the message ends on, in the other system: one part
         *  for each result ("10 inch" → 25.4 cm, 0.254 m), and a tap on a part
         *  adds it in brackets (Smart.conversions). Smart.swift's `.convert`. */
        data class Convert(val answer: Conversions) : Chip()
        /** The model read the sentence and named what Glyf could do with it. */
        data class Action(val label: String, val query: String, val intent: String) : Chip()
        /** Someone's Solana wallet on screen: Send opens in the app with it
         *  filled in (and the amount the message asks for). The keyboard
         *  never holds a key: Phantom signs. */
        data class Pay(val address: String, val amount: String? = null, val token: String? = null) : Chip()
        /** A token's address (a contract address someone shared): Buy opens
         *  for it in the app. */
        data class Buy(val mint: String, val symbol: String, val price: String?) : Chip()
        /** "$13" → "$13 = ₹1,246" where the phone is; "$sol" → "1 SOL = $112".
         *  `shown` is the whole line, `insert` what a tap adds after the
         *  amount. Never offered without a live rate. `buy` is the token's
         *  address when a cashtag can be bought: Buy then sits beside Insert. */
        data class Money(val shown: String, val insert: String, val buy: String? = null) : Chip()
        /** A plan in the message ("dinner friday 8pm"): one tap opens New
         *  Event with it filled in, nothing typed. */
        data class Event(val plan: EventParse.Plan) : Chip()
        /** Someone's Cal.com or Calendly page, in the message or just copied:
         *  one tap shows its open times to book, with the person's own details. */
        data class Booking(val link: String) : Chip()
    }

    /** The rates the keyboard has at hand (from the server, via RatesStore):
     *  `fiat` per dollar (INR: 95.88), `crypto` dollars per token (SOL: 111.77),
     *  `local` the currency where the phone is ("INR"). */
    data class RatesSnapshot(
        val fiat: Map<String, Double> = emptyMap(),
        val crypto: Map<String, Double> = emptyMap(),
        val local: String = "USD",
        /** A cashtag's token address, when it can be bought ("SOL" → "So1…"). */
        val mints: Map<String, String> = emptyMap(),
        /** What an address on screen turned out to be, once asked. */
        val addresses: Map<String, AddressKind> = emptyMap(),
        /** The market's ticker for what was typed ("APPLE", "APPL" → "AAPL"). */
        val tickers: Map<String, String> = emptyMap(),
    ) { companion object { val EMPTY = RatesSnapshot() } }

    /** A Solana address is someone's wallet or a token's; only a lookup can
     *  tell (both are base58 of the same length). */
    sealed class AddressKind {
        object Wallet : AddressKind()
        data class Token(val symbol: String, val usd: Double?) : AddressKind()
    }

    /** "7dHb…7ARj". */
    fun shortAddress(a: String): String = if (a.length > 12) "${a.take(4)}…${a.takeLast(4)}" else a

    /** The address a chip is waiting on: on screen, not yours, and not yet
     *  known to be a wallet or a token. */
    fun addressToCheck(text: String, rates: RatesSnapshot, ownWallet: String? = null): String? =
        payment(text)?.first?.takeIf { it != ownWallet && rates.addresses[it] == null }

    /** The small label on the chip's left, when there is one. */
    fun key(chip: Chip): String? = when (chip) {
        is Chip.Vault -> chip.field.title
        is Chip.Pay -> "Wallet"
        is Chip.Buy -> chip.symbol
        else -> null
    }

    /** What a tap does, on the chip's right edge; null for the model's own
     *  words, and for a details chip, whose parts are each their own action. */
    fun verb(chip: Chip): String? = when (chip) {
        is Chip.Calc, is Chip.Vault, is Chip.Money -> "Insert"
        is Chip.Event -> "Add"
        is Chip.Booking -> "Book"
        is Chip.Pay -> "Send"
        is Chip.Buy -> "Buy"
        is Chip.Action, is Chip.Details, is Chip.Convert -> null
    }

    /** What the chip says. */
    fun display(chip: Chip): String = when (chip) {
        // The whole sum where it fits: "2+5 = 7" reads as an answer, "7" alone
        // was easy to miss (user, 2026-09-29: "show result in recommendation strip").
        is Chip.Calc -> if (chip.expression.isEmpty() || chip.expression.length > 22) "= ${chip.result}"
            else "${chip.expression} = ${chip.result}"
        is Chip.Vault -> chip.field.value
        is Chip.Details -> (chip.fields.map { it.value } + if (chip.temp) listOf("Temp mail") else emptyList())
            .joinToString(" · ")
        is Chip.Convert -> if (chip.answer.source.isEmpty()) chip.answer.results.joinToString(" · ")
            else "${chip.answer.source} = " + chip.answer.results.joinToString(" · ")
        is Chip.Action -> chip.label
        is Chip.Money -> chip.shown
        // A plan that clashes says so, before the tap adds it (2026-10-14).
        is Chip.Event -> EventParse.summary(chip.plan) + (EventParse.busyNote?.invoke(chip.plan)?.let { " · $it" } ?: "")
        is Chip.Booking -> "A time on ${shortLink(chip.link)}"
        is Chip.Pay -> {
            val short = shortAddress(chip.address)
            if (chip.amount != null) "${chip.amount} ${chip.token ?: "USDC"} to $short" else short
        }
        is Chip.Buy -> chip.price ?: shortAddress(chip.mint)
    }

    /** What tapping puts in the field. */
    fun insert(chip: Chip): String = when (chip) {
        is Chip.Calc -> if (chip.hasEquals) " ${chip.result}" else " = ${chip.result}"
        is Chip.Vault -> chip.field.value
        is Chip.Money -> chip.insert
        // A part's own tap types it.
        is Chip.Action, is Chip.Pay, is Chip.Buy, is Chip.Event, is Chip.Booking, is Chip.Details,
        is Chip.Convert -> ""
    }

    /** A saved detail typed after what is there, with a space between when
     *  it would otherwise run on from the word before ("email" + a tap gives
     *  "email alex@example.com"). iOS's spaced(_:after:). */
    fun spaced(value: String, before: String?): String {
        val last = before?.lastOrNull() ?: return value
        return if (last.isWhitespace()) value else " $value"
    }

    /** An email chip gets a Temp mail part (Arpit, 2026-10-01: "i should
     *  also see a temp mail option"): your email and Temp mail, or two of
     *  yours and Temp mail. Any other chip is left as it is. */
    fun withTempMail(chip: Chip?): Chip? = when {
        chip is Chip.Vault && chip.field.kind == "email" -> Chip.Details(listOf(chip.field), temp = true)
        chip is Chip.Details && !chip.temp && chip.typed.isEmpty() && chip.fields.firstOrNull()?.kind == "email" ->
            Chip.Details(chip.fields.take(2), temp = true)
        else -> chip
    }

    private val bookingPattern = Regex(
        """(?:https?://)?(?:[a-z0-9-]+\.)?(?:cal\.com|calendly\.com)/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)?""",
        RegexOption.IGNORE_CASE)
    private val scheme = Regex("""^https?://(www\.)?""", RegexOption.IGNORE_CASE)

    /** A Cal.com or Calendly booking page in the text ("cal.com/sam/30min",
     *  "https://calendly.com/sam"), unless it is the person's own. */
    fun bookingLink(text: String, own: String? = null): String? {
        val link = bookingPattern.find(text)?.value ?: return null
        fun bare(s: String) = s.lowercase().replace(scheme, "")
        if (!own.isNullOrBlank() && (bare(own.trim()).startsWith(bare(link)) || bare(link).startsWith(bare(own.trim())))) return null
        return link
    }

    /** "cal.com/sam/30min" without the scheme. */
    fun shortLink(link: String): String = link.replace(scheme, "")

    /** The message asks for a time to talk, which the booking page answers. */
    fun asksToBook(text: String): Boolean = firstMatch(
        """\b(?:calendar link|booking link|scheduling link|calendly(?:\s+link)?|cal\.com(?:\s+link)?|book (?:a |some )?(?:time|slot|call|meeting|session)|pick a (?:time|slot)|grab (?:a |some )?time|schedule (?:a |some )?(?:time|call|meeting|chat)|find a time|set up a (?:call|meeting|time)|when (?:are|r) (?:you|u) free|(?:are|r) (?:you|u) free (?:this|next) week|your availability|my availability|what times? works? for you|a time that works)\b[?.!]?\s?$""",
        text) != null

    /** The message is about getting on a call, which a Meet link answers
     *  ("hop on a quick call?", "can we talk", "send me the meet link"). */
    fun asksToCall(text: String): Boolean = firstMatch(
        """\b(?:(?:hop|jump|get) on a (?:quick |video )?call|quick call|video call|can we (?:talk|call|chat|hop on)|(?:lets|let's) (?:call|talk|hop on|jump on|do a call)|wanna call|want to call|free (?:to talk|for a call)|up for a call|call now|meet link|(?:send|share) (?:me )?(?:a|the|your) (?:meet|call|video) link|(?:zoom|meet|facetime|call)\?)[?.!]?\s?$""",
        text) != null

    /** Vault fields out of the decrypted vault JSON. */
    fun fields(vault: org.json.JSONObject): List<Field> {
        val arr: JSONArray = vault.optJSONArray("fields") ?: return emptyList()
        return (0 until arr.length()).mapNotNull { i ->
            val f = arr.optJSONObject(i) ?: return@mapNotNull null
            Field(f.optString("kind"), f.optString("label"), f.optString("value"))
                .takeIf { it.value.isNotBlank() }
        }
    }

    /** One chip at most, in the website's order: a payment, a sum, an amount
     *  in another currency, a detail. [fieldKind] is what an empty form
     *  field asks for (Autofill.kind: "email", "phone", …): with nothing
     *  typed, the detail of that kind we hold, or every one of them. */
    fun chip(text: String, fields: List<Field>, indianGrouping: Boolean = true,
             rates: RatesSnapshot = RatesSnapshot.EMPTY, ownBooking: String? = null,
             ownWallet: String? = null, fieldKind: String? = null,
             region: String? = java.util.Locale.getDefault().country,
             linkContext: String? = null): Chip? {
        // A form asking for something we already know: one tap fills it,
        // one part each when there is more than one (nothing else reads an
        // empty field).
        if (text.isEmpty()) {
            val held = fieldKind?.let { detailsFor(it, fields) }.orEmpty()
            return when {
                fieldKind == null || held.isEmpty() -> null
                held.size > 1 -> Chip.Details(held.take(3), temp = false)
                else -> Chip.Vault(held[0])
            }
        }
        // An address: Send to a wallet, Buy a token. Your own wallet is one
        // you are sharing, not paying. Until the lookup says which, nothing
        // (the keyboard asks, and the strip is arranged again).
        payment(text)?.takeIf { it.first != ownWallet }?.let { (address, amount) ->
            return when (val kind = rates.addresses[address]) {
                is AddressKind.Token -> Chip.Buy(address, kind.symbol, kind.usd?.let { price(it) })
                AddressKind.Wallet -> {
                    val asked = amount ?: amountAsked(text)
                    Chip.Pay(address, asked?.first, asked?.second)
                }
                null -> null
            }
        }
        // A link longer than the strip's view of the message: its trackers.
        if (linkContext != null && linkContext.length > text.length && endsInLink(text)) {
            cleanLink(linkContext)?.let { return Chip.Convert(it) }
        }
        val quick = quickAnswer(text, region = region)
        calcMatch(text, indianGrouping)?.let { (value, hasEquals, expression) ->
            // "scored 43/50" is a score, not a division: the answer that read
            // more of the message wins.
            if (quick != null && quick.source.length > expression.length + 2 && quick.source.endsWith(expression)) return Chip.Convert(quick)
            return Chip.Calc(value, hasEquals).also { it.expression = expression }
        }
        money(text, rates)?.let { m ->
            // "18% gst on ₹1,000", "3 for $10": the bill says more than the
            // amount it ends on.
            if (quick != null && quick.source.length > moneyTailLength(text)) return Chip.Convert(quick)
            return m
        }
        // A cashtag waits for its price: "$sol" is SOL's price, never your
        // Solana wallet, even before the price has come.
        if (cashtag(text) != null) return null
        // "remind me to pay rent on the 1st": the reminder, before the date.
        if (Regex("""^\s*(?:pls\s+|please\s+)?(?:remind\s+me|reminder)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text)) {
            EventParse.looksLikePlan(text)?.let { return Chip.Event(it) }
        }
        quick?.let { return Chip.Convert(it) }
        // Every saved value the sentence asks for: two emails show both.
        val matches = vaultMatches(text, fields)
        if (matches.size > 1) return Chip.Details(matches.take(3), temp = false)
        matches.firstOrNull()?.let { return Chip.Vault(it) }
        // A detail being typed: its first letters offer the whole of it.
        completions(text, fields)?.let { (typed, hits) -> return Chip.Details(hits, temp = false, typed = typed) }
        // "Best," on a line of its own: sign with the saved name.
        signOff(text, fields)?.let { return Chip.Convert(it) }
        // Asked for a time to talk ("when are you free", "send me your
        // calendar link"): the person's own booking page (iOS 10-07).
        if (!ownBooking.isNullOrBlank() && asksToBook(text)) return Chip.Vault(Field("link", "Book a time", ownBooking))
        EventParse.looksLikePlan(text)?.let { return Chip.Event(it) }
        bookingLink(text, ownBooking)?.let { return Chip.Booking(it) }
        return null
    }

    // MARK: Money (Smart.swift twin)

    private val symbolCurrency = mapOf('$' to "USD", '€' to "EUR", '£' to "GBP", '₹' to "INR", '¥' to "JPY")
    private val wordCurrency = mapOf(
        "usd" to "USD", "dollar" to "USD", "dollars" to "USD", "bucks" to "USD",
        "eur" to "EUR", "euro" to "EUR", "euros" to "EUR",
        "gbp" to "GBP", "pound" to "GBP", "pounds" to "GBP", "quid" to "GBP",
        "inr" to "INR", "rupee" to "INR", "rupees" to "INR", "rs" to "INR",
        "jpy" to "JPY", "yen" to "JPY", "aud" to "AUD", "cad" to "CAD", "sgd" to "SGD",
        "chf" to "CHF", "cny" to "CNY", "rmb" to "CNY", "yuan" to "CNY", "hkd" to "HKD",
        "aed" to "AED", "dirham" to "AED", "dirhams" to "AED", "krw" to "KRW", "won" to "KRW",
    )
    private val currencySymbol = mapOf(
        "USD" to "$", "EUR" to "€", "GBP" to "£", "INR" to "₹", "JPY" to "¥", "CNY" to "¥", "KRW" to "₩",
    )
    /** How much of the message's end the money chip reads ("₹1,000"). */
    fun moneyTailLength(text: String): Int = amountPattern.find(text)?.value?.trim()?.length ?: 0

    /** An amount at the end of the text: "$13", "13 usd", "₹500", "20 euros". */
    private val amountPattern = Regex(
        """(?:([$€£₹¥])\s?(\d[\d,]*(?:\.\d+)?)|(\d[\d,]*(?:\.\d+)?)\s?([$€£₹¥]|[A-Za-z]{2,7}))\s*$""",
        RegexOption.IGNORE_CASE)
    private val weightTalk = Regex(
        """\b(lose|lost|losing|gain|gained|gaining|weigh|weighs|weighed|weighing|weight|heavy|heavier|lighter|lbs?|kgs?|kilos?|bench|squat|deadlift|lift|lifted|lifting|dumbbells?|curls?|born)\b""",
        RegexOption.IGNORE_CASE)
    /** "$sol", "$usdc": a ticker, never a number. */
    /** "\$sol", "\$aapl", or a name ("\$apple", "\$bitcoin"; the server finds it). */
    private val cashtagPattern = Regex("""(?:^|\s)\$([A-Za-z]{2,14})\s*$""")

    /** The ticker at the end of the text, for whoever fetches prices. */
    fun cashtag(text: String): String? = cashtagPattern.find(text)?.groupValues?.get(1)?.uppercase()

    private fun unitOf(m: MatchResult): String = m.groups[1]?.value ?: m.groups[4]?.value ?: ""
    private fun currencyOf(unit: String): String? =
        if (unit.length == 1) symbolCurrency[unit[0]] else wordCurrency[unit.lowercase()]

    /** Whether the text ends in an amount the chip could convert, rate or no
     *  rate — so the keyboard knows to go and fetch one. */
    fun looksLikeMoney(text: String): Boolean {
        val m = amountPattern.find(text) ?: return false
        return currencyOf(unitOf(m)) != null
    }

    /** "$13" here in India → "$13 = ₹1,246"; "₹500" → "₹500 = $5.21";
     *  "$sol" → "1 SOL = $111.77". A converted amount reads in the local
     *  currency (the point of converting); a token price is a price, which
     *  the market quotes in dollars, so it stays in dollars. */
    fun money(text: String, rates: RatesSnapshot): Chip.Money? {
        cashtag(text)?.let { ticker ->
            val usd = rates.crypto[ticker] ?: return null
            // "1 SOL = $112" is already the answer; do not price the price.
            if (text.replace("\$${ticker.lowercase()}", "", ignoreCase = true).trim().endsWith("=")) return null
            val quoted = price(usd)
            val name = rates.tickers[ticker] ?: ticker
            return Chip.Money("1 $name = $quoted", " = $quoted", rates.mints[ticker])
        }
        // "100 usd to inr", "$20 in euros": both currencies named (iOS 10-07).
        currencyPair(text)?.let { (amount, from, to) ->
            val fromRate = rates.fiat[from]?.takeIf { it > 0 } ?: return null
            val toRate = rates.fiat[to] ?: return null
            val result = format(amount / fromRate * toRate, to)
            return Chip.Money("${format(amount, from)} = $result", " = $result")
        }
        // "1 sol", "0.5 btc": an amount of a coin in dollars, Buy beside it.
        coinAmount(text)?.let { (typed, amount, symbol) ->
            val usd = rates.crypto[symbol] ?: return null
            val worth = price(usd * amount)
            return Chip.Money("$typed $symbol = $worth", " = $worth", rates.mints[symbol])
        }
        val m = amountPattern.find(text) ?: return null
        // The right-hand side of a conversion the chip itself put in ("$13 =
        // ₹1,246"): converting that back would be a loop, not help.
        if (text.substring(0, m.range.first).trimEnd().endsWith("=")) return null
        val amount = (m.groups[2]?.value ?: m.groups[3]?.value ?: "")
            .replace(",", "").toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val from = currencyOf(unitOf(m)) ?: return null
        // Pounds of weight are not money: "I lost 5 pounds", "bench 100 pounds".
        if (unitOf(m).lowercase().startsWith("pound") && weightTalk.containsMatchIn(text)) return null
        // Where the phone is, or dollars when the amount already is local.
        val to = if (from == rates.local) "USD" else rates.local
        if (to == from) return null
        val fromRate = rates.fiat[from]?.takeIf { it > 0 } ?: return null
        val toRate = rates.fiat[to] ?: return null
        val result = format(amount / fromRate * toRate, to)
        return Chip.Money("${format(amount, from)} = $result", " = $result")
    }

    /** An amount with both currencies named, the message ending on the
     *  second: (100, "USD", "INR") for "100 usd to inr". */
    fun currencyPair(text: String): Triple<Double, String, String>? {
        val g = firstMatch("""(?:([₹$€£¥])\s*)?(\d[\d,]*(?:\.\d+)?)\s*([A-Za-z]{2,8})?\s+(?:to|in|into|as)\s+([A-Za-z]{2,8}|[₹$€£¥])\??\s?$""", text)
            ?: return null
        val amount = g[2]?.replace(",", "")?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val from = g[1]?.firstOrNull()?.let { symbolCurrency[it] } ?: g[3]?.let { wordCurrency[it.lowercase()] } ?: return null
        val to = g[4]?.let { if (it.length == 1) symbolCurrency[it[0]] else wordCurrency[it.lowercase()] } ?: return null
        return if (from == to) null else Triple(amount, from, to)
    }

    /** Coins people write amounts of ("2 eth"); no LINK or DOT, which are words. */
    private val coinWords = setOf("sol", "btc", "eth", "usdc", "usdt", "bnb", "xrp", "doge",
                                  "ada", "avax", "ltc", "trx", "shib", "pepe", "bonk", "jup", "wif")

    /** An amount of a coin the message ends on: ("0.5", 0.5, "BTC") for "0.5 btc". */
    fun coinAmount(text: String): Triple<String, Double, String>? {
        // "price of eth", "how much is a btc" (iOS 10-14).
        firstMatch("""\b(?:price\s+of|how\s+much\s+is)\s+(?:an?\s+|one\s+)?([A-Za-z]{3,4})\s*(?:right\s+now|now|today)?\??\s?$""", text)?.let { g ->
            val word = g[1]?.lowercase()?.takeIf { it in coinWords } ?: return@let
            return Triple("1", 1.0, word.uppercase())
        }
        val g = firstMatch("""(?<![\d.,$])(\d[\d,]*(?:\.\d+)?)\s*([A-Za-z]{3,4})\.?(?:\s+(?:in|to)\s+(?:usd|dollars?|\$))?\??\s?$""", text) ?: return null
        val typed = g[1] ?: return null
        val word = g[2]?.lowercase()?.takeIf { it in coinWords } ?: return null
        val amount = typed.replace(",", "").toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        return Triple(typed, amount, word.uppercase())
    }

    /** A token's dollar price: cents from a dollar up ("$112.40"), and
     *  enough figures below one to see it move ("$0.50", "$0.0823",
     *  "$0.00000364"), as the app's Buy shows it. Smart.swift's `price`. */
    fun price(usd: Double): String {
        if (usd >= 0.01 || usd <= 0) {
            val nf = java.text.NumberFormat.getNumberInstance(java.util.Locale.US).apply {
                minimumFractionDigits = 2
                maximumFractionDigits = if (usd >= 1) 2 else 4
            }
            return "$" + nf.format(usd)
        }
        return "$" + java.math.BigDecimal(usd).round(java.math.MathContext(3)).stripTrailingZeros().toPlainString()
    }

    /** "₹1,246", "$5.21", "AED 47.70": the symbol where one is common, the
     *  code elsewhere; Indian grouping for rupees, whole yen and won. Money
     *  with cents shows both places ("₹1,919.60", not "₹1,919.6", which read
     *  as a typo); a whole amount shows none ("$20"). iOS formatNumber. */
    fun format(value: Double, code: String): String {
        val v = if (code == "JPY" || code == "KRW") Math.round(value).toDouble() else value
        var text = format(v, code == "INR")
        if (oneCentsPlace.containsMatchIn(text)) text += "0"
        return (currencySymbol[code] ?: "$code ") + text
    }
    private val oneCentsPlace = Regex("""\.\d$""")

    // MARK: Calculator

    /** A number as typed: a currency sign, square roots, digits or π, and a
     *  percentage. */
    private const val NUM = """(?:[₹$€£]\s*)?(?:√\s*)*(?:\d[\d,]*(?:\.\d+)?|π)%?"""
    /** Every operator people type between numbers (Arpit, 2026-09-29: "work
     *  for all maths symbols"): + - − * ** × x / ÷ ^ mod, the comparisons,
     *  and "of" after a percentage. */
    private const val OP = """(?:\*\*|>=|<=|[-−+*/×÷^x≥≤><]|\bmod\b|\bof\b)"""
    private val calcPattern = Regex(
        """((?:(?:(?<![\p{L}\d)])[-−]\s*)?\(?\s*$NUM\s*\)?(?:\s*$OP\s*\(?\s*$NUM\s*\)?)+)|√\s*\(?\s*$NUM\s*\)?)(\s*=)?\s*$""",
        RegexOption.IGNORE_CASE)
    /** What makes it a sum: any operator but a bare "of" ("page 2 of 10" is
     *  a count; "20% of 150" has its %). */
    private val hasOperator = Regex("""\*\*|>=|<=|[-−+*/×÷^≥≤><%√x]|\bmod\b""", RegexOption.IGNORE_CASE)
    /** Numbers that only look like a sum: whole dates ("29/09/2024",
     *  "2024-09-29", "exp 09/2026") and phone numbers ("555-1234",
     *  "555-123-4567", "+1-555-123-4567", "98765-43210"). Two small numbers
     *  are a sum: "24/7" is divided, "2-3" is -1. */
    private val notASum = Regex(
        """\s*(?:\d+(?:-\d+){2,}|\d{1,2}\s*/\s*\d{1,2}\s*/\s*\d{2,4}|\d{4}\s*/\s*\d{1,2}\s*/\s*\d{1,2}|\d{1,2}\s*/\s*(?:19|20)\d{2}|""" +
            """\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}-\d{4}|(?:\d{1,3}-)?\d{3}-\d{3}-\d{4}|\d{3}-\d{4}|\d{5}-\d{5})\s*""")
    private val comparison = Regex("""\s*(>=|<=|≥|≤|>|<)\s*""")

    fun calc(text: String, indianGrouping: Boolean = true): Pair<String, Boolean>? =
        calcMatch(text, indianGrouping)?.let { it.first to it.second }

    /** The sum at the end of the text: its value, whether "=" is typed, and
     *  the sum as typed. A comparison is "true" or "false". */
    fun calcMatch(text: String, indianGrouping: Boolean = true): Triple<String, Boolean, String>? {
        if (text.isEmpty()) return null
        // "half of 350", "a third of 90", "double 25", "sqrt 81": sums said
        // in words (iOS 10-07).
        firstMatch("""\b((?:a\s+)?(?:half|third|quarter)\s+of|double|twice|triple|sqrt|square\s+root(?:\s+of)?)\s+(?:[₹$€£]\s*)?(\d[\d,]*(?:\.\d+)?)\??\s?$""", text)?.let { g ->
            val words = g[1]?.lowercase()?.replace(Regex("""\s+"""), " ") ?: return@let
            val n = g[2]?.replace(",", "")?.toDoubleOrNull() ?: return@let
            val v = when {
                words.endsWith("half of") -> n / 2
                words.endsWith("third of") -> n / 3
                words.endsWith("quarter of") -> n / 4
                words == "double" || words == "twice" -> n * 2
                words == "triple" -> n * 3
                else -> kotlin.math.sqrt(n)
            }
            return Triple(format(v, indianGrouping), false, (g[0] ?: "").trim())
        }
        // "2 to the power of 10", "square of 12", "cube root of 27", "log 100",
        // "10 factorial", "pi to 5 digits" (iOS 10-14 probe).
        firstMatch("""(\d+(?:\.\d+)?)\s+(?:to\s+the\s+power\s+(?:of\s+)?|raised\s+to\s+(?:the\s+)?(?:power\s+(?:of\s+)?)?)(\d+(?:\.\d+)?)\??\s?$""", text)?.let { g ->
            val a = g[1]?.toDoubleOrNull() ?: return@let
            val b = g[2]?.toDoubleOrNull()?.takeIf { it <= 64 } ?: return@let
            val v = calcNumber(Math.pow(a, b), indianGrouping) ?: return@let
            return Triple(v, false, g[0]!!.trim())
        }
        firstMatch("""\b(square|cube)\s+of\s+(\d+(?:\.\d+)?)\??\s?$""", text)?.let { g ->
            val n = g[2]?.toDoubleOrNull() ?: return@let
            val v = calcNumber(if (g[1]?.lowercase() == "cube") n * n * n else n * n, indianGrouping) ?: return@let
            return Triple(v, false, g[0]!!.trim())
        }
        firstMatch("""\bcube\s+root\s+(?:of\s+)?(\d+(?:\.\d+)?)\??\s?$""", text)?.let { g ->
            val n = g[1]?.toDoubleOrNull() ?: return@let
            val v = calcNumber(Math.cbrt(n), indianGrouping) ?: return@let
            return Triple(v, false, g[0]!!.trim())
        }
        firstMatch("""\b(log|ln)\s*\(?\s*(\d+(?:\.\d+)?)\s*\)?\??\s?$""", text)?.let { g ->
            val n = g[2]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return@let
            val v = calcNumber(if (g[1]?.lowercase() == "ln") Math.log(n) else Math.log10(n), indianGrouping) ?: return@let
            return Triple(v, false, g[0]!!.trim())
        }
        firstMatch("""(?<![\w.])(\d{1,2})\s*(?:factorial|!)\??\s?$""", text)?.let { g ->
            val n = g[1]?.toIntOrNull()?.takeIf { it <= 20 } ?: return@let
            val v = (1..maxOf(1, n)).fold(1.0) { acc, k -> acc * k }
            calcNumber(v, indianGrouping)?.let { return Triple(it, false, g[0]!!.trim()) }
        }
        firstMatch("""\bpi\s+to\s+(\d{1,2})\s+(?:digits|decimal\s+places|places|decimals)\??\s?$""", text)?.let { g ->
            val n = g[1]?.toIntOrNull()?.takeIf { it in 1..15 } ?: return@let
            return Triple(String.format(java.util.Locale.US, "%.${n}f", Math.PI), false, g[0]!!.trim())
        }
        val m = calcPattern.find(text) ?: return null
        val expr = m.groups[1]?.value ?: return null
        val hasEquals = m.groups[2] != null
        if (!hasEquals && !hasOperator.containsMatchIn(expr)) return null
        if (!hasEquals && notASum.matches(expr)) return null
        // "the score was 3-1", "pick a number 1-10": two whole numbers and a
        // bare hyphen at the end of a sentence are a score or a range
        // (2026-10-14 probe: 2 and -9). Asked ("whats 10-3") or on its own
        // ("10-2") it is still a sum.
        if (!hasEquals && Regex("""^\s*\d+-\d+\s*$""").matches(expr)) {
            val before = text.substring(0, m.groups[1]!!.range.first)
            if (before.any { it.isLetter() } &&
                !Regex("""(?:what'?s|what\s+is|calc(?:ulate)?|equals?|=)\s*$""", RegexOption.IGNORE_CASE).containsMatchIn(before)) return null
        }
        // "miss you 2 <3": a heart, not a comparison.
        if (!hasEquals && Regex("""\s<3\s*$""").containsMatchIn(text)) return null
        val shown = expr.trim().replace(Regex("""\s+"""), " ")
        val cmp = comparison.find(expr)
        if (cmp != null) {
            val a = evaluate(expr.substring(0, cmp.range.first)) ?: return null
            val b = evaluate(expr.substring(cmp.range.last + 1)) ?: return null
            val truth = when (cmp.groupValues[1]) {
                ">" -> a > b
                "<" -> a < b
                ">=", "≥" -> a >= b
                else -> a <= b
            }
            return Triple(if (truth) "true" else "false", hasEquals, shown)
        }
        val v = evaluate(expr) ?: return null
        val currency = expr.firstOrNull { it in "₹$€£" }?.toString() ?: ""
        return Triple(currency + format(v, indianGrouping), hasEquals, shown)
    }

    /** [format] for the word sums, safe past a Long's reach ("20 factorial");
     *  nothing for infinity or NaN (Swift's calcNumber). */
    private fun calcNumber(v: Double, indian: Boolean): String? {
        if (!v.isFinite()) return null
        if (kotlin.math.abs(v) < 1e15) return format(v, indian)
        val digits = java.math.BigDecimal(v).setScale(0, java.math.RoundingMode.HALF_EVEN).abs().toPlainString()
        val grouped = if (indian) {
            digits.dropLast(3).reversed().chunked(2).joinToString(",").reversed() + "," + digits.takeLast(3)
        } else {
            digits.reversed().chunked(3).joinToString(",").reversed()
        }
        return (if (v < 0) "-" else "") + grouped
    }

    /** Up to two decimals, grouped the way the phone's region writes numbers:
     *  1,23,456 in India, 123,456 elsewhere. */
    fun format(v: Double, indian: Boolean): String {
        val rounded = Math.round(v * 100) / 100.0
        val negative = rounded < 0
        val abs = kotlin.math.abs(rounded)
        val whole = abs.toLong()
        val cents = Math.round((abs - whole) * 100)
        val digits = whole.toString()
        val grouped = if (digits.length <= 3) digits else if (indian) {
            val head = digits.dropLast(3)
            head.reversed().chunked(2).joinToString(",").reversed() + "," + digits.takeLast(3)
        } else {
            digits.reversed().chunked(3).joinToString(",").reversed()
        }
        val frac = when {
            cents == 0L -> ""
            cents % 10 == 0L -> "." + (cents / 10)
            else -> "." + cents.toString().padStart(2, '0')
        }
        return (if (negative) "-" else "") + grouped + frac
    }

    /** Recursive descent over a token list; null on anything not understood. */
    fun evaluate(expression: String): Double? {
        var src = expression.lowercase()
            .replace(Regex("""\bof\b"""), "*")
            .replace(Regex("""\bmod\b"""), "#")
            .replace("**", "^")
            .replace("x", "*")
            .replace("×", "*").replace("÷", "/").replace("−", "-")
        src = src.filterNot { it in "₹$€£, \t" }
        if (src.isEmpty()) return null

        val tokens = mutableListOf<String>()
        val number = StringBuilder()
        for (ch in src) {
            when {
                ch.isDigit() || ch == '.' -> number.append(ch)
                ch == 'π' -> {
                    if (number.isNotEmpty()) { tokens.add(number.toString()); number.clear() }
                    tokens.add(Math.PI.toString())
                }
                ch in "+-*/^()%#√" -> {
                    if (number.isNotEmpty()) { tokens.add(number.toString()); number.clear() }
                    tokens.add(ch.toString())
                }
                else -> return null
            }
        }
        if (number.isNotEmpty()) tokens.add(number.toString())

        var i = 0
        fun peek(): String? = tokens.getOrNull(i)
        fun percentSuffix(v: Double): Double {
            if (peek() == "%") { i++; return v / 100 }
            return v
        }
        lateinit var sum: () -> Double?
        fun unary(): Double? {
            if (peek() == "-") { i++; return unary()?.let { -it } }
            if (peek() == "√") {
                i++
                val v = unary() ?: return null
                return if (v < 0) null else kotlin.math.sqrt(v)
            }
            if (peek() == "(") {
                i++
                val v = sum() ?: return null
                if (peek() != ")") return null
                i++
                return percentSuffix(v)
            }
            val v = peek()?.toDoubleOrNull() ?: return null
            i++
            return percentSuffix(v)
        }
        fun power(): Double? {
            val base = unary() ?: return null
            if (peek() == "^") {
                i++
                val e = power() ?: return null
                return base.pow(e)
            }
            return base
        }
        fun product(): Double? {
            var v = power() ?: return null
            while (peek() == "*" || peek() == "/" || peek() == "#") {
                val op = peek()
                i++
                val rhs = power() ?: return null
                when (op) {
                    "/" -> { if (rhs == 0.0) return null; v /= rhs }
                    "#" -> { if (rhs == 0.0) return null; v %= rhs }
                    else -> v *= rhs
                }
            }
            return v
        }
        sum = {
            var v = product()
            while (v != null && (peek() == "+" || peek() == "-")) {
                val op = peek()
                i++
                // "200 + 10%" is 220, as on a phone's calculator: a bare
                // percentage added or taken off is a share of the left side.
                val start = i
                val rhs = product()
                val share = if (rhs != null && i == start + 2 && tokens[i - 1] == "%") v * rhs else rhs
                v = if (share == null) null else if (op == "+") v + share else v - share
            }
            v
        }
        val v = sum() ?: return null
        return if (i == tokens.size && v.isFinite()) v else null
    }

    // MARK: Payments

    private val addressPattern =
        Regex("""(?<![A-HJ-NP-Za-km-z1-9])([1-9A-HJ-NP-Za-km-z]{32,44})(?![A-HJ-NP-Za-km-z1-9])""")

    fun payment(text: String): Pair<String, Pair<String, String>?>? {
        if (text.isEmpty()) return null
        val address = addressPattern.find(text)?.groups?.get(1)?.value ?: return null
        // A real key mixes cases and digits; a run of letters is a sentence.
        if (address.none { it.isUpperCase() } || address.none { it.isLowerCase() } ||
            address.none { it.isDigit() }) return null
        return address to amountAsked(text)
    }

    /** "send $200" / "200 usdc" → ("200", "USDC"); "0.5 sol" → ("0.5", "SOL").
     *  Only what Send can pay in: dollars go as USDC, and nothing else is
     *  guessed at (500 rupees is not 500 USDC). */
    fun amountAsked(text: String): Pair<String, String>? {
        for ((p, token) in listOf(
            """\$\s*\d[\d,]*(?:\.\d{1,6})?(?![\d.])""" to "USDC",
            """\b\d[\d,]*(?:\.\d{1,6})?\s*(?:usdc|dollars?|bucks)\b""" to "USDC",
            """\b\d[\d,]*(?:\.\d{1,9})?\s*sol\b""" to "SOL",
        )) {
            val m = Regex(p, RegexOption.IGNORE_CASE).find(text) ?: continue
            val digits = m.value.filter { it.isDigit() || it == '.' }
            if (digits.isNotEmpty() && (digits.toDoubleOrNull() ?: 0.0) > 0) return digits to token
        }
        return null
    }

    // MARK: Contextual vault

    /** Sentence endings that mean "the next thing I type is X": the
     *  sentence leads into one of your own details ("my email is", "call me
     *  at", "ship it to") or labels it ("Email:"). A bare word at the end is
     *  not enough, "email" itself aside: "wrong address", "can you email",
     *  "i lost my phone" and "saw it on insta" are about something else.
     *  Smart.swift's twin. */
    private val triggers: List<Triple<Regex, List<String>, String?>> = listOf(
        // "This is" introduces you only at the start: "Hi, this is", not "this is great".
        Triple("""(?:\bmy name is|\bname:|(?:^|[.!?,\n]\s*|\b(?:hi|hey|hello|hii|hiya)\W*)this is)\s*$""", listOf("name"), null),
        // Before address: "my wallet address" asks for the wallet.
        // A coin's name alone is not a wallet ("$sol" is its price, "I bought
        // sol" a purchase), nor is someone else's ("phantom wallet is down").
        Triple("""(?<!\$)\b(?:(?:my|our)\s+(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet(?:\s+(?:address|addy))?|(?:my|our)\s+(?:sol|solana|phantom|usdc|crypto)\s+(?:address|addy)|(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet(?:\s+(?:address|addy))?\s*:|(?:sol|solana|phantom|usdc|crypto)\s+(?:address|addy)\s*:)\s*(?:is\s*)?:?\s*$""", listOf("wallet"), null),
        // Before address: "my email address is" is an email.
        Triple("""\b(?:(?:my|our)\s+(?:e-?mail|g-?mail|mail)(?:\s*(?:id|address|addy))?|(?:e-?mail|g-?mail|mail)\s+(?:me|us)\s+(?:at|on)|(?:e-?mail|g-?mail)(?:\s*(?:id|address|addy))?\s*:|mail\s*id\s*:)\s*(?:is\s*)?:?\s*$""", listOf("email"), null),
        // The word alone at the end offers it too (Arpit, 2026-10-01: "when
        // i type email it should show my email id"): "email", "send it to my
        // email", "email id", "gmail". Never the verb ("can you email", "i'll
        // email", "please email"), and it goes as soon as the sentence moves on.
        Triple("""(?:^|[\s,(])(?<!\b(?:can|could|will|would|should|shall|must|i'll|ill|we'll|i|we|you|u|they|he|she|to|pls|please|gonna|wanna|the|this|that|a|an|last|previous|prior|recent|earlier|next|new|old|first|same|your|his|her|their|its|whose|another|any|no|every|each|an?)\s)(?:e-?mail|g-?mail|mail\s*id)(?:\s*(?:id|address|addy))?\s*(?:is\s*)?:?\s*$""", listOf("email"), null),
        // An IP, web or website address is no place to deliver to.
        Triple("""(?:\b(?:my|our)\s+(?:(?:home|delivery|shipping|office|current|new)\s+)?(?:address|addy)|(?<!e-?mail\s)(?<!gmail\s)(?<!ip\s)(?<!web\s)(?<!website\s)(?<!mac\s)\b(?:(?:home|delivery|shipping|office)\s+)?address\s*:|\bdeliver(?:\s+it)?\s+to|\bsend\s+it\s+to|\bship\s+(?:it\s+)?to|\bcome\s+(?:over\s+)?to|\bpick\s+me\s+up\s+(?:from|at))\s*(?:is\s*)?:?\s*$""", listOf("address"), null),
        Triple("""\b(?:(?:my|our)\s+(?:upi|vpa|gpay|google\s+pay|phonepe|paytm)(?:\s+(?:id|number|handle))?|(?:upi|vpa|gpay|phonepe|paytm)(?:\s*id)?\s*:|(?:pay|gpay|phonepe|paytm)\s+me\s+(?:at|on))\s*(?:is\s*)?:?\s*$""", listOf("upi"), null),
        Triple("""\b(?:(?:my|our)\s+(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?|(?:follow|find|add|dm)\s+(?:me|us)\s+on\s+(?:insta|instagram|ig)|(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?\s*:)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "insta"),
        Triple("""\b(?:(?:my|our)\s+(?:twitter|x)(?:\s+(?:handle|id|username))?|(?:follow|find|dm)\s+(?:me|us)\s+on\s+(?:twitter|x)|(?:twitter|x\s+handle)\s*:)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "x"),
        Triple("""\b(?:(?:my|our)\s+linkedin(?:\s+(?:profile|url|handle|id))?|(?:find|add|connect\s+with)\s+(?:me|us)\s+on\s+linkedin|linkedin\s*:)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "linkedin"),
        // A phone number, not an account, card, order or ticket number, and
        // not the phone itself ("i lost my phone").
        Triple("""\b(?:(?:my|our)\s+(?:(?:phone|mobile|cell|contact|whatsapp)\s+)?(?:number|no\.?|num)|(?:my|our)\s+whatsapp|(?:phone|mobile|cell|contact|whatsapp)(?:\s+(?:number|no\.?|num))?\s*:|(?:call|text|whatsapp|ping|reach|ring)\s+(?:me|us)\s+(?:at|on))\s*(?:is\s*)?:?\s*$""", listOf("phone"), null),
        // The kind's own words, two of them, alone at the end (Arpit,
        // 2026-10-02: "for all data in vault, it should be super fast using
        // regex"): "phone number", "shipping address", "wallet address", "upi
        // id", "instagram", "linkedin". Never someone else's ("your number",
        // "the phone number", "whose address"), nor where something was seen
        // ("saw it on insta"). Smart.swift's twins.
        Triple("""(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:phone|mobile|cell|contact|whatsapp)\s+(?:number|no\.?|num)\s*(?:is\s*)?:?\s*$""", listOf("phone"), null),
        Triple("""(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:home|delivery|shipping|billing|office|work|current|postal|mailing)\s+(?:address|addy)\s*(?:is\s*)?:?\s*$""", listOf("address"), null),
        Triple("""(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet\s+(?:address|addy)|(?:sol|solana)\s+(?:address|addy))\s*(?:is\s*)?:?\s*$""", listOf("wallet"), null),
        Triple("""(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:upi|vpa)(?:\s*(?:id|handle))?\s*(?:is\s*)?:?\s*$""", listOf("upi"), null),
        Triple("""(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what|on|in|from|at|via|to)\s)(?:insta|instagram|ig\s+(?:handle|id|username))(?:\s+(?:handle|id|username))?\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "insta"),
        Triple("""(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:twitter|x)\s+(?:handle|id|username)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "x"),
        Triple("""(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what|on|in|from|at|via|to)\s)linkedin(?:\s+(?:profile|url|handle|id))?\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "linkedin"),
    ).map { (p, kinds, label) -> Triple(Regex(p, RegexOption.IGNORE_CASE), kinds, label) }

    /** Words that lead into one of your own details near the end of the
     *  sentence ("here's my number", "gpay me on"): the same list the server's
     *  suggestions use (server/src/lib/details.ts). */
    private val firstPerson: List<Pair<Regex, String>> = listOf(
        """\b(my|our)\s+(home\s+|delivery\s+|shipping\s+|office\s+|current\s+)?(address|addy|location)\b""" to "address",
        """\b(ship|deliver|send|courier|post)\s+(it|them|the\s+\w+|this)?\s*(to|at)\s*:?\s*$""" to "address",
        """\b(i\s+(live|stay)\s+(at|in)|come\s+(over\s+)?to|pick\s+me\s+up\s+(from|at))\s*:?\s*$""" to "address",
        """\b(my|our)\s+(phone|mobile|cell|contact|whatsapp)?\s*(number|no\.?|num)\b""" to "phone",
        """\b(call|text|whatsapp|ping|reach)\s+me\s+(on|at)\s*:?\s*$""" to "phone",
        """\b(my|our)\s+(e-?mail|mail\s*id|gmail)\b""" to "email",
        """\b(e-?mail|mail)\s+me\s+(on|at)\s*:?\s*$""" to "email",
        """\b(my|our)\s+(upi|vpa|gpay|google\s+pay|phonepe|paytm)(\s+(id|number|handle))?\b""" to "upi",
        """\b(gpay|google\s+pay|phonepe|paytm|upi|pay|transfer|send\s+(the\s+)?(money|amount|it))\s+(me\s+)?(on|at|to)\s*:?\s*$""" to "upi",
        """\b(my|our)\s+(sol(ana)?|crypto|usdc|phantom)?\s*wallet(\s+address)?\b""" to "wallet",
        """\b(my|our)\s+(website|portfolio|site|link|calendly)\b""" to "link",
        """\b(my|our)\s+(insta(gram)?|ig|twitter|x\s+handle|linkedin|handle)\b""" to "social",
        """\b(my|our)\s+gst(in)?(\s+(number|no\.?))?\b""" to "gst",
    ).map { (p, kind) -> Regex(p, RegexOption.IGNORE_CASE) to kind }

    fun vaultMatch(text: String, fields: List<Field>): Field? {
        if (text.isEmpty()) return null
        if (asksSomeoneElse(text)) return null
        for ((re, kinds, label) in triggers) {
            if (!re.containsMatchIn(text)) continue
            val candidates = fields.filter { it.kind in kinds }
            if (label != null) {
                candidates.firstOrNull { isPlatform(it.label, label) }?.let { return it }
                continue
            }
            // The sentence named the kind; with none saved there is nothing to offer.
            return candidates.firstOrNull()
        }
        return firstPersonMatch(text, fields)
    }

    /** What the vault holds for a field of this kind, one per value: its
     *  saved details, or a part of one (the postcode in an address, the first
     *  or last word of the name, a detail labelled as the company).
     *  Smart.swift's detailsFor; shared/vault/field-cases.json. */
    fun detailsFor(kind: String, fields: List<Field>): List<Field> {
        val found = when (kind) {
            "postcode" -> fields.filter { it.kind == "address" }
                .mapNotNull { a -> postcode(a.value)?.let { Field("postcode", "Postcode", it) } }
            "givenName", "familyName" -> fields.filter { it.kind == "name" }.mapNotNull { n ->
                val parts = n.value.trim().split(Regex("""\s+""")).filter { it.isNotEmpty() }
                if (parts.isEmpty() || (kind == "familyName" && parts.size < 2)) null
                else if (kind == "givenName") Field(kind, "First name", parts.first())
                else Field(kind, "Last name", parts.last())
            }
            "company" -> fields.filter {
                it.kind == "company" ||
                    Regex("""\b(?:company|organi[sz]ation|employer|workplace)\b""", RegexOption.IGNORE_CASE)
                        .containsMatchIn(it.label)
            }
            "city", "state", "cityState" -> fields.filter { it.kind == "address" }.mapNotNull { a ->
                val (city, state) = cityState(a.value) ?: return@mapNotNull null
                when (kind) {
                    "city" -> Field(kind, "City", city)
                    "state" -> state?.let { Field(kind, "State", it) }
                    else -> Field(kind, "City", state?.let { "$city, $it" } ?: city)
                }
            }
            else -> fields.filter { it.kind == kind }
        }
        return found.distinctBy { it.value.trim().lowercase() }
    }

    /** The city (and state, when one is written) in a saved address: "123
     *  Market St, San Francisco, CA 94103" → San Francisco, CA; "10 Downing
     *  St, London SW1A 2AA" → London. Nothing for a one-line address. */
    fun cityState(address: String): Pair<String, String?>? {
        val parts = address.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (parts.size < 2) return null
        val postcodes = Regex("""\b(?:\d[\d-]*|[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2})\b""")
        fun words(s: String) = s.replace(postcodes, "").trim().trim { !it.isLetterOrDigit() }
        fun isState(s: String) = s.isNotEmpty() && s.length <= 3 && s == s.uppercase()
        var tail = words(parts[parts.size - 1])
        var city: String
        var state: String? = null
        if (isState(tail) && parts.size >= 3) {
            state = tail
            city = words(parts[parts.size - 2])
        } else if (tail.isEmpty() && parts.size >= 3) {
            tail = words(parts[parts.size - 2])
            if (isState(tail) && parts.size >= 4) { state = tail; city = words(parts[parts.size - 3]) } else city = tail
        } else {
            city = tail
        }
        if (city.isEmpty() || city.length > 40 || !Regex("""^[\p{L} .'-]+$""").matches(city)) return null
        return city to state
    }

    /** The postcode in an address, the last one written: a UK or Canadian
     *  postcode, a US ZIP, a six-digit PIN, or four digits at the very end. */
    fun postcode(address: String): String? {
        val patterns = listOf(
            """\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b""",   // UK: SW1A 2AA
            """\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b""",            // Canada: K1A 0B1
            """\b\d{5}(?:-\d{4})?\b""",                     // US ZIP: 94103, 94103-1234
            """\b\d{3}\s?\d{3}\b""",                        // six digits: 560038, 560 038
            """\b\d{4}\s*$""",                              // four at the end: 2000, 1012
        )
        for (p in patterns) {
            val m = Regex(p, RegexOption.IGNORE_CASE).findAll(address).lastOrNull() ?: continue
            return m.value.trim().uppercase()
        }
        return null
    }

    /** The saved details the words being typed are the start of (Arpit,
     *  2026-10-06: "as soon person enters first 2-4 letters of any details
     *  in vault show that"): two letters or more ("ar" offers your email
     *  and your name), three digits or more of a number, with or without the
     *  country code it was saved with ("415"), across up to four words
     *  ("123 Mar" offers the address). The first of the pair is what a tap
     *  replaces; the longest run of words that starts something wins, and a
     *  detail typed out in full offers nothing. Three at most, one per
     *  value. Smart.swift's completions. */
    fun completions(text: String, fields: List<Field>): Pair<String, List<Field>>? {
        if (text.isEmpty() || text.last().isWhitespace() || fields.isEmpty()) return null
        val starts = text.indices.filter { !text[it].isWhitespace() && (it == 0 || text[it - 1].isWhitespace()) }
        if (starts.isEmpty()) return null
        for (k in minOf(4, starts.size) downTo 1) {
            val typed = text.substring(starts[starts.size - k])
            val seen = mutableSetOf<String>()
            val hits = fields.filter { startsDetail(typed, it.value) && seen.add(it.value.lowercase()) }
            if (hits.isNotEmpty()) return typed to hits.take(3)
        }
        return null
    }

    /** Whether [typed] begins [value] without being all of it: by its
     *  letters (two at least), or, with none, by its digits (three at least),
     *  a saved "+1 (415) 555-0100" answering to "415" too. */
    fun startsDetail(typed: String, value: String): Boolean {
        val t = typed.lowercase()
        val v = value.trim().lowercase()
        if (v.isEmpty() || t == v || t.length >= v.length) return false
        if (t.any { it.isLetter() }) return t.length >= 2 && v.startsWith(t)
        val td = t.filter { it.isDigit() }
        if (td.length < 3) return false
        if (v.any { it.isLetter() }) return v.startsWith(t)
        val vd = v.filter { it.isDigit() }
        if (vd.startsWith(td)) return vd.length > td.length
        // Saved with its country code, typed without it; all of it typed
        // without the code is typed already.
        if (!v.startsWith("+")) return false
        return (1..3).any { n -> vd.drop(n).let { rest -> rest.length > td.length && rest.startsWith(td) } }
    }

    /** Every saved detail the sentence asks for: the one vaultMatch finds
     *  first, then the others of its kind in the vault's order (a value saved
     *  twice shows once). A handle stays the platform's own: "my insta" is
     *  never the LinkedIn one. Smart.swift's vaultMatches. */
    fun vaultMatches(text: String, fields: List<Field>): List<Field> {
        // The person's own name for a detail wins: "work email" is the work one.
        val named = labelMatches(text, fields)
        if (named.isNotEmpty()) return named
        val first = vaultMatch(text, fields) ?: return emptyList()
        if (first.kind == "social" || first.kind == "handle") return listOf(first)
        return (listOf(first) + fields.filter { it.kind == first.kind }).distinctBy { it.value.trim() }
    }

    /** The word a qualifying label is followed by, per kind: "work" +
     *  "email", "home" + "address", "office" + "number". */
    private val kindWords = mapOf(
        "email" to """e-?mail|g-?mail|mail(?:\s*id)?""",
        "phone" to """(?:phone\s+)?(?:number|no\.?|num)|phone|line""",
        "address" to """address|addy""",
        "link" to """link|url|website|site""",
        "upi" to """upi(?:\s*id)?""",
        "wallet" to """(?:wallet\s+)?(?:address|addy)""",
        "handle" to """handle|username|id""",
        "social" to """handle|username|id""",
    )
    /** A label that is just the kind's own name ("Email", "Phone number"):
     *  the plain kind, which the triggers already offer. "Mobile", "Work" or
     *  "Home" are not: they say which one. */
    private val kindNames = mapOf(
        "email" to """e-?mail(?:\s+(?:address|id))?|g-?mail|mail(?:\s*id)?""",
        "phone" to """phone(?:\s+number)?|number|tel(?:ephone)?|contact(?:\s+number)?""",
        "address" to """address""",
        "link" to """link|url|website|site""",
        "upi" to """upi(?:\s*id)?|vpa""",
        "wallet" to """wallet(?:\s+address)?|address""",
        "handle" to """handle|username""",
        "social" to """handle|username""",
    )
    /** What a detail's own label may end on, or be followed by, and still
     *  name that detail: "passport number", "locker code", "car plate". */
    private const val DETAIL_NOUNS = """number|no\.?|num|id|code|pin|address|link|handle|account|acct|plate"""

    /** Saved details named by the person's own label for them, at the end of
     *  the sentence: "work email", "my office number is", "my passport number
     *  is", "locker code:", "car:". A label that only qualifies a kind (Home,
     *  Work, Office) needs the kind's word after it ("on my way home" is no
     *  address); a label of the person's own naming stands alone when it ends
     *  on a detail's noun ("locker code"), else takes one after it or a colon
     *  ("car number", "car:"; "my car is" is not the plate). Never someone
     *  else's ("your passport number", "the locker code"). Vault order.
     *  Smart.swift's labelMatches; shared/vault/cases.json. */
    fun labelMatches(text: String, fields: List<Field>): List<Field> {
        val clause = text.lowercase().split(Regex("[.!?\n]")).lastOrNull()?.trim().orEmpty()
        if (clause.isEmpty() || asksSomeoneElse(text)) return emptyList()
        val lead = """(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)"""
        val ending = """\s*(?:(?:is|are|=)\s*)?:?\s*$"""
        return fields.filter { f ->
            val label = f.label.lowercase().trim()
            if (label.length < 2) return@filter false
            val words = label.split(Regex("""\s+""")).joinToString("""\s+""") { Regex.escape(it) }
            val kind = kindWords[f.kind]
            val pattern = when {
                kind != null -> {
                    val name = kindNames[f.kind]
                    if (name != null && Regex("^(?:$name)$").matches(label)) return@filter false
                    lead + words + """\s+(?:""" + kind + ")" + ending
                }
                Regex("""\b(?:$DETAIL_NOUNS)$""").containsMatchIn(label) -> lead + words + ending
                else -> lead + words + """(?:\s+(?:$DETAIL_NOUNS)""" + ending + """|\s*:\s*$)"""
            }
            Regex(pattern).containsMatchIn(clause)
        }
    }

    /** The platform the words named for a handle ("insta", "x",
     *  "linkedin"), or null for a plain "handle". */
    private fun platformNamed(words: String): String? {
        val w = words.lowercase()
        return when {
            Regex("""\b(insta(gram)?|ig)\b""").containsMatchIn(w) -> "insta"
            Regex("""\b(twitter|x)\b""").containsMatchIn(w) -> "x"
            w.contains("linkedin") -> "linkedin"
            else -> null
        }
    }

    /** Whether a saved handle is that platform's, by its label ("Instagram",
     *  "IG", "Twitter", "X"). */
    private fun isPlatform(label: String, platform: String): Boolean {
        val l = label.lowercase().trim()
        return when (platform) {
            "insta" -> l.contains("insta") || Regex("""\big\b""").containsMatchIn(l)
            "x" -> l.contains("twitter") || Regex("""(^|\W)x($|\W)""").containsMatchIn(l)
            else -> l.contains(platform)
        }
    }

    /** "send me ur upi", "what's your address": a question for someone else. */
    private fun asksSomeoneElse(text: String): Boolean {
        val clause = text.lowercase().split(Regex("[.!?\n]")).lastOrNull()?.trim().orEmpty()
        val tail = clause.split(Regex("""\s+""")).takeLast(6).joinToString(" ")
        return Regex("""\b(your|ur|yours|his|her|their)\b""").containsMatchIn(tail)
    }

    /** First-person asks only. */
    fun firstPersonMatch(text: String, fields: List<Field>): Field? {
        val clause = text.lowercase().split(Regex("[.!?\n]")).lastOrNull()?.trim().orEmpty()
        if (clause.isEmpty() || asksSomeoneElse(text)) return null
        for ((re, kind) in firstPerson) {
            val m = re.find(clause) ?: continue
            // "My linkedin" is the LinkedIn one, never the Instagram handle;
            // "my handle" takes whichever there is.
            val platform = if (kind == "social") platformNamed(m.value) else null
            val field = fields.firstOrNull {
                (it.kind == kind || (kind == "social" && it.kind == "handle")) &&
                    (platform == null || isPlatform(it.label, platform))
            } ?: continue
            // The detail itself has not been typed yet.
            val after = clause.substring(m.range.last + 1).replace(Regex("""^[\s:,-]*(is|are|=)?[\s:,-]*"""), "")
            if (after.length <= 3) return field
        }
        return null
    }

    // MARK: Answers worked out on the phone (hold space)

    /** What a held space answers right here: a sum, a conversion, money at
     *  the rates the keyboard already holds, the time or the date. No
     *  network, no model, no run spent ("2+5" went to the server and back).
     *  Everything else still goes to the server. Smart.swift's twin, and the
     *  unit table is the server's lib/units.ts. */
    data class InstantAnswer(
        val title: String,
        /** The big line on the card: "7", "3.107 miles", "10:28 PM". */
        val value: String,
        val sub: String,
        /** What Insert puts in the message: "2+5 = 7", "5 km is 3.107 miles". */
        val say: String,
    )

    fun instantAnswer(
        text: String, rates: RatesSnapshot = RatesSnapshot.EMPTY, indianGrouping: Boolean = true,
        now: Long = System.currentTimeMillis(), zone: java.time.ZoneId = java.time.ZoneId.systemDefault(),
        locale: java.util.Locale = java.util.Locale.getDefault(),
    ): InstantAnswer? {
        val t = text.trim().replace(Regex("""\s+"""), " ").replace('’', '\'')
        if (t.isEmpty() || t.length > 80) return null
        sumAnswer(t, indianGrouping)?.let { return it }
        convertUnits(t)?.let { return InstantAnswer(t, it.to, it.from, it.say) }
        moneyAnswer(t, rates)?.let { return it }
        daysAnswer(t, now, zone, locale)?.let { return it }
        return clockAnswer(t, now, zone, locale)
    }

    // A sum asked as a sum: "2+5", "3480/4 =", "what is 12*12?", "18% of 2450".
    private val sumLead = Regex("""^(?:what\s+is|what's|whats|how\s+much\s+is|calculate|calc|solve)\s+""")
    private val sumTail = Regex("""[\s?=]+$""")
    private val percentOf = Regex("""^\d+(?:\.\d+)?\s*%\s*of\s*[\d,]+(?:\.\d+)?$""")
    private val plainSum = Regex("""^(?:[\d\s.,+\-−*/×÷^()%x√π<>≥≤]|mod)+$""")
    private val anOperation = Regex("""\d\s*(?:[-−+*/×÷^%<>≥≤]|x|mod)\s*[\d(√π]|\d\s*%|√\s*[\d(π]""")

    // "15% tip on 64": the tip, and what that comes to (answers.ts mathAnswer).
    private val tipAsk = Regex(
        """^(?:what\s+is\s+|what's\s+|whats\s+|calculate\s+)?([\d.]+)\s*%\s*tip\s*(?:on|for|of)\s*([$€£₹]?)\s*([\d,.]+)\s*\??$""",
        RegexOption.IGNORE_CASE)

    private fun tipAnswer(t: String): InstantAnswer? {
        val m = tipAsk.find(t) ?: return null
        val percentText = m.groupValues[1]
        val symbol = m.groupValues[2]
        val billText = m.groupValues[3]
        val percent = percentText.toDoubleOrNull() ?: return null
        val bill = billText.replace(",", "").toDoubleOrNull() ?: return null
        val f = java.text.DecimalFormat("#,##0.00", java.text.DecimalFormatSymbols(java.util.Locale.US))
            .apply { roundingMode = java.math.RoundingMode.HALF_UP }
        fun money(n: Double) = symbol + f.format(n)
        val tip = percent / 100 * bill
        return InstantAnswer(t, money(tip), "${money(bill + tip)} in all",
            "$percentText% tip on $symbol$billText is ${money(tip)} (${money(bill + tip)} in all)")
    }

    private fun sumAnswer(t: String, indianGrouping: Boolean): InstantAnswer? {
        tipAnswer(t)?.let { return it }
        val expr = t.lowercase().replace(sumLead, "").replace(sumTail, "").trim()
        val percent = percentOf.matches(expr)
        val plain = plainSum.matches(expr) && expr.any { it.isDigit() } && anOperation.containsMatchIn(expr)
        if (!percent && !plain) return null
        val value = calc("$expr =", indianGrouping)?.first ?: return null
        return InstantAnswer(expr, value, expr, if (percent) "$expr is $value" else "$expr = $value")
    }

    // "100 usd to inr", "$13 in rupees", "50 euros in dollars": today's rates,
    // when the keyboard has them (otherwise the server answers).
    private val moneyAsk = Regex(
        """^(?:convert\s+|what\s+is\s+|what's\s+|whats\s+|how\s+much\s+is\s+)?(?:([$€£₹¥])\s?(\d[\d,]*(?:\.\d+)?)|(\d[\d,]*(?:\.\d+)?)\s?([a-z]{2,8}|[$€£₹¥]))\s+(?:to|in|into|=)\s+([a-z]{2,8}|[$€£₹¥])\s*\??$""",
        RegexOption.IGNORE_CASE)

    private fun moneyAnswer(t: String, rates: RatesSnapshot): InstantAnswer? {
        val m = moneyAsk.find(t) ?: return null
        fun code(unit: String?): String? = unit?.let { currencyOf(it) }
        val amount = (m.groups[2]?.value ?: m.groups[3]?.value ?: "").replace(",", "")
            .toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val from = code(m.groups[1]?.value ?: m.groups[4]?.value) ?: return null
        val to = code(m.groups[5]?.value) ?: return null
        if (from == to) return null
        val fromRate = rates.fiat[from]?.takeIf { it > 0 } ?: return null
        val toRate = rates.fiat[to] ?: return null
        val typed = format(amount, from)
        val result = format(amount / fromRate * toRate, to)
        return InstantAnswer("$from to $to", result, "$typed · today's rate", "$typed = $result")
    }

    // "how many days until christmas": counted on the phone's own calendar
    // (answers.ts daysAnswer).
    private val daysAsk = Regex(
        """^(?:how\s+many\s+(days?|weeks?)\s+(?:are\s+)?(?:left\s+)?(?:until|till|til|to|before)|(days?|weeks?)\s+(?:left\s+)?(?:until|till|til|to)|how\s+long\s+(?:is\s+it\s+)?(?:until|till|til|to))\s+(.+?)\s*\??$""",
        RegexOption.IGNORE_CASE)

    /** Days everyone counts to: the name it is said with, and its month and
     *  day in a given year (Thanksgiving moves). */
    private val countedDays: List<Triple<Regex, String, (Int) -> Pair<Int, Int>>> = listOf(
        Triple(Regex("""^christmas eve$"""), "Christmas Eve") { _ -> 12 to 24 },
        Triple(Regex("""^(?:christmas|xmas|christmas day)$"""), "Christmas") { _ -> 12 to 25 },
        Triple(Regex("""^new year'?s eve$"""), "New Year's Eve") { _ -> 12 to 31 },
        Triple(Regex("""^(?:new year'?s?|new year'?s day|the new year)$"""), "New Year's Day") { _ -> 1 to 1 },
        Triple(Regex("""^halloween$"""), "Halloween") { _ -> 10 to 31 },
        Triple(Regex("""^valentine'?s(?: day)?$"""), "Valentine's Day") { _ -> 2 to 14 },
        Triple(Regex("""^(?:the )?(?:4th|fourth) of july$|^independence day$"""), "the Fourth of July") { _ -> 7 to 4 },
        Triple(Regex("""^thanksgiving$"""), "Thanksgiving") { year ->
            val first = java.time.LocalDate.of(year, 11, 1).dayOfWeek.value   // Monday 1 … Sunday 7
            11 to (1 + (4 - first + 7) % 7 + 21)                              // the fourth Thursday
        },
    )
    private val monthNames = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")

    private fun daysAnswer(t: String, now: Long, zone: java.time.ZoneId, locale: java.util.Locale): InstantAnswer? {
        val m = daysAsk.find(t.lowercase()) ?: return null
        val weeks = (m.groups[1]?.value ?: m.groups[2]?.value ?: "").startsWith("week")
        val what = m.groupValues[3].replace(Regex("""^the\s+"""), "").trim('?', '!', '.', ' ')
        val today = java.time.Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val label: String
        val dateFor: (Int) -> Pair<Int, Int>
        val holiday = countedDays.firstOrNull { (re, _, _) -> re.matches(what) || re.matches("the $what") }
        if (holiday != null) {
            label = holiday.second
            dateFor = holiday.third
        } else {
            // "dec 25", "december 25", "25 dec", "25th of december"
            val parts = what.split(" ").filter { it.isNotEmpty() && it != "of" }
            if (parts.size != 2) return null
            val dayFirst = parts[0].first().isDigit()
            val dayText = if (dayFirst) parts[0] else parts[1]
            val monthText = if (dayFirst) parts[1] else parts[0]
            val day = dayText.trimEnd { it.isLetter() }.toIntOrNull()?.takeIf { it in 1..31 } ?: return null
            val index = monthNames.indexOf(monthText.take(3)).takeIf { it >= 0 } ?: return null
            label = "${monthText.take(1).uppercase()}${monthText.drop(1).take(2)} $day"
            dateFor = { _ -> (index + 1) to day }
        }
        fun target(year: Int): java.time.LocalDate? = runCatching {
            val (month, day) = dateFor(year); java.time.LocalDate.of(year, month, day)
        }.getOrNull()
        var whenDate = target(today.year) ?: return null
        if (whenDate.isBefore(today)) whenDate = target(today.year + 1) ?: return null
        val days = java.time.temporal.ChronoUnit.DAYS.between(today, whenDate).toInt()
        fun plural(n: Int, word: String) = "$n $word${if (n == 1) "" else "s"}"
        val count = if (weeks && days >= 7)
            plural(days / 7, "week") + (if (days % 7 > 0) " and ${plural(days % 7, "day")}" else "")
        else plural(days, "day")
        val shown = if (locale.language == "en")
            java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d", locale).format(whenDate)
        else java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.FULL).withLocale(locale).format(whenDate)
        return InstantAnswer(t, if (days == 0) "Today" else count, shown,
            if (days == 0) "$label is today" else "$count until $label")
    }

    // "what time is it", "what's the date": the phone's own clock.
    private val timeAsk = Regex("""^(?:what(?:'s|s| is)?\s+(?:the\s+)?time(?:\s+(?:is\s+it|now|rn))?|what\s+time\s+is\s+it(?:\s+now)?|time(?:\s+now)?|current\s+time)\s*\??$""")
    private val dateAsk = Regex("""^(?:what(?:'s|s| is)?\s+(?:the\s+|today'?s\s+)?date(?:\s+today)?|today'?s\s+date|what\s+day\s+is\s+(?:it|today)(?:\s+today)?|date(?:\s+today)?|what(?:'s|s| is)\s+today)\s*\??$""")

    private fun clockAnswer(t: String, now: Long, zone: java.time.ZoneId, locale: java.util.Locale): InstantAnswer? {
        val lower = t.lowercase()
        val time = timeAsk.matches(lower)
        if (!time && !dateAsk.matches(lower)) return null
        val at = java.time.Instant.ofEpochMilli(now).atZone(zone)
        if (time) {
            // Newer Java puts a narrow no-break space before PM; a message wants a plain one.
            val clock = java.time.format.DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT)
                .withLocale(locale).format(at).replace(' ', ' ')
            val day = java.time.format.DateTimeFormatter.ofPattern("EEEE", locale).format(at)
            return InstantAnswer("Time", clock, day, "It's $clock")
        }
        val day = if (locale.language == "en")
            java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d", locale).format(at)
        else java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.FULL)
            .withLocale(locale).format(at)
        return InstantAnswer("Date", day, at.year.toString(), "It's $day")
    }

    // MARK: Units (lib/units.ts, the same table and the same cases)

    data class UnitConversion(val from: String, val to: String, val say: String)

    private class UnitDef(val dim: String, val size: Double, val one: String, val many: String, val names: List<String>)

    private val unitDefs = listOf(
        UnitDef("length", 0.001, "mm", "mm", listOf("mm", "millimeter", "millimeters", "millimetre", "millimetres")),
        UnitDef("length", 0.01, "cm", "cm", listOf("cm", "cms", "centimeter", "centimeters", "centimetre", "centimetres")),
        UnitDef("length", 1.0, "m", "m", listOf("m", "meter", "meters", "metre", "metres", "mtr", "mtrs")),
        UnitDef("length", 1000.0, "km", "km", listOf("km", "kms", "kilometer", "kilometers", "kilometre", "kilometres")),
        UnitDef("length", 0.0254, "inch", "inches", listOf("in", "inch", "inches")),
        UnitDef("length", 0.3048, "foot", "feet", listOf("ft", "foot", "feet")),
        UnitDef("length", 0.9144, "yard", "yards", listOf("yd", "yds", "yard", "yards")),
        UnitDef("length", 1609.344, "mile", "miles", listOf("mi", "mile", "miles")),
        UnitDef("mass", 0.001, "mg", "mg", listOf("mg", "milligram", "milligrams")),
        UnitDef("mass", 1.0, "g", "g", listOf("g", "gm", "gms", "gram", "grams")),
        UnitDef("mass", 1000.0, "kg", "kg", listOf("kg", "kgs", "kilo", "kilos", "kilogram", "kilograms")),
        UnitDef("mass", 1e6, "tonne", "tonnes", listOf("tonne", "tonnes")),
        UnitDef("mass", 28.349523125, "oz", "oz", listOf("oz", "ounce", "ounces")),
        UnitDef("mass", 453.59237, "lb", "lb", listOf("lb", "lbs", "pound", "pounds")),
        UnitDef("mass", 6350.29318, "stone", "stone", listOf("st", "stone", "stones")),
        UnitDef("temperature", 1.0, "°C", "°C", listOf("c", "°c", "celsius", "centigrade", "degrees c", "degree c", "deg c", "degrees celsius")),
        UnitDef("temperature", 1.0, "°F", "°F", listOf("f", "°f", "fahrenheit", "degrees f", "degree f", "deg f", "degrees fahrenheit")),
        UnitDef("temperature", 1.0, "K", "K", listOf("k", "kelvin")),
        UnitDef("volume", 0.001, "ml", "ml", listOf("ml", "milliliter", "milliliters", "millilitre", "millilitres")),
        UnitDef("volume", 1.0, "litre", "litres", listOf("l", "liter", "liters", "litre", "litres", "ltr", "ltrs")),
        UnitDef("volume", 0.00492892159375, "tsp", "tsp", listOf("tsp", "teaspoon", "teaspoons")),
        UnitDef("volume", 0.01478676478125, "tbsp", "tbsp", listOf("tbsp", "tablespoon", "tablespoons")),
        UnitDef("volume", 0.0295735295625, "fl oz", "fl oz", listOf("fl oz", "fluid ounce", "fluid ounces")),
        UnitDef("volume", 0.2365882365, "cup", "cups", listOf("cup", "cups")),
        UnitDef("volume", 0.473176473, "pint", "pints", listOf("pint", "pints")),
        UnitDef("volume", 0.946352946, "quart", "quarts", listOf("quart", "quarts")),
        UnitDef("volume", 3.785411784, "gallon", "gallons", listOf("gal", "gallon", "gallons")),
        UnitDef("speed", 1 / 3.6, "km/h", "km/h", listOf("km/h", "kmh", "kmph", "kph", "kilometers per hour", "kilometres per hour", "km per hour")),
        UnitDef("speed", 0.44704, "mph", "mph", listOf("mph", "miles per hour", "mi/h")),
        UnitDef("speed", 1.0, "m/s", "m/s", listOf("m/s", "meters per second", "metres per second")),
        UnitDef("speed", 1852.0 / 3600, "knot", "knots", listOf("knot", "knots")),
        UnitDef("time", 1.0, "second", "seconds", listOf("s", "sec", "secs", "second", "seconds")),
        UnitDef("time", 60.0, "minute", "minutes", listOf("min", "mins", "minute", "minutes")),
        UnitDef("time", 3600.0, "hour", "hours", listOf("h", "hr", "hrs", "hour", "hours")),
        UnitDef("time", 86400.0, "day", "days", listOf("day", "days")),
        UnitDef("time", 604800.0, "week", "weeks", listOf("wk", "wks", "week", "weeks")),
        UnitDef("time", 31557600.0, "year", "years", listOf("yr", "yrs", "year", "years")),
        UnitDef("area", 0.09290304, "sq ft", "sq ft", listOf("sq ft", "sqft", "square feet", "square foot", "ft2")),
        UnitDef("area", 1.0, "sq m", "sq m", listOf("sq m", "sqm", "square meters", "square metres", "square meter", "square metre", "m2")),
        UnitDef("area", 4046.8564224, "acre", "acres", listOf("acre", "acres")),
        UnitDef("area", 10000.0, "hectare", "hectares", listOf("ha", "hectare", "hectares")),
    )
    private val unitByName: Map<String, UnitDef> = unitDefs.flatMap { u -> u.names.map { it to u } }.toMap()
    /** Longest names first, so "fl oz" wins over "oz" and "km/h" over "km". */
    private val unitNames = unitByName.keys.sortedByDescending { it.length }.joinToString("|") { Regex.escape(it) }
    private const val UNIT_NUMBER = """(-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|-?\.\d+)"""
    private val unitDirect = Regex(
        """^(?:(?:convert|what\s+is|what's|whats|how\s+much\s+is|how\s+many\s+is)\s+)?$UNIT_NUMBER\s*(?:degrees?\s+)?($unitNames)\s+(?:to|in|into|as|in\s+to|=|->|=>)\s+(?:degrees?\s+)?($unitNames)\s*\??$""")
    private val unitHowMany = Regex(
        """^how\s+many\s+($unitNames)\s+(?:are\s+)?(?:in|is\s+in|make|makes)\s+(?:(?:a|an|one)\s+|$UNIT_NUMBER\s*)($unitNames)\s*\??$""")

    /** A height in feet and inches: "5 ft 10 in", "5'10", "5 feet 10 inches". */
    private val unitFeetInches = Regex(
        """^(?:(?:convert|what\s+is|what's|whats|how\s+much\s+is)\s+)?(\d+)\s*(?:ft|feet|foot|')\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|"|'')?\s+(?:to|in|into|as|=)\s+($unitNames)\s*\??$""")

    /** Under ten feet, feet come as a height: "5 ft 10 in", not "5.84 feet". */
    private fun asHeight(metres: Double): String? {
        val feet = metres / 0.3048
        if (feet < 1 || feet >= 10) return null
        var whole = kotlin.math.floor(feet).toInt()
        var inches = Math.round((feet - whole) * 12).toInt()
        if (inches == 12) { whole += 1; inches = 0 }
        return if (inches > 0) "$whole ft $inches in" else "$whole ft"
    }

    /** "5 km in miles" → "5 km is 3.107 miles"; null when it is not a conversion. */
    fun convertUnits(text: String): UnitConversion? {
        val t = text.trim().replace(Regex("""\s+"""), " ").replace('’', '\'').lowercase()
        unitFeetInches.find(t)?.let { h ->
            val to = unitByName[h.groupValues[3]]?.takeIf { it.dim == "length" } ?: return null
            val feet = h.groupValues[1].toDoubleOrNull() ?: return null
            val inches = h.groupValues[2].toDoubleOrNull() ?: return null
            val metres = feet * 0.3048 + inches * 0.0254
            val a = if (inches > 0) "${feet.toInt()} ft ${unitNumber(inches)} in" else "${feet.toInt()} ft"
            val b = unitNamed(unitFromBase(metres, to), to)
            return UnitConversion(a, b, "$a is $b")
        }
        val amount: Double
        val from: UnitDef?
        val to: UnitDef?
        val direct = unitDirect.find(t)
        if (direct != null) {
            amount = direct.groupValues[1].replace(",", "").toDoubleOrNull() ?: return null
            from = unitByName[direct.groupValues[2]]
            to = unitByName[direct.groupValues[3]]
        } else {
            val how = unitHowMany.find(t) ?: return null
            to = unitByName[how.groupValues[1]]
            amount = how.groups[2]?.value?.replace(",", "")?.toDoubleOrNull() ?: 1.0
            from = unitByName[how.groupValues[3]]
        }
        if (from == null || to == null || from.one == to.one || from.dim != to.dim || !amount.isFinite()) return null
        val result = unitFromBase(unitToBase(amount, from), to)
        if (!result.isFinite()) return null
        val a = unitNamed(amount, from)
        val b = (if (to.one == "foot") asHeight(unitToBase(amount, from)) else null) ?: unitNamed(result, to)
        return UnitConversion(a, b, "$a is $b")
    }

    private fun unitToBase(n: Double, u: UnitDef): Double = when {
        u.dim != "temperature" -> n * u.size
        u.one == "°F" -> (n - 32) * 5 / 9
        u.one == "K" -> n - 273.15
        else -> n
    }

    private fun unitFromBase(n: Double, u: UnitDef): Double = when {
        u.dim != "temperature" -> n / u.size
        u.one == "°F" -> n * 9 / 5 + 32
        u.one == "K" -> n + 273.15
        else -> n
    }

    /** As precise as the size needs: 160,934, 220.5, 32.19, 3.107, 0.0254. */
    fun unitNumber(n: Double): String {
        val size = kotlin.math.abs(n)
        if (size >= 1 || size == 0.0) {
            val decimals = when { size >= 1000 -> 0; size >= 100 -> 1; size >= 10 -> 2; else -> 3 }
            val pattern = "#,##0" + if (decimals > 0) "." + "#".repeat(decimals) else ""
            return java.text.DecimalFormat(pattern, java.text.DecimalFormatSymbols(java.util.Locale.US))
                .apply { roundingMode = java.math.RoundingMode.HALF_UP }.format(n)
        }
        return java.math.BigDecimal(n).round(java.math.MathContext(3, java.math.RoundingMode.HALF_UP))
            .stripTrailingZeros().toPlainString()
    }

    private fun unitNamed(n: Double, u: UnitDef): String {
        val text = unitNumber(n)
        return when {
            u.one == "K" -> "$text K"
            u.one.startsWith("°") -> "$text${u.one}"
            else -> "$text ${if (kotlin.math.abs(n) == 1.0) u.one else u.many}"
        }
    }

    // MARK: measurements, in the other system as they are typed (Smart.swift twin)

    /** A measurement the message ends on, in the other system (Arpit,
     *  2026-10-03: "when i write lets 10 inch, i see in cm or meteres, diff
     *  strips with suggestions"): "10 inch" → 25.4 cm, 0.254 m; "5'11" →
     *  180 cm, 1.8 m; "72°F" → 22.2°C; "1/2 cup" → 118 ml. Each result is a
     *  chip of its own, and a tap adds it in brackets after the measurement.
     *  Only names that can't be anything else after a number in a chat:
     *  "in", "m", "min", "c" or "f" without "°", and "4g" are other things.
     *  shared/units/strip-cases.json holds the cases. */
    data class Conversions(
        /** What the answer is about, as typed: "10 inch". */
        val source: String,
        /** What each chip says, best first: ["25.4 cm", "0.254 m"]. */
        val results: List<String>,
        /** What each chip puts in the message, when it is not its words (a
         *  carrier's link behind "UPS tracking"). */
        val inserts: List<String>? = null,
        /** How each goes in; in brackets after what was typed when null. */
        val hows: List<Insertion>? = null,
    ) {
        fun insert(i: Int): String = inserts?.getOrNull(i) ?: results[i]
        fun how(i: Int): Insertion = hows?.getOrNull(i) ?: Insertion.BRACKET
    }

    /** How a tap on an answer goes into the message: in brackets after what
     *  was typed, after it (a link, a piece of a copy), or in its place
     *  (";date" → the date). */
    enum class Insertion { BRACKET, AFTER, REPLACE }

    private val stripNames: Map<String, String> = buildMap {
        fun add(unit: String, vararg names: String) { for (n in names) put(n, unit) }
        add("mm", "mm", "millimeter", "millimeters", "millimetre", "millimetres")
        add("cm", "cm", "cms", "centimeter", "centimeters", "centimetre", "centimetres")
        // A bare "m" too ("2m"), unless it reads as millions or minutes
        // (conversions checks).
        add("m", "m", "meter", "meters", "metre", "metres", "mtr", "mtrs")
        add("km", "km", "kms", "kilometer", "kilometers", "kilometre", "kilometres")
        add("inch", "inch", "inches")
        add("foot", "ft", "foot", "feet")
        add("yard", "yd", "yds", "yard", "yards")
        add("mile", "mile", "miles")
        add("g", "g", "gm", "gms", "gram", "grams")
        add("kg", "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms")
        add("oz", "oz", "ounce", "ounces")
        add("lb", "lb", "lbs", "pound", "pounds")
        add("stone", "stone", "stones")
        add("°C", "°c", "° c", "ºc", "deg c", "degree c", "degrees c", "celsius", "degrees celsius", "centigrade")
        add("°F", "°f", "° f", "ºf", "deg f", "degree f", "degrees f", "fahrenheit", "degrees fahrenheit")
        add("ml", "ml", "milliliter", "milliliters", "millilitre", "millilitres")
        add("litre", "litre", "litres", "liter", "liters", "ltr", "ltrs")
        add("tsp", "tsp", "teaspoon", "teaspoons")
        add("tbsp", "tbsp", "tablespoon", "tablespoons")
        add("fl oz", "fl oz", "fluid ounce", "fluid ounces")
        add("cup", "cup", "cups")
        add("pint", "pint", "pints")
        add("quart", "quart", "quarts")
        add("gallon", "gal", "gallon", "gallons")
        add("km/h", "km/h", "kmh", "kmph", "kph", "km per hour", "kilometers per hour", "kilometres per hour")
        add("mph", "mph", "miles per hour")
        add("m/s", "m/s", "meters per second", "metres per second")
        add("knot", "knot", "knots")
        add("sq ft", "sq ft", "sqft", "square feet", "square foot", "ft2")
        add("sq m", "sq m", "sqm", "square meter", "square meters", "square metre", "square metres", "m2")
        add("sq yd", "sq yd", "sqyd", "square yard", "square yards")
        add("acre", "acre", "acres")
        add("hectare", "hectare", "hectares")
    }

    /** A number as typed: 10, 2.5, 1,500, 1/2, 1 1/2, ½, 1½, -5. */
    private const val STRIP_AMOUNT = """(-?\d+\s+\d+/\d+|\d+/\d+|-?\d*[½⅓⅔¼¾⅛]|-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|-?\.\d+)"""
    private val stripMeasure: Regex by lazy {
        val names = stripNames.keys.sortedByDescending { it.length }.joinToString("|") { Regex.escape(it) }
        Regex("""(?<![\p{L}\d.,/])""" + STRIP_AMOUNT + """\s*(?:degrees?\s+)?(""" + names + """)\.?\s?$""",
            RegexOption.IGNORE_CASE)
    }
    /** A measure and the unit asked for: "10 km to miles", "5 lbs in kg?". */
    private val stripAsked: Regex by lazy {
        val names = stripNames.keys.sortedByDescending { it.length }.joinToString("|") { Regex.escape(it) }
        Regex("""(?<![\p{L}\d.,/])""" + STRIP_AMOUNT + """\s*(?:degrees?\s+)?(""" + names +
            """)\.?\s+(?:to|in|into|as)\s+(""" + names + """)\??\s?$""", RegexOption.IGNORE_CASE)
    }

    /** What a unit measures: only a length goes into a length. */
    private fun stripDimension(unit: String): String = when (unit) {
        "mm", "cm", "m", "km", "inch", "foot", "yard", "mile" -> "length"
        "g", "kg", "oz", "lb", "stone" -> "mass"
        "km/h", "mph", "m/s", "knot" -> "speed"
        "sq ft", "sq m", "sq yd", "acre", "hectare" -> "area"
        "°C", "°F" -> "temperature"
        else -> "volume"
    }

    /** A height: 5'11, 5'11", 5 ft 11 in, 5 feet 11 inches, 5ft11. */
    private val stripHeight = Regex(
        """(?<![\p{L}\d.])([1-8])\s*(?:'|′|ft|feet|foot)\s*(\d{1,2}(?:\.\d+)?)\s*(?:"|″|''|in|inch|inches)?\.?\s?$""",
        RegexOption.IGNORE_CASE)
    private val partOfMore = Regex("""\d\s*(?:-|–|to|x|×|by)\s*$""", RegexOption.IGNORE_CASE)
    private val fractions = mapOf('½' to 0.5, '⅓' to 1.0 / 3, '⅔' to 2.0 / 3, '¼' to 0.25, '¾' to 0.75, '⅛' to 0.125)

    private fun amount(s: String): Double? {
        val t = s.trim()
        val last = t.lastOrNull() ?: return null
        fractions[last]?.let { part ->
            val whole = t.dropLast(1)
            if (whole.isEmpty()) return part
            if (whole == "-") return -part
            val w = whole.toDoubleOrNull() ?: return null
            return if (w < 0) w - part else w + part
        }
        val pieces = t.split(" ").filter { it.isNotEmpty() }
        if (pieces.size == 2) {
            val w = pieces[0].toDoubleOrNull()
            val f = amount(pieces[1])
            if (w != null && f != null) return if (w < 0) w - f else w + f
        }
        if ('/' in t) {
            val ab = t.split("/").mapNotNull { it.toDoubleOrNull() }
            if (ab.size != 2 || ab[1] == 0.0) return null
            return ab[0] / ab[1]
        }
        return t.replace(",", "").toDoubleOrNull()
    }

    /** Sizes in metres, kilograms, litres, metres a second and square metres;
     *  in Britain pints, gallons and fluid ounces are imperial ones. */
    private fun stripSize(unit: String, uk: Boolean): Double? = when (unit) {
        "mm" -> 0.001; "cm" -> 0.01; "m" -> 1.0; "km" -> 1000.0
        "inch" -> 0.0254; "foot" -> 0.3048; "yard" -> 0.9144; "mile" -> 1609.344
        "g" -> 0.001; "kg" -> 1.0; "oz" -> 0.028349523125; "lb" -> 0.45359237; "stone" -> 6.35029318
        "ml" -> 0.001; "litre", "L" -> 1.0
        "tsp" -> 0.00492892159375; "tbsp" -> 0.01478676478125
        "fl oz" -> if (uk) 0.0284130625 else 0.0295735295625
        "cup" -> 0.2365882365
        "pint" -> if (uk) 0.56826125 else 0.473176473
        "quart" -> if (uk) 1.1365225 else 0.946352946
        "gallon" -> if (uk) 4.54609 else 3.785411784
        "km/h" -> 1 / 3.6; "mph" -> 0.44704; "m/s" -> 1.0; "knot" -> 1852.0 / 3600
        "sq ft" -> 0.09290304; "sq m" -> 1.0; "sq yd" -> 0.83612736; "acre" -> 4046.8564224; "hectare" -> 10000.0
        else -> null
    }

    /** How a result is written: "25.4 cm", "3.11 miles", "22.2°C". */
    private fun stripNamed(n: Double, unit: String): String {
        val text = stripNumber(n)
        val one = kotlin.math.abs(n) == 1.0
        return when (unit) {
            "°C", "°F" -> text + unit
            "inch" -> "$text in"
            "foot" -> "$text ft"
            "yard" -> "$text yd"
            "mile" -> "$text ${if (one) "mile" else "miles"}"
            "litre" -> "$text L"
            "cup" -> "$text ${if (one) "cup" else "cups"}"
            "pint" -> "$text ${if (one) "pint" else "pints"}"
            "gallon" -> "$text gal"
            "acre" -> "$text ${if (one) "acre" else "acres"}"
            "hectare" -> "$text ${if (one) "hectare" else "hectares"}"
            else -> "$text $unit"
        }
    }

    /** Three figures, whole numbers from 100: 25.4, 3.94, 0.254, 180, 1,609. */
    fun stripNumber(n: Double): String {
        val size = kotlin.math.abs(n)
        val text = if (size >= 1 || size == 0.0) {
            val decimals = when { size >= 100 -> 0; size >= 10 -> 1; else -> 2 }
            val pattern = "#,##0" + if (decimals > 0) "." + "#".repeat(decimals) else ""
            java.text.DecimalFormat(pattern, java.text.DecimalFormatSymbols(java.util.Locale.US))
                .apply { roundingMode = java.math.RoundingMode.HALF_UP }.format(n)
        } else {
            java.math.BigDecimal(n).round(java.math.MathContext(3, java.math.RoundingMode.HALF_UP))
                .stripTrailingZeros().toPlainString()
        }
        return if (text == "-0") "0" else text
    }

    /** Feet and inches, for a height: "5 ft 11 in". */
    private fun feetInches(metres: Double): String {
        var feet = kotlin.math.floor(metres / 0.3048).toInt()
        var inches = Math.round((metres / 0.3048 - feet) * 12).toInt()
        if (inches == 12) { feet += 1; inches = 0 }
        return if (inches > 0) "$feet ft $inches in" else "$feet ft"
    }

    fun conversions(text: String, region: String? = java.util.Locale.getDefault().country): Conversions? {
        val t = text.replace('’', '\'')
        // "½" is a number too, if not a digit.
        if (t.none { it.isDigit() || it in fractions }) return null
        val uk = region.equals("GB", ignoreCase = true)
        val us = region.equals("US", ignoreCase = true)
        // A range or a size ("5-10 km", "10x20 cm") would be half answered.
        fun partOfMore(m: MatchResult) = partOfMore.containsMatchIn(t.substring(0, m.range.first))

        stripHeight.find(t)?.takeIf { !partOfMore(it) }?.let { m ->
            val feet = m.groupValues[1].toDoubleOrNull()
            val inches = m.groupValues[2].toDoubleOrNull()
            if (feet != null && inches != null && inches < 12) {
                val metres = feet * 0.3048 + inches * 0.0254
                return Conversions(m.value.trim(), listOf(stripNamed(metres * 100, "cm"), stripNamed(metres, "m")))
            }
        }
        // "it's 30 degrees": on the phone's own scale, shown on the other one.
        firstMatch("""\b(?:it'?s|it\s+is|feels\s+like|high\s+of|low\s+of|temp(?:erature)?\s+(?:is\s+|of\s+)?|was|hitting|around|about)\s+(-?\d{1,3}(?:\.\d+)?)\s*(?:°|degrees?|deg)\.?\s?$""", t)?.let { g ->
            val n = g[1]?.toDoubleOrNull() ?: return@let
            val fahrenheit = (region ?: "").uppercase() in setOf("US", "BS", "BZ", "KY", "PR", "PW")
            val result = if (fahrenheit) stripNamed((n - 32) * 5 / 9, "°C") else stripNamed(n * 9 / 5 + 32, "°F")
            return Conversions((g[0] ?: "").trim(), listOf(result))
        }
        // Asked for one unit ("10 km to miles", "5 lbs in kg"): that one.
        // Only the bare measure showed anything (2026-10-14).
        stripAsked.find(t)?.takeIf { !partOfMore(it) }?.let { a ->
            val n = amount(a.groupValues[1])?.takeIf { it.isFinite() } ?: return@let
            val from = stripNames[a.groupValues[2].lowercase()] ?: return@let
            val into = stripNames[a.groupValues[3].lowercase()] ?: return@let
            if (from == into) return@let
            val answer = when {
                from == "°C" && into == "°F" -> stripNamed(n * 9 / 5 + 32, "°F")
                from == "°F" && into == "°C" -> stripNamed((n - 32) * 5 / 9, "°C")
                else -> {
                    val sa = stripSize(from, uk)
                    val sb = stripSize(into, uk)
                    if (n > 0 && sa != null && sb != null && stripDimension(from) == stripDimension(into)) {
                        if (into == "foot" && n * sa < 3) feetInches(n * sa) else stripNamed(n * sa / sb, into)
                    } else null
                }
            }
            if (answer != null) return Conversions(a.value.trim(), listOf(answer))
        }
        val m = stripMeasure.find(t)?.takeIf { !partOfMore(it) } ?: return null
        val n = amount(m.groupValues[1])?.takeIf { it.isFinite() } ?: return null
        val name = m.groupValues[2].lowercase()
        val unit = stripNames[name] ?: return null
        // "4g", "5g": a network, not grams. "10 pounds" is money outside the US.
        if (unit == "g" && name == "g" && Regex("^[2-6]g", RegexOption.IGNORE_CASE).containsMatchIn(m.value)) return null
        if (name.startsWith("pound") && !us) return null
        // "2m" is metres (Arpit, 2026-10-06: "writing 2m doesnt show in inches
        // or other units"), but "$2m" is millions, "in 5m" minutes and "5M" money.
        // Only touching its number: "1 m" stays a minute or a million.
        if (name == "m" && (m.groupValues[2] != "m" ||
                !Regex("""[\d½⅓⅔¼¾⅛]m\.?\s?$""").containsMatchIn(m.value) ||
                Regex("""[$€£₹¥]\s*$|\bin\s*$|\d\s*(?:h|hrs?|hours?)\s*$""", RegexOption.IGNORE_CASE).containsMatchIn(t.substring(0, m.range.first)))) return null
        if (n < 0 && unit != "°C" && unit != "°F") return null

        val results: List<String> = when (unit) {
            "°C" -> listOf(stripNamed(n * 9 / 5 + 32, "°F"))
            "°F" -> listOf(stripNamed((n - 32) * 5 / 9, "°C"))
            else -> {
                val size = stripSize(unit, uk) ?: return null
                if (n <= 0) return null
                val base = n * size
                fun to(u: String) = stripNamed(base / (stripSize(u, uk) ?: 1.0), u)
                // Millilitres under a litre, grams under a kilo.
                fun metricVolume() = if (base < 1) to("ml") else to("litre")
                fun metricMass() = if (base < 1) to("g") else to("kg")
                // Two or three units people would want, the other system
                // first (Arpit, 2026-10-06: "i dont need only to 1 unit, need
                // it to 2-3 diff relevant units"). Smart.swift's twin.
                when (unit) {
                    "mm" -> listOf(to("inch"), to("cm"))
                    "cm" -> if (base < 0.3) listOf(to("inch"), to("mm"))
                        else if (base < 3) listOf(feetInches(base), to("inch"), to("m")) else listOf(to("foot"), to("m"))
                    "m" -> if (base < 3) listOf(feetInches(base), to("inch"), to("cm"))
                        else if (base < 1000) listOf(to("foot"), to("yard")) else listOf(to("mile"), to("foot"), to("km"))
                    "km" -> if (base < 10_000) listOf(to("mile"), to("foot"), to("m")) else listOf(to("mile"), to("m"))
                    "inch" -> if (base < 0.3) listOf(to("cm"), to("mm"), to("foot")) else listOf(to("cm"), to("m"), to("foot"))
                    "foot" -> if (n < 10) listOf(to("m"), to("cm"), to("inch")) else listOf(to("m"), to("yard"))
                    "yard" -> listOf(to("m"), to("foot"), to("cm"))
                    "mile" -> if (base < 2000) listOf(to("km"), to("m"), to("foot")) else listOf(to("km"), to("m"))
                    "g" -> listOf(to("oz"), to("lb"), to("kg"))
                    "kg" -> if (base < 10) listOf(to("lb"), to("oz"), to("g")) else listOf(to("lb"), to("stone"))
                    "oz" -> listOf(metricMass(), to("lb"))
                    "lb" -> if (base < 2.27) listOf(to("kg"), to("g"), to("oz"))
                        else if (base < 6.35) listOf(to("kg"), to("g")) else listOf(to("kg"), to("stone"))
                    "stone" -> listOf(to("kg"), to("lb"))
                    "ml" -> if (base < 0.00003) listOf(to("tsp"), to("tbsp"), to("fl oz")) else listOf(to("fl oz"), to("cup"), to("litre"))
                    "litre" -> if (uk) listOf(to("pint"), to("gallon"), to("fl oz")) else listOf(to("gallon"), to("cup"), to("fl oz"))
                    "tsp" -> listOf(to("ml"), to("tbsp"))
                    "tbsp" -> listOf(to("ml"), to("tsp"))
                    "fl oz" -> listOf(metricVolume(), to("cup"))
                    "cup" -> listOf(metricVolume(), to("fl oz"), to("tbsp"))
                    "pint" -> listOf(metricVolume(), to("cup"), to("fl oz"))
                    "quart" -> listOf(to("litre"), to("pint"), to("cup"))
                    "gallon" -> listOf(to("litre"), to("pint"), to("fl oz"))
                    "km/h" -> listOf(to("mph"), to("m/s"))
                    "mph" -> listOf(to("km/h"), to("m/s"))
                    "m/s", "knot" -> listOf(to("km/h"), to("mph"))
                    "sq ft" -> listOf(to("sq m"), to("sq yd"))
                    "sq m" -> listOf(to("sq ft"), to("sq yd"))
                    "sq yd" -> listOf(to("sq m"), to("sq ft"))
                    "acre" -> listOf(to("hectare"), to("sq m"), to("sq ft"))
                    "hectare" -> listOf(to("acre"), to("sq m"))
                    else -> return null
                }
            }
        }
        return if (results.isEmpty()) null else Conversions(m.value.trim(), results)
    }

    /** What a tap on a result adds after the measurement: " (25.4 cm)", or
     *  "(25.4 cm) " after a space already typed. */
    fun conversionInsert(result: String, before: String?): String {
        val last = before?.lastOrNull()
        return if (last == null || last == ' ' || last == '\n') "($result) " else " ($result)"
    }

    // MARK: a time in someone else's zone, in yours (Smart.swift twin)

    /** Zones people write after a time, with the place each means. EST, CST
     *  and IST say more than one place; the one most people mean wins, and
     *  the phone's region picks the other (China's CST, Ireland's and
     *  Israel's IST). ET/PT and the like follow summer time, as people mean
     *  them, and so do EST and PST. */
    private val zoneNames: Map<String, String> = mapOf(
        "et" to "America/New_York", "est" to "America/New_York", "edt" to "America/New_York", "eastern" to "America/New_York",
        "ct" to "America/Chicago", "cst" to "America/Chicago", "cdt" to "America/Chicago", "central" to "America/Chicago",
        "mt" to "America/Denver", "mst" to "America/Denver", "mdt" to "America/Denver", "mountain" to "America/Denver",
        "pt" to "America/Los_Angeles", "pst" to "America/Los_Angeles", "pdt" to "America/Los_Angeles", "pacific" to "America/Los_Angeles",
        "akst" to "America/Anchorage", "akdt" to "America/Anchorage", "hst" to "Pacific/Honolulu",
        "gmt" to "GMT", "utc" to "GMT", "bst" to "Europe/London", "uk time" to "Europe/London", "london time" to "Europe/London",
        "cet" to "Europe/Paris", "cest" to "Europe/Paris", "eet" to "Europe/Athens", "eest" to "Europe/Athens",
        "msk" to "Europe/Moscow", "ist" to "Asia/Kolkata", "india time" to "Asia/Kolkata", "pkt" to "Asia/Karachi",
        "gst" to "Asia/Dubai", "dubai time" to "Asia/Dubai", "ict" to "Asia/Bangkok", "wib" to "Asia/Jakarta",
        "sgt" to "Asia/Singapore", "hkt" to "Asia/Hong_Kong", "pht" to "Asia/Manila", "jst" to "Asia/Tokyo",
        "kst" to "Asia/Seoul", "aest" to "Australia/Sydney", "aedt" to "Australia/Sydney", "awst" to "Australia/Perth",
        "nzst" to "Pacific/Auckland", "nzdt" to "Pacific/Auckland", "sast" to "Africa/Johannesburg",
        "wat" to "Africa/Lagos", "eat" to "Africa/Nairobi", "brt" to "America/Sao_Paulo",
        "ny time" to "America/New_York", "new york time" to "America/New_York", "la time" to "America/Los_Angeles",
        "tokyo time" to "Asia/Tokyo", "singapore time" to "Asia/Singapore", "sydney time" to "Australia/Sydney",
        // Cities, as Raycast takes them ("5pm london"); none that is also a
        // word ("reading", "nice", "bath", "split").
        "london" to "Europe/London",
        "paris" to "Europe/Paris",
        "berlin" to "Europe/Berlin",
        "madrid" to "Europe/Madrid",
        "rome" to "Europe/Rome",
        "amsterdam" to "Europe/Amsterdam",
        "brussels" to "Europe/Brussels",
        "vienna" to "Europe/Vienna",
        "zurich" to "Europe/Zurich",
        "stockholm" to "Europe/Stockholm",
        "dublin" to "Europe/Dublin",
        "lisbon" to "Europe/Lisbon",
        "athens" to "Europe/Athens",
        "istanbul" to "Europe/Istanbul",
        "moscow" to "Europe/Moscow",
        "dubai" to "Asia/Dubai",
        "abu dhabi" to "Asia/Dubai",
        "riyadh" to "Asia/Riyadh",
        "doha" to "Asia/Qatar",
        "karachi" to "Asia/Karachi",
        "lahore" to "Asia/Karachi",
        "mumbai" to "Asia/Kolkata",
        "delhi" to "Asia/Kolkata",
        "new delhi" to "Asia/Kolkata",
        "bangalore" to "Asia/Kolkata",
        "bengaluru" to "Asia/Kolkata",
        "chennai" to "Asia/Kolkata",
        "hyderabad" to "Asia/Kolkata",
        "kolkata" to "Asia/Kolkata",
        "dhaka" to "Asia/Dhaka",
        "colombo" to "Asia/Colombo",
        "bangkok" to "Asia/Bangkok",
        "jakarta" to "Asia/Jakarta",
        "singapore" to "Asia/Singapore",
        "kuala lumpur" to "Asia/Kuala_Lumpur",
        "manila" to "Asia/Manila",
        "hong kong" to "Asia/Hong_Kong",
        "shanghai" to "Asia/Shanghai",
        "beijing" to "Asia/Shanghai",
        "taipei" to "Asia/Taipei",
        "seoul" to "Asia/Seoul",
        "tokyo" to "Asia/Tokyo",
        "sydney" to "Australia/Sydney",
        "melbourne" to "Australia/Melbourne",
        "brisbane" to "Australia/Brisbane",
        "perth" to "Australia/Perth",
        "auckland" to "Pacific/Auckland",
        "honolulu" to "Pacific/Honolulu",
        "los angeles" to "America/Los_Angeles",
        "la" to "America/Los_Angeles",
        "san francisco" to "America/Los_Angeles",
        "sf" to "America/Los_Angeles",
        "seattle" to "America/Los_Angeles",
        "vancouver" to "America/Vancouver",
        "denver" to "America/Denver",
        "phoenix" to "America/Phoenix",
        "chicago" to "America/Chicago",
        "dallas" to "America/Chicago",
        "houston" to "America/Chicago",
        "austin" to "America/Chicago",
        "toronto" to "America/Toronto",
        "montreal" to "America/Toronto",
        "new york" to "America/New_York",
        "nyc" to "America/New_York",
        "boston" to "America/New_York",
        "miami" to "America/New_York",
        "atlanta" to "America/New_York",
        "washington" to "America/New_York",
        "mexico city" to "America/Mexico_City",
        "sao paulo" to "America/Sao_Paulo",
        "são paulo" to "America/Sao_Paulo",
        "buenos aires" to "America/Argentina/Buenos_Aires",
        "lagos" to "Africa/Lagos",
        "nairobi" to "Africa/Nairobi",
        "cairo" to "Africa/Cairo",
        "johannesburg" to "Africa/Johannesburg",
        "cape town" to "Africa/Johannesburg",
        "tel aviv" to "Asia/Jerusalem",
    )

    /** How a zone is named in the result: the letters people know, or the
     *  offset ("GMT+6") for a zone without them. */
    private val zoneLetters: Map<String, Pair<String, String>> = mapOf(
        "America/New_York" to ("EST" to "EDT"), "America/Toronto" to ("EST" to "EDT"), "America/Chicago" to ("CST" to "CDT"),
        "America/Mexico_City" to ("CST" to "CST"), "America/Denver" to ("MST" to "MDT"), "America/Phoenix" to ("MST" to "MST"),
        "America/Los_Angeles" to ("PST" to "PDT"), "America/Vancouver" to ("PST" to "PDT"), "America/Anchorage" to ("AKST" to "AKDT"),
        "Pacific/Honolulu" to ("HST" to "HST"), "Europe/London" to ("GMT" to "BST"), "GMT" to ("GMT" to "GMT"), "UTC" to ("UTC" to "UTC"),
        "Europe/Paris" to ("CET" to "CEST"), "Europe/Berlin" to ("CET" to "CEST"), "Europe/Madrid" to ("CET" to "CEST"),
        "Europe/Rome" to ("CET" to "CEST"), "Europe/Amsterdam" to ("CET" to "CEST"), "Europe/Brussels" to ("CET" to "CEST"),
        "Europe/Vienna" to ("CET" to "CEST"), "Europe/Stockholm" to ("CET" to "CEST"), "Europe/Zurich" to ("CET" to "CEST"),
        "Europe/Warsaw" to ("CET" to "CEST"), "Europe/Athens" to ("EET" to "EEST"), "Europe/Helsinki" to ("EET" to "EEST"),
        "Europe/Moscow" to ("MSK" to "MSK"), "Asia/Dubai" to ("GST" to "GST"), "Asia/Karachi" to ("PKT" to "PKT"),
        "Asia/Kolkata" to ("IST" to "IST"), "Asia/Calcutta" to ("IST" to "IST"), "Asia/Bangkok" to ("ICT" to "ICT"),
        "Asia/Jakarta" to ("WIB" to "WIB"), "Asia/Singapore" to ("SGT" to "SGT"), "Asia/Hong_Kong" to ("HKT" to "HKT"),
        "Asia/Manila" to ("PHT" to "PHT"), "Asia/Tokyo" to ("JST" to "JST"), "Asia/Seoul" to ("KST" to "KST"),
        "Australia/Sydney" to ("AEST" to "AEDT"), "Australia/Melbourne" to ("AEST" to "AEDT"), "Australia/Perth" to ("AWST" to "AWST"),
        "Pacific/Auckland" to ("NZST" to "NZDT"), "Africa/Johannesburg" to ("SAST" to "SAST"), "Africa/Lagos" to ("WAT" to "WAT"),
        "Africa/Nairobi" to ("EAT" to "EAT"), "America/Sao_Paulo" to ("BRT" to "BRT"),
    )

    private fun zoneLabel(zone: java.time.ZoneId, at: java.time.Instant): String {
        zoneLetters[zone.id]?.let { (standard, summer) -> return if (zone.rules.isDaylightSavings(at)) summer else standard }
        val seconds = zone.rules.getOffset(at).totalSeconds
        val h = kotlin.math.abs(seconds) / 3600
        val m = kotlin.math.abs(seconds) % 3600 / 60
        return "GMT" + (if (seconds < 0) "-" else "+") + h + (if (m > 0) ":%02d".format(m) else "")
    }

    private val zoneTime: Regex by lazy {
        val names = zoneNames.keys.sortedByDescending { it.length }.joinToString("|") { Regex.escape(it) }
        Regex("""(?<![\d:.])(\d{1,2})(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)?\s*\(?(?:in\s+)?(""" + names + """)\)?\.?\s?$""",
            RegexOption.IGNORE_CASE)
    }

    /** A list said in one breath: "need: milk, eggs, bread" → "• List" and
     *  "1. List", one item a line in place of the line. Three items at
     *  least, each short (iOS 10-07). */
    fun listMaker(text: String): Conversions? {
        val line = text.substringAfterLast('\n')
        val g = firstMatch("""^\s*((?:(?:need|needs|todo|to do|to-do|list|buy|get|pack|bring|grocer(?:y|ies)|shopping|tasks?|steps?|agenda|plan|order|ingredients|items|things|remember|checklist)\b[^:\n]{0,24}:\s*)|(?:need|buy|get|pack|bring|grab|remember)\s+)(.{5,200})$""", line)
            ?: return null
        val lead = g[1] ?: return null
        val rest = g[2] ?: return null
        val items = rest.replace(Regex("""\s+and\s+""", RegexOption.IGNORE_CASE), ",")
            .split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (items.size < 3 || items.any { it.length > 40 || it.contains(':') }) return null
        val head = if (lead.contains(':')) lead.trim() + "\n" else ""
        val bullets = head + items.joinToString("\n") { "• $it" }
        val numbered = head + items.withIndex().joinToString("\n") { "${it.index + 1}. ${it.value}" }
        return Conversions((g[0] ?: "").trim(), listOf("• List", "1. List"), listOf(bullets, numbered),
                           listOf(Insertion.REPLACE, Insertion.REPLACE))
    }

    private val pollLeads = setOf("do", "does", "did", "are", "is", "will", "would", "can", "could", "should", "shall",
        "you", "u", "we", "i", "they", "it", "that", "this", "want", "wanna", "prefer", "like",
        "rather", "going", "go", "for", "to", "get", "have", "eat", "order", "the", "a", "an",
        "some", "which", "what", "where", "when", "who", "with", "at", "in", "on", "so", "and",
        "guys", "ppl", "everyone", "tonight", "today", "tomorrow", "pick", "choose", "vote")
    private val pollOff = setOf("not", "no", "nah", "what", "something", "whatever", "anything", "nothing", "else", "so", "later")

    /** Three to six options in a question ("pizza, burgers or pasta?") →
     *  "Make it a poll": the question kept, the options on numbered lines,
     *  "reply with a number" under it. Two options are a question. */
    fun pollMaker(text: String): Conversions? {
        val line = text.substringAfterLast('\n')
        val g = firstMatch("""([A-Za-z0-9][A-Za-z0-9 ']{0,28}(?:,\s*[A-Za-z0-9][A-Za-z0-9 ']{0,24}){0,4})\s*,?\s+or\s+([A-Za-z0-9][A-Za-z0-9 ']{0,24}?)\s*\?\s?$""", line)
            ?: return null
        val options = (g[1] ?: return null).split(",").map { it.trim() }.toMutableList()
        val last = g[2] ?: return null
        val words = options[0].split(" ").filter { it.isNotEmpty() }.toMutableList()
        while (words.size > 1 && words[0].lowercase() in pollLeads) words.removeAt(0)
        options[0] = words.joinToString(" ")
        options += last.trim()
        if (options.size !in 3..6) return null
        if (options.any { it.isEmpty() || it.length > 25 || it.lowercase() in pollOff || it.none { c -> c.isLetterOrDigit() } }) return null
        if (options.map { it.lowercase() }.toSet().size != options.size) return null
        val keycaps = listOf("1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣")
        val question = (g[0] ?: "").trim()
        val poll = question + "\n" + options.withIndex().joinToString("\n") { "${keycaps[it.index]} ${it.value}" } + "\nreply with a number"
        return Conversions(question, listOf("Make it a poll"), listOf(poll), listOf(Insertion.REPLACE))
    }

    private val notAPlace = setOf("the", "what", "same", "this", "that", "my", "your", "our", "their", "his", "her", "free", "long", "next")

    /** The time now somewhere else: "what time is it in tokyo", "tokyo
     *  time" → "7:45 PM Tokyo" (the day too when it isn't today there).
     *  Nothing for the phone's own zone (iOS 10-07). */
    fun cityTime(text: String, now: java.time.Instant = java.time.Instant.now(),
                 here: java.time.ZoneId = java.time.ZoneId.systemDefault(),
                 region: String? = java.util.Locale.getDefault().country): Conversions? {
        val name = firstMatch("""\btime\s+(?:is\s+it\s+|now\s+|is\s+)?in\s+([a-z][a-z .]{1,30}?)\??\s?$""", text)?.get(1)
            ?: firstMatch("""\b([a-z]{3,20}(?:\s+[a-z]{3,20})?)\s+time(?:\s+now)?\??\s?$""", text)?.get(1)
            ?: return null
        val key = name.lowercase().trim()
        // "3pm london time in new york" converts 3pm; it isn't asking the time now.
        if (Regex("""\b\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.)""", RegexOption.IGNORE_CASE).containsMatchIn(text)) return null
        if (key in notAPlace) return null
        val r = region?.uppercase()
        var id = zoneNames[key] ?: zoneNames["$key time"] ?: ""
        if (key == "cst" && r == "CN") id = "Asia/Shanghai"
        if (key == "ist" && r == "IE") id = "Europe/Dublin"
        if (key == "ist" && r == "IL") id = "Asia/Jerusalem"
        val there = runCatching { java.time.ZoneId.of(id) }.getOrNull() ?: return null
        if (there.rules.getOffset(now) == here.rules.getOffset(now)) return null
        val at = now.atZone(there)
        var clock = java.time.format.DateTimeFormatter.ofPattern(if (at.minute == 0) "h a" else "h:mm a", java.util.Locale.US)
            .format(at).replace('\u202F', ' ')
        if (at.dayOfMonth != now.atZone(here).dayOfMonth) {
            clock = java.time.format.DateTimeFormatter.ofPattern("EEE", java.util.Locale.US).format(at) + " " + clock
        }
        val label = if (key.length <= 4 && zoneNames[key] != null && !key.contains(' ')) key.uppercase()
            else key.split(" ").joinToString(" ") { w -> w.replaceFirstChar { it.uppercase() } }
        val source = firstMatch("""\S.*$""", text)?.get(0)?.trim() ?: text.trim()
        return Conversions(source, listOf("$clock $label"))
    }

    /** The wait till a clock time: "how long until 5pm" → "in 2h 15m"; a
     *  time gone by today is tomorrow's (iOS 10-07). */
    fun untilTime(text: String, now: java.time.Instant = java.time.Instant.now(),
                  here: java.time.ZoneId = java.time.ZoneId.systemDefault()): Conversions? {
        val g = firstMatch("""\b(?:until|till|til|'til)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\??\s?$""", text)
            ?: return null
        var hour = g[1]?.toIntOrNull() ?: return null
        val minute = g[2]?.toIntOrNull() ?: 0
        val half = g[3]?.lowercase()?.replace(".", "")
        if (half != null) {
            if (hour !in 1..12) return null
            if (half == "pm" && hour < 12) hour += 12
            if (half == "am" && hour == 12) hour = 0
        } else if (g[2] == null || hour !in 0..23 || minute >= 60) return null
        val today = now.atZone(here)
        var whenAt = today.toLocalDate().atTime(hour, minute).atZone(here)
        if (!whenAt.toInstant().isAfter(now)) whenAt = whenAt.plusDays(1)
        val minutes = Math.round(java.time.Duration.between(now, whenAt.toInstant()).seconds / 60.0).toInt()
        if (minutes <= 0) return null
        val wait = if (minutes >= 60) (if (minutes % 60 == 0) "${minutes / 60}h" else "${minutes / 60}h ${minutes % 60}m") else "${minutes}m"
        return Conversions((g[0] ?: "").trim(), listOf("in $wait"))
    }

    /** A time in someone else's zone the message ends on, in the phone's own
     *  (Raycast's "5pm PT in London", in the strip): "call at 3pm EST" →
     *  "Sun 12:30 AM IST" in India. A time needs am/pm or minutes ("3 est"
     *  is not one); nothing when the zone is the phone's own. The day shows
     *  when it is not the same day there. shared/zones/strip-cases.json. */
    fun zoneTimes(text: String, now: java.time.Instant = java.time.Instant.now(),
                  here: java.time.ZoneId = java.time.ZoneId.systemDefault(),
                  region: String? = java.util.Locale.getDefault().country): Conversions? {
        if (text.none { it.isDigit() }) return null
        val m = zoneTime.find(text) ?: return null
        var hour = m.groupValues[1].toIntOrNull() ?: return null
        val minuteText = m.groups[2]?.value
        val minute = minuteText?.toIntOrNull() ?: 0
        val half = m.groups[3]?.value?.lowercase()?.replace(".", "")
        if (half != null) {
            if (hour !in 1..12) return null
            if (half == "pm" && hour < 12) hour += 12
            if (half == "am" && hour == 12) hour = 0
        } else {
            // "3 est" is not a time; "15:00 GMT" and "9:30 IST" are.
            if (minuteText == null || hour !in 0..23) return null
        }
        val typed = m.groupValues[4]
        val name = typed.lowercase()
        // A two-letter zone in small letters only after am/pm ("9am pt"):
        // "9:30 pt" may be a part or a point.
        if (name.length == 2 && half == null && typed != typed.uppercase()) return null
        val r = region?.uppercase()
        var id = zoneNames[name] ?: return null
        if (name == "cst" && r == "CN") id = "Asia/Shanghai"
        if (name == "ist" && r == "IE") id = "Europe/Dublin"
        if (name == "ist" && r == "IL") id = "Asia/Jerusalem"
        val there = runCatching { java.time.ZoneId.of(id) }.getOrNull() ?: return null
        // That time today, where it was said.
        val said = java.time.ZonedDateTime.of(now.atZone(there).toLocalDate(), java.time.LocalTime.of(hour, minute), there)
        val instant = said.toInstant()
        if (there.rules.getOffset(instant) == here.rules.getOffset(instant)) return null
        val mine = instant.atZone(here)
        var clock = java.time.format.DateTimeFormatter.ofPattern(if (mine.minute == 0) "h a" else "h:mm a", java.util.Locale.US)
            .format(mine).replace(' ', ' ')
        if (mine.toLocalDate() != said.toLocalDate()) {
            clock = java.time.format.DateTimeFormatter.ofPattern("EEE", java.util.Locale.US).format(mine) + " " + clock
        }
        return Conversions(m.value.trim(), listOf("$clock ${zoneLabel(here, instant)}"))
    }

    // MARK: bills, arrivals and dates, worked out as they are typed (Smart.swift twin)

    /** Everything the strip works out on the phone from how the message
     *  ends, most particular first: a shortcut, a face, a measurement or a
     *  recipe's, a time in another zone or on the clock, a pace, a bill, a
     *  price or a loan, when someone will be there, a date or a holiday,
     *  numbers in other forms, links, and a coin or a pick. One chip per
     *  result; a tap adds it in brackets unless the answer says otherwise.
     *  shared/quick/strip-cases.json. */
    fun quickAnswer(text: String, now: java.time.Instant = java.time.Instant.now(),
                    here: java.time.ZoneId = java.time.ZoneId.systemDefault(),
                    region: String? = java.util.Locale.getDefault().country): Conversions? {
        if (text.length > 400) return null
        // A link's digits are its address: only its trackers are worth a chip.
        if (endsInLink(text)) return cleanLink(text)
        return shortcut(text, now, here, region)
            ?: face(text)
            ?: symbol(text)
            ?: slangMeaning(text)
            ?: Phrases.phraseIn(text)
            ?: writingHelp(text)
            ?: mathsSymbol(text)
            ?: solveEquation(text)
            ?: cookingSafety(text)
            ?: substitute(text)
            ?: calories(text)
            ?: clockChange(text, now, here, region)
            ?: outOfOffice(text, now, here, region)
            ?: emergencyNumber(text, region)
            ?: uuid(text)
            ?: base64(text)
            ?: roman(text)
            ?: listMaker(text)
            ?: pollMaker(text)
            ?: unitPrice(text)
            ?: degreesAsked(text)
            ?: duration(text)
            ?: kitchenVolume(text)
            ?: bmi(text)
            ?: feetInches(text)
            ?: driveTime(text)
            ?: conversions(text, region)
            ?: cooking(text, region)
            ?: fuel(text, region)
            ?: zoneTimes(text, now, here, region)
            ?: cityTime(text, now, here, region)
            ?: SunAnswer.answer(text, now, here)
            ?: timeDifference(text, now, here, region)
            ?: untilTime(text, now, here)
            ?: clockMaths(text)
            ?: everyHours(text)
            ?: pace(text)
            ?: stackedDiscount(text)
            ?: buyGetFree(text)
            ?: billMath(text)
            ?: taxInside(text, region)
            ?: change(text)
            ?: wasNow(text)
            ?: testScore(text, region)
            ?: averageOf(text)
            ?: monthlySavings(text)
            ?: heartRate(text)
            ?: ratio(text)
            ?: payRate(text)
            ?: loan(text)
            ?: arrival(text, now, here)
            ?: backIn(text, now, here)
            ?: holiday(text, now, here, region)
            ?: dateInWords(text, now, here, region)
            ?: workingDays(text, now, here, region)
            ?: weekNumber(text, now, here, region)
            ?: age(text, now, here, region)
            ?: dayOfWeek(text, region)
            ?: bases(text)
            ?: colours(text)
            ?: tracking(text)
            ?: flight(text)
            ?: phone(text, region)
            ?: unixTime(text, here, region)
            ?: inWords(text, region)
            ?: download(text)
            ?: mapLink(text)
            ?: luckAnswer(text)
            ?: bigNumber(text, region)
    }

    /** Patterns are built once: the strip asks on every key. */
    private val patternCache = java.util.concurrent.ConcurrentHashMap<String, Regex>()

    private fun firstMatch(pattern: String, text: String): List<String?>? {
        val re = patternCache.getOrPut(pattern) { Regex(pattern, RegexOption.IGNORE_CASE) }
        val m = re.find(text) ?: return null
        return m.groups.map { it?.value }
    }

    private const val SYM = """([$€£₹¥])?"""
    private const val AMT = """(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"""
    private const val PCT = """(\d+(?:\.\d+)?)\s*%"""
    private const val END = """[.?!]?\s?$"""

    /** Money as it is written back: the sign typed, cents only when there
     *  are some ("$30", "$33.33"), none for yen. */
    fun billMoney(n: Double, symbol: String): String {
        val cents = Math.round(n * 100) / 100.0
        val whole = symbol == "¥" || cents == kotlin.math.round(cents)
        val f = java.text.DecimalFormat(if (whole) "#,##0" else "#,##0.00", java.text.DecimalFormatSymbols(java.util.Locale.US))
            .apply { roundingMode = java.math.RoundingMode.HALF_UP }
        return symbol + f.format(cents)
    }

    private fun number(s: String?): Double? = s?.replace(",", "")?.toDoubleOrNull()

    /** "split 120 4 ways" → 30 each; "15% tip on 80" → 12 tip, 92 total;
     *  "20% off 80" → 64, save 16; "$80 + 8.875% tax" → $87.10 total,
     *  $7.10 tax. Each needs its word (split, tip, off, tax), so "50% sure"
     *  and "24/7" stay what they are. */
    fun billMath(text: String): Conversions? {
        val ways = """\s*(?:ways?|people|persons|of us|friends)?"""
        val splits = listOf(
            """\bsplit\s+(?:the\s+)?(?:bill\s+(?:of\s+)?|[a-z]{2,12}\s+(?:of\s+)?)?$SYM\s*$AMT\s+(?:in\s+|into\s+|between\s+|among\s+|by\s+|with\s+)?(\d{1,2})$ways$END""",
            """$SYM\s*$AMT\s+(?:split|divided)\s+(?:in\s+|into\s+|between\s+|among\s+|by\s+)?(\d{1,2})$ways$END""",
            """$SYM\s*$AMT\s+(?:between|among)\s+(\d{1,2})\s+(?:people|persons|of us|friends)$END""",
        )
        for (p in splits) {
            val g = firstMatch(p, text) ?: continue
            val bill = number(g[2]) ?: continue
            val n = number(g[3]) ?: continue
            if (n < 2 || n > 50) continue
            return Conversions(g[0]!!.trim(), listOf("${billMoney(bill / n, g[1] ?: "")} each"))
        }
        // (percent, sign, amount) or (sign, amount, percent)
        fun pick(g: List<String?>, percentFirst: Boolean): Triple<Double, String, Double>? {
            val p = number(if (percentFirst) g[1] else g[3]) ?: return null
            val s = (if (percentFirst) g[2] else g[1]) ?: ""
            val a = number(if (percentFirst) g[3] else g[2]) ?: return null
            return if (p > 0 && p <= 100) Triple(p, s, a) else null
        }
        val tips = listOf(
            """\b$PCT\s*tip\s*(?:on|for|of|to)?\s*$SYM\s*$AMT$END""" to true,
            """\btip\s+(?:of\s+)?$PCT\s*(?:on|for)\s*$SYM\s*$AMT$END""" to true,
            """\btip\s+(?:of\s+)?(\d{1,2}(?:\.\d+)?)\s*(?:on|for)\s*$SYM\s*$AMT$END""" to true,
            """$SYM\s*$AMT\s*(?:\+|plus|with|and)\s*$PCT\s*tip$END""" to false,
        )
        for ((p, first) in tips) {
            val g = firstMatch(p, text) ?: continue
            val (percent, s, bill) = pick(g, first) ?: continue
            val tip = bill * percent / 100
            return Conversions(g[0]!!.trim(), listOf("${billMoney(tip, s)} tip", "${billMoney(bill + tip, s)} total"))
        }
        // "85 minus 15%", "120 plus 8%" (iOS 10-14).
        firstMatch("""(?<![\w.,])$SYM\s*$AMT\s+(minus|less|plus)\s+$PCT$END""", text)?.let { g ->
            val base = number(g[2]) ?: return@let
            val p = number(g[4])?.takeIf { it > 0 && it < 1000 } ?: return@let
            val minus = (g[3] ?: "").lowercase() != "plus"
            val v = if (minus) base * (1 - p / 100) else base * (1 + p / 100)
            return Conversions(g[0]!!.trim(), listOf(billMoney(v, g[1] ?: "")))
        }
        val offs = listOf(
            """\b$PCT\s*off\s*(?:of\s+)?$SYM\s*$AMT$END""" to true,
            """$SYM\s*$AMT\s*(?:with\s+|at\s+|less\s+|minus\s+|-\s*)?$PCT\s*off$END""" to false,
        )
        for ((p, first) in offs) {
            val g = firstMatch(p, text) ?: continue
            val (percent, s, price) = pick(g, first) ?: continue
            val saved = price * percent / 100
            return Conversions(g[0]!!.trim(), listOf(billMoney(price - saved, s), "save ${billMoney(saved, s)}"))
        }
        val taxes = listOf(
            """$SYM\s*$AMT\s*(?:\+|plus|with|and)\s*$PCT\s*(?:sales\s+)?(?:tax|gst|vat)$END""" to false,
            """\b$PCT\s*(?:sales\s+)?(?:tax|gst|vat)\s*(?:on|for|of)\s*$SYM\s*$AMT$END""" to true,
        )
        for ((p, first) in taxes) {
            val g = firstMatch(p, text) ?: continue
            val (percent, s, price) = pick(g, first) ?: continue
            val tax = price * percent / 100
            return Conversions(g[0]!!.trim(), listOf("${billMoney(price + tax, s)} total", "${billMoney(tax, s)} tax"))
        }
        return null
    }

    private fun clockAt(at: java.time.ZonedDateTime, now: java.time.ZonedDateTime): String {
        var text = java.time.format.DateTimeFormatter.ofPattern(if (at.minute == 0) "h a" else "h:mm a", java.util.Locale.US)
            .format(at).replace(' ', ' ')
        if (at.toLocalDate() != now.toLocalDate()) {
            text = java.time.format.DateTimeFormatter.ofPattern("EEE", java.util.Locale.US).format(at) + " " + text
        }
        return text
    }

    private val smallNumbers = mapOf(
        "a" to 1.0, "an" to 1.0, "one" to 1.0, "two" to 2.0, "three" to 3.0, "four" to 4.0, "five" to 5.0, "six" to 6.0,
        "seven" to 7.0, "eight" to 8.0, "nine" to 9.0, "ten" to 10.0, "eleven" to 11.0, "twelve" to 12.0, "fifteen" to 15.0,
        "twenty" to 20.0, "thirty" to 30.0, "forty" to 40.0, "forty five" to 45.0, "fifty" to 50.0, "half an" to 0.5,
        "a couple of" to 2.0, "couple of" to 2.0,
    )
    private const val COUNT_WORD = """(\d+(?:\.\d+)?|a couple of|couple of|half an|forty five|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty)"""

    /** "there in 20 mins" → the clock then; "back in 2 hrs"; "eta 45 min".
     *  Under ten minutes only when the words say someone is coming. "movie is
     *  145 mins" → 2 h 25 min (from 90 minutes up). */
    fun arrival(text: String, now: java.time.Instant, here: java.time.ZoneId): Conversions? {
        val unit = """(mins?|minutes?|hrs?|hours?)"""
        // "15 min from now", "whats 2 hours from now", "in 2 hours what time" (iOS 10-14).
        (firstMatch("""\b(?:what'?s\s+|whats\s+|what\s+time\s+is\s+it\s+)?(\d{1,3})\s*(mins?|minutes?|hrs?|hours?)\s+from\s+now\??$END""", text)
            ?: firstMatch("""\bin\s+(\d{1,3})\s*(mins?|minutes?|hrs?|hours?)\s*,?\s*what\s+time(?:\s+(?:is\s+it|will\s+it\s+be))?\??$END""", text))?.let { g ->
            val n = g[1]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return@let
            val u = g[2] ?: return@let
            val mins = if (u.lowercase().startsWith("h")) n * 60 else n
            if (mins > 24 * 60) return null
            val start = now.atZone(here)
            return Conversions(g[0]!!.trim(), listOf(clockAt(start.plusSeconds(Math.round(mins * 60)), start)))
        }
        val coming = Regex("""\b(?:eta|back|there|home|ready|leav(?:e|ing)|land(?:s|ing)?|reach(?:ing)?|arriv(?:e|ing)|be\s+(?:there|back|home|ready|free|done)|see\s+(?:you|u)|done|free|out|wait)\b""",
            RegexOption.IGNORE_CASE)
        firstMatch("""\b(?:in|within|eta)\s*:?\s*(?:about\s+|around\s+|like\s+|~\s*)?$COUNT_WORD\s*$unit$END""", text)?.let { g ->
            val n = g[1]?.let { it.toDoubleOrNull() ?: smallNumbers[it.lowercase()] } ?: return@let
            val mins = if (g[2]!!.lowercase().startsWith("h")) n * 60 else n
            if (mins <= 0 || mins > 12 * 60) return@let
            if (mins < 10 && !coming.containsMatchIn(text)) return null
            val start = now.atZone(here)
            val at = start.plusSeconds(Math.round(mins * 60))
            return Conversions(g[0]!!.trim(), listOf(clockAt(at, start)))
        }
        firstMatch("""(?<![\d.])(\d{2,4})\s*(mins?|minutes?)$END""", text)?.let { g ->
            if (Regex("""\b(?:in|within)\s+\d+\s*(?:mins?|minutes?)\.?\s?$""", RegexOption.IGNORE_CASE).containsMatchIn(text)) return@let
            val n = number(g[1]) ?: return@let
            if (n < 90 || n >= 24 * 60) return@let
            val h = n.toInt() / 60
            val m = n.toInt() % 60
            return Conversions(g[0]!!.trim(), listOf(if (m == 0) "$h h" else "$h h $m min"))
        }
        return null
    }

    private val weekdays = listOf(
        "sunday" to 7, "sun" to 7, "monday" to 1, "mon" to 1, "tuesday" to 2, "tues" to 2, "tue" to 2,
        "wednesday" to 3, "wed" to 3, "thursday" to 4, "thurs" to 4, "thur" to 4, "thu" to 4,
        "friday" to 5, "fri" to 5, "saturday" to 6, "sat" to 6,
    )
    private val datedMonths = listOf(
        "january" to 1, "jan" to 1, "february" to 2, "feb" to 2, "march" to 3, "mar" to 3, "april" to 4, "apr" to 4,
        "may" to 5, "june" to 6, "jun" to 6, "july" to 7, "jul" to 7, "august" to 8, "aug" to 8,
        "september" to 9, "sept" to 9, "sep" to 9, "october" to 10, "oct" to 10, "november" to 11, "nov" to 11,
        "december" to 12, "dec" to 12,
    )

    /** A day as people write dates: "Fri 9 Oct", or "Fri, Oct 9" in the US;
     *  the year when it is not this one. */
    private fun dayName(date: java.time.LocalDate, today: java.time.LocalDate, region: String?): String {
        val us = region.equals("US", ignoreCase = true)
        var text = java.time.format.DateTimeFormatter.ofPattern(if (us) "EEE, MMM d" else "EEE d MMM", java.util.Locale.US).format(date)
        if (date.year != today.year) text += (if (us) ", " else " ") + date.year
        return text
    }

    /** "next friday" → Fri 9 Oct (and Fri 16 Oct when the coming Friday is
     *  still this week); "this friday"; "in 3 weeks"; "day after tomorrow";
     *  "the 14th"; "oct 14" or "14 october" → Wed 14 Oct · in 11 days (how
     *  far off, from a week away). Never a lone weekday, "today" or
     *  "tomorrow". */
    fun dateInWords(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val today = now.atZone(here).toLocalDate()
        fun say(g: List<String?>, dates: List<java.time.LocalDate>, counted: Boolean = false): Conversions {
            val results = dates.map { dayName(it, today, region) }.toMutableList()
            val first = dates.firstOrNull()
            if (counted && first != null && java.time.temporal.ChronoUnit.DAYS.between(today, first) >= 7) {
                results += countdown(first, today)
            }
            return Conversions(g[0]!!.trim(), results)
        }
        val dayNames = weekdays.joinToString("|") { it.first }
        firstMatch("""\b(next|this|coming)\s+($dayNames)$END""", text)?.let { g ->
            val which = g[1]!!.lowercase()
            val target = weekdays.first { it.first == g[2]!!.lowercase() }.second
            var ahead = (target - today.dayOfWeek.value + 7) % 7
            if (which == "next" && ahead == 0) ahead = 7
            val coming = today.plusDays(ahead.toLong())
            val week = java.time.temporal.WeekFields.ISO
            val sameWeek = coming.get(week.weekOfWeekBasedYear()) == today.get(week.weekOfWeekBasedYear()) &&
                coming.get(week.weekBasedYear()) == today.get(week.weekBasedYear())
            return if (which == "next" && sameWeek) say(g, listOf(coming, coming.plusDays(7))) else say(g, listOf(coming))
        }
        firstMatch("""\bin\s+$COUNT_WORD\s*(days?|weeks?|wks?|months?)$END""", text)?.let { g ->
            val n = (g[1]!!.toDoubleOrNull() ?: smallNumbers[g[1]!!.lowercase()] ?: 0.0).toInt()
            val u = g[2]!!.lowercase()
            val most = if (u.startsWith("d")) 365 else if (u.startsWith("w")) 52 else 24
            if (n < 1 || n > most) return null
            val date = when {
                u.startsWith("d") -> today.plusDays(n.toLong())
                u.startsWith("w") -> today.plusDays(n * 7L)
                else -> today.plusMonths(n.toLong())
            }
            return say(g, listOf(date))
        }
        firstMatch("""\bday\s+after\s+tomorrow$END""", text)?.let { g -> return say(g, listOf(today.plusDays(2))) }
        // "the 14th", "on the 3rd", "by the 21st": the next such day.
        firstMatch("""\b(?:(?:on|by|till|until|before|after|from)\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)$END""", text)?.let { g ->
            val d = g[1]!!.toInt()
            if (d < 1 || d > 31) return null
            for (add in 0L..2L) {
                val month = today.withDayOfMonth(1).plusMonths(add)
                if (d > month.lengthOfMonth()) continue
                val date = month.withDayOfMonth(d)
                if (!date.isBefore(today)) return say(g, listOf(date), counted = true)
            }
            return null
        }
        // "oct 14", "october 14th", "14 oct", "14th of october": that day's weekday.
        val months = datedMonths.joinToString("|") { it.first }
        val monthFirst = firstMatch("""\b($months)\.?\s+(\d{1,2})(?:st|nd|rd|th)?$END""", text)
        val dayFirst = if (monthFirst == null) firstMatch("""\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?($months)$END""", text) else null
        val g = monthFirst ?: dayFirst ?: return null
        val mName = if (monthFirst != null) g[1] else g[2]
        val dText = if (monthFirst != null) g[2] else g[1]
        val m = datedMonths.firstOrNull { it.first == mName?.lowercase() }?.second ?: return null
        val d = dText?.toIntOrNull() ?: return null
        if (d < 1 || d > 31) return null
        // "may 5" could be "you may 5…": May only with a word before it that dates.
        if (m == 5 && monthFirst != null && !Regex("""\b(?:on|by|till|until|before|after|from|since|in)\s+may\s+\d""",
                RegexOption.IGNORE_CASE).containsMatchIn(text)) return null
        if (d > java.time.YearMonth.of(today.year, m).lengthOfMonth()) return null
        var date = java.time.LocalDate.of(today.year, m, d)
        if (date.isBefore(today)) {
            if (d > java.time.YearMonth.of(today.year + 1, m).lengthOfMonth()) return null
            date = java.time.LocalDate.of(today.year + 1, m, d)
        }
        return say(g, listOf(date), counted = true)
    }

    // MARK: shortcuts, numbers, colours, parcels, flights and phones (Smart.swift twin)

    /** The shortcuts the keyboard knows itself; the person's own shorthand
     *  of the same name wins (the keyboard leaves the chip out then). */
    val builtInShortcuts: Set<String> by lazy {
        setOf(";date", ";today", ";time", ";now", ";tmrw", ";tomorrow", ";yday", ";yesterday", ";iso") + faces.keys.map { ";$it" }
    }

    /** ";date" → Sat 3 Oct 2026, ";time" → 1:15 AM, ";now", ";tmrw",
     *  ";yday", ";iso": typed in place of the shortcut. */
    fun shortcut(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val g = firstMatch("""(?:^|\s)(;(?:date|today|time|now|tmrw|tomorrow|yday|yesterday|iso))\s?$""", text) ?: return null
        val token = g[1]?.lowercase() ?: return null
        val at = now.atZone(here)
        val us = region.equals("US", ignoreCase = true)
        fun day(d: java.time.ZonedDateTime, year: Boolean): String = java.time.format.DateTimeFormatter.ofPattern(
            if (us) (if (year) "EEE, MMM d, yyyy" else "EEE, MMM d") else (if (year) "EEE d MMM yyyy" else "EEE d MMM"),
            java.util.Locale.US).format(d)
        fun time(d: java.time.ZonedDateTime): String =
            java.time.format.DateTimeFormatter.ofPattern("h:mm a", java.util.Locale.US).format(d).replace(' ', ' ')
        val out = when (token) {
            ";date", ";today" -> day(at, true)
            ";time" -> time(at)
            ";now" -> day(at, false) + ", " + time(at)
            ";tmrw", ";tomorrow" -> day(at.plusDays(1), false)
            ";yday", ";yesterday" -> day(at.minusDays(1), false)
            else -> java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd", java.util.Locale.US).format(at)
        }
        return Conversions(token, listOf(out), hows = listOf(Insertion.REPLACE))
    }

    fun roman(n: Long): String? {
        if (n < 1 || n > 3999) return null
        val table = listOf(1000 to "M", 900 to "CM", 500 to "D", 400 to "CD", 100 to "C", 90 to "XC",
            50 to "L", 40 to "XL", 10 to "X", 9 to "IX", 5 to "V", 4 to "IV", 1 to "I")
        var left = n.toInt()
        val out = StringBuilder()
        for ((value, letters) in table) while (left >= value) { out.append(letters); left -= value }
        return out.toString()
    }

    /** "0xFF" → 255 · 0b11111111; "0b1010" → 10 · 0xA; "255 in hex" → 0xFF;
     *  "10 in binary" → 0b1010; "1010 in decimal" or "binary 1010" → 10;
     *  "hex ff" → 255; "2026 in roman" → MMXXVI. */
    fun bases(text: String): Conversions? {
        fun binary(n: Long): String? = if (n < (1L shl 32)) "0b" + java.lang.Long.toBinaryString(n) else null
        fun hex(n: Long) = "0x" + java.lang.Long.toHexString(n).uppercase()
        firstMatch("""(?<![\w])0x([0-9a-f]{1,15})$END""", text)?.let { g ->
            val n = g[1]?.toLongOrNull(16) ?: return@let
            return Conversions(g[0]!!.trim(), listOfNotNull(n.toString(), binary(n)))
        }
        firstMatch("""(?<![\w])0b([01]{1,62})$END""", text)?.let { g ->
            val n = g[1]?.toLongOrNull(2) ?: return@let
            return Conversions(g[0]!!.trim(), listOf(n.toString(), hex(n)))
        }
        firstMatch("""\b(\d{1,18})\s+(?:in|to|as|into)\s+(hex|hexadecimal|binary|bin|octal|oct|roman|roman numerals?)$END""", text)?.let { g ->
            val n = g[1]?.toLongOrNull() ?: return@let
            val to = g[2]!!.lowercase()
            val out = when {
                to.startsWith("hex") -> hex(n)
                to.startsWith("bin") -> binary(n)
                to.startsWith("oct") -> "0o" + java.lang.Long.toOctalString(n)
                else -> roman(n)
            } ?: return null
            return Conversions(g[0]!!.trim(), listOf(out))
        }
        (firstMatch("""\b([01]{2,62})\s+(?:in|to|as|into)\s+(?:decimal|dec|denary|base 10)$END""", text)
            ?: firstMatch("""\bbinary\s+([01]{2,62})$END""", text))?.let { g ->
            val n = g[1]?.toLongOrNull(2) ?: return@let
            return Conversions(g[0]!!.trim(), listOf(n.toString()))
        }
        firstMatch("""\bhex\s+([0-9a-f]{1,15})$END""", text)?.let { g ->
            val n = g[1]?.toLongOrNull(16) ?: return@let
            return Conversions(g[0]!!.trim(), listOf(n.toString()))
        }
        return null
    }

    private fun hsl(r0: Double, g0: Double, b0: Double): String {
        val r = r0 / 255; val g = g0 / 255; val b = b0 / 255
        val most = maxOf(r, g, b); val least = minOf(r, g, b)
        val l = (most + least) / 2
        var h = 0.0; var s = 0.0
        if (most != least) {
            val d = most - least
            s = if (l > 0.5) d / (2 - most - least) else d / (most + least)
            h = when (most) {
                r -> (g - b) / d + (if (g < b) 6 else 0)
                g -> (b - r) / d + 2
                else -> (r - g) / d + 4
            }
            h *= 60
        }
        return "hsl(${Math.round(h).toInt() % 360}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)"
    }

    /** "#ff6363" → rgb(255, 99, 99) · hsl(0, 100%, 69%); "rgb(255, 99, 99)"
     *  → #FF6363 · hsl(0, 100%, 69%). A hashtag that is a word (#bad, #cafe,
     *  #decade) is not a colour: a hex with no digit needs a word about
     *  colour in the message. */
    fun colours(text: String): Conversions? {
        firstMatch("""(?<![\w&#])#([0-9a-f]{6}|[0-9a-f]{3}|[0-9a-f]{8})$END""", text)?.let { g ->
            var hex = g[1] ?: return@let
            val colourWords = Regex("""\b(?:colou?rs?|hex|shade|bg|background|fill|stroke|tint|hue)\b""",
                RegexOption.IGNORE_CASE).containsMatchIn(text)
            // Six or eight characters with a digit are a colour; three need a
            // letter too ("#f00"), since "#007" and "#123" are hashtags.
            val digit = hex.any { it.isDigit() }
            val letter = hex.any { it.lowercaseChar() in 'a'..'f' }
            if (!(colourWords || (digit && (hex.length != 3 || letter)))) return null
            if (hex.length == 3) hex = hex.map { "$it$it" }.joinToString("")
            val v = hex.take(6).toLongOrNull(16) ?: return null
            val r = ((v shr 16) and 0xFF).toDouble(); val gg = ((v shr 8) and 0xFF).toDouble(); val b = (v and 0xFF).toDouble()
            return Conversions(g[0]!!.trim(), listOf("rgb(${r.toInt()}, ${gg.toInt()}, ${b.toInt()})", hsl(r, gg, b)))
        }
        firstMatch("""\brgba?(?:\(\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*(?:[,/]\s*[\d.]+%?\s*)?\)|\s+(\d{1,3})\s*,?\s+(\d{1,3})\s*,?\s+(\d{1,3}))$END""", text)
            // "rgb 255 87 51": the numbers without brackets (2026-10-08 probe).
            ?.let { g -> if (g[1] != null) g else listOf(g[0], g[4], g[5], g[6]) }?.let { g ->
            val r = g[1]?.toIntOrNull() ?: return@let
            val gg = g[2]?.toIntOrNull() ?: return@let
            val b = g[3]?.toIntOrNull() ?: return@let
            if (r > 255 || gg > 255 || b > 255) return null
            return Conversions(g[0]!!.trim(), listOf("#%02X%02X%02X".format(r, gg, b), hsl(r.toDouble(), gg.toDouble(), b.toDouble())))
        }
        return null
    }

    /** UPS's check digit: the 15 characters after 1Z, letters as
     *  (code − 63) mod 10, odd places once and even places twice. */
    fun upsValid(n: String): Boolean {
        val s = n.uppercase()
        if (s.length != 18 || !s.startsWith("1Z")) return false
        var sum = 0
        for ((i, c) in s.substring(2, 17).withIndex()) {
            val v = if (c.isDigit()) c - '0' else if (c in 'A'..'Z') (c.code - 63) % 10 else return false
            sum += if (i % 2 == 0) v else v * 2
        }
        return (10 - sum % 10) % 10 == s[17] - '0'
    }

    /** The postal format every country shares (RA123456785IN): its check
     *  digit, weights 8 6 4 2 3 5 9 7. */
    fun s10Valid(n: String): Boolean {
        val s = n.uppercase()
        if (s.length != 13) return false
        val digits = s.substring(2, 11).map { if (it.isDigit()) it - '0' else return false }
        val weights = listOf(8, 6, 4, 2, 3, 5, 9, 7)
        val sum = digits.take(8).zip(weights).sumOf { (d, w) -> d * w }
        var check = 11 - sum % 11
        if (check == 10) check = 0 else if (check == 11) check = 5
        return check == digits[8]
    }

    /** A tracking number the message ends on, with its carrier's own page
     *  (Smart.swift's tracking(in:)). The chip names the carrier; a tap adds
     *  the link. */
    fun tracking(text: String): Conversions? {
        fun link(label: String, url: String, g: List<String?>) =
            Conversions(g[0]!!.trim(), listOf(label), inserts = listOf(url), hows = listOf(Insertion.AFTER))
        firstMatch("""\b(1Z[0-9A-Z]{16})$END""", text)?.let { g ->
            val n = g[1]!!.uppercase()
            if (upsValid(n)) return link("UPS tracking", "https://www.ups.com/track?tracknum=$n", g)
        }
        firstMatch("""\b([A-Z]{2}\d{9}[A-Z]{2})$END""", text)?.let { g ->
            val n = g[1]!!.uppercase()
            if (s10Valid(n)) return when (n.takeLast(2)) {
                "GB" -> link("Royal Mail tracking", "https://www.royalmail.com/track-your-item#/tracking-results/$n", g)
                "US" -> link("USPS tracking", "https://tools.usps.com/go/TrackConfirmAction?tLabels=$n", g)
                "CA" -> link("Canada Post tracking", "https://www.canadapost-postescanada.ca/track-reperage/en#/search?searchFor=$n", g)
                "AU" -> link("Australia Post tracking", "https://auspost.com.au/mypost/track/#/details/$n", g)
                else -> null
            }
        }
        fun says(word: String) = Regex("""\b$word\b""", RegexOption.IGNORE_CASE).containsMatchIn(text)
        firstMatch("""(?<![\d])(9[2-5](?:\s?\d){18,20})$END""", text)?.let { g ->
            if (says("usps") || says("tracking") || says("track")) return link("USPS tracking", "https://tools.usps.com/go/TrackConfirmAction?tLabels=${g[1]!!.filter { it.isDigit() }}", g)
        }
        firstMatch("""(?<![\d])(\d{12}|\d{15})$END""", text)?.let { g ->
            if (says("fedex")) return link("FedEx tracking", "https://www.fedex.com/fedextrack/?trknbr=${g[1]}", g)
        }
        firstMatch("""(?<![\d])(\d{10})$END""", text)?.let { g ->
            if (says("dhl")) return link("DHL tracking", "https://www.dhl.com/global-en/home/tracking/tracking-express.html?submit=1&tracking-id=${g[1]}", g)
        }
        return null
    }

    private val airlines = mapOf(
        "AA" to "American", "UA" to "United", "DL" to "Delta", "WN" to "Southwest", "B6" to "JetBlue", "AS" to "Alaska",
        "NK" to "Spirit", "F9" to "Frontier", "HA" to "Hawaiian", "AC" to "Air Canada", "WS" to "WestJet", "AM" to "Aeroméxico",
        "BA" to "British Airways", "VS" to "Virgin Atlantic", "EI" to "Aer Lingus", "LH" to "Lufthansa", "AF" to "Air France",
        "KL" to "KLM", "LX" to "Swiss", "OS" to "Austrian", "SN" to "Brussels Airlines", "IB" to "Iberia", "VY" to "Vueling",
        "TP" to "TAP", "AY" to "Finnair", "SK" to "SAS", "DY" to "Norwegian", "FR" to "Ryanair", "U2" to "easyJet", "W6" to "Wizz Air",
        "LO" to "LOT", "A3" to "Aegean", "TK" to "Turkish Airlines", "EK" to "Emirates", "QR" to "Qatar Airways", "EY" to "Etihad",
        "FZ" to "flydubai", "G9" to "Air Arabia", "SV" to "Saudia", "GF" to "Gulf Air", "WY" to "Oman Air", "KU" to "Kuwait Airways",
        "LY" to "El Al", "MS" to "EgyptAir", "ET" to "Ethiopian", "KQ" to "Kenya Airways", "SA" to "South African",
        "AI" to "Air India", "6E" to "IndiGo", "IX" to "Air India Express", "SG" to "SpiceJet", "QP" to "Akasa Air",
        "UL" to "SriLankan", "PK" to "PIA", "BG" to "Biman", "SQ" to "Singapore Airlines", "TR" to "Scoot", "CX" to "Cathay Pacific",
        "MH" to "Malaysia Airlines", "AK" to "AirAsia", "TG" to "Thai", "VN" to "Vietnam Airlines", "GA" to "Garuda",
        "PR" to "Philippine Airlines", "5J" to "Cebu Pacific", "JL" to "JAL", "NH" to "ANA", "KE" to "Korean Air", "OZ" to "Asiana",
        "CA" to "Air China", "MU" to "China Eastern", "CZ" to "China Southern", "BR" to "EVA Air", "CI" to "China Airlines",
        "QF" to "Qantas", "VA" to "Virgin Australia", "JQ" to "Jetstar", "NZ" to "Air New Zealand", "LA" to "LATAM",
        "AV" to "Avianca", "CM" to "Copa", "AR" to "Aerolíneas Argentinas", "G3" to "Gol", "AD" to "Azul",
    )

    /** A flight number the message ends on, with its status page (Smart.swift's
     *  flight(in:)): the message has to say something about flying, or the
     *  code is in capitals after "on" or "taking". */
    fun flight(text: String): Conversions? {
        val g = firstMatch("""\b([A-Za-z0-9]{2})\s?(\d{1,4})$END""", text) ?: return null
        val typed = g[1] ?: return null
        val name = airlines[typed.uppercase()] ?: return null
        if (typed.none { it.isLetter() }) return null
        val flying = Regex("""\b(?:flight|flights|flying|fly|flies|flew|landing|lands|landed|departs|departing|departure|arrives|arriving|arrival|boarding|board|gate|terminal|airport|layover|connecting|plane)\b""",
            RegexOption.IGNORE_CASE).containsMatchIn(text)
        val onIt = typed == typed.uppercase() &&
            Regex("""\b(?:on|taking|catching|booked)\s+[A-Z0-9]{2}\s?\d{1,4}[.?!]?\s?$""").containsMatchIn(text)
        val number = g[2]?.toIntOrNull() ?: return null
        if (!(flying || onIt) || number <= 0) return null
        val code = typed.uppercase()
        return Conversions(g[0]!!.trim(), listOf("$name $number status"),
            inserts = listOf("https://www.flightaware.com/live/flight/$code$number"), hows = listOf(Insertion.AFTER))
    }

    /** A phone number the message ends on, written out properly, and its
     *  WhatsApp link (Smart.swift's phone(in:region:)). A string of digits
     *  counts only with a "+" or a word that says it is a number. */
    fun phone(text: String, region: String?): Conversions? {
        val g = firstMatch("""(?<![\w+])(\+?)(\(?\d[\d\s().-]{8,16}\d)$END""", text) ?: return null
        val plus = g[1] == "+"
        val digits = g[2]!!.filter { it.isDigit() }
        val said = Regex("""\b(?:call|calling|phone|ph|tel|number|no|num|whatsapp|wa|text\s+me|msg\s+me|mobile|mob|cell|contact|reach\s+me|ring)\b""",
            RegexOption.IGNORE_CASE).containsMatchIn(text)
        if (!plus && !said) return null
        val r = region?.uppercase() ?: ""
        val cc: String
        val national: String
        when {
            plus && digits.startsWith("1") && digits.length == 11 -> { cc = "1"; national = digits.drop(1) }
            plus && digits.startsWith("91") && digits.length == 12 -> { cc = "91"; national = digits.drop(2) }
            plus && digits.startsWith("44") && digits.length == 12 -> { cc = "44"; national = digits.drop(2) }
            plus -> return if (digits.length in 8..15)
                Conversions(g[0]!!.trim(), listOf("WhatsApp"), inserts = listOf("https://wa.me/$digits"),
                    hows = listOf(Insertion.AFTER)) else null
            r in setOf("US", "CA") && (digits.length == 10 || (digits.length == 11 && digits.startsWith("1"))) -> {
                cc = "1"; national = digits.takeLast(10)
            }
            r == "IN" && (digits.length == 10 || (digits.length == 11 && digits.startsWith("0"))) -> {
                cc = "91"; national = digits.takeLast(10)
            }
            r == "GB" && digits.length == 11 && digits.startsWith("0") -> { cc = "44"; national = digits.drop(1) }
            else -> return null
        }
        val n = national
        val local: String
        val world: String
        when (cc) {
            "1" -> {
                if (n.length != 10 || n[0] in "01" || n[3] in "01") return null
                local = "(${n.substring(0, 3)}) ${n.substring(3, 6)}-${n.substring(6)}"
                world = "+1 ${n.substring(0, 3)}-${n.substring(3, 6)}-${n.substring(6)}"
            }
            "91" -> {
                if (n.length != 10 || n[0] !in "6789") return null
                local = "${n.substring(0, 5)} ${n.substring(5)}"
                world = "+91 $local"
            }
            else -> {
                if (n.length != 10 || n[0] != '7') return null
                local = "0${n.substring(0, 4)} ${n.substring(4)}"
                world = "+44 ${n.substring(0, 4)} ${n.substring(4)}"
            }
        }
        // Two chips fit the strip: the number as it is written where it was
        // typed (with its country when a "+" was), and WhatsApp.
        val written = if (plus) world else local
        return Conversions(g[0]!!.trim(), listOf(written, "WhatsApp"),
            inserts = listOf(written, "https://wa.me/$cc$national"), hows = listOf(Insertion.REPLACE, Insertion.AFTER))
    }

    /** A Unix time (seconds or milliseconds, 2001 to 2036) or an ISO 8601
     *  time, as a date where the phone is (Smart.swift's unixTime). */
    fun unixTime(text: String, here: java.time.ZoneId, region: String?): Conversions? {
        fun say(instant: java.time.Instant): String {
            val at = instant.atZone(here)
            val pattern = if (region.equals("US", ignoreCase = true)) "EEE, MMM d, yyyy, h:mm a" else "EEE d MMM yyyy, h:mm a"
            return java.time.format.DateTimeFormatter.ofPattern(pattern, java.util.Locale.US).format(at).replace(' ', ' ') +
                " " + zoneLabel(here, instant)
        }
        firstMatch("""\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2}))$END""", text)?.let { g ->
            val iso = g[1] ?: return@let
            val instant = runCatching { java.time.OffsetDateTime.parse(iso).toInstant() }.getOrNull() ?: return null
            return Conversions(iso, listOf(say(instant)))
        }
        val g = firstMatch("""(?<![\d.])(\d{10}|\d{13})$END""", text) ?: return null
        val digits = g[1] ?: return null
        var n = digits.toDoubleOrNull() ?: return null
        if (digits.length == 13) n /= 1000
        if (n < 1_000_000_000 || n > 2_100_000_000) return null
        val alone = text.trim() == digits
        val said = Regex("""\b(?:timestamp|epoch|unix|ts|time)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text)
        if (!alone && !said) return null
        return Conversions(digits, listOf(say(java.time.Instant.ofEpochSecond(n.toLong()))))
    }

    /** A number in words or short, written out, and back (Smart.swift's
     *  bigNumber): "$2.4m" → $2,400,000 · $2.4 million; "3 crore" →
     *  3,00,00,000 · 30 million in India; "1500000" → 1,500,000 · 1.5 million. */
    fun bigNumber(text: String, region: String?): Conversions? {
        val india = region.equals("IN", ignoreCase = true)
        val scale = mapOf("k" to 1e3, "thousand" to 1e3, "m" to 1e6, "mn" to 1e6, "mm" to 1e6, "mil" to 1e6, "million" to 1e6,
            "b" to 1e9, "bn" to 1e9, "billion" to 1e9, "lakh" to 1e5, "lakhs" to 1e5, "lac" to 1e5, "lacs" to 1e5,
            "crore" to 1e7, "crores" to 1e7, "cr" to 1e7)
        var value: Double
        var symbol = ""
        val source: String
        val worded = firstMatch("""([$€£₹¥])\s?(\d+(?:\.\d+)?)\s?(k|m|mn|mm|b|bn|thousand|million|mil|billion|lakhs?|lacs?|crores?|cr)\b$END""", text)
            ?: firstMatch("""()(?<![\d.,])(\d+(?:\.\d+)?)\s?(thousand|million|billion|lakhs?|lacs?|crores?)\b$END""", text)
        if (worded != null) {
            val n = worded[2]?.toDoubleOrNull() ?: return null
            val s = scale[worded[3]!!.lowercase()] ?: return null
            value = n * s
            symbol = worded[1] ?: ""
            source = worded[0]!!.trim()
        } else {
            val g = firstMatch("""(?<![\d.,+])(\d{7,9})$END""", text) ?: return null
            value = g[1]!!.toDouble()
            source = g[0]!!.trim()
        }
        if (value < 1000 || value >= 1e15) return null
        fun short(n: Double): String = java.text.DecimalFormat("#,##0.##", java.text.DecimalFormatSymbols(java.util.Locale.US))
            .apply { roundingMode = java.math.RoundingMode.HALF_UP }.format(n)
        fun grouped(n: Double): String {
            val whole = Math.round(n).toString()
            if (!india || whole.length <= 3) {
                return java.text.DecimalFormat("#,##0", java.text.DecimalFormatSymbols(java.util.Locale.US)).format(Math.round(n))
            }
            // 1,23,45,678: the last three, then twos.
            var head = whole.dropLast(3)
            val groups = ArrayDeque<String>()
            while (head.length > 2) { groups.addFirst(head.takeLast(2)); head = head.dropLast(2) }
            if (head.isNotEmpty()) groups.addFirst(head)
            return groups.joinToString(",") + "," + whole.takeLast(3)
        }
        fun words(indian: Boolean): String? = if (indian) when {
            value >= 1e7 -> "${short(value / 1e7)} crore"
            value >= 1e5 -> "${short(value / 1e5)} lakh"
            else -> null
        } else when {
            // "10 thousand" says nothing "10,000" doesn't.
            value >= 1e9 -> "${short(value / 1e9)} billion"
            value >= 1e6 -> "${short(value / 1e6)} million"
            else -> null
        }
        // Two chips fit the strip: written out, then in words (lakh and
        // crore in India).
        val spoken = listOfNotNull(words(india), if (india) words(false) else null).map { symbol + it }
        val results = buildList {
            add(symbol + grouped(value))
            spoken.firstOrNull { !it.equals(source, ignoreCase = true) }?.let { add(it) }
        }.filter { !it.equals(source, ignoreCase = true) }.take(3)
        if (results.isEmpty()) return null
        return Conversions(source, results, hows = List(results.size) { Insertion.REPLACE })
    }

    /** What a copy holds that is worth pasting alone (Gboard's paste chips):
     *  its emails, links and phone numbers, in order, at most two, when the
     *  copy is more than just one of them (Smart.swift's pieces(of:)). */
    fun pieces(copy: String): List<String>? {
        val t = copy.trim()
        if (t.length < 8 || t.length > 2000) return null
        val patterns = listOf(
            """[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}""",
            """\bhttps?://[^\s<>"]+|\bwww\.[^\s<>"]+""",
            """(?<![\w+])\+?\(?\d[\d\s().-]{8,16}\d(?![\w])""",
        )
        val found = mutableListOf<Pair<IntRange, String>>()
        // A code in a message ("Your verification code is 482913"): the code
        // first, as Gboard's clipboard offers it (2026-10-08 research).
        Regex("""\b(?:code|otp|pin|passcode|password|verification|one[- ]time)\b[^\d\n]{0,24}?(?<![\d-])(\d{4,8})(?![\d-])""",
            RegexOption.IGNORE_CASE).find(t)?.groups?.get(1)?.let { found.add(it.range to it.value) }
        for ((i, p) in patterns.withIndex()) {
            for (m in Regex(p, RegexOption.IGNORE_CASE).findAll(t)) {
                var s = m.value.trim(' ', '.', ',', ';', ':', ')', '!', '?', '\'', '"')
                if (i == 2) {
                    // A phone has ten digits or more; dates and sums have fewer.
                    if (s.count { it.isDigit() } < 10) continue
                    s = s.trim()
                }
                if (found.none { it.second == s || (it.first.first <= m.range.last && m.range.first <= it.first.last) }) {
                    found.add(m.range to s)
                }
            }
        }
        val parts = found.sortedBy { it.first.first }.map { it.second }
        if (parts.isEmpty() || (parts.size == 1 && parts[0] == t)) return null
        return parts.take(2)
    }

    // MARK: what launchers work out: Raycast, Alfred, Spotlight (Smart.swift twin)

    /** Query keys that only say where a click came from, never what the
     *  page shows (Raycast's Link Cleaner, Firefox's Copy Clean Link). */
    private val trackerKeys = setOf(
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "gad_source", "gad_campaignid", "srsltid",
        "msclkid", "yclid", "twclid", "ttclid", "li_fat_id", "mc_cid", "mc_eid", "_hsenc", "_hsmi",
        "__hssc", "__hstc", "__hsfp", "hsctatracking", "mkt_tok", "igshid", "igsh", "mibextid",
        "oly_anon_id", "oly_enc_id", "rb_clickid", "s_cid", "s_kwcid", "ef_id", "vero_id", "vero_conv",
        "wickedid", "_openstat", "ocid", "icid", "ncid", "_branch_match_id", "_branch_referrer",
        "ref_src", "ref_url", "wt.mc_id", "pk_campaign", "pk_kwd", "pk_source", "pk_medium", "pk_content",
        "pk_cid", "utm", "_ga", "_gl",
    )
    private val trackerPrefixes = listOf("utm_", "mtm_", "matomo_")

    /** Keys that track on their own sites only: "si" on YouTube and
     *  Spotify, "s" and "t" on X ("t" is a time on YouTube), "ref" on
     *  Amazon and Reddit (elsewhere it can be a referral code). */
    private fun siteTrackers(host: String): Pair<Set<String>, List<String>> {
        fun on(domain: String) = host == domain || host.endsWith(".$domain")
        return when {
            on("youtube.com") || on("youtu.be") -> setOf("si", "pp") to emptyList()
            on("spotify.com") || on("spotify.link") -> setOf("si", "nd") to emptyList()
            on("x.com") || on("twitter.com") -> setOf("s", "t") to emptyList()
            on("tiktok.com") -> setOf("_r", "_t", "is_from_webapp", "sender_device", "is_copy_url", "share_app_id",
                "share_link_id", "social_sharing", "u_code", "preview_pb", "share_item_id", "tt_from") to emptyList()
            on("linkedin.com") -> setOf("trk", "trackingid", "lipi", "midtoken", "midsig", "trkemail", "eid", "refid", "rcm") to emptyList()
            on("facebook.com") || on("fb.com") || on("fb.watch") -> setOf("rdid", "sfnsn", "__tn__") to listOf("__cft__")
            on("reddit.com") -> setOf("share_id", "rdt", "ref", "ref_source") to emptyList()
            host.startsWith("amazon.") || host.contains(".amazon.") -> setOf("crid", "dib", "dib_tag", "qid", "sprefix", "sr",
                "keywords", "ref", "ref_", "content-id", "_encoding", "spla", "sp_csd") to listOf("pd_rd_", "pf_rd_")
            else -> emptySet<String>() to emptyList()
        }
    }

    /** The link without its trackers, or null when it has none. A time
     *  ("t=42"), a page, a search and the part after "#" stay. */
    fun withoutTrackers(link: String): String? {
        var rest = link
        var fragment = ""
        rest.indexOf('#').takeIf { it >= 0 }?.let { fragment = rest.substring(it); rest = rest.substring(0, it) }
        var path = rest
        var query = ""
        rest.indexOf('?').takeIf { it >= 0 }?.let { path = rest.substring(0, it); query = rest.substring(it + 1) }
        val afterScheme = path.indexOf("://").let { if (it >= 0) path.substring(it + 3) else path }
        var host = afterScheme.takeWhile { it != '/' && it != ':' }.lowercase()
        for (p in listOf("www.", "m.", "mobile.", "smile.")) if (host.startsWith(p)) host = host.removePrefix(p)
        val (keys, prefixes) = siteTrackers(host)
        var cleanPath = path
        // Amazon says which list a click came from in the path ("/ref=sr_1_3").
        if (host.startsWith("amazon.") || host.contains(".amazon.")) cleanPath = cleanPath.replace(Regex("""/ref=[^/]*"""), "")
        val youtube = host == "youtube.com" || host.endsWith(".youtube.com") || host == "youtu.be"
        var removed = cleanPath != path
        val kept = query.split("&").filter { pair ->
            val key = pair.substringBefore("=").lowercase()
            val value = if ('=' in pair) pair.substringAfter("=").lowercase() else ""
            val tracker = key in trackerKeys || key in keys || (trackerPrefixes + prefixes).any { key.startsWith(it) } ||
                (youtube && key == "feature" && value.startsWith("share"))
            if (tracker) removed = true
            !tracker
        }
        if (!removed) return null
        val left = kept.filter { it.isNotEmpty() }
        return cleanPath + (if (left.isEmpty()) "" else "?" + left.joinToString("&")) + fragment
    }

    /** The link the message ends on, without its trackers: "Remove
     *  tracking" puts it back clean, in its place. */
    fun cleanLink(text: String): Conversions? {
        val g = firstMatch("""(?:^|\s)((?:https?://|www\.)[^\s<>"]+)\s?$""", text) ?: return null
        val link = g[1] ?: return null
        if (link.last() in ".,;:!?)]}'\"") return null
        val clean = withoutTrackers(link) ?: return null
        return Conversions(link, listOf("Remove tracking"), listOf(clean), listOf(Insertion.REPLACE))
    }

    /** A copy that is one link with trackers: the link without them. */
    fun cleanCopy(copy: String): String? {
        val t = copy.trim()
        if (t.any { it.isWhitespace() } || !Regex("""^(?:https?://|www\.)""", RegexOption.IGNORE_CASE).containsMatchIn(t)) return null
        return withoutTrackers(t)
    }

    /** Whether the message ends inside a link, or what is left of one in
     *  the strip's last characters: its digits are an address, not a sum,
     *  a phone number or a parcel. */
    fun endsInLink(text: String): Boolean {
        val token = text.split(' ', '\n').lastOrNull { it.isNotEmpty() }?.lowercase() ?: return false
        if ("://" in token || token.startsWith("www.")) return true
        if (Regex("""^(?:[a-z0-9-]+\.)+[a-z]{2,}/""").containsMatchIn(token)) return true
        // A query cut off at the front: "…ource=news&utm_medium=email".
        return '=' in token && ('&' in token || '?' in token)
    }

    /** Faces by name, as Slack has /shrug: the Emoticons tab's own faces. */
    val faces = mapOf(
        "shrug" to "¯\\_(ツ)_/¯", "tableflip" to "(╯°□°）╯︵ ┻━┻", "flip" to "(╯°□°）╯︵ ┻━┻",
        "unflip" to "┬─┬ノ( º _ ºノ)", "lenny" to "( ͡° ͜ʖ ͡°)", "disapprove" to "ಠ_ಠ", "lod" to "ಠ_ಠ",
        "happy" to "(◕‿◕)", "hug" to "(づ｡◕‿‿◕｡)づ", "cry" to "(╥﹏╥)", "love" to "(♥ω♥)", "bear" to "ʕ•ᴥ•ʔ",
        "cool" to "(⌐■_■)", "sparkle" to "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "cat" to "(=^･ω･^=)", "dance" to "ᕕ( ᐛ )ᕗ",
        "angry" to "(╬ Ò﹏Ó)", "shock" to "(⊙_⊙)", "fight" to "(ง •̀_•́)ง", "yay" to "\\(^o^)/",
    )

    /** "/shrug" or ";shrug" → ¯\_(ツ)_/¯ in its place, and "shrug" alone. */
    fun face(text: String): Conversions? {
        val names = faces.keys.sortedByDescending { it.length }.joinToString("|")
        firstMatch("""(?:^|\s)([/;](?:$names))\s?$""", text)?.let { g ->
            val typed = g[1] ?: return@let
            faces[typed.drop(1).lowercase()]?.let { return Conversions(typed, listOf(it), hows = listOf(Insertion.REPLACE)) }
        }
        firstMatch("""^\s*(shrug|tableflip|lenny)\s?$""", text)?.let { g ->
            val typed = g[1] ?: return@let
            faces[typed.lowercase()]?.let { return Conversions(typed, listOf(it), hows = listOf(Insertion.REPLACE)) }
        }
        return null
    }

    private val symbolSwaps = mapOf(
        "<->" to "↔", "<=>" to "⇔", "->" to "→", "<-" to "←", "=>" to "⇒", "+/-" to "±", "+-" to "±",
        "!=" to "≠", "=/=" to "≠", "~=" to "≈", "<=" to "≤", ">=" to "≥", "(tm)" to "™",
    )

    /** "->" → →, "+-" → ±, "!=" → ≠, "(tm)" → ™, in its place. A heart
     *  ("<3") and a face (":->") stay as they are. */
    fun symbol(text: String): Conversions? {
        val g = firstMatch("""(?:^|[\s\w])(<->|<=>|->|<-|=>|\+/-|\+-|!=|=/=|~=|<=|>=|\(tm\))\s?$""", text) ?: return null
        val typed = g[1] ?: return null
        val swap = symbolSwaps[typed.lowercase()] ?: return null
        return Conversions(typed, listOf(swap), hows = listOf(Insertion.REPLACE))
    }

    private val onesWords = listOf("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen")
    private val tensWords = listOf("", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")

    /** Under a thousand in words: "two hundred fifty-six". */
    private fun hundredsInWords(n: Int): String {
        val parts = mutableListOf<String>()
        if (n >= 100) parts += onesWords[n / 100] + " hundred"
        val r = n % 100
        if (r > 0) parts += if (r < 20) onesWords[r] else tensWords[r / 10] + (if (r % 10 > 0) "-" + onesWords[r % 10] else "")
        return parts.joinToString(" ")
    }

    /** A whole number in words, as a cheque has it: "one thousand two
     *  hundred fifty"; in India "one lakh twenty thousand". */
    fun numberInWords(n: Long, indian: Boolean): String {
        if (n == 0L) return "zero"
        val scales = if (indian) listOf(10_000_000L to "crore", 100_000L to "lakh", 1000L to "thousand")
        else listOf(1_000_000_000_000L to "trillion", 1_000_000_000L to "billion", 1_000_000L to "million", 1000L to "thousand")
        val parts = mutableListOf<String>()
        var rest = n
        for ((size, name) in scales) {
            if (rest < size) continue
            val count = rest / size
            parts += (if (count >= 1000) numberInWords(count, indian) else hundredsInWords(count.toInt())) + " " + name
            rest %= size
        }
        if (rest > 0) parts += hundredsInWords(rest.toInt())
        return parts.joinToString(" ")
    }

    private val moneyWords = mapOf(
        "$" to listOf("dollar", "dollars", "cent", "cents"), "€" to listOf("euro", "euros", "cent", "cents"),
        "£" to listOf("pound", "pounds", "penny", "pence"), "₹" to listOf("rupee", "rupees", "paisa", "paise"),
    )

    /** "1,250 in words" → One thousand two hundred fifty; "$1,250.50 in
     *  words" → … dollars and fifty cents; lakh and crore in India (a
     *  cheque wants words). Typed in place of what was asked. */
    fun inWords(text: String, region: String?): Conversions? {
        val g = firstMatch("""(?<![\w.,])([$€£₹])?\s?(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d{1,13}(?:\.\d{1,2})?)\s+(?:in|into|to)\s+words$END""", text)
            ?: return null
        val parts = (g[2] ?: return null).replace(",", "").split(".")
        val whole = parts[0].toLongOrNull()?.takeIf { it < 1_000_000_000_000L } ?: return null
        val symbol = g[1]
        var words = numberInWords(whole, region.equals("IN", ignoreCase = true) || symbol == "₹")
        val w = symbol?.let { moneyWords[it] }
        if (w != null) {
            words += " " + (if (whole == 1L) w[0] else w[1])
            if (parts.size == 2) {
                val c = (if (parts[1].length == 1) parts[1] + "0" else parts[1]).toIntOrNull()
                if (c != null && c > 0) words += " and " + hundredsInWords(c) + " " + (if (c == 1) w[2] else w[3])
            }
        } else if (parts.size == 2) {
            words += " point " + parts[1].mapNotNull { it.digitToIntOrNull() }.joinToString(" ") { onesWords[it] }
        }
        return Conversions(g[0]!!.trim(), listOf(words.replaceFirstChar { it.uppercase() }), hows = listOf(Insertion.REPLACE))
    }

    private const val CLOCK_PART = """(\d{1,2})(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)?"""

    /** Minutes after midnight, or null when it can't be a time of day. */
    private fun dayMinutes(h: Int, m: Int, ap: String?): Int? {
        if (m >= 60) return null
        if (ap != null) {
            if (h < 1 || h > 12) return null
            return (h % 12 + if (ap.lowercase().startsWith("p")) 12 else 0) * 60 + m
        }
        return if (h <= 23) h * 60 + m else null
    }

    /** "7 h 45 min", "8 h", "45 min". */
    private fun spanText(minutes: Int): String {
        val h = minutes / 60
        val m = minutes % 60
        if (h == 0) return "$m min"
        return if (m == 0) "$h h" else "$h h $m min"
    }

    /** "6:15 PM" where am/pm was said, "16:30" on a 24-hour clock. */
    private fun clockText(minutes: Int, twelve: Boolean): String {
        val t = (minutes % 1440 + 1440) % 1440
        val h = t / 60
        val m = t % 60
        val mm = if (m < 10) "0$m" else "$m"
        if (!twelve) return "$h:$mm"
        val h12 = if (h % 12 == 0) 12 else h % 12
        val ap = if (h < 12) "AM" else "PM"
        return if (m == 0) "$h12 $ap" else "$h12:$mm $ap"
    }

    /** "9:30–5:15", "shift 9am to 5:30pm" → 7 h 45 min; "3:45pm + 2h30",
     *  "9am plus 8 hours" → 6:15 PM. A span needs minutes or am/pm at one
     *  end ("working 9 to 5" is a phrase, "won 3-1" a score), and is said
     *  only when it takes working out (not "2-3pm"). */
    fun clockMaths(text: String): Conversions? {
        firstMatch("""(?<![\d:.$€£₹/])$CLOCK_PART\s*(?:-|–|—|to|till|til|until)\s*$CLOCK_PART$END""", text)?.let { g ->
            val h1 = g[1]?.toIntOrNull() ?: return@let
            val h2 = g[4]?.toIntOrNull() ?: return@let
            if (g[2] == null && g[3] == null && g[5] == null && g[6] == null) return@let
            val m1 = g[2]?.toIntOrNull() ?: 0
            val m2 = g[5]?.toIntOrNull() ?: 0
            var ap1 = g[3]
            var ap2 = g[6]
            fun flip(ap: String) = if (ap.lowercase().startsWith("a")) "pm" else "am"
            if (ap1 == null && ap2 != null) {
                val a = ap2
                ap1 = a
                val s = dayMinutes(h1, m1, a)
                val f = dayMinutes(h2, m2, a)
                if (s != null && f != null && s > f) ap1 = flip(a)
            } else if (ap1 != null && ap2 == null) {
                val a = ap1
                ap2 = a
                val s = dayMinutes(h1, m1, a)
                val f = dayMinutes(h2, m2, a)
                if (s != null && f != null && f <= s) ap2 = flip(a)
            }
            val s = dayMinutes(h1, m1, ap1) ?: return null
            var f = dayMinutes(h2, m2, ap2) ?: return null
            if (ap1 == null && h1 <= 12 && h2 <= 12) {
                // "9:30–5:15": the end is the next time the clock says it.
                while (f <= s) f += 12 * 60
            } else if (f <= s) {
                f += 24 * 60
            }
            val span = f - s
            if (span <= 0 || span >= 24 * 60 || (span % 60 == 0 && span < 3 * 60)) return null
            return Conversions(g[0]!!.trim(), listOf(spanText(span)))
        }
        val duration = """(?:(\d{1,2}(?:\.\d+)?)\s*(?:h|hrs?|hours?)\s*(?:(\d{1,2})\s*(?:m|mins?|minutes?)?)?|(\d{1,3})\s*(?:m|mins?|minutes?))"""
        val g = firstMatch("""(?<![\d:.$€£₹/])$CLOCK_PART\s*(\+|plus|-|minus)\s*$duration$END""", text) ?: return null
        val h = g[1]?.toIntOrNull() ?: return null
        if (g[2] == null && g[3] == null) return null
        val start = dayMinutes(h, g[2]?.toIntOrNull() ?: 0, g[3]) ?: return null
        val add = g[5]?.toDoubleOrNull()?.let { it * 60 + (g[6]?.toDoubleOrNull() ?: 0.0) } ?: g[7]?.toDoubleOrNull() ?: 0.0
        if (add <= 0 || add >= 48 * 60) return null
        val op = g[4]!!.lowercase()
        val at = start + (if (op == "-" || op == "minus") -1 else 1) * Math.round(add).toInt()
        return Conversions(g[0]!!.trim(), listOf(clockText(at, twelve = g[3] != null)))
    }

    /** "every 8 hours from 7am" → 7 AM, 3 PM, 11 PM: the times on the clock
     *  in a day, from four hours apart to twelve. */
    fun everyHours(text: String): Conversions? {
        val counts = mapOf("four" to 4, "five" to 5, "six" to 6, "eight" to 8, "twelve" to 12)
        val g = firstMatch("""\bevery\s+(\d{1,2}|four|five|six|eight|twelve)\s*(?:h|hrs?|hours?)\s+(?:from|starting(?:\s+(?:at|from))?|beginning(?:\s+at)?|at)\s+$CLOCK_PART$END""", text)
            ?: return null
        val n = g[1]?.toIntOrNull() ?: counts[g[1]!!.lowercase()] ?: return null
        if (n < 4 || n > 12) return null
        val h = g[2]?.toIntOrNull() ?: return null
        if (g[3] == null && g[4] == null && h <= 12) return null
        val start = dayMinutes(h, g[3]?.toIntOrNull() ?: 0, g[4]) ?: return null
        val times = (0 until 24 * 60 step n * 60).map { clockText(start + it, twelve = g[4] != null) }
        return Conversions(g[0]!!.trim(), listOf(times.joinToString(", ")))
    }

    /** The weekday of a date, Sunday 0 to Saturday 6 (Sakamoto's method). */
    private fun weekdayOf(y: Int, m: Int, d: Int): Int {
        val t = intArrayOf(0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4)
        val yy = if (m < 3) y - 1 else y
        return (yy + yy / 4 - yy / 100 + yy / 400 + t[m - 1] + d) % 7
    }

    private fun daysIn(y: Int, m: Int): Int {
        val leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        return intArrayOf(31, if (leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[m - 1]
    }

    /** The nth weekday (Sunday 0) of a month; n = -1 is the last. */
    private fun nthWeekday(y: Int, m: Int, weekday: Int, n: Int): Pair<Int, Int> {
        if (n < 0) {
            val last = daysIn(y, m)
            return m to last - (weekdayOf(y, m, last) - weekday + 7) % 7
        }
        return m to 1 + (weekday - weekdayOf(y, m, 1) + 7) % 7 + (n - 1) * 7
    }

    /** Easter Sunday, by the Gregorian computus. */
    private fun easter(y: Int): Pair<Int, Int> {
        val a = y % 19; val b = y / 100; val c = y % 100; val d = b / 4; val e = b % 4
        val f = (b + 8) / 25; val g = (b - f + 1) / 3
        val h = (19 * a + b - d - g + 15) % 30; val i = c / 4; val k = c % 4
        val l = (32 + 2 * e + 2 * i - h - k) % 7; val m = (a + 11 * h + 22 * l) / 451
        return (h + l - 7 * m + 114) / 31 to (h + l - 7 * m + 114) % 31 + 1
    }

    /** A month and day some days later or earlier in the same year. */
    private fun shifted(y: Int, md: Pair<Int, Int>, days: Int): Pair<Int, Int> {
        var (m, d) = md
        d += days
        while (d < 1) { m -= 1; d += daysIn(y, m) }
        while (d > daysIn(y, m)) { d -= daysIn(y, m); m += 1 }
        return m to d
    }

    /** Diwali (Lakshmi Puja) and the Lunar New Year follow the moon. */
    private val diwaliDays = mapOf(2025 to (10 to 20), 2026 to (11 to 8), 2027 to (10 to 29), 2028 to (10 to 17),
        2029 to (11 to 5), 2030 to (10 to 26))
    private val lunarNewYears = mapOf(2025 to (1 to 29), 2026 to (2 to 17), 2027 to (2 to 6), 2028 to (1 to 26),
        2029 to (2 to 13), 2030 to (2 to 3))

    /** Holidays as people name them; apostrophes and dots optional. */
    private const val HOLIDAY_NAMES = """new\s+year'?s\s+eve|nye|new\s+year'?s\s+day|new\s+year'?s|new\s+year|valentine'?s\s+day|valentine'?s|st\.?\s+patrick'?s\s+day|saint\s+patrick'?s\s+day|paddy'?s\s+day|easter\s+sunday|easter\s+monday|easter|good\s+friday|mother'?s\s+day|father'?s\s+day|memorial\s+day|independence\s+day|(?:4th|fourth)\s+of\s+july|labou?r\s+day|halloween|thanksgiving|black\s+friday|cyber\s+monday|christmas\s+eve|xmas\s+eve|christmas\s+day|christmas|xmas|boxing\s+day|mlk\s+day|martin\s+luther\s+king(?:\s+jr\.?)?\s+day|presidents'?\s+day|juneteenth|veterans'?\s+day|remembrance\s+day|canada\s+day|australia\s+day|bastille\s+day|guy\s+fawkes(?:\s+night)?|bonfire\s+night|april\s+fools'?(?:\s+day)?|earth\s+day|groundhog\s+day|cinco\s+de\s+mayo|diwali|deepavali|lunar\s+new\s+year|chinese\s+new\s+year|republic\s+day|gandhi\s+jayanti"""

    /** A holiday's month and day in a year, where the phone is (Mother's
     *  Day is in Lent in Britain, Thanksgiving in October in Canada). */
    private fun holidayDay(name: String, y: Int, region: String?): Pair<Int, Int>? {
        val r = region?.uppercase() ?: ""
        val n = name.lowercase().replace("'", "").replace(".", "").replace(Regex("""\s+"""), " ")
        val thanksgiving = nthWeekday(y, 11, 4, 4)
        return when (n) {
            "new years eve", "nye" -> 12 to 31
            "new years day", "new years", "new year" -> 1 to 1
            "valentines day", "valentines" -> 2 to 14
            "st patricks day", "saint patricks day", "paddys day" -> 3 to 17
            "easter", "easter sunday" -> easter(y)
            "good friday" -> shifted(y, easter(y), -2)
            "easter monday" -> shifted(y, easter(y), 1)
            "mothers day" -> if (r in setOf("GB", "IE")) shifted(y, easter(y), -21) else nthWeekday(y, 5, 0, 2)
            "fathers day" -> if (r in setOf("AU", "NZ")) nthWeekday(y, 9, 0, 1) else nthWeekday(y, 6, 0, 3)
            "memorial day" -> nthWeekday(y, 5, 1, -1)
            "independence day" -> if (r == "IN") 8 to 15 else 7 to 4
            "4th of july", "fourth of july" -> 7 to 4
            "labor day", "labour day" -> if (r in setOf("US", "CA")) nthWeekday(y, 9, 1, 1) else 5 to 1
            "halloween" -> 10 to 31
            "thanksgiving" -> if (r == "CA") nthWeekday(y, 10, 1, 2) else thanksgiving
            "black friday" -> shifted(y, thanksgiving, 1)
            "cyber monday" -> shifted(y, thanksgiving, 4)
            "christmas eve", "xmas eve" -> 12 to 24
            "christmas", "xmas", "christmas day" -> 12 to 25
            "boxing day" -> 12 to 26
            "mlk day", "martin luther king day", "martin luther king jr day" -> nthWeekday(y, 1, 1, 3)
            "presidents day" -> nthWeekday(y, 2, 1, 3)
            "juneteenth" -> 6 to 19
            "veterans day", "remembrance day" -> 11 to 11
            "canada day" -> 7 to 1
            "australia day" -> 1 to 26
            "bastille day" -> 7 to 14
            "guy fawkes", "guy fawkes night", "bonfire night" -> 11 to 5
            "april fools", "april fools day" -> 4 to 1
            "earth day" -> 4 to 22
            "groundhog day" -> 2 to 2
            "cinco de mayo" -> 5 to 5
            "diwali", "deepavali" -> diwaliDays[y]
            "lunar new year", "chinese new year" -> lunarNewYears[y]
            "republic day" -> if (r == "IN") 1 to 26 else null
            "gandhi jayanti" -> 10 to 2
            else -> null
        }
    }

    /** The next time a month and day comes round, today included. */
    private fun nextDay(day: (Int) -> Pair<Int, Int>?, today: java.time.LocalDate): java.time.LocalDate? {
        for (y in listOf(today.year, today.year + 1)) {
            val (m, d) = day(y) ?: continue
            val date = java.time.LocalDate.of(y, m, d)
            if (!date.isBefore(today)) return date
        }
        return null
    }

    /** "today", "tomorrow", "in 54 days". */
    private fun countdown(date: java.time.LocalDate, today: java.time.LocalDate): String {
        val days = java.time.temporal.ChronoUnit.DAYS.between(today, date)
        return when (days) { 0L -> "today"; 1L -> "tomorrow"; else -> "in $days days" }
    }

    /** "oct 14", "14th of october": a month and day. */
    private fun monthAndDay(s: String): Pair<Int, Int>? {
        val words = s.lowercase().replace(Regex("""(\d)(?:st|nd|rd|th)"""), "$1")
            .split(' ', '.', ',').filter { it.isNotEmpty() && it != "of" }
        if (words.size != 2) return null
        val (dText, mText) = if (words[0].toIntOrNull() != null) words[0] to words[1] else words[1] to words[0]
        val d = dText.toIntOrNull() ?: return null
        val m = datedMonths.firstOrNull { it.first == mText }?.second ?: return null
        if (d < 1 || d > daysIn(2024, m)) return null
        return m to d
    }

    /** "after thanksgiving" → Thu 26 Nov · in 54 days; "christmas party";
     *  "days until christmas" → 83 days. A holiday needs a word that dates
     *  it ("merry christmas" is a greeting), and only days ahead count. */
    fun holiday(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val t = text.replace('’', '\'')
        val today = now.atZone(here).toLocalDate()
        val monthNames = datedMonths.joinToString("|") { it.first }
        val monthDay = """(?:$monthNames)\.?\s+\d{1,2}(?:st|nd|rd|th)?|\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?(?:$monthNames)"""
        // "days until christmas", "how many days till dec 25", "sleeps to christmas".
        firstMatch("""\b(?:how\s+many\s+)?(days?|weeks?|sleeps)\s+(?:left\s+)?(?:until|till|til|to|before)\s+(?:the\s+)?($HOLIDAY_NAMES|$monthDay)$END""", t)?.let { g ->
            val what = g[2] ?: return null
            val named = firstMatch("""^(?:$HOLIDAY_NAMES)$""", what) != null
            val date = (if (named) nextDay({ holidayDay(what, it, region) }, today)
            else monthAndDay(what)?.let { md -> nextDay({ md }, today) }) ?: return null
            val days = java.time.temporal.ChronoUnit.DAYS.between(today, date).toInt()
            val unit = g[1]!!.lowercase()
            val count = if (unit.startsWith("week") && days >= 7) {
                "${days / 7} week${if (days / 7 == 1) "" else "s"}" + (if (days % 7 > 0) " ${days % 7} day${if (days % 7 == 1) "" else "s"}" else "")
            } else {
                "$days " + if (unit == "sleeps") (if (days == 1) "sleep" else "sleeps") else (if (days == 1) "day" else "days")
            }
            return Conversions(g[0]!!.trim(), listOf(count, dayName(date, today, region)))
        }
        // "when is thanksgiving", "what day is christmas this year", "countdown
        // to new year", "when is easter 2027" (iOS 10-14 probe).
        firstMatch("""\b(?:when\s+is|when'?s|whens|what\s+(?:day|date)\s+is|countdown\s+(?:to|till|until)|how\s+long\s+(?:until|till|to))\s+(?:the\s+)?($HOLIDAY_NAMES)(?:\s+(?:this\s+year|(20\d{2})))?\??$END""", t)?.let { g ->
            val name = g[1] ?: return@let
            val y = g[2]?.toIntOrNull()
            val md = y?.let { holidayDay(name, it, region) }
            val date = if (y != null && md != null) runCatching { java.time.LocalDate.of(y, md.first, md.second) }.getOrNull()
                else nextDay({ holidayDay(name, it, region) }, today)
            if (date != null) return Conversions(g[0]!!.trim(), listOf(dayName(date, today, region), countdown(date, today)))
        }
        val lead = """\b(?:on|after|before|by|till|til|until|for|over|during|around|this|next|from|at)\s+(?:the\s+)?($HOLIDAY_NAMES)(?:\s+(?:day|weekend|break|holidays?|party|parties|trip|sale|sales|dinner|lunch|brunch|plans?|week|vacation))?$END"""
        val tail = """(?<!\blast\s)(?<!\bpast\s)\b($HOLIDAY_NAMES)\s+(?:weekend|break|party|parties|trip|sale|sales|dinner|lunch|brunch|plans?|holidays?|vacation|week)$END"""
        for (p in listOf(lead, tail)) {
            val g = firstMatch(p, t) ?: continue
            val name = g[1] ?: continue
            val date = nextDay({ holidayDay(name, it, region) }, today) ?: continue
            return Conversions(g[0]!!.trim(), listOf(dayName(date, today, region), countdown(date, today)))
        }
        return null
    }

    /** Weekends on Friday and Saturday where the week runs that way. */
    private val fridayWeekends = setOf("SA", "EG", "IL", "QA", "KW", "OM", "BH", "JO", "IQ", "DZ", "LY", "SD", "YE")

    /** "10 working days from today", "in 5 business days" → Fri 16 Oct:
     *  weekdays counted from tomorrow (public holidays aside). */
    fun workingDays(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val g = firstMatch("""\b$COUNT_WORD\s+(?:working|business|work)\s+days?(?:\s+(?:from\s+(?:today|now)|after\s+today))?$END""", text)
            ?: return null
        val whole = g[0]!!
        // "3-5 business days": a range, half answered.
        val head = text.dropLast(whole.length)
        if (Regex("""\d\s*(?:-|–|to)\s*$""", RegexOption.IGNORE_CASE).containsMatchIn(head)) return null
        val count = g[1]!!
        val n = (count.toDoubleOrNull() ?: smallNumbers[count.lowercase()] ?: 0.0).toInt()
        if (n < 1 || n > 260) return null
        val friday = (region?.uppercase() ?: "") in fridayWeekends
        val today = now.atZone(here).toLocalDate()
        var day = today
        var left = n
        while (left > 0) {
            day = day.plusDays(1)
            val wd = day.dayOfWeek
            val weekend = if (friday) wd == java.time.DayOfWeek.FRIDAY || wd == java.time.DayOfWeek.SATURDAY
            else wd == java.time.DayOfWeek.SATURDAY || wd == java.time.DayOfWeek.SUNDAY
            if (!weekend) left -= 1
        }
        return Conversions(whole.trim(), listOf(dayName(day, today, region)))
    }

    /** "12–18 Oct" ("Oct 12–18" in the US), across months "28 Sep–4 Oct". */
    private fun dayRange(a: java.time.LocalDate, b: java.time.LocalDate, today: java.time.LocalDate, region: String?): String {
        val month = java.time.format.DateTimeFormatter.ofPattern("MMM", java.util.Locale.US)
        val ma = month.format(a)
        val mb = month.format(b)
        val us = region.equals("US", ignoreCase = true)
        var text = if (ma == mb) (if (us) "$ma ${a.dayOfMonth}–${b.dayOfMonth}" else "${a.dayOfMonth}–${b.dayOfMonth} $mb")
        else (if (us) "$ma ${a.dayOfMonth}–$mb ${b.dayOfMonth}" else "${a.dayOfMonth} $ma–${b.dayOfMonth} $mb")
        if (b.year != today.year) text += (if (us) ", " else " ") + b.year
        return text
    }

    /** "cw 42", "KW 42", "calendar week 42", "week no. 42" → 12–18 Oct: an
     *  ISO week, Monday to Sunday. "week 3" alone is a count, not a date. */
    fun weekNumber(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        // "what week is it", "week number?": this week's ISO number.
        firstMatch("""(?:^|\b(?:what|which)\s+)(?:week\s+(?:is\s+it|are\s+we\s+in|number\s+is\s+it)|(?:current\s+|this\s+)?week\s+(?:no\.?|number|num))\s*(?:today|now)?$END""", text)?.let { w ->
            val week = now.atZone(here).toLocalDate().get(java.time.temporal.IsoFields.WEEK_OF_WEEK_BASED_YEAR)
            return Conversions(w[0]!!.trim(), listOf("Week $week"))
        }
        val g =firstMatch("""\b(?:cw|kw|calendar\s+week|week\s+(?:no\.?|number|num|#))\s*#?\s*(\d{1,2})$END""", text) ?: return null
        val n = g[1]?.toIntOrNull()?.takeIf { it in 1..53 } ?: return null
        val today = now.atZone(here).toLocalDate()
        val thisYear = today.get(java.time.temporal.IsoFields.WEEK_BASED_YEAR)
        for (year in listOf(thisYear, thisYear + 1)) {
            val anchor = java.time.LocalDate.of(year, 1, 4)
            if (n > java.time.temporal.IsoFields.WEEK_OF_WEEK_BASED_YEAR.rangeRefinedBy(anchor).maximum) continue
            val monday = anchor.with(java.time.temporal.IsoFields.WEEK_OF_WEEK_BASED_YEAR, n.toLong())
                .with(java.time.DayOfWeek.MONDAY)
            val sunday = monday.plusDays(6)
            if (sunday.isBefore(today)) continue
            return Conversions(g[0]!!.trim(), listOf(dayRange(monday, sunday, today, region)))
        }
        return null
    }

    /** A whole date as written: "14 mar 1998", "march 14, 1998",
     *  "14/03/1998" (month first in the US), "1998-03-14". Twelve groups. */
    private val fullDatePattern: String by lazy {
        val m = datedMonths.joinToString("|") { it.first }
        """(?:(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?($m)\.?,?\s+(\d{4})|($m)\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})|(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})|(\d{4})-(\d{1,2})-(\d{1,2}))"""
    }

    /** The year, month and day of a whole date matched from group [i]. */
    private fun fullDate(g: List<String?>, i: Int, region: String?): Triple<Int, Int, Int>? {
        fun month(s: String?) = s?.let { w -> datedMonths.firstOrNull { it.first == w.lowercase() }?.second }
        fun int(k: Int) = g[i + k]?.toIntOrNull()
        val d0 = int(0); val m1 = month(g[i + 1]); val y2 = int(2)
        val m3 = month(g[i + 3]); val d4 = int(4); val y5 = int(5)
        val a6 = int(6); val b7 = int(7); val y8 = int(8)
        val y9 = int(9); val m10 = int(10); val d11 = int(11)
        val date = when {
            d0 != null && m1 != null && y2 != null -> Triple(y2, m1, d0)
            m3 != null && d4 != null && y5 != null -> Triple(y5, m3, d4)
            a6 != null && b7 != null && y8 != null -> if (region.equals("US", ignoreCase = true)) Triple(y8, a6, b7) else Triple(y8, b7, a6)
            y9 != null && m10 != null && d11 != null -> Triple(y9, m10, d11)
            else -> return null
        }
        val (y, m, d) = date
        if (y < 1900 || m < 1 || m > 12 || d < 1 || d > daysIn(y, m)) return null
        return date
    }

    /** "born 14 mar 1998" → 28 years old; "together since 12 june 2021" →
     *  5 years 3 months. A whole date only: "born in 1995" says it already. */
    fun age(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val today = now.atZone(here).toLocalDate()
        val ty = today.year; val tm = today.monthValue; val td = today.dayOfMonth
        fun before(a: Triple<Int, Int, Int>, b: Triple<Int, Int, Int>) =
            a.first < b.first || (a.first == b.first && (a.second < b.second || (a.second == b.second && a.third < b.third)))
        val now3 = Triple(ty, tm, td)
        firstMatch("""\b(?:born|dob|d\.o\.b\.?|date\s+of\s+birth|birthday|bday|b'day)\s*(?:is\s+|was\s+|:\s*|-\s*)?(?:on\s+)?$fullDatePattern$END""", text)?.let { g ->
            val b = fullDate(g, 1, region) ?: return@let
            if (before(now3, b)) return@let
            val years = ty - b.first - (if (tm < b.second || (tm == b.second && td < b.third)) 1 else 0)
            if (years >= 130) return null
            return Conversions(g[0]!!.trim(), listOf(if (years == 1) "1 year old" else "$years years old"))
        }
        firstMatch("""\bsince\s+$fullDatePattern$END""", text)?.let { g ->
            val b = fullDate(g, 1, region) ?: return@let
            if (!before(b, now3)) return@let
            var years = ty - b.first
            var months = tm - b.second
            var days = td - b.third
            if (days < 0) {
                months -= 1
                days += daysIn(if (tm == 1) ty - 1 else ty, if (tm == 1) 12 else tm - 1)
            }
            if (months < 0) { years -= 1; months += 12 }
            fun plural(n: Int, word: String) = "$n $word" + if (n == 1) "" else "s"
            val said = when {
                years > 0 -> plural(years, "year") + (if (months > 0) " " + plural(months, "month") else "")
                months > 0 -> plural(months, "month") + (if (days > 0) " " + plural(days, "day") else "")
                else -> plural(days, "day")
            }
            return Conversions(g[0]!!.trim(), listOf(said))
        }
        return null
    }

    /** Whole numbers grouped the Indian way: 1,23,45,678. */
    fun indianGrouped(n: Double): String {
        val whole = Math.round(n).toString()
        if (whole.length <= 3) return whole
        var head = whole.dropLast(3)
        val groups = ArrayDeque<String>()
        while (head.length > 2) { groups.addFirst(head.takeLast(2)); head = head.dropLast(2) }
        if (head.isNotEmpty()) groups.addFirst(head)
        return groups.joinToString(",") + "," + whole.takeLast(3)
    }

    /** Money for pay and loans: cents under a hundred, whole above, rupees
     *  grouped in lakhs. */
    private fun wholeMoney(n: Double, symbol: String): String {
        if (n < 100) return billMoney(n, symbol)
        return if (symbol == "₹") "₹" + indianGrouped(n) else billMoney(Math.round(n).toDouble(), symbol)
    }

    /** One decimal at most: 54.1, 1.2, 3. */
    private fun oneDecimal(n: Double): String {
        val r = Math.round(n * 10) / 10.0
        return if (r == Math.floor(r)) r.toLong().toString() else r.toString()
    }

    /** Money said short: "$383k", "$1.2M", "₹54.1 lakh". */
    private fun shortMoney(n: Double, symbol: String): String {
        if (symbol == "₹") {
            if (n >= 1e7) return "₹" + oneDecimal(n / 1e7) + " crore"
            if (n >= 1e5) return "₹" + oneDecimal(n / 1e5) + " lakh"
            return wholeMoney(n, symbol)
        }
        if (n >= 1e6) return symbol + oneDecimal(n / 1e6) + "M"
        if (n >= 1e4) return symbol + Math.round(n / 1e3) + "k"
        return wholeMoney(n, symbol)
    }

    private val payWords = Regex("""\b(?:pay|pays|paid|paying|rate|salary|wage|wages|earn|earns|earning|earned|make|makes|making|charge|charges|charging|offer|offered|offering|job|gig|freelance|contract|income|hourly|ctc|package)\b""",
        RegexOption.IGNORE_CASE)

    /** "$45/hr" → $93,600/yr · $7,800/mo (40 hours a week); "$120k a year"
     *  → $57.69/hr · $10,000/mo; "18 LPA" → ₹1,50,000/mo. Without a currency
     *  sign the message has to be about pay. */
    fun payRate(asked: String): Conversions? {
        var about = payWords.containsMatchIn(asked)
        // A trailing "hourly", "monthly", "annually" asks which way to say it.
        var text = asked
        val tailWord = firstMatch("""\s+(?:in\s+|as\s+)?(?:hourly|monthly|annually|yearly|per\s+month|a\s+month)\??\s?$""", asked)?.get(0)
        if (tailWord != null &&
            Regex("""(?:/\s*|per\s+|an?\s+)(?:hr|hour|h|yr|year|annum)\s+\S+\??\s?$""", RegexOption.IGNORE_CASE).containsMatchIn(asked)) {
            text = asked.dropLast(tailWord.length)
            about = true   // asking it "annually" is talking pay
        }
        firstMatch("""(?<![\w.,])([$€£₹¥])?\s?(\d{1,4}(?:\.\d{1,2})?)\s*(?:/\s*(?:hr|hour|h)|an?\s+hour|per\s+hour|hourly)$END""", text)?.let { g ->
            val n = g[2]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return@let
            if (g[1] == null && !about) return@let
            val s = g[1] ?: ""
            val year = n * 2080
            return Conversions(g[0]!!.trim(), listOf("${wholeMoney(year, s)}/yr", "${wholeMoney(year / 12, s)}/mo"))
        }
        firstMatch("""(?<![\w.,])([$€£₹¥])?\s?(\d{1,3}(?:,\d{2,3})+|\d+(?:\.\d+)?)\s*(k|m)?\s*(?:/\s*(?:yr|year|y|annum)|(?:a|per)\s+(?:year|annum)|p\.?\s?a\.?|annually|yearly)$END""", text)?.let { g ->
            val base = number(g[2]) ?: return@let
            val scale = g[3]?.lowercase()
            val year = base * (if (scale == "k") 1e3 else if (scale == "m") 1e6 else 1.0)
            if (year < 1000 || (g[1] == null && !about)) return null
            val s = g[1] ?: ""
            return Conversions(g[0]!!.trim(), listOf("${wholeMoney(year / 2080, s)}/hr", "${wholeMoney(year / 12, s)}/mo"))
        }
        val g = firstMatch("""(?<![\w.,])(\d{1,3}(?:\.\d{1,2})?)\s*(?:lpa|l\.p\.a\.?|lakhs?\s+(?:per\s+annum|a\s+year|p\.?a\.?))$END""", text)
            ?: return null
        val lakhs = g[1]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val year = lakhs * 1e5
        return Conversions(g[0]!!.trim(), listOf("${wholeMoney(year / 12, "₹")}/mo", "${wholeMoney(year / 2080, "₹")}/hr"))
    }

    private val scaleWords = mapOf(
        "k" to 1e3, "m" to 1e6, "mn" to 1e6, "million" to 1e6, "b" to 1e9, "bn" to 1e9, "billion" to 1e9,
        "l" to 1e5, "lakh" to 1e5, "lakhs" to 1e5, "lac" to 1e5, "lacs" to 1e5, "cr" to 1e7, "crore" to 1e7, "crores" to 1e7,
    )
    /** An amount with its sign and its size word: "$300k", "50 lakh". Three groups. */
    private const val SCALED_AMOUNT = """([$€£₹¥])?\s?(\d{1,3}(?:,\d{2,3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(k|m|mn|million|b|bn|billion|l|lakhs?|lacs?|cr|crores?)?"""

    /** "$300k mortgage at 6.5% for 30 years" → $1,896/mo · $383k interest;
     *  "50 lakh home loan @ 8.5% 20 years" → ₹43,391/mo; "10k at 7% for 10
     *  years" → $19,672 · +$9,672 (grown once a year). */
    fun loan(text: String): Conversions? {
        val rate = """(\d{1,2}(?:\.\d{1,3})?)\s*%"""
        val term = """(\d{1,3})\s*(years?|yrs?|y|months?|mos?)"""
        val kinds = """(?:home\s+|car\s+|auto\s+|personal\s+|student\s+|education\s+)?(?:mortgage|loan|emi)"""
        val borrowing = Regex("""\b(?:mortgage|loan|emi|borrow\w*|owe|debt)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text)
        val patterns = listOf(
            """\b$kinds\s+(?:of\s+|for\s+|on\s+)?$SCALED_AMOUNT\s*(?:at|@)\s*$rate\s*(?:for|over)?\s*$term$END""" to true,
            """(?<![\w.,])$SCALED_AMOUNT\s+$kinds\s*(?:at|@)?\s*$rate\s*(?:for|over)?\s*$term$END""" to true,
            """(?<![\w.,])$SCALED_AMOUNT\s*(?:at|@)\s*$rate\s*(?:for|over)\s*$term$END""" to false,
            """\b(?:compound(?:ed)?|invest(?:ed)?|grow)\s+(?:of\s+)?$SCALED_AMOUNT\s*(?:at|@)?\s*$rate\s*(?:for|over)?\s*$term$END""" to false,
        )
        for ((p, borrowed) in patterns) {
            if (!borrowed && borrowing) continue
            val g = firstMatch(p, text) ?: continue
            val base = number(g[2]) ?: continue
            val size = g[3]?.lowercase() ?: ""
            val principal = base * (scaleWords[size] ?: 1.0)
            val r = g[4]?.toDoubleOrNull() ?: continue
            val t = g[5]?.toDoubleOrNull() ?: continue
            if (r <= 0 || r > 50 || t <= 0 || principal < 100) continue
            // Lakh and crore are rupees, said or not.
            val s = g[1] ?: if (size in setOf("l", "lakh", "lakhs", "lac", "lacs", "cr", "crore", "crores")) "₹" else ""
            val inMonths = g[6]!!.lowercase().startsWith("m")
            if (borrowed) {
                val n = if (inMonths) t else t * 12
                if (n > 600) continue
                val i = r / 100 / 12
                val pay = principal * i / (1 - Math.pow(1 + i, -n))
                return Conversions(g[0]!!.trim(), listOf("${wholeMoney(pay, s)}/mo", "${shortMoney(pay * n - principal, s)} interest"))
            }
            if (inMonths || t > 60) continue
            val total = principal * Math.pow(1 + r / 100, t)
            return Conversions(g[0]!!.trim(), listOf(wholeMoney(total, s), "+" + wholeMoney(total - principal, s)))
        }
        return null
    }

    private val vatRates = mapOf(
        "GB" to 20.0, "IE" to 23.0, "DE" to 19.0, "AT" to 20.0, "FR" to 20.0, "IT" to 22.0, "ES" to 21.0, "NL" to 21.0,
        "BE" to 21.0, "PT" to 23.0, "LU" to 17.0, "FI" to 25.5, "SE" to 25.0, "DK" to 25.0, "NO" to 25.0, "PL" to 23.0,
        "CH" to 8.1, "AE" to 5.0, "SA" to 15.0, "ZA" to 15.0,
    )
    private val gstRates = mapOf("AU" to 10.0, "NZ" to 15.0, "SG" to 9.0)
    private val euroRegions = setOf("IE", "DE", "AT", "FR", "IT", "ES", "NL", "BE", "PT", "LU", "FI")

    /** "£120 inc VAT" → £100 + £20 VAT; "€99 inkl. MwSt" at the rate where
     *  the phone is; "₹1,180 incl 18% GST". Where the rate depends on what
     *  is bought (India's GST, a US sales tax) it has to be typed. */
    fun taxInside(text: String, region: String?): Conversions? {
        val g = firstMatch("""(?<![\w.,])(?:([$€£₹])\s?$AMT|$AMT\s?([$€£₹])|$AMT)\s*(?:inc\.?|incl\.?|including|inkl\.?|inclusive\s+of|incl\.?\s+of)\s*(?:(\d{1,2}(?:\.\d+)?)\s*%\s*)?(vat|gst|mwst|tva|iva|btw|moms|tax)$END""", text)
            ?: return null
        val gross = number(g[2] ?: g[3] ?: g[5])?.takeIf { it > 0 } ?: return null
        val word = g[7]?.lowercase() ?: return null
        val symbol = g[1] ?: g[4] ?: ""
        val r = region?.uppercase() ?: ""
        var rate = g[6]?.toDoubleOrNull()
        if (rate == null && word != "tax") {
            rate = when {
                word == "gst" -> if (symbol.isEmpty() || symbol == "$") gstRates[r] else null
                symbol == "£" -> 20.0
                symbol == "€" -> if (r in euroRegions) vatRates[r] else null
                symbol.isEmpty() -> vatRates[r]
                else -> null
            }
        }
        if (rate == null || rate <= 0 || rate >= 100) return null
        val net = gross / (1 + rate / 100)
        val label = mapOf("vat" to "VAT", "gst" to "GST", "mwst" to "MwSt", "tva" to "TVA", "iva" to "IVA", "btw" to "BTW")[word] ?: word
        return Conversions(g[0]!!.trim(), listOf("${billMoney(net, symbol)} + ${billMoney(gross - net, symbol)} $label"))
    }

    /** "$12.99 for 24" → $0.54 each; "3 for $10" → $3.33 each; "₹300 for
     *  5 kg" → ₹60/kg; "$4 for 500 g" → $8/kg · $0.80/100 g. A price is
     *  needed: "table for 4" is a booking. */
    fun unitPrice(text: String): Conversions? {
        val weights = """(kg|kgs|g|gm|gms|grams?|lbs?|pounds?|oz|l|litres?|liters?|ml)"""
        var price: Double? = null
        var quantity: Double? = null
        var unit: String? = null
        var symbol = ""
        var source = ""
        val a = firstMatch("""([$€£₹¥])\s?$AMT\s+(?:for|per)\s+(\d+(?:\.\d+)?)\s*$weights$END""", text)
        val b = if (a == null) firstMatch("""(?<![\w.,])(\d+(?:\.\d+)?)\s*$weights\s+for\s+([$€£₹¥])\s?$AMT$END""", text) else null
        val c = if (a == null && b == null) firstMatch("""([$€£₹¥])\s?$AMT\s+for\s+(?:a\s+)?(\d{1,4}|dozen|pair)\s*(?:pack|pk|pcs|pieces|count|ct|items|units|cans|bottles)?$END""", text) else null
        val d = if (a == null && b == null && c == null) firstMatch("""(?<![\w.,$€£₹¥])(\d{1,4})\s+for\s+([$€£₹¥])\s?$AMT$END""", text) else null
        // "1.5kg for 9": a weight for a price, the sign left off (2026-10-08 probe).
        val e = if (a == null && b == null && c == null && d == null) firstMatch("""(?<![\w.,])(\d+(?:\.\d+)?)\s*$weights\s+for\s+$AMT$END""", text) else null
        // "3 pack for 12.99".
        val f = if (a == null && b == null && c == null && d == null && e == null)
            firstMatch("""(?<![\w.,$€£₹¥])(\d{1,3})\s*[- ]?(?:pack|pk|pcs|pieces|count|ct|cans|bottles)\s+(?:for|at|is|=)\s+([$€£₹¥])?\s?$AMT$END""", text) else null
        when {
            a != null -> { symbol = a[1] ?: ""; price = number(a[2]); quantity = a[3]?.toDoubleOrNull(); unit = a[4]; source = a[0]!!.trim() }
            b != null -> { symbol = b[3] ?: ""; price = number(b[4]); quantity = b[1]?.toDoubleOrNull(); unit = b[2]; source = b[0]!!.trim() }
            c != null -> {
                val q = c[3]!!.lowercase()
                symbol = c[1] ?: ""; price = number(c[2])
                quantity = if (q == "dozen") 12.0 else if (q == "pair") 2.0 else q.toDoubleOrNull()
                source = c[0]!!.trim()
            }
            d != null -> { symbol = d[2] ?: ""; price = number(d[3]); quantity = d[1]?.toDoubleOrNull(); source = d[0]!!.trim() }
            e != null -> { price = number(e[3]); quantity = e[1]?.toDoubleOrNull(); unit = e[2]; source = e[0]!!.trim() }
            f != null -> { symbol = f[2] ?: ""; price = number(f[3]); quantity = f[1]?.toDoubleOrNull(); source = f[0]!!.trim() }
        }
        val p = price?.takeIf { it > 0 } ?: return null
        val q = quantity?.takeIf { it > 0 } ?: return null
        fun per(amount: Double, label: String) = "${billMoney(p / amount, symbol)}$label"
        val u = unit?.lowercase()
        if (u == null) {
            if (q < 2 || p / q < 0.01) return null
            return Conversions(source, listOf(per(q, " each")))
        }
        val results = when (u) {
            "kg", "kgs" -> listOf(per(q, "/kg"))
            "g", "gm", "gms", "gram", "grams" -> listOf(per(q / 1000, "/kg"), per(q / 100, "/100 g"))
            "lb", "lbs", "pound", "pounds" -> listOf(per(q, "/lb"), per(q * 0.45359237, "/kg"))
            "oz" -> listOf(per(q, "/oz"), per(q * 28.349523125 / 100, "/100 g"))
            "ml" -> listOf(per(q / 1000, "/L"), per(q / 100, "/100 ml"))
            else -> listOf(per(q, "/L"))
        }
        return Conversions(source, results)
    }

    /** "+37.5%", "-20%": one decimal at most. */
    private fun percentChange(p: Double) = (if (p > 0) "+" else "-") + oneDecimal(kotlin.math.abs(p)) + "%"

    /** "went from $40 to $55" → +37.5% · +$15; "followers jumped from 1.2k
     *  to 3k" → +150%. A change needs its verb, or money on both sides:
     *  "from 9 to 5" is a working day. */
    fun change(text: String): Conversions? {
        val side = """([$€£₹¥])?\s?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(k|m)?"""
        val verbs = """(?:went|gone|grew|grown|rose|risen|jumped|dropped|fell|fallen|increased|decreased|climbed|raised|cut|surged|slipped|declined|spiked|up|down)"""
        val g = firstMatch("""\b$verbs\s+(?:from\s+)?$side\s+to\s+$side$END""", text)
            ?: firstMatch("""\bfrom\s+([$€£₹¥])\s?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(k|m)?\s+to\s+$side$END""", text)
            ?: return null
        fun scale(s: String?) = when (s?.lowercase()) { "k" -> 1e3; "m" -> 1e6; else -> 1.0 }
        val a = (number(g[2]) ?: return null) * scale(g[3])
        val b = (number(g[5]) ?: return null) * scale(g[6])
        if (a <= 0 || a == b) return null
        val results = mutableListOf(percentChange((b - a) / a * 100))
        (g[1] ?: g[4])?.let { s -> results += (if (b > a) "+" else "-") + billMoney(kotlin.math.abs(b - a), s) }
        return Conversions(g[0]!!.trim(), results)
    }

    /** "aspect ratio 1920x1080" → 16:9; "2560x1080 ratio" → ≈21:9. The
     *  word is needed: "10x20 cm" is a size. */
    fun ratio(text: String): Conversions? {
        val g = firstMatch("""\b(?:aspect(?:\s+ratio)?|ratio|resolution|res)\s*(?:of\s+|is\s+|:\s*|=\s*)?(\d{1,5})\s*[x×:]\s*(\d{1,5})$END""", text)
            ?: firstMatch("""(?<![\w.])(\d{1,5})\s*[x×]\s*(\d{1,5})\s+(?:aspect(?:\s+ratio)?|ratio|resolution)$END""", text)
            ?: return null
        val a = g[1]?.toIntOrNull()?.takeIf { it > 0 } ?: return null
        val b = g[2]?.toIntOrNull()?.takeIf { it > 0 } ?: return null
        tailrec fun gcd(x: Int, y: Int): Int = if (y == 0) x else gcd(y, x % y)
        val d = gcd(a, b)
        val x = a / d
        val y = b / d
        val said = when {
            x == 8 && y == 5 -> "16:10"
            x == 5 && y == 8 -> "10:16"
            x <= 21 && y <= 21 -> if (x == a && y == b) return null else "$x:$y"
            else -> {
                val value = a.toDouble() / b
                val named = listOf(1 to 1, 5 to 4, 4 to 3, 3 to 2, 16 to 10, 16 to 9, 2 to 1, 21 to 9, 32 to 9,
                    4 to 5, 3 to 4, 2 to 3, 10 to 16, 9 to 16, 9 to 21)
                val near = named.minByOrNull { kotlin.math.abs(it.first.toDouble() / it.second - value) }!!
                when {
                    kotlin.math.abs(near.first.toDouble() / near.second - value) / value < 0.03 -> "≈${near.first}:${near.second}"
                    value >= 1 -> String.format(java.util.Locale.US, "%.2f:1", value)
                    else -> String.format(java.util.Locale.US, "1:%.2f", 1 / value)
                }
            }
        }
        return Conversions(g[0]!!.trim(), listOf(said))
    }

    /** Grams in a US cup, from King Arthur Baking's ingredient weight chart. */
    private val cupGrams = mapOf(
        "all-purpose flour" to 120.0, "all purpose flour" to 120.0, "plain flour" to 120.0, "ap flour" to 120.0,
        "bread flour" to 120.0, "cake flour" to 120.0, "self-raising flour" to 120.0, "self raising flour" to 120.0,
        "self-rising flour" to 120.0, "flour" to 120.0, "maida" to 120.0, "whole wheat flour" to 113.0,
        "wholemeal flour" to 113.0, "atta" to 113.0, "almond flour" to 96.0, "almond meal" to 96.0, "semolina" to 163.0,
        "rice flour" to 142.0, "cornmeal" to 138.0, "cornstarch" to 112.0, "corn starch" to 112.0, "cornflour" to 112.0,
        "brown sugar" to 213.0, "powdered sugar" to 113.0, "icing sugar" to 113.0, "confectioners sugar" to 113.0,
        "confectioners' sugar" to 113.0, "sugar" to 198.0, "caster sugar" to 198.0, "butter" to 226.8, "honey" to 336.0,
        "maple syrup" to 312.0, "corn syrup" to 312.0, "molasses" to 340.0, "cocoa powder" to 84.0, "cocoa" to 84.0,
        "oats" to 89.0, "rolled oats" to 89.0, "oatmeal" to 89.0, "rice" to 198.0, "quinoa" to 177.0,
        "chocolate chips" to 170.0, "chocolate" to 170.0, "peanut butter" to 270.0, "cheese" to 113.0, "cheddar" to 113.0,
        "mozzarella" to 113.0, "parmesan" to 100.0, "cream cheese" to 227.0, "sour cream" to 227.0, "yogurt" to 227.0,
        "yoghurt" to 227.0, "ricotta" to 227.0, "raisins" to 149.0, "walnuts" to 113.0, "pecans" to 105.0,
        "almonds" to 142.0, "coconut" to 85.0, "breadcrumbs" to 112.0, "bread crumbs" to 112.0, "salt" to 288.0,
        "baking powder" to 192.0, "baking soda" to 288.0, "bicarbonate of soda" to 288.0, "yeast" to 144.0,
        "banana" to 227.0, "pumpkin puree" to 227.0, "applesauce" to 255.0,
    )
    /** Poured by volume: millilitres say it best. */
    private val pouredLiquids = setOf(
        "milk", "water", "cream", "heavy cream", "whipping cream", "buttermilk", "oil", "olive oil", "vegetable oil",
        "vinegar", "juice", "lemon juice", "lime juice", "orange juice", "stock", "broth", "wine", "coconut milk",
        "vanilla", "vanilla extract", "soy sauce",
    )
    private const val KITCHEN_WORDS = """(?:(?:packed|sifted|softened|melted|unsalted|salted|granulated|white|light|dark|cold|warm|chopped|grated|shredded|mashed|dried|fresh|plain|raw|uncooked|dry|fine|ground|light\s+brown|dark\s+brown)\s+)*"""
    private val ingredientNames: String by lazy {
        (cupGrams.keys + pouredLiquids).sortedWith(compareByDescending<String> { it.length }.thenBy { it })
            .joinToString("|") { Regex.escape(it) }
    }

    /** Gas marks with their oven temperatures in °C and °F. */
    private val gasMarks = listOf(
        Triple("¼", 110, 225), Triple("½", 120, 250), Triple("1", 140, 275), Triple("2", 150, 300), Triple("3", 170, 325),
        Triple("4", 180, 350), Triple("5", 190, 375), Triple("6", 200, 400), Triple("7", 220, 425), Triple("8", 230, 450),
        Triple("9", 240, 475),
    )

    /** Grams as a cook writes them: "240 g", "4 g", "1.5 g". */
    private fun gramsText(g: Double) = if (g >= 10) "${Math.round(g)} g" else "${oneDecimal(g)} g"

    /** "1⅔ cups", "¾ cup", "3 tbsp", "½ tsp": the nearest a cup measures. */
    private fun cupsText(grams: Double, perCup: Double): String {
        fun nice(x: Double): Pair<Int, String> {
            val parts = listOf(0.0 to "", 0.25 to "¼", 1.0 / 3 to "⅓", 0.5 to "½", 2.0 / 3 to "⅔", 0.75 to "¾", 1.0 to "")
            var whole = kotlin.math.floor(x).toInt()
            val near = parts.minByOrNull { kotlin.math.abs(it.first - (x - whole)) }!!
            if (near.first == 1.0) whole += 1
            return whole to (if (near.first == 1.0) "" else near.second)
        }
        val cups = grams / perCup
        val (wf, unit) = when {
            cups >= 0.25 -> nice(cups) to "cup"
            cups * 16 >= 1 -> nice(cups * 16) to "tbsp"
            else -> nice(cups * 48) to "tsp"
        }
        val (w, f) = wf
        val amount = (if (w > 0) "$w" else "") + f
        val named = if (unit == "cup" && (w > 1 || (w == 1 && f.isNotEmpty()))) "cups" else unit
        return "${amount.ifEmpty { "0" }} $named"
    }

    /** "2 cups flour" → 240 g · 8.47 oz (King Arthur's weights); "1 cup
     *  milk" → 237 ml; in the US "200 g flour" → 1⅔ cups; "gas mark 4" →
     *  180°C · 350°F; "bake at 350" → 180°C · gas mark 4. */
    fun cooking(text: String, region: String?): Conversions? {
        val units = """(cups?|c\.|tbsps?|tablespoons?|tbs|tbl|tsps?|teaspoons?|sticks?)"""
        firstMatch("""(?<![\w.,/])$STRIP_AMOUNT\s*$units\s+(?:of\s+)?$KITCHEN_WORDS($ingredientNames)$END""", text)?.let { g ->
            val n = g[1]?.let { amount(it) }?.takeIf { it > 0 } ?: return@let
            val u = g[2]!!.lowercase()
            val name = g[3]!!.lowercase()
            val cups = when {
                u.startsWith("c") -> n
                u.startsWith("tb") || u.startsWith("tablespoon") -> n / 16
                u.startsWith("ts") || u.startsWith("teaspoon") -> n / 48
                name == "butter" -> n / 2
                else -> return null
            }
            if (name in pouredLiquids) {
                val ml = cups * 236.5882365
                return Conversions(g[0]!!.trim(), listOf(if (ml < 1000) stripNamed(ml, "ml") else stripNamed(ml / 1000, "litre")))
            }
            val perCup = cupGrams[name] ?: return null
            val grams = cups * perCup
            return Conversions(g[0]!!.trim(), listOf(gramsText(grams), stripNamed(grams / 28.349523125, "oz")))
        }
        if (region.equals("US", ignoreCase = true)) {
            firstMatch("""(?<![\w.,/])(\d+(?:\.\d+)?)\s*(g|gm|gms|grams?|kg|kgs)\s+(?:of\s+)?$KITCHEN_WORDS($ingredientNames)$END""", text)?.let { g ->
                val n = g[1]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return@let
                val perCup = cupGrams[g[3]!!.lowercase()] ?: return@let
                val grams = if (g[2]!!.lowercase().startsWith("k")) n * 1000 else n
                return Conversions(g[0]!!.trim(), listOf(cupsText(grams, perCup), stripNamed(grams / 28.349523125, "oz")))
            }
        }
        firstMatch("""\bgas\s+mark\s+(1/4|1/2|¼|½|[1-9])$END""", text)?.let { g ->
            val mark = g[1]!!.replace("1/4", "¼").replace("1/2", "½")
            val gm = gasMarks.firstOrNull { it.first == mark } ?: return null
            return Conversions(g[0]!!.trim(), listOf("${gm.second}°C", "${gm.third}°F"))
        }
        val g = firstMatch("""\b(?:oven|bake|baking|preheat(?:\s+(?:the\s+)?oven)?|roast|roasting)\s+(?:it\s+)?(?:at|to|on)\s+(\d{2,3})\s*(?:degrees?|deg|°)?$END""", text)
            ?: return null
        val v = g[1]?.toIntOrNull() ?: return null
        // 300 and up is Fahrenheit, 250 and under Celsius; between, the
        // scale the phone's country bakes in.
        val fahrenheit = v >= 300 || (v > 250 && (region?.uppercase() ?: "") in setOf("US", "BS", "BZ", "KY", "PR", "PW"))
        fun five(x: Double) = (Math.round(x / 5) * 5).toInt()
        if (fahrenheit) {
            if (v > 550) return null
            val gm = gasMarks.firstOrNull { it.third == v }
            val c = gm?.second ?: five((v - 32) * 5.0 / 9)
            return Conversions(g[0]!!.trim(), listOf("$c°C") + listOfNotNull(gm?.let { "gas mark ${it.first}" }))
        }
        if (v < 90) return null
        val gm = gasMarks.firstOrNull { it.second == v }
        val f = gm?.third ?: five(v * 9.0 / 5 + 32)
        return Conversions(g[0]!!.trim(), listOf("$f°F") + listOfNotNull(gm?.let { "gas mark ${it.first}" }))
    }

    /** "30 mpg" → 7.84 L/100 km · 12.8 km/L; "6.5 L/100km" → 36.2 mpg;
     *  "15 kmpl" → 35.3 mpg. Imperial gallons in Britain. */
    fun fuel(text: String, region: String?): Conversions? {
        val g = firstMatch("""(?<![\w.])(\d{1,3}(?:\.\d+)?)\s*(mpg|miles\s+per\s+gallon|l/100\s?km|l\s+per\s+100\s?km|lit(?:re|er)s?\s+per\s+100\s?km|km/l|kmpl|km\s+per\s+lit(?:re|er)|kpl)$END""", text)
            ?: return null
        val n = g[1]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val u = g[2]!!.lowercase()
        val uk = region.equals("GB", ignoreCase = true)
        val litresTimesMpg = if (uk) 282.480936 else 235.214583
        val kmlPerMpg = if (uk) 0.35400619 else 0.42514371
        val results = when {
            u.startsWith("mpg") || u.startsWith("miles") ->
                listOf("${stripNumber(litresTimesMpg / n)} L/100 km", "${stripNumber(n * kmlPerMpg)} km/L")
            u.startsWith("l") -> listOf("${stripNumber(litresTimesMpg / n)} mpg", "${stripNumber(100 / n)} km/L")
            else -> listOf("${stripNumber(n / kmlPerMpg)} mpg", "${stripNumber(100 / n)} L/100 km")
        }
        return Conversions(g[0]!!.trim(), results)
    }

    /** "5:15", "1:05:30": minutes and seconds, hours when there are some. */
    private fun durationClock(seconds: Double): String {
        val s = Math.round(seconds).toInt()
        fun pad(n: Int) = if (n < 10) "0$n" else "$n"
        return if (s >= 3600) "${s / 3600}:${pad(s % 3600 / 60)}:${pad(s % 60)}" else "${s / 60}:${pad(s % 60)}"
    }

    /** "ran 10k in 52:30" → 5:15 /km · 8:27 /mi; "half marathon in 1:45:00";
     *  "rode 40 km in 1h 20m" → 30 km/h · 18.6 mph; "5:30/km" → 8:51 /mi ·
     *  27:30 for 5k. A time is needed: "run 5k this morning" is a plan. */
    fun pace(text: String): Conversions? {
        val dist = """(half[\s-]?marathon|full\s+marathon|marathon|half|(\d{1,3}(?:\.\d+)?)\s*(k|km|kms|kilomet(?:er|re)s?|mi|miles?))"""
        val time = """(?:(\d{1,2}):([0-5]\d)(?::([0-5]\d))?|(\d{1,3})\s*(?:min|mins|minutes)|(\d)\s*(?:h|hr|hrs|hours?)\s*(\d{1,2})\s*(?:m|min|mins)?)"""
        firstMatch("""\b(?:(ran|run|running|did|finished|done|completed|walked|cycled|rode|biked)\s+)?(?:a\s+|the\s+|my\s+)?$dist\s+in\s+$time$END""", text)?.let { g ->
            val d = g[2]!!.lowercase()
            val km = when {
                d.startsWith("half") -> 21.0975
                "marathon" in d -> 42.195
                else -> {
                    val n = g[3]?.toDoubleOrNull() ?: return null
                    if (g[4]!!.lowercase().startsWith("mi")) n * 1.609344 else n
                }
            }
            if (km <= 0) return null
            val riding = g[1]?.lowercase() in setOf("cycled", "rode", "biked")
            val a = g[5]?.toDoubleOrNull()
            val b = g[6]?.toDoubleOrNull()
            val options = when {
                a != null && b != null -> {
                    val c = g[7]?.toDoubleOrNull()
                    if (c != null) listOf(a * 3600 + b * 60 + c)
                    else if (km >= 21 || riding) listOf(a * 3600 + b * 60, a * 60 + b) else listOf(a * 60 + b, a * 3600 + b * 60)
                }
                g[8] != null -> listOf(g[8]!!.toDouble() * 60)
                g[9] != null && g[10] != null -> listOf(g[9]!!.toDouble() * 3600 + g[10]!!.toDouble() * 60)
                else -> emptyList()
            }
            if (riding) {
                val secs = options.firstOrNull { km / (it / 3600) in 5.0..80.0 } ?: return null
                val kmh = km / (secs / 3600)
                return Conversions(g[0]!!.trim(), listOf("${stripNumber(kmh)} km/h", "${stripNumber(kmh / 1.609344)} mph"))
            }
            val secs = options.firstOrNull { it / km in 120.0..1200.0 } ?: return null
            return Conversions(g[0]!!.trim(), listOf(durationClock(secs / km) + " /km", durationClock(secs / km * 1.609344) + " /mi"))
        }
        val g = firstMatch("""(?<![\d:])(\d{1,2}):([0-5]\d)\s*(?:/\s*|per\s+|a\s+)(km|k|kilomet(?:er|re)s?|mi|miles?)$END""", text) ?: return null
        val m = g[1]?.toDoubleOrNull() ?: return null
        val s = g[2]?.toDoubleOrNull() ?: return null
        val mile = g[3]!!.lowercase().startsWith("mi")
        val perKm = if (mile) (m * 60 + s) / 1.609344 else m * 60 + s
        if (perKm < 120 || perKm > 1200) return null
        val other = if (mile) durationClock(perKm) + " /km" else durationClock(perKm * 1.609344) + " /mi"
        return Conversions(g[0]!!.trim(), listOf(other, durationClock(perKm * 5) + " for 5k"))
    }

    /** "12 s", "6 min 16 s", "1 h 23 min", "2 days 3 h". */
    private fun durationWords(seconds: Double): String {
        val s = Math.round(seconds).toInt()
        if (s < 60) return "$s s"
        if (s < 3600) return if (s % 60 == 0) "${s / 60} min" else "${s / 60} min ${s % 60} s"
        val minutes = Math.round(seconds / 60).toInt()
        if (minutes < 1440) return if (minutes % 60 == 0) "${minutes / 60} h" else "${minutes / 60} h ${minutes % 60} min"
        val hours = Math.round(seconds / 3600).toInt()
        return "${hours / 24} day${if (hours / 24 == 1) "" else "s"}" + (if (hours % 24 > 0) " ${hours % 24} h" else "")
    }

    /** "4.7 GB at 100 Mbps" → ≈ 6 min 16 s. "Mbps" and "Mb/s" are bits,
     *  "MB/s" and "MBps" bytes (and "mb/s", as download managers write it). */
    fun download(text: String): Conversions? {
        val g = firstMatch("""(?<![\w.])(\d+(?:\.\d+)?)\s*(kb|mb|gb|tb)\s+(?:at|@|on|with|over|via)\s+(\d+(?:\.\d+)?)\s*(kbps|mbps|gbps|kb/s|mb/s|gb/s|kbit/s|mbit/s|gbit/s)$END""", text)
            ?: return null
        val size = g[1]?.toDoubleOrNull() ?: return null
        val speed = g[3]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val speedUnit = g[4] ?: return null
        if (speedUnit.length < 4) return null
        val bytes = size * (mapOf("kb" to 1e3, "mb" to 1e6, "gb" to 1e9, "tb" to 1e12)[g[2]!!.lowercase()] ?: 1.0)
        val scale = when (speedUnit[0].lowercaseChar()) { 'k' -> 1e3; 'm' -> 1e6; else -> 1e9 }
        val inBytes = "bit" !in speedUnit.lowercase() &&
            (speedUnit[1] == 'B' || (speedUnit.endsWith("/s") && speedUnit == speedUnit.lowercase()))
        val seconds = bytes * 8 / (speed * scale * (if (inBytes) 8 else 1))
        if (seconds < 1 || seconds >= 30 * 86400) return null
        return Conversions(g[0]!!.trim(), listOf("≈ " + durationWords(seconds)))
    }

    /** A shorthand's text with its blanks filled, as Raycast's snippets
     *  have them: {date}, {date+2d}, {date-1w}, {tomorrow}, {yesterday},
     *  {time}, {day}, {clipboard} and {cursor}, where typing goes on (the
     *  first one). The second is how far before the end the cursor ends, in
     *  UTF-16 units. A blank it doesn't know stays. */
    fun fillIn(template: String, now: java.time.Instant = java.time.Instant.now(),
               here: java.time.ZoneId = java.time.ZoneId.systemDefault(),
               region: String? = java.util.Locale.getDefault().country,
               clipboard: () -> String? = { null }): Pair<String, Int> {
        if ('{' !in template) return template to 0
        val re = Regex("""\{\s*(date|time|day|tomorrow|yesterday|clipboard|cursor)(?:\s*([+-])\s*(\d{1,3})\s*([dw]))?\s*\}""",
            RegexOption.IGNORE_CASE)
        val at = now.atZone(here)
        val today = at.toLocalDate()
        val out = StringBuilder()
        var cursor = -1
        var last = 0
        for (m in re.findAll(template)) {
            out.append(template, last, m.range.first)
            last = m.range.last + 1
            val g = m.groups
            when (val name = g[1]!!.value.lowercase()) {
                "cursor" -> if (cursor < 0) cursor = out.length
                "clipboard" -> out.append(clipboard() ?: "")
                "time" -> out.append(java.time.format.DateTimeFormatter.ofPattern("h:mm a", java.util.Locale.US).format(at).replace('\u202F', ' '))
                "day" -> out.append(java.time.format.DateTimeFormatter.ofPattern("EEEE", java.util.Locale.US).format(at))
                else -> {
                    var days = if (name == "tomorrow") 1L else if (name == "yesterday") -1L else 0L
                    g[3]?.value?.toLongOrNull()?.let { n ->
                        days += (if (g[2]?.value == "-") -1 else 1) * n * (if (g[4]?.value?.lowercase() == "w") 7 else 1)
                    }
                    out.append(dayName(today.plusDays(days), today, region))
                }
            }
        }
        out.append(template, last, template.length)
        val text = out.toString()
        return text to (if (cursor < 0) 0 else text.length - cursor)
    }

    /** The keyboard's draw for the next coin, die or pick: the same until
     *  one is used, so the answer can't change under the finger. */
    var luck: ULong = kotlin.random.Random.nextLong().toULong() or 1UL

    /** A number below n from what was asked and the draw (FNV-1a, then
     *  SplitMix64: the same on both keyboards). */
    fun lucky(asked: String, n: Int, salt: ULong = 0UL): Int {
        var h = 0xcbf29ce484222325UL
        for (b in asked.lowercase().toByteArray(Charsets.UTF_8)) h = (h xor (b.toULong() and 0xFFUL)) * 0x100000001b3UL
        var z = (h xor luck xor salt) + 0x9E3779B97F4A7C15UL
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9UL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBUL
        z = z xor (z shr 31)
        return (z % n.toULong()).toInt()
    }

    /** "flip a coin" → 🪙 Heads; "roll a die" → 🎲 4, "roll two dice" →
     *  🎲 3 + 5 = 8, "roll a d20"; "pick a number between 1 and 10" → 🎲 7;
     *  "pick one: pizza, sushi or tacos" → 🎯 sushi; rock, paper, scissors.
     *  A tap adds it after; the next draw is new. */
    fun luckAnswer(text: String): Conversions? {
        fun said(g: List<String?>, result: String) = Conversions(g[0]!!.trim(), listOf(result), hows = listOf(Insertion.AFTER))
        firstMatch("""\b(?:flip\s+a\s+coin|coin\s+(?:flip|toss)|toss\s+a\s+coin|heads\s+or\s+tails)$END""", text)?.let {
            return said(it, if (lucky("coin", 2) == 0) "🪙 Heads" else "🪙 Tails")
        }
        firstMatch("""\b(?:rock\s*,?\s*paper\s*,?\s*(?:or\s+|and\s+)?scissors|rps)$END""", text)?.let {
            return said(it, listOf("✊ Rock", "✋ Paper", "✌️ Scissors")[lucky("rps", 3)])
        }
        firstMatch("""\broll\s+(?:(a|an|one|the|two|three|1|2|3)\s+)?(?:dice|die|d(4|6|8|10|12|20|100))$END""", text)?.let { g ->
            val count = mapOf("two" to 2, "2" to 2, "three" to 3, "3" to 3)[g[1]?.lowercase()] ?: 1
            val sides = g[2]?.toIntOrNull() ?: 6
            val rolls = (0 until count).map { lucky("die", sides, it.toULong()) + 1 }
            return said(g, "🎲 " + if (count == 1) "${rolls[0]}" else rolls.joinToString(" + ") + " = ${rolls.sum()}")
        }
        (firstMatch("""\b(?:pick|choose|give\s+me|random)\s+(?:a\s+)?(?:random\s+)?number\s+(?:between|from)\s+(-?\d{1,6})\s+(?:and|to|-)\s+(-?\d{1,6})$END""", text)
            ?: firstMatch("""\brandom\s+number\s+(-?\d{1,6})\s*(?:-|to)\s*(-?\d{1,6})$END""", text))?.let { g ->
            val a = g[1]?.toIntOrNull() ?: return@let
            val b = g[2]?.toIntOrNull() ?: return@let
            if (a == b) return@let
            val lo = minOf(a, b)
            val hi = maxOf(a, b)
            return said(g, "🎲 ${lo + lucky("number $lo $hi", hi - lo + 1)}")
        }
        val g = firstMatch("""\b(?:pick|choose)\s+(?:one|1|for\s+me|from|between|among)\s*[:\-–]?\s*(.+?)$END""", text)
            ?: firstMatch("""\bdecide\s+between\s+(.+?)$END""", text) ?: return null
        val items = (g[1] ?: return null).replace(Regex("""\s*(?:,|/|\bor\b|\band\b|\bvs\.?)\s*""", RegexOption.IGNORE_CASE), "\n")
            .split("\n").map { it.trim() }.filter { it.isNotEmpty() }
        if (items.size < 2 || items.size > 8 || items.any { it.length > 40 || it.split(" ").size > 5 }) return null
        return said(g, "🎯 " + items[lucky(items.joinToString("|"), items.size)])
    }

    // MARK: more everyday answers (2026-10-08 probe of 150 messages; Smart.swift twins)

    /** The zone a place or abbreviation names ("tokyo", "ist", "new york"). */
    private fun namedZone(name: String, region: String?): java.time.ZoneId? {
        val key = name.lowercase().trim()
        val r = region?.uppercase()
        var id = zoneNames[key] ?: zoneNames["$key time"] ?: ""
        if (key == "cst" && r == "CN") id = "Asia/Shanghai"
        if (key == "ist" && r == "IE") id = "Europe/Dublin"
        if (key == "ist" && r == "IL") id = "Asia/Jerusalem"
        return runCatching { java.time.ZoneId.of(id) }.getOrNull()
    }

    /** Swift's capitalized: each word's first letter up, the rest down. */
    private fun capitalizedWords(s: String): String =
        s.split(" ").joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.uppercase() } }

    private fun placeLabel(key: String): String =
        if (key.length <= 4 && zoneNames[key] != null && !key.contains(' ')) key.uppercase() else capitalizedWords(key)

    /** "time difference with london", "how far ahead is tokyo" → "Tokyo is
     *  13h ahead" from where the phone is. */
    fun timeDifference(text: String, now: java.time.Instant = java.time.Instant.now(),
                       here: java.time.ZoneId = java.time.ZoneId.systemDefault(),
                       region: String? = java.util.Locale.getDefault().country): Conversions? {
        // "pst to ist", "est vs gmt": how far apart two zones are (iOS 10-14).
        firstMatch("""^\s*(?:what'?s\s+|whats\s+)?([a-z]{2,4})\s+(?:to|vs\.?|versus|and)\s+([a-z]{2,4})(?:\s+(?:time\s+)?difference)?\??\s?$""", text)?.let { g ->
            val a = g[1]?.lowercase() ?: return@let
            val b = g[2]?.lowercase() ?: return@let
            if (a == b) return@let
            val za = namedZone(a, region) ?: return@let
            val zb = namedZone(b, region) ?: return@let
            val diff = zb.rules.getOffset(now).totalSeconds - za.rules.getOffset(now).totalSeconds
            val mins = kotlin.math.abs(diff) / 60
            val gap = if (mins % 60 == 0) "${mins / 60}h" else "${mins / 60}h ${mins % 60}m"
            val said = if (diff == 0) "${b.uppercase()} = ${a.uppercase()}"
                else "${b.uppercase()} is $gap ${if (diff > 0) "ahead of" else "behind"} ${a.uppercase()}"
            return Conversions(g[0]!!.trim(), listOf(said))
        }
        val g = firstMatch("""\b(?:time\s+(?:difference|diff|gap)\s+(?:with|to|from|for|in|between\s+(?:us|here)\s+and)|how\s+(?:many\s+hours\s+|far\s+)?(?:ahead|behind)\s+is)\s+([a-z][a-z .]{1,30}?)\??\s?$""", text)
            ?: return null
        val name = g[1]?.lowercase()?.trim() ?: return null
        val there = namedZone(name, region) ?: return null
        val diff = there.rules.getOffset(now).totalSeconds - here.rules.getOffset(now).totalSeconds
        val label = placeLabel(name)
        if (diff == 0) return Conversions(g[0]!!.trim(), listOf("$label: same time"))
        val mins = kotlin.math.abs(diff) / 60
        val gap = if (mins % 60 == 0) "${mins / 60}h" else "${mins / 60}h ${mins % 60}m"
        return Conversions(g[0]!!.trim(), listOf("$label is $gap ${if (diff > 0) "ahead" else "behind"}"))
    }

    /** "100f in c", "30 c to f", "-40 celsius in fahrenheit": a temperature
     *  asked for in the other scale, without the degree sign. */
    fun degreesAsked(text: String): Conversions? {
        val g = firstMatch("""(?<![\w.])(-?\d{1,4}(?:\.\d+)?)\s*°?\s*(f|c|fahrenheit|celsius|centigrade)(?:\s+oven)?\s+(?:in|to|into|as)\s+°?(c|f|celsius|fahrenheit|centigrade)\??\s?$""", text)
            ?: return null
        val v = g[1]?.toDoubleOrNull() ?: return null
        val fromF = g[2]?.lowercase()?.firstOrNull() == 'f'
        val toF = g[3]?.lowercase()?.firstOrNull() == 'f'
        if (fromF == toF) return null
        val out = if (toF) v * 9 / 5 + 32 else (v - 32) * 5 / 9
        return Conversions(g[0]!!.trim(), listOf(oneDecimal(out) + (if (toF) "°F" else "°C")))
    }

    // MARK: durations, kitchen volumes and writing help (iOS 10-14 third probe; Smart.swift twins)

    /** "90 minutes in hours" → 1.5 h; "2 hours 45 minutes in minutes" → 165 min;
     *  "3.5 hours in minutes" → 210 min. */
    fun duration(text: String): Conversions? {
        val g = firstMatch("""(?<![\w.])(?:(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\s*(?:and\s+)?)?(?:(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|m))?\s+(?:in|to|into|as)\s+(hours?|hrs?|minutes?|mins?|seconds?|secs?)\??\s?$""", text)
            ?: return null
        if (g[1] == null && g[2] == null) return null
        val unit = g[3]?.lowercase() ?: return null
        val minutes = (g[1]?.toDoubleOrNull() ?: 0.0) * 60 + (g[2]?.toDoubleOrNull() ?: 0.0)
        if (minutes <= 0) return null
        val said = when {
            unit.startsWith("h") -> {
                if (g[2] == null) return null   // "2 hours in hours" says nothing
                oneDecimal(minutes / 60) + " h"
            }
            unit.startsWith("m") -> {
                if (g[1] == null) return null
                "${Math.round(minutes)} min"
            }
            else -> "${Math.round(minutes * 60)} s"
        }
        return Conversions(g[0]!!.trim(), listOf(said))
    }

    private val kitchenMl = mapOf(
        "oz" to 29.5735, "fl oz" to 29.5735, "floz" to 29.5735, "cup" to 236.588, "cups" to 236.588,
        "pint" to 473.176, "pints" to 473.176, "quart" to 946.353, "quarts" to 946.353,
        "gallon" to 3785.41, "gallons" to 3785.41, "tbsp" to 14.7868, "tsp" to 4.92892,
    )

    /** US kitchen volumes asked in millilitres or litres: "16 oz in ml" (a
     *  volume asked as one is fluid ounces), "a cup in ml", "2 pints in litres". */
    fun kitchenVolume(text: String): Conversions? {
        val g = firstMatch("""(?<![\w.])(\d+(?:\.\d+)?|an?|one|half\s+an?)\s*(fl\s*oz|floz|oz|cups?|pints?|quarts?|gallons?|tbsp|tsp)\s+(?:in|to|into|as)\s+(ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)\??\s?$""", text)
            ?: return null
        val raw = g[1]?.lowercase() ?: return null
        val unit = g[2]?.lowercase()?.replace(" ", "") ?: return null
        val per = kitchenMl[unit] ?: kitchenMl[unit.replace("floz", "oz")] ?: return null
        val count = raw.toDoubleOrNull() ?: if (raw.startsWith("half")) 0.5 else 1.0
        val total = count * per
        val toLitres = (g[3] ?: "").lowercase().startsWith("l")
        val said = if (toLitres) String.format(java.util.Locale.US, "%.2f L", total / 1000).replace(".00", "")
            else "${Math.round(total)} ml"
        return Conversions(g[0]!!.trim(), listOf(said))
    }

    /** Words people mix up: "is it affect or effect", "their there or they're". */
    private val confusions: List<Pair<Set<String>, String>> = listOf(
        setOf("affect", "effect") to "affect: to change (it affects me) · effect: the result (the effect)",
        setOf("their", "there", "they're") to "their: belongs to them · there: a place · they're: they are",
        setOf("your", "you're") to "your: belongs to you · you're: you are",
        setOf("its", "it's") to "its: belongs to it · it's: it is",
        setOf("then", "than") to "then: next, at that time · than: comparing (bigger than)",
        setOf("lose", "loose") to "lose: to misplace or not win · loose: not tight",
        setOf("fewer", "less") to "fewer: things you count · less: amounts you don't",
        setOf("who", "whom") to "who: does it (who called?) · whom: has it done to them (to whom)",
        setOf("lie", "lay") to "lie: to recline (I lie down) · lay: to put something (lay it down)",
        setOf("ie", "eg", "i.e.", "e.g.") to "i.e.: that is (exactly) · e.g.: for example",
        setOf("to", "too", "two") to "to: direction · too: also, very · two: 2",
        setOf("accept", "except") to "accept: to receive · except: apart from",
        setOf("advice", "advise") to "advice: the noun · advise: the verb",
        setOf("principal", "principle") to "principal: main, or a school head · principle: a rule or belief",
        setOf("stationary", "stationery") to "stationary: not moving · stationery: paper and pens",
        setOf("compliment", "complement") to "compliment: praise · complement: complete, go well with",
        setOf("weather", "whether") to "weather: rain or sun · whether: if",
        setOf("loose", "lose") to "lose: to misplace or not win · loose: not tight",
    )

    /** Irregular past tenses: "past tense of run" → ran, run. */
    private val pastTenses = mapOf(
        "be" to "was / were · been", "begin" to "began · begun", "break" to "broke · broken", "bring" to "brought · brought",
        "buy" to "bought · bought", "catch" to "caught · caught", "choose" to "chose · chosen", "come" to "came · come",
        "cost" to "cost · cost", "cut" to "cut · cut", "do" to "did · done", "draw" to "drew · drawn", "drink" to "drank · drunk",
        "drive" to "drove · driven", "eat" to "ate · eaten", "fall" to "fell · fallen", "feel" to "felt · felt", "fight" to "fought · fought",
        "find" to "found · found", "fly" to "flew · flown", "forget" to "forgot · forgotten", "forgive" to "forgave · forgiven",
        "freeze" to "froze · frozen", "get" to "got · got / gotten", "give" to "gave · given", "go" to "went · gone", "grow" to "grew · grown",
        "hang" to "hung · hung", "have" to "had · had", "hear" to "heard · heard", "hide" to "hid · hidden", "hit" to "hit · hit",
        "hold" to "held · held", "hurt" to "hurt · hurt", "keep" to "kept · kept", "know" to "knew · known", "lay" to "laid · laid",
        "lead" to "led · led", "leave" to "left · left", "lend" to "lent · lent", "let" to "let · let", "lie" to "lay · lain",
        "lose" to "lost · lost", "make" to "made · made", "mean" to "meant · meant", "meet" to "met · met", "pay" to "paid · paid",
        "put" to "put · put", "quit" to "quit · quit", "read" to "read · read", "ride" to "rode · ridden", "ring" to "rang · rung",
        "rise" to "rose · risen", "run" to "ran · run", "say" to "said · said", "see" to "saw · seen", "sell" to "sold · sold",
        "send" to "sent · sent", "set" to "set · set", "shake" to "shook · shaken", "shine" to "shone · shone", "shoot" to "shot · shot",
        "show" to "showed · shown", "shut" to "shut · shut", "sing" to "sang · sung", "sink" to "sank · sunk", "sit" to "sat · sat",
        "sleep" to "slept · slept", "speak" to "spoke · spoken", "spend" to "spent · spent", "stand" to "stood · stood",
        "steal" to "stole · stolen", "stick" to "stuck · stuck", "sting" to "stung · stung", "strike" to "struck · struck",
        "swear" to "swore · sworn", "swim" to "swam · swum", "take" to "took · taken", "teach" to "taught · taught",
        "tear" to "tore · torn", "tell" to "told · told", "think" to "thought · thought", "throw" to "threw · thrown",
        "understand" to "understood · understood", "wake" to "woke · woken", "wear" to "wore · worn", "win" to "won · won",
        "write" to "wrote · written", "dive" to "dove / dived · dived", "lit" to "lit · lit", "light" to "lit · lit",
        "seek" to "sought · sought", "bite" to "bit · bitten", "blow" to "blew · blown", "build" to "built · built",
        "burn" to "burned / burnt · burned / burnt", "dream" to "dreamed / dreamt · dreamed / dreamt", "spell" to "spelled / spelt · spelled / spelt",
    )

    /** Irregular plurals: "plural of cactus" → cacti (or cactuses). */
    private val plurals = mapOf(
        "cactus" to "cacti (or cactuses)", "child" to "children", "person" to "people", "man" to "men", "woman" to "women",
        "mouse" to "mice", "goose" to "geese", "tooth" to "teeth", "foot" to "feet", "ox" to "oxen", "fish" to "fish",
        "sheep" to "sheep", "deer" to "deer", "moose" to "moose", "series" to "series", "species" to "species",
        "criterion" to "criteria", "phenomenon" to "phenomena", "datum" to "data", "medium" to "media (or mediums)",
        "analysis" to "analyses", "crisis" to "crises", "thesis" to "theses", "hypothesis" to "hypotheses",
        "basis" to "bases", "diagnosis" to "diagnoses", "fungus" to "fungi", "nucleus" to "nuclei", "radius" to "radii",
        "stimulus" to "stimuli", "syllabus" to "syllabi (or syllabuses)", "octopus" to "octopuses", "virus" to "viruses",
        "alumnus" to "alumni", "index" to "indexes (or indices)", "appendix" to "appendices (or appendixes)",
        "matrix" to "matrices", "vertex" to "vertices", "knife" to "knives", "life" to "lives", "wife" to "wives",
        "leaf" to "leaves", "half" to "halves", "wolf" to "wolves", "loaf" to "loaves", "shelf" to "shelves",
        "potato" to "potatoes", "tomato" to "tomatoes", "hero" to "heroes", "echo" to "echoes", "piano" to "pianos",
        "photo" to "photos", "die" to "dice", "louse" to "lice", "quiz" to "quizzes", "bus" to "buses", "box" to "boxes",
        "mother-in-law" to "mothers-in-law", "passerby" to "passersby", "aircraft" to "aircraft", "salmon" to "salmon",
    )

    /** "is it affect or effect", "past tense of run", "plural of cactus". */
    fun writingHelp(text: String): Conversions? {
        firstMatch("""\b(?:is\s+it\s+|which\s+is\s+(?:right|correct)[:,]?\s+|when\s+to\s+use\s+)?([a-z'.]{2,12})(?:\s*,\s*|\s+or\s+|\s+vs\.?\s+|\s+and\s+)([a-z'.]{2,12})(?:(?:\s*,\s*|\s+or\s+)([a-z'.]{2,12}))?\??\s?$""", text)?.let { g ->
            val a = g[1]?.lowercase() ?: return@let
            val b = g[2]?.lowercase() ?: return@let
            val asked = setOfNotNull(a, b, g[3]?.lowercase())
            val hit = confusions.firstOrNull { it.first.containsAll(asked) && asked.size >= 2 } ?: return@let
            return Conversions(g[0]!!.trim(), listOf(hit.second))
        }
        firstMatch("""\b(?:what(?:'s|s|\s+is)\s+the\s+)?past\s+(?:tense|form)\s+(?:of\s+)?["']?([a-z]{2,12})["']?\??\s?$""", text)?.let { g ->
            val past = g[1]?.lowercase()?.let { pastTenses[it] } ?: return@let
            return Conversions(g[0]!!.trim(), listOf(past))
        }
        firstMatch("""\b(?:what(?:'s|s|\s+is)\s+the\s+)?plural\s+(?:of\s+|for\s+)?(?:an?\s+)?["']?([a-z-]{2,16})["']?\??\s?$""", text)?.let { g ->
            val many = g[1]?.lowercase()?.let { plurals[it] } ?: return@let
            return Conversions(g[0]!!.trim(), listOf(many))
        }
        return null
    }

    /** "5'10", "6’2\"", "5'10 in cm": a height in feet and inches, in cm. */
    fun feetInches(text: String): Conversions? {
        val g = firstMatch("""(?<![\w.'’])([3-7])\s*['’]\s*(\d{1,2})\s*(?:"|”|''|’’|in(?:ch(?:es)?)?)?(?:\s+(?:in|to)\s+(?:cm|centimet(?:er|re)s?|m|met(?:er|re)s?))?\??\s?$""", text)
            ?: return null
        val ft = g[1]?.toIntOrNull() ?: return null
        val inch = g[2]?.toIntOrNull()?.takeIf { it < 12 } ?: return null
        val cm = (ft * 12 + inch) * 2.54
        return Conversions(g[0]!!.trim(), listOf("${Math.round(cm)} cm", String.format(java.util.Locale.US, "%.2f m", cm / 100)))
    }

    /** "bmi 70kg 175cm", "my bmi at 160 lbs and 5'10": weight and height
     *  after "bmi" → BMI 22.9. */
    fun bmi(text: String): Conversions? {
        val g = firstMatch("""\bbmi\b(.{3,60})$""", text) ?: return null
        val rest = g[1] ?: return null
        val w = firstMatch("""(\d{2,3}(?:\.\d)?)\s*(kg|kgs|kilos?|lbs?|pounds?)\b""", rest) ?: return null
        val weight = w[1]?.toDoubleOrNull() ?: return null
        val kg = if ((w[2] ?: "").lowercase().startsWith("k")) weight else weight * 0.45359237
        val cm = firstMatch("""(\d{3}(?:\.\d)?)\s*cm\b""", rest)
        val metric = if (cm == null) firstMatch("""(?<![\d.])([12]\.\d{1,2})\s*m\b""", rest) else null
        val feet = if (cm == null && metric == null) firstMatch("""([3-7])\s*(?:['’]|ft|foot|feet)\s*(\d{1,2})?""", rest) else null
        val metres = when {
            cm != null -> cm[1]?.toDoubleOrNull()?.let { it / 100 }
            metric != null -> metric[1]?.toDoubleOrNull()
            feet != null -> feet[1]?.toDoubleOrNull()?.let { ft -> (ft * 12 + (feet[2]?.toDoubleOrNull() ?: 0.0)) * 0.0254 }
            else -> null
        } ?: return null
        if (metres <= 1 || metres >= 2.5 || kg <= 20 || kg >= 300) return null
        if (firstMatch("""\d\s*(?:cm|m|kg|kgs|kilos?|lbs?|pounds?|['’"”]|ft|feet|in)?\s*\??\s?$""", rest) == null) return null
        return Conversions(g[0]!!.trim(), listOf("BMI " + oneDecimal(kg / (metres * metres))))
    }

    /** "be there in 15", "back in 5", "call you back in 10": minutes left
     *  unsaid → the clock time then. */
    fun backIn(text: String, now: java.time.Instant, here: java.time.ZoneId): Conversions? {
        val g = firstMatch("""\b(?:be\s+(?:there|back|home|ready|down|out|free|done|over)|call\s+(?:you|u)\s+back|back|ready|leaving|home|there)\s+in\s+(\d{1,2})[.!]?\s?$""", text)
            ?: return null
        val n = g[1]?.toDoubleOrNull()?.takeIf { it >= 2 && it <= 60 } ?: return null
        val start = now.atZone(here)
        return Conversions(g[0]!!.trim(), listOf(clockAt(start.plusSeconds((n * 60).toLong()), start)))
    }

    /** "was 80 now 60", "was $120, now $90" → -25% · save $30. */
    fun wasNow(text: String): Conversions? {
        val g = firstMatch("""\bwas\s+([$€£₹¥])?\s?$AMT\s*,?\s*(?:now|is\s+now|now\s+(?:just|only)|but\s+now|reduced\s+to|down\s+to)\s+([$€£₹¥])?\s?$AMT$END""", text)
            ?: return null
        val a = number(g[2])?.takeIf { it > 0 } ?: return null
        val b = number(g[4]) ?: return null
        if (a == b) return null
        val s = g[1] ?: g[3] ?: ""
        return Conversions(g[0]!!.trim(),
            listOf(percentChange((b - a) / a * 100), (if (b < a) "save " else "+") + billMoney(kotlin.math.abs(b - a), s)))
    }

    private val romanDigits = listOf(1000 to "M", 900 to "CM", 500 to "D", 400 to "CD", 100 to "C", 90 to "XC",
        50 to "L", 40 to "XL", 10 to "X", 9 to "IX", 5 to "V", 4 to "IV", 1 to "I")

    fun romanNumeral(n: Int): String {
        var left = n
        val out = StringBuilder()
        for ((v, r) in romanDigits) while (left >= v) { out.append(r); left -= v }
        return out.toString()
    }

    /** "roman numeral 2026", "2026 in roman" → MMXXVI in its place;
     *  "MMXXVI in numbers" → 2026. */
    fun roman(text: String): Conversions? {
        val g = firstMatch("""\broman(?:\s+numerals?)?\s+(?:for\s+|of\s+)?(\d{1,4})$END""", text)
            ?: firstMatch("""(?<![\w.,])(\d{1,4})\s+(?:in|as|to|into)\s+roman(?:\s+numerals?)?$END""", text)
        val n = g?.get(1)?.toIntOrNull()
        if (g != null && n != null && n in 1..3999) {
            return Conversions(g[0]!!.trim(), listOf(romanNumeral(n)), hows = listOf(Insertion.REPLACE))
        }
        val r = firstMatch("""(?<![\w])([MDCLXVI]{2,15})\s+(?:in\s+(?:numbers|digits|arabic)|as\s+a\s+number|to\s+(?:numbers|digits))$END""", text)
            ?: return null
        val letters = r[1]?.uppercase() ?: return null
        var total = 0
        var i = 0
        for ((v, sym) in romanDigits) while (letters.startsWith(sym, i)) { total += v; i += sym.length }
        if (i != letters.length || total <= 0 || romanNumeral(total) != letters) return null
        return Conversions(r[0]!!.trim(), listOf("$total"))
    }

    /** "base64 hello" → aGVsbG8= in its place; "base64 decode aGVsbG8=" → hello. */
    fun base64(text: String): Conversions? {
        firstMatch("""\bbase\s?64\s+decode\s*:?\s+([A-Za-z0-9+/_-]{4,}={0,2})\s?$""", text)?.let { g ->
            var code = (g[1] ?: return@let).replace('-', '+').replace('_', '/')
            while (code.length % 4 != 0) code += "="
            val bytes = runCatching { java.util.Base64.getDecoder().decode(code) }.getOrNull() ?: return null
            val plain = runCatching {
                Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
            }.getOrNull() ?: return null
            val control = plain.codePoints().anyMatch {
                val type = Character.getType(it)
                (type == Character.CONTROL.toInt() || type == Character.FORMAT.toInt()) && it != '\n'.code
            }
            if (plain.isEmpty() || control) return null
            return Conversions(g[0]!!.trim(), listOf(plain), hows = listOf(Insertion.REPLACE))
        }
        val g = firstMatch("""\bbase\s?64(?:\s+encode)?\s*:?\s+(?!decode\b)(\S.{0,199}?)\s?$""", text) ?: return null
        val plain = g[1] ?: return null
        return Conversions(g[0]!!.trim(), listOf(java.util.Base64.getEncoder().encodeToString(plain.toByteArray(Charsets.UTF_8))),
            hows = listOf(Insertion.REPLACE))
    }

    @Volatile private var lastUUID: Pair<String, String>? = null

    /** "uuid", "new guid": a fresh one in its place, the same while the
     *  words stay the same. */
    fun uuid(text: String): Conversions? {
        val g = firstMatch("""(?:^|[\s(])((?:new\s+|random\s+|generate\s+(?:a\s+)?|fresh\s+)?(?:uuid|guid)(?:\s*v4)?)\??\s?$""", text)
            ?: return null
        val source = g[1] ?: return null
        val made = lastUUID?.takeIf { it.first == text }
            ?: (text to java.util.UUID.randomUUID().toString().lowercase()).also { lastUUID = it }
        return Conversions(source.trim(), listOf(made.second), hows = listOf(Insertion.REPLACE))
    }

    /** Emergency numbers by country: one number where it is one, police and
     *  ambulance where they differ. Only numbers checked against each
     *  country's own published lists; nothing for a country not in it. */
    private val emergencyNumbers = mapOf(
        "US" to "911", "CA" to "911", "MX" to "911", "AR" to "911", "PH" to "911",
        "GB" to "999", "HK" to "999", "MY" to "999",
        "IE" to "112", "FR" to "112", "DE" to "112", "ES" to "112", "IT" to "112", "NL" to "112", "BE" to "112", "PT" to "112",
        "AT" to "112", "CH" to "112", "SE" to "112", "NO" to "112", "DK" to "112", "FI" to "112", "PL" to "112", "GR" to "112",
        "CZ" to "112", "IN" to "112", "ID" to "112",
        "AU" to "000", "NZ" to "111",
        "JP" to "110 police · 119 ambulance", "CN" to "110 police · 120 ambulance", "KR" to "112 police · 119 ambulance",
        "SG" to "999 police · 995 ambulance", "AE" to "999 police · 998 ambulance", "BR" to "190 police · 192 ambulance",
        "IL" to "100 police · 101 ambulance", "TH" to "191 police · 1669 ambulance", "ZA" to "10111 police · 10177 ambulance",
    )
    private val countryWords = mapOf(
        "us" to "US", "usa" to "US", "america" to "US", "united states" to "US", "the us" to "US", "canada" to "CA", "mexico" to "MX",
        "argentina" to "AR", "philippines" to "PH", "uk" to "GB", "britain" to "GB", "great britain" to "GB", "england" to "GB",
        "scotland" to "GB", "wales" to "GB", "united kingdom" to "GB", "the uk" to "GB", "hong kong" to "HK", "malaysia" to "MY",
        "ireland" to "IE", "france" to "FR", "germany" to "DE", "spain" to "ES", "italy" to "IT", "netherlands" to "NL",
        "holland" to "NL", "belgium" to "BE", "portugal" to "PT", "austria" to "AT", "switzerland" to "CH", "sweden" to "SE",
        "norway" to "NO", "denmark" to "DK", "finland" to "FI", "poland" to "PL", "greece" to "GR", "czechia" to "CZ",
        "czech republic" to "CZ", "europe" to "FR", "eu" to "FR", "india" to "IN", "indonesia" to "ID", "bali" to "ID",
        "australia" to "AU", "new zealand" to "NZ", "nz" to "NZ", "japan" to "JP", "china" to "CN", "korea" to "KR",
        "south korea" to "KR", "singapore" to "SG", "uae" to "AE", "dubai" to "AE", "abu dhabi" to "AE", "brazil" to "BR",
        "israel" to "IL", "thailand" to "TH", "south africa" to "ZA",
    )

    fun emergencyNumber(text: String, region: String?): Conversions? {
        val g = firstMatch("""\b(?:emergency|police|ambulance)\s+(?:number|no\.?|line|phone|services?|contact)(?:\s+(?:(?:in|for|of)\s+)?([a-z][a-z .]{1,25}?))?\??\s?$""", text)
            ?: return null
        val named = g[1]?.lowercase()?.trim()
        // A country named and not known: nothing, not the phone's own.
        val code = (if (named != null) countryWords[named] else region?.uppercase()) ?: return null
        val number = emergencyNumbers[code] ?: return null
        val place = named?.let { if (it == "europe" || it == "eu") "EU" else if (it.length <= 3) it.uppercase() else capitalizedWords(it) }
        return Conversions(g[0]!!.trim(), listOf(if (place != null) "$number · $place" else number))
    }

    /** What chat shorthand stands for: "what does ngl mean" → not gonna lie. */
    private val slang = mapOf(
        "ngl" to "not gonna lie", "iykyk" to "if you know, you know", "tbh" to "to be honest", "imo" to "in my opinion",
        "imho" to "in my humble opinion", "idk" to "I don't know", "idc" to "I don't care", "ikr" to "I know, right?",
        "smh" to "shaking my head", "fr" to "for real", "nvm" to "never mind", "tbf" to "to be fair", "afaik" to "as far as I know",
        "irl" to "in real life", "fyi" to "for your information", "btw" to "by the way", "brb" to "be right back",
        "ttyl" to "talk to you later", "gtg" to "got to go", "g2g" to "got to go", "hmu" to "hit me up", "wyd" to "what (are) you doing",
        "wbu" to "what about you", "hbu" to "how about you", "lmk" to "let me know", "ofc" to "of course", "rn" to "right now",
        "np" to "no problem", "ty" to "thank you", "tysm" to "thank you so much", "yw" to "you're welcome", "omw" to "on my way",
        "otw" to "on the way", "eta" to "estimated time of arrival", "asap" to "as soon as possible",
        "rsvp" to "please reply (répondez s'il vous plaît)", "tldr" to "too long; didn't read", "tl;dr" to "too long; didn't read",
        "dm" to "direct message", "pov" to "point of view", "goat" to "greatest of all time", "fomo" to "fear of missing out",
        "yolo" to "you only live once", "bff" to "best friends forever", "jk" to "just kidding", "lol" to "laughing out loud",
        "lmao" to "laughing my ass off", "rofl" to "rolling on the floor laughing", "istg" to "I swear to god",
        "ily" to "I love you", "sus" to "suspicious", "ong" to "on god (I swear)", "nsfw" to "not safe for work",
        "tmi" to "too much information", "ftw" to "for the win", "icymi" to "in case you missed it", "ootd" to "outfit of the day",
        "wfh" to "work from home", "ooo" to "out of office", "eod" to "end of day", "eow" to "end of week",
        "cob" to "close of business", "pto" to "paid time off", "tbd" to "to be decided", "tba" to "to be announced",
        "wip" to "work in progress", "aka" to "also known as", "diy" to "do it yourself", "fwiw" to "for what it's worth",
        "til" to "today I learned", "eli5" to "explain like I'm 5", "ama" to "ask me anything", "smth" to "something",
        "ppl" to "people", "hbd" to "happy birthday", "nbd" to "no big deal", "wagmi" to "we're all gonna make it",
        "ngmi" to "not gonna make it", "dyor" to "do your own research", "hodl" to "hold (don't sell)",
        "fud" to "fear, uncertainty and doubt", "gg" to "good game", "glhf" to "good luck, have fun", "afk" to "away from keyboard",
        "bet" to "okay, deal", "no cap" to "no lie", "cap" to "a lie", "lowkey" to "a little, quietly",
        "highkey" to "very, openly", "rizz" to "charm", "delulu" to "delusional", "mid" to "mediocre", "slay" to "did great",
        "ate" to "did great", "stan" to "a big fan", "simp" to "too eager to please someone", "salty" to "bitter, upset",
        "ghosted" to "cut off contact without a word", "situationship" to "a relationship with no label",
        "periodt" to "end of discussion", "bussin" to "really good", "finna" to "going to", "gonna" to "going to",
        "wanna" to "want to", "tryna" to "trying to", "wdym" to "what do you mean", "wym" to "what do you mean",
        "ik" to "I know", "ig" to "I guess", "icl" to "I can't lie", "mb" to "my bad", "nm" to "not much", "sry" to "sorry",
        "pls" to "please", "thx" to "thanks", "gm" to "good morning", "gn" to "good night", "hru" to "how are you",
        "wtv" to "whatever", "bc" to "because", "cuz" to "because", "b4" to "before", "l8r" to "later", "w/e" to "whatever",
        "oomf" to "one of my followers", "pfp" to "profile picture", "ratio" to "a reply with more likes than the post",
        "fyp" to "for you page", "op" to "original poster", "ic" to "I see", "ttys" to "talk to you soon", "rofr" to "right of first refusal",
    )

    fun slangMeaning(text: String): Conversions? {
        val word = """["'“]?([a-z0-9;/ ]{2,14}?)["'”]?"""
        val g = firstMatch("""\bwhat\s+(?:does|do|is|r|are)\s+(?:an?\s+|the\s+)?$word\s+(?:mean|stand\s+for|short\s+for)\??\s?$""", text)
            ?: firstMatch("""\b(?:meaning\s+of|define|wdym\s+by)\s+$word\??\s?$""", text)
            ?: firstMatch("""(?:^|\s)$word\s+meaning\??\s?$""", text)
            ?: return null
        val key = g[1]?.lowercase()?.trim() ?: return null
        val meaning = slang[key] ?: return null
        return Conversions(g[0]!!.trim(), listOf(meaning))
    }

    private val notAMeetingPlace = setOf("my", "your", "his", "her", "our", "their", "a", "an", "some", "this", "that", "it", "work",
        "home", "school", "noon", "night", "midnight", "lunch", "dinner", "breakfast", "peace", "least", "most", "all", "once",
        "last", "first")

    /** A place as a URL query, the way iOS's urlQueryAllowed leaves it, with
     *  "&" and "+" escaped too. */
    private fun queryEncoded(s: String): String {
        val allowed = "-._~!${'$'}&'()*+,;=:@/?"
        val out = StringBuilder()
        for (byte in s.toByteArray(Charsets.UTF_8)) {
            val c = byte.toInt() and 0xFF
            val ch = c.toChar()
            if (c < 0x80 && (ch.isLetterOrDigit() || ch in allowed)) out.append(ch) else out.append("%%%02X".format(c))
        }
        return out.toString().replace("&", "%26").replace("+", "%2B")
    }

    private fun isPunctuation(c: Char): Boolean = when (Character.getType(c).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION -> true
        else -> false
    }

    /** "lets meet at starbucks on main st", "im at central park", "address
     *  is 1 infinite loop cupertino" → "Add a map link": a Google Maps
     *  search for the place, after it. Not a time ("meet at 7"), nowhere in
     *  general ("home", "the airport"), nothing that isn't a place ("im at
     *  peace"). */
    fun mapLink(text: String): Conversions? {
        val lead = """\b(?:(meet\s+(?:me\s+|us\s+|you\s+|u\s+)?(?:at|outside|in\s+front\s+of)|let'?s\s+meet\s+(?:at|outside)|see\s+(?:you|u)\s+at|pick\s+(?:me|us)\s+up\s+(?:at|from)|drop\s+(?:me|us)\s+(?:at|off\s+at))|(?:i'?m|im|we'?re|i\s+am|we\s+are)\s+(?:at|outside)|address\s+is|located\s+at|come\s+to)\s+"""
        val g = firstMatch(lead + """(.{3,60}?)[.!?]?\s?$""", text) ?: return null
        // The time and day after the place: "starbucks at 5", "the mall tomorrow".
        val place = Regex("""\s+(?:at|by|around|before|after)\s+\d.*$|\s+(?:tomorrow|today|tonight|tmrw|this\s+\w+|next\s+\w+|on\s+(?:mon|tue|wed|thu|fri|sat|sun)\w*|in\s+\d+.*)$""",
            RegexOption.IGNORE_CASE).replace((g[2] ?: return null).trim(), "")
            .trim { it == ' ' || it == '\t' || isPunctuation(it) }
        val lower = place.lowercase()
        val words = lower.split(" ").filter { it.isNotEmpty() }
        val first = words.firstOrNull() ?: return null
        if (place.length < 3) return null
        if (Regex("""^\d{1,2}(?::\d{2})?\s*(?:am|pm)?$|\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b""").containsMatchIn(lower)) return null
        if (first in notAMeetingPlace || (first == "the" && words.size == 2)) return null
        // "im at" needs a place's name: two words, a capital, or a number.
        val meeting = g[1] != null
        val named = words.size >= 2 || place.first().isUpperCase() || place.any { it.isDigit() }
        if (!(named || (meeting && place.length >= 4))) return null
        return Conversions(place, listOf("Add a map link"),
            inserts = listOf("https://www.google.com/maps/search/?api=1&query=" + queryEncoded(place)), hows = listOf(Insertion.AFTER))
    }

    /** "what day is 25 december 2026", "day of the week for 3/14/1998" → Friday. */
    fun dayOfWeek(text: String, region: String?): Conversions? {
        val g = firstMatch("""\b(?:what\s+day\s+(?:of\s+the\s+week\s+)?(?:is|was|will\s+be|falls\s+on)|which\s+day\s+(?:is|was)|day\s+of\s+(?:the\s+)?week\s+(?:for|of|on|is))\s+(?:it\s+on\s+)?(?:the\s+)?$fullDatePattern$END""", text)
            ?: return null
        val (y, m, d) = fullDate(g, 1, region) ?: return null
        val date = runCatching { java.time.LocalDate.of(y, m, d) }.getOrNull() ?: return null
        return Conversions(g[0]!!.trim(), listOf(date.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.US)))
    }

    // MARK: answers from the 2026-10-08 research pass (Smart.swift twins)

    /** "got 43/50 on the quiz", "scored 18 out of 25" → 86%. A score word
     *  is needed: "3 out of 5" alone stays quiet. */
    @Suppress("UNUSED_PARAMETER")
    fun testScore(text: String, region: String?): Conversions? {
        val g = firstMatch("""\b(?:got|get|getting|scored|score|marks?|mark|result)\s+(?:a\s+|of\s+|is\s+|was\s+)?(\d{1,3}(?:\.\d{1,2})?)\s*(?:/|out\s+of)\s*(\d{1,3})(?:\s+(?:on|in)\s+(?:the\s+|my\s+|a\s+|an\s+)?[a-z]{2,15})?$END""", text)
            ?: return null
        val a = g[1]?.toDoubleOrNull() ?: return null
        val b = g[2]?.toDoubleOrNull() ?: return null
        if (b <= 0 || a > b || b < 5) return null
        return Conversions(g[0]!!.trim(), listOf(oneDecimal(a / b * 100) + "%"))
    }

    /** "avg of 85, 92, 78", "average 12 15 9 22" → 85 avg · median 85;
     *  "sum of 12, 30, 8" → 50. */
    fun averageOf(text: String): Conversions? {
        val g = firstMatch("""\b(avg|average|mean|median|sum|total)\s+(?:of\s+)?((?:-?\d+(?:\.\d+)?\s*(?:,|and|\s)\s*){1,49}-?\d+(?:\.\d+)?)$END""", text)
            ?: return null
        val kind = g[1]?.lowercase() ?: return null
        val list = g[2] ?: return null
        // "total 1,250" is one number, not two.
        if (Regex("""^\d{1,3}(?:,\d{3})+(?:\.\d+)?$""").containsMatchIn(list)) return null
        val values = list.split(',', ' ').filter { it != "and" && it.isNotEmpty() }.mapNotNull { it.toDoubleOrNull() }
        if (values.size < 2) return null
        val sorted = values.sorted()
        val median = if (sorted.size % 2 == 1) sorted[sorted.size / 2] else (sorted[sorted.size / 2 - 1] + sorted[sorted.size / 2]) / 2
        val sum = values.sum()
        fun n(v: Double): String {
            var t = billMoney(v, "")
            if (t.contains('.')) t = t.trimEnd('0').removeSuffix(".")
            return t
        }
        if (kind == "sum" || kind == "total") return Conversions(g[0]!!.trim(), listOf(n(sum)))
        if (kind == "median") return Conversions(g[0]!!.trim(), listOf("median " + n(median)))
        return Conversions(g[0]!!.trim(), listOf("${n(sum / values.size)} avg", "median " + n(median)))
    }

    /** "extra 10% off 20% off $80", "20% + 10% off $80" → $57.60 · 28% off. */
    fun stackedDiscount(text: String): Conversions? {
        val g = firstMatch("""\b(?:extra|additional|another)\s+$PCT\s*off\s+(?:the\s+)?$PCT\s*off\s*(?:of\s+)?$SYM\s*$AMT$END""", text)
            ?: firstMatch("""\b$PCT\s*(?:off)?\s*(?:\+|and|then|plus|,)\s*(?:an?\s+)?(?:extra\s+|additional\s+)?$PCT\s*off\s*(?:of\s+)?$SYM\s*$AMT$END""", text)
            ?: return null
        val a = number(g[1]) ?: return null
        val b = number(g[2]) ?: return null
        val price = number(g[4]) ?: return null
        if (a <= 0 || b <= 0 || a >= 100 || b >= 100) return null
        val left = (1 - a / 100) * (1 - b / 100)
        return Conversions(g[0]!!.trim(), listOf(billMoney(price * left, g[3] ?: ""), oneDecimal((1 - left) * 100) + "% off"))
    }

    /** "buy 2 get 1 free $12 each", "bogo $10" → $8 each. */
    fun buyGetFree(text: String): Conversions? {
        val words = mapOf("one" to 1.0, "two" to 2.0, "three" to 3.0, "four" to 4.0, "a" to 1.0)
        fun count(s: String?): Double? = s?.let { it.toDoubleOrNull() ?: words[it.lowercase()] }
        val g = firstMatch("""\bbuy\s+(\d|one|two|three|four)\s*,?\s*get\s+(\d|one|two|a)\s+free\s*(?:at\s+|@\s*|for\s+)?$SYM\s*$AMT\s*(?:each|ea|apiece)?$END""", text)
        val h = if (g == null) firstMatch("""\bbogo\s*(?:at\s+|@\s*|for\s+)?$SYM\s*$AMT\s*(?:each|ea)?$END""", text) else null
        val buy: Double?
        val free: Double?
        val price: Double?
        val symbol: String
        val source: String
        when {
            g != null -> { buy = count(g[1]); free = count(g[2]); symbol = g[3] ?: ""; price = number(g[4]); source = g[0]!!.trim() }
            h != null -> { buy = 1.0; free = 1.0; symbol = h[1] ?: ""; price = number(h[2]); source = h[0]!!.trim() }
            else -> return null
        }
        if (buy == null || free == null || price == null || buy <= 0 || free <= 0 || price <= 0) return null
        return Conversions(source, listOf("${billMoney(price * buy / (buy + free), symbol)} each"))
    }

    /** "save $500/mo for 10 yrs at 7%" → $86,542 · +$26,542 growth. */
    fun monthlySavings(text: String): Conversions? {
        val each = """\s*(?:/|a|per|every|each)\s*(?:mo|mon|month|m)\b"""
        val term = """(\d{1,2})\s*(?:years?|yrs?|y)\b"""
        val rate = """(\d{1,2}(?:\.\d{1,2})?)\s*%"""
        val lead = """\b(?:save|saving|invest|investing|put\s+(?:away|in)|deposit|sip\s+of|sip)?\s*$SYM\s*$AMT"""
        val g = firstMatch(lead + each + """\s*(?:for|over)\s*""" + term + """\s*(?:at|@)\s*""" + rate + END, text)
        val h = if (g == null) firstMatch(lead + each + """\s*(?:at|@)\s*""" + rate + """\s*(?:for|over)\s*""" + term + END, text) else null
        val s: String
        val p: Double?
        val years: Double?
        val r: Double?
        val source: String
        when {
            g != null -> { s = g[1] ?: ""; p = number(g[2]); years = g[3]?.toDoubleOrNull(); r = g[4]?.toDoubleOrNull(); source = g[0]!!.trim() }
            h != null -> { s = h[1] ?: ""; p = number(h[2]); r = h[3]?.toDoubleOrNull(); years = h[4]?.toDoubleOrNull(); source = h[0]!!.trim() }
            else -> return null
        }
        if (p == null || years == null || r == null || p <= 0 || years <= 0 || years > 60 || r <= 0 || r > 30) return null
        val i = r / 100 / 12
        val n = years * 12
        val total = p * ((1 + i).pow(n) - 1) / i
        return Conversions(source, listOf(wholeMoney(total, s), "+" + wholeMoney(total - p * n, s) + " growth"))
    }

    /** "300 miles at 65 mph" → 4 h 37 min; "120 km at 80 km/h" → 1 h 30 min. */
    fun driveTime(text: String): Conversions? {
        val g = firstMatch("""(?<![\w.,])(\d{1,5}(?:\.\d+)?)\s*(?:miles?|mi|km|kms|kilomet(?:er|re)s?)\s+(?:at|@)\s*(\d{1,3})\s*(?:mph|km/?h|kmh|kph|kmph)$END""", text)
            ?: return null
        val d = g[1]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val v = g[2]?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val minutes = Math.round(d / v * 60)
        if (minutes <= 0 || minutes >= 100 * 60) return null
        val h = minutes / 60
        val m = minutes % 60
        return Conversions(g[0]!!.trim(), listOf(if (h == 0L) "$m min" else if (m == 0L) "$h h" else "$h h $m min"))
    }

    /** "when do the clocks change", "daylight saving" → Sun 1 Nov · back 1 h,
     *  where the phone is. */
    fun clockChange(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val g = firstMatch("""\b(?:when\s+(?:do|does|will)\s+(?:the\s+)?clocks?\s+(?:change|go\s+(?:back|forward)|spring\s+forward|fall\s+back)|(?:when\s+(?:is|does)\s+)?(?:daylight\s+sav(?:ing|ings)(?:\s+time)?|dst)(?:\s+(?:start|end|begin)s?)?)$END""", text)
            ?: return null
        val next = here.rules.nextTransition(now)?.instant
            ?: return Conversions(g[0]!!.trim(), listOf("No clock changes here"))
        val before = here.rules.getOffset(next.minusSeconds(60)).totalSeconds
        val after = here.rules.getOffset(next.plusSeconds(60)).totalSeconds
        val shift = (after - before) / 60
        val day = java.time.format.DateTimeFormatter.ofPattern(
            if (region?.uppercase() == "US") "EEE, MMM d" else "EEE d MMM", java.util.Locale.US).format(next.atZone(here))
        val size = kotlin.math.abs(shift)
        val amount = if (size % 60 == 0) "${size / 60} h" else "$size min"
        return Conversions(g[0]!!.trim(), listOf("$day · ${if (shift > 0) "forward" else "back"} $amount"))
    }

    /** "zone 2 heart rate age 34", "max hr age 34", "im 34 whats my max heart
     *  rate" → Zone 2: 113–132 bpm · Max HR 186 (the 220 − age rule). */
    fun heartRate(text: String): Conversions? {
        if (firstMatch("""\b(?:heart\s*rate|hr|bpm)\b""", text) == null) return null
        val a = firstMatch("""(?:\bage\s*(?:is\s+|of\s+|:)?|\bi'?m\s+|\bim\s+|\bi\s+am\s+)(\d{2})(?:\s*(?:yo|y/o|years?\s+old))?\b""", text)
            ?: firstMatch("""\b(\d{2})\s*(?:yo|y/o|years?\s+old)\b""", text)
            ?: return null
        val age = a[1]?.toDoubleOrNull()?.takeIf { it >= 10 && it <= 100 } ?: return null
        if (firstMatch("""(?:rate|hr|bpm|\d|old|yo)\??\s?$""", text) == null) return null
        val max = 220 - age
        val source = firstMatch("""\S.*$""", text)?.get(0)?.trim() ?: text.trim()
        firstMatch("""\bzone\s*([1-5])\b""", text)?.get(1)?.toDoubleOrNull()?.let { zone ->
            val lo = Math.round(max * (0.4 + zone * 0.1))
            val hi = Math.round(max * (0.5 + zone * 0.1))
            return Conversions(source, listOf("Zone ${zone.toInt()}: $lo–$hi bpm", "Max HR ${max.toInt()}"))
        }
        return Conversions(source, listOf("Max HR ${max.toInt()} bpm", "Zone 2: ${Math.round(max * 0.6)}–${Math.round(max * 0.7)} bpm"))
    }

    /** "x^2" → x², "\\alpha" → α, "\\pi" → π: in place. */
    private val greek = mapOf(
        "alpha" to "α", "beta" to "β", "gamma" to "γ", "delta" to "δ", "epsilon" to "ε", "theta" to "θ", "lambda" to "λ", "mu" to "μ",
        "pi" to "π", "rho" to "ρ", "sigma" to "σ", "tau" to "τ", "phi" to "φ", "omega" to "ω", "Delta" to "Δ", "Sigma" to "Σ", "Omega" to "Ω",
        "infty" to "∞", "sqrt" to "√", "pm" to "±", "neq" to "≠", "leq" to "≤", "geq" to "≥", "approx" to "≈", "times" to "×", "div" to "÷",
        "degree" to "°", "deg" to "°",
    )
    private val superscripts = mapOf(
        '0' to '⁰', '1' to '¹', '2' to '²', '3' to '³', '4' to '⁴', '5' to '⁵', '6' to '⁶', '7' to '⁷', '8' to '⁸', '9' to '⁹',
        'n' to 'ⁿ', '-' to '⁻', '+' to '⁺',
    )

    fun mathsSymbol(text: String): Conversions? {
        firstMatch("""\\([A-Za-z]{2,7})\s?$""", text)?.let { g ->
            val name = g[1] ?: return@let
            val sym = greek[name] ?: greek[name.lowercase()] ?: return@let
            return Conversions(g[0]!!.trim(), listOf(sym), hows = listOf(Insertion.REPLACE))
        }
        val g = firstMatch("""(?<![\w^])([a-z0-9)])\^(-?[0-9n]{1,3})\s?$""", text) ?: return null
        val base = g[1] ?: return null
        val power = g[2] ?: return null
        if (!power.all { superscripts.containsKey(it) }) return null
        // "2^10" is a sum, worked out already; a letter's power is notation.
        if (!(base.first().isLetter() || base == ")")) return null
        return Conversions(g[0]!!.trim(), listOf(base + power.map { superscripts[it] }.joinToString("")), hows = listOf(Insertion.REPLACE))
    }

    /** C's "%.3g", as Swift's String(format:) writes it: three significant
     *  digits, trailing zeros dropped, an exponent below 1e-4 or from 1000. */
    private fun threeSignificant(v: Double): String {
        if (v == 0.0 || v.isNaN() || v.isInfinite()) return if (v == 0.0) "0" else v.toString()
        val bd = java.math.BigDecimal(v).round(java.math.MathContext(3, java.math.RoundingMode.HALF_EVEN))
        val exp = bd.precision() - bd.scale() - 1
        if (exp < -4 || exp >= 3) {
            val mantissa = bd.movePointLeft(exp).stripTrailingZeros().toPlainString()
            return mantissa + "e" + (if (exp < 0) "-" else "+") + "%02d".format(kotlin.math.abs(exp))
        }
        return bd.stripTrailingZeros().toPlainString()
    }

    /** "solve 2x+5=17", "3x - 4 = 11" → x = 6; "x^2-5x+6=0" → x = 2, 3. */
    fun solveEquation(text: String): Conversions? {
        fun num(s: String?, empty: Double): Double? {
            val t = s?.replace(" ", "") ?: return null
            if (t.isEmpty() || t == "+") return empty
            if (t == "-") return -empty
            return t.toDoubleOrNull()
        }
        fun tidy(v: Double) = if (kotlin.math.abs(v - Math.round(v)) < 1e-9) Math.round(v).toString() else threeSignificant(v)
        firstMatch("""(?:\bsolve\s*:?\s*)?(?<![\w.])([-+]?\s*\d*\.?\d*)\s*\*?\s*([a-z])\s*(?:\^2|²)\s*([-+]\s*\d*\.?\d*)\s*\*?\s*\2\s*([-+]\s*\d+(?:\.\d+)?)?\s*=\s*0\??\s?$""", text)?.let { g ->
            val a = num(g[1], 1.0) ?: return@let
            val b = num(g[3], 1.0) ?: return@let
            val x = g[2] ?: return@let
            val c = num(g[4], 0.0) ?: 0.0
            if (a == 0.0) return null
            val d = b * b - 4 * a * c
            if (d < 0) return Conversions(g[0]!!.trim(), listOf("no real $x"))
            val r1 = (-b + kotlin.math.sqrt(d)) / (2 * a)
            val r2 = (-b - kotlin.math.sqrt(d)) / (2 * a)
            val roots = setOf(tidy(r1), tidy(r2)).sortedBy { it.toDoubleOrNull() ?: 0.0 }
            return Conversions(g[0]!!.trim(), listOf("$x = " + roots.joinToString(", ")))
        }
        val g = firstMatch("""(?:\bsolve\s*:?\s*)?(?<![\w.^])([-+]?\s*\d*\.?\d*)\s*\*?\s*([a-z])\s*([-+]\s*\d+(?:\.\d+)?)?\s*=\s*([-+]?\s*\d+(?:\.\d+)?)\??\s?$""", text)
            ?: return null
        val a = num(g[1], 1.0) ?: return null
        val x = g[2] ?: return null
        val c = num(g[4], 0.0) ?: return null
        // A bare "x = 5" is already solved; there must be a sum to undo.
        if (a == 0.0 || !(g[3] != null || (g[1] ?: "").any { it.isDigit() })) return null
        val b = num(g[3], 0.0) ?: 0.0
        return Conversions(g[0]!!.trim(), listOf("$x = " + tidy((c - b) / a)))
    }

    /** Safe inside temperatures (USDA FSIS's chart): "chicken internal
     *  temp", "safe temp for pork" → 165°F · 74°C. */
    private val safeTemps = listOf(
        """chicken|turkey|poultry|duck|goose|leftovers?|casseroles?|stuffing""" to "165°F · 74°C",
        """ground\s+(?:beef|pork|meat|lamb|veal)|burgers?|minced?\s+(?:beef|meat)|sausages?|meatloaf|egg\s+dish(?:es)?""" to "160°F · 71°C",
        """ground\s+(?:chicken|turkey)""" to "165°F · 74°C",
        """beef|steaks?|pork|lamb|veal|roast|chops?|ham""" to "145°F · 63°C, then rest 3 min",
        """fish|salmon|tuna|cod|shellfish|shrimp|prawns?""" to "145°F · 63°C",
    )

    fun cookingSafety(text: String): Conversions? {
        val g = firstMatch("""\b(?:(?:safe|internal|cooking|cook|done)\s+(?:temp|temperature)\s+(?:for|of)\s+(?:a\s+|the\s+)?([a-z ]{3,24}?)|([a-z ]{3,24}?)\s+(?:internal|safe|cooking|cooked|done)\s+(?:temp|temperature)|what\s+temp(?:erature)?\s+(?:is|should)\s+([a-z ]{3,24}?)\s+(?:done|cooked|safe))\??\s?$""", text)
            ?: return null
        val food = (g[1] ?: g[2] ?: g[3])?.lowercase() ?: return null
        // The most particular first: "ground turkey" before "turkey".
        val ordered = listOf(safeTemps[2], safeTemps[1], safeTemps[0], safeTemps[3], safeTemps[4])
        for ((pattern, temp) in ordered) {
            if (Regex("""\b(?:$pattern)\b""").containsMatchIn(food)) return Conversions(g[0]!!.trim(), listOf(temp))
        }
        return null
    }

    /** Kitchen swaps: "substitute for buttermilk" → 1 cup milk + 1 tbsp lemon juice. */
    private val swaps = mapOf(
        "buttermilk" to "1 cup milk + 1 tbsp lemon juice", "egg" to "1 tbsp ground flax + 3 tbsp water",
        "eggs" to "1 tbsp ground flax + 3 tbsp water each", "baking powder" to "¼ tsp baking soda + ½ tsp cream of tartar",
        "baking soda" to "3 tsp baking powder per 1 tsp", "brown sugar" to "1 cup sugar + 1 tbsp molasses",
        "cake flour" to "1 cup flour less 2 tbsp + 2 tbsp cornstarch", "self raising flour" to "1 cup flour + 1½ tsp baking powder + ¼ tsp salt",
        "self-raising flour" to "1 cup flour + 1½ tsp baking powder + ¼ tsp salt", "self rising flour" to "1 cup flour + 1½ tsp baking powder + ¼ tsp salt",
        "heavy cream" to "¾ cup milk + ¼ cup melted butter", "sour cream" to "plain Greek yogurt, same amount",
        "butter" to "same amount of oil × ¾", "honey" to "1¼ cups sugar + ¼ cup water per cup", "cornstarch" to "2 tbsp flour per 1 tbsp",
        "corn starch" to "2 tbsp flour per 1 tbsp", "lemon juice" to "same amount of vinegar", "wine" to "same amount of stock + 1 tbsp vinegar",
        "white wine" to "same amount of stock + 1 tbsp white wine vinegar", "red wine" to "same amount of stock + 1 tbsp red wine vinegar",
        "garlic clove" to "⅛ tsp garlic powder", "fresh herbs" to "⅓ the amount of dried", "milk" to "same amount of oat or soy milk",
        "mayonnaise" to "plain Greek yogurt, same amount", "sugar" to "¾ cup honey per cup, less 3 tbsp liquid",
        "breadcrumbs" to "crushed crackers or rolled oats, same amount", "ricotta" to "cottage cheese, same amount",
        "vanilla extract" to "maple syrup, same amount", "shallot" to "½ small onion + a pinch of garlic", "yeast" to "2¼ tsp instant per packet",
    )

    fun substitute(text: String): Conversions? {
        val g = firstMatch("""\b(?:substitute|sub|replacement|swap|alternative)\s+(?:for|to)\s+(?:a\s+|an\s+)?([a-z -]{3,24}?)\??\s?$""", text)
            ?: firstMatch("""\bwhat\s+(?:can|could|do)\s+i\s+use\s+instead\s+of\s+(?:a\s+|an\s+)?([a-z -]{3,24}?)\??\s?$""", text)
            ?: return null
        val food = g[1]?.lowercase()?.trim() ?: return null
        val swap = swaps[food] ?: return null
        return Conversions(g[0]!!.trim(), listOf(swap))
    }

    /** "ooo until monday", "out of office till 14 oct" → "OOO reply · Mon
     *  12 Oct": a short reply in its place with the day worked out. */
    fun outOfOffice(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val g = firstMatch("""^\s*(?:i'?m\s+|im\s+)?(?:ooo|out\s+of\s+(?:the\s+)?office|on\s+(?:leave|vacation|holiday|pto))\s+(?:until|till|til|through|thru)\s+([a-z0-9 ]{3,20}?)[.!]?\s?$""", text)
            ?: return null
        val said = g[1]?.lowercase() ?: return null
        val today = now.atZone(here).toLocalDate()
        val weekday = weekdays.firstOrNull { it.first == said || said == "next " + it.first }
        val dated = if (weekday == null && said != "tomorrow" && said != "tmrw")
            firstMatch("""^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,9})$|^([a-z]{3,9})\s+(\d{1,2})(?:st|nd|rd|th)?$""", said) else null
        val back: java.time.LocalDate = when {
            weekday != null -> {
                var next = today.plusDays(1)
                while (next.dayOfWeek.value != weekday.second) next = next.plusDays(1)
                next
            }
            said == "tomorrow" || said == "tmrw" -> today.plusDays(1)
            dated != null -> {
                val dayN = (dated[1] ?: dated[4])?.toIntOrNull() ?: return null
                val monthName = dated[2] ?: dated[3] ?: ""
                val month = datedMonths.firstOrNull { it.first == monthName }?.second ?: return null
                val date = runCatching { java.time.LocalDate.of(today.year, month, dayN) }.getOrNull() ?: return null
                if (date.isBefore(today)) date.plusYears(1) else date
            }
            else -> return null
        }
        val day = dayName(back, today, region)
        val reply = "I'm out of the office until $day and will reply when I'm back."
        return Conversions(g[0]!!.trim(), listOf("OOO reply · $day"), inserts = listOf(reply), hows = listOf(Insertion.REPLACE))
    }

    /** "Best," or "Thanks," on a line of its own at the end of an email:
     *  "Sign as Alex Kim" puts the saved name under it. */
    fun signOff(text: String, fields: List<Field>): Conversions? {
        if (!text.contains('\n')) return null
        val g = firstMatch("""\n\s*((?:best(?:\s+regards|\s+wishes)?|kind\s+regards|warm\s+regards|regards|thanks(?:\s+again|\s+so\s+much)?|thank\s+you|many\s+thanks|cheers|sincerely|yours(?:\s+sincerely|\s+truly)?|cordially|talk\s+soon|warmly|all\s+the\s+best),)\s*\n?$""", text)
            ?: return null
        val line = g[1] ?: return null
        val name = fields.firstOrNull { it.kind == "name" }?.value?.takeIf { it.isNotEmpty() } ?: return null
        return Conversions(line, listOf("Sign as $name"), inserts = listOf(line + "\n" + name), hows = listOf(Insertion.REPLACE))
    }

    // MARK: calories in everyday foods (Smart.swift twin)

    /** kcal for one usual serving, and how that serving is said (USDA
     *  FoodData Central figures, rounded). */
    private val foodCalories: Map<String, Pair<Int, String>> = mapOf(
        "banana" to (105 to "medium"), "apple" to (95 to "medium"), "orange" to (62 to "medium"), "pear" to (101 to "medium"),
        "peach" to (59 to "medium"), "mango" to (202 to "whole"), "avocado" to (240 to "whole"), "kiwi" to (42 to "each"),
        "grapes" to (104 to "1 cup"), "strawberries" to (49 to "1 cup"), "blueberries" to (84 to "1 cup"), "watermelon" to (46 to "1 cup"),
        "pineapple" to (82 to "1 cup"), "cherries" to (97 to "1 cup"), "raspberries" to (64 to "1 cup"), "plum" to (30 to "each"),
        "egg" to (72 to "large"), "boiled egg" to (78 to "large"), "fried egg" to (90 to "large"), "scrambled eggs" to (182 to "2 eggs"),
        "slice of bread" to (80 to "slice"), "bread" to (80 to "slice"), "toast" to (80 to "slice"), "bagel" to (277 to "medium"),
        "croissant" to (231 to "medium"), "muffin" to (377 to "large"), "donut" to (253 to "glazed"), "doughnut" to (253 to "glazed"),
        "pancake" to (90 to "6-inch"), "waffle" to (218 to "7-inch"), "tortilla" to (138 to "flour, 8-inch"), "roti" to (120 to "each"),
        "chapati" to (120 to "each"), "naan" to (262 to "each"), "rice" to (205 to "1 cup cooked"), "white rice" to (205 to "1 cup cooked"),
        "brown rice" to (218 to "1 cup cooked"), "pasta" to (221 to "1 cup cooked"), "spaghetti" to (221 to "1 cup cooked"),
        "noodles" to (219 to "1 cup cooked"), "oatmeal" to (166 to "1 cup cooked"), "oats" to (150 to "½ cup dry"), "quinoa" to (222 to "1 cup cooked"),
        "potato" to (161 to "medium, baked"), "sweet potato" to (103 to "medium, baked"), "fries" to (365 to "medium serving"),
        "french fries" to (365 to "medium serving"), "chips" to (152 to "1 oz"), "popcorn" to (31 to "1 cup popped"),
        "chicken breast" to (165 to "100 g cooked"), "chicken" to (165 to "100 g breast, cooked"), "chicken thigh" to (209 to "100 g cooked"),
        "salmon" to (206 to "100 g cooked"), "tuna" to (132 to "100 g canned"), "shrimp" to (99 to "100 g cooked"), "steak" to (271 to "100 g cooked"),
        "beef" to (250 to "100 g cooked"), "pork chop" to (231 to "100 g cooked"), "bacon" to (43 to "slice"), "sausage" to (229 to "link"),
        "ham" to (46 to "slice"), "turkey" to (135 to "100 g roasted"), "tofu" to (94 to "½ cup"), "paneer" to (265 to "100 g"),
        "hamburger" to (354 to "single patty"), "burger" to (354 to "single patty"), "cheeseburger" to (303 to "single"),
        "big mac" to (590 to "each"), "hot dog" to (290 to "with bun"), "pizza" to (285 to "slice, cheese"), "slice of pizza" to (285 to "cheese"),
        "taco" to (170 to "each"), "burrito" to (430 to "each"), "sushi roll" to (255 to "6 pieces"), "sandwich" to (350 to "average"),
        "salad" to (150 to "side, with dressing"), "soup" to (150 to "1 cup"), "samosa" to (262 to "each"), "dosa" to (168 to "plain"),
        "idli" to (39 to "each"), "biryani" to (290 to "1 cup"),
        "milk" to (103 to "1 cup, 2%"), "whole milk" to (149 to "1 cup"), "skim milk" to (83 to "1 cup"), "almond milk" to (39 to "1 cup"),
        "oat milk" to (120 to "1 cup"), "yogurt" to (149 to "1 cup plain"), "greek yogurt" to (130 to "1 cup plain, nonfat"),
        "cheese" to (113 to "1 oz cheddar"), "butter" to (102 to "1 tbsp"), "peanut butter" to (188 to "2 tbsp"), "almonds" to (164 to "1 oz"),
        "peanuts" to (161 to "1 oz"), "cashews" to (157 to "1 oz"), "walnuts" to (185 to "1 oz"), "olive oil" to (119 to "1 tbsp"),
        "honey" to (64 to "1 tbsp"), "sugar" to (16 to "1 tsp"), "chocolate" to (155 to "1 oz dark"), "ice cream" to (273 to "1 cup vanilla"),
        "cookie" to (78 to "chocolate chip"), "cake" to (350 to "slice"), "brownie" to (227 to "each"),
        "coffee" to (2 to "black, 1 cup"), "latte" to (190 to "16 oz, 2% milk"), "cappuccino" to (130 to "16 oz"), "tea" to (2 to "1 cup"),
        "chai latte" to (240 to "16 oz"), "coke" to (140 to "12 oz can"), "soda" to (140 to "12 oz can"), "diet coke" to (0 to "can"),
        "orange juice" to (112 to "1 cup"), "apple juice" to (114 to "1 cup"), "beer" to (153 to "12 oz"), "wine" to (125 to "5 oz glass"),
        "red wine" to (125 to "5 oz glass"), "white wine" to (121 to "5 oz glass"), "vodka" to (97 to "1.5 oz shot"), "whiskey" to (105 to "1.5 oz shot"),
        "smoothie" to (230 to "16 oz"), "protein shake" to (160 to "1 scoop in water"), "carrot" to (25 to "medium"), "broccoli" to (31 to "1 cup"),
        "cucumber" to (45 to "whole"), "tomato" to (22 to "medium"), "corn" to (88 to "ear"), "peas" to (117 to "1 cup"),
    )

    /** "how many calories in a banana", "calories in 2 eggs", "cals in a
     *  slice of pizza" → ~105 kcal (medium); a count multiplies. */
    fun calories(text: String): Conversions? {
        val g = firstMatch("""\b(?:how\s+many\s+)?(?:calories|cals?|kcals?)\s+(?:are\s+)?(?:in|for)\s+(?:a\s+|an\s+|one\s+|1\s+|(\d{1,2})\s+)?([a-z][a-z ']{1,24}?)\??\s?$""", text)
            ?: firstMatch("""(?:^|\s)(?:a\s+|an\s+|one\s+|(\d{1,2})\s+)?([a-z][a-z ']{1,24}?)\s+(?:calories|cals?|kcals?)\??\s?$""", text)
            ?: return null
        var food = g[2]?.lowercase()?.trim() ?: return null
        val count = g[1]?.toIntOrNull() ?: 1
        var hit = foodCalories[food]
        if (hit == null && food.endsWith("s")) { food = food.dropLast(1); hit = foodCalories[food] }
        if (hit == null && food.endsWith("e")) hit = foodCalories[food.dropLast(1)]
        val (kcal, serving) = hit ?: return null
        if (count < 1 || count > 20) return null
        val said = if (count > 1) "~${kcal * count} kcal ($count × $serving)" else "~$kcal kcal ($serving)"
        return Conversions(g[0]!!.trim(), listOf(said))
    }

    // MARK: styled text, the g menu's Style (Smart.swift twin)

    /** The g menu's Style (Arpit, 2026-10-03: "option to stylise text in glyf
     *  menu like bold italic underline, cut, etc"): letters from Unicode's
     *  styled alphabets, which show in any app because they are characters,
     *  not formatting. Screen readers read some letter by letter, so Plain
     *  puts text back. shared/style/cases.json. */
    enum class TextStyle(val id: String, val title: String, val upper: Int = 0, val lower: Int = 0, val digit: Int? = null) {
        // Bold to strikethrough first (what Arpit asked for), then the case
        // changes people reach for most, then the fancier letters; Plain last.
        BOLD("bold", "Bold", 0x1D5D4, 0x1D5EE, 0x1D7EC),
        ITALIC("italic", "Italic", 0x1D608, 0x1D622),
        BOLD_ITALIC("boldItalic", "Bold italic", 0x1D63C, 0x1D656, 0x1D7EC),
        UNDERLINE("underline", "Underline"),
        STRIKE("strike", "Strikethrough"),
        UPPER("upper", "UPPERCASE"),
        LOWER("lower", "lowercase"),
        TITLE_CASE("titleCase", "Title Case"),
        SENTENCE_CASE("sentenceCase", "Sentence case"),
        SERIF_BOLD("serifBold", "Serif bold", 0x1D400, 0x1D41A, 0x1D7CE),
        SCRIPT("script", "Script", 0x1D4D0, 0x1D4EA),
        DOUBLE_STRUCK("doubleStruck", "Double-struck", 0x1D538, 0x1D552, 0x1D7D8),
        MONOSPACE("monospace", "Monospace", 0x1D670, 0x1D68A, 0x1D7F6),
        BUBBLE("bubble", "Bubble"),
        SMALL_CAPS("smallCaps", "Small caps"),
        WIDE("wide", "Wide"),
        UPSIDE_DOWN("upsideDown", "Upside down"),
        PLAIN("plain", "Plain");

        companion object { fun of(id: String) = values().firstOrNull { it.id == id } }
    }

    /** Double-struck capitals Unicode had already: ℂ ℍ ℕ ℙ ℚ ℝ ℤ. */
    private val doubleStruckHoles = mapOf('C' to 0x2102, 'H' to 0x210D, 'N' to 0x2115, 'P' to 0x2119, 'Q' to 0x211A,
        'R' to 0x211D, 'Z' to 0x2124)
    private val holeScalars = doubleStruckHoles.values.toSet()
    private val smallCapsLetters = "abcdefghijklmnopqrstuvwxyz".toList().zip(listOf("ᴀ", "ʙ", "ᴄ", "ᴅ", "ᴇ", "ꜰ", "ɢ", "ʜ", "ɪ", "ᴊ", "ᴋ",
        "ʟ", "ᴍ", "ɴ", "ᴏ", "ᴘ", "ǫ", "ʀ", "ꜱ", "ᴛ", "ᴜ", "ᴠ", "ᴡ", "x", "ʏ", "ᴢ")).toMap()
    private val flipped: Map<String, String> = buildMap {
        "abcdefghijklmnopqrstuvwxyz".toList().zip(listOf("ɐ", "q", "ɔ", "p", "ǝ", "ɟ", "ƃ", "ɥ", "ı", "ɾ", "ʞ", "ן", "ɯ", "u", "o",
            "d", "b", "ɹ", "s", "ʇ", "n", "ʌ", "ʍ", "x", "ʎ", "z")).forEach { (k, v) -> put(k.toString(), v) }
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ".toList().zip(listOf("∀", "ꓭ", "Ɔ", "ᗡ", "Ǝ", "Ⅎ", "⅁", "H", "I", "ſ", "ꓘ", "˥", "W", "N", "O",
            "Ԁ", "Ό", "ꓤ", "S", "⊥", "∩", "Λ", "M", "X", "⅄", "Z")).forEach { (k, v) -> put(k.toString(), v) }
        "1234567890".toList().zip(listOf("Ɩ", "ᄅ", "Ɛ", "ㄣ", "ϛ", "9", "ㄥ", "8", "6", "0")).forEach { (k, v) -> put(k.toString(), v) }
        putAll(mapOf("." to "˙", "," to "'", "'" to ",", "?" to "¿", "!" to "¡", "(" to ")", ")" to "(", "[" to "]",
            "]" to "[", "{" to "}", "}" to "{", "<" to ">", ">" to "<", "&" to "⅋", "_" to "‾"))
    }

    /** What a person sees as one character each (an emoji with its joins,
     *  a letter with its marks), as iOS's Characters are. */
    private fun graphemes(text: String): List<String> {
        val it = java.text.BreakIterator.getCharacterInstance(java.util.Locale.ROOT)
        it.setText(text)
        val out = mutableListOf<String>()
        var start = it.first()
        var end = it.next()
        while (end != java.text.BreakIterator.DONE) { out.add(text.substring(start, end)); start = end; end = it.next() }
        return out
    }

    private fun cp(v: Int) = String(Character.toChars(v))

    /** Text in a style. It starts from plain letters, so styles don't pile
     *  up; what has no styled form (punctuation, emoji) stays as it is. */
    fun styled(text: String, style: TextStyle): String {
        val base = plainText(text)
        val g = graphemes(base)
        fun ascii(s: String): Int? = if (s.length == 1 && s[0].code < 0x80) s[0].code else null
        return when (style) {
            TextStyle.PLAIN -> base
            TextStyle.UPPER -> base.uppercase()
            TextStyle.LOWER -> base.lowercase()
            TextStyle.TITLE_CASE, TextStyle.SENTENCE_CASE -> recased(base, title = style == TextStyle.TITLE_CASE)
            TextStyle.UNDERLINE, TextStyle.STRIKE -> {
                val mark = if (style == TextStyle.UNDERLINE) "̲" else "̶"
                g.joinToString("") { if (it == "\n") "\n" else it + mark }
            }
            TextStyle.BUBBLE -> g.joinToString("") { s ->
                when (val v = ascii(s)) {
                    in 0x41..0x5A -> cp(0x24B6 + v!! - 0x41)
                    in 0x61..0x7A -> cp(0x24D0 + v!! - 0x61)
                    in 0x31..0x39 -> cp(0x2460 + v!! - 0x31)
                    0x30 -> "⓪"
                    else -> s
                }
            }
            TextStyle.SMALL_CAPS -> g.joinToString("") { s -> s.singleOrNull()?.let { smallCapsLetters[it] } ?: s }
            TextStyle.WIDE -> g.joinToString("") { s ->
                val v = ascii(s)
                when {
                    v == 0x20 -> "　"
                    v != null && v in 0x21..0x7E -> cp(v + 0xFEE0)
                    else -> s
                }
            }
            TextStyle.UPSIDE_DOWN -> g.reversed().joinToString("") { flipped[it] ?: it }
            else -> g.joinToString("") { s ->
                when (val v = ascii(s)) {
                    in 0x41..0x5A -> if (style == TextStyle.DOUBLE_STRUCK && doubleStruckHoles[s[0]] != null)
                        cp(doubleStruckHoles[s[0]]!!) else cp(style.upper + v!! - 0x41)
                    in 0x61..0x7A -> cp(style.lower + v!! - 0x61)
                    in 0x30..0x39 -> style.digit?.let { cp(it + v!! - 0x30) } ?: s
                    else -> s
                }
            }
        }
    }

    /** Words that stay small inside a title. */
    private val smallWords = setOf("a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "on",
        "at", "to", "by", "of", "in", "up", "as", "is", "vs", "via", "per")

    /** The first letter in capitals: "(hello" → "(Hello". */
    private fun capitalised(w: String): String {
        val i = w.indexOfFirst { it.isLetter() }
        if (i < 0) return w
        return w.substring(0, i) + w[i].uppercase() + w.substring(i + 1)
    }

    /** Title Case ("The Lord of the Rings": small words stay small inside)
     *  or Sentence case (a capital to start each sentence, and for "I").
     *  A word in capitals ("NASA") stays as it is, unless the whole text
     *  was in capitals: then it was caps lock. */
    fun recased(text: String, title: Boolean): String {
        val letters = text.filter { it.isLetter() }
        val shouting = letters.isNotEmpty() && letters.count { it.isUpperCase() }.toDouble() / letters.length >= 0.6
        // Words and the space between them, in turn.
        val tokens = mutableListOf<String>()
        val current = StringBuilder()
        var inSpace: Boolean? = null
        for (ch in text) {
            if (inSpace != null && inSpace != ch.isWhitespace()) { tokens.add(current.toString()); current.clear() }
            current.append(ch)
            inSpace = ch.isWhitespace()
        }
        if (current.isNotEmpty()) tokens.add(current.toString())
        val words = tokens.indices.filter { !tokens[it][0].isWhitespace() }
        var startsSentence = true
        val out = StringBuilder()
        for ((i, token) in tokens.withIndex()) {
            if (token[0].isWhitespace()) {
                if ('\n' in token) startsSentence = true
                out.append(token)
                continue
            }
            val acronym = !shouting && token.length > 1 && token == token.uppercase() && token != token.lowercase()
            val lower = token.lowercase()
            var word = when {
                acronym -> token
                title -> if (i != words.first() && i != words.last() && lower in smallWords) lower else capitalised(lower)
                startsSentence || lower == "i" || lower.startsWith("i'") -> capitalised(lower)
                else -> lower
            }
            if (title && startsSentence) word = capitalised(word)
            out.append(word)
            startsSentence = token.last() in ".!?"
        }
        return out.toString()
    }

    /** "12 words · 64 characters": what the Style screen says of the text. */
    fun textCount(text: String): String {
        val words = text.split(Regex("""\s+""")).count { it.isNotEmpty() }
        val characters = graphemes(text).size
        return "$words word${if (words == 1) "" else "s"} · $characters character${if (characters == 1) "" else "s"}"
    }

    /** Styled text back to plain letters (Smart.swift's plainText): marks
     *  off, the styled alphabets, circles and wide letters back to their
     *  own, small capitals to small letters. ™, ½ and emoji stay. */
    fun plainText(text: String): String {
        val small = smallCapsLetters.entries.filter { it.key != 'x' }.associate { (k, v) -> v to k }
        val out = StringBuilder()
        for (g in graphemes(text)) {
            val s = g.replace("̲", "").replace("̶", "")
            if (s.isEmpty()) continue
            val v = s.codePointAt(0)
            val styledLetter = v in 0x1D400..0x1D7FF || v in holeScalars || v in 0x2460..0x24FF ||
                v in 0xFF01..0xFF5E || v == 0x3000
            when {
                styledLetter -> out.append(java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFKC))
                small[s] != null -> out.append(small[s])
                else -> out.append(s)
            }
        }
        return out.toString()
    }

    // MARK: questions (the AI answer chip, as it is typed)

    /** A question for a fact, told by its words on the phone (Arpit,
     *  2026-09-30: "we can detect questions too with what where like words"):
     *  the strip offers "AI answer" as it is typed, with no wait for the
     *  server's read. The server's rules (lib/act.ts infoQuestion, searchLike,
     *  answers.ts rightNow), with one more: the question has to end on a word
     *  of substance, so "who is the" offers nothing yet. The question (the
     *  last sentence typed), or null. iOS Smart.question's twin;
     *  shared/questions/cases.json holds the cases both run. */
    fun question(text: String): String? {
        var t = text.trim().replace('’', '\'').replace('‘', '\'')
        if (t.isEmpty() || t.length > 160) return null
        // The last line, then the last sentence: "ok cool. who painted it?"
        val nl = t.lastIndexOf('\n')
        if (nl >= 0) t = t.substring(nl + 1)
        val asked = t.endsWith("?")
        var body = t.replace(QuestionRules.trailing, "")
        QuestionRules.lastSentence.find(body)?.let { body = body.substring(it.range.last + 1) }
        // Already answered: the strip's own answer went in after it ("whats
        // 15% of 240 = 36", "10 km to miles (6.21 miles)" offered AI answer
        // again, 2026-10-14).
        if ('=' in body || body.endsWith(")")) return null
        val lower = body.lowercase().replace(QuestionRules.spaces, " ").trim()
        val words = lower.split(' ').filter { it.isNotEmpty() }
        if (words.size < 3 || words.size > 12) return null
        if (!asked && !QuestionRules.start.containsMatchIn(lower)) return null
        // "how to make pancakes" is a video to find, not a fact.
        if (lower.startsWith("how to ")) return null
        for (rule in listOf(QuestionRules.chitchat, QuestionRules.secondPerson, QuestionRules.addressed,
                            QuestionRules.ownPlans, QuestionRules.localAsk, QuestionRules.smallTalk,
                            QuestionRules.rightNow)) {
            if (rule.containsMatchIn(lower)) return null
        }
        // "does it hurt?", "is that true": short, and about the chat.
        if (words.size <= 4 && QuestionRules.pointing.containsMatchIn(lower)) return null
        val bare = QuestionRules.searchMe.replace(lower, " ")
        if (QuestionRules.people.containsMatchIn(bare)) return null
        // Still being typed: "who is the", "what does".
        if (!asked && words.last() in QuestionRules.unfinished) return null
        val q = body.trim()
        return if (asked) "$q?" else q
    }

    /** The server's word lists, as it has them (lib/act.ts), and iOS has them. */
    private object QuestionRules {
        val trailing = Regex("""[?!.\s]+$""")
        val lastSentence = Regex("""^.*[.!?]\s+""")
        val spaces = Regex("""\s+""")
        val start = Regex("""^(?:what|what's|whats|who|who's|whos|whose|whom|where|where's|wheres|when|when's|whens|why|how|how's|hows|which|is|isn't|are|aren't|was|were|can|can't|could|do|does|don't|doesn't|did|didn't|will|won't|would|should|shall|have|has|may|might|any)\b""")
        val chitchat = Regex("""^(?:ok(?:ay)?|k+|kk|hi+|hey+|hello|yo|sup|wass?up|what'?s up|whats up|wyd|hru|how (?:are|r) (?:you|u)|how'?s it going|good (?:morning|night|evening|afternoon)|gm|gn|thanks?|thank you|thx|ty|lol|haha\w*|yes|yeah|yep|no|nope|sure|cool|nice|great|done|np|no worries|see (?:you|u|ya)(?: soon| later)?|bye|cya|ttyl|lmk|brb|omw)(?:\s+(?:bro|dude|man|yaar|bhai|mate|buddy))?[\s!?.]*$""")
        val secondPerson = Regex("""\b(?:u|ur|you|your|yours|you're|youre|ya|yall|y'all|tu|tum|tumhe|tumko|tumne|tumhara|tumhari|tumhare|tera|teri|tere|aap|aapko|aapne|aapka|aapki|aapke)\b""")
        val addressed = Regex("""^(?:bhai|bro|bruh|yaar|dude|mom|mum|maa|papa|dad|didi|bhaiya|babe|baby|hey|hi|hello|yo|oye|arre)\b|\b(?:bhai|bro|yaar|dude|babe|bhaiya|didi)[?!.]*$""")
        val ownPlans = Regex("""\b(?:the|our|my|ur|your|this|tonight'?s|tomorrow'?s|tmrw'?s)\s+(?:meeting|meet|party|call|dinner|lunch|brunch|breakfast|appointment|appt|flight|reservation|booking|interview|class|practice|rehearsal|wedding|event|plan|plans|trip|standup|stand-up|shift|session|date|hangout|get together|get-together|pickup|pick up|drop off|shoot|exam|gig|reunion|sleepover|potluck|bus|train|metro|subway|uber|lyft|cab|taxi|ride|delivery|order|package|parcel)\b|\bwho(?:'s| is| all is| all are| are)\s+(?:coming|joining|going|in|bringing)\b""")
        /** A question for a person there, not a fact: "is the store open",
         *  "whats the wifi password", "where are the keys". */
        val localAsk = Regex("""\b(?:password|passcode|wifi|wi-fi|door code|the (?:store|shop|pharmacy|mall|gym|car|kids|dog|cat|baby|fridge|remote|charger|keys?))\b""")
        /** iOS's \p{Extended_Pictographic}, as ranges the phone's and the
         *  JVM's regex engines both read: the symbol blocks and the emoji
         *  planes. */
        val smallTalk = Regex("""\b(?:thanks|thank you|thx|tnx|ty|lol|lmao|lmfao|rofl|haha\w*|hehe\w*|omg|congrats|sorry|sry|pls|plz|please|hey|hi|hello|yo|bro|dude|yaar|bhai|okay|ok|kk|yeah|yep|yup|nope|sure)\b|!|[\x{00A9}\x{00AE}\x{203C}\x{2049}\x{2122}\x{2139}\x{2194}-\x{21AA}\x{231A}-\x{23FF}\x{24C2}\x{25AA}-\x{27BF}\x{2934}\x{2935}\x{2B05}-\x{2B55}\x{3030}\x{303D}\x{3297}\x{3299}\x{1F000}-\x{1FAFF}]""")
        /** Today's score or the news: the AI can't know, so no chip that
         *  would only say "Nothing found" (answers.ts rightNow). */
        val rightNow = Regex("""\b(?:scores?|live|right now|today'?s?|tonight'?s?|this (?:morning|afternoon|evening|week|weekend)|yesterday'?s?|last night'?s?|news|headlines?|breaking|stock price|share price|trading at|exchange rates?|forex|forecast|weather|time is it|time in)\b""")
        val pointing = Regex("""\b(?:it|this|that|these|those|there)\b""")
        val people = Regex("""\b(?:i|i'm|im|i've|ive|i'll|i'd|me|my|mine|myself|we|we're|we've|we'll|we'd|us|our|ours|u|ur|you|you're|youre|you've|you'll|you'd|your|yours|ya|yall|y'all|let's|lets|he|she|him|her|his|hers|they|them|their|theirs)\b""")
        val searchMe = Regex("""\b(?:near|around|for|to|from|with)\s+me\b|^(?:send|show|give|find|get|play|tell)\s+me\b""")
        /** A question can't end on these: it is still being typed. */
        val unfinished = setOf(
            "the", "a", "an", "of", "in", "on", "at", "to", "for", "from", "with", "by", "and", "or", "but",
            "is", "are", "was", "were", "be", "been", "do", "does", "did", "has", "have", "had", "what",
            "who", "where", "when", "why", "how", "which", "whose", "whom", "this", "that", "these", "those",
            "some", "any", "much", "many", "than", "as", "about", "into", "over", "like", "if", "so", "not",
            "can", "could", "will", "would", "should", "shall", "may", "might", "must", "very", "more",
            "most", "less", "per", "vs", "via", "its", "no",
        )
    }
}
