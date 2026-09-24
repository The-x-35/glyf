import Foundation

/// §6.1 / §11.4: the clipboard manager must never persist passwords, card
/// numbers, or seed phrases. Pure logic — unit-tested in RunnerTests.
enum SecretScanner {

    enum Verdict: String {
        case clean
        case cardNumber
        case seedPhrase
        case privateKeyOrToken
        case otpCode
    }

    static func scan(_ text: String) -> Verdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .clean }
        if looksLikeCardNumber(trimmed) { return .cardNumber }
        if looksLikeSeedPhrase(trimmed) { return .seedPhrase }
        if looksLikeKeyOrToken(trimmed) { return .privateKeyOrToken }
        if looksLikeOTP(trimmed) { return .otpCode }
        return .clean
    }

    /// 13–19 digits (spaces/dashes allowed) passing Luhn.
    static func looksLikeCardNumber(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard text.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }),
              (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            var d = ch.wholeNumberValue ?? 0
            if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
            sum += d
        }
        return sum % 10 == 0
    }

    /// 12/15/18/21/24 lowercase dictionary-looking words → BIP-39 shape.
    static func looksLikeSeedPhrase(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard [12, 15, 18, 21, 24].contains(words.count) else { return false }
        return words.allSatisfy { w in
            w.count >= 3 && w.count <= 8 && w.allSatisfy { $0.isLetter && $0.isLowercase }
        }
    }

    /// The prefixes of the keys people most often have on their clipboard:
    /// AI and payment keys, webhook signing secrets, GitHub/GitLab/Slack/npm/
    /// Hugging Face/Shopify/SendGrid tokens, AWS and Google keys. Kept in step
    /// with the Android SecretScanner.
    static let keyPrefixes = [
        "sk-", "sk_live_", "sk_test_", "rk_live_", "rk_test_", "whsec_", "xoxb-", "xoxp-",
        "xoxa-", "xoxr-", "xoxs-", "xapp-", "ghp_", "gho_", "ghu_", "ghs_", "ghr_",
        "github_pat_", "glpat-", "AKIA", "ASIA", "AIza", "ya29.", "npm_", "hf_", "shpat_",
        "shpss_", "SG.", "sq0atp-", "sq0csp-", "privy_app_secret_",
    ]

    static func looksLikeKeyOrToken(_ text: String) -> Bool {
        if text.contains("PRIVATE KEY-----") { return true }
        guard !text.contains(where: \.isWhitespace) else { return false }
        if keyPrefixes.contains(where: { text.hasPrefix($0) }) && text.count >= 16 { return true }
        // A wallet ADDRESS is meant to be shared (Glyf's pay chip reads a
        // copied one): only its private key or seed is a secret.
        if looksLikeWalletAddress(text) { return false }
        // A JWT: three base64url parts, the first starting {" (eyJ).
        if text.range(of: #"^eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$"#,
                      options: .regularExpression) != nil { return true }
        // A long unbroken run of key characters (a raw secret, base64).
        if text.count >= 40,
           text.range(of: #"^[A-Za-z0-9+/=_-]+$"#, options: .regularExpression) != nil { return true }
        // Random-looking: 32+ letters and digits in both cases, no words.
        if text.count >= 32, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
           text.contains(where: \.isUppercase), text.contains(where: \.isLowercase),
           text.contains(where: \.isNumber) { return true }
        // 64-hex = raw private key material
        if text.count == 64, text.allSatisfy({ $0.isHexDigit }) { return true }
        // Solana-style base58 secret (87–88 chars) — refuse long unbroken base58
        if text.count >= 80, text.count <= 90,
           text.allSatisfy({ "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".contains($0) }) {
            return true
        }
        return false
    }

    /// Public addresses: EVM (0x + 40 hex), Bitcoin bech32, and base58
    /// (Solana 32–44, Bitcoin legacy 25–35). A Solana SECRET key is 87–88
    /// base58 characters and stays refused above.
    static func looksLikeWalletAddress(_ text: String) -> Bool {
        let patterns = [#"^0x[0-9a-fA-F]{40}$"#, #"^(bc1|tb1)[0-9a-z]{25,90}$"#,
                        #"^[1-9A-HJ-NP-Za-km-z]{25,44}$"#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Bare 6-digit codes are almost always OTPs — not worth persisting.
    static func looksLikeOTP(_ text: String) -> Bool {
        text.count == 6 && text.allSatisfy(\.isNumber)
    }
}
