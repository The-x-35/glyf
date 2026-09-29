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

    /** What a tap does, on the chip's right edge; null for the model's own words. */
    fun verb(chip: Chip): String? = when (chip) {
        is Chip.Calc, is Chip.Vault, is Chip.Money -> "Insert"
        is Chip.Event -> "Add"
        is Chip.Booking -> "Book"
        is Chip.Pay -> "Send"
        is Chip.Buy -> "Buy"
        is Chip.Action -> null
    }

    /** What the chip says. */
    fun display(chip: Chip): String = when (chip) {
        // The whole sum where it fits: "2+5 = 7" reads as an answer, "7" alone
        // was easy to miss (user, 2026-09-29: "show result in recommendation strip").
        is Chip.Calc -> if (chip.expression.isEmpty() || chip.expression.length > 22) "= ${chip.result}"
            else "${chip.expression} = ${chip.result}"
        is Chip.Vault -> chip.field.value
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
        is Chip.Action, is Chip.Pay, is Chip.Buy, is Chip.Event, is Chip.Booking -> ""
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
     *  in another currency, a detail. */
    fun chip(text: String, fields: List<Field>, indianGrouping: Boolean = true,
             rates: RatesSnapshot = RatesSnapshot.EMPTY, ownBooking: String? = null,
             ownWallet: String? = null): Chip? {
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
        vaultMatch(text, fields)?.let { return Chip.Vault(it) }
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

    /** "₹1,246", "$5.21", "AED 47.7": the symbol where one is common, the
     *  code elsewhere; Indian grouping for rupees, whole yen and won. */
    fun format(value: Double, code: String): String {
        val v = if (code == "JPY" || code == "KRW") Math.round(value).toDouble() else value
        return (currencySymbol[code] ?: "$code ") + format(v, code == "INR")
    }

    // MARK: Calculator

    private const val NUM = """(?:[₹$€£]\s*)?\d[\d,]*(?:\.\d+)?%?"""
    private const val OP = """(?:[-+*/×÷^]|\bx\b|\bof\b)"""
    private val calcPattern = Regex(
        """(\(?\s*$NUM\s*\)?(?:\s*$OP\s*\(?\s*$NUM\s*\)?)+)(\s*=)?\s*$""",
        RegexOption.IGNORE_CASE)
    /** "of" alone is not an operator: "page 2 of 10" is no sum, "20% of 150" is. */
    private val hasOperator = Regex("""[+*/×÷^%]|\bx\b""", RegexOption.IGNORE_CASE)
    private val lonelyMinus = Regex("""\s*(?:[₹$€£]\s*)?(\d[\d,]*(?:\.\d+)?)\s*(-)\s*(?:[₹$€£]\s*)?(\d[\d,]*(?:\.\d+)?)\s*""")

    /** "150-45" or "5 - 2" typed on their own. Not "3-2" or "9-5" (a score,
     *  a job), and nothing below zero ("10-11" is a range, "555-1234" a
     *  number). */
    private fun loneSubtraction(expr: String): Boolean {
        val m = lonelyMinus.matchEntire(expr) ?: return false
        val a = m.groupValues[1].replace(",", "").toDoubleOrNull() ?: return false
        val b = m.groupValues[3].replace(",", "").toDoubleOrNull() ?: return false
        return a >= b && (a >= 100 || Regex("""\s-\s""").containsMatchIn(expr))
    }
    /** "24/7" and dates: "9/28", "28/9", "29/09/2024", "2024/09/29", "exp 09/2026". */
    private val smallOverSmall = Regex(
        """\s*(?:\d{1,2}\s*/\s*\d{1,2}|\d{1,2}\s*/\s*\d{1,2}\s*/\s*\d{2,4}|\d{4}\s*/\s*\d{1,2}\s*/\s*\d{1,2}|\d{1,2}\s*/\s*(?:19|20)\d{2})\s*""")

    fun calc(text: String, indianGrouping: Boolean = true): Pair<String, Boolean>? =
        calcMatch(text, indianGrouping)?.let { it.first to it.second }

    /** The sum at the end of the text: its value, whether "=" is typed, and
     *  the sum as typed. */
    fun calcMatch(text: String, indianGrouping: Boolean = true): Triple<String, Boolean, String>? {
        if (text.isEmpty()) return null
        val m = calcPattern.find(text) ?: return null
        val expr = m.groups[1]?.value ?: return null
        val hasEquals = m.groups[2] != null
        // A bare number is not a sum; only offer when an operator is present.
        // A dash is one only in a sum typed on its own ("150-45"): in a
        // sentence it is a range, a score or a phone number ("won 3-2").
        if (!hasEquals && !hasOperator.containsMatchIn(expr) && !(expr.trim() == text.trim() && loneSubtraction(expr))) return null
        // "24/7" and dates read as numbers over numbers: with no "=", they
        // are not a sum.
        if (!hasEquals && smallOverSmall.matches(expr)) return null
        val v = evaluate(expr) ?: return null
        val currency = expr.firstOrNull { it in "₹$€£" }?.toString() ?: ""
        return Triple(currency + format(v, indianGrouping), hasEquals, expr.trim().replace(Regex("""\s+"""), " "))
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
            .replace(Regex("""\bx\b"""), "*")
            .replace("×", "*").replace("÷", "/")
        src = src.filterNot { it in "₹$€£, \t" }
        if (src.isEmpty()) return null

        val tokens = mutableListOf<String>()
        val number = StringBuilder()
        for (ch in src) {
            when {
                ch.isDigit() || ch == '.' -> number.append(ch)
                ch in "+-*/^()%" -> {
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
            while (peek() == "*" || peek() == "/") {
                val op = peek()
                i++
                val rhs = power() ?: return null
                if (op == "/") {
                    if (rhs == 0.0) return null
                    v /= rhs
                } else v *= rhs
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
     *  not enough: "wrong address", "can you email", "i lost my phone" and
     *  "saw it on insta" are about something else. Smart.swift's twin. */
    private val triggers: List<Triple<Regex, List<String>, String?>> = listOf(
        // "This is" introduces you only at the start: "Hi, this is", not "this is great".
        Triple("""(?:\bmy name is|\bname:|(?:^|[.!?,\n]\s*|\b(?:hi|hey|hello|hii|hiya)\W*)this is)\s*$""", listOf("name"), null),
        // Before address: "my wallet address" asks for the wallet.
        // A coin's name alone is not a wallet ("$sol" is its price, "I bought
        // sol" a purchase), nor is someone else's ("phantom wallet is down").
        Triple("""(?<!\$)\b(?:(?:my|our)\s+(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet(?:\s+(?:address|addy))?|(?:my|our)\s+(?:sol|solana|phantom|usdc|crypto)\s+(?:address|addy)|(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet(?:\s+(?:address|addy))?\s*:|(?:sol|solana|phantom|usdc|crypto)\s+(?:address|addy)\s*:)\s*(?:is\s*)?:?\s*$""", listOf("wallet"), null),
        // Before address: "my email address is" is an email.
        Triple("""\b(?:(?:my|our)\s+(?:e-?mail|g-?mail|mail)(?:\s*(?:id|address|addy))?|(?:e-?mail|g-?mail|mail)\s+(?:me|us)\s+(?:at|on)|(?:e-?mail|g-?mail)(?:\s*(?:id|address|addy))?\s*:|mail\s*id\s*:)\s*(?:is\s*)?:?\s*$""", listOf("email"), null),
        // An IP, web or website address is no place to deliver to.
        Triple("""(?:\b(?:my|our)\s+(?:(?:home|delivery|shipping|office|current|new)\s+)?(?:address|addy)|(?<!e-?mail\s)(?<!gmail\s)(?<!ip\s)(?<!web\s)(?<!website\s)(?<!mac\s)\b(?:(?:home|delivery|shipping|office)\s+)?address\s*:|\bdeliver(?:\s+it)?\s+to|\bsend\s+it\s+to|\bship\s+(?:it\s+)?to|\bcome\s+(?:over\s+)?to|\bpick\s+me\s+up\s+(?:from|at))\s*(?:is\s*)?:?\s*$""", listOf("address"), null),
        Triple("""\b(?:(?:my|our)\s+(?:upi|vpa|gpay|google\s+pay|phonepe|paytm)(?:\s+(?:id|number|handle))?|(?:upi|vpa|gpay|phonepe|paytm)(?:\s*id)?\s*:|(?:pay|gpay|phonepe|paytm)\s+me\s+(?:at|on))\s*(?:is\s*)?:?\s*$""", listOf("upi"), null),
        Triple("""\b(?:(?:my|our)\s+(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?|(?:follow|find|add|dm)\s+(?:me|us)\s+on\s+(?:insta|instagram|ig)|(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?\s*:)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "insta"),
        Triple("""\b(?:(?:my|our)\s+(?:twitter|x)(?:\s+(?:handle|id|username))?|(?:follow|find|dm)\s+(?:me|us)\s+on\s+(?:twitter|x)|(?:twitter|x\s+handle)\s*:)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "x"),
        Triple("""\b(?:(?:my|our)\s+linkedin(?:\s+(?:profile|url|handle|id))?|(?:find|add|connect\s+with)\s+(?:me|us)\s+on\s+linkedin|linkedin\s*:)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "linkedin"),
        // A phone number, not an account, card, order or ticket number, and
        // not the phone itself ("i lost my phone").
        Triple("""\b(?:(?:my|our)\s+(?:(?:phone|mobile|cell|contact|whatsapp)\s+)?(?:number|no\.?|num)|(?:my|our)\s+whatsapp|(?:phone|mobile|cell|contact|whatsapp)(?:\s+(?:number|no\.?|num))?\s*:|(?:call|text|whatsapp|ping|reach|ring)\s+(?:me|us)\s+(?:at|on))\s*(?:is\s*)?:?\s*$""", listOf("phone"), null),
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
    private val plainSum = Regex("""^[\d\s.,+\-*/×÷^()%x]+$""")
    private val anOperation = Regex("""\d\s*(?:[-+*/×÷^%]|x)\s*[\d(]|\d\s*%""")

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
}
