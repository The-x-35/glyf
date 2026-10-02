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
        /// A measurement the message ends on, in the other system: one part
        /// for each result ("10 inch" → 25.4 cm, 0.254 m), and a tap on a
        /// part adds it in brackets (Smart.conversions).
        case convert(Conversions)

        /// The parts of a chip drawn as a row of chips: the saved details (and
        /// Temp), or a measurement's results.
        var choices: (values: [String], temp: Bool)? {
            switch self {
            case .details(let fields, let temp): return (fields.map(\.value), temp)
            case .convert(let c): return (c.results, false)
            default: return nil
            }
        }

        var key: String {
            switch self {
            case .event, .booking: return "Calendar"
            case .calc, .money, .convert: return "="
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
            case .details, .convert: return nil    // each part is its own action
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
            // A copy shown in its parts: the whole copy is the first part.
            case .convert(let c) where c.source.isEmpty: return c.inserts?.first
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
            case .convert(let c):
                return c.source.isEmpty ? c.results.joined(separator: " · ") : "\(c.source) = " + c.results.joined(separator: " · ")
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
            case .details, .convert: return ""   // a part's own tap types it
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
                     ownWallet: String? = nil, indianGrouping: Bool = true,
                     region: String? = Locale.current.region?.identifier) -> Chip? {
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
        if let c = quickAnswer(in: text, region: region) { return .convert(c) }
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
            let held = detailsFor(kind: kind, fields: fields)
            if held.count > 1 { return .details(fields: Array(held.prefix(3)), temp: false) }
            if let f = held.first { return .vault(field: f) }
        }
        if let paste, !paste.isEmpty, text.isEmpty {
            // A copy with emails, links or numbers in it: the whole, then each.
            if let parts = pieces(of: paste) {
                let all = [paste] + parts
                return .convert(Conversions(source: "", results: ["Paste all"] + parts,
                                            inserts: all, hows: Array(repeating: .after, count: all.count)))
            }
            return .paste(text: paste)
        }
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
        (#"(?:^|[\s,(])(?<!\b(?:can|could|will|would|should|shall|must|i'll|ill|we'll|i|we|you|u|they|he|she|to|pls|please|gonna|wanna|the|this|that|a|an)\s)(?:e-?mail|g-?mail|mail\s*id)(?:\s*(?:id|address|addy))?\s*(?:is\s*)?:?\s*$"#, "email", nil),
        // An IP, web or website address is no place to deliver to.
        (#"(?:\b(?:my|our)\s+(?:(?:home|delivery|shipping|office|current|new)\s+)?(?:address|addy)|(?<!e-?mail\s)(?<!gmail\s)(?<!ip\s)(?<!web\s)(?<!website\s)(?<!mac\s)\b(?:(?:home|delivery|shipping|office)\s+)?address\s*:|\bdeliver(?:\s+it)?\s+to|\bsend\s+it\s+to|\bship\s+(?:it\s+)?to|\bcome\s+(?:over\s+)?to|\bpick\s+me\s+up\s+(?:from|at))\s*(?:is\s*)?:?\s*$"#, "address", nil),
        (#"\b(?:(?:my|our)\s+(?:upi|vpa|gpay|google\s+pay|phonepe|paytm)(?:\s+(?:id|number|handle))?|(?:upi|vpa|gpay|phonepe|paytm)(?:\s*id)?\s*:|(?:pay|gpay|phonepe|paytm)\s+me\s+(?:at|on))\s*(?:is\s*)?:?\s*$"#, "upi", nil),
        (#"\b(?:(?:my|our)\s+(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?|(?:follow|find|add|dm)\s+(?:me|us)\s+on\s+(?:insta|instagram|ig)|(?:insta|instagram|ig)(?:\s+(?:handle|id|username))?\s*:)\s*(?:is\s*)?:?\s*$"#, "social", "insta"),
        (#"\b(?:(?:my|our)\s+(?:twitter|x)(?:\s+(?:handle|id|username))?|(?:follow|find|dm)\s+(?:me|us)\s+on\s+(?:twitter|x)|(?:twitter|x\s+handle)\s*:)\s*(?:is\s*)?:?\s*$"#, "social", "x"),
        (#"\b(?:(?:my|our)\s+linkedin(?:\s+(?:profile|url|handle|id))?|(?:find|add|connect\s+with)\s+(?:me|us)\s+on\s+linkedin|linkedin\s*:)\s*(?:is\s*)?:?\s*$"#, "social", "linkedin"),
        // A phone number, not an account, card, order or ticket number, and
        // not the phone itself ("i lost my phone").
        (#"\b(?:(?:my|our)\s+(?:(?:phone|mobile|cell|contact|whatsapp)\s+)?(?:number|no\.?|num)|(?:my|our)\s+whatsapp|(?:phone|mobile|cell|contact|whatsapp)(?:\s+(?:number|no\.?|num))?\s*:|(?:call|text|whatsapp|ping|reach|ring)\s+(?:me|us)\s+(?:at|on))\s*(?:is\s*)?:?\s*$"#, "phone", nil),
        // The kind's own words, two of them, alone at the end (Arpit,
        // 2026-10-02: "for all data in vault, it should be super fast using
        // regex"): "phone number", "shipping address", "wallet address", "upi
        // id", "instagram", "linkedin". Never someone else's ("your number",
        // "the phone number", "whose address").
        (#"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:phone|mobile|cell|contact|whatsapp)\s+(?:number|no\.?|num)\s*(?:is\s*)?:?\s*$"#, "phone", nil),
        (#"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:home|delivery|shipping|billing|office|work|current|postal|mailing)\s+(?:address|addy)\s*(?:is\s*)?:?\s*$"#, "address", nil),
        (#"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:(?:(?:sol|solana|phantom|usdc|crypto)\s+)?wallet\s+(?:address|addy)|(?:sol|solana)\s+(?:address|addy))\s*(?:is\s*)?:?\s*$"#, "wallet", nil),
        (#"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:upi|vpa)(?:\s*(?:id|handle))?\s*(?:is\s*)?:?\s*$"#, "upi", nil),
        (#"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what|on|in|from|at|via|to)\s)(?:insta|instagram|ig\s+(?:handle|id|username))(?:\s+(?:handle|id|username))?\s*(?:is\s*)?:?\s*$"#, "social", "insta"),
        (#"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)(?:twitter|x)\s+(?:handle|id|username)\s*(?:is\s*)?:?\s*$"#, "social", "x"),
        (#"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what|on|in|from|at|via|to)\s)linkedin(?:\s+(?:profile|url|handle|id))?\s*(?:is\s*)?:?\s*$"#, "social", "linkedin"),
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

    /// What the vault holds for a field of this kind, one per value: its
    /// saved details, or a part of one (the postcode in an address, the first
    /// or last word of the name, a detail labelled as the company). Both
    /// keyboards; shared/vault/field-cases.json.
    static func detailsFor(kind: String, fields: [VaultField]) -> [VaultField] {
        let found: [VaultField]
        switch kind {
        case "postcode":
            found = fields.filter { $0.kind == "address" }.compactMap { a in
                postcode(in: a.value).map { VaultField(id: a.id + ":postcode", kind: "postcode", label: "Postcode", value: $0) }
            }
        case "givenName", "familyName":
            found = fields.filter { $0.kind == "name" }.compactMap { n in
                let parts = n.value.split(separator: " ").map(String.init)
                guard !parts.isEmpty, kind == "givenName" || parts.count >= 2 else { return nil }
                return VaultField(id: n.id + ":" + kind, kind: kind,
                                  label: kind == "givenName" ? "First name" : "Last name",
                                  value: kind == "givenName" ? parts[0] : parts[parts.count - 1])
            }
        case "company":
            found = fields.filter {
                $0.kind == "company" || $0.label.range(of: #"\b(?:company|organi[sz]ation|employer|workplace)\b"#,
                                                        options: [.regularExpression, .caseInsensitive]) != nil
            }
        default:
            found = fields.filter { $0.kind == kind }
        }
        var seen: Set<String> = []
        return found.filter { seen.insert($0.value.trimmingCharacters(in: .whitespaces).lowercased()).inserted }
    }

    /// The postcode in an address, the last one written: a UK or Canadian
    /// postcode, a US ZIP, a six-digit PIN, or four digits at the very end.
    static func postcode(in address: String) -> String? {
        let patterns = [
            #"\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b"#,   // UK: SW1A 2AA
            #"\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b"#,            // Canada: K1A 0B1
            #"\b\d{5}(?:-\d{4})?\b"#,                     // US ZIP: 94103, 94103-1234
            #"\b\d{3}\s?\d{3}\b"#,                        // six digits: 560038, 560 038
            #"\b\d{4}\s*$"#,                              // four at the end: 2000, 1012
        ]
        let ns = address as NSString
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
                  let m = re.matches(in: address, range: NSRange(location: 0, length: ns.length)).last
            else { continue }
            return ns.substring(with: m.range).trimmingCharacters(in: .whitespaces).uppercased()
        }
        return nil
    }

    /// Every saved detail the sentence asks for: the one vaultMatch finds
    /// first, then the others of its kind in the vault's order (a handle
    /// stays the platform's own).
    static func vaultMatches(_ text: String, fields: [VaultField]) -> [VaultField] {
        // The person's own name for a detail wins: "work email" is the work one.
        let named = labelMatches(text, fields: fields)
        if !named.isEmpty { return named }
        guard let first = vaultMatch(text, fields: fields) else { return [] }
        if first.kind == "social" || first.kind == "handle" { return [first] }
        // One chip per value: the same address saved twice shows once.
        var seen: Set<String> = [first.value.lowercased()]
        return [first] + fields.filter {
            $0.kind == first.kind && $0.id != first.id && seen.insert($0.value.lowercased()).inserted
        }
    }

    /// The word a qualifying label is followed by, per kind: "work" +
    /// "email", "home" + "address", "office" + "number".
    private static let kindWords: [String: String] = [
        "email": #"e-?mail|g-?mail|mail(?:\s*id)?"#,
        "phone": #"(?:phone\s+)?(?:number|no\.?|num)|phone|line"#,
        "address": #"address|addy"#,
        "link": #"link|url|website|site"#,
        "upi": #"upi(?:\s*id)?"#,
        "wallet": #"(?:wallet\s+)?(?:address|addy)"#,
        "handle": #"handle|username|id"#,
        "social": #"handle|username|id"#,
    ]
    /// A label that is just the kind's own name ("Email", "Phone number"):
    /// the plain kind, which the triggers already offer. "Mobile", "Work" or
    /// "Home" are not: they say which one.
    private static let kindNames: [String: String] = [
        "email": #"e-?mail(?:\s+(?:address|id))?|g-?mail|mail(?:\s*id)?"#,
        "phone": #"phone(?:\s+number)?|number|tel(?:ephone)?|contact(?:\s+number)?"#,
        "address": #"address"#,
        "link": #"link|url|website|site"#,
        "upi": #"upi(?:\s*id)?|vpa"#,
        "wallet": #"wallet(?:\s+address)?|address"#,
        "handle": #"handle|username"#,
        "social": #"handle|username"#,
    ]
    /// What a detail's own label may end on, or be followed by, and still
    /// name that detail: "passport number", "locker code", "car plate".
    private static let detailNouns = #"number|no\.?|num|id|code|pin|address|link|handle|account|acct|plate"#

    /// Saved details named by the person's own label for them, at the end of
    /// the sentence: "work email", "my office number is", "my passport number
    /// is", "locker code:", "car:". A label that only qualifies a kind (Home,
    /// Work, Office) needs the kind's word after it ("on my way home" is no
    /// address); a label of the person's own naming stands alone when it ends
    /// on a detail's noun ("locker code"), else takes one after it or a colon
    /// ("car number", "car:"; "my car is" is not the plate). Never someone
    /// else's ("your passport number", "the locker code"). Vault order.
    static func labelMatches(_ text: String, fields: [VaultField]) -> [VaultField] {
        let clause = lastClause(text)
        guard !clause.isEmpty, !asksSomeoneElse(text) else { return [] }
        let lead = #"(?:^|[\s,(])(?<!\b(?:your|ur|his|her|their|the|this|that|a|an|whose|which|what)\s)"#
        let ending = #"\s*(?:(?:is|are|=)\s*)?:?\s*$"#
        return fields.filter { f in
            let label = f.label.lowercased().trimmingCharacters(in: .whitespaces)
            guard label.count >= 2 else { return false }
            let words = NSRegularExpression.escapedPattern(for: label)
                .replacingOccurrences(of: #"\s+"#, with: #"\\s+"#, options: .regularExpression)
            let pattern: String
            if let kind = kindWords[f.kind] {
                // The kind's own name as the label ("Email") is the plain kind,
                // which the triggers above already offer.
                if let name = kindNames[f.kind],
                   label.range(of: "^(?:" + name + ")$", options: .regularExpression) != nil { return false }
                pattern = lead + words + #"\s+(?:"# + kind + ")" + ending
            } else if label.range(of: #"\b(?:"# + detailNouns + ")$", options: .regularExpression) != nil {
                pattern = lead + words + ending
            } else {
                pattern = lead + words + #"(?:\s+(?:"# + detailNouns + ")" + ending + #"|\s*:\s*$)"#
            }
            return clause.range(of: pattern, options: .regularExpression) != nil
        }
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

// MARK: - Measurements, in the other system as they are typed

extension Smart {

    /// A measurement the message ends on, in the other system (Arpit,
    /// 2026-10-03: "when i write lets 10 inch, i see in cm or meteres, diff
    /// strips with suggestions"): "10 inch" → 25.4 cm, 0.254 m; "5'11" →
    /// 180 cm, 1.8 m; "72°F" → 22.2°C; "1/2 cup" → 118 ml. Each result is a
    /// chip of its own, and a tap adds it in brackets after the measurement.
    /// Only names that can't be anything else after a number in a chat:
    /// "in", "m", "min", "c" or "f" without "°", and "4g" are other things.
    /// Smart.kt's twin; shared/units/strip-cases.json holds the cases.
    struct Conversions: Equatable {
        /// What the answer is about, as typed: "10 inch".
        var source: String
        /// What each chip says, best first: ["25.4 cm", "0.254 m"].
        var results: [String]
        /// What each chip puts in the message, when it is not its words (a
        /// carrier's link behind "UPS tracking").
        var inserts: [String]? = nil
        /// How each goes in; in brackets after what was typed when nil.
        var hows: [Insertion]? = nil

        func insert(_ i: Int) -> String { inserts.flatMap { i < $0.count ? $0[i] : nil } ?? results[i] }
        func how(_ i: Int) -> Insertion { hows.flatMap { i < $0.count ? $0[i] : nil } ?? .bracket }
    }

    /// How a tap on an answer goes into the message.
    enum Insertion: Equatable {
        /// " (25.4 cm)" after what was typed.
        case bracket
        /// " https://…" after what was typed, or what was copied, pasted.
        case after
        /// In place of what was typed: ";date" → the date, "4155550123" →
        /// "(415) 555-0123".
        case replace
    }

    /// Unit names a measurement in a chat can end on, and the unit each is.
    private static let stripNames: [String: String] = {
        var out: [String: String] = [:]
        func add(_ unit: String, _ names: [String]) { for n in names { out[n] = unit } }
        add("mm", ["mm", "millimeter", "millimeters", "millimetre", "millimetres"])
        add("cm", ["cm", "cms", "centimeter", "centimeters", "centimetre", "centimetres"])
        add("m", ["meter", "meters", "metre", "metres", "mtr", "mtrs"])
        add("km", ["km", "kms", "kilometer", "kilometers", "kilometre", "kilometres"])
        add("inch", ["inch", "inches"])
        add("foot", ["ft", "foot", "feet"])
        add("yard", ["yd", "yds", "yard", "yards"])
        add("mile", ["mile", "miles"])
        add("g", ["g", "gm", "gms", "gram", "grams"])
        add("kg", ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"])
        add("oz", ["oz", "ounce", "ounces"])
        add("lb", ["lb", "lbs", "pound", "pounds"])
        add("stone", ["stone", "stones"])
        add("°C", ["°c", "° c", "ºc", "deg c", "degree c", "degrees c", "celsius", "degrees celsius", "centigrade"])
        add("°F", ["°f", "° f", "ºf", "deg f", "degree f", "degrees f", "fahrenheit", "degrees fahrenheit"])
        add("ml", ["ml", "milliliter", "milliliters", "millilitre", "millilitres"])
        add("litre", ["litre", "litres", "liter", "liters", "ltr", "ltrs"])
        add("tsp", ["tsp", "teaspoon", "teaspoons"])
        add("tbsp", ["tbsp", "tablespoon", "tablespoons"])
        add("fl oz", ["fl oz", "fluid ounce", "fluid ounces"])
        add("cup", ["cup", "cups"])
        add("pint", ["pint", "pints"])
        add("quart", ["quart", "quarts"])
        add("gallon", ["gal", "gallon", "gallons"])
        add("km/h", ["km/h", "kmh", "kmph", "kph", "km per hour", "kilometers per hour", "kilometres per hour"])
        add("mph", ["mph", "miles per hour"])
        add("m/s", ["m/s", "meters per second", "metres per second"])
        add("knot", ["knot", "knots"])
        add("sq ft", ["sq ft", "sqft", "square feet", "square foot", "ft2"])
        add("sq m", ["sq m", "sqm", "square meter", "square meters", "square metre", "square metres", "m2"])
        add("acre", ["acre", "acres"])
        add("hectare", ["hectare", "hectares"])
        return out
    }()

    /// A number as typed: 10, 2.5, 1,500, 1/2, 1 1/2, ½, 1½, -5.
    private static let stripAmount = #"(-?\d+\s+\d+/\d+|\d+/\d+|-?\d*[½⅓⅔¼¾⅛]|-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|-?\.\d+)"#
    private static let stripMeasure: NSRegularExpression? = {
        let names = stripNames.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try? NSRegularExpression(pattern: #"(?<![\p{L}\d.,/])"# + stripAmount + #"\s*(?:degrees?\s+)?("# + names + #")\.?\s?$"#,
                                        options: [.caseInsensitive])
    }()
    /// A height: 5'11, 5'11", 5 ft 11 in, 5 feet 11 inches, 5ft11.
    private static let stripHeight = try? NSRegularExpression(pattern:
        #"(?<![\p{L}\d.])([1-8])\s*(?:'|′|ft|feet|foot)\s*(\d{1,2}(?:\.\d+)?)\s*(?:"|″|''|in|inch|inches)?\.?\s?$"#,
        options: [.caseInsensitive])

    private static let fractions: [Character: Double] = ["½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75, "⅛": 0.125]

    private static func amount(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let last = t.last, let part = fractions[last] {
            let whole = String(t.dropLast())
            if whole.isEmpty { return part }
            if whole == "-" { return -part }
            guard let w = Double(whole) else { return nil }
            return w < 0 ? w - part : w + part
        }
        let pieces = t.split(separator: " ").map(String.init)
        if pieces.count == 2, let w = Double(pieces[0]), let f = amount(pieces[1]) { return w < 0 ? w - f : w + f }
        if t.contains("/") {
            let ab = t.split(separator: "/").compactMap { Double($0) }
            guard ab.count == 2, ab[1] != 0 else { return nil }
            return ab[0] / ab[1]
        }
        return Double(t.replacingOccurrences(of: ",", with: ""))
    }

    /// Sizes in metres, kilograms, litres, metres a second and square metres;
    /// in Britain pints, gallons and fluid ounces are imperial ones.
    private static func stripSize(_ unit: String, uk: Bool) -> Double? {
        switch unit {
        case "mm": return 0.001
        case "cm": return 0.01
        case "m": return 1
        case "km": return 1000
        case "inch": return 0.0254
        case "foot": return 0.3048
        case "yard": return 0.9144
        case "mile": return 1609.344
        case "g": return 0.001
        case "kg": return 1
        case "oz": return 0.028349523125
        case "lb": return 0.45359237
        case "stone": return 6.35029318
        case "ml": return 0.001
        case "litre", "L": return 1
        case "tsp": return 0.00492892159375
        case "tbsp": return 0.01478676478125
        case "fl oz": return uk ? 0.0284130625 : 0.0295735295625
        case "cup": return 0.2365882365
        case "pint": return uk ? 0.56826125 : 0.473176473
        case "quart": return uk ? 1.1365225 : 0.946352946
        case "gallon": return uk ? 4.54609 : 3.785411784
        case "km/h": return 1 / 3.6
        case "mph": return 0.44704
        case "m/s": return 1
        case "knot": return 1852.0 / 3600
        case "sq ft": return 0.09290304
        case "sq m": return 1
        case "acre": return 4046.8564224
        case "hectare": return 10000
        default: return nil
        }
    }

    /// How a result is written: "25.4 cm", "3.11 miles", "22.2°C".
    private static func stripNamed(_ n: Double, _ unit: String) -> String {
        let text = stripNumber(n)
        switch unit {
        case "°C", "°F": return text + unit
        case "inch": return "\(text) in"
        case "foot": return "\(text) ft"
        case "yard": return "\(text) yd"
        case "mile": return "\(text) \(abs(n) == 1 ? "mile" : "miles")"
        case "litre": return "\(text) L"
        case "cup": return "\(text) \(abs(n) == 1 ? "cup" : "cups")"
        case "pint": return "\(text) \(abs(n) == 1 ? "pint" : "pints")"
        case "gallon": return "\(text) gal"
        case "acre": return "\(text) \(abs(n) == 1 ? "acre" : "acres")"
        case "hectare": return "\(text) \(abs(n) == 1 ? "hectare" : "hectares")"
        default: return "\(text) \(unit)"
        }
    }

    /// Three figures, whole numbers from 100: 25.4, 3.94, 0.254, 180, 1,609.
    static func stripNumber(_ n: Double) -> String {
        let size = abs(n)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 0
        f.roundingMode = .halfUp
        if size >= 1 || size == 0 {
            f.maximumFractionDigits = size >= 100 ? 0 : size >= 10 ? 1 : 2
        } else {
            f.usesSignificantDigits = true
            f.maximumSignificantDigits = 3
        }
        let text = f.string(from: NSNumber(value: n)) ?? String(n)
        return text == "-0" ? "0" : text
    }

    /// Feet and inches, for a height: "5 ft 11 in".
    private static func feetInches(metres: Double) -> String {
        var feet = Int((metres / 0.3048).rounded(.down))
        var inches = Int(((metres / 0.3048 - Double(feet)) * 12).rounded(.toNearestOrAwayFromZero))
        if inches == 12 { feet += 1; inches = 0 }
        return inches > 0 ? "\(feet) ft \(inches) in" : "\(feet) ft"
    }

    static func conversions(in text: String, region: String? = Locale.current.region?.identifier) -> Conversions? {
        let t = text.replacingOccurrences(of: "’", with: "'")
        // "½" is a number too, if not a digit.
        guard t.range(of: #"[\d½⅓⅔¼¾⅛]"#, options: .regularExpression) != nil else { return nil }
        let ns = t as NSString
        let all = NSRange(location: 0, length: ns.length)
        let uk = region?.uppercased() == "GB"
        let us = region?.uppercased() == "US"
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        func source(_ m: NSTextCheckingResult) -> String {
            ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
        }
        // A range or a size ("5-10 km", "10x20 cm") would be half answered.
        func partOfMore(_ m: NSTextCheckingResult) -> Bool {
            let before = ns.substring(to: m.range.location)
            return before.range(of: #"\d\s*(?:-|–|to|x|×|by)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }

        if let m = stripHeight?.firstMatch(in: t, range: all), !partOfMore(m),
           let feet = group(m, 1).flatMap(Double.init), let inches = group(m, 2).flatMap(Double.init), inches < 12 {
            let metres = feet * 0.3048 + inches * 0.0254
            return Conversions(source: source(m), results: [stripNamed(metres * 100, "cm"), stripNamed(metres, "m")])
        }
        // "it's 30 degrees": on the phone's own scale, shown on the other one.
        if let g = firstMatch(#"\b(?:it'?s|it\s+is|feels\s+like|high\s+of|low\s+of|temp(?:erature)?\s+(?:is\s+|of\s+)?|was|hitting|around|about)\s+(-?\d{1,3}(?:\.\d+)?)\s*(?:°|degrees?|deg)\.?\s?$"#, in: t),
           let n = g[1].flatMap(Double.init) {
            let fahrenheit = ["US", "BS", "BZ", "KY", "PR", "PW"].contains(region?.uppercased() ?? "")
            let result = fahrenheit ? stripNamed((n - 32) * 5 / 9, "°C") : stripNamed(n * 9 / 5 + 32, "°F")
            return Conversions(source: (g[0] ?? "").trimmingCharacters(in: .whitespaces), results: [result])
        }
        guard let m = stripMeasure?.firstMatch(in: t, range: all), !partOfMore(m),
              let typed = group(m, 1), let n = amount(typed), n.isFinite,
              let name = group(m, 2)?.lowercased(), let unit = stripNames[name] else { return nil }
        // "4g", "5g": a network, not grams. "10 pounds" is money outside the US.
        if unit == "g", name == "g", ns.substring(with: m.range).range(of: #"^[2-6]g"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        if name.hasPrefix("pound"), !us { return nil }
        if n < 0, unit != "°C", unit != "°F" { return nil }

        var results: [String] = []
        switch unit {
        case "°C": results = [stripNamed(n * 9 / 5 + 32, "°F")]
        case "°F": results = [stripNamed((n - 32) * 5 / 9, "°C")]
        default:
            guard let size = stripSize(unit, uk: uk), n > 0 else { return nil }
            let base = n * size
            func to(_ u: String) -> String { stripNamed(base / (stripSize(u, uk: uk) ?? 1), u) }
            // Millilitres under a litre, grams under a kilo.
            func metricVolume() -> String { base < 1 ? to("ml") : to("litre") }
            func metricMass() -> String { base < 1 ? to("g") : to("kg") }
            switch unit {
            case "mm": results = [to("inch")]
            case "cm": results = base >= 0.3 && base < 3 ? [feetInches(metres: base), to("inch")] : [to("inch")]
            case "m": results = base < 3 ? [feetInches(metres: base), to("foot")] : [to("foot"), to("yard")]
            case "km": results = [to("mile")]
            case "inch": results = [to("cm"), to("m")]
            case "foot": results = n < 10 ? [to("m"), to("cm")] : [to("m")]
            case "yard": results = [to("m")]
            case "mile": results = [to("km")]
            case "g": results = [to("oz")]
            case "kg": results = [to("lb")]
            case "oz": results = [metricMass()]
            case "lb": results = [to("kg")]
            case "stone": results = [to("kg"), to("lb")]
            case "ml": results = [to("fl oz")]
            case "litre": results = uk ? [to("pint"), to("gallon")] : [to("gallon"), to("fl oz")]
            case "tsp", "tbsp", "fl oz", "cup", "pint": results = [metricVolume()]
            case "quart", "gallon": results = [to("litre")]
            case "km/h": results = [to("mph")]
            case "mph": results = [to("km/h")]
            case "m/s", "knot": results = [to("km/h"), to("mph")]
            case "sq ft": results = [to("sq m")]
            case "sq m": results = [to("sq ft")]
            case "acre": results = [to("hectare")]
            case "hectare": results = [to("acre")]
            default: return nil
            }
        }
        return results.isEmpty ? nil : Conversions(source: source(m), results: results)
    }

    /// What a tap on a result adds after the measurement: " (25.4 cm)", or
    /// "(25.4 cm) " after a space already typed.
    static func conversionInsert(_ result: String, before: String?) -> String {
        let last = before?.last
        return last == nil || last == " " || last == "\n" ? "(\(result)) " : " (\(result))"
    }
}

// MARK: - A time in someone else's zone, in yours

extension Smart {

    /// Zones people write after a time, with the place each means. EST, CST
    /// and IST say more than one place; the one most people mean wins, and
    /// the phone's region picks the other (China's CST, Ireland's and
    /// Israel's IST). ET/PT and the like follow summer time, as people mean
    /// them, and so do EST and PST.
    private static let zoneNames: [String: String] = [
        "et": "America/New_York", "est": "America/New_York", "edt": "America/New_York", "eastern": "America/New_York",
        "ct": "America/Chicago", "cst": "America/Chicago", "cdt": "America/Chicago", "central": "America/Chicago",
        "mt": "America/Denver", "mst": "America/Denver", "mdt": "America/Denver", "mountain": "America/Denver",
        "pt": "America/Los_Angeles", "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pacific": "America/Los_Angeles",
        "akst": "America/Anchorage", "akdt": "America/Anchorage", "hst": "Pacific/Honolulu",
        "gmt": "GMT", "utc": "GMT", "bst": "Europe/London", "uk time": "Europe/London", "london time": "Europe/London",
        "cet": "Europe/Paris", "cest": "Europe/Paris", "eet": "Europe/Athens", "eest": "Europe/Athens",
        "msk": "Europe/Moscow", "ist": "Asia/Kolkata", "india time": "Asia/Kolkata", "pkt": "Asia/Karachi",
        "gst": "Asia/Dubai", "dubai time": "Asia/Dubai", "ict": "Asia/Bangkok", "wib": "Asia/Jakarta",
        "sgt": "Asia/Singapore", "hkt": "Asia/Hong_Kong", "pht": "Asia/Manila", "jst": "Asia/Tokyo",
        "kst": "Asia/Seoul", "aest": "Australia/Sydney", "aedt": "Australia/Sydney", "awst": "Australia/Perth",
        "nzst": "Pacific/Auckland", "nzdt": "Pacific/Auckland", "sast": "Africa/Johannesburg",
        "wat": "Africa/Lagos", "eat": "Africa/Nairobi", "brt": "America/Sao_Paulo",
        "ny time": "America/New_York", "new york time": "America/New_York", "la time": "America/Los_Angeles",
        "tokyo time": "Asia/Tokyo", "singapore time": "Asia/Singapore", "sydney time": "Australia/Sydney",
        // Cities, as Raycast takes them ("5pm london"); none that is also a
        // word ("reading", "nice", "bath", "split").
        "london": "Europe/London",
        "paris": "Europe/Paris",
        "berlin": "Europe/Berlin",
        "madrid": "Europe/Madrid",
        "rome": "Europe/Rome",
        "amsterdam": "Europe/Amsterdam",
        "brussels": "Europe/Brussels",
        "vienna": "Europe/Vienna",
        "zurich": "Europe/Zurich",
        "stockholm": "Europe/Stockholm",
        "dublin": "Europe/Dublin",
        "lisbon": "Europe/Lisbon",
        "athens": "Europe/Athens",
        "istanbul": "Europe/Istanbul",
        "moscow": "Europe/Moscow",
        "dubai": "Asia/Dubai",
        "abu dhabi": "Asia/Dubai",
        "riyadh": "Asia/Riyadh",
        "doha": "Asia/Qatar",
        "karachi": "Asia/Karachi",
        "lahore": "Asia/Karachi",
        "mumbai": "Asia/Kolkata",
        "delhi": "Asia/Kolkata",
        "new delhi": "Asia/Kolkata",
        "bangalore": "Asia/Kolkata",
        "bengaluru": "Asia/Kolkata",
        "chennai": "Asia/Kolkata",
        "hyderabad": "Asia/Kolkata",
        "kolkata": "Asia/Kolkata",
        "dhaka": "Asia/Dhaka",
        "colombo": "Asia/Colombo",
        "bangkok": "Asia/Bangkok",
        "jakarta": "Asia/Jakarta",
        "singapore": "Asia/Singapore",
        "kuala lumpur": "Asia/Kuala_Lumpur",
        "manila": "Asia/Manila",
        "hong kong": "Asia/Hong_Kong",
        "shanghai": "Asia/Shanghai",
        "beijing": "Asia/Shanghai",
        "taipei": "Asia/Taipei",
        "seoul": "Asia/Seoul",
        "tokyo": "Asia/Tokyo",
        "sydney": "Australia/Sydney",
        "melbourne": "Australia/Melbourne",
        "brisbane": "Australia/Brisbane",
        "perth": "Australia/Perth",
        "auckland": "Pacific/Auckland",
        "honolulu": "Pacific/Honolulu",
        "los angeles": "America/Los_Angeles",
        "la": "America/Los_Angeles",
        "san francisco": "America/Los_Angeles",
        "sf": "America/Los_Angeles",
        "seattle": "America/Los_Angeles",
        "vancouver": "America/Vancouver",
        "denver": "America/Denver",
        "phoenix": "America/Phoenix",
        "chicago": "America/Chicago",
        "dallas": "America/Chicago",
        "houston": "America/Chicago",
        "austin": "America/Chicago",
        "toronto": "America/Toronto",
        "montreal": "America/Toronto",
        "new york": "America/New_York",
        "nyc": "America/New_York",
        "boston": "America/New_York",
        "miami": "America/New_York",
        "atlanta": "America/New_York",
        "washington": "America/New_York",
        "mexico city": "America/Mexico_City",
        "sao paulo": "America/Sao_Paulo",
        "são paulo": "America/Sao_Paulo",
        "buenos aires": "America/Argentina/Buenos_Aires",
        "lagos": "Africa/Lagos",
        "nairobi": "Africa/Nairobi",
        "cairo": "Africa/Cairo",
        "johannesburg": "Africa/Johannesburg",
        "cape town": "Africa/Johannesburg",
        "tel aviv": "Asia/Jerusalem",
    ]

    /// How a zone is named in the result: the letters people know, or the
    /// offset ("GMT+6") for a zone without them.
    private static let zoneLetters: [String: (String, String)] = [
        "America/New_York": ("EST", "EDT"), "America/Toronto": ("EST", "EDT"), "America/Chicago": ("CST", "CDT"),
        "America/Mexico_City": ("CST", "CST"), "America/Denver": ("MST", "MDT"), "America/Phoenix": ("MST", "MST"),
        "America/Los_Angeles": ("PST", "PDT"), "America/Vancouver": ("PST", "PDT"), "America/Anchorage": ("AKST", "AKDT"),
        "Pacific/Honolulu": ("HST", "HST"), "Europe/London": ("GMT", "BST"), "GMT": ("GMT", "GMT"), "UTC": ("UTC", "UTC"),
        "Europe/Paris": ("CET", "CEST"), "Europe/Berlin": ("CET", "CEST"), "Europe/Madrid": ("CET", "CEST"),
        "Europe/Rome": ("CET", "CEST"), "Europe/Amsterdam": ("CET", "CEST"), "Europe/Brussels": ("CET", "CEST"),
        "Europe/Vienna": ("CET", "CEST"), "Europe/Stockholm": ("CET", "CEST"), "Europe/Zurich": ("CET", "CEST"),
        "Europe/Warsaw": ("CET", "CEST"), "Europe/Athens": ("EET", "EEST"), "Europe/Helsinki": ("EET", "EEST"),
        "Europe/Moscow": ("MSK", "MSK"), "Asia/Dubai": ("GST", "GST"), "Asia/Karachi": ("PKT", "PKT"),
        "Asia/Kolkata": ("IST", "IST"), "Asia/Calcutta": ("IST", "IST"), "Asia/Bangkok": ("ICT", "ICT"),
        "Asia/Jakarta": ("WIB", "WIB"), "Asia/Singapore": ("SGT", "SGT"), "Asia/Hong_Kong": ("HKT", "HKT"),
        "Asia/Manila": ("PHT", "PHT"), "Asia/Tokyo": ("JST", "JST"), "Asia/Seoul": ("KST", "KST"),
        "Australia/Sydney": ("AEST", "AEDT"), "Australia/Melbourne": ("AEST", "AEDT"), "Australia/Perth": ("AWST", "AWST"),
        "Pacific/Auckland": ("NZST", "NZDT"), "Africa/Johannesburg": ("SAST", "SAST"), "Africa/Lagos": ("WAT", "WAT"),
        "Africa/Nairobi": ("EAT", "EAT"), "America/Sao_Paulo": ("BRT", "BRT"),
    ]

    private static func zoneLabel(_ zone: TimeZone, at date: Date) -> String {
        if let pair = zoneLetters[zone.identifier] {
            return zone.isDaylightSavingTime(for: date) ? pair.1 : pair.0
        }
        let seconds = zone.secondsFromGMT(for: date)
        let h = abs(seconds) / 3600, m = abs(seconds) % 3600 / 60
        return "GMT" + (seconds < 0 ? "-" : "+") + "\(h)" + (m > 0 ? String(format: ":%02d", m) : "")
    }

    private static let zoneTime: NSRegularExpression? = {
        let names = zoneNames.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try? NSRegularExpression(pattern:
            #"(?<![\d:.])(\d{1,2})(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)?\s*\(?(?:in\s+)?("# + names + #")\)?\.?\s?$"#,
            options: [.caseInsensitive])
    }()

    /// A time in someone else's zone the message ends on, in the phone's own
    /// (Raycast's "5pm PT in London", in the strip): "call at 3pm EST" →
    /// "Sun 12:30 AM IST" in India. A time needs am/pm or minutes ("3 est"
    /// is not one); nothing when the zone is the phone's own. The day shows
    /// when it is not the same day there. Smart.kt's twin;
    /// shared/zones/strip-cases.json.
    static func zoneTimes(in text: String, now: Date = Date(), here: TimeZone = .current,
                          region: String? = Locale.current.region?.identifier) -> Conversions? {
        guard let re = zoneTime, text.range(of: #"\d"#, options: .regularExpression) != nil else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        guard var hour = group(1).flatMap({ Int($0) }), let name = group(4)?.lowercased() else { return nil }
        let minute = group(2).flatMap { Int($0) } ?? 0
        let half = group(3)?.lowercased().replacingOccurrences(of: ".", with: "")
        if let half {
            guard (1...12).contains(hour) else { return nil }
            if half == "pm", hour < 12 { hour += 12 }
            if half == "am", hour == 12 { hour = 0 }
        } else {
            // "3 est" is not a time; "15:00 GMT" and "9:30 IST" are.
            guard group(2) != nil, (0...23).contains(hour) else { return nil }
        }
        // A two-letter zone in small letters only after am/pm ("9am pt"):
        // "9:30 pt" may be a part or a point.
        if name.count == 2, half == nil, group(4) != group(4)?.uppercased() { return nil }
        let r = region?.uppercased()
        var id = zoneNames[name] ?? ""
        if name == "cst", r == "CN" { id = "Asia/Shanghai" }
        if name == "ist", r == "IE" { id = "Europe/Dublin" }
        if name == "ist", r == "IL" { id = "Asia/Jerusalem" }
        guard let there = TimeZone(identifier: id) else { return nil }

        // That time today, where it was said.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = there
        var day = cal.dateComponents([.year, .month, .day], from: now)
        day.hour = hour
        day.minute = minute
        guard let when = cal.date(from: day) else { return nil }
        if there.secondsFromGMT(for: when) == here.secondsFromGMT(for: when) { return nil }

        var mine = Calendar(identifier: .gregorian)
        mine.timeZone = here
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        f.dateFormat = mine.component(.minute, from: when) == 0 ? "h a" : "h:mm a"
        var clock = f.string(from: when).replacingOccurrences(of: "\u{202F}", with: " ")
        let sameDay = mine.component(.day, from: when) == cal.component(.day, from: when)
        if !sameDay {
            f.dateFormat = "EEE"
            clock = f.string(from: when) + " " + clock
        }
        let result = "\(clock) \(zoneLabel(here, at: when))"
        return Conversions(source: ns.substring(with: m.range).trimmingCharacters(in: .whitespaces), results: [result])
    }
}

// MARK: - Bills, arrivals and dates, worked out as they are typed

extension Smart {

    /// Everything the strip works out on the phone from how the message
    /// ends (Arpit, 2026-10-03: "finding more things we can do faster with
    /// regex like we did math email etc ... raycast and apple's default
    /// spotlight search has a lot of things too lets try"), in the order
    /// tried: a measurement, a time in another zone, a bill (split, tip,
    /// discount, tax), when someone will be there, how long a span of
    /// minutes is, and a date in words. One chip per result; a tap adds it
    /// in brackets. Smart.kt's twin; shared/quick/strip-cases.json.
    static func quickAnswer(in text: String, now: Date = Date(), here: TimeZone = .current,
                            region: String? = Locale.current.region?.identifier) -> Conversions? {
        guard text.count <= 400 else { return nil }
        let tries: [() -> Conversions?] = [
            { shortcut(in: text, now: now, here: here, region: region) },
            { conversions(in: text, region: region) },
            { zoneTimes(in: text, now: now, here: here, region: region) },
            { billMath(in: text) },
            { arrival(in: text, now: now, here: here) },
            { dateInWords(in: text, now: now, here: here, region: region) },
            { bases(in: text) },
            { colours(in: text) },
            { tracking(in: text) },
            { flight(in: text) },
            { phone(in: text, region: region) },
            { unixTime(in: text, here: here, region: region) },
            { bigNumber(in: text, region: region) },
        ]
        for attempt in tries { if let answer = attempt() { return answer } }
        return nil
    }

    /// Patterns are built once: the strip asks on every key.
    private static let patternCache = NSCache<NSString, NSRegularExpression>()

    static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        let re: NSRegularExpression
        if let cached = patternCache.object(forKey: pattern as NSString) {
            re = cached
        } else {
            guard let made = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            patternCache.setObject(made, forKey: pattern as NSString)
            re = made
        }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }

    // MARK: Bills

    private static let sym = #"([$€£₹¥])?"#
    private static let amt = #"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"#
    private static let pct = #"(\d+(?:\.\d+)?)\s*%"#
    private static let end = #"[.?!]?\s?$"#

    /// Money as it is written back: the sign typed, cents only when there
    /// are some ("$30", "$33.33"), none for yen.
    static func billMoney(_ n: Double, _ symbol: String) -> String {
        let cents = (n * 100).rounded() / 100
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.roundingMode = .halfUp
        let whole = symbol == "¥" || cents == cents.rounded()
        f.minimumFractionDigits = whole ? 0 : 2
        f.maximumFractionDigits = whole ? 0 : 2
        return symbol + (f.string(from: NSNumber(value: cents)) ?? String(cents))
    }

    private static func number(_ s: String?) -> Double? { s.flatMap { Double($0.replacingOccurrences(of: ",", with: "")) } }

    /// "split 120 4 ways" → $30 each; "15% tip on 80" → $12 tip, $92 total;
    /// "20% off 80" → $64, save $16; "$80 + 8.875% tax" → $87.10 total,
    /// $7.10 tax. Each needs its word (split, tip, off, tax), so "50% sure"
    /// and "24/7" stay what they are.
    static func billMath(in text: String) -> Conversions? {
        let ways = #"\s*(?:ways?|people|persons|of us|friends)?"#
        let splits = [
            #"\bsplit\s+(?:the\s+)?(?:bill\s+(?:of\s+)?)?"# + sym + #"\s*"# + amt + #"\s+(?:in\s+|into\s+|between\s+|among\s+|by\s+|with\s+)?(\d{1,2})"# + ways + end,
            sym + #"\s*"# + amt + #"\s+(?:split|divided)\s+(?:in\s+|into\s+|between\s+|among\s+|by\s+)?(\d{1,2})"# + ways + end,
            sym + #"\s*"# + amt + #"\s+(?:between|among)\s+(\d{1,2})\s+(?:people|persons|of us|friends)"# + end,
        ]
        for p in splits {
            guard let g = firstMatch(p, in: text), let bill = number(g[2]), let n = number(g[3]), n >= 2, n <= 50 else { continue }
            let s = g[1] ?? ""
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces), results: ["\(billMoney(bill / n, s)) each"])
        }
        // (percent, sign, amount) or (sign, amount, percent)
        func pick(_ g: [String?], percentFirst: Bool) -> (Double, String, Double)? {
            let p = number(percentFirst ? g[1] : g[3]), s = (percentFirst ? g[2] : g[1]) ?? "", a = number(percentFirst ? g[3] : g[2])
            guard let p, let a, p > 0, p <= 100 else { return nil }
            return (p, s, a)
        }
        let tips: [(String, Bool)] = [
            (#"\b"# + pct + #"\s*tip\s*(?:on|for|of)?\s*"# + sym + #"\s*"# + amt + end, true),
            (#"\btip\s+(?:of\s+)?"# + pct + #"\s*(?:on|for)\s*"# + sym + #"\s*"# + amt + end, true),
            (sym + #"\s*"# + amt + #"\s*(?:\+|plus|with|and)\s*"# + pct + #"\s*tip"# + end, false),
        ]
        for (p, first) in tips {
            guard let g = firstMatch(p, in: text), let r = pick(g, percentFirst: first) else { continue }
            let (percent, s, bill) = r
            let tip = bill * percent / 100
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces),
                               results: ["\(billMoney(tip, s)) tip", "\(billMoney(bill + tip, s)) total"])
        }
        let offs: [(String, Bool)] = [
            (#"\b"# + pct + #"\s*off\s*(?:of\s+)?"# + sym + #"\s*"# + amt + end, true),
            (sym + #"\s*"# + amt + #"\s*(?:with\s+|at\s+|less\s+|minus\s+|-\s*)?"# + pct + #"\s*off"# + end, false),
        ]
        for (p, first) in offs {
            guard let g = firstMatch(p, in: text), let r = pick(g, percentFirst: first) else { continue }
            let (percent, s, price) = r
            let saved = price * percent / 100
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces),
                               results: [billMoney(price - saved, s), "save \(billMoney(saved, s))"])
        }
        let taxes: [(String, Bool)] = [
            (sym + #"\s*"# + amt + #"\s*(?:\+|plus|with|and)\s*"# + pct + #"\s*(?:sales\s+)?(?:tax|gst|vat)"# + end, false),
            (#"\b"# + pct + #"\s*(?:sales\s+)?(?:tax|gst|vat)\s*(?:on|for|of)\s*"# + sym + #"\s*"# + amt + end, true),
        ]
        for (p, first) in taxes {
            guard let g = firstMatch(p, in: text), let r = pick(g, percentFirst: first) else { continue }
            let (percent, s, price) = r
            let tax = price * percent / 100
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces),
                               results: ["\(billMoney(price + tax, s)) total", "\(billMoney(tax, s)) tax"])
        }
        return nil
    }

    // MARK: Arrivals and spans

    private static func clock(_ date: Date, from now: Date, here: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        f.dateFormat = cal.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        var text = f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
        if !cal.isDate(date, inSameDayAs: now) {
            f.dateFormat = "EEE"
            text = f.string(from: date) + " " + text
        }
        return text
    }

    private static let smallNumbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty": 40, "forty five": 45, "fifty": 50, "half an": 0.5, "a couple of": 2, "couple of": 2,
    ]
    private static let countWord = #"(\d+(?:\.\d+)?|a couple of|couple of|half an|forty five|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty)"#

    /// "there in 20 mins" → the clock then (12:58 AM); "back in 2 hrs";
    /// "eta 45 min". Under ten minutes only when the words say someone is
    /// coming. "movie is 145 mins" → 2 h 25 min (from 90 minutes up).
    static func arrival(in text: String, now: Date, here: TimeZone) -> Conversions? {
        let unit = #"(mins?|minutes?|hrs?|hours?)"#
        let coming = #"\b(?:eta|back|there|home|ready|leav(?:e|ing)|land(?:s|ing)?|reach(?:ing)?|arriv(?:e|ing)|be\s+(?:there|back|home|ready|free|done)|see\s+(?:you|u)|done|free|out|wait)\b"#
        func minutes(_ count: String?, _ u: String?) -> Double? {
            guard let count, let u else { return nil }
            let n = Double(count) ?? smallNumbers[count.lowercased()]
            guard let n else { return nil }
            return u.lowercased().hasPrefix("h") ? n * 60 : n
        }
        if let g = firstMatch(#"\b(?:in|within|eta)\s*:?\s*(?:about\s+|around\s+|like\s+|~\s*)?"# + countWord + #"\s*"# + unit + end, in: text),
           let mins = minutes(g[1], g[2]), mins > 0, mins <= 12 * 60 {
            let said = text.range(of: coming, options: [.regularExpression, .caseInsensitive]) != nil
            guard mins >= 10 || said else { return nil }
            let when = now.addingTimeInterval(mins * 60)
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces), results: [clock(when, from: now, here: here)])
        }
        if let g = firstMatch(#"(?<![\d.])(\d{2,4})\s*(mins?|minutes?)"# + end, in: text),
           text.range(of: #"\b(?:in|within)\s+\d+\s*(?:mins?|minutes?)\.?\s?$"#, options: [.regularExpression, .caseInsensitive]) == nil,
           let n = number(g[1]), n >= 90, n < 24 * 60 {
            let h = Int(n) / 60, m = Int(n) % 60
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces), results: [m == 0 ? "\(h) h" : "\(h) h \(m) min"])
        }
        return nil
    }

    // MARK: Dates in words

    private static let weekdays: [(String, Int)] = [
        ("sunday", 1), ("sun", 1), ("monday", 2), ("mon", 2), ("tuesday", 3), ("tues", 3), ("tue", 3),
        ("wednesday", 4), ("wed", 4), ("thursday", 5), ("thurs", 5), ("thur", 5), ("thu", 5),
        ("friday", 6), ("fri", 6), ("saturday", 7), ("sat", 7),
    ]
    private static let months: [(String, Int)] = [
        ("january", 1), ("jan", 1), ("february", 2), ("feb", 2), ("march", 3), ("mar", 3), ("april", 4), ("apr", 4),
        ("may", 5), ("june", 6), ("jun", 6), ("july", 7), ("jul", 7), ("august", 8), ("aug", 8),
        ("september", 9), ("sept", 9), ("sep", 9), ("october", 10), ("oct", 10), ("november", 11), ("nov", 11),
        ("december", 12), ("dec", 12),
    ]

    /// A day as people write dates: "Fri 9 Oct", or "Fri, Oct 9" in the US;
    /// the year when it is not this one.
    private static func dayName(_ date: Date, now: Date, here: TimeZone, region: String?) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        let us = region?.uppercased() == "US"
        f.dateFormat = us ? "EEE, MMM d" : "EEE d MMM"
        var text = f.string(from: date)
        if cal.component(.year, from: date) != cal.component(.year, from: now) {
            f.dateFormat = "yyyy"
            text += (us ? ", " : " ") + f.string(from: date)
        }
        return text
    }

    /// "next friday" → Fri 9 Oct (and Fri 16 Oct when the coming Friday is
    /// still this week, as "next" can mean either); "this friday"; "in 3
    /// weeks" → Sat 24 Oct; "day after tomorrow"; "the 14th" → Wed 14 Oct;
    /// "oct 14" or "14 october" → Wed 14 Oct. Never a lone weekday, "today"
    /// or "tomorrow": those are said all day long.
    static func dateInWords(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        cal.firstWeekday = 2   // weeks start on Monday
        let today = cal.startOfDay(for: now)
        func say(_ g: [String?], _ dates: [Date]) -> Conversions {
            Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces),
                        results: dates.map { dayName($0, now: now, here: here, region: region) })
        }
        let dayNames = weekdays.map(\.0).joined(separator: "|")
        if let g = firstMatch(#"\b(next|this|coming)\s+("# + dayNames + #")"# + end, in: text),
           let which = g[1]?.lowercased(), let name = g[2]?.lowercased(),
           let target = weekdays.first(where: { $0.0 == name })?.1 {
            let todayDay = cal.component(.weekday, from: today)
            var ahead = (target - todayDay + 7) % 7
            if which == "next", ahead == 0 { ahead = 7 }
            guard let coming = cal.date(byAdding: .day, value: ahead, to: today) else { return nil }
            if which == "next", cal.isDate(coming, equalTo: today, toGranularity: .weekOfYear),
               let after = cal.date(byAdding: .day, value: 7, to: coming) {
                return say(g, [coming, after])
            }
            return say(g, [coming])
        }
        if let g = firstMatch(#"\bin\s+"# + countWord + #"\s*(days?|weeks?|wks?|months?)"# + end, in: text),
           let count = g[1], let u = g[2]?.lowercased() {
            let n = Int(Double(count) ?? smallNumbers[count.lowercased()] ?? 0)
            let (component, most): (Calendar.Component, Int) = u.hasPrefix("d") ? (.day, 365) : u.hasPrefix("w") ? (.day, 52) : (.month, 24)
            guard n >= 1, n <= most,
                  let date = cal.date(byAdding: component, value: u.hasPrefix("w") ? n * 7 : n, to: today) else { return nil }
            return say(g, [date])
        }
        if let g = firstMatch(#"\bday\s+after\s+tomorrow"# + end, in: text),
           let date = cal.date(byAdding: .day, value: 2, to: today) {
            return say(g, [date])
        }
        // "the 14th", "on the 3rd", "by the 21st": the next such day.
        if let g = firstMatch(#"\b(?:(?:on|by|till|until|before|after|from)\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)"# + end, in: text),
           let d = g[1].flatMap({ Int($0) }), d >= 1, d <= 31 {
            for add in 0..<3 {
                guard let month = cal.date(byAdding: .month, value: add, to: today) else { continue }
                var c = cal.dateComponents([.year, .month], from: month)
                c.day = d
                if let date = cal.date(from: c), cal.component(.day, from: date) == d, date >= today {
                    return say(g, [date])
                }
            }
            return nil
        }
        // "oct 14", "october 14th", "14 oct", "14th of october": that day's weekday.
        let monthNames = months.map(\.0).joined(separator: "|")
        let monthFirst = firstMatch(#"\b("# + monthNames + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?"# + end, in: text)
        let dayFirst = monthFirst == nil ? firstMatch(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?("# + monthNames + #")"# + end, in: text) : nil
        if let g = monthFirst ?? dayFirst {
            let (mName, dText) = monthFirst != nil ? (g[1], g[2]) : (g[2], g[1])
            guard let m = months.first(where: { $0.0 == mName?.lowercased() })?.1, let d = dText.flatMap({ Int($0) }),
                  d >= 1, d <= 31 else { return nil }
            // "may 5" could be "you may 5…": May only with a word before it that dates.
            if m == 5, monthFirst != nil, text.range(of: #"\b(?:on|by|till|until|before|after|from|since|in)\s+may\s+\d"#, options: [.regularExpression, .caseInsensitive]) == nil { return nil }
            var c = cal.dateComponents([.year], from: today)
            c.month = m
            c.day = d
            guard var date = cal.date(from: c), cal.component(.day, from: date) == d else { return nil }
            if date < today, let next = cal.date(byAdding: .year, value: 1, to: date) { date = next }
            return say(g, [date])
        }
        return nil
    }
}

// MARK: - Shortcuts, numbers, colours, parcels, flights and phones

extension Smart {

    private static func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespaces) }

    // MARK: Shortcuts

    /// The shortcuts the keyboard knows itself; the person's own shorthand
    /// of the same name wins (the keyboard leaves the chip out then).
    static let builtInShortcuts: Set<String> = [";date", ";today", ";time", ";now", ";tmrw", ";tomorrow", ";yday", ";yesterday", ";iso"]

    /// ";date" → Sat 3 Oct 2026, ";time" → 1:15 AM, ";now", ";tmrw",
    /// ";yday", ";iso" (Raycast's {date} placeholders): typed in place of
    /// the shortcut.
    static func shortcut(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        guard let g = firstMatch(#"(?:^|\s)(;(?:date|today|time|now|tmrw|tomorrow|yday|yesterday|iso))\s?$"#, in: text),
              let token = g[1]?.lowercased() else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        let us = region?.uppercased() == "US"
        func day(_ d: Date, year: Bool) -> String {
            f.dateFormat = us ? (year ? "EEE, MMM d, yyyy" : "EEE, MMM d") : (year ? "EEE d MMM yyyy" : "EEE d MMM")
            return f.string(from: d)
        }
        func time(_ d: Date) -> String {
            f.dateFormat = "h:mm a"
            return f.string(from: d).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        let out: String
        switch token {
        case ";date", ";today": out = day(now, year: true)
        case ";time": out = time(now)
        case ";now": out = day(now, year: false) + ", " + time(now)
        case ";tmrw", ";tomorrow": out = day(cal.date(byAdding: .day, value: 1, to: now) ?? now, year: false)
        case ";yday", ";yesterday": out = day(cal.date(byAdding: .day, value: -1, to: now) ?? now, year: false)
        default:
            f.dateFormat = "yyyy-MM-dd"
            out = f.string(from: now)
        }
        return Conversions(source: token, results: [out], hows: [.replace])
    }

    // MARK: Number bases and Roman numerals

    static func roman(_ n: Int) -> String? {
        guard n >= 1, n <= 3999 else { return nil }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, out = ""
        for (value, letters) in table { while n >= value { out += letters; n -= value } }
        return out
    }

    /// "0xFF" → 255 · 0b11111111; "0b1010" → 10 · 0xA; "255 in hex" →
    /// 0xFF; "10 in binary" → 0b1010; "1010 in decimal" or "binary 1010" →
    /// 10; "hex ff" → 255; "2026 in roman" → MMXXVI (Arpit: "binary to
    /// decimal things maybe too").
    static func bases(in text: String) -> Conversions? {
        func binary(_ n: UInt64) -> String? { n < (1 << 32) ? "0b" + String(n, radix: 2) : nil }
        func hex(_ n: UInt64) -> String { "0x" + String(n, radix: 16).uppercased() }
        if let g = firstMatch(#"(?<![\w])0x([0-9a-f]{1,15})"# + end, in: text), let n = UInt64(g[1] ?? "", radix: 16) {
            return Conversions(source: trimmed(g[0]), results: [String(n)] + [binary(n)].compactMap { $0 })
        }
        if let g = firstMatch(#"(?<![\w])0b([01]{1,63})"# + end, in: text), let n = UInt64(g[1] ?? "", radix: 2) {
            return Conversions(source: trimmed(g[0]), results: [String(n), hex(n)])
        }
        if let g = firstMatch(#"\b(\d{1,18})\s+(?:in|to|as|into)\s+(hex|hexadecimal|binary|bin|octal|oct|roman|roman numerals?)"# + end, in: text),
           let n = UInt64(g[1] ?? "") {
            let to = (g[2] ?? "").lowercased()
            let out: String?
            if to.hasPrefix("hex") { out = hex(n) }
            else if to.hasPrefix("bin") { out = binary(n) }
            else if to.hasPrefix("oct") { out = "0o" + String(n, radix: 8) }
            else { out = roman(Int(clamping: n)) }
            guard let out else { return nil }
            return Conversions(source: trimmed(g[0]), results: [out])
        }
        if let g = firstMatch(#"\b([01]{2,63})\s+(?:in|to|as|into)\s+(?:decimal|dec|denary|base 10)"# + end, in: text)
            ?? firstMatch(#"\bbinary\s+([01]{2,63})"# + end, in: text),
           let n = UInt64(g[1] ?? "", radix: 2) {
            return Conversions(source: trimmed(g[0]), results: [String(n)])
        }
        if let g = firstMatch(#"\bhex\s+([0-9a-f]{1,15})"# + end, in: text), let n = UInt64(g[1] ?? "", radix: 16) {
            return Conversions(source: trimmed(g[0]), results: [String(n)])
        }
        return nil
    }

    // MARK: Colours

    private static func hsl(_ r: Double, _ g: Double, _ b: Double) -> String {
        let r = r / 255, g = g / 255, b = b / 255
        let most = max(r, g, b), least = min(r, g, b)
        let l = (most + least) / 2
        var h = 0.0, s = 0.0
        if most != least {
            let d = most - least
            s = l > 0.5 ? d / (2 - most - least) : d / (most + least)
            if most == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if most == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
        }
        func round(_ x: Double) -> Int { Int(x.rounded(.toNearestOrAwayFromZero)) }
        return "hsl(\(round(h) % 360), \(round(s * 100))%, \(round(l * 100))%)"
    }

    /// "#ff6363" → rgb(255, 99, 99) · hsl(0, 100%, 69%); "rgb(255, 99, 99)"
    /// → #FF6363 · hsl(0, 100%, 69%). A hashtag that is a word (#bad,
    /// #cafe, #decade) is not a colour: a hex with no digit needs a word
    /// about colour in the message.
    static func colours(in text: String) -> Conversions? {
        if let g = firstMatch(#"(?<![\w&#])#([0-9a-f]{6}|[0-9a-f]{3}|[0-9a-f]{8})"# + end, in: text), var hex = g[1] {
            let colourWords = text.range(of: #"\b(?:colou?rs?|hex|shade|bg|background|fill|stroke|tint|hue)\b"#,
                                         options: [.regularExpression, .caseInsensitive]) != nil
            guard hex.range(of: #"\d"#, options: .regularExpression) != nil || colourWords else { return nil }
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let v = UInt64(String(hex.prefix(6)), radix: 16) else { return nil }
            let r = Double((v >> 16) & 0xFF), gg = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
            return Conversions(source: trimmed(g[0]), results: ["rgb(\(Int(r)), \(Int(gg)), \(Int(b)))", hsl(r, gg, b)])
        }
        if let g = firstMatch(#"\brgba?\(\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*(?:[,/]\s*[\d.]+%?\s*)?\)"# + end, in: text),
           let r = Int(g[1] ?? ""), let gg = Int(g[2] ?? ""), let b = Int(g[3] ?? ""), r <= 255, gg <= 255, b <= 255 {
            let hex = String(format: "#%02X%02X%02X", r, gg, b)
            return Conversions(source: trimmed(g[0]), results: [hex, hsl(Double(r), Double(gg), Double(b))])
        }
        return nil
    }

    // MARK: Parcels

    /// UPS's check digit: the 15 characters after 1Z, letters as
    /// (code − 63) mod 10, odd places once and even places twice.
    static func upsValid(_ n: String) -> Bool {
        let s = Array(n.uppercased())
        guard s.count == 18, s[0] == "1", s[1] == "Z" else { return false }
        var sum = 0
        for (i, c) in s[2..<17].enumerated() {
            guard let v = c.isNumber ? c.wholeNumberValue : c.asciiValue.map({ (Int($0) - 63) % 10 }) else { return false }
            sum += i % 2 == 0 ? v : v * 2
        }
        return (10 - sum % 10) % 10 == s[17].wholeNumberValue
    }

    /// The postal format every country shares (RA123456785IN): its check
    /// digit, weights 8 6 4 2 3 5 9 7.
    static func s10Valid(_ n: String) -> Bool {
        let s = Array(n.uppercased())
        guard s.count == 13 else { return false }
        let digits = s[2..<11].compactMap(\.wholeNumberValue)
        guard digits.count == 9 else { return false }
        let weights = [8, 6, 4, 2, 3, 5, 9, 7]
        let sum = zip(digits.prefix(8), weights).map(*).reduce(0, +)
        var check = 11 - sum % 11
        if check == 10 { check = 0 } else if check == 11 { check = 5 }
        return check == digits[8]
    }

    /// A tracking number the message ends on, with its carrier's own page:
    /// UPS (1Z…, check digit), the postal format (check digit; Royal Mail,
    /// USPS, Canada Post and Australia Post have pages a number can open),
    /// and, with the carrier named in the message, USPS (20–22 digits from
    /// 9), FedEx (12 or 15 digits) and DHL (10 digits). The chip names the
    /// carrier; a tap adds the link.
    static func tracking(in text: String) -> Conversions? {
        func link(_ label: String, _ url: String, _ g: [String?]) -> Conversions {
            Conversions(source: trimmed(g[0]), results: [label], inserts: [url], hows: [.after])
        }
        if let g = firstMatch(#"\b(1Z[0-9A-Z]{16})"# + end, in: text), let n = g[1]?.uppercased(), upsValid(n) {
            return link("UPS tracking", "https://www.ups.com/track?tracknum=\(n)", g)
        }
        if let g = firstMatch(#"\b([A-Z]{2}\d{9}[A-Z]{2})"# + end, in: text), let n = g[1]?.uppercased(), s10Valid(n) {
            switch String(n.suffix(2)) {
            case "GB": return link("Royal Mail tracking", "https://www.royalmail.com/track-your-item#/tracking-results/\(n)", g)
            case "US": return link("USPS tracking", "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(n)", g)
            case "CA": return link("Canada Post tracking", "https://www.canadapost-postescanada.ca/track-reperage/en#/search?searchFor=\(n)", g)
            case "AU": return link("Australia Post tracking", "https://auspost.com.au/mypost/track/#/details/\(n)", g)
            default: return nil
            }
        }
        let says = { (word: String) in text.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive]) != nil }
        if let g = firstMatch(#"(?<![\d])(9[2-5](?:\s?\d){18,20})"# + end, in: text), says("usps") {
            let n = (g[1] ?? "").filter(\.isNumber)
            return link("USPS tracking", "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(n)", g)
        }
        if let g = firstMatch(#"(?<![\d])(\d{12}|\d{15})"# + end, in: text), says("fedex") {
            return link("FedEx tracking", "https://www.fedex.com/fedextrack/?trknbr=\(g[1] ?? "")", g)
        }
        if let g = firstMatch(#"(?<![\d])(\d{10})"# + end, in: text), says("dhl") {
            return link("DHL tracking", "https://www.dhl.com/global-en/home/tracking/tracking-express.html?submit=1&tracking-id=\(g[1] ?? "")", g)
        }
        return nil
    }

    // MARK: Flights

    private static let airlines: [String: String] = [
        "AA": "American", "UA": "United", "DL": "Delta", "WN": "Southwest", "B6": "JetBlue", "AS": "Alaska",
        "NK": "Spirit", "F9": "Frontier", "HA": "Hawaiian", "AC": "Air Canada", "WS": "WestJet", "AM": "Aeroméxico",
        "BA": "British Airways", "VS": "Virgin Atlantic", "EI": "Aer Lingus", "LH": "Lufthansa", "AF": "Air France",
        "KL": "KLM", "LX": "Swiss", "OS": "Austrian", "SN": "Brussels Airlines", "IB": "Iberia", "VY": "Vueling",
        "TP": "TAP", "AY": "Finnair", "SK": "SAS", "DY": "Norwegian", "FR": "Ryanair", "U2": "easyJet", "W6": "Wizz Air",
        "LO": "LOT", "A3": "Aegean", "TK": "Turkish Airlines", "EK": "Emirates", "QR": "Qatar Airways", "EY": "Etihad",
        "FZ": "flydubai", "G9": "Air Arabia", "SV": "Saudia", "GF": "Gulf Air", "WY": "Oman Air", "KU": "Kuwait Airways",
        "LY": "El Al", "MS": "EgyptAir", "ET": "Ethiopian", "KQ": "Kenya Airways", "SA": "South African",
        "AI": "Air India", "6E": "IndiGo", "IX": "Air India Express", "SG": "SpiceJet", "QP": "Akasa Air",
        "UL": "SriLankan", "PK": "PIA", "BG": "Biman", "SQ": "Singapore Airlines", "TR": "Scoot", "CX": "Cathay Pacific",
        "MH": "Malaysia Airlines", "AK": "AirAsia", "TG": "Thai", "VN": "Vietnam Airlines", "GA": "Garuda",
        "PR": "Philippine Airlines", "5J": "Cebu Pacific", "JL": "JAL", "NH": "ANA", "KE": "Korean Air", "OZ": "Asiana",
        "CA": "Air China", "MU": "China Eastern", "CZ": "China Southern", "BR": "EVA Air", "CI": "China Airlines",
        "QF": "Qantas", "VA": "Virgin Australia", "JQ": "Jetstar", "NZ": "Air New Zealand", "LA": "LATAM",
        "AV": "Avianca", "CM": "Copa", "AR": "Aerolíneas Argentinas", "G3": "Gol", "AD": "Azul",
    ]

    /// A flight number the message ends on, with its status page: "flight
    /// AI 101", "landing on UA 123", "boarding BA287". Codes look like a lot
    /// of things ("AI 2027", "PS5", "OS 18"), so the message has to say
    /// something about flying, or the code is in capitals after "on" or
    /// "taking".
    static func flight(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\b([A-Za-z0-9]{2})\s?(\d{1,4})"# + end, in: text),
              let typed = g[1], let digits = g[2], let name = airlines[typed.uppercased()],
              typed.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else { return nil }
        let flying = text.range(of: #"\b(?:flight|flights|flying|fly|flies|flew|landing|lands|landed|departs|departing|departure|arrives|arriving|arrival|boarding|board|gate|terminal|airport|layover|connecting|plane)\b"#,
                                options: [.regularExpression, .caseInsensitive]) != nil
        let onIt = typed == typed.uppercased() &&
            text.range(of: #"\b(?:on|taking|catching|booked)\s+[A-Z0-9]{2}\s?\d{1,4}[.?!]?\s?$"#, options: .regularExpression) != nil
        guard flying || onIt, let number = Int(digits), number > 0 else { return nil }
        let code = typed.uppercased()
        return Conversions(source: trimmed(g[0]), results: ["\(name) \(number) status"],
                           inserts: ["https://www.flightaware.com/live/flight/\(code)\(number)"], hows: [.after])
    }

    // MARK: Phone numbers

    /// A phone number the message ends on, written out properly, and its
    /// WhatsApp link: "call me on 4155550123" → (415) 555-0123 ·
    /// WhatsApp (https://wa.me/14155550123). A string of digits counts only with
    /// a "+" or a word that says it is a number (call, phone, number,
    /// whatsapp, text me, mobile, cell, contact): codes and order numbers
    /// are digits too.
    static func phone(in text: String, region: String?) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w+])(\+?)(\(?\d[\d\s().-]{8,16}\d)"# + end, in: text) else { return nil }
        let plus = g[1] == "+"
        let digits = (g[2] ?? "").filter(\.isNumber)
        let said = text.range(of: #"\b(?:call|calling|phone|ph|tel|number|no|num|whatsapp|wa|text\s+me|msg\s+me|mobile|mob|cell|contact|reach\s+me|ring)\b"#,
                              options: [.regularExpression, .caseInsensitive]) != nil
        guard plus || said else { return nil }
        let r = region?.uppercased() ?? ""
        var cc = "", national = ""
        if plus {
            if digits.hasPrefix("1"), digits.count == 11 { cc = "1"; national = String(digits.dropFirst()) }
            else if digits.hasPrefix("91"), digits.count == 12 { cc = "91"; national = String(digits.dropFirst(2)) }
            else if digits.hasPrefix("44"), digits.count == 12 { cc = "44"; national = String(digits.dropFirst(2)) }
            else if digits.count >= 8, digits.count <= 15 {
                return Conversions(source: trimmed(g[0]), results: ["WhatsApp"],
                                   inserts: ["https://wa.me/\(digits)"], hows: [.after])
            } else { return nil }
        } else if ["US", "CA"].contains(r), digits.count == 10 || (digits.count == 11 && digits.hasPrefix("1")) {
            cc = "1"; national = String(digits.suffix(10))
        } else if r == "IN", digits.count == 10 || (digits.count == 11 && digits.hasPrefix("0")) {
            cc = "91"; national = String(digits.suffix(10))
        } else if r == "GB", digits.count == 11, digits.hasPrefix("0") {
            cc = "44"; national = String(digits.dropFirst())
        } else { return nil }
        let n = Array(national)
        func part(_ a: Int, _ b: Int) -> String { String(n[a..<b]) }
        var local = "", world = ""
        switch cc {
        case "1":
            guard n.count == 10, n[0] != "0", n[0] != "1", n[3] != "0", n[3] != "1" else { return nil }
            local = "(\(part(0, 3))) \(part(3, 6))-\(part(6, 10))"
            world = "+1 \(part(0, 3))-\(part(3, 6))-\(part(6, 10))"
        case "91":
            guard n.count == 10, "6789".contains(n[0]) else { return nil }
            local = "\(part(0, 5)) \(part(5, 10))"
            world = "+91 \(local)"
        default:
            guard n.count == 10, n[0] == "7" else { return nil }
            local = "0\(part(0, 4)) \(part(4, 10))"
            world = "+44 \(part(0, 4)) \(part(4, 10))"
        }
        // Two chips fit the strip: the number as it is written where it was
        // typed (with its country when a "+" was), and WhatsApp.
        let written = plus ? world : local
        return Conversions(source: trimmed(g[0]), results: [written, "WhatsApp"],
                           inserts: [written, "https://wa.me/\(cc)\(national)"], hows: [.replace, .after])
    }

    // MARK: Unix and ISO times

    /// A Unix time (seconds or milliseconds, 2001 to 2036) or an ISO 8601
    /// time, as a date where the phone is: "1733823083" → Tue 10 Dec 2024,
    /// 3:01 PM IST. A bare number counts when it is the whole message or the
    /// message says it is a time (timestamp, epoch, unix, ts).
    static func unixTime(in text: String, here: TimeZone, region: String?) -> Conversions? {
        func say(_ date: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US")
            f.timeZone = here
            f.dateFormat = region?.uppercased() == "US" ? "EEE, MMM d, yyyy, h:mm a" : "EEE d MMM yyyy, h:mm a"
            return f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ") + " " + zoneLabel(here, at: date)
        }
        if let g = firstMatch(#"\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2}))"# + end, in: text),
           let iso = g[1] {
            let f = ISO8601DateFormatter()
            f.formatOptions = iso.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            guard let date = f.date(from: iso) else { return nil }
            return Conversions(source: iso, results: [say(date)])
        }
        guard let g = firstMatch(#"(?<![\d.])(\d{10}|\d{13})"# + end, in: text), let digits = g[1], var n = Double(digits) else { return nil }
        if digits.count == 13 { n /= 1000 }
        guard n >= 1_000_000_000, n <= 2_100_000_000 else { return nil }
        let alone = text.trimmingCharacters(in: .whitespacesAndNewlines) == digits
        let said = text.range(of: #"\b(?:timestamp|epoch|unix|ts|time)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard alone || said else { return nil }
        return Conversions(source: digits, results: [say(Date(timeIntervalSince1970: n))])
    }

    // MARK: Big and short numbers

    /// A number in words or short, written out, and back: "$2.4m" →
    /// $2,400,000 · $2.4 million; "3 crore" → 3,00,00,000 · 30 million in
    /// India; "1500000" → 1,500,000 · 1.5 million (15,00,000 · 15 lakh in
    /// India). k, m and bn only beside money ("10k run", "4k video" are
    /// not); plain digits from seven to nine.
    static func bigNumber(in text: String, region: String?) -> Conversions? {
        let india = region?.uppercased() == "IN"
        var value: Double, symbol = "", source: String
        let scale: [String: Double] = ["k": 1e3, "thousand": 1e3, "m": 1e6, "mn": 1e6, "mm": 1e6, "mil": 1e6, "million": 1e6,
                                       "b": 1e9, "bn": 1e9, "billion": 1e9, "lakh": 1e5, "lakhs": 1e5, "lac": 1e5, "lacs": 1e5,
                                       "crore": 1e7, "crores": 1e7, "cr": 1e7]
        if let g = firstMatch(#"([$€£₹¥])\s?(\d+(?:\.\d+)?)\s?(k|m|mn|mm|b|bn|thousand|million|mil|billion|lakhs?|lacs?|crores?|cr)\b"# + end, in: text)
            ?? firstMatch(#"()(?<![\d.,])(\d+(?:\.\d+)?)\s?(thousand|million|billion|lakhs?|lacs?|crores?)\b"# + end, in: text),
           let n = Double(g[2] ?? ""), let s = scale[(g[3] ?? "").lowercased()] {
            value = n * s
            symbol = g[1] ?? ""
            source = trimmed(g[0])
        } else if let g = firstMatch(#"(?<![\d.,+])(\d{7,9})"# + end, in: text), let n = Double(g[1] ?? "") {
            value = n
            source = trimmed(g[0])
        } else { return nil }
        guard value >= 1000, value < 1e15 else { return nil }
        func short(_ n: Double) -> String {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_US")
            f.maximumFractionDigits = 2
            f.roundingMode = .halfUp
            return f.string(from: NSNumber(value: n)) ?? String(n)
        }
        func grouped(_ n: Double) -> String {
            let whole = String(format: "%.0f", n.rounded())
            guard india, whole.count > 3 else {
                let f = NumberFormatter()
                f.numberStyle = .decimal
                f.locale = Locale(identifier: "en_US")
                f.maximumFractionDigits = 0
                return f.string(from: NSNumber(value: n.rounded())) ?? whole
            }
            // 1,23,45,678: the last three, then twos.
            var head = String(whole.dropLast(3)), groups: [String] = []
            while head.count > 2 { groups.insert(String(head.suffix(2)), at: 0); head = String(head.dropLast(2)) }
            if !head.isEmpty { groups.insert(head, at: 0) }
            return groups.joined(separator: ",") + "," + whole.suffix(3)
        }
        func words(indian: Bool) -> String? {
            if indian {
                if value >= 1e7 { return "\(short(value / 1e7)) crore" }
                if value >= 1e5 { return "\(short(value / 1e5)) lakh" }
                return nil
            }
            // "10 thousand" says nothing "10,000" doesn't.
            if value >= 1e9 { return "\(short(value / 1e9)) billion" }
            if value >= 1e6 { return "\(short(value / 1e6)) million" }
            return nil
        }
        // Two chips fit the strip: written out, then in words (lakh and
        // crore in India).
        var results = [symbol + grouped(value)]
        let spoken = [words(indian: india), india ? words(indian: false) : nil].compactMap { $0 }.map { symbol + $0 }
        if let w = spoken.first(where: { $0.lowercased() != source.lowercased() }) { results.append(w) }
        // What was typed is not offered back.
        results = results.filter { $0.lowercased() != source.lowercased() }
        guard !results.isEmpty else { return nil }
        return Conversions(source: source, results: Array(results.prefix(3)), hows: Array(repeating: .replace, count: min(3, results.count)))
    }

    // MARK: Copied text, in its parts

    /// What a copy holds that is worth pasting alone (Gboard's paste
    /// chips): the emails, links and phone numbers in it, in order, when
    /// the copy is more than just one of them. The whole copy comes first.
    static func pieces(of copy: String) -> [String]? {
        let t = copy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 8, t.count <= 2000 else { return nil }
        let patterns = [
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"\bhttps?://[^\s<>"]+|\bwww\.[^\s<>"]+"#,
            #"(?<![\w+])\+?\(?\d[\d\s().-]{8,16}\d(?![\w])"#,
        ]
        var found: [(NSRange, String)] = []
        let ns = t as NSString
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                var s = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: " .,;:)!?'\""))
                if p.contains("\\d[") {
                    // A phone has ten digits or more; dates and sums have fewer.
                    guard s.filter(\.isNumber).count >= 10 else { continue }
                    s = s.trimmingCharacters(in: .whitespaces)
                }
                if !found.contains(where: { $0.1 == s || NSIntersectionRange($0.0, m.range).length > 0 }) { found.append((m.range, s)) }
            }
        }
        let parts = found.sorted { $0.0.location < $1.0.location }.map(\.1)
        guard !parts.isEmpty, !(parts.count == 1 && parts[0] == t) else { return nil }
        return Array(parts.prefix(2))
    }
}

// MARK: - Styled text (the g menu's Style)

extension Smart {

    /// The g menu's Style (Arpit, 2026-10-03: "option to stylise text in
    /// glyf menu like bold italic underline, cut, etc"): letters from
    /// Unicode's styled alphabets, which show in any app because they are
    /// characters, not formatting (chats have no bold of their own). Screen
    /// readers read some letter by letter, so Plain puts text back.
    /// Smart.kt's twin; shared/style/cases.json.
    enum TextStyle: String, CaseIterable {
        case bold, italic, boldItalic, underline, strike, serifBold, script, doubleStruck, monospace,
             bubble, smallCaps, wide, upsideDown, plain

        var title: String {
            switch self {
            case .bold: return "Bold"
            case .italic: return "Italic"
            case .boldItalic: return "Bold italic"
            case .underline: return "Underline"
            case .strike: return "Strikethrough"
            case .serifBold: return "Serif bold"
            case .script: return "Script"
            case .doubleStruck: return "Double-struck"
            case .monospace: return "Monospace"
            case .bubble: return "Bubble"
            case .smallCaps: return "Small caps"
            case .wide: return "Wide"
            case .upsideDown: return "Upside down"
            case .plain: return "Plain"
            }
        }

        /// Where A, a and 0 start in Unicode's styled alphabets.
        fileprivate var starts: (upper: UInt32, lower: UInt32, digit: UInt32?)? {
            switch self {
            case .bold: return (0x1D5D4, 0x1D5EE, 0x1D7EC)
            case .italic: return (0x1D608, 0x1D622, nil)
            case .boldItalic: return (0x1D63C, 0x1D656, 0x1D7EC)
            case .serifBold: return (0x1D400, 0x1D41A, 0x1D7CE)
            case .script: return (0x1D4D0, 0x1D4EA, nil)
            case .doubleStruck: return (0x1D538, 0x1D552, 0x1D7D8)
            case .monospace: return (0x1D670, 0x1D68A, 0x1D7F6)
            default: return nil
            }
        }
    }

    /// Double-struck capitals Unicode had already: ℂ ℍ ℕ ℙ ℚ ℝ ℤ.
    private static let doubleStruckHoles: [Character: String] = [
        "C": "\u{2102}", "H": "\u{210D}", "N": "\u{2115}", "P": "\u{2119}", "Q": "\u{211A}", "R": "\u{211D}", "Z": "\u{2124}",
    ]
    private static let smallCapsLetters: [Character: String] = [
        "a": "ᴀ", "b": "ʙ", "c": "ᴄ", "d": "ᴅ", "e": "ᴇ", "f": "ꜰ", "g": "ɢ", "h": "ʜ", "i": "ɪ", "j": "ᴊ", "k": "ᴋ",
        "l": "ʟ", "m": "ᴍ", "n": "ɴ", "o": "ᴏ", "p": "ᴘ", "q": "ǫ", "r": "ʀ", "s": "ꜱ", "t": "ᴛ", "u": "ᴜ", "v": "ᴠ",
        "w": "ᴡ", "x": "x", "y": "ʏ", "z": "ᴢ",
    ]
    private static let flipped: [Character: String] = [
        "a": "ɐ", "b": "q", "c": "ɔ", "d": "p", "e": "ǝ", "f": "ɟ", "g": "ƃ", "h": "ɥ", "i": "ı", "j": "ɾ", "k": "ʞ",
        "l": "ן", "m": "ɯ", "n": "u", "o": "o", "p": "d", "q": "b", "r": "ɹ", "s": "s", "t": "ʇ", "u": "n", "v": "ʌ",
        "w": "ʍ", "x": "x", "y": "ʎ", "z": "z",
        "A": "∀", "B": "ꓭ", "C": "Ɔ", "D": "ᗡ", "E": "Ǝ", "F": "Ⅎ", "G": "⅁", "H": "H", "I": "I", "J": "ſ", "K": "ꓘ",
        "L": "˥", "M": "W", "N": "N", "O": "O", "P": "Ԁ", "Q": "Ό", "R": "ꓤ", "S": "S", "T": "⊥", "U": "∩", "V": "Λ",
        "W": "M", "X": "X", "Y": "⅄", "Z": "Z",
        "1": "Ɩ", "2": "ᄅ", "3": "Ɛ", "4": "ㄣ", "5": "ϛ", "6": "9", "7": "ㄥ", "8": "8", "9": "6", "0": "0",
        ".": "˙", ",": "'", "'": ",", "?": "¿", "!": "¡", "(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{",
        "<": ">", ">": "<", "&": "⅋", "_": "‾",
    ]
    private static func scalar(_ v: UInt32) -> String { Unicode.Scalar(v).map { String(Character($0)) } ?? "" }

    /// Text in a style. It starts from plain letters, so styles don't pile
    /// up; what has no styled form (punctuation, emoji) stays as it is.
    static func styled(_ text: String, _ style: TextStyle) -> String {
        let base = plainText(text)
        switch style {
        case .plain:
            return base
        case .underline, .strike:
            let mark = style == .underline ? "\u{0332}" : "\u{0336}"
            return base.map { $0 == "\n" ? "\n" : String($0) + mark }.joined()
        case .bubble:
            return base.map { c -> String in
                guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return String(c) }
                switch v {
                case 0x41...0x5A: return scalar(0x24B6 + v - 0x41)
                case 0x61...0x7A: return scalar(0x24D0 + v - 0x61)
                case 0x31...0x39: return scalar(0x2460 + v - 0x31)
                case 0x30: return "\u{24EA}"
                default: return String(c)
                }
            }.joined()
        case .smallCaps:
            return base.map { smallCapsLetters[$0] ?? String($0) }.joined()
        case .wide:
            return base.map { c -> String in
                guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return String(c) }
                if v == 0x20 { return "\u{3000}" }
                return (0x21...0x7E).contains(v) ? scalar(v + 0xFEE0) : String(c)
            }.joined()
        case .upsideDown:
            return base.reversed().map { flipped[$0] ?? String($0) }.joined()
        default:
            guard let s = style.starts else { return base }
            return base.map { c -> String in
                guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return String(c) }
                switch v {
                case 0x41...0x5A:
                    if style == .doubleStruck, let hole = doubleStruckHoles[c] { return hole }
                    return scalar(s.upper + v - 0x41)
                case 0x61...0x7A: return scalar(s.lower + v - 0x61)
                case 0x30...0x39: return s.digit.map { scalar($0 + v - 0x30) } ?? String(c)
                default: return String(c)
                }
            }.joined()
        }
    }

    /// The double-struck capitals' code points, the only letterlike symbols
    /// Plain turns back (™ and ℃ stay as they are).
    private static let holeScalars: Set<UInt32> = [0x2102, 0x210D, 0x2115, 0x2119, 0x211A, 0x211D, 0x2124]

    /// Styled text back to plain letters: underlines and strikes off, the
    /// styled alphabets, circles and wide letters back to their own, small
    /// capitals to small letters. Upside-down text stays as it is: its
    /// letters are ordinary letters of other alphabets ("ı" is Turkish).
    static func plainText(_ text: String) -> String {
        var out = ""
        for c in text {
            let scalars = c.unicodeScalars.filter { $0.value != 0x0332 && $0.value != 0x0336 }
            guard let first = scalars.first else { continue }
            let v = first.value
            let styledLetter = (0x1D400...0x1D7FF).contains(v) || holeScalars.contains(v)
                || (0x2460...0x24FF).contains(v) || (0xFF01...0xFF5E).contains(v) || v == 0x3000
            if styledLetter {
                let s = String(String.UnicodeScalarView(scalars))
                out += s.precomposedStringWithCompatibilityMapping
            } else if let small = smallCapsLetters.first(where: { $0.value == String(c) && $0.key != "x" })?.key {
                out.append(small)
            } else {
                out += String(String.UnicodeScalarView(scalars))
            }
        }
        return out
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
