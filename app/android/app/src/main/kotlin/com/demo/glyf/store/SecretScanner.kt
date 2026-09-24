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
        if (looksLikeOTP(t)) return "One-time codes aren't worth saving"
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

    /** The key prefixes people most often have on their clipboard, kept in
     *  step with the iOS SecretScanner.keyPrefixes. */
    val keyPrefixes = listOf(
        "sk-", "sk_live_", "sk_test_", "rk_live_", "rk_test_", "whsec_", "xoxb-", "xoxp-",
        "xoxa-", "xoxr-", "xoxs-", "xapp-", "ghp_", "gho_", "ghu_", "ghs_", "ghr_",
        "github_pat_", "glpat-", "AKIA", "ASIA", "AIza", "ya29.", "npm_", "hf_", "shpat_",
        "shpss_", "SG.", "sq0atp-", "sq0csp-", "privy_app_secret_",
    )

    fun looksLikeKeyOrToken(text: String): Boolean {
        val t = text.trim()
        if (t.startsWith("-----BEGIN") || t.contains("PRIVATE KEY-----")) return true
        if (t.any { it.isWhitespace() }) return false
        if (keyPrefixes.any { t.startsWith(it) } && t.length >= 16) return true
        // A wallet ADDRESS is meant to be shared (Glyf's pay chip reads a
        // copied one): only its private key or seed is a secret.
        if (looksLikeWalletAddress(t)) return false
        if (Regex("^(0x)?[0-9a-fA-F]{64}$").matches(t)) return true
        // A JWT: three base64url parts, the first starting {" (eyJ).
        if (Regex("^eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}$").matches(t)) return true
        // A long unbroken run of key characters (a raw secret, base64).
        if (Regex("^[A-Za-z0-9+/=_-]{40,}$").matches(t)) return true
        // Random-looking: 32+ letters and digits in both cases, no words.
        if (t.length >= 32 && Regex("^[A-Za-z0-9_-]+$").matches(t) &&
            t.any { it.isUpperCase() } && t.any { it.isLowerCase() } && t.any { it.isDigit() }) return true
        return false
    }

    /** Public addresses: EVM (0x + 40 hex), Bitcoin bech32, base58 (Solana
     *  32–44, Bitcoin legacy 25–35). A Solana secret key (87–88) stays refused. */
    fun looksLikeWalletAddress(t: String): Boolean =
        Regex("^0x[0-9a-fA-F]{40}$").matches(t) ||
            Regex("^(bc1|tb1)[0-9a-z]{25,90}$").matches(t) ||
            Regex("^[1-9A-HJ-NP-Za-km-z]{25,44}$").matches(t)

    private fun looksLikeOTP(text: String): Boolean =
        Regex("^\\d{6}$").matches(text.trim()) || Regex("^\\d{3}[- ]\\d{3}$").matches(text.trim())
}
