package com.demo.glyf.ime

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
         *  a temp mail option"). Smart.swift's `.details`. */
        data class Details(val fields: List<Field>, val temp: Boolean) : Chip()
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
        is Chip.Event -> EventParse.summary(chip.plan)
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
        chip is Chip.Details && !chip.temp && chip.fields.firstOrNull()?.kind == "email" ->
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
             region: String? = java.util.Locale.getDefault().country): Chip? {
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
        calcMatch(text, indianGrouping)?.let { (value, hasEquals, expression) ->
            return Chip.Calc(value, hasEquals).also { it.expression = expression }
        }
        money(text, rates)?.let { return it }
        // A cashtag waits for its price: "$sol" is SOL's price, never your
        // Solana wallet, even before the price has come.
        if (cashtag(text) != null) return null
        quickAnswer(text, region = region)?.let { return Chip.Convert(it) }
        // Every saved value the sentence asks for: two emails show both.
        val matches = vaultMatches(text, fields)
        if (matches.size > 1) return Chip.Details(matches.take(3), temp = false)
        matches.firstOrNull()?.let { return Chip.Vault(it) }
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
        """\s*(?:\d{1,2}\s*/\s*\d{1,2}\s*/\s*\d{2,4}|\d{4}\s*/\s*\d{1,2}\s*/\s*\d{1,2}|\d{1,2}\s*/\s*(?:19|20)\d{2}|""" +
            """\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}-\d{4}|(?:\d{1,3}-)?\d{3}-\d{3}-\d{4}|\d{3}-\d{4}|\d{5}-\d{5})\s*""")
    private val comparison = Regex("""\s*(>=|<=|≥|≤|>|<)\s*""")

    fun calc(text: String, indianGrouping: Boolean = true): Pair<String, Boolean>? =
        calcMatch(text, indianGrouping)?.let { it.first to it.second }

    /** The sum at the end of the text: its value, whether "=" is typed, and
     *  the sum as typed. A comparison is "true" or "false". */
    fun calcMatch(text: String, indianGrouping: Boolean = true): Triple<String, Boolean, String>? {
        if (text.isEmpty()) return null
        val m = calcPattern.find(text) ?: return null
        val expr = m.groups[1]?.value ?: return null
        val hasEquals = m.groups[2] != null
        if (!hasEquals && !hasOperator.containsMatchIn(expr)) return null
        if (!hasEquals && notASum.matches(expr)) return null
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
        Triple("""(?:^|[\s,(])(?<!\b(?:can|could|will|would|should|shall|must|i'll|ill|we'll|i|we|you|u|they|he|she|to|pls|please|gonna|wanna|the|this|that|a|an)\s)(?:e-?mail|g-?mail|mail\s*id)(?:\s*(?:id|address|addy))?\s*(?:is\s*)?:?\s*$""", listOf("email"), null),
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
            else -> fields.filter { it.kind == kind }
        }
        return found.distinctBy { it.value.trim().lowercase() }
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
        add("m", "meter", "meters", "metre", "metres", "mtr", "mtrs")
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
        "sq ft" -> 0.09290304; "sq m" -> 1.0; "acre" -> 4046.8564224; "hectare" -> 10000.0
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
        val m = stripMeasure.find(t)?.takeIf { !partOfMore(it) } ?: return null
        val n = amount(m.groupValues[1])?.takeIf { it.isFinite() } ?: return null
        val name = m.groupValues[2].lowercase()
        val unit = stripNames[name] ?: return null
        // "4g", "5g": a network, not grams. "10 pounds" is money outside the US.
        if (unit == "g" && name == "g" && Regex("^[2-6]g", RegexOption.IGNORE_CASE).containsMatchIn(m.value)) return null
        if (name.startsWith("pound") && !us) return null
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
                when (unit) {
                    "mm" -> listOf(to("inch"))
                    "cm" -> if (base >= 0.3 && base < 3) listOf(feetInches(base), to("inch")) else listOf(to("inch"))
                    "m" -> if (base < 3) listOf(feetInches(base), to("foot")) else listOf(to("foot"), to("yard"))
                    "km" -> listOf(to("mile"))
                    "inch" -> listOf(to("cm"), to("m"))
                    "foot" -> if (n < 10) listOf(to("m"), to("cm")) else listOf(to("m"))
                    "yard" -> listOf(to("m"))
                    "mile" -> listOf(to("km"))
                    "g" -> listOf(to("oz"))
                    "kg" -> listOf(to("lb"))
                    "oz" -> listOf(metricMass())
                    "lb" -> listOf(to("kg"))
                    "stone" -> listOf(to("kg"), to("lb"))
                    "ml" -> listOf(to("fl oz"))
                    "litre" -> if (uk) listOf(to("pint"), to("gallon")) else listOf(to("gallon"), to("fl oz"))
                    "tsp", "tbsp", "fl oz", "cup", "pint" -> listOf(metricVolume())
                    "quart", "gallon" -> listOf(to("litre"))
                    "km/h" -> listOf(to("mph"))
                    "mph" -> listOf(to("km/h"))
                    "m/s", "knot" -> listOf(to("km/h"), to("mph"))
                    "sq ft" -> listOf(to("sq m"))
                    "sq m" -> listOf(to("sq ft"))
                    "acre" -> listOf(to("hectare"))
                    "hectare" -> listOf(to("acre"))
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
     *  ends, in the order tried: a measurement, a time in another zone, a
     *  bill (split, tip, discount, tax), when someone will be there, how long
     *  a span of minutes is, and a date in words. One chip per result; a tap
     *  adds it in brackets. shared/quick/strip-cases.json. */
    fun quickAnswer(text: String, now: java.time.Instant = java.time.Instant.now(),
                    here: java.time.ZoneId = java.time.ZoneId.systemDefault(),
                    region: String? = java.util.Locale.getDefault().country): Conversions? {
        if (text.length > 400) return null
        return shortcut(text, now, here, region)
            ?: conversions(text, region)
            ?: zoneTimes(text, now, here, region)
            ?: billMath(text)
            ?: arrival(text, now, here)
            ?: dateInWords(text, now, here, region)
            ?: bases(text)
            ?: colours(text)
            ?: tracking(text)
            ?: flight(text)
            ?: phone(text, region)
            ?: unixTime(text, here, region)
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
            """\bsplit\s+(?:the\s+)?(?:bill\s+(?:of\s+)?)?$SYM\s*$AMT\s+(?:in\s+|into\s+|between\s+|among\s+|by\s+|with\s+)?(\d{1,2})$ways$END""",
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
            """\b$PCT\s*tip\s*(?:on|for|of)?\s*$SYM\s*$AMT$END""" to true,
            """\btip\s+(?:of\s+)?$PCT\s*(?:on|for)\s*$SYM\s*$AMT$END""" to true,
            """$SYM\s*$AMT\s*(?:\+|plus|with|and)\s*$PCT\s*tip$END""" to false,
        )
        for ((p, first) in tips) {
            val g = firstMatch(p, text) ?: continue
            val (percent, s, bill) = pick(g, first) ?: continue
            val tip = bill * percent / 100
            return Conversions(g[0]!!.trim(), listOf("${billMoney(tip, s)} tip", "${billMoney(bill + tip, s)} total"))
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
     *  "the 14th"; "oct 14" or "14 october". Never a lone weekday, "today"
     *  or "tomorrow". */
    fun dateInWords(text: String, now: java.time.Instant, here: java.time.ZoneId, region: String?): Conversions? {
        val today = now.atZone(here).toLocalDate()
        fun say(g: List<String?>, dates: List<java.time.LocalDate>) =
            Conversions(g[0]!!.trim(), dates.map { dayName(it, today, region) })
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
                if (!date.isBefore(today)) return say(g, listOf(date))
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
        return say(g, listOf(date))
    }

    // MARK: shortcuts, numbers, colours, parcels, flights and phones (Smart.swift twin)

    /** The shortcuts the keyboard knows itself; the person's own shorthand
     *  of the same name wins (the keyboard leaves the chip out then). */
    val builtInShortcuts = setOf(";date", ";today", ";time", ";now", ";tmrw", ";tomorrow", ";yday", ";yesterday", ";iso")

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
        firstMatch("""\brgba?\(\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*(?:[,/]\s*[\d.]+%?\s*)?\)$END""", text)?.let { g ->
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
            if (says("usps")) return link("USPS tracking", "https://tools.usps.com/go/TrackConfirmAction?tLabels=${g[1]!!.filter { it.isDigit() }}", g)
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

    // MARK: styled text, the g menu's Style (Smart.swift twin)

    /** The g menu's Style (Arpit, 2026-10-03: "option to stylise text in glyf
     *  menu like bold italic underline, cut, etc"): letters from Unicode's
     *  styled alphabets, which show in any app because they are characters,
     *  not formatting. Screen readers read some letter by letter, so Plain
     *  puts text back. shared/style/cases.json. */
    enum class TextStyle(val id: String, val title: String, val upper: Int = 0, val lower: Int = 0, val digit: Int? = null) {
        BOLD("bold", "Bold", 0x1D5D4, 0x1D5EE, 0x1D7EC),
        ITALIC("italic", "Italic", 0x1D608, 0x1D622),
        BOLD_ITALIC("boldItalic", "Bold italic", 0x1D63C, 0x1D656, 0x1D7EC),
        UNDERLINE("underline", "Underline"),
        STRIKE("strike", "Strikethrough"),
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
