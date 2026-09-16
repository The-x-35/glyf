import Foundation

/// The website's smart strip, on the phone: while you type, the keyboard
/// notices either an arithmetic expression or a sentence that is about to
/// need a detail you already saved, and offers exactly one chip for it.
/// Pure logic so it can be unit tested; no evaluation of user text as code.
enum Smart {

    enum Chip: Equatable {
        /// "3480/4" -> " = 870". `hasEquals` is true when the person already
        /// typed the "=" themselves, so the insert does not repeat it.
        case calc(value: String, hasEquals: Bool)
        /// "my upi id is " -> the saved UPI.
        case vault(field: VaultField)
        /// Something was just copied: one tap pastes it.
        case paste(text: String)

        var key: String {
            switch self {
            case .calc: return "="
            case .vault(let f): return f.label
            case .paste: return "Paste"
            }
        }
        var value: String {
            switch self {
            case .calc(let v, _): return v
            case .vault(let f): return f.value
            case .paste(let t): return t.replacingOccurrences(of: "\n", with: " ")
            }
        }
        /// What tapping the chip puts in the field.
        var insert: String {
            switch self {
            case .calc(let v, let hasEquals): return hasEquals ? " \(v)" : " = \(v)"
            case .vault(let f): return f.value
            case .paste(let t): return t
            }
        }
    }

    /// One chip at most, in the website's order: a sum you just typed, then a
    /// saved detail the sentence asks for, then something freshly copied.
    static func chip(for text: String, fields: [VaultField], paste: String? = nil) -> Chip? {
        if let c = calc(text) { return .calc(value: c.value, hasEquals: c.hasEquals) }
        if let f = vaultMatch(text, fields: fields) { return .vault(field: f) }
        if let paste, !paste.isEmpty, text.isEmpty { return .paste(text: paste) }
        return nil
    }

    // MARK: Calculator

    private static let calcPattern: NSRegularExpression? = {
        let num = #"(?:[₹$€£]\s*)?\d[\d,]*(?:\.\d+)?%?"#
        let op = #"(?:[-+*/×÷^]|\bx\b|\bof\b)"#
        return try? NSRegularExpression(
            pattern: #"(\(?\s*\#(num)\s*\)?(?:\s*\#(op)\s*\(?\s*\#(num)\s*\)?)+)(\s*=)?\s*$"#,
            options: [.caseInsensitive])
    }()

    static func calc(_ text: String) -> (value: String, hasEquals: Bool)? {
        guard let re = calcPattern, !text.isEmpty else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.range(at: 1).location != NSNotFound else { return nil }
        let expr = ns.substring(with: m.range(at: 1))
        let hasEquals = m.range(at: 2).location != NSNotFound
        // A bare number is not a sum; only offer when an operator is present.
        if !hasEquals,
           expr.range(of: #"[+*/×÷^%]|\bx\b|\bof\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            return nil
        }
        guard let v = evaluate(expr) else { return nil }
        let currency = expr.first(where: { "₹$€£".contains($0) }).map(String.init) ?? ""
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 2
        guard let text = f.string(from: NSNumber(value: v)) else { return nil }
        return (currency + text, hasEquals)
    }

    /// Recursive descent over a token list. Returns nil on anything it does
    /// not fully understand, so junk never turns into a wrong answer.
    static func evaluate(_ expression: String) -> Double? {
        var src = expression.lowercased()
        for (from, to) in [("of", "*"), ("x", "*")] {
            src = src.replacingOccurrences(of: #"\b\#(from)\b"#, with: to,
                                           options: .regularExpression)
        }
        src = src.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
        src = src.filter { !"₹$€£, \t".contains($0) }
        guard !src.isEmpty else { return nil }

        var tokens: [String] = []
        var number = ""
        for ch in src {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else if "+-*/^()%".contains(ch) {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(ch))
            } else {
                return nil        // an unknown character: not a sum
            }
        }
        if !number.isEmpty { tokens.append(number) }

        var i = 0
        func peek() -> String? { i < tokens.count ? tokens[i] : nil }

        func unary() -> Double? {
            if peek() == "-" { i += 1; return unary().map { -$0 } }
            if peek() == "(" {
                i += 1
                guard let v = sum(), peek() == ")" else { return nil }
                i += 1
                return percentSuffix(v)
            }
            guard let t = peek(), let v = Double(t) else { return nil }
            i += 1
            return percentSuffix(v)
        }
        func percentSuffix(_ v: Double) -> Double {
            if peek() == "%" { i += 1; return v / 100 }
            return v
        }
        func power() -> Double? {
            guard let base = unary() else { return nil }
            if peek() == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(base, e)
            }
            return base
        }
        func product() -> Double? {
            guard var v = power() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                i += 1
                guard let rhs = power() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    v /= rhs
                } else {
                    v *= rhs
                }
            }
            return v
        }
        func sum() -> Double? {
            guard var v = product() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                i += 1
                guard let rhs = product() else { return nil }
                v = op == "+" ? v + rhs : v - rhs
            }
            return v
        }
        guard let v = sum(), i == tokens.count, v.isFinite else { return nil }
        return v
    }

    // MARK: Contextual vault

    /// Sentence endings that mean "the next thing I type is X".
    /// Each pattern maps to a vault field kind, and for socials to a label.
    private static let triggers: [(pattern: String, kind: String, label: String?)] = [
        (#"\b(my name is|name:|this is)\s*$"#, "name", nil),
        (#"\b(address|deliver(?: it)? to|send (?:it |the \w+ )?to|ship (?:it )?to|come to|pick me up (?:from|at))\s*(?:is\s*)?:?\s*$"#, "address", nil),
        (#"\b(upi|gpay|google pay|phonepe|paytm)(?:\s*id)?\s*(?:is\s*)?:?\s*$"#, "upi", nil),
        (#"\bpay me (?:at|on)\s*$"#, "upi", nil),
        (#"\b(wallet|sol|solana|phantom|usdc|crypto)(?:\s*(?:address|addy|wallet))?\s*(?:is\s*)?:?\s*$"#, "wallet", nil),
        (#"\b(insta|instagram|ig)(?:\s*(?:handle|id))?\s*(?:is\s*)?:?\s*$"#, "social", "insta"),
        (#"\b(twitter|on x|x handle)\s*(?:is\s*)?:?\s*$"#, "social", "x"),
        (#"\blinkedin\s*(?:is\s*)?:?\s*$"#, "social", "linkedin"),
        (#"\b(e-?mail|mail)(?:\s*id)?\s*(?:is\s*)?:?\s*$"#, "email", nil),
        (#"\b(number|phone|mobile|whatsapp|call me (?:at|on))\s*(?:is\s*)?:?\s*$"#, "phone", nil),
    ]

    static func vaultMatch(_ text: String, fields: [VaultField]) -> VaultField? {
        // Each pattern ends at the end of the text, so the chip appears as
        // soon as the sentence asks for the detail. (The field's reported
        // context can lag a keystroke, so requiring a trailing space here
        // would make the chip miss the moment it is needed.)
        guard !text.isEmpty else { return nil }
        for (pattern, kind, label) in triggers {
            guard text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            else { continue }
            let candidates = fields.filter { $0.kind == kind }
            if let label {
                if let hit = candidates.first(where: { $0.label.lowercased().contains(label) }) {
                    return hit
                }
                continue
            }
            if let hit = candidates.first { return hit }
        }
        return nil
    }
}
