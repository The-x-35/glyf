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

    data class Field(val kind: String, val label: String, val value: String)

    sealed class Chip {
        /** "3480/4" -> " = 870"; `hasEquals` when the "=" is already typed. */
        data class Calc(val result: String, val hasEquals: Boolean) : Chip()
        /** "my upi id is " -> the saved UPI. */
        data class Vault(val field: Field) : Chip()
        /** The model read the sentence and named what Glyf could do with it. */
        data class Action(val label: String, val query: String, val intent: String) : Chip()
        /** A Solana address on screen: one tap opens the wallet with it. */
        data class Pay(val address: String, val amount: String?) : Chip()
    }

    /** The small label on the chip's left, when there is one. */
    fun key(chip: Chip): String? = (chip as? Chip.Vault)?.field?.label

    /** What a tap does, on the chip's right edge; null for the model's own words. */
    fun verb(chip: Chip): String? = when (chip) {
        is Chip.Calc, is Chip.Vault -> "Insert"
        is Chip.Pay -> "Pay"
        is Chip.Action -> null
    }

    /** What the chip says. */
    fun display(chip: Chip): String = when (chip) {
        is Chip.Calc -> chip.result
        is Chip.Vault -> chip.field.value
        is Chip.Action -> chip.label
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
        is Chip.Action, is Chip.Pay -> ""
    }

    /** Vault fields out of the decrypted vault JSON. */
    fun fields(vault: org.json.JSONObject): List<Field> {
        val arr: JSONArray = vault.optJSONArray("fields") ?: return emptyList()
        return (0 until arr.length()).mapNotNull { i ->
            val f = arr.optJSONObject(i) ?: return@mapNotNull null
            Field(f.optString("kind"), f.optString("label"), f.optString("value"))
                .takeIf { it.value.isNotBlank() }
        }
    }

    /** One chip at most, in the website's order: a payment, a sum, a detail. */
    fun chip(text: String, fields: List<Field>, indianGrouping: Boolean = true): Chip? {
        payment(text)?.let { return Chip.Pay(it.first, it.second ?: amountAsked(text)) }
        calc(text, indianGrouping)?.let { return Chip.Calc(it.first, it.second) }
        vaultMatch(text, fields)?.let { return Chip.Vault(it) }
        return null
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
        Triple("""\b(address|deliver(?: it)? to|send (?:it |the \w+ )?to|ship (?:it )?to|come to|pick me up (?:from|at))\s*(?:is\s*)?:?\s*$""", listOf("address"), null),
        Triple("""\b(upi|gpay|google pay|phonepe|paytm)(?:\s*id)?\s*(?:is\s*)?:?\s*$""", listOf("upi"), null),
        Triple("""\bpay me (?:at|on)\s*$""", listOf("upi"), null),
        Triple("""\b(wallet|sol|solana|phantom|usdc|crypto)(?:\s*(?:address|addy|wallet))?\s*(?:is\s*)?:?\s*$""", listOf("wallet"), null),
        Triple("""\b(insta|instagram|ig)(?:\s*(?:handle|id))?\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "insta"),
        Triple("""\b(twitter|on x|x handle)\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "x"),
        Triple("""\blinkedin\s*(?:is\s*)?:?\s*$""", listOf("social", "handle"), "linkedin"),
        Triple("""\b(e-?mail|mail)(?:\s*id)?\s*(?:is\s*)?:?\s*$""", listOf("email"), null),
        Triple("""\b(number|phone|mobile|whatsapp|call me (?:at|on))\s*(?:is\s*)?:?\s*$""", listOf("phone"), null),
    ).map { (p, kinds, label) -> Triple(Regex(p, RegexOption.IGNORE_CASE), kinds, label) }

    fun vaultMatch(text: String, fields: List<Field>): Field? {
        if (text.isEmpty()) return null
        for ((re, kinds, label) in triggers) {
            if (!re.containsMatchIn(text)) continue
            val candidates = fields.filter { it.kind in kinds }
            if (label != null) {
                candidates.firstOrNull { it.label.lowercase().contains(label) }?.let { return it }
                continue
            }
            candidates.firstOrNull()?.let { return it }
        }
        return null
    }
}
