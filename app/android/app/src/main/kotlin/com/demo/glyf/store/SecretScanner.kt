package com.demo.glyf.store

/** Port of iOS SecretScanner (§11.9): card numbers, seed phrases, keys,
 *  OTPs are refused at input everywhere secrets could stick. Returns a
 *  user-facing refusal, or null when clean. */
object SecretScanner {

    fun scan(text: String): String? {
        val t = text.trim()
        if (t.isEmpty()) return null
        if (looksLikeCardNumber(t)) return "Card numbers can't be saved"
        if (looksLikeSeedPhrase(t)) return "Seed phrases can't be saved anywhere in Glyf"
        if (looksLikeKeyOrToken(t)) return "Keys and tokens can't be saved"
        if (looksLikeOTP(t)) return "One-time codes expire — not worth saving"
        return null
    }

    private fun looksLikeCardNumber(text: String): Boolean {
        if (!text.all { it.isDigit() || it == ' ' || it == '-' }) return false
        val digits = text.filter { it.isDigit() }
        if (digits.length !in 13..19) return false
        var sum = 0
        digits.reversed().forEachIndexed { i, ch ->
            var d = ch.digitToInt()
            if (i % 2 == 1) { d *= 2; if (d > 9) d -= 9 }
            sum += d
        }
        return sum % 10 == 0
    }

    private fun looksLikeSeedPhrase(text: String): Boolean {
        val words = text.lowercase().split(Regex("\\s+"))
        if (words.size !in setOf(12, 15, 18, 21, 24)) return false
        return words.all { it.length in 3..8 && it.all { c -> c.isLetter() } }
    }

    private fun looksLikeKeyOrToken(text: String): Boolean {
        val t = text.trim()
        if (Regex("^(sk|pk|rk|ghp|gho|xox[bap])[-_][A-Za-z0-9_-]{16,}").containsMatchIn(t)) return true
        if (Regex("^0x[0-9a-fA-F]{64}$").matches(t)) return true
        if (Regex("^[A-Za-z0-9+/=_-]{40,}$").matches(t) && t.none { it.isWhitespace() }) return true
        if (t.startsWith("-----BEGIN")) return true
        return false
    }

    private fun looksLikeOTP(text: String): Boolean =
        Regex("^\\d{6}$").matches(text.trim()) || Regex("^\\d{3}[- ]\\d{3}$").matches(text.trim())
}
