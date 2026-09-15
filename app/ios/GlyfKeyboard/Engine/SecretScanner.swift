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

    static func looksLikeKeyOrToken(_ text: String) -> Bool {
        if text.contains("PRIVATE KEY-----") { return true }
        let prefixes = ["sk-", "sk_live_", "xoxb-", "xoxp-", "ghp_", "AKIA", "privy_app_secret_"]
        if prefixes.contains(where: { text.hasPrefix($0) }) && text.count > 12 { return true }
        // 64-hex = raw private key material
        if text.count == 64, text.allSatisfy({ $0.isHexDigit }) { return true }
        // Solana-style base58 secret (87–88 chars) — refuse long unbroken base58
        if text.count >= 80, text.count <= 90,
           text.allSatisfy({ "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".contains($0) }) {
            return true
        }
        return false
    }

    /// Bare 6-digit codes are almost always OTPs — not worth persisting.
    static func looksLikeOTP(_ text: String) -> Bool {
        text.count == 6 && text.allSatisfy(\.isNumber)
    }
}
