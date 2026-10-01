import Foundation

/// The website's smart strip, on the phone: while you type, the keyboard
/// notices either an arithmetic expression or a sentence that is about to
/// need a detail you already saved, and offers exactly one chip for it.
/// Pure logic so it can be unit tested; no evaluation of user text as code.
enum Smart {

    enum Chip: Equatable {
        /// "3480/4" -> " = 870". `hasEquals` is true when the person already
        /// typed the "=" themselves, so the insert does not repeat it.
        /// The sum as typed rides along, so the strip reads "2+5 = 7".
        case calc(value: String, hasEquals: Bool, expression: String = "")
        /// "my upi id is " -> the saved UPI.
        case vault(field: VaultField)
        /// Something was just copied: one tap pastes it.
        case paste(text: String)
        /// The model read what is being typed and named what Glyf could do
        /// about it — the website's coach, in the strip.
        case action(label: String, query: String, intent: String)
        /// Someone's Solana wallet, on screen or freshly copied: Send opens in
        /// the app with it filled in (and the amount, when the message asks
        /// for one). The keyboard never holds a key: Phantom signs. `copied`
        /// is the whole copy when it came from one: the chip is then the
        /// paste, with Send beside it.
        case pay(address: String, amount: String? = nil, token: String? = nil, copied: String? = nil)
        /// A token's address (a contract address someone shared), on screen
        /// or freshly copied: Buy opens for it in the app. `copied` as above.
        case buy(mint: String, symbol: String, price: String?, copied: String? = nil)
        /// "$13" → "$13 = ₹1,246" where the phone is; "$sol" → "1 SOL = $112".
        /// `shown` is the whole line, `insert` what a tap adds after the
        /// amount. Never shown without a live rate. `buy` is the token's
        /// address when a cashtag can be bought: Buy then sits beside Insert.
        case money(shown: String, insert: String, buy: String? = nil)
        /// A plan in the message ("dinner friday 8pm"): one tap opens New
        /// Event with it filled in, nothing typed.
        case event(plan: EventParse.Plan)
        /// Someone's Cal.com or Calendly page, in the message or just copied:
        /// one tap shows its open times to book, with the person's own details.
        case booking(link: String)
        /// A mail that landed at the temp address while it was watched: its
        /// code, which a tap types, or, with none, the mail, which a tap opens
        /// (TempMailWatcher).
        case tempMail(id: String, from: String, code: String?)
        /// An email field with nothing typed in it: the temp address still
        /// live, typed again (its inbox is the one being watched), or, with
        /// none, a new one made, typed and watched, in one tap.
        case tempAddress(live: String?)
        /// More than one saved detail of the kind the sentence asks for (two
        /// emails, a home and a work address), or an email with a temp
        /// address beside it: one part of the chip for each, and a tap on a
        /// part types it (Arpit, 2026-10-01: "if i added 2 mail ids i should
        /// see both, and i should also see a temp mail option").
        case details(fields: [VaultField], temp: Bool)

        var key: String {
            switch self {
            case .event, .booking: return "Calendar"
            case .calc, .money: return "="
            case .vault(let f): return f.title
            case .paste: return "Paste"
            case .pay: return "Send"
            case .buy: return "Buy"
            case .action: return "Glyf"
            case .tempMail: return "Mail"
            case .tempAddress(let live): return live == nil ? "Email" : "Temp email"
            case .details(let fields, _): return fields.first?.title ?? "Email"
            }
        }
        /// The verb on the chip's right edge: what a tap does. Nil for the
        /// model's suggestions, whose text is already the action.
        var verb: String? {
            switch self {
            case .calc, .vault, .money: return "Insert"
            case .event: return "Add"
            case .booking: return "Book"
            case .paste: return "Paste"
            case .pay(_, _, _, let copied): return copied == nil ? "Send" : "Paste"
            case .buy(_, _, _, let copied): return copied == nil ? "Buy" : "Paste"
            case .action: return nil
            case .tempMail(_, _, let code): return code == nil ? "Open" : "Insert"
            case .tempAddress(let live): return live == nil ? "Create" : "Insert"
            case .details: return nil    // each part is its own action
            }
        }
        /// A second action, as a button beside the first: Buy on a token's
        /// price, Send or Buy on a copied address (whose own tap pastes it).
        var extra: String? {
            switch self {
            case .money(_, _, let mint): return mint == nil ? nil : "Buy"
            case .pay(_, _, _, let copied): return copied == nil ? nil : "Send"
            case .buy(_, _, _, let copied): return copied == nil ? nil : "Buy"
            default: return nil
            }
        }
        /// What was copied, for a chip that pastes it.
        var copiedText: String? {
            switch self {
            case .paste(let t): return t
            case .pay(_, _, _, let copied), .buy(_, _, _, let copied): return copied
            default: return nil
            }
        }
        /// A quieter word before the value, saying what it is ("Home" before
        /// an address, "Wallet" before someone's wallet).
        var label: String? {
            switch self {
            case .vault(let f): return f.title
            case .pay: return "Wallet"
            case .buy(_, let symbol, _, _): return symbol
            default: return nil
            }
        }
        var value: String {
            switch self {
            // The whole sum where it fits: "2+5 = 7" reads as an answer, "7" alone
            // was easy to miss (user, 2026-09-29: "show result in recommendation strip").
            case .calc(let v, _, let expression):
                return expression.isEmpty || expression.count > 22 ? "= \(v)" : "\(expression) = \(v)"
            case .vault(let f): return f.value
            case .paste(let t): return t.replacingOccurrences(of: "\n", with: " ")
            case .action(let label, _, _): return label
            case .money(let shown, _, _): return shown
            case .event(let plan): return EventParse.summary(plan)
            case .booking(let link): return "A time on \(Smart.shortLink(link))"
            case .pay(let address, let amount, let token, _):
                let short = Smart.shortAddress(address)
                return amount.map { "\($0) \(token ?? "USDC") to \(short)" } ?? short
            case .buy(let mint, _, let price, _):
                return price ?? Smart.shortAddress(mint)
            case .tempMail(_, let from, let code):
                return code.map { "\($0) · \(from)" } ?? "Mail from \(from)"
            case .tempAddress(let live): return live ?? "Temp email"
            case .details(let fields, let temp):
                return (fields.map(\.value) + (temp ? ["Temp mail"] : [])).joined(separator: " · ")
            }
        }
        /// What tapping the chip puts in the field.
        var insert: String {
            switch self {
            case .calc(let v, let hasEquals, _): return hasEquals ? " \(v)" : " = \(v)"
            case .vault(let f): return f.value
            case .paste(let t): return t
            case .money(_, let insert, _): return insert
            case .pay(_, _, _, let copied), .buy(_, _, _, let copied):
                return copied ?? ""    // a copy pastes; the rest happens in the app
            case .event: return ""     // opens New Event instead of typing
            case .booking: return ""   // opens Book a time instead of typing
            case .action: return ""    // runs a glyf instead of typing
            case .tempMail(_, _, let code): return code ?? ""   // no code: opens the mail
            case .tempAddress(let live): return live ?? ""   // none live: made first, then typed
            case .details: return ""   // a part's own tap types it
            }
        }
    }

    /// A Cal.com or Calendly booking page in the text ("cal.com/sam/30min",
    /// "https://calendly.com/sam"), unless it is the person's own.
    static func bookingLink(in text: String, own: String? = SettingsStore.current.bookingLink) -> String? {
        let pattern = #"(?:https?://)?(?:[a-z0-9-]+\.)?(?:cal\.com|calendly\.com)/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)?"#
        guard let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let link = String(text[r])
        let bare = { (s: String) in s.lowercased().replacingOccurrences(of: #"^https?://(www\.)?"#, with: "",
                                                                        options: .regularExpression) }
        if let own, !own.isEmpty, bare(own).hasPrefix(bare(link)) || bare(link).hasPrefix(bare(own)) { return nil }
        return link
    }

    /// "cal.com/sam/30min" without the scheme.
    static func shortLink(_ link: String) -> String {
        link.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// The rates the keyboard has at hand (from the server, via RatesStore).
    /// `fiat` is per dollar (INR: 95.88), `crypto` is dollars per token
    /// (SOL: 111.77), `local` the currency where the phone is ("INR").
    struct RatesSnapshot: Equatable {
        var fiat: [String: Double] = [:]
        var crypto: [String: Double] = [:]
        var local: String = "USD"
        /// A cashtag's token address, when it can be bought ("SOL": "So1…").
        var mints: [String: String] = [:]
        /// What an address on screen turned out to be, once asked.
        var addresses: [String: AddressKind] = [:]
        /// The market's ticker for what was typed ("APPLE", "APPL": "AAPL").
        var tickers: [String: String] = [:]

        static let empty = RatesSnapshot()
    }

    /// A Solana address is someone's wallet or a token's; only a lookup can
    /// tell (both are base58 of the same length).
    enum AddressKind: Equatable {
        case wallet
        case token(symbol: String, usd: Double?)
    }

    /// "7dHb…7ARj".
    static func shortAddress(_ address: String) -> String {
        address.count > 12 ? "\(address.prefix(4))…\(address.suffix(4))" : address
    }

    /// The address a chip is waiting on: on screen or copied, not yours,
    /// and not yet known to be a wallet or a token.
    static func addressToCheck(in text: String, paste: String?, rates: RatesSnapshot,
                               ownWallet: String? = nil) -> String? {
        let copy = text.isEmpty ? paste : nil
        guard let p = payment(in: text) ?? copy.flatMap({ payment(in: $0) }),
              p.address != ownWallet, rates.addresses[p.address] == nil else { return nil }
        return p.address
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
                     field: FieldHint = .none, rates: RatesSnapshot = .empty,
                     ownWallet: String? = nil, indianGrouping: Bool = true) -> Chip? {
        // An address: Send to a wallet, Buy a token. Your own wallet is one
        // you are sharing, not paying. Until the lookup says which, nothing
        // (the keyboard asks, and the strip is arranged again).
        let typed = payment(in: text)
        let copy = typed == nil && text.isEmpty ? paste : nil
        if let p = typed ?? copy.flatMap({ payment(in: $0) }), p.address != ownWallet {
            switch rates.addresses[p.address] {
            case .token(let symbol, let usd)?:
                return .buy(mint: p.address, symbol: symbol, price: usd.map(price), copied: copy)
            case .wallet?:
                let asked = p.amount ?? amountAsked(in: text)
                return .pay(address: p.address, amount: asked?.value, token: asked?.token, copied: copy)
            case nil:
                return nil
            }
        }
        if let c = calc(text, indianGrouping: indianGrouping) {
            return .calc(value: c.value, hasEquals: c.hasEquals, expression: c.expression)
        }
        if let m = money(in: text, rates: rates) { return m }
        // A cashtag waits for its price: "$sol" is SOL's price, never your
        // Solana wallet, even before the price has come.
        if cashtag(in: text) != nil { return nil }
        let matches = vaultMatches(text, fields: fields)
        if matches.count > 1 { return .details(fields: Array(matches.prefix(3)), temp: false) }
        if let f = matches.first { return .vault(field: f) }
        if let plan = EventParse.looksLikePlan(text, dayFirst: EventParse.regionDayFirst) {
            return .event(plan: plan)
        }
        if let link = bookingLink(in: text) ?? paste.flatMap({ bookingLink(in: $0) }) {
            return .booking(link: link)
        }
        // A form asking for something we already know: one tap fills it.
        if text.isEmpty, field.empty, let kind = field.kind {
            let held = fields.filter { $0.kind == kind }
            if held.count > 1 { return .details(fields: Array(held.prefix(3)), temp: false) }
            if let f = held.first { return .vault(field: f) }
        }
        if let paste, !paste.isEmpty, text.isEmpty { return .paste(text: paste) }
        return nil
    }

    // MARK: Calculator

    /// A number as typed: a currency sign, square roots, digits or π, and a
    /// percentage. Every operator people type between numbers (Arpit,
    /// 2026-09-29: "work for all maths symbols"): + - − * ** × x / ÷ ^ mod,
    /// the comparisons, and "of" after a percentage (Smart.kt twin).
    private static let calcPattern: NSRegularExpression? = {
        let num = #"(?:[₹$€£]\s*)?(?:√\s*)*(?:\d[\d,]*(?:\.\d+)?|π)%?"#
        let op = #"(?:\*\*|>=|<=|[-−+*/×÷^x≥≤><]|\bmod\b|\bof\b)"#
        return try? NSRegularExpression(
            pattern: #"((?:(?:(?<![\p{L}\d)])[-−]\s*)?\(?\s*\#(num)\s*\)?(?:\s*\#(op)\s*\(?\s*\#(num)\s*\)?)+)|√\s*\(?\s*\#(num)\s*\)?)(\s*=)?\s*$"#,
            options: [.caseInsensitive])
    }()

    /// Numbers that only look like a sum: whole dates ("29/09/2024",
    /// "2024-09-29", "exp 09/2026") and phone numbers ("555-1234",
    /// "555-123-4567", "+1-555-123-4567", "98765-43210"). Two small numbers
    /// are a sum: "24/7" is divided, "2-3" is -1.
    private static let notASum = #"^\s*(?:\d{1,2}\s*/\s*\d{1,2}\s*/\s*\d{2,4}|\d{4}\s*/\s*\d{1,2}\s*/\s*\d{1,2}|\d{1,2}\s*/\s*(?:19|20)\d{2}|\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}-\d{4}|(?:\d{1,3}-)?\d{3}-\d{3}-\d{4}|\d{3}-\d{4}|\d{5}-\d{5})\s*$"#

    static func calc(_ text: String, indianGrouping: Bool = true) -> (value: String, hasEquals: Bool, expression: String)? {
        guard let re = calcPattern, !text.isEmpty else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.range(at: 1).location != NSNotFound else { return nil }
        let expr = ns.substring(with: m.range(at: 1))
        let hasEquals = m.range(at: 2).location != NSNotFound
        if !hasEquals {
            // A bare number is not a sum, nor is a bare "of" ("page 2 of 10";
            // "20% of 150" has its %).
            if expr.range(of: #"\*\*|>=|<=|[-−+*/×÷^≥≤><%√x]|\bmod\b"#,
                          options: [.regularExpression, .caseInsensitive]) == nil { return nil }
            if expr.range(of: notASum, options: .regularExpression) != nil { return nil }
            // "miss you 2 <3": a heart, not a comparison.
            if text.range(of: #"\s<3\s*$"#, options: .regularExpression) != nil { return nil }
        }
        let shown = expr.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let cmp = expr.range(of: #"\s*(>=|<=|≥|≤|>|<)\s*"#, options: .regularExpression) {
            let sign = expr[cmp].trimmingCharacters(in: .whitespaces)
            guard let a = evaluate(String(expr[..<cmp.lowerBound])),
                  let b = evaluate(String(expr[cmp.upperBound...])) else { return nil }
            let truth: Bool
            switch sign {
            case ">": truth = a > b
            case "<": truth = a < b
            case ">=", "≥": truth = a >= b
            default: truth = a <= b
            }
            return (truth ? "true" : "false", hasEquals, shown)
        }
        guard let v = evaluate(expr) else { return nil }
        let currency = expr.first(where: { "₹$€£".contains($0) }).map(String.init) ?? ""
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // Lakh and crore grouping in India; thousands everywhere else.
        f.locale = Locale(identifier: indianGrouping ? "en_IN" : "en_US")
        f.maximumFractionDigits = 2
        guard let text = f.string(from: NSNumber(value: v)) else { return nil }
        return (currency + text, hasEquals, shown)
    }

    /// Recursive descent over a token list. Returns nil on anything it does
    /// not fully understand, so junk never turns into a wrong answer.
    static func evaluate(_ expression: String) -> Double? {
        var src = expression.lowercased()
        for (from, to) in [("of", "*"), ("mod", "#")] {
            src = src.replacingOccurrences(of: #"\b\#(from)\b"#, with: to,
                                           options: .regularExpression)
        }
        src = src.replacingOccurrences(of: "**", with: "^")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        src = src.filter { !"₹$€£, \t".contains($0) }
        guard !src.isEmpty else { return nil }

        var tokens: [String] = []
        var number = ""
        for ch in src {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else if ch == "π" {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(Double.pi))
            } else if "+-*/^()%#√".contains(ch) {
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
            if peek() == "√" {
                i += 1
                guard let v = unary(), v >= 0 else { return nil }
                return v.squareRoot()
            }
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
            while let op = peek(), op == "*" || op == "/" || op == "#" {
                i += 1
                guard let rhs = power() else { return nil }
                switch op {
                case "/":
                    guard rhs != 0 else { return nil }
                    v /= rhs
                case "#":
                    guard rhs != 0 else { return nil }
                    v = v.truncatingRemainder(dividingBy: rhs)
                default:
                    v *= rhs
                }
            }
            return v
        }
        func sum() -> Double? {
            guard var v = product() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                i += 1
                // "200 + 10%" is 220, as on a phone's calculator: a bare
                // percentage added or taken off is a share of the left side.
                let start = i
                guard let rhs = product() else { return nil }
                let share = i == start + 2 && tokens[i - 1] == "%" ? v * rhs : rhs
                v = op == "+" ? v + share : v - share
            }
            return v
        }
        guard let v = sum(), i == tokens.count, v.isFinite else { return nil }
        return v
    }

    // MARK: Money

    private static let symbolCurrency: [Character: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "₹": "INR", "¥": "JPY",
    ]
    private static let wordCurrency: [String: String] = [
        "usd": "USD", "dollar": "USD", "dollars": "USD", "bucks": "USD",
        "eur": "EUR", "euro": "EUR", "euros": "EUR",
        "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "quid": "GBP",
        "inr": "INR", "rupee": "INR", "rupees": "INR", "rs": "INR",
        "jpy": "JPY", "yen": "JPY", "aud": "AUD", "cad": "CAD", "sgd": "SGD",
        "chf": "CHF", "cny": "CNY", "rmb": "CNY", "yuan": "CNY", "hkd": "HKD",
        "aed": "AED", "dirham": "AED", "dirhams": "AED", "krw": "KRW", "won": "KRW",
    ]
    private static let currencySymbol: [String: String] = [
        "USD": "$", "EUR": "€", "GBP": "£", "INR": "₹", "JPY": "¥", "CNY": "¥", "KRW": "₩",
    ]

    /// An amount at the end of what is being typed: "$13", "13 usd", "₹500",
    /// "20 euros". Symbol or word, either side of the number.
    private static let amountPattern = try? NSRegularExpression(
        pattern: #"(?:([$€£₹¥])\s?(\d[\d,]*(?:\.\d+)?)|(\d[\d,]*(?:\.\d+)?)\s?([$€£₹¥]|[A-Za-z]{2,7}))\s*$"#,
        options: [.caseInsensitive])
    /// "$sol", "$aapl", or the name for people who don't know the ticker
    /// ("$apple", "$bitcoin"; the server finds it): never a number.
    private static let cashtagPattern = try? NSRegularExpression(
        pattern: #"(?:^|\s)\$([A-Za-z]{2,14})\s*$"#)

    /// The ticker at the end of the text, for whoever fetches prices.
    static func cashtag(in text: String) -> String? {
        guard let re = cashtagPattern, !text.isEmpty else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return ns.substring(with: m.range(at: 1)).uppercased()
    }

    /// Whether the text ends in an amount the chip could convert, rate or no
    /// rate — so the keyboard knows to go and fetch one.
    static func looksLikeMoney(_ text: String) -> Bool {
        guard let re = amountPattern, !text.isEmpty else { return false }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return false }
        let unitRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 4)
        guard unitRange.location != NSNotFound else { return false }
        let unit = ns.substring(with: unitRange)
        if unit.count == 1, let c = unit.first { return symbolCurrency[c] != nil }
        return wordCurrency[unit.lowercased()] != nil
    }

    /// "$13" here in India → "$13 = ₹1,246"; "₹500" → "₹500 = $5.21";
    /// "$sol" → "1 SOL = $111.77". A converted amount reads in the local
    /// currency (that is the point of converting); a token price is a price,
    /// which the market quotes in dollars, so it stays in dollars.
    private static let weightTalk = #"\b(lose|lost|losing|gain|gained|gaining|weigh|weighs|weighed|weighing|weight|heavy|heavier|lighter|lbs?|kgs?|kilos?|bench|squat|deadlift|lift|lifted|lifting|dumbbells?|curls?|born)\b"#

    static func money(in text: String, rates: RatesSnapshot) -> Chip? {
        if let ticker = cashtag(in: text) {
            guard let usd = rates.crypto[ticker] else { return nil }
            // "1 SOL = $112" is already the answer; do not price the price.
            if text.replacingOccurrences(of: "$\(ticker.lowercased())", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces).hasSuffix("=") { return nil }
            let quoted = price(usd)
            let name = rates.tickers[ticker] ?? ticker
            return .money(shown: "1 \(name) = \(quoted)", insert: " = \(quoted)", buy: rates.mints[ticker])
        }
        guard let re = amountPattern, !text.isEmpty else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        // The right-hand side of a conversion the chip itself put in ("$13 =
        // ₹1,246"): converting that back would be a loop, not help.
        let head = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
        if head.hasSuffix("=") { return nil }
        func group(_ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        let numberText = group(2) ?? group(3) ?? ""
        guard let amount = Double(numberText.replacingOccurrences(of: ",", with: "")),
              amount > 0 else { return nil }
        let unit = group(1) ?? group(4) ?? ""
        // Pounds of weight are not money: "I lost 5 pounds", "bench 100 pounds".
        if unit.lowercased().hasPrefix("pound"),
           text.range(of: weightTalk, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let from: String
        if unit.count == 1, let c = unit.first, let code = symbolCurrency[c] {
            from = code
        } else if let code = wordCurrency[unit.lowercased()] {
            from = code
        } else {
            return nil
        }
        // Where the phone is, or dollars when the amount already is local.
        let to = from == rates.local ? "USD" : rates.local
        guard to != from, let fromRate = rates.fiat[from], let toRate = rates.fiat[to],
              fromRate > 0 else { return nil }
        let converted = amount / fromRate * toRate
        let typed = "\(currencySymbol[from] ?? "\(from) ")\(formatNumber(amount, code: from))"
        let result = format(converted, in: to)
        return .money(shown: "\(typed) = \(result)", insert: " = \(result)")
    }

    /// A token's dollar price: cents from a dollar up ("$112.40"), and
    /// enough figures below one to see it move ("$0.50", "$0.0823",
    /// "$0.00000364"), as the app's Buy shows it.
    static func price(_ usd: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        if usd >= 0.01 || usd <= 0 {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = usd >= 1 ? 2 : 4
        } else {
            f.usesSignificantDigits = true
            f.maximumSignificantDigits = 3
        }
        return "$" + (f.string(from: NSNumber(value: usd)) ?? String(usd))
    }

    /// "₹1,246", "$5.21", "AED 47.70": the symbol where one is common, the
    /// code elsewhere; Indian grouping for rupees.
    static func format(_ value: Double, in code: String) -> String {
        "\(currencySymbol[code] ?? "\(code) ")\(formatNumber(value, code: code))"
    }

    private static func formatNumber(_ value: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: code == "INR" ? "en_IN" : "en_US")
        let places = code == "JPY" || code == "KRW" ? 0 : 2
        f.maximumFractionDigits = places
        // Money with cents shows both places ("₹1,919.60", not "₹1,919.6");
        // a whole amount shows none ("$20").
        let cents = (value * 100).rounded() / 100
        f.minimumFractionDigits = cents == cents.rounded() ? 0 : places
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: Payments

    /// A Solana address sitting in the text (or on the clipboard), which in a
    /// chat means someone is asking to be paid.
    private static let addressPattern = try? NSRegularExpression(
        pattern: #"(?<![A-HJ-NP-Za-km-z1-9])([1-9A-HJ-NP-Za-km-z]{32,44})(?![A-HJ-NP-Za-km-z1-9])"#)

    static func payment(in text: String) -> (address: String, amount: (value: String, token: String)?)? {
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

    /// "send $200" / "200 usdc" → ("200", "USDC"); "0.5 sol" → ("0.5", "SOL").
    /// Only what Send can pay in: dollars go as USDC, and nothing else is
    /// guessed at (500 rupees is not 500 USDC).
    static func amountAsked(in text: String) -> (value: String, token: String)? {
        let patterns: [(String, String)] = [
            (#"\$\s*\d[\d,]*(?:\.\d{1,6})?(?![\d.])"#, "USDC"),
            (#"\b\d[\d,]*(?:\.\d{1,6})?\s*(?:usdc|dollars?|bucks)\b"#, "USDC"),
            (#"\b\d[\d,]*(?:\.\d{1,9})?\s*sol\b"#, "SOL"),
        ]
        for (p, token) in patterns {
            if let r = text.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                let digits = text[r].filter { $0.isNumber || $0 == "." }
                if !digits.isEmpty, Double(digits) ?? 0 > 0 { return (String(digits), token) }
            }
        }
        return nil
    }

    // MARK: Contextual vault

    /// Sentence endings that mean "the next thing I type is X": the
    /// sentence leads into one of your own details ("my email is", "call me
    /// at", "ship it to") or labels it ("Email:"). A bare word at the end is
    /// not enough: "wrong address", "can you email", "i lost my phone" and
    /// "saw it on insta" are about something else. Each pattern maps to a
    /// vault field kind, and for socials to a platform. Smart.kt's twin.
    private static let triggers: [(pattern: String, kind: String, label: String?)] = [
        // "This is" introduces you only at the start: "Hi, this is", not "this is great".
        (#"(?:\bmy name is|\bname:|(?:^|[.!?,\n]\s*|\b(?:hi|hey|hello|hii|hiya)\W*)this is)\s*$"#, "name", nil),
        // Before address: "my wallet address" asks for the wallet.
        // A coin's name alone is not a wallet ("$sol" is its price, "I bought
        // sol" a purchase), nor is someone else's ("phantom wallet is down").
        (#"(?<!\$)\b(?:(?:my|our)\s+(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet(?:\s+(?:address|addy))?|(?:my|our)\s+(?:sol|solana|phantom|usdc|crypto)\s+(?:address|addy)|(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet(?:\s+(?:address|addy))?\s*:|(?:sol|solana|phantom|usdc|crypto)\s+(?:address|addy)\s*:)\s*(?:is\s*)?:?\s*$"#, "wallet", nil),
        // Before address: "my email address is" is an email.
        (#"\b(?:(?:my|our)\s+(?:e-?mail|g-?mail|mail)(?:\s*(?:id|address|addy))?|(?:e-?mail|g-?mail|mail)\s+(?:me|us)\s+(?:at|on)|(?:e-?mail|g-?mail)(?:\s*(?:id|address|addy))?\s*:|mail\s*id\s*:)\s*(?:is\s*)?:?\s*$"#, "email", nil),
        // The word alone at the end offers it too (Arpit, 2026-10-01: "when i
        // type email it should show my email id"): "email", "send it to my
        // email", "email id", "gmail". Not the verb: "can you email", "i'll
        // email", "please email" ask for one to be sent.
        (#"(?:^|[\s,(])(?<!\b(?:can|could|will|would|should|shall|must|i'll|ill|we'll|i|we|you|u|they|he|she|to|pls|please|gonna|wanna)\s)(?:e-?mail|g-?mail|mail\s*id)(?:\s*(?:id|address|addy))?\s*(?:is\s*)?:?\s*$"#, "email", nil),
        // An IP, web or website address is no place to deliver to.
        (#"(?:\b(?:my|our)\s+(?:(?:home|delivery|shipping|office|current|new)\s+)?(?:address|addy)|(?<!e-?mail\s)(?<!gmail\s)(?<!ip\s)(?<!web\s)(?<!website\s)(?<!mac\s)\b(?:(?:home|delivery|shipping|office)\s+)?address\s*:|\bdeliver(?:\s+it)?\s+to|\bsend\s+it\s+to|\bship\s+(?:it\s+)?to|\bcome\s+(?:over\s+)?to|\bpick\s+me\s+up\s+(?:from|at))\s*(?:is\s*)?:?\s*$"#, "address", nil),
        (#"\b(?:(?:my|our)\s+(?:upi|vpa|gpay|google\s+pay|phonepe|paytm)(?:\s+(?:id|number|handle))?|(?:upi|vpa|gpay|phonepe|paytm)(?:\s*id)?\s*:|(?:pay|gpay|phonepe|paytm)\s+me\s+(?:at|on))\s*(?:is\s*)?:?\s*$"#, "upi", nil),
        (#"\b(?:(?:my|our)\s+(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?|(?:follow|find|add|dm)\s+(?:me|us)\s+on\s+(?:insta|instagram|ig)|(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?\s*:)\s*(?:is\s*)?:?\s*$"#, "social", "insta"),
        (#"\b(?:(?:my|our)\s+(?:twitter|x)(?:\s+(?:handle|id|username))?|(?:follow|find|dm)\s+(?:me|us)\s+on\s+(?:twitter|x)|(?:twitter|x\s+handle)\s*:)\s*(?:is\s*)?:?\s*$"#, "social", "x"),
        (#"\b(?:(?:my|our)\s+linkedin(?:\s+(?:profile|url|handle|id))?|(?:find|add|connect\s+with)\s+(?:me|us)\s+on\s+linkedin|linkedin\s*:)\s*(?:is\s*)?:?\s*$"#, "social", "linkedin"),
        // A phone number, not an account, card, order or ticket number, and
        // not the phone itself ("i lost my phone").
        (#"\b(?:(?:my|our)\s+(?:(?:phone|mobile|cell|contact|whatsapp)\s+)?(?:number|no\.?|num)|(?:my|our)\s+whatsapp|(?:phone|mobile|cell|contact|whatsapp)(?:\s+(?:number|no\.?|num))?\s*:|(?:call|text|whatsapp|ping|reach|ring)\s+(?:me|us)\s+(?:at|on))\s*(?:is\s*)?:?\s*$"#, "phone", nil),
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
            // A social detail may be saved as a handle.
            let candidates = fields.filter { $0.kind == kind || (kind == "social" && $0.kind == "handle") }
            if let label {
                if let hit = candidates.first(where: { isPlatform($0.label, label) }) {
                    return hit
                }
                continue
            }
            // The sentence named the kind; with none saved there is nothing to offer.
            return candidates.first
        }
        return firstPersonMatch(text, fields: fields)
    }

    /// Every saved detail the sentence asks for: the one vaultMatch finds
    /// first, then the others of its kind in the vault's order (a handle
    /// stays the platform's own).
    static func vaultMatches(_ text: String, fields: [VaultField]) -> [VaultField] {
        guard let first = vaultMatch(text, fields: fields) else { return [] }
        if first.kind == "social" || first.kind == "handle" { return [first] }
        return [first] + fields.filter { $0.kind == first.kind && $0.id != first.id }
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

    /// The platform the words named for a handle ("insta", "x",
    /// "linkedin"), or nil for a plain "handle".
    private static func platformNamed(_ words: String) -> String? {
        let w = words.lowercased()
        if w.range(of: #"\b(insta(gram)?|ig)\b"#, options: .regularExpression) != nil { return "insta" }
        if w.range(of: #"\b(twitter|x)\b"#, options: .regularExpression) != nil { return "x" }
        if w.contains("linkedin") { return "linkedin" }
        return nil
    }

    /// Whether a saved handle is that platform's, by its label ("Instagram",
    /// "IG", "Twitter", "X").
    private static func isPlatform(_ label: String, _ platform: String) -> Bool {
        let l = label.lowercased().trimmingCharacters(in: .whitespaces)
        switch platform {
        case "insta": return l.contains("insta") || l.range(of: #"\big\b"#, options: .regularExpression) != nil
        case "x": return l.contains("twitter") || l.range(of: #"(^|\W)x($|\W)"#, options: .regularExpression) != nil
        default: return l.contains(platform)
        }
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
            guard let r = clause.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            else { continue }
            // "My linkedin" is the LinkedIn one, never the Instagram handle;
            // "my handle" takes whichever there is.
            let platform = kind == "social" ? platformNamed(String(clause[r])) : nil
            guard let field = fields.first(where: {
                ($0.kind == kind || (kind == "social" && $0.kind == "handle"))
                    && (platform == nil || isPlatform($0.label, platform!))
            }) else { continue }
            let after = String(clause[r.upperBound...])
                .replacingOccurrences(of: #"^[\s:,-]*(is|are|=)?[\s:,-]*"#, with: "", options: .regularExpression)
            if after.count <= 3 { return field }
        }
        return nil
    }
}

// MARK: - Answers worked out on the phone (hold space)

extension Smart {

    /// What a held space answers right here: a sum, a conversion, money at
    /// the rates the keyboard already holds, the time or the date. No
    /// network, no model, no run spent ("2+5" went to the server and back).
    /// Everything else still goes to the server. Smart.kt's twin, and the
    /// unit table is the server's lib/units.ts.
    struct InstantAnswer: Equatable {
        var title: String
        /// The big line on the card: "7", "3.107 miles", "10:28 PM".
        var value: String
        var sub: String
        /// What Insert puts in the message: "2+5 = 7", "5 km is 3.107 miles".
        var say: String
    }

    static func instantAnswer(_ text: String, rates: RatesSnapshot = .empty,
                              indianGrouping: Bool = true, now: Date = Date(),
                              timeZone: TimeZone = .current, locale: Locale = .current) -> InstantAnswer? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "’", with: "'")
        guard !t.isEmpty, t.count <= 80 else { return nil }
        if let sum = sumAnswer(t, indianGrouping: indianGrouping) { return sum }
        if let units = convertUnits(t) {
            return InstantAnswer(title: t, value: units.to, sub: units.from, say: units.say)
        }
        if let money = moneyAnswer(t, rates: rates) { return money }
        if let days = daysAnswer(t, now: now, timeZone: timeZone, locale: locale) { return days }
        return clockAnswer(t, now: now, timeZone: timeZone, locale: locale)
    }

    // A sum asked as a sum: "2+5", "3480/4 =", "what is 12*12?", "18% of 2450".
    private static func sumAnswer(_ t: String, indianGrouping: Bool) -> InstantAnswer? {
        if let tip = tipAnswer(t) { return tip }
        var expr = t.lowercased()
            .replacingOccurrences(of: #"^(?:what\s+is|what's|whats|how\s+much\s+is|calculate|calc|solve)\s+"#,
                                  with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s?=]+$"#, with: "", options: .regularExpression)
        expr = expr.trimmingCharacters(in: .whitespaces)
        let percent = expr.range(of: #"^\d+(?:\.\d+)?\s*%\s*of\s*[\d,]+(?:\.\d+)?$"#, options: .regularExpression) != nil
        let plain = expr.range(of: #"^(?:[\d\s.,+\-−*/×÷^()%x√π<>≥≤]|mod)+$"#, options: .regularExpression) != nil
            && expr.range(of: #"\d"#, options: .regularExpression) != nil
            && expr.range(of: #"\d\s*(?:[-−+*/×÷^%<>≥≤]|x|mod)\s*[\d(√π]|\d\s*%|√\s*[\d(π]"#, options: .regularExpression) != nil
        guard percent || plain, let result = calc(expr + " =", indianGrouping: indianGrouping) else { return nil }
        let say = percent ? "\(expr) is \(result.value)" : "\(expr) = \(result.value)"
        return InstantAnswer(title: expr, value: result.value, sub: expr, say: say)
    }

    // "15% tip on 64": the tip, and what that comes to (answers.ts mathAnswer).
    private static let tipAsk = try? NSRegularExpression(pattern:
        #"^(?:what\s+is\s+|what's\s+|whats\s+|calculate\s+)?([\d.]+)\s*%\s*tip\s*(?:on|for|of)\s*([$€£₹]?)\s*([\d,.]+)\s*\??$"#,
        options: [.caseInsensitive])

    private static func tipAnswer(_ t: String) -> InstantAnswer? {
        guard let re = tipAsk else { return nil }
        let ns = t as NSString
        guard let m = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let percentText = ns.substring(with: m.range(at: 1))
        let symbol = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
        let billText = ns.substring(with: m.range(at: 3))
        guard let percent = Double(percentText), let bill = Double(billText.replacingOccurrences(of: ",", with: ""))
        else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.roundingMode = .halfUp
        func money(_ n: Double) -> String { symbol + (f.string(from: NSNumber(value: n)) ?? String(n)) }
        let tip = percent / 100 * bill
        return InstantAnswer(title: t, value: money(tip), sub: "\(money(bill + tip)) in all",
                             say: "\(percentText)% tip on \(symbol)\(billText) is \(money(tip)) (\(money(bill + tip)) in all)")
    }

    // "100 usd to inr", "$13 in rupees", "50 euros in dollars": today's rates,
    // when the keyboard has them (otherwise the server answers).
    private static let moneyAsk = try? NSRegularExpression(pattern:
        #"^(?:convert\s+|what\s+is\s+|what's\s+|whats\s+|how\s+much\s+is\s+)?(?:([$€£₹¥])\s?(\d[\d,]*(?:\.\d+)?)|(\d[\d,]*(?:\.\d+)?)\s?([a-z]{2,8}|[$€£₹¥]))\s+(?:to|in|into|=)\s+([a-z]{2,8}|[$€£₹¥])\s*\??$"#,
        options: [.caseInsensitive])

    private static func moneyAnswer(_ t: String, rates: RatesSnapshot) -> InstantAnswer? {
        guard let re = moneyAsk else { return nil }
        let ns = t as NSString
        guard let m = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        func code(_ unit: String?) -> String? {
            guard let unit else { return nil }
            if unit.count == 1, let c = unit.first, let code = symbolCurrency[c] { return code }
            return wordCurrency[unit.lowercased()]
        }
        guard let amount = Double((group(2) ?? group(3) ?? "").replacingOccurrences(of: ",", with: "")),
              amount > 0,
              let from = code(group(1) ?? group(4)), let to = code(group(5)), from != to,
              let fromRate = rates.fiat[from], fromRate > 0, let toRate = rates.fiat[to]
        else { return nil }
        let typed = format(amount, in: from)
        let result = format(amount / fromRate * toRate, in: to)
        return InstantAnswer(title: "\(from) to \(to)", value: result, sub: "\(typed) · today's rate",
                             say: "\(typed) = \(result)")
    }

    // "how many days until christmas": counted on the phone's own calendar
    // (answers.ts daysAnswer).
    private static let daysAsk = try? NSRegularExpression(pattern:
        #"^(?:how\s+many\s+(days?|weeks?)\s+(?:are\s+)?(?:left\s+)?(?:until|till|til|to|before)|(days?|weeks?)\s+(?:left\s+)?(?:until|till|til|to)|how\s+long\s+(?:is\s+it\s+)?(?:until|till|til|to))\s+(.+?)\s*\??$"#,
        options: [.caseInsensitive])

    /// Days everyone counts to: the name it is said with, and its month and
    /// day in a given year (Thanksgiving moves).
    private static let countedDays: [(pattern: String, label: String, date: (Int) -> (Int, Int))] = [
        (#"^christmas eve$"#, "Christmas Eve", { _ in (12, 24) }),
        (#"^(?:christmas|xmas|christmas day)$"#, "Christmas", { _ in (12, 25) }),
        (#"^new year'?s eve$"#, "New Year's Eve", { _ in (12, 31) }),
        (#"^(?:new year'?s?|new year'?s day|the new year)$"#, "New Year's Day", { _ in (1, 1) }),
        (#"^halloween$"#, "Halloween", { _ in (10, 31) }),
        (#"^valentine'?s(?: day)?$"#, "Valentine's Day", { _ in (2, 14) }),
        (#"^(?:the )?(?:4th|fourth) of july$|^independence day$"#, "the Fourth of July", { _ in (7, 4) }),
        (#"^thanksgiving$"#, "Thanksgiving", { year in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let first = cal.date(from: DateComponents(year: year, month: 11, day: 1)).map { cal.component(.weekday, from: $0) } ?? 1
            // weekday: Sunday 1 … Thursday 5; the fourth Thursday.
            return (11, 1 + (5 - first + 7) % 7 + 21)
        }),
    ]
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func daysAnswer(_ t: String, now: Date, timeZone: TimeZone, locale: Locale) -> InstantAnswer? {
        guard let re = daysAsk else { return nil }
        let lower = t.lowercased()
        let ns = lower as NSString
        guard let m = re.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        let weeks = (group(1) ?? group(2) ?? "").hasPrefix("week")
        let what = (group(3) ?? "").replacingOccurrences(of: #"^the\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        let year = cal.component(.year, from: now)
        var label: String
        var dateFor: (Int) -> (Int, Int)
        if let holiday = countedDays.first(where: { what.range(of: $0.pattern, options: .regularExpression) != nil
                                                    || "the \(what)".range(of: $0.pattern, options: .regularExpression) != nil }) {
            label = holiday.label
            dateFor = holiday.date
        } else {
            // "dec 25", "december 25", "25 dec", "25th of december"
            let parts = what.split(separator: " ").map(String.init).filter { $0 != "of" }
            guard parts.count == 2 else { return nil }
            let first = parts[0], second = parts[1]
            let digits = CharacterSet.decimalDigits
            let dayText = first.unicodeScalars.first.map { digits.contains($0) } == true ? first : second
            let monthText = dayText == first ? second : first
            guard let day = Int(dayText.trimmingCharacters(in: CharacterSet.letters)),
                  let index = monthNames.firstIndex(of: String(monthText.prefix(3))), (1...31).contains(day)
            else { return nil }
            label = "\(monthText.prefix(1).uppercased())\(monthText.dropFirst().prefix(2)) \(day)"
            dateFor = { _ in (index + 1, day) }
        }
        func target(_ y: Int) -> Date? {
            let (month, day) = dateFor(y)
            return cal.date(from: DateComponents(year: y, month: month, day: day))
        }
        guard var when = target(year) else { return nil }
        if when < today, let next = target(year + 1) { when = next }
        let days = cal.dateComponents([.day], from: today, to: when).day ?? 0
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        let count = weeks && days >= 7
            ? plural(days / 7, "week") + (days % 7 > 0 ? " and \(plural(days % 7, "day"))" : "")
            : plural(days, "day")
        let say = days == 0 ? "\(label) is today" : "\(count) until \(label)"
        return InstantAnswer(title: t, value: days == 0 ? "Today" : count, sub: f.string(from: when), say: say)
    }

    // "what time is it", "what's the date": the phone's own clock.
    private static func clockAnswer(_ t: String, now: Date, timeZone: TimeZone, locale: Locale) -> InstantAnswer? {
        let lower = t.lowercased()
        let time = lower.range(of: #"^(?:what(?:'s|s| is)?\s+(?:the\s+)?time(?:\s+(?:is\s+it|now|rn))?|what\s+time\s+is\s+it(?:\s+now)?|time(?:\s+now)?|current\s+time)\s*\??$"#,
                               options: .regularExpression) != nil
        let date = lower.range(of: #"^(?:what(?:'s|s| is)?\s+(?:the\s+|today'?s\s+)?date(?:\s+today)?|today'?s\s+date|what\s+day\s+is\s+(?:it|today)(?:\s+today)?|date(?:\s+today)?|what(?:'s|s| is)\s+today)\s*\??$"#,
                               options: .regularExpression) != nil
        guard time || date else { return nil }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        if time {
            f.timeStyle = .short
            f.dateStyle = .none
            // iOS puts a narrow no-break space before PM; a message wants a plain one.
            let clock = f.string(from: now).replacingOccurrences(of: "\u{202F}", with: " ")
            f.setLocalizedDateFormatFromTemplate("EEEE")
            return InstantAnswer(title: "Time", value: clock, sub: f.string(from: now), say: "It's \(clock)")
        }
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let day = f.string(from: now)
        f.setLocalizedDateFormatFromTemplate("y")
        return InstantAnswer(title: "Date", value: day, sub: f.string(from: now), say: "It's \(day)")
    }

    // MARK: Units (lib/units.ts, the same table and the same cases)

    struct UnitConversion: Equatable {
        var from: String
        var to: String
        var say: String
    }

    private struct UnitDef {
        let dim: String
        let size: Double
        let one: String
        let many: String
        let names: [String]
    }

    private static let unitDefs: [UnitDef] = [
        UnitDef(dim: "length", size: 0.001, one: "mm", many: "mm", names: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"]),
        UnitDef(dim: "length", size: 0.01, one: "cm", many: "cm", names: ["cm", "cms", "centimeter", "centimeters", "centimetre", "centimetres"]),
        UnitDef(dim: "length", size: 1, one: "m", many: "m", names: ["m", "meter", "meters", "metre", "metres", "mtr", "mtrs"]),
        UnitDef(dim: "length", size: 1000, one: "km", many: "km", names: ["km", "kms", "kilometer", "kilometers", "kilometre", "kilometres"]),
        UnitDef(dim: "length", size: 0.0254, one: "inch", many: "inches", names: ["in", "inch", "inches"]),
        UnitDef(dim: "length", size: 0.3048, one: "foot", many: "feet", names: ["ft", "foot", "feet"]),
        UnitDef(dim: "length", size: 0.9144, one: "yard", many: "yards", names: ["yd", "yds", "yard", "yards"]),
        UnitDef(dim: "length", size: 1609.344, one: "mile", many: "miles", names: ["mi", "mile", "miles"]),
        UnitDef(dim: "mass", size: 0.001, one: "mg", many: "mg", names: ["mg", "milligram", "milligrams"]),
        UnitDef(dim: "mass", size: 1, one: "g", many: "g", names: ["g", "gm", "gms", "gram", "grams"]),
        UnitDef(dim: "mass", size: 1000, one: "kg", many: "kg", names: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"]),
        UnitDef(dim: "mass", size: 1e6, one: "tonne", many: "tonnes", names: ["tonne", "tonnes"]),
        UnitDef(dim: "mass", size: 28.349523125, one: "oz", many: "oz", names: ["oz", "ounce", "ounces"]),
        UnitDef(dim: "mass", size: 453.59237, one: "lb", many: "lb", names: ["lb", "lbs", "pound", "pounds"]),
        UnitDef(dim: "mass", size: 6350.29318, one: "stone", many: "stone", names: ["st", "stone", "stones"]),
        UnitDef(dim: "temperature", size: 1, one: "°C", many: "°C", names: ["c", "°c", "celsius", "centigrade", "degrees c", "degree c", "deg c", "degrees celsius"]),
        UnitDef(dim: "temperature", size: 1, one: "°F", many: "°F", names: ["f", "°f", "fahrenheit", "degrees f", "degree f", "deg f", "degrees fahrenheit"]),
        UnitDef(dim: "temperature", size: 1, one: "K", many: "K", names: ["k", "kelvin"]),
        UnitDef(dim: "volume", size: 0.001, one: "ml", many: "ml", names: ["ml", "milliliter", "milliliters", "millilitre", "millilitres"]),
        UnitDef(dim: "volume", size: 1, one: "litre", many: "litres", names: ["l", "liter", "liters", "litre", "litres", "ltr", "ltrs"]),
        UnitDef(dim: "volume", size: 0.00492892159375, one: "tsp", many: "tsp", names: ["tsp", "teaspoon", "teaspoons"]),
        UnitDef(dim: "volume", size: 0.01478676478125, one: "tbsp", many: "tbsp", names: ["tbsp", "tablespoon", "tablespoons"]),
        UnitDef(dim: "volume", size: 0.0295735295625, one: "fl oz", many: "fl oz", names: ["fl oz", "fluid ounce", "fluid ounces"]),
        UnitDef(dim: "volume", size: 0.2365882365, one: "cup", many: "cups", names: ["cup", "cups"]),
        UnitDef(dim: "volume", size: 0.473176473, one: "pint", many: "pints", names: ["pint", "pints"]),
        UnitDef(dim: "volume", size: 0.946352946, one: "quart", many: "quarts", names: ["quart", "quarts"]),
        UnitDef(dim: "volume", size: 3.785411784, one: "gallon", many: "gallons", names: ["gal", "gallon", "gallons"]),
        UnitDef(dim: "speed", size: 1 / 3.6, one: "km/h", many: "km/h", names: ["km/h", "kmh", "kmph", "kph", "kilometers per hour", "kilometres per hour", "km per hour"]),
        UnitDef(dim: "speed", size: 0.44704, one: "mph", many: "mph", names: ["mph", "miles per hour", "mi/h"]),
        UnitDef(dim: "speed", size: 1, one: "m/s", many: "m/s", names: ["m/s", "meters per second", "metres per second"]),
        UnitDef(dim: "speed", size: 1852.0 / 3600, one: "knot", many: "knots", names: ["knot", "knots"]),
        UnitDef(dim: "time", size: 1, one: "second", many: "seconds", names: ["s", "sec", "secs", "second", "seconds"]),
        UnitDef(dim: "time", size: 60, one: "minute", many: "minutes", names: ["min", "mins", "minute", "minutes"]),
        UnitDef(dim: "time", size: 3600, one: "hour", many: "hours", names: ["h", "hr", "hrs", "hour", "hours"]),
        UnitDef(dim: "time", size: 86400, one: "day", many: "days", names: ["day", "days"]),
        UnitDef(dim: "time", size: 604800, one: "week", many: "weeks", names: ["wk", "wks", "week", "weeks"]),
        UnitDef(dim: "time", size: 31557600, one: "year", many: "years", names: ["yr", "yrs", "year", "years"]),
        UnitDef(dim: "area", size: 0.09290304, one: "sq ft", many: "sq ft", names: ["sq ft", "sqft", "square feet", "square foot", "ft2"]),
        UnitDef(dim: "area", size: 1, one: "sq m", many: "sq m", names: ["sq m", "sqm", "square meters", "square metres", "square meter", "square metre", "m2"]),
        UnitDef(dim: "area", size: 4046.8564224, one: "acre", many: "acres", names: ["acre", "acres"]),
        UnitDef(dim: "area", size: 10000, one: "hectare", many: "hectares", names: ["ha", "hectare", "hectares"]),
    ]

    private static let unitByName: [String: UnitDef] = {
        var out: [String: UnitDef] = [:]
        for u in unitDefs { for n in u.names { out[n] = u } }
        return out
    }()

    /// Longest names first, so "fl oz" wins over "oz" and "km/h" over "km".
    private static let unitNamePattern: String = unitByName.keys.sorted { $0.count > $1.count }
        .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    private static let unitNumber = #"(-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|-?\.\d+)"#
    private static let unitDirect = try? NSRegularExpression(pattern:
        #"^(?:(?:convert|what\s+is|what's|whats|how\s+much\s+is|how\s+many\s+is)\s+)?"# + unitNumber +
        #"\s*(?:degrees?\s+)?("# + unitNamePattern + #")\s+(?:to|in|into|as|in\s+to|=|->|=>)\s+(?:degrees?\s+)?("# +
        unitNamePattern + #")\s*\??$"#, options: [.caseInsensitive])
    private static let unitHowMany = try? NSRegularExpression(pattern:
        #"^how\s+many\s+("# + unitNamePattern + #")\s+(?:are\s+)?(?:in|is\s+in|make|makes)\s+(?:(?:a|an|one)\s+|"# +
        unitNumber + #"\s*)("# + unitNamePattern + #")\s*\??$"#, options: [.caseInsensitive])

    /// A height in feet and inches: "5 ft 10 in", "5'10", "5 feet 10 inches".
    private static let unitFeetInches = try? NSRegularExpression(pattern:
        #"^(?:(?:convert|what\s+is|what's|whats|how\s+much\s+is)\s+)?(\d+)\s*(?:ft|feet|foot|')\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|"|'')?\s+(?:to|in|into|as|=)\s+("# +
        unitNamePattern + #")\s*\??$"#, options: [.caseInsensitive])

    /// Under ten feet, feet come as a height: "5 ft 10 in", not "5.84 feet".
    private static func asHeight(metres: Double) -> String? {
        let feet = metres / 0.3048
        guard feet >= 1, feet < 10 else { return nil }
        var whole = Int(feet.rounded(.down))
        var inches = Int(((feet - Double(whole)) * 12).rounded(.toNearestOrAwayFromZero))
        if inches == 12 { whole += 1; inches = 0 }
        return inches > 0 ? "\(whole) ft \(inches) in" : "\(whole) ft"
    }

    /// "5 km in miles" → "5 km is 3.107 miles"; nil when it is not a conversion.
    static func convertUnits(_ text: String) -> UnitConversion? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "’", with: "'").lowercased()
        let ns = t as NSString
        let all = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        if let m = unitFeetInches?.firstMatch(in: t, range: all) {
            guard let to = group(m, 3).flatMap({ unitByName[$0] }), to.dim == "length",
                  let feet = group(m, 1).flatMap({ Double($0) }), let inches = group(m, 2).flatMap({ Double($0) })
            else { return nil }
            let metres = feet * 0.3048 + inches * 0.0254
            let a = inches > 0 ? "\(Int(feet)) ft \(unitNumber(inches)) in" : "\(Int(feet)) ft"
            let b = unitNamed(unitFromBase(metres, to), to)
            return UnitConversion(from: a, to: b, say: "\(a) is \(b)")
        }
        var amount: Double
        var from: UnitDef?
        var to: UnitDef?
        if let m = unitDirect?.firstMatch(in: t, range: all) {
            amount = Double((group(m, 1) ?? "").replacingOccurrences(of: ",", with: "")) ?? .nan
            from = group(m, 2).flatMap { unitByName[$0] }
            to = group(m, 3).flatMap { unitByName[$0] }
        } else if let m = unitHowMany?.firstMatch(in: t, range: all) {
            to = group(m, 1).flatMap { unitByName[$0] }
            amount = group(m, 2).flatMap { Double($0.replacingOccurrences(of: ",", with: "")) } ?? 1
            from = group(m, 3).flatMap { unitByName[$0] }
        } else {
            return nil
        }
        guard let from, let to, from.one != to.one, from.dim == to.dim, amount.isFinite else { return nil }
        let result = unitFromBase(unitToBase(amount, from), to)
        guard result.isFinite else { return nil }
        let a = unitNamed(amount, from)
        let b = (to.one == "foot" ? asHeight(metres: unitToBase(amount, from)) : nil) ?? unitNamed(result, to)
        return UnitConversion(from: a, to: b, say: "\(a) is \(b)")
    }

    private static func unitToBase(_ n: Double, _ u: UnitDef) -> Double {
        guard u.dim == "temperature" else { return n * u.size }
        if u.one == "°F" { return (n - 32) * 5 / 9 }
        if u.one == "K" { return n - 273.15 }
        return n
    }

    private static func unitFromBase(_ n: Double, _ u: UnitDef) -> Double {
        guard u.dim == "temperature" else { return n / u.size }
        if u.one == "°F" { return n * 9 / 5 + 32 }
        if u.one == "K" { return n + 273.15 }
        return n
    }

    /// As precise as the size needs: 160,934, 220.5, 32.19, 3.107, 0.0254.
    static func unitNumber(_ n: Double) -> String {
        let size = abs(n)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 0
        f.roundingMode = .halfUp   // as the server's toLocaleString rounds
        if size >= 1 || size == 0 {
            f.maximumFractionDigits = size >= 1000 ? 0 : size >= 100 ? 1 : size >= 10 ? 2 : 3
            return f.string(from: NSNumber(value: n)) ?? String(n)
        }
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 3
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static func unitNamed(_ n: Double, _ u: UnitDef) -> String {
        let text = unitNumber(n)
        if u.one == "K" { return "\(text) K" }
        if u.one.hasPrefix("°") { return "\(text)\(u.one)" }
        return "\(text) \(abs(n) == 1 ? u.one : u.many)"
    }
}

// MARK: - Questions (the AI answer chip, as it is typed)

extension Smart {

    /// A question for a fact, told by its words on the phone (Arpit,
    /// 2026-09-30: "we can detect questions too with what where like words"):
    /// the strip offers "AI answer" as it is typed, with no wait for the
    /// server's read. The server's rules (lib/act.ts infoQuestion, searchLike,
    /// answers.ts rightNow), with one more: the question has to end on a word
    /// of substance, so "who is the" offers nothing yet. Returns the question
    /// (the last sentence typed), or nil. Smart.kt's twin, and
    /// shared/questions/cases.json holds the cases both run.
    static func question(in text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        guard !t.isEmpty, t.count <= 160 else { return nil }
        // The last line, then the last sentence: "ok cool. who painted it?"
        if let nl = t.lastIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
        let asked = t.hasSuffix("?")
        var body = t.replacingOccurrences(of: #"[?!.\s]+$"#, with: "", options: .regularExpression)
        if let end = body.range(of: #"^.*[.!?]\s+"#, options: .regularExpression) {
            body = String(body[end.upperBound...])
        }
        let lower = body.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let words = lower.split(separator: " ")
        guard words.count >= 3, words.count <= 12 else { return nil }
        guard asked || matches(QuestionRules.start, lower) else { return nil }
        // "how to make pancakes" is a video to find, not a fact.
        if lower.hasPrefix("how to ") { return nil }
        for rule in [QuestionRules.chitchat, QuestionRules.secondPerson, QuestionRules.addressed,
                     QuestionRules.ownPlans, QuestionRules.localAsk, QuestionRules.smallTalk, QuestionRules.rightNow]
        where matches(rule, lower) { return nil }
        // "does it hurt?", "is that true": short, and about the chat.
        if words.count <= 4, matches(QuestionRules.pointing, lower) { return nil }
        let bare = QuestionRules.searchMe.map {
            $0.stringByReplacingMatches(in: lower, range: NSRange(lower.startIndex..., in: lower), withTemplate: " ")
        } ?? lower
        if matches(QuestionRules.people, bare) { return nil }
        // Still being typed: "who is the", "what does".
        if !asked, let last = words.last, QuestionRules.unfinished.contains(String(last)) { return nil }
        let q = body.trimmingCharacters(in: .whitespaces)
        return asked ? q + "?" : q
    }

    private static func matches(_ re: NSRegularExpression?, _ s: String) -> Bool {
        guard let re else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// The server's word lists, as it has them (lib/act.ts).
    private enum QuestionRules {
        static let start = rx(#"^(?:what|what's|whats|who|who's|whos|whose|whom|where|where's|wheres|when|when's|whens|why|how|how's|hows|which|is|isn't|are|aren't|was|were|can|can't|could|do|does|don't|doesn't|did|didn't|will|won't|would|should|shall|have|has|may|might|any)\b"#)
        static let chitchat = rx(#"^(?:ok(?:ay)?|k+|kk|hi+|hey+|hello|yo|sup|wass?up|what'?s up|whats up|wyd|hru|how (?:are|r) (?:you|u)|how'?s it going|good (?:morning|night|evening|afternoon)|gm|gn|thanks?|thank you|thx|ty|lol|haha\w*|yes|yeah|yep|no|nope|sure|cool|nice|great|done|np|no worries|see (?:you|u|ya)(?: soon| later)?|bye|cya|ttyl|lmk|brb|omw)(?:\s+(?:bro|dude|man|yaar|bhai|mate|buddy))?[\s!?.]*$"#)
        static let secondPerson = rx(#"\b(?:u|ur|you|your|yours|you're|youre|ya|yall|y'all|tu|tum|tumhe|tumko|tumne|tumhara|tumhari|tumhare|tera|teri|tere|aap|aapko|aapne|aapka|aapki|aapke)\b"#)
        static let addressed = rx(#"^(?:bhai|bro|bruh|yaar|dude|mom|mum|maa|papa|dad|didi|bhaiya|babe|baby|hey|hi|hello|yo|oye|arre)\b|\b(?:bhai|bro|yaar|dude|babe|bhaiya|didi)[?!.]*$"#)
        static let ownPlans = rx(#"\b(?:the|our|my|ur|your|this|tonight'?s|tomorrow'?s|tmrw'?s)\s+(?:meeting|meet|party|call|dinner|lunch|brunch|breakfast|appointment|appt|flight|reservation|booking|interview|class|practice|rehearsal|wedding|event|plan|plans|trip|standup|stand-up|shift|session|date|hangout|get together|get-together|pickup|pick up|drop off|shoot|exam|gig|reunion|sleepover|potluck|bus|train|metro|subway|uber|lyft|cab|taxi|ride|delivery|order|package|parcel)\b|\bwho(?:'s| is| all is| all are| are)\s+(?:coming|joining|going|in|bringing)\b"#)
        /// About something where the writer is ("is the store open", "whats
        /// the wifi password"): a question for a person there, not the AI.
        static let localAsk = rx(#"\b(?:password|passcode|wifi|wi-fi|door code|the (?:store|shop|pharmacy|mall|gym|car|kids|dog|cat|baby|fridge|remote|charger|keys?))\b"#)
        static let smallTalk = rx(#"\b(?:thanks|thank you|thx|tnx|ty|lol|lmao|lmfao|rofl|haha\w*|hehe\w*|omg|congrats|sorry|sry|pls|plz|please|hey|hi|hello|yo|bro|dude|yaar|bhai|okay|ok|kk|yeah|yep|yup|nope|sure)\b|!|\p{Extended_Pictographic}"#)
        /// Today's score or the news: the AI can't know, so no chip that would
        /// only say "Nothing found" (answers.ts rightNow).
        static let rightNow = rx(#"\b(?:scores?|live|right now|today'?s?|tonight'?s?|this (?:morning|afternoon|evening|week|weekend)|yesterday'?s?|last night'?s?|news|headlines?|breaking|stock price|share price|trading at|exchange rates?|forex|forecast|weather|time is it|time in)\b"#)
        static let pointing = rx(#"\b(?:it|this|that|these|those|there)\b"#)
        static let people = rx(#"\b(?:i|i'm|im|i've|ive|i'll|i'd|me|my|mine|myself|we|we're|we've|we'll|we'd|us|our|ours|u|ur|you|you're|youre|you've|you'll|you'd|your|yours|ya|yall|y'all|let's|lets|he|she|him|her|his|hers|they|them|their|theirs)\b"#)
        static let searchMe = rx(#"\b(?:near|around|for|to|from|with)\s+me\b|^(?:send|show|give|find|get|play|tell)\s+me\b"#)
        /// A question can't end on these: it is still being typed.
        static let unfinished: Set<String> = [
            "the", "a", "an", "of", "in", "on", "at", "to", "for", "from", "with", "by", "and", "or", "but",
            "is", "are", "was", "were", "be", "been", "do", "does", "did", "has", "have", "had", "what",
            "who", "where", "when", "why", "how", "which", "whose", "whom", "this", "that", "these", "those",
            "some", "any", "much", "many", "than", "as", "about", "into", "over", "like", "if", "so", "not",
            "can", "could", "will", "would", "should", "shall", "may", "might", "must", "very", "more",
            "most", "less", "per", "vs", "via", "its", "no",
        ]
        private static func rx(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }
    }
}
