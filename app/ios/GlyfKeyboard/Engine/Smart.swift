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
        /// The model read what is being typed and named what Glyf could do
        /// about it — the website's coach, in the strip.
        case action(label: String, query: String, intent: String)
        /// A Solana address is on screen or freshly copied: one tap opens the
        /// wallet with it filled in. The keyboard never holds a key — the app
        /// signs (website 6.10, "Private sends by MagicBlock").
        case pay(address: String, amount: String?)

        var key: String {
            switch self {
            case .calc: return "="
            case .vault(let f): return f.label
            case .paste: return "Paste"
            case .pay: return "Pay"
            case .action: return "Glyf"
            }
        }
        /// The verb on the chip's right edge: what a tap does. Nil for the
        /// model's suggestions, whose text is already the action.
        var verb: String? {
            switch self {
            case .calc, .vault: return "Insert"
            case .paste: return "Paste"
            case .pay: return "Pay"
            case .action: return nil
            }
        }
        var value: String {
            switch self {
            case .calc(let v, _): return v
            case .vault(let f): return f.value
            case .paste(let t): return t.replacingOccurrences(of: "\n", with: " ")
            case .action(let label, _, _): return label
            case .pay(let address, let amount):
                let short = address.count > 12
                    ? "\(address.prefix(4))…\(address.suffix(4))" : address
                return amount.map { "\($0) USDC to \(short)" } ?? "privately to \(short)"
            }
        }
        /// What tapping the chip puts in the field.
        var insert: String {
            switch self {
            case .calc(let v, let hasEquals): return hasEquals ? " \(v)" : " = \(v)"
            case .vault(let f): return f.value
            case .paste(let t): return t
            case .pay: return ""       // handled by the app, never typed
            case .action: return ""    // runs a glyf instead of typing
            }
        }
    }

    /// What the field itself says it wants, as far as a keyboard can tell.
    /// iOS gives a keyboard extension no label, so this is assembled from the
    /// keyboard type and the field's capitalisation/return key; Android adds
    /// the real hint and autofill hints, which are stronger.
    struct FieldHint: Equatable {
        /// A vault kind ("email", "phone", "address", "name", "upi", "link"),
        /// or nil when the field gives nothing away.
        var kind: String?
        /// The field is empty, so filling it is the only thing to do here.
        var empty: Bool = true

        static let none = FieldHint(kind: nil)

        /// Android hints and iOS placeholders, matched by wording. Kept here
        /// so both platforms agree on what a field is asking for.
        static func kind(fromHint hint: String) -> String? {
            let h = hint.lowercased()
            func has(_ words: [String]) -> Bool { words.contains { h.contains($0) } }
            if has(["e-mail", "email", "mail id"]) { return "email" }
            if has(["phone", "mobile", "contact number", "whatsapp"]) { return "phone" }
            if has(["address", "street", "flat", "house", "city", "pincode",
                    "postal", "zip", "delivery"]) { return "address" }
            if has(["full name", "your name", "first name", "last name",
                    "name"]) { return "name" }
            if has(["upi", "vpa", "gpay", "phonepe", "paytm"]) { return "upi" }
            if has(["website", "url", "link", "portfolio"]) { return "link" }
            if has(["company", "organisation", "organization", "employer"]) { return "company" }
            if has(["instagram", "twitter", "linkedin", "handle", "social"]) { return "social" }
            return nil
        }
    }

    /// One chip at most, in the website's order: a payment someone just asked
    /// for, a sum you typed, a saved detail the sentence (or the field) asks
    /// for, then something freshly copied.
    static func chip(for text: String, fields: [VaultField], paste: String? = nil,
                     field: FieldHint = .none) -> Chip? {
        if let p = payment(in: text) ?? paste.flatMap({ payment(in: $0) }) {
            return .pay(address: p.address, amount: p.amount ?? amountAsked(in: text))
        }
        if let c = calc(text) { return .calc(value: c.value, hasEquals: c.hasEquals) }
        if let f = vaultMatch(text, fields: fields) { return .vault(field: f) }
        // A form asking for something we already know: one tap fills it.
        if text.isEmpty, field.empty, let kind = field.kind,
           let f = fields.first(where: { $0.kind == kind }) {
            return .vault(field: f)
        }
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

    // MARK: Payments

    /// A Solana address sitting in the text (or on the clipboard), which in a
    /// chat means someone is asking to be paid.
    private static let addressPattern = try? NSRegularExpression(
        pattern: #"(?<![A-HJ-NP-Za-km-z1-9])([1-9A-HJ-NP-Za-km-z]{32,44})(?![A-HJ-NP-Za-km-z1-9])"#)

    static func payment(in text: String) -> (address: String, amount: String?)? {
        guard let re = addressPattern, !text.isEmpty else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        let address = ns.substring(with: m.range(at: 1))
        // Base58 has no 0, O, I or l; a run of hex or a sentence is not an
        // address. Require the mix of cases a real key has.
        let hasUpper = address.contains { $0.isUppercase }
        let hasLower = address.contains { $0.isLowercase }
        let hasDigit = address.contains { $0.isNumber }
        guard hasUpper, hasLower, hasDigit else { return nil }
        return (address, amountAsked(in: text))
    }

    /// "send $200" / "200 usdc" → "200".
    static func amountAsked(in text: String) -> String? {
        let patterns = [#"[$₹]\s*([\d,]+(?:\.\d{1,6})?)"#,
                        #"([\d,]+(?:\.\d{1,6})?)\s*(?:usdc|usdt|dollars?)"#]
        for p in patterns {
            if let r = text.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                let digits = text[r].filter { $0.isNumber || $0 == "." }
                if !digits.isEmpty { return String(digits) }
            }
        }
        return nil
    }

    // MARK: Contextual vault

    /// Sentence endings that mean "the next thing I type is X".
    /// Each pattern maps to a vault field kind, and for socials to a label.
    private static let triggers: [(pattern: String, kind: String, label: String?)] = [
        (#"\b(my name is|name:|this is)\s*$"#, "name", nil),
        // Before address: "my wallet address" asks for the wallet.
        (#"\b(wallet|sol|solana|phantom|usdc|crypto)(?:\s*(?:address|addy|wallet))?\s*(?:is\s*)?:?\s*$"#, "wallet", nil),
        (#"\b(address|deliver(?: it)? to|send (?:it |the \w+ )?to|ship (?:it )?to|come to|pick me up (?:from|at))\s*(?:is\s*)?:?\s*$"#, "address", nil),
        (#"\b(upi|gpay|google pay|phonepe|paytm)(?:\s*id)?\s*(?:is\s*)?:?\s*$"#, "upi", nil),
        (#"\bpay me (?:at|on)\s*$"#, "upi", nil),
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
        guard !text.isEmpty, !asksSomeoneElse(text) else { return nil }
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
            // The sentence named the kind; with none saved there is nothing to offer.
            return candidates.first
        }
        return firstPersonMatch(text, fields: fields)
    }

    /// Words that lead into one of your own details near the end of the
    /// sentence ("here's my number", "gpay me on"): the same list the server's
    /// suggestions use (server/src/lib/details.ts).
    private static let firstPerson: [(pattern: String, kind: String)] = [
        (#"\b(my|our)\s+(home\s+|delivery\s+|shipping\s+|office\s+|current\s+)?(address|addy|location)\b"#, "address"),
        (#"\b(ship|deliver|send|courier|post)\s+(it|them|the\s+\w+|this)?\s*(to|at)\s*:?\s*$"#, "address"),
        (#"\b(i\s+(live|stay)\s+(at|in)|come\s+(over\s+)?to|pick\s+me\s+up\s+(from|at))\s*:?\s*$"#, "address"),
        (#"\b(my|our)\s+(phone|mobile|cell|contact|whatsapp)?\s*(number|no\.?|num)\b"#, "phone"),
        (#"\b(call|text|whatsapp|ping|reach)\s+me\s+(on|at)\s*:?\s*$"#, "phone"),
        (#"\b(my|our)\s+(e-?mail|mail\s*id|gmail)\b"#, "email"),
        (#"\b(e-?mail|mail)\s+me\s+(on|at)\s*:?\s*$"#, "email"),
        (#"\b(my|our)\s+(upi|vpa|gpay|google\s+pay|phonepe|paytm)(\s+(id|number|handle))?\b"#, "upi"),
        (#"\b(gpay|google\s+pay|phonepe|paytm|upi|pay|transfer|send\s+(the\s+)?(money|amount|it))\s+(me\s+)?(on|at|to)\s*:?\s*$"#, "upi"),
        (#"\b(my|our)\s+(sol(ana)?|crypto|usdc|phantom)?\s*wallet(\s+address)?\b"#, "wallet"),
        (#"\b(my|our)\s+(website|portfolio|site|link|calendly)\b"#, "link"),
        (#"\b(my|our)\s+(insta(gram)?|ig|twitter|x\s+handle|linkedin|handle)\b"#, "social"),
        (#"\b(my|our)\s+gst(in)?(\s+(number|no\.?))?\b"#, "gst"),
    ]

    private static func lastClause(_ text: String) -> String {
        let parts = text.lowercased().components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        return (parts.last ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// "send me ur upi", "what's your address": a question for someone else.
    private static func asksSomeoneElse(_ text: String) -> Bool {
        let tail = lastClause(text).split(separator: " ").suffix(6).joined(separator: " ")
        return tail.range(of: #"\b(your|ur|yours|his|her|their)\b"#, options: .regularExpression) != nil
    }

    /// First-person asks only, and only before the detail has been typed.
    static func firstPersonMatch(_ text: String, fields: [VaultField]) -> VaultField? {
        let clause = lastClause(text)
        guard !clause.isEmpty, !asksSomeoneElse(text) else { return nil }
        for (pattern, kind) in firstPerson {
            guard let r = clause.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                  let field = fields.first(where: { $0.kind == kind || (kind == "social" && $0.kind == "handle") })
            else { continue }
            let after = String(clause[r.upperBound...])
                .replacingOccurrences(of: #"^[\s:,-]*(is|are|=)?[\s:,-]*"#, with: "", options: .regularExpression)
            if after.count <= 3 { return field }
        }
        return nil
    }
}
