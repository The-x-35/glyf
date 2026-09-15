package com.demo.glyf.ime.typing

import java.text.Normalizer
import kotlin.math.min

/** Text rules shared by the dictionary, the decoder and learning — the
 *  Kotlin half of shared/typing/FORMAT.md (Swift: Engine/Typing/TypingText.swift). */
object TypingText {

    /** Lookup key: NFC, lowercase, apostrophes and hyphens dropped. */
    fun key(word: String): String {
        val nfc = Normalizer.normalize(word, Normalizer.Form.NFC).lowercase()
        val out = StringBuilder(nfc.length)
        var i = 0
        while (i < nfc.length) {
            val cp = nfc.codePointAt(i)
            if (cp != '\''.code && cp != 0x2019 && cp != '-'.code) out.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
        return out.toString()
    }

    fun scalars(s: String): IntArray = s.codePoints().toArray()

    private val foldTable = IntArray(0x250) { v ->
        val decomposed = Normalizer.normalize(String(Character.toChars(v)), Normalizer.Form.NFD)
        val stripped = decomposed.filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }.lowercase()
        if (stripped.codePointCount(0, stripped.length) == 1) stripped.codePointAt(0) else Character.toLowerCase(v)
    }

    /** Lowercase base letter used for key matching: "É" → "e". */
    fun base(cp: Int): Int = if (cp in foldTable.indices) foldTable[cp] else Character.toLowerCase(cp)

    /** Optimal-string-alignment Damerau-Levenshtein. */
    fun editDistance(a: IntArray, b: IntArray): Int {
        if (a.isEmpty()) return b.size
        if (b.isEmpty()) return a.size
        val w = b.size + 1
        val d = IntArray((a.size + 1) * w)
        for (i in 0..a.size) d[i * w] = i
        for (j in 0..b.size) d[j] = j
        for (i in 1..a.size) {
            for (j in 1..b.size) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                var v = min(min(d[(i - 1) * w + j] + 1, d[i * w + j - 1] + 1), d[(i - 1) * w + j - 1] + cost)
                if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
                    v = min(v, d[(i - 2) * w + j - 2] + 1)
                }
                d[i * w + j] = v
            }
        }
        return d[a.size * w + b.size]
    }

    fun capitalCount(s: String): Int = s.codePoints().filter { Character.isUpperCase(it) }.count().toInt()

    fun hasDigit(s: String): Boolean = s.codePoints().anyMatch {
        when (Character.getType(it)) {
            Character.DECIMAL_DIGIT_NUMBER.toInt(), Character.LETTER_NUMBER.toInt(),
            Character.OTHER_NUMBER.toInt() -> true
            else -> false
        }
    }

    /** Tokens that are addresses, handles or codes rather than words. */
    fun isWebish(s: String): Boolean = s.any { it in "@#./:_" }

    fun isCapitalized(s: String): Boolean = s.isNotEmpty() && Character.isUpperCase(s.codePointAt(0))

    fun hasUppercase(s: String): Boolean = capitalCount(s) > 0

    /** "Delhi", not "HSA" or "iPhone": one capital, and it's the first letter. */
    fun isTitleCase(s: String): Boolean = isCapitalized(s) && capitalCount(s) == 1

    fun capitalizeFirst(s: String): String {
        if (s.isEmpty()) return s
        val n = Character.charCount(s.codePointAt(0))
        return s.substring(0, n).uppercase() + s.substring(n)
    }

    fun lowercaseFirst(s: String): String {
        if (s.isEmpty()) return s
        val n = Character.charCount(s.codePointAt(0))
        return s.substring(0, n).lowercase() + s.substring(n)
    }

    /** "Teh" + "the" → "The"; forms with capitals of their own stay as spelled. */
    fun matchCase(typed: String, form: String): String {
        if (hasUppercase(form)) return form
        return if (isCapitalized(typed)) capitalizeFirst(form) else form
    }

    /** Exactly this form, or a lowercase word with its first letter capitalized. */
    fun sameWord(typed: String, form: String): Boolean =
        typed == form || (!hasUppercase(form) && typed == capitalizeFirst(form))

    fun isAlphabetic(s: String): Boolean = s.codePoints().anyMatch { Character.isAlphabetic(it) }

    /** Days since 1970 — the clock learning decays by. */
    fun day(millis: Long = System.currentTimeMillis()): Int = (millis / 86_400_000L).toInt()
}
