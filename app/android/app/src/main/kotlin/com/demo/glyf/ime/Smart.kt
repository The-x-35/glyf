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
        data class Calc(val result: String, val hasEquals: Boolean) : Chip()
        /** "my upi id is " -> the saved UPI. */
        data class Vault(val field: Field) : Chip()
        /** The model read the sentence and named what Glyf could do with it. */
        data class Action(val label: String, val query: String, val intent: String) : Chip()
        /** A Solana address on screen: one tap opens the wallet with it. */
        data class Pay(val address: String, val amount: String?) : Chip()
        /** "$13" → "$13 = ₹1,246" where the phone is; "$sol" → "1 SOL = $112".
         *  `shown` is the whole line, `insert` what a tap adds after the
         *  amount. Never offered without a live rate. */
        data class Money(val shown: String, val insert: String) : Chip()
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
    ) { companion object { val EMPTY = RatesSnapshot() } }

    /** The small label on the chip's left, when there is one. */
    fun key(chip: Chip): String? = (chip as? Chip.Vault)?.field?.title

    /** What a tap does, on the chip's right edge; null for the model's own words. */
    fun verb(chip: Chip): String? = when (chip) {
        is Chip.Calc, is Chip.Vault, is Chip.Money -> "Insert"
        is Chip.Event -> "Add"
        is Chip.Booking -> "Book"
        is Chip.Pay -> "Pay"
        is Chip.Action -> null
    }

    /** What the chip says. */
    fun display(chip: Chip): String = when (chip) {
        is Chip.Calc -> chip.result
        is Chip.Vault -> chip.field.value
        is Chip.Action -> chip.label
        is Chip.Money -> chip.shown
        is Chip.Event -> EventParse.summary(chip.plan)
        is Chip.Booking -> "A time on ${shortLink(chip.link)}"
        is Chip.Pay -> {
            val a = chip.address
            val short = if (a.length > 12) "${a.take(4)}…${a.takeLast(4)}" else a
            if (chip.amount != null) "${chip.amount} USDC to $short" else "privately to $short"
        }
    }

    /** What tapping puts in the field. */
    fun insert(chip: Chip): String = when (chip) {
        is Chip.Calc -> if (chip.hasEquals) " ${chip.result}" else " = ${chip.result}"
        is Chip.Vault -> chip.field.value
        is Chip.Money -> chip.insert
        is Chip.Action, is Chip.Pay, is Chip.Event, is Chip.Booking -> ""
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
             rates: RatesSnapshot = RatesSnapshot.EMPTY, ownBooking: String? = null): Chip? {
        payment(text)?.let { return Chip.Pay(it.first, it.second ?: amountAsked(text)) }
        calc(text, indianGrouping)?.let { return Chip.Calc(it.first, it.second) }
        money(text, rates)?.let { return it }
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
            val price = format(usd, "USD")
            return Chip.Money("1 $ticker = $price", " = $price")
        }
        val m = amountPattern.find(text) ?: return null
        val amount = (m.groups[2]?.value ?: m.groups[3]?.value ?: "")
            .replace(",", "").toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val from = currencyOf(unitOf(m)) ?: return null
        // Where the phone is, or dollars when the amount already is local.
        val to = if (from == rates.local) "USD" else rates.local
        if (to == from) return null
        val fromRate = rates.fiat[from]?.takeIf { it > 0 } ?: return null
        val toRate = rates.fiat[to] ?: return null
        val result = format(amount / fromRate * toRate, to)
        return Chip.Money("${format(amount, from)} = $result", " = $result")
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
    private val hasOperator = Regex("""[+*/×÷^%]|\bx\b|\bof\b""", RegexOption.IGNORE_CASE)

    fun calc(text: String, indianGrouping: Boolean = true): Pair<String, Boolean>? {
        if (text.isEmpty()) return null
        val m = calcPattern.find(text) ?: return null
        val expr = m.groups[1]?.value ?: return null
        val hasEquals = m.groups[2] != null
        // A bare number is not a sum; only offer when an operator is present.
        if (!hasEquals && !hasOperator.containsMatchIn(expr)) return null
        val v = evaluate(expr) ?: return null
        val currency = expr.firstOrNull { it in "₹$€£" }?.toString() ?: ""
        return (currency + format(v, indianGrouping)) to hasEquals
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
                val rhs = product()
                v = if (rhs == null) null else if (op == "+") v + rhs else v - rhs
            }
            v
        }
        val v = sum() ?: return null
        return if (i == tokens.size && v.isFinite()) v else null
    }

    // MARK: Payments

    private val addressPattern =
        Regex("""(?<![A-HJ-NP-Za-km-z1-9])([1-9A-HJ-NP-Za-km-z]{32,44})(?![A-HJ-NP-Za-km-z1-9])""")

    fun payment(text: String): Pair<String, String?>? {
        if (text.isEmpty()) return null
        val address = addressPattern.find(text)?.groups?.get(1)?.value ?: return null
        // A real key mixes cases and digits; a run of letters is a sentence.
        if (address.none { it.isUpperCase() } || address.none { it.isLowerCase() } ||
            address.none { it.isDigit() }) return null
        return address to amountAsked(text)
    }

    /** "send $200" / "200 usdc" -> "200". */
    fun amountAsked(text: String): String? {
        for (p in listOf("""[$₹]\s*([\d,]+(?:\.\d{1,6})?)""",
                         """([\d,]+(?:\.\d{1,6})?)\s*(?:usdc|usdt|dollars?)""")) {
            val m = Regex(p, RegexOption.IGNORE_CASE).find(text) ?: continue
            val digits = m.value.filter { it.isDigit() || it == '.' }
            if (digits.isNotEmpty()) return digits
        }
        return null
    }

    // MARK: Contextual vault

    /** Sentence endings that mean "the next thing I type is X". */
    private val triggers: List<Triple<Regex, List<String>, String?>> = listOf(
        Triple("""\b(my name is|name:|this is)\s*$""", listOf("name"), null),
        // Before address: "my wallet address" asks for the wallet.
        Triple("""\b(wallet|sol|solana|phantom|usdc|crypto)(?:\s*(?:address|addy|wallet))?\s*(?:is\s*)?:?\s*$""", listOf("wallet"), null),
        Triple("""\b(address|deliver(?: it)? to|send (?:it |the \w+ )?to|ship (?:it )?to|come to|pick me up (?:from|at))\s*(?:is\s*)?:?\s*$""", listOf("address"), null),
        Triple("""\b(upi|gpay|google pay|phonepe|paytm)(?:\s*id)?\s*(?:is\s*)?:?\s*$""", listOf("upi"), null),
        Triple("""\bpay me (?:at|on)\s*$""", listOf("upi"), null),
        Triple("""\b(insta|instagram|ig)(?:\s*(?:handle|id))?\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "insta"),
        Triple("""\b(twitter|on x|x handle)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "x"),
        Triple("""\blinkedin\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "linkedin"),
        Triple("""\b(e-?mail|mail)(?:\s*id)?\s*(?:is\s*)?:?\s*$""", listOf("email"), null),
        Triple("""\b(number|phone|mobile|whatsapp|call me (?:at|on))\s*(?:is\s*)?:?\s*$""", listOf("phone"), null),
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
                candidates.firstOrNull { it.label.lowercase().contains(label) }?.let { return it }
                continue
            }
            // The sentence named the kind; with none saved there is nothing to offer.
            return candidates.firstOrNull()
        }
        return firstPersonMatch(text, fields)
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
            val field = fields.firstOrNull { it.kind == kind || (kind == "social" && it.kind == "handle") } ?: continue
            // The detail itself has not been typed yet.
            val after = clause.substring(m.range.last + 1).replace(Regex("""^[\s:,-]*(is|are|=)?[\s:,-]*"""), "")
            if (after.length <= 3) return field
        }
        return null
    }
}
