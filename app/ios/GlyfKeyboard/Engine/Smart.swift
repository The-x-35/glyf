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
        /// see both, and i should also see a temp mail option"). `typed` is
        /// the start of a detail already typed ("ar", "123 Mar"): a part's
        /// tap puts the whole detail in its place (Smart.completions).
        case details(fields: [VaultField], temp: Bool, typed: String = "")
        /// A measurement the message ends on, in the other system: one part
        /// for each result ("10 inch" → 25.4 cm, 0.254 m), and a tap on a
        /// part adds it in brackets (Smart.conversions).
        case convert(Conversions)
        /// A trade said in words ("swap 0.05 eth to usdc on base", "sell my
        /// eth if it drops below 3000", "request 20 usdt"): a tap opens the
        /// trade panel over the keys (TradeSurface), nothing typed.
        case trade(TradeIntent)
        /// A Whitechain request's pay link on screen or just copied ("Pay me
        /// 20 USDT: https://www.tryglyf.com/pay?chain=1874&contract=…&id=…"):
        /// a tap opens it in the app, which reads it from the chain and pays.
        case payLink(path: String)
        /// A trade just shared from the app (Share in chat): its line and
        /// link, which a tap types into the chat (TradeShare in the app).
        case shareTrade(text: String)

        /// The parts of a chip drawn as a row of chips: the saved details (and
        /// Temp), or a measurement's results.
        var choices: (values: [String], temp: Bool)? {
            switch self {
            case .details(let fields, let temp, _): return (fields.map(\.shown), temp)
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
            case .details(let fields, _, _): return fields.first?.title ?? "Email"
            case .trade(let t): return t.venue
            case .payLink: return "Whitechain"
            case .shareTrade: return "Share trade"
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
            case .trade(let t):
                switch t.kind {
                case .swap: return t.amountIsUSD || t.buyAmount != nil ? "Buy" : "Swap"
                case .send: return "Send"
                case .request: return "Request"
                case .bridge: return "Move"
                default: return "Set"
                }
            case .payLink: return "Pay"
            case .shareTrade: return "Insert"
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
            case .trade(let t): return t.venue
            case .payLink: return "Whitechain"
            case .shareTrade: return "Share trade"
            default: return nil
            }
        }
        var value: String {
            switch self {
            // The whole sum where it fits: "2+5 = 7" reads as an answer, "7" alone
            // was easy to miss (user, 2026-09-29: "show result in recommendation strip").
            case .calc(let v, _, let expression):
                return expression.isEmpty || expression.count > 22 ? "= \(v)" : "\(expression) = \(v)"
            case .vault(let f): return f.shown
            case .paste(let t): return t.replacingOccurrences(of: "\n", with: " ")
            case .action(let label, _, _): return label
            case .money(let shown, _, _): return shown
            // A plan that clashes says so, before the tap adds it (2026-10-14).
            case .event(let plan): return EventParse.summary(plan) + (EventParse.busyNote?(plan).map { " · \($0)" } ?? "")
            case .booking(let link): return "A time on \(Smart.shortLink(link))"
            case .pay(let address, let amount, let token, _):
                let short = Smart.shortAddress(address)
                return amount.map { "\($0) \(token ?? "USDC") to \(short)" } ?? short
            case .buy(let mint, _, let price, _):
                return price ?? Smart.shortAddress(mint)
            case .tempMail(_, let from, let code):
                return code.map { "\($0) · \(from)" } ?? "Mail from \(from)"
            case .tempAddress(let live): return live ?? "Temp email"
            case .details(let fields, let temp, _):
                return (fields.map(\.shown) + (temp ? ["Temp mail"] : [])).joined(separator: " · ")
            case .convert(let c):
                return c.source.isEmpty ? c.results.joined(separator: " · ") : "\(c.source) = " + c.results.joined(separator: " · ")
            case .trade(let t): return t.title + " · " + t.chainLabel
            case .payLink: return "A USDT request"
            case .shareTrade(let text): return text
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
            case .trade: return ""     // opens the trade panel instead of typing
            case .payLink: return ""   // opens the request in the app
            case .shareTrade(let text): return text
            }
        }
    }

    /// The app path for a GlyfPayRequest link in the text (its https or
    /// glyf:// form), the last one if there are several.
    static func payRequestPath(in text: String) -> String? {
        let pattern = #"(?:https?://(?:www\.)?tryglyf\.com/pay|glyf://pay-request)\?((?:chain=\d+&)?contract=0x[0-9a-fA-F]{40}&id=\d+)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return "pay-request?" + text[r]
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

    /// The message asks for a time to talk, which the booking page answers.
    static func asksToBook(_ text: String) -> Bool {
        firstMatch(#"\b(?:calendar link|booking link|scheduling link|calendly(?:\s+link)?|cal\.com(?:\s+link)?|book (?:a |some )?(?:time|slot|call|meeting|session)|pick a (?:time|slot)|grab (?:a |some )?time|schedule (?:a |some )?(?:time|call|meeting|chat)|find a time|set up a (?:call|meeting|time)|when (?:are|r) (?:you|u) free|(?:are|r) (?:you|u) free (?:this|next) week|your availability|my availability|what times? works? for you|a time that works)\b[?.!]?\s?$"#, in: text) != nil
    }

    /// The message is about getting on a call, which a Meet link answers
    /// ("hop on a quick call?", "can we talk", "send me the meet link").
    static func asksToCall(_ text: String) -> Bool {
        firstMatch(#"\b(?:(?:hop|jump|get) on a (?:quick |video )?call|quick call|video call|can we (?:talk|call|chat|hop on)|(?:lets|let's) (?:call|talk|hop on|jump on|do a call)|wanna call|want to call|free (?:to talk|for a call)|up for a call|call now|meet link|(?:send|share) (?:me )?(?:a|the|your) (?:meet|call|video) link|(?:zoom|meet|facetime|call)\?)[?.!]?\s?$"#, in: text) != nil
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
    /// for, then something freshly copied. `linkContext` is more of the
    /// message than `text`, for a link too long for the strip's view of it.
    static func chip(for text: String, fields: [VaultField], paste: String? = nil,
                     field: FieldHint = .none, rates: RatesSnapshot = .empty,
                     ownWallet: String? = nil, indianGrouping: Bool = true,
                     region: String? = Locale.current.region?.identifier,
                     linkContext: String? = nil,
                     ownBooking: String? = SettingsStore.current.bookingLink) -> Chip? {
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
        // Someone's request link, in the chat or just copied: pay it.
        if let link = payRequestPath(in: text) ?? (text.isEmpty ? paste.flatMap(payRequestPath) : nil) {
            return .payLink(path: link)
        }
        // A trade said in words: swaps, orders, sends to a name, requests.
        if let t = TradeIntent.parse(text) { return .trade(t) }
        // A link longer than the strip's view of the message: its trackers.
        if let context = linkContext, context.count > text.count, endsInLink(text), let c = cleanLink(in: context) {
            return .convert(c)
        }
        let quick = quickAnswer(in: text, region: region)
        if let c = calc(text, indianGrouping: indianGrouping) {
            // "scored 43/50" is a score, not a division: the answer that read
            // more of the message wins.
            if let q = quick, q.source.count > c.expression.count + 2, q.source.hasSuffix(c.expression) { return .convert(q) }
            return .calc(value: c.value, hasEquals: c.hasEquals, expression: c.expression)
        }
        if let m = money(in: text, rates: rates) {
            // "18% gst on ₹1,000", "3 for $10": the bill says more than the
            // amount it ends on.
            if let q = quick, q.source.count > moneyTailLength(text) { return .convert(q) }
            return m
        }
        // A cashtag waits for its price: "$sol" is SOL's price, never your
        // Solana wallet, even before the price has come.
        if cashtag(in: text) != nil { return nil }
        // "remind me to pay rent on the 1st": the reminder, before the date.
        if text.range(of: #"^\s*(?:pls\s+|please\s+)?(?:remind\s+me|reminder)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
           let plan = EventParse.looksLikePlan(text, dayFirst: EventParse.regionDayFirst) {
            return .event(plan: plan)
        }
        if let c = quick { return .convert(c) }
        let matches = vaultMatches(text, fields: fields)
        if matches.count > 1 { return .details(fields: Array(matches.prefix(3)), temp: false) }
        if let f = matches.first { return .vault(field: f) }
        // A detail being typed: its first letters offer the whole of it.
        if let c = completions(text, fields: fields) {
            return .details(fields: c.fields, temp: false, typed: c.typed)
        }
        // "Best," on a line of its own: sign with the saved name.
        if let sign = signOff(in: text, fields: fields) { return .convert(sign) }
        // Asked for a time to talk ("when are you free", "send me your
        // calendar link"): the person's own booking page, where it would be
        // typed. The panel had it; the strip didn't offer it (2026-10-07).
        if let own = ownBooking, !own.isEmpty, asksToBook(text) {
            return .vault(field: VaultField(id: "booking", kind: "link", label: "Book a time", value: own))
        }
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
            // A copied link with trackers: clean, or as it was copied.
            if let clean = cleanCopy(paste) {
                return .convert(Conversions(source: "", results: ["Paste clean link", "Paste as copied"],
                                            inserts: [clean, paste], hows: [.after, .after]))
            }
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
    private static let notASum = #"^\s*(?:\d+(?:-\d+){2,}|\d{1,2}\s*/\s*\d{1,2}\s*/\s*\d{2,4}|\d{4}\s*/\s*\d{1,2}\s*/\s*\d{1,2}|\d{1,2}\s*/\s*(?:19|20)\d{2}|\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}-\d{4}|(?:\d{1,3}-)?\d{3}-\d{3}-\d{4}|\d{3}-\d{4}|\d{5}-\d{5})\s*$"#

    static func calc(_ text: String, indianGrouping: Bool = true) -> (value: String, hasEquals: Bool, expression: String)? {
        // "half of 350", "a third of 90", "double 25", "twice 40", "sqrt 81":
        // sums said in words (2026-10-07 probe: nothing showed).
        if let g = firstMatch(#"\b((?:a\s+)?(?:half|third|quarter)\s+of|double|twice|triple|sqrt|square\s+root(?:\s+of)?)\s+(?:[₹$€£]\s*)?(\d[\d,]*(?:\.\d+)?)\??\s?$"#, in: text),
           let words = g[1]?.lowercased(), let n = g[2].flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }) {
            let v: Double
            if words.hasSuffix("half of") { v = n / 2 }
            else if words.hasSuffix("third of") { v = n / 3 }
            else if words.hasSuffix("quarter of") { v = n / 4 }
            else if words == "double" || words == "twice" { v = n * 2 }
            else if words == "triple" { v = n * 3 }
            else { v = n.squareRoot() }
            guard let value = calcNumber(v, indianGrouping: indianGrouping) else { return nil }
            return (value, false, (g[0] ?? "").trimmingCharacters(in: .whitespaces))
        }
        // "2 to the power of 10", "square of 12", "cube root of 27", "log 100",
        // "10 factorial", "pi to 5 digits" (2026-10-14 probe).
        if let g = firstMatch(#"(\d+(?:\.\d+)?)\s+(?:to\s+the\s+power\s+(?:of\s+)?|raised\s+to\s+(?:the\s+)?(?:power\s+(?:of\s+)?)?)(\d+(?:\.\d+)?)\??\s?$"#, in: text),
           let a = Double(g[1] ?? ""), let b = Double(g[2] ?? ""), b <= 64, let v = calcNumber(pow(a, b), indianGrouping: indianGrouping) {
            return (v, false, trimmed(g[0]))
        }
        if let g = firstMatch(#"\b(square|cube)\s+of\s+(\d+(?:\.\d+)?)\??\s?$"#, in: text), let n = Double(g[2] ?? ""),
           let v = calcNumber(g[1]?.lowercased() == "cube" ? n * n * n : n * n, indianGrouping: indianGrouping) {
            return (v, false, trimmed(g[0]))
        }
        if let g = firstMatch(#"\bcube\s+root\s+(?:of\s+)?(\d+(?:\.\d+)?)\??\s?$"#, in: text), let n = Double(g[1] ?? ""),
           let v = calcNumber(cbrt(n), indianGrouping: indianGrouping) {
            return (v, false, trimmed(g[0]))
        }
        if let g = firstMatch(#"\b(log|ln)\s*\(?\s*(\d+(?:\.\d+)?)\s*\)?\??\s?$"#, in: text), let n = Double(g[2] ?? ""), n > 0,
           let v = calcNumber(g[1]?.lowercased() == "ln" ? log(n) : log10(n), indianGrouping: indianGrouping) {
            return (v, false, trimmed(g[0]))
        }
        if let g = firstMatch(#"(?<![\w.])(\d{1,2})\s*(?:factorial|!)\??\s?$"#, in: text), let n = Int(g[1] ?? ""), n <= 20 {
            let v = (1...max(1, n)).reduce(1.0) { $0 * Double($1) }
            if let t = calcNumber(v, indianGrouping: indianGrouping) { return (t, false, trimmed(g[0])) }
        }
        if let g = firstMatch(#"\bpi\s+to\s+(\d{1,2})\s+(?:digits|decimal\s+places|places|decimals)\??\s?$"#, in: text), let n = Int(g[1] ?? ""), n >= 1, n <= 15 {
            return (String(format: "%.\(n)f", Double.pi), false, trimmed(g[0]))
        }
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
            // "the score was 3-1", "pick a number 1-10": two whole numbers
            // and a bare hyphen at the end of a sentence are a score or a
            // range (2026-10-14 probe: 2 and -9). Asked ("whats 10-3") or on
            // its own ("10-2") it is still a sum.
            if expr.range(of: #"^\s*\d+-\d+\s*$"#, options: .regularExpression) != nil {
                let before = ns.substring(to: m.range(at: 1).location)
                if before.contains(where: \.isLetter),
                   before.range(of: #"(?:what'?s|what\s+is|calc(?:ulate)?|equals?|=)\s*$"#,
                                options: [.regularExpression, .caseInsensitive]) == nil { return nil }
            }
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
        guard let text = calcNumber(v, indianGrouping: indianGrouping) else { return nil }
        return (currency + text, hasEquals, shown)
    }

    /// A sum's answer as written: lakh and crore grouping in India,
    /// thousands everywhere else, two places at most.
    private static func calcNumber(_ v: Double, indianGrouping: Bool) -> String? {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: indianGrouping ? "en_IN" : "en_US")
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v))
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

    /// How much of the message's end the money chip reads ("₹1,000").
    static func moneyTailLength(_ text: String) -> Int {
        guard let re = amountPattern, !text.isEmpty else { return 0 }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return 0 }
        return ns.substring(with: m.range).trimmingCharacters(in: .whitespaces).count
    }

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
        // "100 usd to inr", "50 dollars in rupees", "$20 in euros": both
        // currencies named, so neither the phone's region nor dollars decide
        // (2026-10-07 probe: nothing showed).
        if let pair = currencyPair(in: text) {
            guard let fromRate = rates.fiat[pair.from], let toRate = rates.fiat[pair.to], fromRate > 0 else { return nil }
            let converted = pair.amount / fromRate * toRate
            let typed = "\(currencySymbol[pair.from] ?? "\(pair.from) ")\(formatNumber(pair.amount, code: pair.from))"
            let result = format(converted, in: pair.to)
            return .money(shown: "\(typed) = \(result)", insert: " = \(result)")
        }
        // "1 sol", "0.5 btc": an amount of a coin, in dollars, with Buy beside
        // it when the coin can be bought (the cashtag's chip, for an amount).
        if let coin = coinAmount(in: text) {
            guard let usd = rates.crypto[coin.symbol] else { return nil }
            let worth = price(usd * coin.amount)
            return .money(shown: "\(coin.typed) \(coin.symbol) = \(worth)", insert: " = \(worth)", buy: rates.mints[coin.symbol])
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

    /// An amount with both currencies named, the message ending on the
    /// second: (100, "USD", "INR") for "100 usd to inr". The keyboard asks
    /// for the rates off this too, before any are at hand.
    static func currencyPair(in text: String) -> (amount: Double, from: String, to: String)? {
        guard let g = firstMatch(#"(?:([₹$€£¥])\s*)?(\d[\d,]*(?:\.\d+)?)\s*([A-Za-z]{2,8})?\s+(?:to|in|into|as)\s+([A-Za-z]{2,8}|[₹$€£¥])\??\s?$"#, in: text),
              let amount = g[2].flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }), amount > 0,
              let from = g[1].flatMap({ $0.first }).flatMap({ symbolCurrency[$0] }) ?? g[3].flatMap({ wordCurrency[$0.lowercased()] }),
              let to = g[4].flatMap({ word in word.count == 1 ? word.first.flatMap { symbolCurrency[$0] } : wordCurrency[word.lowercased()] }),
              from != to else { return nil }
        return (amount, from, to)
    }

    /// Coins people write amounts of ("2 eth"); no LINK or DOT, which are
    /// words. Smart.kt's twin.
    private static let coinWords: Set<String> = ["sol", "btc", "eth", "usdc", "usdt", "bnb", "xrp", "doge",
                                                 "ada", "avax", "ltc", "trx", "shib", "pepe", "bonk", "jup", "wif"]

    /// An amount of a coin the message ends on: ("0.5", 0.5, "BTC") for
    /// "0.5 btc". The keyboard asks for the coin's rate off this too.
    static func coinAmount(in text: String) -> (typed: String, amount: Double, symbol: String)? {
        if let g = firstMatch(#"\b(?:price\s+of|how\s+much\s+is)\s+(?:an?\s+|one\s+)?([A-Za-z]{3,4})\s*(?:right\s+now|now|today)?\??\s?$"#, in: text),
           let word = g[1]?.lowercased(), coinWords.contains(word) {
            return ("1", 1, word.uppercased())
        }
        guard let g = firstMatch(#"(?<![\d.,$])(\d[\d,]*(?:\.\d+)?)\s*([A-Za-z]{3,4})\.?(?:\s+(?:in|to)\s+(?:usd|dollars?|\$))?\??\s?$"#, in: text),
              let typed = g[1], let word = g[2]?.lowercased(), coinWords.contains(word),
              let amount = Double(typed.replacingOccurrences(of: ",", with: "")), amount > 0 else { return nil }
        return (typed, amount, word.uppercased())
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
        // "I am" / "I'm" too, at the start the same way (Arpit, 2026-11-07).
        (#"(?:\bmy name is|\bname:|(?:^|[.!?,\n]\s*|\b(?:hi|hey|hello|hii|hiya)\W*)(?:this is|i am|i['’]m|im))\s*$"#, "name", nil),
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
        (#"(?:^|[\s,(])(?<!\b(?:can|could|will|would|should|shall|must|i'll|ill|we'll|i|we|you|u|they|he|she|to|pls|please|gonna|wanna|the|this|that|a|an|last|previous|prior|recent|earlier|next|new|old|first|same|your|his|her|their|its|whose|another|any|no|every|each|an?)\s)(?:e-?mail|g-?mail|mail\s*id)(?:\s*(?:id|address|addy))?\s*(?:is\s*)?:?\s*$"#, "email", nil),
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
        case "city", "state", "cityState":
            found = fields.filter { $0.kind == "address" }.compactMap { a in
                guard let place = cityState(in: a.value) else { return nil }
                switch kind {
                case "city": return VaultField(id: a.id + ":city", kind: kind, label: "City", value: place.city)
                case "state": return place.state.map { VaultField(id: a.id + ":state", kind: kind, label: "State", value: $0) }
                default: return VaultField(id: a.id + ":cityState", kind: kind, label: "City",
                                           value: place.state.map { "\(place.city), \($0)" } ?? place.city)
                }
            }
        default:
            found = fields.filter { $0.kind == kind }
        }
        var seen: Set<String> = []
        return found.filter { seen.insert($0.value.trimmingCharacters(in: .whitespaces).lowercased()).inserted }
    }

    /// The city (and state, when one is written) in a saved address: "123
    /// Market St, San Francisco, CA 94103" → San Francisco, CA; "10 Downing
    /// St, London SW1A 2AA" → London; "12 MG Road, Indiranagar, Bengaluru
    /// 560038" → Bengaluru. Nothing when the address is one line.
    static func cityState(in address: String) -> (city: String, state: String?)? {
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        // The last part, less its postcode: "CA 94103" → "CA", "London SW1A 2AA" → "London".
        func words(_ s: String) -> String {
            s.replacingOccurrences(of: #"\b(?:\d[\d-]*|[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2})\b"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters)
        }
        var tail = words(parts[parts.count - 1])
        var city = ""
        var state: String?
        if tail.count <= 3, tail == tail.uppercased(), !tail.isEmpty, parts.count >= 3 {
            state = tail
            city = words(parts[parts.count - 2])
        } else if tail.isEmpty, parts.count >= 3 {
            // "…, CA, 94103": the postcode on its own.
            tail = words(parts[parts.count - 2])
            if tail.count <= 3, tail == tail.uppercased(), parts.count >= 4 { state = tail; city = words(parts[parts.count - 3]) }
            else { city = tail }
        } else {
            city = tail
        }
        guard !city.isEmpty, city.range(of: #"^[\p{L} .'-]+$"#, options: .regularExpression) != nil, city.count <= 40 else { return nil }
        return (city, state)
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
    /// The saved details the words being typed are the start of (Arpit,
    /// 2026-10-06: "as soon person enters first 2-4 letters of any details
    /// in vault show that"): two letters or more ("ar" offers your email and
    /// your name), three digits or more of a number, with or without the
    /// country code it was saved with ("415"), across up to four words
    /// ("123 Mar" offers the address). `typed` is what a tap replaces; the
    /// longest run of words that starts something wins, and a detail typed
    /// out in full offers nothing. Three at most, one per value.
    static func completions(_ text: String, fields: [VaultField]) -> (typed: String, fields: [VaultField])? {
        guard let last = text.last, !last.isWhitespace, !fields.isEmpty else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        for k in stride(from: min(4, words.count), through: 1, by: -1) {
            let typed = String(text[words[words.count - k].startIndex...])
            var seen = Set<String>()
            let hits = fields.filter { startsDetail(typed, $0.value) && seen.insert($0.value.lowercased()).inserted }
            if !hits.isEmpty { return (typed, Array(hits.prefix(3))) }
        }
        return nil
    }

    /// Whether `typed` begins `value` without being all of it: by its
    /// letters (two at least), or, with none, by its digits (three at
    /// least), a saved "+1 (415) 555-0100" answering to "415" too.
    static func startsDetail(_ typed: String, _ value: String) -> Bool {
        let t = typed.lowercased()
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !v.isEmpty, t != v, t.count < v.count else { return false }
        if t.contains(where: \.isLetter) { return t.count >= 2 && v.hasPrefix(t) }
        let td = t.filter(\.isNumber)
        guard td.count >= 3 else { return false }
        if v.contains(where: \.isLetter) { return v.hasPrefix(t) }
        let vd = v.filter(\.isNumber)
        if vd.hasPrefix(td) { return vd.count > td.count }
        // Saved with its country code, typed without it; all of it typed
        // without the code is typed already.
        guard v.hasPrefix("+") else { return false }
        return (1...3).contains { n in
            let rest = vd.dropFirst(n)
            return rest.count > td.count && rest.hasPrefix(td)
        }
    }

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
        // A bare "m" too ("2m"), unless it reads as millions or minutes
        // (conversions checks).
        add("m", ["m", "meter", "meters", "metre", "metres", "mtr", "mtrs"])
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
        add("sq yd", ["sq yd", "sqyd", "square yard", "square yards"])
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
    /// A measure and the unit asked for: "10 km to miles", "5 lbs in kg?".
    private static let stripAsked: NSRegularExpression? = {
        let names = stripNames.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try? NSRegularExpression(pattern: #"(?<![\p{L}\d.,/])"# + stripAmount + #"\s*(?:degrees?\s+)?("# + names
                                        + #")\.?\s+(?:to|in|into|as)\s+("# + names + #")\??\s?$"#,
                                        options: [.caseInsensitive])
    }()

    /// What a unit measures: only a length goes into a length.
    private static func stripDimension(_ unit: String) -> String {
        switch unit {
        case "mm", "cm", "m", "km", "inch", "foot", "yard", "mile": return "length"
        case "g", "kg", "oz", "lb", "stone": return "mass"
        case "km/h", "mph", "m/s", "knot": return "speed"
        case "sq ft", "sq m", "sq yd", "acre", "hectare": return "area"
        case "°C", "°F": return "temperature"
        default: return "volume"
        }
    }

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
        case "sq yd": return 0.83612736
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
        // Asked for one unit ("10 km to miles", "5 lbs in kg"): that one.
        // Only the bare measure showed anything (2026-10-14).
        if let m = stripAsked?.firstMatch(in: t, range: all), !partOfMore(m),
           let n = group(m, 1).flatMap(amount), n.isFinite,
           let from = group(m, 2).flatMap({ stripNames[$0.lowercased()] }),
           let into = group(m, 3).flatMap({ stripNames[$0.lowercased()] }), from != into {
            let answer: String?
            switch (from, into) {
            case ("°C", "°F"): answer = stripNamed(n * 9 / 5 + 32, "°F")
            case ("°F", "°C"): answer = stripNamed((n - 32) * 5 / 9, "°C")
            default:
                if n > 0, let a = stripSize(from, uk: uk), let b = stripSize(into, uk: uk),
                   stripDimension(from) == stripDimension(into) {
                    answer = into == "foot" && n * a < 3 ? feetInches(metres: n * a) : stripNamed(n * a / b, into)
                } else {
                    answer = nil
                }
            }
            if let answer { return Conversions(source: source(m), results: [answer]) }
        }
        guard let m = stripMeasure?.firstMatch(in: t, range: all), !partOfMore(m),
              let typed = group(m, 1), let n = amount(typed), n.isFinite,
              let name = group(m, 2)?.lowercased(), let unit = stripNames[name] else { return nil }
        // "4g", "5g": a network, not grams. "10 pounds" is money outside the US.
        if unit == "g", name == "g", ns.substring(with: m.range).range(of: #"^[2-6]g"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        if name.hasPrefix("pound"), !us { return nil }
        // "2m" is metres (Arpit, 2026-10-06: "writing 2m doesnt show in inches
        // or other units"), but "$2m" is millions, "in 5m" minutes and "5M" money.
        if name == "m" {
            let before = ns.substring(to: m.range.location)
            // Only touching its number: "1 m" stays a minute or a million.
            let touching = ns.substring(with: m.range).range(of: #"[\d½⅓⅔¼¾⅛]m\.?\s?$"#, options: .regularExpression) != nil
            if group(m, 2) != "m" || !touching
                || before.range(of: #"[$€£₹¥]\s*$|\bin\s*$|\d\s*(?:h|hrs?|hours?)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return nil
            }
        }
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
            // Two or three units people would want, the other system first
            // (Arpit, 2026-10-06: "i dont need only to 1 unit, need it to 2-3
            // diff relevant units"). SmartUnits' Kotlin twin says the same.
            switch unit {
            case "mm": results = [to("inch"), to("cm")]
            case "cm": results = base < 0.3 ? [to("inch"), to("mm")]
                : base < 3 ? [feetInches(metres: base), to("inch"), to("m")] : [to("foot"), to("m")]
            case "m": results = base < 3 ? [feetInches(metres: base), to("inch"), to("cm")]
                : base < 1000 ? [to("foot"), to("yard")] : [to("mile"), to("foot"), to("km")]
            case "km": results = base < 10_000 ? [to("mile"), to("foot"), to("m")] : [to("mile"), to("m")]
            case "inch": results = base < 0.3 ? [to("cm"), to("mm"), to("foot")] : [to("cm"), to("m"), to("foot")]
            case "foot": results = n < 10 ? [to("m"), to("cm"), to("inch")] : [to("m"), to("yard")]
            case "yard": results = [to("m"), to("foot"), to("cm")]
            case "mile": results = base < 2000 ? [to("km"), to("m"), to("foot")] : [to("km"), to("m")]
            case "g": results = [to("oz"), to("lb"), to("kg")]
            case "kg": results = base < 10 ? [to("lb"), to("oz"), to("g")] : [to("lb"), to("stone")]
            case "oz": results = [metricMass(), to("lb")]
            case "lb": results = base < 2.27 ? [to("kg"), to("g"), to("oz")]
                : base < 6.35 ? [to("kg"), to("g")] : [to("kg"), to("stone")]
            case "stone": results = [to("kg"), to("lb")]
            case "ml": results = base < 0.00003 ? [to("tsp"), to("tbsp"), to("fl oz")] : [to("fl oz"), to("cup"), to("litre")]
            case "litre": results = uk ? [to("pint"), to("gallon"), to("fl oz")] : [to("gallon"), to("cup"), to("fl oz")]
            case "tsp": results = [to("ml"), to("tbsp")]
            case "tbsp": results = [to("ml"), to("tsp")]
            case "fl oz": results = [metricVolume(), to("cup")]
            case "cup": results = [metricVolume(), to("fl oz"), to("tbsp")]
            case "pint": results = [metricVolume(), to("cup"), to("fl oz")]
            case "quart": results = [to("litre"), to("pint"), to("cup")]
            case "gallon": results = [to("litre"), to("pint"), to("fl oz")]
            case "km/h": results = [to("mph"), to("m/s")]
            case "mph": results = [to("km/h"), to("m/s")]
            case "m/s", "knot": results = [to("km/h"), to("mph")]
            case "sq ft": results = [to("sq m"), to("sq yd")]
            case "sq m": results = [to("sq ft"), to("sq yd")]
            case "sq yd": results = [to("sq m"), to("sq ft")]
            case "acre": results = [to("hectare"), to("sq m"), to("sq ft")]
            case "hectare": results = [to("acre"), to("sq m")]
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

    /// A list said in one breath: "need: milk, eggs, bread", "todo: call
    /// bank, gym and book flight", "get milk, eggs, bread" → "• List" and
    /// "1. List", each putting one item a line in place of the line
    /// (Samsung and Apple do this with AI; this is instant). Three items at
    /// least, each short, on the line being typed.
    static func listMaker(in text: String) -> Conversions? {
        let line = text.components(separatedBy: "\n").last ?? text
        guard let g = firstMatch(#"^\s*((?:(?:need|needs|todo|to do|to-do|list|buy|get|pack|bring|grocer(?:y|ies)|shopping|tasks?|steps?|agenda|plan|order|ingredients|items|things|remember|checklist)\b[^:\n]{0,24}:\s*)|(?:need|buy|get|pack|bring|grab|remember)\s+)(.{5,200})$"#, in: line),
              let lead = g[1], let rest = g[2] else { return nil }
        let items = rest.replacingOccurrences(of: #"\s+and\s+"#, with: ",", options: [.regularExpression, .caseInsensitive])
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard items.count >= 3, items.allSatisfy({ $0.count <= 40 && !$0.contains(":") }) else { return nil }
        let head = lead.contains(":") ? lead.trimmingCharacters(in: .whitespaces) + "\n" : ""
        let bullets = head + items.map { "• \($0)" }.joined(separator: "\n")
        let numbered = head + items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return Conversions(source: trimmed(g[0]), results: ["• List", "1. List"], inserts: [bullets, numbered],
                           hows: [.replace, .replace])
    }

    /// Options in a question ("pizza, burgers or pasta?", "do you want
    /// coffee, tea or juice?") → "Make it a poll": the question kept, the
    /// options on numbered lines and "reply with a number" under it, since
    /// a keyboard can't make an app's own poll. Three to six short options,
    /// letters and digits; "ps5 or xbox?" is a question, not a poll.
    static func pollMaker(in text: String) -> Conversions? {
        let line = text.components(separatedBy: "\n").last ?? text
        guard let g = firstMatch(#"([A-Za-z0-9][A-Za-z0-9 ']{0,28}(?:,\s*[A-Za-z0-9][A-Za-z0-9 ']{0,24}){0,4})\s*,?\s+or\s+([A-Za-z0-9][A-Za-z0-9 ']{0,24}?)\s*\?\s?$"#, in: line),
              let head = g[1], let last = g[2] else { return nil }
        var options = head.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        // "do you want pizza": the question's words before the first option.
        let leads: Set<String> = ["do", "does", "did", "are", "is", "will", "would", "can", "could", "should", "shall",
                                  "you", "u", "we", "i", "they", "it", "that", "this", "want", "wanna", "prefer", "like",
                                  "rather", "going", "go", "for", "to", "get", "have", "eat", "order", "the", "a", "an",
                                  "some", "which", "what", "where", "when", "who", "with", "at", "in", "on", "so", "and",
                                  "guys", "ppl", "everyone", "tonight", "today", "tomorrow", "pick", "choose", "vote"]
        if var first = options.first {
            var words = first.split(separator: " ").map(String.init)
            while words.count > 1, leads.contains(words[0].lowercased()) { words.removeFirst() }
            first = words.joined(separator: " ")
            options[0] = first
        }
        options.append(last.trimmingCharacters(in: .whitespaces))
        let off: Set<String> = ["not", "no", "nah", "what", "something", "whatever", "anything", "nothing", "else", "so", "later"]
        guard options.count >= 3, options.count <= 6,
              options.allSatisfy({ !$0.isEmpty && $0.count <= 25 && !off.contains($0.lowercased()) && $0.contains(where: { $0.isLetter || $0.isNumber }) }),
              Set(options.map { $0.lowercased() }).count == options.count else { return nil }
        let keycaps = ["1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣"]
        let question = trimmed(g[0])
        let poll = question + "\n" + zip(keycaps, options).map { "\($0) \($1)" }.joined(separator: "\n") + "\nreply with a number"
        return Conversions(source: question, results: ["Make it a poll"], inserts: [poll], hows: [.replace])
    }

    /// The time now somewhere else: "what time is it in tokyo", "time in
    /// london?", "tokyo time" → "7:45 PM Tokyo" (the day too when it is not
    /// today there). Nothing for the phone's own zone (2026-10-07 probe).
    static func cityTime(in text: String, now: Date = Date(), here: TimeZone = .current,
                         region: String? = Locale.current.region?.identifier) -> Conversions? {
        let name: String
        if let g = firstMatch(#"\btime\s+(?:is\s+it\s+|now\s+|is\s+)?in\s+([a-z][a-z .]{1,30}?)\??\s?$"#, in: text), let n = g[1] {
            name = n
        } else if let g = firstMatch(#"\b([a-z]{3,20}(?:\s+[a-z]{3,20})?)\s+time(?:\s+now)?\??\s?$"#, in: text), let n = g[1] {
            name = n
        } else { return nil }
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        // "3pm london time in new york" converts 3pm; it isn't asking the time now.
        if text.range(of: #"\b\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.)"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        guard key != "the", key != "what", key != "same", key != "this", key != "that", key != "my", key != "your",
              key != "our", key != "their", key != "his", key != "her", key != "free", key != "long", key != "next" else { return nil }
        let r = region?.uppercased()
        var id = zoneNames[key] ?? zoneNames[key + " time"] ?? ""
        if key == "cst", r == "CN" { id = "Asia/Shanghai" }
        if key == "ist", r == "IE" { id = "Europe/Dublin" }
        if key == "ist", r == "IL" { id = "Asia/Jerusalem" }
        guard let there = TimeZone(identifier: id),
              there.secondsFromGMT(for: now) != here.secondsFromGMT(for: now) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = there
        var mine = Calendar(identifier: .gregorian)
        mine.timeZone = here
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = there
        f.dateFormat = cal.component(.minute, from: now) == 0 ? "h a" : "h:mm a"
        var clock = f.string(from: now).replacingOccurrences(of: "\u{202F}", with: " ")
        if cal.component(.day, from: now) != mine.component(.day, from: now) {
            f.dateFormat = "EEE"
            clock = f.string(from: now) + " " + clock
        }
        let label = key.count <= 4 && zoneNames[key] != nil && !key.contains(" ")
            ? key.uppercased() : key.capitalized
        return Conversions(source: trimmed(firstMatch(#"\S.*$"#, in: text)?[0] ?? text), results: ["\(clock) \(label)"])
    }

    /// The wait till a clock time: "how long until 5pm", "till 6:30pm" →
    /// "in 2h 15m"; a time gone by today is tomorrow's (2026-10-07 probe).
    static func untilTime(in text: String, now: Date = Date(), here: TimeZone = .current) -> Conversions? {
        guard let g = firstMatch(#"\b(?:until|till|til|'til)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\??\s?$"#, in: text),
              var hour = g[1].flatMap({ Int($0) }) else { return nil }
        let minute = g[2].flatMap { Int($0) } ?? 0
        let half = g[3]?.lowercased().replacingOccurrences(of: ".", with: "")
        if let half {
            guard (1...12).contains(hour) else { return nil }
            if half == "pm", hour < 12 { hour += 12 }
            if half == "am", hour == 12 { hour = 0 }
        } else {
            guard g[2] != nil, (0...23).contains(hour), minute < 60 else { return nil }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        var day = cal.dateComponents([.year, .month, .day], from: now)
        day.hour = hour
        day.minute = minute
        guard var when = cal.date(from: day) else { return nil }
        if when <= now, let next = cal.date(byAdding: .day, value: 1, to: when) { when = next }
        let minutes = Int((when.timeIntervalSince(now) / 60).rounded())
        guard minutes > 0 else { return nil }
        let wait = minutes >= 60 ? (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m") : "\(minutes)m"
        return Conversions(source: trimmed(g[0]), results: ["in \(wait)"])
    }

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
    /// spotlight search has a lot of things too lets try"), most particular
    /// first: a shortcut, a face, a measurement or a recipe's, a time in
    /// another zone or on the clock, a pace, a bill, a price or a loan, when
    /// someone will be there, a date or a holiday, numbers in other forms,
    /// links, and a coin or a pick. One chip per result; a tap adds it in
    /// brackets unless the answer says otherwise. Smart.kt's twin;
    /// shared/quick/strip-cases.json.
    static func quickAnswer(in text: String, now: Date = Date(), here: TimeZone = .current,
                            region: String? = Locale.current.region?.identifier) -> Conversions? {
        guard text.count <= 400 else { return nil }
        // A link's digits are its address: only its trackers are worth a chip.
        if endsInLink(text) { return cleanLink(in: text) }
        let tries: [() -> Conversions?] = [
            { shortcut(in: text, now: now, here: here, region: region) },
            { face(in: text) },
            { symbol(in: text) },
            { slangMeaning(in: text) },
            { phraseIn(in: text) },
            { writingHelp(in: text) },
            { mathsSymbol(in: text) },
            { solveEquation(in: text) },
            { cookingSafety(in: text) },
            { substitute(in: text) },
            { calories(in: text) },
            { clockChange(in: text, now: now, here: here, region: region) },
            { outOfOffice(in: text, now: now, here: here, region: region) },
            { emergencyNumber(in: text, region: region) },
            { uuid(in: text) },
            { base64(in: text) },
            { roman(in: text) },
            { listMaker(in: text) },
            { pollMaker(in: text) },
            { unitPrice(in: text) },
            { degreesAsked(in: text) },
            { duration(in: text) },
            { kitchenVolume(in: text) },
            { bmi(in: text) },
            { feetInches(in: text) },
            { driveTime(in: text) },
            { conversions(in: text, region: region) },
            { cooking(in: text, region: region) },
            { fuel(in: text, region: region) },
            { zoneTimes(in: text, now: now, here: here, region: region) },
            { cityTime(in: text, now: now, here: here, region: region) },
            { sunAnswer(in: text, now: now, here: here) },
            { timeDifference(in: text, now: now, here: here, region: region) },
            { untilTime(in: text, now: now, here: here) },
            { clockMaths(in: text) },
            { everyHours(in: text) },
            { pace(in: text) },
            { stackedDiscount(in: text) },
            { buyGetFree(in: text) },
            { billMath(in: text) },
            { taxInside(in: text, region: region) },
            { change(in: text) },
            { wasNow(in: text) },
            { testScore(in: text, region: region) },
            { averageOf(in: text) },
            { monthlySavings(in: text) },
            { heartRate(in: text) },
            { ratio(in: text) },
            { payRate(in: text) },
            { loan(in: text) },
            { arrival(in: text, now: now, here: here) },
            { backIn(in: text, now: now, here: here) },
            { holiday(in: text, now: now, here: here, region: region) },
            { dateInWords(in: text, now: now, here: here, region: region) },
            { workingDays(in: text, now: now, here: here, region: region) },
            { weekNumber(in: text, now: now, here: here, region: region) },
            { age(in: text, now: now, here: here, region: region) },
            { dayOfWeek(in: text, region: region) },
            { bases(in: text) },
            { colours(in: text) },
            { tracking(in: text) },
            { flight(in: text) },
            { phone(in: text, region: region) },
            { unixTime(in: text, here: here, region: region) },
            { inWords(in: text, region: region) },
            { download(in: text) },
            { mapLink(in: text) },
            { luckAnswer(in: text) },
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
            #"\bsplit\s+(?:the\s+)?(?:bill\s+(?:of\s+)?|[a-z]{2,12}\s+(?:of\s+)?)?"# + sym + #"\s*"# + amt + #"\s+(?:in\s+|into\s+|between\s+|among\s+|by\s+|with\s+)?(\d{1,2})"# + ways + end,
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
            (#"\b"# + pct + #"\s*tip\s*(?:on|for|of|to)?\s*"# + sym + #"\s*"# + amt + end, true),
            (#"\btip\s+(?:of\s+)?"# + pct + #"\s*(?:on|for)\s*"# + sym + #"\s*"# + amt + end, true),
            (#"\btip\s+(?:of\s+)?(\d{1,2}(?:\.\d+)?)\s*(?:on|for)\s*"# + sym + #"\s*"# + amt + end, true),
            (sym + #"\s*"# + amt + #"\s*(?:\+|plus|with|and)\s*"# + pct + #"\s*tip"# + end, false),
        ]
        for (p, first) in tips {
            guard let g = firstMatch(p, in: text), let r = pick(g, percentFirst: first) else { continue }
            let (percent, s, bill) = r
            let tip = bill * percent / 100
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces),
                               results: ["\(billMoney(tip, s)) tip", "\(billMoney(bill + tip, s)) total"])
        }
        if let g = firstMatch(#"(?<![\w.,])"# + sym + #"\s*"# + amt + #"\s+(minus|less|plus)\s+"# + pct + end, in: text),
           let base = number(g[2]), let p = number(g[4]), p > 0, p < 1000 {
            let minus = (g[3] ?? "").lowercased() != "plus"
            let v = minus ? base * (1 - p / 100) : base * (1 + p / 100)
            return Conversions(source: trimmed(g[0]), results: [billMoney(v, g[1] ?? "")])
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
        // "15 min from now", "whats 2 hours from now", "in 2 hours what time" (2026-10-14 probe).
        if let g = firstMatch(#"\b(?:what'?s\s+|whats\s+|what\s+time\s+is\s+it\s+)?(\d{1,3})\s*(mins?|minutes?|hrs?|hours?)\s+from\s+now\??"# + end, in: text)
            ?? firstMatch(#"\bin\s+(\d{1,3})\s*(mins?|minutes?|hrs?|hours?)\s*,?\s*what\s+time(?:\s+(?:is\s+it|will\s+it\s+be))?\??"# + end, in: text),
           let n = Double(g[1] ?? ""), let u = g[2], n > 0 {
            let mins = u.lowercased().hasPrefix("h") ? n * 60 : n
            guard mins <= 24 * 60 else { return nil }
            return Conversions(source: trimmed(g[0]), results: [clock(now.addingTimeInterval(mins * 60), from: now, here: here)])
        }
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
    /// "oct 14" or "14 october" → Wed 14 Oct · in 11 days (how far off, from
    /// a week away). Never a lone weekday, "today" or "tomorrow": those are
    /// said all day long.
    static func dateInWords(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        cal.firstWeekday = 2   // weeks start on Monday
        let today = cal.startOfDay(for: now)
        func say(_ g: [String?], _ dates: [Date], counted: Bool = false) -> Conversions {
            var results = dates.map { dayName($0, now: now, here: here, region: region) }
            if counted, let date = dates.first, (cal.dateComponents([.day], from: today, to: date).day ?? 0) >= 7 {
                results.append(countdown(to: date, from: now, here: here))
            }
            return Conversions(source: g[0]!.trimmingCharacters(in: .whitespaces), results: results)
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
                    return say(g, [date], counted: true)
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
            return say(g, [date], counted: true)
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
    static let builtInShortcuts: Set<String> = Set([";date", ";today", ";time", ";now", ";tmrw", ";tomorrow", ";yday", ";yesterday", ";iso"]
                                                   + faces.keys.map { ";" + $0 })

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
            // Six or eight characters with a digit are a colour; three need a
            // letter too ("#f00"), since "#007" and "#123" are hashtags.
            let digit = hex.range(of: #"\d"#, options: .regularExpression) != nil
            let letter = hex.range(of: #"[a-f]"#, options: [.regularExpression, .caseInsensitive]) != nil
            guard colourWords || (digit && (hex.count != 3 || letter)) else { return nil }
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let v = UInt64(String(hex.prefix(6)), radix: 16) else { return nil }
            let r = Double((v >> 16) & 0xFF), gg = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
            return Conversions(source: trimmed(g[0]), results: ["rgb(\(Int(r)), \(Int(gg)), \(Int(b)))", hsl(r, gg, b)])
        }
        if let g = firstMatch(#"\brgba?(?:\(\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*,?\s*(\d{1,3})\s*(?:[,/]\s*[\d.]+%?\s*)?\)|\s+(\d{1,3})\s*,?\s+(\d{1,3})\s*,?\s+(\d{1,3}))"# + end, in: text).map({ g in
               g[1] != nil ? g : [g[0], g[4], g[5], g[6]] }),
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
        if let g = firstMatch(#"(?<![\d])(9[2-5](?:\s?\d){18,20})"# + end, in: text), says("usps") || says("tracking") || says("track") {
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
        // A code in a message ("Your verification code is 482913"): the code
        // first, as Gboard's clipboard offers it (2026-10-08 research).
        if let re = try? NSRegularExpression(pattern: #"\b(?:code|otp|pin|passcode|password|verification|one[- ]time)\b[^\d\n]{0,24}?(?<![\d-])(\d{4,8})(?![\d-])"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) {
            found.append((m.range(at: 1), ns.substring(with: m.range(at: 1))))
        }
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

// MARK: - What launchers work out (Raycast, Alfred, Spotlight)

/// More of what the strip works out on the phone (Arpit, 2026-10-03: "also
/// research on more things wee can have ... find more things from raycast
/// etc too"): links without their trackers, faces and symbols by name,
/// numbers in words, clock maths, holidays and countdowns, working days,
/// ages, pay, loans, tax inside a price, unit prices, changes, ratios,
/// cooking, fuel, pace, downloads, and a coin, a die or a pick. Smart.kt's
/// twin; shared/quick/strip-cases.json holds the cases.
extension Smart {

    // MARK: Links without their trackers

    /// Query keys that only say where a click came from, never what the
    /// page shows (Raycast's Link Cleaner, Firefox's Copy Clean Link).
    private static let trackerKeys: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "gad_source", "gad_campaignid", "srsltid",
        "msclkid", "yclid", "twclid", "ttclid", "li_fat_id", "mc_cid", "mc_eid", "_hsenc", "_hsmi",
        "__hssc", "__hstc", "__hsfp", "hsctatracking", "mkt_tok", "igshid", "igsh", "mibextid",
        "oly_anon_id", "oly_enc_id", "rb_clickid", "s_cid", "s_kwcid", "ef_id", "vero_id", "vero_conv",
        "wickedid", "_openstat", "ocid", "icid", "ncid", "_branch_match_id", "_branch_referrer",
        "ref_src", "ref_url", "wt.mc_id", "pk_campaign", "pk_kwd", "pk_source", "pk_medium", "pk_content",
        "pk_cid", "utm", "_ga", "_gl",
    ]
    private static let trackerPrefixes = ["utm_", "mtm_", "matomo_"]

    /// Keys that track on their own sites only: "si" on YouTube and
    /// Spotify, "s" and "t" on X ("t" is a time on YouTube), "ref" on
    /// Amazon and Reddit (elsewhere it can be a referral code).
    private static func siteTrackers(_ host: String) -> (keys: Set<String>, prefixes: [String]) {
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if on("youtube.com") || on("youtu.be") { return (["si", "pp"], []) }
        if on("spotify.com") || on("spotify.link") { return (["si", "nd"], []) }
        if on("x.com") || on("twitter.com") { return (["s", "t"], []) }
        if on("tiktok.com") {
            return (["_r", "_t", "is_from_webapp", "sender_device", "is_copy_url", "share_app_id", "share_link_id",
                     "social_sharing", "u_code", "preview_pb", "share_item_id", "tt_from"], [])
        }
        if on("linkedin.com") { return (["trk", "trackingid", "lipi", "midtoken", "midsig", "trkemail", "eid", "refid", "rcm"], []) }
        if on("facebook.com") || on("fb.com") || on("fb.watch") { return (["rdid", "sfnsn", "__tn__"], ["__cft__"]) }
        if on("reddit.com") { return (["share_id", "rdt", "ref", "ref_source"], []) }
        if host.hasPrefix("amazon.") || host.contains(".amazon.") {
            return (["crid", "dib", "dib_tag", "qid", "sprefix", "sr", "keywords", "ref", "ref_", "content-id",
                     "_encoding", "spla", "sp_csd"], ["pd_rd_", "pf_rd_"])
        }
        return ([], [])
    }

    /// The link without its trackers, or nil when it has none. A time
    /// ("t=42"), a page, a search and the part after "#" stay.
    static func withoutTrackers(_ link: String) -> String? {
        var rest = Substring(link), fragment = Substring("")
        if let hash = rest.firstIndex(of: "#") { fragment = rest[hash...]; rest = rest[..<hash] }
        var path = rest, query = Substring("")
        if let q = rest.firstIndex(of: "?") { path = rest[..<q]; query = rest[rest.index(after: q)...] }
        let afterScheme = path.range(of: "://").map { path[$0.upperBound...] } ?? path
        var host = afterScheme.prefix { $0 != "/" && $0 != ":" }.lowercased()
        for p in ["www.", "m.", "mobile.", "smile."] where host.hasPrefix(p) { host.removeFirst(p.count) }
        let site = siteTrackers(host)
        var cleanPath = String(path)
        // Amazon says which list a click came from in the path ("/ref=sr_1_3").
        if host.hasPrefix("amazon.") || host.contains(".amazon.") {
            cleanPath = cleanPath.replacingOccurrences(of: #"/ref=[^/]*"#, with: "", options: .regularExpression)
        }
        let youtube = host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
        var removed = cleanPath != String(path)
        let kept = query.split(separator: "&", omittingEmptySubsequences: false).filter { pair in
            let key = pair.prefix { $0 != "=" }.lowercased()
            let value = pair.drop { $0 != "=" }.dropFirst().lowercased()
            let tracker = trackerKeys.contains(key) || site.keys.contains(key)
                || (trackerPrefixes + site.prefixes).contains { key.hasPrefix($0) }
                || (youtube && key == "feature" && value.hasPrefix("share"))
            if tracker { removed = true }
            return !tracker
        }
        guard removed else { return nil }
        let left = kept.filter { !$0.isEmpty }
        return cleanPath + (left.isEmpty ? "" : "?" + left.joined(separator: "&")) + fragment
    }

    /// The link the message ends on, without its trackers: "Remove
    /// tracking" puts it back clean, in its place.
    static func cleanLink(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?:^|\s)((?:https?://|www\.)[^\s<>"]+)\s?$"#, in: text), let link = g[1],
              let last = link.last, !".,;:!?)]}'\"".contains(last),
              let clean = withoutTrackers(link) else { return nil }
        return Conversions(source: link, results: ["Remove tracking"], inserts: [clean], hows: [.replace])
    }

    /// A copy that is one link with trackers: the link without them.
    static func cleanCopy(_ copy: String) -> String? {
        let t = copy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace),
              t.range(of: #"^(?:https?://|www\.)"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return withoutTrackers(t)
    }

    /// Whether the message ends inside a link, or what is left of one in
    /// the strip's last characters: its digits are an address, not a sum,
    /// a phone number or a parcel.
    static func endsInLink(_ text: String) -> Bool {
        guard let last = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).last else { return false }
        let token = last.lowercased()
        if token.contains("://") || token.hasPrefix("www.") { return true }
        if token.range(of: #"^(?:[a-z0-9-]+\.)+[a-z]{2,}/"#, options: .regularExpression) != nil { return true }
        // A query cut off at the front: "…ource=news&utm_medium=email".
        return token.contains("=") && (token.contains("&") || token.contains("?"))
    }

    // MARK: Faces and symbols by name

    /// Faces by name, as Slack has /shrug: the Emoticons tab's own faces.
    static let faces: [String: String] = [
        "shrug": "¯\\_(ツ)_/¯", "tableflip": "(╯°□°）╯︵ ┻━┻", "flip": "(╯°□°）╯︵ ┻━┻",
        "unflip": "┬─┬ノ( º _ ºノ)", "lenny": "( ͡° ͜ʖ ͡°)", "disapprove": "ಠ_ಠ", "lod": "ಠ_ಠ",
        "happy": "(◕‿◕)", "hug": "(づ｡◕‿‿◕｡)づ", "cry": "(╥﹏╥)", "love": "(♥ω♥)", "bear": "ʕ•ᴥ•ʔ",
        "cool": "(⌐■_■)", "sparkle": "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "cat": "(=^･ω･^=)", "dance": "ᕕ( ᐛ )ᕗ",
        "angry": "(╬ Ò﹏Ó)", "shock": "(⊙_⊙)", "fight": "(ง •̀_•́)ง", "yay": "\\(^o^)/",
    ]

    /// "/shrug" or ";shrug" → ¯\_(ツ)_/¯ in its place, and "shrug" alone.
    static func face(in text: String) -> Conversions? {
        let names = faces.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let g = firstMatch(#"(?:^|\s)([/;](?:"# + names + #"))\s?$"#, in: text), let typed = g[1],
           let face = faces[String(typed.dropFirst()).lowercased()] {
            return Conversions(source: typed, results: [face], hows: [.replace])
        }
        if let g = firstMatch(#"^\s*(shrug|tableflip|lenny)\s?$"#, in: text), let typed = g[1],
           let face = faces[typed.lowercased()] {
            return Conversions(source: typed, results: [face], hows: [.replace])
        }
        return nil
    }

    private static let symbolSwaps: [String: String] = [
        "<->": "↔", "<=>": "⇔", "->": "→", "<-": "←", "=>": "⇒", "+/-": "±", "+-": "±",
        "!=": "≠", "=/=": "≠", "~=": "≈", "<=": "≤", ">=": "≥", "(tm)": "™",
    ]

    /// "->" → →, "+-" → ±, "!=" → ≠, "(tm)" → ™, in its place. A heart
    /// ("<3") and a face (":->") stay as they are.
    static func symbol(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?:^|[\s\w])(<->|<=>|->|<-|=>|\+/-|\+-|!=|=/=|~=|<=|>=|\(tm\))\s?$"#, in: text),
              let typed = g[1], let swap = symbolSwaps[typed.lowercased()] else { return nil }
        return Conversions(source: typed, results: [swap], hows: [.replace])
    }

    // MARK: Numbers in words

    private static let onesWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                                    "eighteen", "nineteen"]
    private static let tensWords = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// Under a thousand in words: "two hundred fifty-six".
    private static func hundredsInWords(_ n: Int) -> String {
        var parts: [String] = []
        if n >= 100 { parts.append(onesWords[n / 100] + " hundred") }
        let r = n % 100
        if r > 0 { parts.append(r < 20 ? onesWords[r] : tensWords[r / 10] + (r % 10 > 0 ? "-" + onesWords[r % 10] : "")) }
        return parts.joined(separator: " ")
    }

    /// A whole number in words, as a cheque has it: "one thousand two
    /// hundred fifty"; in India "one lakh twenty thousand".
    static func numberInWords(_ n: Int64, indian: Bool) -> String {
        if n == 0 { return "zero" }
        let scales: [(Int64, String)] = indian
            ? [(10_000_000, "crore"), (100_000, "lakh"), (1000, "thousand")]
            : [(1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"), (1000, "thousand")]
        var parts: [String] = []
        var rest = n
        for (size, name) in scales where rest >= size {
            let count = rest / size
            parts.append((count >= 1000 ? numberInWords(count, indian: indian) : hundredsInWords(Int(count))) + " " + name)
            rest %= size
        }
        if rest > 0 { parts.append(hundredsInWords(Int(rest))) }
        return parts.joined(separator: " ")
    }

    private static let moneyWords: [String: (one: String, many: String, cent: String, cents: String)] = [
        "$": ("dollar", "dollars", "cent", "cents"), "€": ("euro", "euros", "cent", "cents"),
        "£": ("pound", "pounds", "penny", "pence"), "₹": ("rupee", "rupees", "paisa", "paise"),
    ]

    /// "1,250 in words" → One thousand two hundred fifty; "$1,250.50 in
    /// words" → … dollars and fifty cents; lakh and crore in India (a
    /// cheque wants words). Typed in place of what was asked.
    static func inWords(in text: String, region: String?) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.,])([$€£₹])?\s?(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d{1,13}(?:\.\d{1,2})?)\s+(?:in|into|to)\s+words"# + end, in: text),
              let typed = g[2] else { return nil }
        let parts = typed.replacingOccurrences(of: ",", with: "").split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int64(parts[0]), whole < 1_000_000_000_000 else { return nil }
        let symbol = g[1]
        var words = numberInWords(whole, indian: region?.uppercased() == "IN" || symbol == "₹")
        if let symbol, let w = moneyWords[symbol] {
            words += " " + (whole == 1 ? w.one : w.many)
            if parts.count == 2, let c = Int(parts[1].count == 1 ? String(parts[1]) + "0" : String(parts[1])), c > 0 {
                words += " and " + hundredsInWords(c) + " " + (c == 1 ? w.cent : w.cents)
            }
        } else if parts.count == 2 {
            words += " point " + parts[1].compactMap(\.wholeNumberValue).map { onesWords[$0] }.joined(separator: " ")
        }
        return Conversions(source: trimmed(g[0]), results: [words.prefix(1).uppercased() + words.dropFirst()], hows: [.replace])
    }

    // MARK: Clock maths

    private static let clockPart = #"(\d{1,2})(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)?"#

    /// Minutes after midnight, or nil when it can't be a time of day.
    private static func dayMinutes(_ h: Int, _ m: Int, _ ap: String?) -> Int? {
        guard m < 60 else { return nil }
        if let ap {
            guard h >= 1, h <= 12 else { return nil }
            return (h % 12 + (ap.lowercased().hasPrefix("p") ? 12 : 0)) * 60 + m
        }
        return h <= 23 ? h * 60 + m : nil
    }

    /// "7 h 45 min", "8 h", "45 min".
    private static func spanText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "6:15 PM" where am/pm was said, "16:30" on a 24-hour clock.
    private static func clockText(_ minutes: Int, twelve: Bool) -> String {
        let t = (minutes % 1440 + 1440) % 1440
        let h = t / 60, m = t % 60
        let mm = m < 10 ? "0\(m)" : "\(m)"
        if !twelve { return "\(h):\(mm)" }
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m == 0 ? "\(h12) \(ap)" : "\(h12):\(mm) \(ap)"
    }

    /// "9:30–5:15", "shift 9am to 5:30pm" → 7 h 45 min; "3:45pm + 2h30",
    /// "9am plus 8 hours" → 6:15 PM. A span needs minutes or am/pm at one
    /// end ("working 9 to 5" is a phrase, "won 3-1" a score), and is said
    /// only when it takes working out (not "2-3pm").
    static func clockMaths(in text: String) -> Conversions? {
        if let g = firstMatch(#"(?<![\d:.$€£₹/])"# + clockPart + #"\s*(?:-|–|—|to|till|til|until)\s*"# + clockPart + end, in: text),
           let h1 = Int(g[1] ?? ""), let h2 = Int(g[4] ?? ""), g[2] != nil || g[3] != nil || g[5] != nil || g[6] != nil {
            let m1 = Int(g[2] ?? "") ?? 0, m2 = Int(g[5] ?? "") ?? 0
            var ap1 = g[3], ap2 = g[6]
            func flip(_ ap: String) -> String { ap.lowercased().hasPrefix("a") ? "pm" : "am" }
            if ap1 == nil, let a = ap2 {
                ap1 = a
                if let s = dayMinutes(h1, m1, a), let f = dayMinutes(h2, m2, a), s > f { ap1 = flip(a) }
            } else if let a = ap1, ap2 == nil {
                ap2 = a
                if let s = dayMinutes(h1, m1, a), let f = dayMinutes(h2, m2, a), f <= s { ap2 = flip(a) }
            }
            guard let s = dayMinutes(h1, m1, ap1), var f = dayMinutes(h2, m2, ap2) else { return nil }
            if ap1 == nil, h1 <= 12, h2 <= 12 {
                // "9:30–5:15": the end is the next time the clock says it.
                while f <= s { f += 12 * 60 }
            } else if f <= s {
                f += 24 * 60
            }
            let span = f - s
            guard span > 0, span < 24 * 60, span % 60 != 0 || span >= 3 * 60 else { return nil }
            return Conversions(source: trimmed(g[0]), results: [spanText(span)])
        }
        let duration = #"(?:(\d{1,2}(?:\.\d+)?)\s*(?:h|hrs?|hours?)\s*(?:(\d{1,2})\s*(?:m|mins?|minutes?)?)?|(\d{1,3})\s*(?:m|mins?|minutes?))"#
        if let g = firstMatch(#"(?<![\d:.$€£₹/])"# + clockPart + #"\s*(\+|plus|-|minus)\s*"# + duration + end, in: text),
           let h = Int(g[1] ?? ""), g[2] != nil || g[3] != nil,
           let start = dayMinutes(h, Int(g[2] ?? "") ?? 0, g[3]) {
            var add = 0.0
            if let hours = g[5].flatMap(Double.init) { add = hours * 60 + (Double(g[6] ?? "") ?? 0) }
            else if let mins = g[7].flatMap(Double.init) { add = mins }
            guard add > 0, add < 48 * 60 else { return nil }
            let op = (g[4] ?? "").lowercased()
            let at = start + (op == "-" || op == "minus" ? -1 : 1) * Int(add.rounded())
            return Conversions(source: trimmed(g[0]), results: [clockText(at, twelve: g[3] != nil)])
        }
        return nil
    }

    /// "every 8 hours from 7am" → 7 AM, 3 PM, 11 PM: the times on the clock
    /// in a day, from four hours apart to twelve.
    static func everyHours(in text: String) -> Conversions? {
        let counts = ["four": 4, "five": 5, "six": 6, "eight": 8, "twelve": 12]
        guard let g = firstMatch(#"\bevery\s+(\d{1,2}|four|five|six|eight|twelve)\s*(?:h|hrs?|hours?)\s+(?:from|starting(?:\s+(?:at|from))?|beginning(?:\s+at)?|at)\s+"# + clockPart + end, in: text),
              let n = Int(g[1] ?? "") ?? counts[(g[1] ?? "").lowercased()], n >= 4, n <= 12,
              let h = Int(g[2] ?? ""), g[3] != nil || g[4] != nil || h > 12,
              let start = dayMinutes(h, Int(g[3] ?? "") ?? 0, g[4]) else { return nil }
        let times = stride(from: 0, to: 24 * 60, by: n * 60).map { clockText(start + $0, twelve: g[4] != nil) }
        return Conversions(source: trimmed(g[0]), results: [times.joined(separator: ", ")])
    }

    // MARK: Days: holidays, countdowns, working days, weeks, ages

    /// The weekday of a date, Sunday 0 to Saturday 6 (Sakamoto's method).
    private static func weekdayOf(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let yy = m < 3 ? y - 1 : y
        return (yy + yy / 4 - yy / 100 + yy / 400 + t[m - 1] + d) % 7
    }

    private static func daysIn(_ y: Int, _ m: Int) -> Int {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    }

    /// The nth weekday (Sunday 0) of a month; n = -1 is the last.
    private static func nthWeekday(_ y: Int, _ m: Int, _ weekday: Int, _ n: Int) -> (Int, Int) {
        if n < 0 {
            let last = daysIn(y, m)
            return (m, last - (weekdayOf(y, m, last) - weekday + 7) % 7)
        }
        return (m, 1 + (weekday - weekdayOf(y, m, 1) + 7) % 7 + (n - 1) * 7)
    }

    /// Easter Sunday, by the Gregorian computus.
    private static func easter(_ y: Int) -> (Int, Int) {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        return ((h + l - 7 * m + 114) / 31, (h + l - 7 * m + 114) % 31 + 1)
    }

    /// A month and day some days later or earlier in the same year.
    private static func shifted(_ y: Int, _ md: (Int, Int), by days: Int) -> (Int, Int) {
        var (m, d) = md
        d += days
        while d < 1 { m -= 1; d += daysIn(y, m) }
        while d > daysIn(y, m) { d -= daysIn(y, m); m += 1 }
        return (m, d)
    }

    /// Diwali (Lakshmi Puja) and the Lunar New Year follow the moon.
    private static let diwaliDays: [Int: (Int, Int)] = [2025: (10, 20), 2026: (11, 8), 2027: (10, 29), 2028: (10, 17),
                                                        2029: (11, 5), 2030: (10, 26)]
    private static let lunarNewYears: [Int: (Int, Int)] = [2025: (1, 29), 2026: (2, 17), 2027: (2, 6), 2028: (1, 26),
                                                           2029: (2, 13), 2030: (2, 3)]

    /// Holidays as people name them; apostrophes and dots optional.
    private static let holidayNames = #"new\s+year'?s\s+eve|nye|new\s+year'?s\s+day|new\s+year'?s|new\s+year|valentine'?s\s+day|valentine'?s|st\.?\s+patrick'?s\s+day|saint\s+patrick'?s\s+day|paddy'?s\s+day|easter\s+sunday|easter\s+monday|easter|good\s+friday|mother'?s\s+day|father'?s\s+day|memorial\s+day|independence\s+day|(?:4th|fourth)\s+of\s+july|labou?r\s+day|halloween|thanksgiving|black\s+friday|cyber\s+monday|christmas\s+eve|xmas\s+eve|christmas\s+day|christmas|xmas|boxing\s+day|mlk\s+day|martin\s+luther\s+king(?:\s+jr\.?)?\s+day|presidents'?\s+day|juneteenth|veterans'?\s+day|remembrance\s+day|canada\s+day|australia\s+day|bastille\s+day|guy\s+fawkes(?:\s+night)?|bonfire\s+night|april\s+fools'?(?:\s+day)?|earth\s+day|groundhog\s+day|cinco\s+de\s+mayo|diwali|deepavali|lunar\s+new\s+year|chinese\s+new\s+year|republic\s+day|gandhi\s+jayanti"#

    /// A holiday's month and day in a year, where the phone is (Mother's
    /// Day is in Lent in Britain, Thanksgiving in October in Canada).
    private static func holidayDay(_ name: String, year y: Int, region: String?) -> (Int, Int)? {
        let r = region?.uppercased() ?? ""
        let n = name.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let thanksgiving = nthWeekday(y, 11, 4, 4)
        switch n {
        case "new years eve", "nye": return (12, 31)
        case "new years day", "new years", "new year": return (1, 1)
        case "valentines day", "valentines": return (2, 14)
        case "st patricks day", "saint patricks day", "paddys day": return (3, 17)
        case "easter", "easter sunday": return easter(y)
        case "good friday": return shifted(y, easter(y), by: -2)
        case "easter monday": return shifted(y, easter(y), by: 1)
        case "mothers day": return ["GB", "IE"].contains(r) ? shifted(y, easter(y), by: -21) : nthWeekday(y, 5, 0, 2)
        case "fathers day": return ["AU", "NZ"].contains(r) ? nthWeekday(y, 9, 0, 1) : nthWeekday(y, 6, 0, 3)
        case "memorial day": return nthWeekday(y, 5, 1, -1)
        case "independence day": return r == "IN" ? (8, 15) : (7, 4)
        case "4th of july", "fourth of july": return (7, 4)
        case "labor day", "labour day": return ["US", "CA"].contains(r) ? nthWeekday(y, 9, 1, 1) : (5, 1)
        case "halloween": return (10, 31)
        case "thanksgiving": return r == "CA" ? nthWeekday(y, 10, 1, 2) : thanksgiving
        case "black friday": return shifted(y, thanksgiving, by: 1)
        case "cyber monday": return shifted(y, thanksgiving, by: 4)
        case "christmas eve", "xmas eve": return (12, 24)
        case "christmas", "xmas", "christmas day": return (12, 25)
        case "boxing day": return (12, 26)
        case "mlk day", "martin luther king day", "martin luther king jr day": return nthWeekday(y, 1, 1, 3)
        case "presidents day": return nthWeekday(y, 2, 1, 3)
        case "juneteenth": return (6, 19)
        case "veterans day", "remembrance day": return (11, 11)
        case "canada day": return (7, 1)
        case "australia day": return (1, 26)
        case "bastille day": return (7, 14)
        case "guy fawkes", "guy fawkes night", "bonfire night": return (11, 5)
        case "april fools", "april fools day": return (4, 1)
        case "earth day": return (4, 22)
        case "groundhog day": return (2, 2)
        case "cinco de mayo": return (5, 5)
        case "diwali", "deepavali": return diwaliDays[y]
        case "lunar new year", "chinese new year": return lunarNewYears[y]
        case "republic day": return r == "IN" ? (1, 26) : nil
        case "gandhi jayanti": return (10, 2)
        default: return nil
        }
    }

    /// The next time a month and day comes round, today included.
    private static func nextDay(_ day: (Int) -> (Int, Int)?, now: Date, here: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let today = cal.startOfDay(for: now)
        let year = cal.component(.year, from: today)
        for y in [year, year + 1] {
            guard let md = day(y), let date = cal.date(from: DateComponents(year: y, month: md.0, day: md.1)) else { continue }
            if date >= today { return date }
        }
        return nil
    }

    /// "today", "tomorrow", "in 54 days".
    private static func countdown(to date: Date, from now: Date, here: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        return days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days"
    }

    /// "oct 14", "14th of october": a month and day.
    private static func monthAndDay(_ s: String) -> (Int, Int)? {
        let words = s.lowercased().replacingOccurrences(of: #"(\d)(?:st|nd|rd|th)"#, with: "$1", options: .regularExpression)
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "," }).map(String.init).filter { $0 != "of" }
        guard words.count == 2 else { return nil }
        let (dText, mText) = Int(words[0]) != nil ? (words[0], words[1]) : (words[1], words[0])
        guard let d = Int(dText), let m = months.first(where: { $0.0 == mText })?.1, d >= 1, d <= daysIn(2024, m) else { return nil }
        return (m, d)
    }

    /// "after thanksgiving" → Thu 26 Nov · in 54 days; "christmas party";
    /// "days until christmas" → 83 days. A holiday needs a word that dates
    /// it ("merry christmas" is a greeting), and only days ahead count.
    static func holiday(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        let t = text.replacingOccurrences(of: "’", with: "'")
        let monthNames = months.map(\.0).joined(separator: "|")
        let monthDay = #"(?:"# + monthNames + #")\.?\s+\d{1,2}(?:st|nd|rd|th)?|\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?(?:"# + monthNames + #")"#
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        // "days until christmas", "how many days till dec 25", "sleeps to christmas".
        if let g = firstMatch(#"\b(?:how\s+many\s+)?(days?|weeks?|sleeps)\s+(?:left\s+)?(?:until|till|til|to|before)\s+(?:the\s+)?("# + holidayNames + "|" + monthDay + #")"# + end, in: t),
           let what = g[2] {
            let named = firstMatch(#"^(?:"# + holidayNames + #")$"#, in: what) != nil
            let when: Date? = named
                ? nextDay({ holidayDay(what, year: $0, region: region) }, now: now, here: here)
                : monthAndDay(what).flatMap { md in nextDay({ _ in md }, now: now, here: here) }
            guard let when else { return nil }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: when).day ?? 0
            let unit = (g[1] ?? "").lowercased()
            let count: String
            if unit.hasPrefix("week"), days >= 7 {
                count = "\(days / 7) week\(days / 7 == 1 ? "" : "s")" + (days % 7 > 0 ? " \(days % 7) day\(days % 7 == 1 ? "" : "s")" : "")
            } else {
                count = "\(days) " + (unit == "sleeps" ? (days == 1 ? "sleep" : "sleeps") : (days == 1 ? "day" : "days"))
            }
            return Conversions(source: trimmed(g[0]), results: [count, dayName(when, now: now, here: here, region: region)])
        }
        // "when is thanksgiving", "what day is christmas this year", "countdown
        // to new year", "when is easter 2027" (2026-10-14 probe).
        if let g = firstMatch(#"\b(?:when\s+is|when'?s|whens|what\s+(?:day|date)\s+is|countdown\s+(?:to|till|until)|how\s+long\s+(?:until|till|to))\s+(?:the\s+)?("# + holidayNames + #")(?:\s+(?:this\s+year|(20\d{2})))?\??"# + end, in: t),
           let name = g[1] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = here
            let when: Date?
            if let y = g[2].flatMap({ Int($0) }), let md = holidayDay(name, year: y, region: region) {
                when = cal.date(from: DateComponents(year: y, month: md.0, day: md.1))
            } else {
                when = nextDay({ holidayDay(name, year: $0, region: region) }, now: now, here: here)
            }
            if let when {
                return Conversions(source: trimmed(g[0]), results: [dayName(when, now: now, here: here, region: region),
                                                                    countdown(to: when, from: now, here: here)])
            }
        }
        let lead = #"\b(?:on|after|before|by|till|til|until|for|over|during|around|this|next|from|at)\s+(?:the\s+)?("# + holidayNames + #")(?:\s+(?:day|weekend|break|holidays?|party|parties|trip|sale|sales|dinner|lunch|brunch|plans?|week|vacation))?"# + end
        let tail = #"(?<!\blast\s)(?<!\bpast\s)\b("# + holidayNames + #")\s+(?:weekend|break|party|parties|trip|sale|sales|dinner|lunch|brunch|plans?|holidays?|vacation|week)"# + end
        for p in [lead, tail] {
            guard let g = firstMatch(p, in: t), let name = g[1],
                  let when = nextDay({ holidayDay(name, year: $0, region: region) }, now: now, here: here) else { continue }
            return Conversions(source: trimmed(g[0]), results: [dayName(when, now: now, here: here, region: region),
                                                                countdown(to: when, from: now, here: here)])
        }
        return nil
    }

    /// Weekends on Friday and Saturday where the week runs that way.
    private static let fridayWeekends: Set<String> = ["SA", "EG", "IL", "QA", "KW", "OM", "BH", "JO", "IQ", "DZ", "LY", "SD", "YE"]

    /// "10 working days from today", "in 5 business days" → Fri 16 Oct:
    /// weekdays counted from tomorrow (public holidays aside).
    static func workingDays(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        guard let g = firstMatch(#"\b"# + countWord + #"\s+(?:working|business|work)\s+days?(?:\s+(?:from\s+(?:today|now)|after\s+today))?"# + end, in: text),
              let whole = g[0], let count = g[1] else { return nil }
        // "3-5 business days": a range, half answered.
        let head = String(text.dropLast(whole.count))
        if head.range(of: #"\d\s*(?:-|–|to)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let n = Int(Double(count) ?? smallNumbers[count.lowercased()] ?? 0)
        guard n >= 1, n <= 260 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let friday = fridayWeekends.contains(region?.uppercased() ?? "")
        var day = cal.startOfDay(for: now)
        var left = n
        while left > 0 {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
            let wd = cal.component(.weekday, from: day)   // Sunday 1 … Saturday 7
            if !(friday ? (wd == 6 || wd == 7) : (wd == 1 || wd == 7)) { left -= 1 }
        }
        return Conversions(source: trimmed(whole), results: [dayName(day, now: now, here: here, region: region)])
    }

    /// "12–18 Oct" ("Oct 12–18" in the US), across months "28 Sep–4 Oct".
    private static func dayRange(_ a: Date, _ b: Date, now: Date, here: TimeZone, region: String?) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        f.dateFormat = "MMM"
        let ma = f.string(from: a), mb = f.string(from: b)
        let da = cal.component(.day, from: a), db = cal.component(.day, from: b)
        let us = region?.uppercased() == "US"
        var text: String
        if ma == mb { text = us ? "\(ma) \(da)–\(db)" : "\(da)–\(db) \(mb)" }
        else { text = us ? "\(ma) \(da)–\(mb) \(db)" : "\(da) \(ma)–\(db) \(mb)" }
        let year = cal.component(.year, from: b)
        if year != cal.component(.year, from: now) { text += (us ? ", " : " ") + "\(year)" }
        return text
    }

    /// "cw 42", "KW 42", "calendar week 42", "week no. 42" → 12–18 Oct: an
    /// ISO week, Monday to Sunday. "week 3" alone is a count, not a date.
    static func weekNumber(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        // "what week is it", "week number?": this week's ISO number.
        if let g = firstMatch(#"(?:^|\b(?:what|which)\s+)(?:week\s+(?:is\s+it|are\s+we\s+in|number\s+is\s+it)|(?:current\s+|this\s+)?week\s+(?:no\.?|number|num))\s*(?:today|now)?"# + end, in: text) {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = here
            return Conversions(source: trimmed(g[0]), results: ["Week \(cal.component(.weekOfYear, from: now))"])
        }
        guard let g = firstMatch(#"\b(?:cw|kw|calendar\s+week|week\s+(?:no\.?|number|num|#))\s*#?\s*(\d{1,2})"# + end, in: text),
              let n = Int(g[1] ?? ""), n >= 1, n <= 53 else { return nil }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = here
        let today = cal.startOfDay(for: now)
        let thisYear = cal.component(.yearForWeekOfYear, from: today)
        for year in [thisYear, thisYear + 1] {
            guard let monday = cal.date(from: DateComponents(weekday: 2, weekOfYear: n, yearForWeekOfYear: year)),
                  cal.component(.weekOfYear, from: monday) == n,
                  let sunday = cal.date(byAdding: .day, value: 6, to: monday), sunday >= today else { continue }
            return Conversions(source: trimmed(g[0]), results: [dayRange(monday, sunday, now: now, here: here, region: region)])
        }
        return nil
    }

    /// A whole date as written: "14 mar 1998", "march 14, 1998",
    /// "14/03/1998" (month first in the US), "1998-03-14". Twelve groups.
    private static let fullDatePattern: String = {
        let m = months.map(\.0).joined(separator: "|")
        return #"(?:(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?("# + m + #")\.?,?\s+(\d{4})|("# + m + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})|(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})|(\d{4})-(\d{1,2})-(\d{1,2}))"#
    }()

    /// The year, month and day of a whole date matched from group `i`.
    private static func fullDate(_ g: [String?], from i: Int, region: String?) -> (y: Int, m: Int, d: Int)? {
        func month(_ s: String?) -> Int? { s.flatMap { s in months.first { $0.0 == s.lowercased() }?.1 } }
        func int(_ k: Int) -> Int? { g[i + k].flatMap { Int($0) } }
        var date: (y: Int, m: Int, d: Int)
        if let d = int(0), let m = month(g[i + 1]), let y = int(2) { date = (y, m, d) }
        else if let m = month(g[i + 3]), let d = int(4), let y = int(5) { date = (y, m, d) }
        else if let a = int(6), let b = int(7), let y = int(8) { date = region?.uppercased() == "US" ? (y, a, b) : (y, b, a) }
        else if let y = int(9), let m = int(10), let d = int(11) { date = (y, m, d) }
        else { return nil }
        guard date.y >= 1900, date.m >= 1, date.m <= 12, date.d >= 1, date.d <= daysIn(date.y, date.m) else { return nil }
        return date
    }

    /// "born 14 mar 1998" → 28 years old; "together since 12 june 2021" →
    /// 5 years 3 months. A whole date only: "born in 1995" says it already.
    static func age(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let c = cal.dateComponents([.year, .month, .day], from: now)
        guard let ty = c.year, let tm = c.month, let td = c.day else { return nil }
        if let g = firstMatch(#"\b(?:born|dob|d\.o\.b\.?|date\s+of\s+birth|birthday|bday|b'day)\s*(?:is\s+|was\s+|:\s*|-\s*)?(?:on\s+)?"# + fullDatePattern + end, in: text),
           let b = fullDate(g, from: 1, region: region), (b.y, b.m, b.d) <= (ty, tm, td) {
            let years = ty - b.y - ((tm, td) < (b.m, b.d) ? 1 : 0)
            guard years < 130 else { return nil }
            return Conversions(source: trimmed(g[0]), results: [years == 1 ? "1 year old" : "\(years) years old"])
        }
        if let g = firstMatch(#"\bsince\s+"# + fullDatePattern + end, in: text),
           let b = fullDate(g, from: 1, region: region), (b.y, b.m, b.d) < (ty, tm, td) {
            var years = ty - b.y, monthsGone = tm - b.m, days = td - b.d
            if days < 0 {
                monthsGone -= 1
                days += daysIn(tm == 1 ? ty - 1 : ty, tm == 1 ? 12 : tm - 1)
            }
            if monthsGone < 0 { years -= 1; monthsGone += 12 }
            func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
            let said: String
            if years > 0 { said = plural(years, "year") + (monthsGone > 0 ? " " + plural(monthsGone, "month") : "") }
            else if monthsGone > 0 { said = plural(monthsGone, "month") + (days > 0 ? " " + plural(days, "day") : "") }
            else { said = plural(days, "day") }
            return Conversions(source: trimmed(g[0]), results: [said])
        }
        return nil
    }

    // MARK: Money: pay, loans, tax inside a price, unit prices, changes

    /// Whole numbers grouped the Indian way: 1,23,45,678.
    static func indianGrouped(_ n: Double) -> String {
        let whole = String(format: "%.0f", n.rounded())
        guard whole.count > 3 else { return whole }
        var head = String(whole.dropLast(3)), groups: [String] = []
        while head.count > 2 { groups.insert(String(head.suffix(2)), at: 0); head = String(head.dropLast(2)) }
        if !head.isEmpty { groups.insert(head, at: 0) }
        return groups.joined(separator: ",") + "," + whole.suffix(3)
    }

    /// Money for pay and loans: cents under a hundred, whole above, rupees
    /// grouped in lakhs.
    private static func wholeMoney(_ n: Double, _ symbol: String) -> String {
        if n < 100 { return billMoney(n, symbol) }
        return symbol == "₹" ? "₹" + indianGrouped(n) : billMoney(n.rounded(), symbol)
    }

    /// One decimal at most: 54.1, 1.2, 3.
    private static func oneDecimal(_ n: Double) -> String {
        let r = (n * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    /// Money said short: "$383k", "$1.2M", "₹54.1 lakh".
    private static func shortMoney(_ n: Double, _ symbol: String) -> String {
        if symbol == "₹" {
            if n >= 1e7 { return "₹" + oneDecimal(n / 1e7) + " crore" }
            if n >= 1e5 { return "₹" + oneDecimal(n / 1e5) + " lakh" }
            return wholeMoney(n, symbol)
        }
        if n >= 1e6 { return symbol + oneDecimal(n / 1e6) + "M" }
        if n >= 1e4 { return symbol + String(Int((n / 1e3).rounded())) + "k" }
        return wholeMoney(n, symbol)
    }

    private static let payWords = #"\b(?:pay|pays|paid|paying|rate|salary|wage|wages|earn|earns|earning|earned|make|makes|making|charge|charges|charging|offer|offered|offering|job|gig|freelance|contract|income|hourly|ctc|package)\b"#

    /// "$45/hr" → $93,600/yr · $7,800/mo (40 hours a week); "$120k a year"
    /// → $57.69/hr · $10,000/mo; "18 LPA" → ₹1,50,000/mo. Without a currency
    /// sign the message has to be about pay ("earning 50k a month" is not a
    /// rate the strip needs to restate).
    static func payRate(in text: String) -> Conversions? {
        var about = text.range(of: payWords, options: [.regularExpression, .caseInsensitive]) != nil
        // A trailing "hourly", "monthly", "annually" asks which way to say it.
        var text = text
        if let w = firstMatch(#"\s+(?:in\s+|as\s+)?(?:hourly|monthly|annually|yearly|per\s+month|a\s+month)\??\s?$"#, in: text), let tailWord = w[0],
           text.range(of: #"(?:/\s*|per\s+|an?\s+)(?:hr|hour|h|yr|year|annum)\s+\S+\??\s?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            text = String(text.dropLast(tailWord.count))
            about = true   // asking it "annually" is talking pay
        }
        if let g = firstMatch(#"(?<![\w.,])([$€£₹¥])?\s?(\d{1,4}(?:\.\d{1,2})?)\s*(?:/\s*(?:hr|hour|h)|an?\s+hour|per\s+hour|hourly)"# + end, in: text),
           let n = Double(g[2] ?? ""), n > 0, g[1] != nil || about {
            let s = g[1] ?? "", year = n * 2080
            return Conversions(source: trimmed(g[0]), results: ["\(wholeMoney(year, s))/yr", "\(wholeMoney(year / 12, s))/mo"])
        }
        if let g = firstMatch(#"(?<![\w.,])([$€£₹¥])?\s?(\d{1,3}(?:,\d{2,3})+|\d+(?:\.\d+)?)\s*(k|m)?\s*(?:/\s*(?:yr|year|y|annum)|(?:a|per)\s+(?:year|annum)|p\.?\s?a\.?|annually|yearly)"# + end, in: text),
           let base = number(g[2]) {
            let scale = (g[3] ?? "").lowercased()
            let year = base * (scale == "k" ? 1e3 : scale == "m" ? 1e6 : 1)
            guard year >= 1000, g[1] != nil || about else { return nil }
            let s = g[1] ?? ""
            return Conversions(source: trimmed(g[0]), results: ["\(wholeMoney(year / 2080, s))/hr", "\(wholeMoney(year / 12, s))/mo"])
        }
        if let g = firstMatch(#"(?<![\w.,])(\d{1,3}(?:\.\d{1,2})?)\s*(?:lpa|l\.p\.a\.?|lakhs?\s+(?:per\s+annum|a\s+year|p\.?a\.?))"# + end, in: text),
           let lakhs = Double(g[1] ?? ""), lakhs > 0 {
            let year = lakhs * 1e5
            return Conversions(source: trimmed(g[0]), results: ["\(wholeMoney(year / 12, "₹"))/mo", "\(wholeMoney(year / 2080, "₹"))/hr"])
        }
        return nil
    }

    private static let scaleWords: [String: Double] = [
        "k": 1e3, "m": 1e6, "mn": 1e6, "million": 1e6, "b": 1e9, "bn": 1e9, "billion": 1e9,
        "l": 1e5, "lakh": 1e5, "lakhs": 1e5, "lac": 1e5, "lacs": 1e5, "cr": 1e7, "crore": 1e7, "crores": 1e7,
    ]
    /// An amount with its sign and its size word: "$300k", "50 lakh". Three groups.
    private static let scaledAmount = #"([$€£₹¥])?\s?(\d{1,3}(?:,\d{2,3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(k|m|mn|million|b|bn|billion|l|lakhs?|lacs?|cr|crores?)?"#

    /// "$300k mortgage at 6.5% for 30 years" → $1,896/mo · $383k interest;
    /// "50 lakh home loan @ 8.5% 20 years" → ₹43,391/mo; "10k at 7% for 10
    /// years" → $19,672 · +$9,672 (grown once a year).
    static func loan(in text: String) -> Conversions? {
        let rate = #"(\d{1,2}(?:\.\d{1,3})?)\s*%"#
        let term = #"(\d{1,3})\s*(years?|yrs?|y|months?|mos?)"#
        let kinds = #"(?:home\s+|car\s+|auto\s+|personal\s+|student\s+|education\s+)?(?:mortgage|loan|emi)"#
        let borrowing = text.range(of: #"\b(?:mortgage|loan|emi|borrow\w*|owe|debt)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let patterns: [(String, Bool)] = [
            (#"\b"# + kinds + #"\s+(?:of\s+|for\s+|on\s+)?"# + scaledAmount + #"\s*(?:at|@)\s*"# + rate + #"\s*(?:for|over)?\s*"# + term + end, true),
            (#"(?<![\w.,])"# + scaledAmount + #"\s+"# + kinds + #"\s*(?:at|@)?\s*"# + rate + #"\s*(?:for|over)?\s*"# + term + end, true),
            (#"(?<![\w.,])"# + scaledAmount + #"\s*(?:at|@)\s*"# + rate + #"\s*(?:for|over)\s*"# + term + end, false),
            (#"\b(?:compound(?:ed)?|invest(?:ed)?|grow)\s+(?:of\s+)?"# + scaledAmount + #"\s*(?:at|@)?\s*"# + rate + #"\s*(?:for|over)?\s*"# + term + end, false),
        ]
        for (p, borrowed) in patterns {
            guard borrowed || !borrowing, let g = firstMatch(p, in: text), let base = number(g[2]) else { continue }
            let size = (g[3] ?? "").lowercased()
            let principal = base * (scaleWords[size] ?? 1)
            guard let r = Double(g[4] ?? ""), r > 0, r <= 50, let t = Double(g[5] ?? ""), t > 0, principal >= 100 else { continue }
            // Lakh and crore are rupees, said or not.
            let s = g[1] ?? (["l", "lakh", "lakhs", "lac", "lacs", "cr", "crore", "crores"].contains(size) ? "₹" : "")
            let inMonths = (g[6] ?? "").lowercased().hasPrefix("m")
            if borrowed {
                let n = inMonths ? t : t * 12
                guard n <= 600 else { continue }
                let i = r / 100 / 12
                let pay = principal * i / (1 - pow(1 + i, -n))
                return Conversions(source: trimmed(g[0]), results: ["\(wholeMoney(pay, s))/mo", "\(shortMoney(pay * n - principal, s)) interest"])
            }
            guard !inMonths, t <= 60 else { continue }
            let total = principal * pow(1 + r / 100, t)
            return Conversions(source: trimmed(g[0]), results: [wholeMoney(total, s), "+" + wholeMoney(total - principal, s)])
        }
        return nil
    }

    private static let vatRates: [String: Double] = [
        "GB": 20, "IE": 23, "DE": 19, "AT": 20, "FR": 20, "IT": 22, "ES": 21, "NL": 21, "BE": 21, "PT": 23, "LU": 17,
        "FI": 25.5, "SE": 25, "DK": 25, "NO": 25, "PL": 23, "CH": 8.1, "AE": 5, "SA": 15, "ZA": 15,
    ]
    private static let gstRates: [String: Double] = ["AU": 10, "NZ": 15, "SG": 9]
    private static let euroRegions: Set<String> = ["IE", "DE", "AT", "FR", "IT", "ES", "NL", "BE", "PT", "LU", "FI"]

    /// "£120 inc VAT" → £100 + £20 VAT; "€99 inkl. MwSt" at the rate where
    /// the phone is; "₹1,180 incl 18% GST". Where the rate depends on what
    /// is bought (India's GST, a US sales tax) it has to be typed.
    static func taxInside(in text: String, region: String?) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.,])(?:([$€£₹])\s?"# + amt + #"|"# + amt + #"\s?([$€£₹])|"# + amt + #")\s*(?:inc\.?|incl\.?|including|inkl\.?|inclusive\s+of|incl\.?\s+of)\s*(?:(\d{1,2}(?:\.\d+)?)\s*%\s*)?(vat|gst|mwst|tva|iva|btw|moms|tax)"# + end, in: text),
              let gross = number(g[2] ?? g[3] ?? g[5]), gross > 0, let word = g[7]?.lowercased() else { return nil }
        let symbol = g[1] ?? g[4] ?? ""
        let r = region?.uppercased() ?? ""
        var rate = Double(g[6] ?? "")
        if rate == nil, word != "tax" {
            if word == "gst" { rate = symbol.isEmpty || symbol == "$" ? gstRates[r] : nil }
            else if symbol == "£" { rate = 20 }
            else if symbol == "€" { rate = euroRegions.contains(r) ? vatRates[r] : nil }
            else if symbol.isEmpty { rate = vatRates[r] }
        }
        guard let rate, rate > 0, rate < 100 else { return nil }
        let net = gross / (1 + rate / 100)
        let label = ["vat": "VAT", "gst": "GST", "mwst": "MwSt", "tva": "TVA", "iva": "IVA", "btw": "BTW"][word] ?? word
        return Conversions(source: trimmed(g[0]), results: ["\(billMoney(net, symbol)) + \(billMoney(gross - net, symbol)) \(label)"])
    }

    /// "$12.99 for 24" → $0.54 each; "3 for $10" → $3.33 each; "₹300 for
    /// 5 kg" → ₹60/kg; "$4 for 500 g" → $8/kg · $0.80/100 g. A price is
    /// needed: "table for 4" is a booking.
    static func unitPrice(in text: String) -> Conversions? {
        let weights = #"(kg|kgs|g|gm|gms|grams?|lbs?|pounds?|oz|l|litres?|liters?|ml)"#
        var price: Double?, quantity: Double?, unit: String?, symbol = "", source = ""
        if let g = firstMatch(#"([$€£₹¥])\s?"# + amt + #"\s+(?:for|per)\s+(\d+(?:\.\d+)?)\s*"# + weights + end, in: text) {
            (symbol, price, quantity, unit, source) = (g[1] ?? "", number(g[2]), Double(g[3] ?? ""), g[4], trimmed(g[0]))
        } else if let g = firstMatch(#"(?<![\w.,])(\d+(?:\.\d+)?)\s*"# + weights + #"\s+for\s+([$€£₹¥])\s?"# + amt + end, in: text) {
            (symbol, price, quantity, unit, source) = (g[3] ?? "", number(g[4]), Double(g[1] ?? ""), g[2], trimmed(g[0]))
        } else if let g = firstMatch(#"([$€£₹¥])\s?"# + amt + #"\s+for\s+(?:a\s+)?(\d{1,4}|dozen|pair)\s*(?:pack|pk|pcs|pieces|count|ct|items|units|cans|bottles)?"# + end, in: text) {
            let q = (g[3] ?? "").lowercased()
            (symbol, price, quantity, source) = (g[1] ?? "", number(g[2]), q == "dozen" ? 12 : q == "pair" ? 2 : Double(q), trimmed(g[0]))
        } else if let g = firstMatch(#"(?<![\w.,$€£₹¥])(\d{1,4})\s+for\s+([$€£₹¥])\s?"# + amt + end, in: text) {
            (symbol, price, quantity, source) = (g[2] ?? "", number(g[3]), Double(g[1] ?? ""), trimmed(g[0]))
        } else if let g = firstMatch(#"(?<![\w.,])(\d+(?:\.\d+)?)\s*"# + weights + #"\s+for\s+"# + amt + end, in: text) {
            // "1.5kg for 9": a weight for a price, the sign left off (2026-10-08 probe).
            (price, quantity, unit, source) = (number(g[3]), Double(g[1] ?? ""), g[2], trimmed(g[0]))
        } else if let g = firstMatch(#"(?<![\w.,$€£₹¥])(\d{1,3})\s*[- ]?(?:pack|pk|pcs|pieces|count|ct|cans|bottles)\s+(?:for|at|is|=)\s+([$€£₹¥])?\s?"# + amt + end, in: text) {
            // "3 pack for 12.99".
            (symbol, price, quantity, source) = (g[2] ?? "", number(g[3]), Double(g[1] ?? ""), trimmed(g[0]))
        }
        guard let price, let quantity, price > 0, quantity > 0 else { return nil }
        func per(_ amount: Double, _ label: String) -> String { "\(billMoney(price / amount, symbol))\(label)" }
        guard let u = unit?.lowercased() else {
            guard quantity >= 2, price / quantity >= 0.01 else { return nil }
            return Conversions(source: source, results: [per(quantity, " each")])
        }
        let results: [String]
        switch u {
        case "kg", "kgs": results = [per(quantity, "/kg")]
        case "g", "gm", "gms", "gram", "grams": results = [per(quantity / 1000, "/kg"), per(quantity / 100, "/100 g")]
        case "lb", "lbs", "pound", "pounds": results = [per(quantity, "/lb"), per(quantity * 0.45359237, "/kg")]
        case "oz": results = [per(quantity, "/oz"), per(quantity * 28.349523125 / 100, "/100 g")]
        case "ml": results = [per(quantity / 1000, "/L"), per(quantity / 100, "/100 ml")]
        default: results = [per(quantity, "/L")]
        }
        return Conversions(source: source, results: results)
    }

    /// "+37.5%", "-20%": one decimal at most.
    private static func percentChange(_ p: Double) -> String { (p > 0 ? "+" : "-") + oneDecimal(abs(p)) + "%" }

    /// "went from $40 to $55" → +37.5% · +$15; "followers jumped from 1.2k
    /// to 3k" → +150%. A change needs its verb, or money on both sides:
    /// "from 9 to 5" is a working day.
    static func change(in text: String) -> Conversions? {
        let side = #"([$€£₹¥])?\s?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(k|m)?"#
        let verbs = #"(?:went|gone|grew|grown|rose|risen|jumped|dropped|fell|fallen|increased|decreased|climbed|raised|cut|surged|slipped|declined|spiked|up|down)"#
        let moved = firstMatch(#"\b"# + verbs + #"\s+(?:from\s+)?"# + side + #"\s+to\s+"# + side + end, in: text)
        let priced = firstMatch(#"\bfrom\s+([$€£₹¥])\s?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(k|m)?\s+to\s+"# + side + end, in: text)
        guard let g = moved ?? priced else { return nil }
        func scale(_ s: String?) -> Double { s?.lowercased() == "k" ? 1e3 : s?.lowercased() == "m" ? 1e6 : 1 }
        guard let a0 = number(g[2]), let b0 = number(g[5]) else { return nil }
        let a = a0 * scale(g[3]), b = b0 * scale(g[6])
        guard a > 0, a != b else { return nil }
        var results = [percentChange((b - a) / a * 100)]
        if let s = g[1] ?? g[4] { results.append((b > a ? "+" : "-") + billMoney(abs(b - a), s)) }
        return Conversions(source: trimmed(g[0]), results: results)
    }

    /// "aspect ratio 1920x1080" → 16:9; "2560x1080 ratio" → ≈21:9. The
    /// word is needed: "10x20 cm" is a size.
    static func ratio(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\b(?:aspect(?:\s+ratio)?|ratio|resolution|res)\s*(?:of\s+|is\s+|:\s*|=\s*)?(\d{1,5})\s*[x×:]\s*(\d{1,5})"# + end, in: text)
                ?? firstMatch(#"(?<![\w.])(\d{1,5})\s*[x×]\s*(\d{1,5})\s+(?:aspect(?:\s+ratio)?|ratio|resolution)"# + end, in: text),
              let a = Int(g[1] ?? ""), let b = Int(g[2] ?? ""), a > 0, b > 0 else { return nil }
        func gcd(_ x: Int, _ y: Int) -> Int { y == 0 ? x : gcd(y, x % y) }
        let d = gcd(a, b), x = a / d, y = b / d
        let said: String
        if x == 8, y == 5 { said = "16:10" }
        else if x == 5, y == 8 { said = "10:16" }
        else if x <= 21, y <= 21 {
            // "16:9" typed as 16:9 says nothing.
            guard x != a || y != b else { return nil }
            said = "\(x):\(y)"
        } else {
            let value = Double(a) / Double(b)
            let named: [(Int, Int)] = [(1, 1), (5, 4), (4, 3), (3, 2), (16, 10), (16, 9), (2, 1), (21, 9), (32, 9),
                                       (4, 5), (3, 4), (2, 3), (10, 16), (9, 16), (9, 21)]
            let near = named.min { abs(Double($0.0) / Double($0.1) - value) < abs(Double($1.0) / Double($1.1) - value) }!
            if abs(Double(near.0) / Double(near.1) - value) / value < 0.03 { said = "≈\(near.0):\(near.1)" }
            else if value >= 1 { said = String(format: "%.2f:1", value) }
            else { said = String(format: "1:%.2f", 1 / value) }
        }
        return Conversions(source: trimmed(g[0]), results: [said])
    }

    // MARK: Cooking

    /// Grams in a US cup, from King Arthur Baking's ingredient weight chart.
    private static let cupGrams: [String: Double] = [
        "all-purpose flour": 120, "all purpose flour": 120, "plain flour": 120, "ap flour": 120, "bread flour": 120,
        "cake flour": 120, "self-raising flour": 120, "self raising flour": 120, "self-rising flour": 120, "flour": 120,
        "maida": 120, "whole wheat flour": 113, "wholemeal flour": 113, "atta": 113, "almond flour": 96, "almond meal": 96,
        "semolina": 163, "rice flour": 142, "cornmeal": 138, "cornstarch": 112, "corn starch": 112, "cornflour": 112,
        "brown sugar": 213, "powdered sugar": 113, "icing sugar": 113, "confectioners sugar": 113,
        "confectioners' sugar": 113, "sugar": 198, "caster sugar": 198, "butter": 226.8, "honey": 336,
        "maple syrup": 312, "corn syrup": 312, "molasses": 340, "cocoa powder": 84, "cocoa": 84, "oats": 89,
        "rolled oats": 89, "oatmeal": 89, "rice": 198, "quinoa": 177, "chocolate chips": 170, "chocolate": 170,
        "peanut butter": 270, "cheese": 113, "cheddar": 113, "mozzarella": 113, "parmesan": 100, "cream cheese": 227,
        "sour cream": 227, "yogurt": 227, "yoghurt": 227, "ricotta": 227, "raisins": 149, "walnuts": 113, "pecans": 105,
        "almonds": 142, "coconut": 85, "breadcrumbs": 112, "bread crumbs": 112, "salt": 288, "baking powder": 192,
        "baking soda": 288, "bicarbonate of soda": 288, "yeast": 144, "banana": 227, "pumpkin puree": 227,
        "applesauce": 255,
    ]
    /// Poured by volume: millilitres say it best.
    private static let pouredLiquids: Set<String> = [
        "milk", "water", "cream", "heavy cream", "whipping cream", "buttermilk", "oil", "olive oil", "vegetable oil",
        "vinegar", "juice", "lemon juice", "lime juice", "orange juice", "stock", "broth", "wine", "coconut milk",
        "vanilla", "vanilla extract", "soy sauce",
    ]
    private static let kitchenWords = #"(?:(?:packed|sifted|softened|melted|unsalted|salted|granulated|white|light|dark|cold|warm|chopped|grated|shredded|mashed|dried|fresh|plain|raw|uncooked|dry|fine|ground|light\s+brown|dark\s+brown)\s+)*"#
    private static let ingredientNames: String = (Array(cupGrams.keys) + Array(pouredLiquids))
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")

    /// Gas marks with their oven temperatures in °C and °F.
    private static let gasMarks: [(mark: String, c: Int, f: Int)] = [
        ("¼", 110, 225), ("½", 120, 250), ("1", 140, 275), ("2", 150, 300), ("3", 170, 325), ("4", 180, 350),
        ("5", 190, 375), ("6", 200, 400), ("7", 220, 425), ("8", 230, 450), ("9", 240, 475),
    ]

    /// Grams or ounces as a cook writes them: "240 g", "4 g", "1.5 g".
    private static func gramsText(_ g: Double) -> String {
        g >= 10 ? "\(Int(g.rounded())) g" : "\(oneDecimal(g)) g"
    }

    /// "1⅔ cups", "¾ cup", "3 tbsp", "½ tsp": the nearest a cup measures.
    private static func cupsText(grams: Double, perCup: Double) -> String {
        func nice(_ x: Double) -> (Int, String) {
            let parts: [(Double, String)] = [(0, ""), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾"), (1, "")]
            var whole = Int(x.rounded(.down))
            let near = parts.min { abs($0.0 - (x - Double(whole))) < abs($1.0 - (x - Double(whole))) }!
            if near.0 == 1 { whole += 1 }
            return (whole, near.0 == 1 ? "" : near.1)
        }
        let cups = grams / perCup
        let (w, f): (Int, String)
        let unit: String
        if cups >= 0.25 { (w, f) = nice(cups); unit = "cup" }
        else if cups * 16 >= 1 { (w, f) = nice(cups * 16); unit = "tbsp" }
        else { (w, f) = nice(cups * 48); unit = "tsp" }
        let amount = (w > 0 ? "\(w)" : "") + f
        let plural = unit == "cup" && (w > 1 || (w == 1 && !f.isEmpty)) ? "cups" : unit
        return "\(amount.isEmpty ? "0" : amount) \(plural)"
    }

    /// "2 cups flour" → 240 g · 8.47 oz (King Arthur's weights); "1 cup
    /// milk" → 237 ml; in the US "200 g flour" → 1⅔ cups; "gas mark 4" →
    /// 180°C · 350°F; "bake at 350" → 180°C · gas mark 4.
    static func cooking(in text: String, region: String?) -> Conversions? {
        let units = #"(cups?|c\.|tbsps?|tablespoons?|tbs|tbl|tsps?|teaspoons?|sticks?)"#
        if let g = firstMatch(#"(?<![\w.,/])"# + stripAmount + #"\s*"# + units + #"\s+(?:of\s+)?"# + kitchenWords + #"("# + ingredientNames + #")"# + end, in: text),
           let n = g[1].flatMap({ amount($0) }), n > 0, let u = g[2]?.lowercased(), let name = g[3]?.lowercased() {
            let cups: Double
            if u.hasPrefix("c") { cups = n }
            else if u.hasPrefix("tb") || u.hasPrefix("tablespoon") { cups = n / 16 }
            else if u.hasPrefix("ts") || u.hasPrefix("teaspoon") { cups = n / 48 }
            else { guard name == "butter" else { return nil }; cups = n / 2 }
            if pouredLiquids.contains(name) {
                let ml = cups * 236.5882365
                return Conversions(source: trimmed(g[0]), results: [ml < 1000 ? stripNamed(ml, "ml") : stripNamed(ml / 1000, "litre")])
            }
            guard let perCup = cupGrams[name] else { return nil }
            let grams = cups * perCup
            return Conversions(source: trimmed(g[0]), results: [gramsText(grams), stripNamed(grams / 28.349523125, "oz")])
        }
        if region?.uppercased() == "US",
           let g = firstMatch(#"(?<![\w.,/])(\d+(?:\.\d+)?)\s*(g|gm|gms|grams?|kg|kgs)\s+(?:of\s+)?"# + kitchenWords + #"("# + ingredientNames + #")"# + end, in: text),
           let n = Double(g[1] ?? ""), n > 0, let name = g[3]?.lowercased(), let perCup = cupGrams[name] {
            let grams = (g[2] ?? "").lowercased().hasPrefix("k") ? n * 1000 : n
            return Conversions(source: trimmed(g[0]), results: [cupsText(grams: grams, perCup: perCup), stripNamed(grams / 28.349523125, "oz")])
        }
        if let g = firstMatch(#"\bgas\s+mark\s+(1/4|1/2|¼|½|[1-9])"# + end, in: text) {
            let mark = (g[1] ?? "").replacingOccurrences(of: "1/4", with: "¼").replacingOccurrences(of: "1/2", with: "½")
            guard let gm = gasMarks.first(where: { $0.mark == mark }) else { return nil }
            return Conversions(source: trimmed(g[0]), results: ["\(gm.c)°C", "\(gm.f)°F"])
        }
        if let g = firstMatch(#"\b(?:oven|bake|baking|preheat(?:\s+(?:the\s+)?oven)?|roast|roasting)\s+(?:it\s+)?(?:at|to|on)\s+(\d{2,3})\s*(?:degrees?|deg|°)?"# + end, in: text),
           let v = Int(g[1] ?? "") {
            // 300 and up is Fahrenheit, 250 and under Celsius; between, the
            // scale the phone's country bakes in.
            let fahrenheit = v >= 300 || (v > 250 && ["US", "BS", "BZ", "KY", "PR", "PW"].contains(region?.uppercased() ?? ""))
            func five(_ x: Double) -> Int { Int((x / 5).rounded()) * 5 }
            if fahrenheit {
                guard v <= 550 else { return nil }
                let gm = gasMarks.first { $0.f == v }
                let c = gm?.c ?? five(Double(v - 32) * 5 / 9)
                return Conversions(source: trimmed(g[0]), results: ["\(c)°C"] + (gm.map { ["gas mark \($0.mark)"] } ?? []))
            }
            guard v >= 90 else { return nil }
            let gm = gasMarks.first { $0.c == v }
            let f = gm?.f ?? five(Double(v) * 9 / 5 + 32)
            return Conversions(source: trimmed(g[0]), results: ["\(f)°F"] + (gm.map { ["gas mark \($0.mark)"] } ?? []))
        }
        return nil
    }

    // MARK: Fuel, pace and downloads

    /// "30 mpg" → 7.84 L/100 km · 12.8 km/L; "6.5 L/100km" → 36.2 mpg;
    /// "15 kmpl" → 35.3 mpg. Imperial gallons in Britain.
    static func fuel(in text: String, region: String?) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.])(\d{1,3}(?:\.\d+)?)\s*(mpg|miles\s+per\s+gallon|l/100\s?km|l\s+per\s+100\s?km|lit(?:re|er)s?\s+per\s+100\s?km|km/l|kmpl|km\s+per\s+lit(?:re|er)|kpl)"# + end, in: text),
              let n = Double(g[1] ?? ""), n > 0, let u = g[2]?.lowercased() else { return nil }
        let uk = region?.uppercased() == "GB"
        let litresTimesMpg = uk ? 282.480936 : 235.214583
        let kmlPerMpg = uk ? 0.35400619 : 0.42514371
        let results: [String]
        if u.hasPrefix("mpg") || u.hasPrefix("miles") {
            results = ["\(stripNumber(litresTimesMpg / n)) L/100 km", "\(stripNumber(n * kmlPerMpg)) km/L"]
        } else if u.hasPrefix("l") {
            results = ["\(stripNumber(litresTimesMpg / n)) mpg", "\(stripNumber(100 / n)) km/L"]
        } else {
            results = ["\(stripNumber(n / kmlPerMpg)) mpg", "\(stripNumber(100 / n)) L/100 km"]
        }
        return Conversions(source: trimmed(g[0]), results: results)
    }

    /// "5:15", "1:05:30": minutes and seconds, hours when there are some.
    private static func durationClock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let pad = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
        return s >= 3600 ? "\(s / 3600):\(pad(s % 3600 / 60)):\(pad(s % 60))" : "\(s / 60):\(pad(s % 60))"
    }

    /// "ran 10k in 52:30" → 5:15 /km · 8:27 /mi; "half marathon in 1:45:00";
    /// "rode 40 km in 1h 20m" → 30 km/h · 18.6 mph; "5:30/km" → 8:51 /mi ·
    /// 27:30 for 5k. A time is needed: "run 5k this morning" is a plan.
    static func pace(in text: String) -> Conversions? {
        let dist = #"(half[\s-]?marathon|full\s+marathon|marathon|half|(\d{1,3}(?:\.\d+)?)\s*(k|km|kms|kilomet(?:er|re)s?|mi|miles?))"#
        let time = #"(?:(\d{1,2}):([0-5]\d)(?::([0-5]\d))?|(\d{1,3})\s*(?:min|mins|minutes)|(\d)\s*(?:h|hr|hrs|hours?)\s*(\d{1,2})\s*(?:m|min|mins)?)"#
        if let g = firstMatch(#"\b(?:(ran|run|running|did|finished|done|completed|walked|cycled|rode|biked)\s+)?(?:a\s+|the\s+|my\s+)?"# + dist + #"\s+in\s+"# + time + end, in: text) {
            let d = (g[2] ?? "").lowercased()
            var km: Double
            if d.hasPrefix("half") { km = 21.0975 }
            else if d.contains("marathon") { km = 42.195 }
            else if let n = Double(g[3] ?? "") { km = (g[4] ?? "").lowercased().hasPrefix("mi") ? n * 1.609344 : n }
            else { return nil }
            guard km > 0 else { return nil }
            let riding = ["cycled", "rode", "biked"].contains((g[1] ?? "").lowercased())
            var options: [Double] = []
            if let a = Double(g[5] ?? ""), let b = Double(g[6] ?? "") {
                if let c = Double(g[7] ?? "") { options = [a * 3600 + b * 60 + c] }
                else { options = km >= 21 || riding ? [a * 3600 + b * 60, a * 60 + b] : [a * 60 + b, a * 3600 + b * 60] }
            } else if let m = Double(g[8] ?? "") { options = [m * 60] }
            else if let h = Double(g[9] ?? ""), let m = Double(g[10] ?? "") { options = [h * 3600 + m * 60] }
            if riding {
                guard let secs = options.first(where: { km / ($0 / 3600) >= 5 && km / ($0 / 3600) <= 80 }) else { return nil }
                let kmh = km / (secs / 3600)
                return Conversions(source: trimmed(g[0]), results: ["\(stripNumber(kmh)) km/h", "\(stripNumber(kmh / 1.609344)) mph"])
            }
            guard let secs = options.first(where: { $0 / km >= 120 && $0 / km <= 1200 }) else { return nil }
            return Conversions(source: trimmed(g[0]), results: [durationClock(secs / km) + " /km", durationClock(secs / km * 1.609344) + " /mi"])
        }
        if let g = firstMatch(#"(?<![\d:])(\d{1,2}):([0-5]\d)\s*(?:/\s*|per\s+|a\s+)(km|k|kilomet(?:er|re)s?|mi|miles?)"# + end, in: text),
           let m = Double(g[1] ?? ""), let s = Double(g[2] ?? "") {
            let mile = (g[3] ?? "").lowercased().hasPrefix("mi")
            let perKm = mile ? (m * 60 + s) / 1.609344 : m * 60 + s
            guard perKm >= 120, perKm <= 1200 else { return nil }
            let other = mile ? durationClock(perKm) + " /km" : durationClock(perKm * 1.609344) + " /mi"
            return Conversions(source: trimmed(g[0]), results: [other, durationClock(perKm * 5) + " for 5k"])
        }
        return nil
    }

    /// "12 s", "6 min 16 s", "1 h 23 min", "2 days 3 h".
    private static func durationWords(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1440 { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
        let hours = Int((seconds / 3600).rounded())
        return "\(hours / 24) day\(hours / 24 == 1 ? "" : "s")" + (hours % 24 > 0 ? " \(hours % 24) h" : "")
    }

    /// "4.7 GB at 100 Mbps" → ≈ 6 min 16 s. "Mbps" and "Mb/s" are bits,
    /// "MB/s" and "MBps" bytes (and "mb/s", as download managers write it).
    static func download(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.])(\d+(?:\.\d+)?)\s*(kb|mb|gb|tb)\s+(?:at|@|on|with|over|via)\s+(\d+(?:\.\d+)?)\s*(kbps|mbps|gbps|kb/s|mb/s|gb/s|kbit/s|mbit/s|gbit/s)"# + end, in: text),
              let size = Double(g[1] ?? ""), let speed = Double(g[3] ?? ""), speed > 0,
              let sizeUnit = g[2]?.lowercased(), let speedUnit = g[4], speedUnit.count >= 4 else { return nil }
        let bytes = size * (["kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12][sizeUnit] ?? 1)
        let prefix = speedUnit.lowercased().prefix(1)
        let scale = prefix == "k" ? 1e3 : prefix == "m" ? 1e6 : 1e9
        let second = speedUnit[speedUnit.index(after: speedUnit.startIndex)]
        let inBytes = !speedUnit.lowercased().contains("bit")
            && (second == "B" || (speedUnit.hasSuffix("/s") && speedUnit == speedUnit.lowercased()))
        let seconds = bytes * 8 / (speed * scale * (inBytes ? 8 : 1))
        guard seconds >= 1, seconds < 30 * 86400 else { return nil }
        return Conversions(source: trimmed(g[0]), results: ["≈ " + durationWords(seconds)])
    }

    // MARK: Shorthand with blanks

    /// A shorthand's text with its blanks filled, as Raycast's snippets
    /// have them: {date}, {date+2d}, {date-1w}, {tomorrow}, {yesterday},
    /// {time}, {day}, {clipboard} and {cursor}, where typing goes on (the
    /// first one). `back` is how far before the end the cursor ends, in
    /// UTF-16 units as the host counts them. A blank it doesn't know stays.
    static func fillIn(_ template: String, now: Date = Date(), here: TimeZone = .current,
                       region: String? = Locale.current.region?.identifier,
                       clipboard: () -> String? = { nil }) -> (text: String, back: Int) {
        guard template.contains("{"),
              let re = try? NSRegularExpression(pattern: #"\{\s*(date|time|day|tomorrow|yesterday|clipboard|cursor)(?:\s*([+-])\s*(\d{1,3})\s*([dw]))?\s*\}"#,
                                                options: [.caseInsensitive]) else { return (template, 0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        let ns = template as NSString
        var out = "", cursor: String.Index?, last = 0
        for m in re.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            last = m.range.location + m.range.length
            func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            switch (group(1) ?? "").lowercased() {
            case "cursor":
                if cursor == nil { cursor = out.endIndex }
            case "clipboard":
                out += clipboard() ?? ""
            case "time":
                f.dateFormat = "h:mm a"
                out += f.string(from: now).replacingOccurrences(of: "\u{202F}", with: " ")
            case "day":
                f.dateFormat = "EEEE"
                out += f.string(from: now)
            case let name:
                var days = name == "tomorrow" ? 1 : name == "yesterday" ? -1 : 0
                if let n = group(3).flatMap({ Int($0) }) {
                    days += (group(2) == "-" ? -1 : 1) * n * ((group(4) ?? "").lowercased() == "w" ? 7 : 1)
                }
                let date = cal.date(byAdding: .day, value: days, to: now) ?? now
                out += dayName(date, now: now, here: here, region: region)
            }
        }
        out += ns.substring(from: last)
        guard let cursor else { return (out, 0) }
        return (out, out[cursor...].utf16.count)
    }

    // MARK: A coin, a die, a pick

    /// The keyboard's draw for the next coin, die or pick: the same until
    /// one is used, so the answer can't change under the finger.
    static var luck: UInt64 = UInt64.random(in: 1...UInt64.max)

    /// A number below n from what was asked and the draw (FNV-1a, then
    /// SplitMix64: the same on both keyboards).
    static func lucky(_ asked: String, _ n: Int, salt: UInt64 = 0) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in asked.lowercased().utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        var z = (h ^ luck ^ salt) &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Int(z % UInt64(n))
    }

    /// "flip a coin" → 🪙 Heads; "roll a die" → 🎲 4, "roll two dice" →
    /// 🎲 3 + 5 = 8, "roll a d20"; "pick a number between 1 and 10" → 🎲 7;
    /// "pick one: pizza, sushi or tacos" → 🎯 sushi; rock, paper, scissors.
    /// A tap adds it after; the next draw is new.
    static func luckAnswer(in text: String) -> Conversions? {
        func said(_ g: [String?], _ result: String) -> Conversions {
            Conversions(source: trimmed(g[0]), results: [result], hows: [.after])
        }
        if let g = firstMatch(#"\b(?:flip\s+a\s+coin|coin\s+(?:flip|toss)|toss\s+a\s+coin|heads\s+or\s+tails)"# + end, in: text) {
            return said(g, lucky("coin", 2) == 0 ? "🪙 Heads" : "🪙 Tails")
        }
        if let g = firstMatch(#"\b(?:rock\s*,?\s*paper\s*,?\s*(?:or\s+|and\s+)?scissors|rps)"# + end, in: text) {
            return said(g, ["✊ Rock", "✋ Paper", "✌️ Scissors"][lucky("rps", 3)])
        }
        if let g = firstMatch(#"\broll\s+(?:(a|an|one|the|two|three|1|2|3)\s+)?(?:dice|die|d(4|6|8|10|12|20|100))"# + end, in: text) {
            let count = ["two": 2, "2": 2, "three": 3, "3": 3][(g[1] ?? "").lowercased()] ?? 1
            let sides = Int(g[2] ?? "") ?? 6
            let rolls = (0..<count).map { lucky("die", sides, salt: UInt64($0)) + 1 }
            return said(g, "🎲 " + (count == 1 ? "\(rolls[0])" : rolls.map(String.init).joined(separator: " + ") + " = \(rolls.reduce(0, +))"))
        }
        if let g = firstMatch(#"\b(?:pick|choose|give\s+me|random)\s+(?:a\s+)?(?:random\s+)?number\s+(?:between|from)\s+(-?\d{1,6})\s+(?:and|to|-)\s+(-?\d{1,6})"# + end, in: text)
            ?? firstMatch(#"\brandom\s+number\s+(-?\d{1,6})\s*(?:-|to)\s*(-?\d{1,6})"# + end, in: text),
           let a = Int(g[1] ?? ""), let b = Int(g[2] ?? ""), a != b {
            let lo = min(a, b), hi = max(a, b)
            return said(g, "🎲 \(lo + lucky("number \(lo) \(hi)", hi - lo + 1))")
        }
        if let g = firstMatch(#"\b(?:pick|choose)\s+(?:one|1|for\s+me|from|between|among)\s*[:\-–]?\s*(.+?)"# + end, in: text)
            ?? firstMatch(#"\bdecide\s+between\s+(.+?)"# + end, in: text),
           let list = g[1] {
            let items = list.replacingOccurrences(of: #"\s*(?:,|/|\bor\b|\band\b|\bvs\.?)\s*"#, with: "\n",
                                                  options: [.regularExpression, .caseInsensitive])
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard items.count >= 2, items.count <= 8,
                  items.allSatisfy({ $0.count <= 40 && $0.split(separator: " ").count <= 5 }) else { return nil }
            return said(g, "🎯 " + items[lucky(items.joined(separator: "|"), items.count)])
        }
        return nil
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
        // Bold to strikethrough first (what Arpit asked for), then the case
        // changes people reach for most, then the fancier letters; Plain last.
        case bold, italic, boldItalic, underline, strike, upper, lower, titleCase, sentenceCase,
             serifBold, script, doubleStruck, monospace, bubble, smallCaps, wide, upsideDown, plain

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
            case .upper: return "UPPERCASE"
            case .lower: return "lowercase"
            case .titleCase: return "Title Case"
            case .sentenceCase: return "Sentence case"
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
        case .upper:
            return base.uppercased()
        case .lower:
            return base.lowercased()
        case .titleCase, .sentenceCase:
            return recased(base, title: style == .titleCase)
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

    /// Words that stay small inside a title.
    private static let smallWords: Set<String> = ["a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "on",
                                                  "at", "to", "by", "of", "in", "up", "as", "is", "vs", "via", "per"]

    /// The first letter in capitals: "(hello" → "(Hello".
    private static func capitalised(_ w: String) -> String {
        guard let i = w.firstIndex(where: \.isLetter) else { return w }
        return String(w[..<i]) + String(w[i]).uppercased() + w[w.index(after: i)...]
    }

    /// Title Case ("The Lord of the Rings": small words stay small inside)
    /// or Sentence case (a capital to start each sentence, and for "I").
    /// A word in capitals ("NASA") stays as it is, unless the whole text
    /// was in capitals: then it was caps lock.
    static func recased(_ text: String, title: Bool) -> String {
        let letters = text.filter(\.isLetter)
        let shouting = !letters.isEmpty && Double(letters.filter(\.isUppercase).count) / Double(letters.count) >= 0.6
        // Words and the space between them, in turn.
        var tokens: [String] = []
        var current = ""
        var inSpace: Bool?
        for ch in text {
            if let was = inSpace, was != ch.isWhitespace { tokens.append(current); current = "" }
            current.append(ch)
            inSpace = ch.isWhitespace
        }
        if !current.isEmpty { tokens.append(current) }
        let words = tokens.indices.filter { !(tokens[$0].first?.isWhitespace ?? true) }
        var startsSentence = true
        var out = ""
        for (i, token) in tokens.enumerated() {
            if token.first?.isWhitespace ?? true {
                if token.contains("\n") { startsSentence = true }
                out += token
                continue
            }
            let acronym = !shouting && token.count > 1 && token == token.uppercased() && token != token.lowercased()
            let lower = token.lowercased()
            var word: String
            if acronym { word = token }
            else if title {
                let inside = i != words.first && i != words.last
                word = inside && smallWords.contains(lower) ? lower : capitalised(lower)
            } else if startsSentence || lower == "i" || lower.hasPrefix("i'") {
                word = capitalised(lower)
            } else {
                word = lower
            }
            if title && startsSentence { word = capitalised(word) }
            out += word
            startsSentence = token.last.map { ".!?".contains($0) } ?? false
        }
        return out
    }

    /// "12 words · 64 characters": what the Style screen says of the text.
    static func textCount(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        let characters = text.count
        return "\(words) word\(words == 1 ? "" : "s") · \(characters) character\(characters == 1 ? "" : "s")"
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
        // Already answered: the strip's own answer went in after it ("whats
        // 15% of 240 = 36", "10 km to miles (6.21 miles)" offered AI answer
        // again, 2026-10-14).
        if body.contains("=") || body.hasSuffix(")") { return nil }
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

// MARK: - More everyday answers (2026-10-08 probe of 150 messages; Smart.kt twins)

extension Smart {

    /// The zone a place or abbreviation names ("tokyo", "ist", "new york").
    private static func namedZone(_ name: String, region: String?) -> TimeZone? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        let r = region?.uppercased()
        var id = zoneNames[key] ?? zoneNames[key + " time"] ?? ""
        if key == "cst", r == "CN" { id = "Asia/Shanghai" }
        if key == "ist", r == "IE" { id = "Europe/Dublin" }
        if key == "ist", r == "IL" { id = "Asia/Jerusalem" }
        return TimeZone(identifier: id)
    }

    private static func placeLabel(_ key: String) -> String {
        key.count <= 4 && zoneNames[key] != nil && !key.contains(" ") ? key.uppercased() : key.capitalized
    }

    /// "time difference with london", "how far ahead is tokyo" → "Tokyo is
    /// 13h ahead" from where the phone is.
    static func timeDifference(in text: String, now: Date = Date(), here: TimeZone = .current,
                               region: String? = Locale.current.region?.identifier) -> Conversions? {
        // "pst to ist", "est vs gmt": how far apart two zones are.
        if let g = firstMatch(#"^\s*(?:what'?s\s+|whats\s+)?([a-z]{2,4})\s+(?:to|vs\.?|versus|and)\s+([a-z]{2,4})(?:\s+(?:time\s+)?difference)?\??\s?$"#, in: text),
           let a = g[1]?.lowercased(), let b = g[2]?.lowercased(), a != b,
           let za = namedZone(a, region: region), let zb = namedZone(b, region: region) {
            let diff = zb.secondsFromGMT(for: now) - za.secondsFromGMT(for: now)
            let mins = abs(diff) / 60
            let gap = mins % 60 == 0 ? "\(mins / 60)h" : "\(mins / 60)h \(mins % 60)m"
            let said = diff == 0 ? "\(b.uppercased()) = \(a.uppercased())" : "\(b.uppercased()) is \(gap) \(diff > 0 ? "ahead of" : "behind") \(a.uppercased())"
            return Conversions(source: trimmed(g[0]), results: [said])
        }
        guard let g = firstMatch(#"\b(?:time\s+(?:difference|diff|gap)\s+(?:with|to|from|for|in|between\s+(?:us|here)\s+and)|how\s+(?:many\s+hours\s+|far\s+)?(?:ahead|behind)\s+is)\s+([a-z][a-z .]{1,30}?)\??\s?$"#, in: text),
              let name = g[1]?.lowercased().trimmingCharacters(in: .whitespaces),
              let there = namedZone(name, region: region) else { return nil }
        let diff = there.secondsFromGMT(for: now) - here.secondsFromGMT(for: now)
        let label = placeLabel(name)
        guard diff != 0 else { return Conversions(source: trimmed(g[0]), results: ["\(label): same time"]) }
        let mins = abs(diff) / 60
        let gap = mins % 60 == 0 ? "\(mins / 60)h" : "\(mins / 60)h \(mins % 60)m"
        return Conversions(source: trimmed(g[0]), results: ["\(label) is \(gap) \(diff > 0 ? "ahead" : "behind")"])
    }

    /// "100f in c", "30 c to f", "-40 celsius in fahrenheit": a temperature
    /// asked for in the other scale, without the degree sign.
    static func degreesAsked(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.])(-?\d{1,4}(?:\.\d+)?)\s*°?\s*(f|c|fahrenheit|celsius|centigrade)(?:\s+oven)?\s+(?:in|to|into|as)\s+°?(c|f|celsius|fahrenheit|centigrade)\??\s?$"#, in: text),
              let v = Double(g[1] ?? ""), let from = g[2]?.lowercased().first, let to = g[3]?.lowercased().first else { return nil }
        let fromF = from == "f", toF = to == "f"
        guard fromF != toF else { return nil }
        let out = toF ? v * 9 / 5 + 32 : (v - 32) * 5 / 9
        return Conversions(source: trimmed(g[0]), results: [oneDecimal(out) + (toF ? "°F" : "°C")])
    }

    /// "5'10", "6’2\"", "5'10 in cm": a height in feet and inches, in cm.
    static func feetInches(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.'’])([3-7])\s*['’]\s*(\d{1,2})\s*(?:"|”|''|’’|in(?:ch(?:es)?)?)?(?:\s+(?:in|to)\s+(?:cm|centimet(?:er|re)s?|m|met(?:er|re)s?))?\??\s?$"#, in: text),
              let ft = Int(g[1] ?? ""), let inch = Int(g[2] ?? ""), inch < 12 else { return nil }
        let cm = Double(ft * 12 + inch) * 2.54
        return Conversions(source: trimmed(g[0]), results: ["\(Int(cm.rounded())) cm", String(format: "%.2f m", cm / 100)])
    }

    /// "bmi 70kg 175cm", "my bmi at 160 lbs and 5'10": weight and height
    /// after "bmi" → BMI 22.9.
    static func bmi(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\bbmi\b(.{3,60})$"#, in: text), let rest = g[1] else { return nil }
        guard let w = firstMatch(#"(\d{2,3}(?:\.\d)?)\s*(kg|kgs|kilos?|lbs?|pounds?)\b"#, in: rest),
              let weight = Double(w[1] ?? "") else { return nil }
        let kg = (w[2] ?? "").lowercased().hasPrefix("k") ? weight : weight * 0.45359237
        var metres: Double?
        if let h = firstMatch(#"(\d{3}(?:\.\d)?)\s*cm\b"#, in: rest) { metres = Double(h[1] ?? "").map { $0 / 100 } }
        else if let h = firstMatch(#"(?<![\d.])([12]\.\d{1,2})\s*m\b"#, in: rest) { metres = Double(h[1] ?? "") }
        else if let h = firstMatch(#"([3-7])\s*(?:['’]|ft|foot|feet)\s*(\d{1,2})?"#, in: rest),
                let ft = Double(h[1] ?? "") { metres = (ft * 12 + (Double(h[2] ?? "") ?? 0)) * 0.0254 }
        guard let m = metres, m > 1, m < 2.5, kg > 20, kg < 300,
              rest.range(of: #"\d\s*(?:cm|m|kg|kgs|kilos?|lbs?|pounds?|['’"”]|ft|feet|in)?\s*\??\s?$"#, options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        let value = kg / (m * m)
        return Conversions(source: trimmed(g[0]), results: ["BMI " + oneDecimal(value)])
    }

    /// "be there in 15", "back in 5", "call you back in 10": minutes left
    /// unsaid → the clock time then.
    static func backIn(in text: String, now: Date, here: TimeZone) -> Conversions? {
        guard let g = firstMatch(#"\b(?:be\s+(?:there|back|home|ready|down|out|free|done|over)|call\s+(?:you|u)\s+back|back|ready|leaving|home|there)\s+in\s+(\d{1,2})[.!]?\s?$"#, in: text),
              let n = Double(g[1] ?? ""), n >= 2, n <= 60 else { return nil }
        return Conversions(source: trimmed(g[0]), results: [clock(now.addingTimeInterval(n * 60), from: now, here: here)])
    }

    /// "was 80 now 60", "was $120, now $90" → -25% · save $30.
    static func wasNow(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\bwas\s+([$€£₹¥])?\s?"# + amt + #"\s*,?\s*(?:now|is\s+now|now\s+(?:just|only)|but\s+now|reduced\s+to|down\s+to)\s+([$€£₹¥])?\s?"# + amt + end, in: text),
              let a = number(g[2]), let b = number(g[4]), a > 0, a != b else { return nil }
        let s = g[1] ?? g[3] ?? ""
        return Conversions(source: trimmed(g[0]),
                           results: [percentChange((b - a) / a * 100), (b < a ? "save " : "+") + billMoney(abs(b - a), s)])
    }

    private static let romanDigits: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                                       (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
    static func romanNumeral(_ n: Int) -> String {
        var n = n, out = ""
        for (v, r) in romanDigits { while n >= v { out += r; n -= v } }
        return out
    }

    /// "roman numeral 2026", "2026 in roman" → MMXXVI in its place;
    /// "MMXXVI in numbers" → 2026.
    static func roman(in text: String) -> Conversions? {
        if let g = firstMatch(#"\broman(?:\s+numerals?)?\s+(?:for\s+|of\s+)?(\d{1,4})"# + end, in: text)
            ?? firstMatch(#"(?<![\w.,])(\d{1,4})\s+(?:in|as|to|into)\s+roman(?:\s+numerals?)?"# + end, in: text),
           let n = Int(g[1] ?? ""), n >= 1, n <= 3999 {
            return Conversions(source: trimmed(g[0]), results: [romanNumeral(n)], hows: [.replace])
        }
        if let g = firstMatch(#"(?<![\w])([MDCLXVI]{2,15})\s+(?:in\s+(?:numbers|digits|arabic)|as\s+a\s+number|to\s+(?:numbers|digits))"# + end, in: text),
           let r = g[1]?.uppercased() {
            var total = 0, i = r.startIndex
            for (v, sym) in romanDigits { while r[i...].hasPrefix(sym) { total += v; i = r.index(i, offsetBy: sym.count) } }
            guard i == r.endIndex, total > 0, romanNumeral(total) == r else { return nil }
            return Conversions(source: trimmed(g[0]), results: ["\(total)"])
        }
        return nil
    }

    /// "base64 hello" → aGVsbG8= in its place; "base64 decode aGVsbG8=" → hello.
    static func base64(in text: String) -> Conversions? {
        if let g = firstMatch(#"\bbase\s?64\s+decode\s*:?\s+([A-Za-z0-9+/_-]{4,}={0,2})\s?$"#, in: text), var code = g[1] {
            code = code.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while code.count % 4 != 0 { code += "=" }
            guard let data = Data(base64Encoded: code), let plain = String(data: data, encoding: .utf8),
                  !plain.isEmpty, plain.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
            else { return nil }
            return Conversions(source: trimmed(g[0]), results: [plain], hows: [.replace])
        }
        if let g = firstMatch(#"\bbase\s?64(?:\s+encode)?\s*:?\s+(?!decode\b)(\S.{0,199}?)\s?$"#, in: text), let plain = g[1] {
            return Conversions(source: trimmed(g[0]), results: [Data(plain.utf8).base64EncodedString()], hows: [.replace])
        }
        return nil
    }

    private static var lastUUID: (for: String, id: String)?
    /// "uuid", "new guid": a fresh one in its place, the same while the
    /// words stay the same.
    static func uuid(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?:^|[\s(])((?:new\s+|random\s+|generate\s+(?:a\s+)?|fresh\s+)?(?:uuid|guid)(?:\s*v4)?)\??\s?$"#, in: text),
              let source = g[1] else { return nil }
        if lastUUID?.for != text { lastUUID = (text, UUID().uuidString.lowercased()) }
        return Conversions(source: trimmed(source), results: [lastUUID!.id], hows: [.replace])
    }

    /// Emergency numbers by country: one number where it is one, police and
    /// ambulance where they differ. Only numbers checked against each
    /// country's own published lists; nothing for a country not in it.
    private static let emergencyNumbers: [String: String] = [
        "US": "911", "CA": "911", "MX": "911", "AR": "911", "PH": "911",
        "GB": "999", "HK": "999", "MY": "999",
        "IE": "112", "FR": "112", "DE": "112", "ES": "112", "IT": "112", "NL": "112", "BE": "112", "PT": "112",
        "AT": "112", "CH": "112", "SE": "112", "NO": "112", "DK": "112", "FI": "112", "PL": "112", "GR": "112",
        "CZ": "112", "IN": "112", "ID": "112",
        "AU": "000", "NZ": "111",
        "JP": "110 police · 119 ambulance", "CN": "110 police · 120 ambulance", "KR": "112 police · 119 ambulance",
        "SG": "999 police · 995 ambulance", "AE": "999 police · 998 ambulance", "BR": "190 police · 192 ambulance",
        "IL": "100 police · 101 ambulance", "TH": "191 police · 1669 ambulance", "ZA": "10111 police · 10177 ambulance",
    ]
    private static let countryWords: [String: String] = [
        "us": "US", "usa": "US", "america": "US", "united states": "US", "the us": "US", "canada": "CA", "mexico": "MX",
        "argentina": "AR", "philippines": "PH", "uk": "GB", "britain": "GB", "great britain": "GB", "england": "GB",
        "scotland": "GB", "wales": "GB", "united kingdom": "GB", "the uk": "GB", "hong kong": "HK", "malaysia": "MY",
        "ireland": "IE", "france": "FR", "germany": "DE", "spain": "ES", "italy": "IT", "netherlands": "NL",
        "holland": "NL", "belgium": "BE", "portugal": "PT", "austria": "AT", "switzerland": "CH", "sweden": "SE",
        "norway": "NO", "denmark": "DK", "finland": "FI", "poland": "PL", "greece": "GR", "czechia": "CZ",
        "czech republic": "CZ", "europe": "FR", "eu": "FR", "india": "IN", "indonesia": "ID", "bali": "ID",
        "australia": "AU", "new zealand": "NZ", "nz": "NZ", "japan": "JP", "china": "CN", "korea": "KR",
        "south korea": "KR", "singapore": "SG", "uae": "AE", "dubai": "AE", "abu dhabi": "AE", "brazil": "BR",
        "israel": "IL", "thailand": "TH", "south africa": "ZA",
    ]
    static func emergencyNumber(in text: String, region: String?) -> Conversions? {
        guard let g = firstMatch(#"\b(?:emergency|police|ambulance)\s+(?:number|no\.?|line|phone|services?|contact)(?:\s+(?:(?:in|for|of)\s+)?([a-z][a-z .]{1,25}?))?\??\s?$"#, in: text)
        else { return nil }
        let named = g[1]?.lowercased().trimmingCharacters(in: .whitespaces)
        guard let code = named.map({ countryWords[$0] }) ?? region?.uppercased(), let number = emergencyNumbers[code] else { return nil }
        let place = named.map { $0 == "europe" || $0 == "eu" ? "EU" : ($0.count <= 3 ? $0.uppercased() : $0.capitalized) }
        return Conversions(source: trimmed(g[0]), results: [place.map { "\(number) · \($0)" } ?? number])
    }

    /// What chat shorthand stands for: "what does ngl mean" → not gonna lie.
    private static let slang: [String: String] = [
        "ngl": "not gonna lie", "iykyk": "if you know, you know", "tbh": "to be honest", "imo": "in my opinion",
        "imho": "in my humble opinion", "idk": "I don't know", "idc": "I don't care", "ikr": "I know, right?",
        "smh": "shaking my head", "fr": "for real", "nvm": "never mind", "tbf": "to be fair", "afaik": "as far as I know",
        "irl": "in real life", "fyi": "for your information", "btw": "by the way", "brb": "be right back",
        "ttyl": "talk to you later", "gtg": "got to go", "g2g": "got to go", "hmu": "hit me up", "wyd": "what (are) you doing",
        "wbu": "what about you", "hbu": "how about you", "lmk": "let me know", "ofc": "of course", "rn": "right now",
        "np": "no problem", "ty": "thank you", "tysm": "thank you so much", "yw": "you're welcome", "omw": "on my way",
        "otw": "on the way", "eta": "estimated time of arrival", "asap": "as soon as possible",
        "rsvp": "please reply (répondez s'il vous plaît)", "tldr": "too long; didn't read", "tl;dr": "too long; didn't read",
        "dm": "direct message", "pov": "point of view", "goat": "greatest of all time", "fomo": "fear of missing out",
        "yolo": "you only live once", "bff": "best friends forever", "jk": "just kidding", "lol": "laughing out loud",
        "lmao": "laughing my ass off", "rofl": "rolling on the floor laughing", "istg": "I swear to god",
        "ily": "I love you", "sus": "suspicious", "ong": "on god (I swear)", "nsfw": "not safe for work",
        "tmi": "too much information", "ftw": "for the win", "icymi": "in case you missed it", "ootd": "outfit of the day",
        "wfh": "work from home", "ooo": "out of office", "eod": "end of day", "eow": "end of week",
        "cob": "close of business", "pto": "paid time off", "tbd": "to be decided", "tba": "to be announced",
        "wip": "work in progress", "aka": "also known as", "diy": "do it yourself", "fwiw": "for what it's worth",
        "til": "today I learned", "eli5": "explain like I'm 5", "ama": "ask me anything", "smth": "something",
        "ppl": "people", "hbd": "happy birthday", "nbd": "no big deal", "wagmi": "we're all gonna make it",
        "ngmi": "not gonna make it", "dyor": "do your own research", "hodl": "hold (don't sell)",
        "fud": "fear, uncertainty and doubt", "gg": "good game", "glhf": "good luck, have fun", "afk": "away from keyboard",
        "bet": "okay, deal", "no cap": "no lie", "cap": "a lie", "lowkey": "a little, quietly",
        "highkey": "very, openly", "rizz": "charm", "delulu": "delusional", "mid": "mediocre", "slay": "did great",
        "ate": "did great", "stan": "a big fan", "simp": "too eager to please someone", "salty": "bitter, upset",
        "ghosted": "cut off contact without a word", "situationship": "a relationship with no label",
        "periodt": "end of discussion", "bussin": "really good", "finna": "going to", "gonna": "going to",
        "wanna": "want to", "tryna": "trying to", "wdym": "what do you mean", "wym": "what do you mean",
        "ik": "I know", "ig": "I guess", "icl": "I can't lie", "mb": "my bad", "nm": "not much", "sry": "sorry",
        "pls": "please", "thx": "thanks", "gm": "good morning", "gn": "good night", "hru": "how are you",
        "wtv": "whatever", "bc": "because", "cuz": "because", "b4": "before", "l8r": "later", "w/e": "whatever",
        "oomf": "one of my followers", "pfp": "profile picture", "ratio": "a reply with more likes than the post",
        "fyp": "for you page", "op": "original poster", "ic": "I see", "ttys": "talk to you soon", "rofr": "right of first refusal",
    ]
    static func slangMeaning(in text: String) -> Conversions? {
        let word = #"["'“]?([a-z0-9;/ ]{2,14}?)["'”]?"#
        let g = firstMatch(#"\bwhat\s+(?:does|do|is|r|are)\s+(?:an?\s+|the\s+)?"# + word + #"\s+(?:mean|stand\s+for|short\s+for)\??\s?$"#, in: text)
            ?? firstMatch(#"\b(?:meaning\s+of|define|wdym\s+by)\s+"# + word + #"\??\s?$"#, in: text)
            ?? firstMatch(#"(?:^|\s)"# + word + #"\s+meaning\??\s?$"#, in: text)
        guard let g, let key = g[1]?.lowercased().trimmingCharacters(in: .whitespaces), let meaning = slang[key] else { return nil }
        return Conversions(source: trimmed(g[0]), results: [meaning])
    }

    /// "lets meet at starbucks on main st", "im at central park", "address
    /// is 1 infinite loop cupertino" → "Add a map link": a Google Maps
    /// search for the place, after it. Not a time ("meet at 7"), nowhere in
    /// general ("home", "the airport"), nothing that isn't a place ("im at
    /// peace").
    static func mapLink(in text: String) -> Conversions? {
        let lead = #"\b(?:(meet\s+(?:me\s+|us\s+|you\s+|u\s+)?(?:at|outside|in\s+front\s+of)|let'?s\s+meet\s+(?:at|outside)|see\s+(?:you|u)\s+at|pick\s+(?:me|us)\s+up\s+(?:at|from)|drop\s+(?:me|us)\s+(?:at|off\s+at))|(?:i'?m|im|we'?re|i\s+am|we\s+are)\s+(?:at|outside)|address\s+is|located\s+at|come\s+to)\s+"#
        guard let g = firstMatch(lead + #"(.{3,60}?)[.!?]?\s?$"#, in: text), var place = g[2]?.trimmingCharacters(in: .whitespaces)
        else { return nil }
        // The time and day after the place: "starbucks at 5", "the mall tomorrow".
        place = place.replacingOccurrences(of: #"\s+(?:at|by|around|before|after)\s+\d.*$|\s+(?:tomorrow|today|tonight|tmrw|this\s+\w+|next\s+\w+|on\s+(?:mon|tue|wed|thu|fri|sat|sun)\w*|in\s+\d+.*)$"#,
                                           with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        let lower = place.lowercased()
        let words = lower.split(separator: " ").map(String.init)
        guard place.count >= 3, let first = words.first,
              lower.range(of: #"^\d{1,2}(?::\d{2})?\s*(?:am|pm)?$|\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#, options: .regularExpression) == nil,
              !["my", "your", "his", "her", "our", "their", "a", "an", "some", "this", "that", "it", "work", "home", "school",
                "noon", "night", "midnight", "lunch", "dinner", "breakfast", "peace", "least", "most", "all", "once", "last", "first"].contains(first),
              !(first == "the" && words.count == 2) else { return nil }
        // "im at" needs a place's name: two words, a capital, or a number.
        let meeting = g[1] != nil
        let named = words.count >= 2 || place.first?.isUppercase == true || place.contains(where: \.isNumber)
        guard named || (meeting && place.count >= 4) else { return nil }
        let query = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "&", with: "%26").replacingOccurrences(of: "+", with: "%2B") ?? place
        return Conversions(source: place, results: ["Add a map link"],
                           inserts: ["https://www.google.com/maps/search/?api=1&query=" + query], hows: [.after])
    }

    /// "what day is 25 december 2026", "day of the week for 3/14/1998" → Friday.
    static func dayOfWeek(in text: String, region: String?) -> Conversions? {
        guard let g = firstMatch(#"\b(?:what\s+day\s+(?:of\s+the\s+week\s+)?(?:is|was|will\s+be|falls\s+on)|which\s+day\s+(?:is|was)|day\s+of\s+(?:the\s+)?week\s+(?:for|of|on|is))\s+(?:it\s+on\s+)?(?:the\s+)?"# + fullDatePattern + end, in: text),
              let d = fullDate(g, from: 1, region: region) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: DateComponents(year: d.y, month: d.m, day: d.d)) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = cal.timeZone
        f.dateFormat = "EEEE"
        return Conversions(source: trimmed(g[0]), results: [f.string(from: date)])
    }
}

// MARK: - Answers from the 2026-10-08 research pass (Smart.kt twins)

extension Smart {

    /// "got 43/50 on the quiz", "scored 18 out of 25" → 86%. A score word
    /// is needed: "3 out of 5" alone stays quiet.
    static func testScore(in text: String, region: String?) -> Conversions? {
        guard let g = firstMatch(#"\b(?:got|get|getting|scored|score|marks?|mark|result)\s+(?:a\s+|of\s+|is\s+|was\s+)?(\d{1,3}(?:\.\d{1,2})?)\s*(?:/|out\s+of)\s*(\d{1,3})(?:\s+(?:on|in)\s+(?:the\s+|my\s+|a\s+|an\s+)?[a-z]{2,15})?"# + end, in: text),
              let a = Double(g[1] ?? ""), let b = Double(g[2] ?? ""), b > 0, a <= b, b >= 5 else { return nil }
        return Conversions(source: trimmed(g[0]), results: [oneDecimal(a / b * 100) + "%"])
    }

    /// "avg of 85, 92, 78", "average 12 15 9 22" → 85 avg · median 85;
    /// "sum of 12, 30, 8" → 50.
    static func averageOf(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\b(avg|average|mean|median|sum|total)\s+(?:of\s+)?((?:-?\d+(?:\.\d+)?\s*(?:,|and|\s)\s*){1,49}-?\d+(?:\.\d+)?)"# + end, in: text),
              let kind = g[1]?.lowercased(), let list = g[2] else { return nil }
        // "total 1,250" is one number, not two.
        if list.range(of: #"^\d{1,3}(?:,\d{3})+(?:\.\d+)?$"#, options: .regularExpression) != nil { return nil }
        let values = list.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { $0 != "and" && !$0.isEmpty }.compactMap(Double.init)
        guard values.count >= 2 else { return nil }
        let sorted = values.sorted()
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let sum = values.reduce(0, +)
        func n(_ v: Double) -> String {
            var t = billMoney(v, "")
            if t.contains(".") { while t.hasSuffix("0") { t.removeLast() }; if t.hasSuffix(".") { t.removeLast() } }
            return t
        }
        if kind == "sum" || kind == "total" { return Conversions(source: trimmed(g[0]), results: [n(sum)]) }
        if kind == "median" { return Conversions(source: trimmed(g[0]), results: ["median " + n(median)]) }
        return Conversions(source: trimmed(g[0]), results: ["\(n(sum / Double(values.count))) avg", "median " + n(median)])
    }

    /// "extra 10% off 20% off $80", "20% + 10% off $80" → $57.60 · 28% off.
    static func stackedDiscount(in text: String) -> Conversions? {
        let g = firstMatch(#"\b(?:extra|additional|another)\s+"# + pct + #"\s*off\s+(?:the\s+)?"# + pct + #"\s*off\s*(?:of\s+)?"# + sym + #"\s*"# + amt + end, in: text)
            ?? firstMatch(#"\b"# + pct + #"\s*(?:off)?\s*(?:\+|and|then|plus|,)\s*(?:an?\s+)?(?:extra\s+|additional\s+)?"# + pct + #"\s*off\s*(?:of\s+)?"# + sym + #"\s*"# + amt + end, in: text)
        guard let g, let a = number(g[1]), let b = number(g[2]), let price = number(g[4]), a > 0, b > 0, a < 100, b < 100 else { return nil }
        let left = (1 - a / 100) * (1 - b / 100)
        return Conversions(source: trimmed(g[0]), results: [billMoney(price * left, g[3] ?? ""), oneDecimal((1 - left) * 100) + "% off"])
    }

    /// "buy 2 get 1 free $12 each", "bogo $10" → $8 each.
    static func buyGetFree(in text: String) -> Conversions? {
        let words: [String: Double] = ["one": 1, "two": 2, "three": 3, "four": 4, "a": 1]
        func count(_ s: String?) -> Double? { s.flatMap { Double($0) ?? words[$0.lowercased()] } }
        var buy: Double?, free: Double?, price: Double?, symbol = "", source = ""
        if let g = firstMatch(#"\bbuy\s+(\d|one|two|three|four)\s*,?\s*get\s+(\d|one|two|a)\s+free\s*(?:at\s+|@\s*|for\s+)?"# + sym + #"\s*"# + amt + #"\s*(?:each|ea|apiece)?"# + end, in: text) {
            (buy, free, symbol, price, source) = (count(g[1]), count(g[2]), g[3] ?? "", number(g[4]), trimmed(g[0]))
        } else if let g = firstMatch(#"\bbogo\s*(?:at\s+|@\s*|for\s+)?"# + sym + #"\s*"# + amt + #"\s*(?:each|ea)?"# + end, in: text) {
            (buy, free, symbol, price, source) = (1, 1, g[1] ?? "", number(g[2]), trimmed(g[0]))
        }
        guard let buy, let free, let price, buy > 0, free > 0, price > 0 else { return nil }
        return Conversions(source: source, results: ["\(billMoney(price * buy / (buy + free), symbol)) each"])
    }

    /// "save $500/mo for 10 yrs at 7%" → $86,542 · +$26,542 growth.
    static func monthlySavings(in text: String) -> Conversions? {
        let each = #"\s*(?:/|a|per|every|each)\s*(?:mo|mon|month|m)\b"#
        let term = #"(\d{1,2})\s*(?:years?|yrs?|y)\b"#
        let rate = #"(\d{1,2}(?:\.\d{1,2})?)\s*%"#
        var s = "", p: Double?, years: Double?, r: Double?, source = ""
        if let g = firstMatch(#"\b(?:save|saving|invest|investing|put\s+(?:away|in)|deposit|sip\s+of|sip)?\s*"# + sym + #"\s*"# + amt + each + #"\s*(?:for|over)\s*"# + term + #"\s*(?:at|@)\s*"# + rate + end, in: text) {
            (s, p, years, r, source) = (g[1] ?? "", number(g[2]), Double(g[3] ?? ""), Double(g[4] ?? ""), trimmed(g[0]))
        } else if let g = firstMatch(#"\b(?:save|saving|invest|investing|put\s+(?:away|in)|deposit|sip\s+of|sip)?\s*"# + sym + #"\s*"# + amt + each + #"\s*(?:at|@)\s*"# + rate + #"\s*(?:for|over)\s*"# + term + end, in: text) {
            (s, p, r, years, source) = (g[1] ?? "", number(g[2]), Double(g[3] ?? ""), Double(g[4] ?? ""), trimmed(g[0]))
        }
        guard let p, let years, let r, p > 0, years > 0, years <= 60, r > 0, r <= 30 else { return nil }
        let i = r / 100 / 12, n = years * 12
        let total = p * (pow(1 + i, n) - 1) / i
        return Conversions(source: source, results: [wholeMoney(total, s), "+" + wholeMoney(total - p * n, s) + " growth"])
    }

    /// "300 miles at 65 mph" → 4 h 37 min; "120 km at 80 km/h" → 1 h 30 min.
    static func driveTime(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.,])(\d{1,5}(?:\.\d+)?)\s*(?:miles?|mi|km|kms|kilomet(?:er|re)s?)\s+(?:at|@)\s*(\d{1,3})\s*(?:mph|km/?h|kmh|kph|kmph)"# + end, in: text),
              let d = Double(g[1] ?? ""), let v = Double(g[2] ?? ""), d > 0, v > 0 else { return nil }
        let minutes = Int((d / v * 60).rounded())
        guard minutes > 0, minutes < 100 * 60 else { return nil }
        let h = minutes / 60, m = minutes % 60
        return Conversions(source: trimmed(g[0]), results: [h == 0 ? "\(m) min" : (m == 0 ? "\(h) h" : "\(h) h \(m) min")])
    }

    /// "when do the clocks change", "daylight saving" → Sun 1 Nov · back 1 h,
    /// where the phone is.
    static func clockChange(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        guard let g = firstMatch(#"\b(?:when\s+(?:do|does|will)\s+(?:the\s+)?clocks?\s+(?:change|go\s+(?:back|forward)|spring\s+forward|fall\s+back)|(?:when\s+(?:is|does)\s+)?(?:daylight\s+sav(?:ing|ings)(?:\s+time)?|dst)(?:\s+(?:start|end|begin)s?)?)"# + end, in: text) else { return nil }
        guard let next = here.nextDaylightSavingTimeTransition(after: now) else {
            return Conversions(source: trimmed(g[0]), results: ["No clock changes here"])
        }
        let before = here.secondsFromGMT(for: next.addingTimeInterval(-60)), after = here.secondsFromGMT(for: next.addingTimeInterval(60))
        let shift = (after - before) / 60
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        f.dateFormat = region?.uppercased() == "US" ? "EEE, MMM d" : "EEE d MMM"
        let amount = abs(shift) % 60 == 0 ? "\(abs(shift) / 60) h" : "\(abs(shift)) min"
        return Conversions(source: trimmed(g[0]), results: ["\(f.string(from: next)) · \(shift > 0 ? "forward" : "back") \(amount)"])
    }

    /// "zone 2 heart rate age 34", "max hr age 34", "im 34 whats my max heart
    /// rate" → Zone 2: 113–132 bpm · Max HR 186 (the 220 − age rule).
    static func heartRate(in text: String) -> Conversions? {
        guard text.range(of: #"\b(?:heart\s*rate|hr|bpm)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let a = firstMatch(#"(?:\bage\s*(?:is\s+|of\s+|:)?|\bi'?m\s+|\bim\s+|\bi\s+am\s+)(\d{2})(?:\s*(?:yo|y/o|years?\s+old))?\b"#, in: text)
                ?? firstMatch(#"\b(\d{2})\s*(?:yo|y/o|years?\s+old)\b"#, in: text),
              let age = Double(a[1] ?? ""), age >= 10, age <= 100,
              text.range(of: #"(?:rate|hr|bpm|\d|old|yo)\??\s?$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let max = 220 - age
        let source = trimmed(firstMatch(#"\S.*$"#, in: text)?[0] ?? text)
        if let z = firstMatch(#"\bzone\s*([1-5])\b"#, in: text), let zone = Double(z[1] ?? "") {
            let lo = Int((max * (0.4 + zone * 0.1)).rounded()), hi = Int((max * (0.5 + zone * 0.1)).rounded())
            return Conversions(source: source, results: ["Zone \(Int(zone)): \(lo)–\(hi) bpm", "Max HR \(Int(max))"])
        }
        return Conversions(source: source, results: ["Max HR \(Int(max)) bpm", "Zone 2: \(Int((max * 0.6).rounded()))–\(Int((max * 0.7).rounded())) bpm"])
    }

    /// "x^2" → x², "\\alpha" → α, "\\pi" → π: in place.
    private static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "theta": "θ", "lambda": "λ", "mu": "μ",
        "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "phi": "φ", "omega": "ω", "Delta": "Δ", "Sigma": "Σ", "Omega": "Ω",
        "infty": "∞", "sqrt": "√", "pm": "±", "neq": "≠", "leq": "≤", "geq": "≥", "approx": "≈", "times": "×", "div": "÷",
        "degree": "°", "deg": "°",
    ]
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "n": "ⁿ", "-": "⁻", "+": "⁺",
    ]
    static func mathsSymbol(in text: String) -> Conversions? {
        if let g = firstMatch(#"\\([A-Za-z]{2,7})\s?$"#, in: text), let name = g[1], let sym = greek[name] ?? greek[name.lowercased()] {
            return Conversions(source: trimmed(g[0]), results: [sym], hows: [.replace])
        }
        if let g = firstMatch(#"(?<![\w^])([a-z0-9)])\^(-?[0-9n]{1,3})\s?$"#, in: text), let base = g[1], let power = g[2],
           power.allSatisfy({ superscripts[$0] != nil }) {
            // "2^10" is a sum, worked out already; a letter's power is notation.
            guard base.first?.isLetter == true || base == ")" else { return nil }
            return Conversions(source: trimmed(g[0]), results: [base + String(power.compactMap { superscripts[$0] })], hows: [.replace])
        }
        return nil
    }

    /// "solve 2x+5=17", "3x - 4 = 11" → x = 6; "x^2-5x+6=0" → x = 2, 3.
    static func solveEquation(in text: String) -> Conversions? {
        func num(_ s: String?, empty: Double) -> Double? {
            guard let s = s?.replacingOccurrences(of: " ", with: "") else { return nil }
            if s.isEmpty || s == "+" { return empty }
            if s == "-" { return -empty }
            return Double(s)
        }
        func tidy(_ v: Double) -> String { abs(v - v.rounded()) < 1e-9 ? String(Int(v.rounded())) : String(format: "%.3g", v) }
        if let g = firstMatch(#"(?:\bsolve\s*:?\s*)?(?<![\w.])([-+]?\s*\d*\.?\d*)\s*\*?\s*([a-z])\s*(?:\^2|²)\s*([-+]\s*\d*\.?\d*)\s*\*?\s*\2\s*([-+]\s*\d+(?:\.\d+)?)?\s*=\s*0\??\s?$"#, in: text),
           let a = num(g[1], empty: 1), let b = num(g[3], empty: 1), let x = g[2] {
            let c = num(g[4], empty: 0) ?? 0
            guard a != 0 else { return nil }
            let d = b * b - 4 * a * c
            guard d >= 0 else { return Conversions(source: trimmed(g[0]), results: ["no real \(x)"]) }
            let r1 = (-b + d.squareRoot()) / (2 * a), r2 = (-b - d.squareRoot()) / (2 * a)
            let roots = Set([tidy(r1), tidy(r2)]).sorted { (Double($0) ?? 0) < (Double($1) ?? 0) }
            return Conversions(source: trimmed(g[0]), results: ["\(x) = " + roots.joined(separator: ", ")])
        }
        if let g = firstMatch(#"(?:\bsolve\s*:?\s*)?(?<![\w.^])([-+]?\s*\d*\.?\d*)\s*\*?\s*([a-z])\s*([-+]\s*\d+(?:\.\d+)?)?\s*=\s*([-+]?\s*\d+(?:\.\d+)?)\??\s?$"#, in: text),
           let a = num(g[1], empty: 1), let x = g[2], let c = num(g[4], empty: 0) {
            // A bare "x = 5" is already solved; there must be a sum to undo.
            guard a != 0, g[3] != nil || (g[1] ?? "").filter(\.isNumber).count > 0 else { return nil }
            let b = num(g[3], empty: 0) ?? 0
            return Conversions(source: trimmed(g[0]), results: ["\(x) = " + tidy((c - b) / a)])
        }
        return nil
    }

    /// Safe inside temperatures (USDA FSIS's chart): "chicken internal
    /// temp", "safe temp for pork" → 165°F · 74°C.
    private static let safeTemps: [(String, String)] = [
        (#"chicken|turkey|poultry|duck|goose|leftovers?|casseroles?|stuffing"#, "165°F · 74°C"),
        (#"ground\s+(?:beef|pork|meat|lamb|veal)|burgers?|minced?\s+(?:beef|meat)|sausages?|meatloaf|egg\s+dish(?:es)?"#, "160°F · 71°C"),
        (#"ground\s+(?:chicken|turkey)"#, "165°F · 74°C"),
        (#"beef|steaks?|pork|lamb|veal|roast|chops?|ham"#, "145°F · 63°C, then rest 3 min"),
        (#"fish|salmon|tuna|cod|shellfish|shrimp|prawns?"#, "145°F · 63°C"),
    ]
    static func cookingSafety(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\b(?:(?:safe|internal|cooking|cook|done)\s+(?:temp|temperature)\s+(?:for|of)\s+(?:a\s+|the\s+)?([a-z ]{3,24}?)|([a-z ]{3,24}?)\s+(?:internal|safe|cooking|cooked|done)\s+(?:temp|temperature)|what\s+temp(?:erature)?\s+(?:is|should)\s+([a-z ]{3,24}?)\s+(?:done|cooked|safe))\??\s?$"#, in: text),
              let food = (g[1] ?? g[2] ?? g[3])?.lowercased() else { return nil }
        // The most particular first: "ground turkey" before "turkey".
        let ordered = [safeTemps[2], safeTemps[1], safeTemps[0], safeTemps[3], safeTemps[4]]
        for (pattern, temp) in ordered where food.range(of: #"\b(?:"# + pattern + #")\b"#, options: .regularExpression) != nil {
            return Conversions(source: trimmed(g[0]), results: [temp])
        }
        return nil
    }

    /// Kitchen swaps: "substitute for buttermilk" → 1 cup milk + 1 tbsp lemon juice.
    private static let swaps: [String: String] = [
        "buttermilk": "1 cup milk + 1 tbsp lemon juice", "egg": "1 tbsp ground flax + 3 tbsp water",
        "eggs": "1 tbsp ground flax + 3 tbsp water each", "baking powder": "¼ tsp baking soda + ½ tsp cream of tartar",
        "baking soda": "3 tsp baking powder per 1 tsp", "brown sugar": "1 cup sugar + 1 tbsp molasses",
        "cake flour": "1 cup flour less 2 tbsp + 2 tbsp cornstarch", "self raising flour": "1 cup flour + 1½ tsp baking powder + ¼ tsp salt",
        "self-raising flour": "1 cup flour + 1½ tsp baking powder + ¼ tsp salt", "self rising flour": "1 cup flour + 1½ tsp baking powder + ¼ tsp salt",
        "heavy cream": "¾ cup milk + ¼ cup melted butter", "sour cream": "plain Greek yogurt, same amount",
        "butter": "same amount of oil × ¾", "honey": "1¼ cups sugar + ¼ cup water per cup", "cornstarch": "2 tbsp flour per 1 tbsp",
        "corn starch": "2 tbsp flour per 1 tbsp", "lemon juice": "same amount of vinegar", "wine": "same amount of stock + 1 tbsp vinegar",
        "white wine": "same amount of stock + 1 tbsp white wine vinegar", "red wine": "same amount of stock + 1 tbsp red wine vinegar",
        "garlic clove": "⅛ tsp garlic powder", "fresh herbs": "⅓ the amount of dried", "milk": "same amount of oat or soy milk",
        "mayonnaise": "plain Greek yogurt, same amount", "sugar": "¾ cup honey per cup, less 3 tbsp liquid",
        "breadcrumbs": "crushed crackers or rolled oats, same amount", "ricotta": "cottage cheese, same amount",
        "vanilla extract": "maple syrup, same amount", "shallot": "½ small onion + a pinch of garlic", "yeast": "2¼ tsp instant per packet",
    ]
    static func substitute(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\b(?:substitute|sub|replacement|swap|alternative)\s+(?:for|to)\s+(?:a\s+|an\s+)?([a-z -]{3,24}?)\??\s?$"#, in: text)
                ?? firstMatch(#"\bwhat\s+(?:can|could|do)\s+i\s+use\s+instead\s+of\s+(?:a\s+|an\s+)?([a-z -]{3,24}?)\??\s?$"#, in: text),
              let food = g[1]?.lowercased().trimmingCharacters(in: .whitespaces), let swap = swaps[food] else { return nil }
        return Conversions(source: trimmed(g[0]), results: [swap])
    }

    /// "ooo until monday", "out of office till 14 oct" → "OOO reply · back
    /// Mon 12 Oct": a short reply in its place with the day worked out.
    static func outOfOffice(in text: String, now: Date, here: TimeZone, region: String?) -> Conversions? {
        guard let g = firstMatch(#"^\s*(?:i'?m\s+|im\s+)?(?:ooo|out\s+of\s+(?:the\s+)?office|on\s+(?:leave|vacation|holiday|pto))\s+(?:until|till|til|through|thru)\s+([a-z0-9 ]{3,20}?)[.!]?\s?$"#, in: text),
              let when = g[1]?.lowercased() else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let today = cal.startOfDay(for: now)
        var day: Date?
        if let w = weekdays.first(where: { $0.0 == when || when == "next " + $0.0 }) {
            var next = cal.date(byAdding: .day, value: 1, to: today)!
            while cal.component(.weekday, from: next) != w.1 { next = cal.date(byAdding: .day, value: 1, to: next)! }
            day = next
        } else if when == "tomorrow" || when == "tmrw" {
            day = cal.date(byAdding: .day, value: 1, to: today)
        } else if let d = firstMatch(#"^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,9})$|^([a-z]{3,9})\s+(\d{1,2})(?:st|nd|rd|th)?$"#, in: when) {
            let dayN = Int(d[1] ?? d[4] ?? ""), monthName = (d[2] ?? d[3] ?? "")
            if let dayN, let m = months.first(where: { $0.0 == monthName })?.1 {
                var c = cal.dateComponents([.year], from: today)
                c.month = m; c.day = dayN
                if let date = cal.date(from: c) { day = date < today ? cal.date(byAdding: .year, value: 1, to: date) : date }
            }
        }
        guard let back = day else { return nil }
        let said = dayName(back, now: now, here: here, region: region)
        let reply = "I'm out of the office until \(said) and will reply when I'm back."
        return Conversions(source: trimmed(g[0]), results: ["OOO reply · \(said)"], inserts: [reply], hows: [.replace])
    }

    /// "Best," or "Thanks," on a line of its own at the end of an email:
    /// "Sign as Alex Kim" puts the saved name under it.
    static func signOff(in text: String, fields: [VaultField]) -> Conversions? {
        guard text.contains("\n"), let g = firstMatch(#"\n\s*((?:best(?:\s+regards|\s+wishes)?|kind\s+regards|warm\s+regards|regards|thanks(?:\s+again|\s+so\s+much)?|thank\s+you|many\s+thanks|cheers|sincerely|yours(?:\s+sincerely|\s+truly)?|cordially|talk\s+soon|warmly|all\s+the\s+best),)\s*\n?$"#, in: text),
              let line = g[1], let name = fields.first(where: { $0.kind == "name" })?.value, !name.isEmpty else { return nil }
        return Conversions(source: line, results: ["Sign as \(name)"], inserts: [line + "\n" + name], hows: [.replace])
    }
}

// MARK: - Calories in everyday foods (USDA FoodData Central figures, rounded)

extension Smart {
    /// kcal for one usual serving, and how that serving is said.
    private static let foodCalories: [String: (Int, String)] = [
        "banana": (105, "medium"), "apple": (95, "medium"), "orange": (62, "medium"), "pear": (101, "medium"),
        "peach": (59, "medium"), "mango": (202, "whole"), "avocado": (240, "whole"), "kiwi": (42, "each"),
        "grapes": (104, "1 cup"), "strawberries": (49, "1 cup"), "blueberries": (84, "1 cup"), "watermelon": (46, "1 cup"),
        "pineapple": (82, "1 cup"), "cherries": (97, "1 cup"), "raspberries": (64, "1 cup"), "plum": (30, "each"),
        "egg": (72, "large"), "boiled egg": (78, "large"), "fried egg": (90, "large"), "scrambled eggs": (182, "2 eggs"),
        "slice of bread": (80, "slice"), "bread": (80, "slice"), "toast": (80, "slice"), "bagel": (277, "medium"),
        "croissant": (231, "medium"), "muffin": (377, "large"), "donut": (253, "glazed"), "doughnut": (253, "glazed"),
        "pancake": (90, "6-inch"), "waffle": (218, "7-inch"), "tortilla": (138, "flour, 8-inch"), "roti": (120, "each"),
        "chapati": (120, "each"), "naan": (262, "each"), "rice": (205, "1 cup cooked"), "white rice": (205, "1 cup cooked"),
        "brown rice": (218, "1 cup cooked"), "pasta": (221, "1 cup cooked"), "spaghetti": (221, "1 cup cooked"),
        "noodles": (219, "1 cup cooked"), "oatmeal": (166, "1 cup cooked"), "oats": (150, "½ cup dry"), "quinoa": (222, "1 cup cooked"),
        "potato": (161, "medium, baked"), "sweet potato": (103, "medium, baked"), "fries": (365, "medium serving"),
        "french fries": (365, "medium serving"), "chips": (152, "1 oz"), "popcorn": (31, "1 cup popped"),
        "chicken breast": (165, "100 g cooked"), "chicken": (165, "100 g breast, cooked"), "chicken thigh": (209, "100 g cooked"),
        "salmon": (206, "100 g cooked"), "tuna": (132, "100 g canned"), "shrimp": (99, "100 g cooked"), "steak": (271, "100 g cooked"),
        "beef": (250, "100 g cooked"), "pork chop": (231, "100 g cooked"), "bacon": (43, "slice"), "sausage": (229, "link"),
        "ham": (46, "slice"), "turkey": (135, "100 g roasted"), "tofu": (94, "½ cup"), "paneer": (265, "100 g"),
        "hamburger": (354, "single patty"), "burger": (354, "single patty"), "cheeseburger": (303, "single"),
        "big mac": (590, "each"), "hot dog": (290, "with bun"), "pizza": (285, "slice, cheese"), "slice of pizza": (285, "cheese"),
        "taco": (170, "each"), "burrito": (430, "each"), "sushi roll": (255, "6 pieces"), "sandwich": (350, "average"),
        "salad": (150, "side, with dressing"), "soup": (150, "1 cup"), "samosa": (262, "each"), "dosa": (168, "plain"),
        "idli": (39, "each"), "biryani": (290, "1 cup"),
        "milk": (103, "1 cup, 2%"), "whole milk": (149, "1 cup"), "skim milk": (83, "1 cup"), "almond milk": (39, "1 cup"),
        "oat milk": (120, "1 cup"), "yogurt": (149, "1 cup plain"), "greek yogurt": (130, "1 cup plain, nonfat"),
        "cheese": (113, "1 oz cheddar"), "butter": (102, "1 tbsp"), "peanut butter": (188, "2 tbsp"), "almonds": (164, "1 oz"),
        "peanuts": (161, "1 oz"), "cashews": (157, "1 oz"), "walnuts": (185, "1 oz"), "olive oil": (119, "1 tbsp"),
        "honey": (64, "1 tbsp"), "sugar": (16, "1 tsp"), "chocolate": (155, "1 oz dark"), "ice cream": (273, "1 cup vanilla"),
        "cookie": (78, "chocolate chip"), "cake": (350, "slice"), "brownie": (227, "each"),
        "coffee": (2, "black, 1 cup"), "latte": (190, "16 oz, 2% milk"), "cappuccino": (130, "16 oz"), "tea": (2, "1 cup"),
        "chai latte": (240, "16 oz"), "coke": (140, "12 oz can"), "soda": (140, "12 oz can"), "diet coke": (0, "can"),
        "orange juice": (112, "1 cup"), "apple juice": (114, "1 cup"), "beer": (153, "12 oz"), "wine": (125, "5 oz glass"),
        "red wine": (125, "5 oz glass"), "white wine": (121, "5 oz glass"), "vodka": (97, "1.5 oz shot"), "whiskey": (105, "1.5 oz shot"),
        "smoothie": (230, "16 oz"), "protein shake": (160, "1 scoop in water"), "carrot": (25, "medium"), "broccoli": (31, "1 cup"),
        "cucumber": (45, "whole"), "tomato": (22, "medium"), "corn": (88, "ear"), "peas": (117, "1 cup"),
    ]

    /// "how many calories in a banana", "calories in 2 eggs", "cals in a
    /// slice of pizza" → ~105 kcal (medium); a count multiplies.
    static func calories(in text: String) -> Conversions? {
        guard let g = firstMatch(#"\b(?:how\s+many\s+)?(?:calories|cals?|kcals?)\s+(?:are\s+)?(?:in|for)\s+(?:a\s+|an\s+|one\s+|1\s+|(\d{1,2})\s+)?([a-z][a-z ']{1,24}?)\??\s?$"#, in: text)
                ?? firstMatch(#"(?:^|\s)(?:a\s+|an\s+|one\s+|(\d{1,2})\s+)?([a-z][a-z ']{1,24}?)\s+(?:calories|cals?|kcals?)\??\s?$"#, in: text),
              var food = g[2]?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }
        let count = Int(g[1] ?? "") ?? 1
        var hit = foodCalories[food]
        if hit == nil, food.hasSuffix("s") { food.removeLast(); hit = foodCalories[food] }
        if hit == nil, food.hasSuffix("e") { hit = foodCalories[String(food.dropLast())] }
        guard let (kcal, serving) = hit, count >= 1, count <= 20 else { return nil }
        let said = count > 1 ? "~\(kcal * count) kcal (\(count) × \(serving))" : "~\(kcal) kcal (\(serving))"
        return Conversions(source: trimmed(g[0]), results: [said])
    }
}

// MARK: - Everyday phrases in other languages, on the phone (2026-10-14)

extension Smart {
    /// Languages in the order of each row of `phrases`.
    private static let phraseLanguages: [(names: [String], label: String)] = [
        (["spanish", "español", "espanol"], "Spanish"), (["french", "français", "francais"], "French"),
        (["german", "deutsch"], "German"), (["italian", "italiano"], "Italian"),
        (["portuguese", "brazilian", "português"], "Portuguese"), (["hindi"], "Hindi"),
        (["japanese"], "Japanese"), (["korean"], "Korean"), (["chinese", "mandarin"], "Chinese"),
        (["arabic"], "Arabic"), (["russian"], "Russian"), (["dutch"], "Dutch"), (["turkish"], "Turkish"),
    ]
    /// Everyday phrases, checked by hand; an empty entry is one with no
    /// neutral form (Hindi's "I love you" is gendered), which stays quiet.
    private static let phrases: [String: [String]] = [
        "hello": ["hola", "bonjour", "hallo", "ciao", "olá", "नमस्ते", "こんにちは", "안녕하세요", "你好", "مرحبا", "привет", "hallo", "merhaba"],
        "thank you": ["gracias", "merci", "danke", "grazie", "obrigado", "धन्यवाद", "ありがとう", "감사합니다", "谢谢", "شكرا", "спасибо", "dank je", "teşekkürler"],
        "thank you so much": ["muchas gracias", "merci beaucoup", "vielen Dank", "grazie mille", "muito obrigado", "बहुत धन्यवाद", "本当にありがとう", "정말 감사합니다", "非常感谢", "شكرا جزيلا", "большое спасибо", "heel erg bedankt", "çok teşekkürler"],
        "please": ["por favor", "s'il vous plaît", "bitte", "per favore", "por favor", "कृपया", "お願いします", "부탁합니다", "请", "من فضلك", "пожалуйста", "alsjeblieft", "lütfen"],
        "sorry": ["lo siento", "désolé", "Entschuldigung", "scusa", "desculpa", "माफ़ कीजिए", "ごめんなさい", "미안해요", "对不起", "آسف", "извините", "sorry", "özür dilerim"],
        "excuse me": ["disculpe", "excusez-moi", "Entschuldigung", "mi scusi", "com licença", "सुनिए", "すみません", "실례합니다", "打扰一下", "عفوا", "извините", "pardon", "affedersiniz"],
        "good morning": ["buenos días", "bonjour", "guten Morgen", "buongiorno", "bom dia", "सुप्रभात", "おはようございます", "좋은 아침이에요", "早上好", "صباح الخير", "доброе утро", "goedemorgen", "günaydın"],
        "good evening": ["buenas tardes", "bonsoir", "guten Abend", "buonasera", "boa noite", "शुभ संध्या", "こんばんは", "좋은 저녁이에요", "晚上好", "مساء الخير", "добрый вечер", "goedenavond", "iyi akşamlar"],
        "good night": ["buenas noches", "bonne nuit", "gute Nacht", "buonanotte", "boa noite", "शुभ रात्रि", "おやすみなさい", "안녕히 주무세요", "晚安", "تصبح على خير", "спокойной ночи", "welterusten", "iyi geceler"],
        "how are you": ["¿cómo estás?", "comment ça va ?", "wie geht's?", "come stai?", "como vai?", "आप कैसे हैं?", "お元気ですか？", "잘 지내세요?", "你好吗？", "كيف حالك؟", "как дела?", "hoe gaat het?", "nasılsın?"],
        "i love you": ["te quiero", "je t'aime", "ich liebe dich", "ti amo", "eu te amo", "", "愛してる", "사랑해요", "我爱你", "أحبك", "я тебя люблю", "ik hou van je", "seni seviyorum"],
        "goodbye": ["adiós", "au revoir", "auf Wiedersehen", "arrivederci", "adeus", "अलविदा", "さようなら", "안녕히 가세요", "再见", "مع السلامة", "до свидания", "tot ziens", "hoşça kal"],
        "see you later": ["hasta luego", "à plus tard", "bis später", "a dopo", "até logo", "फिर मिलेंगे", "またね", "나중에 봐요", "回头见", "أراك لاحقا", "до встречи", "tot later", "sonra görüşürüz"],
        "yes": ["sí", "oui", "ja", "sì", "sim", "हाँ", "はい", "네", "是的", "نعم", "да", "ja", "evet"],
        "no": ["no", "non", "nein", "no", "não", "नहीं", "いいえ", "아니요", "不是", "لا", "нет", "nee", "hayır"],
        "you're welcome": ["de nada", "de rien", "gern geschehen", "prego", "de nada", "कोई बात नहीं", "どういたしまして", "천만에요", "不客气", "عفوا", "пожалуйста", "graag gedaan", "rica ederim"],
        "cheers": ["¡salud!", "santé !", "prost!", "salute!", "saúde!", "चीयर्स", "乾杯", "건배", "干杯", "في صحتك", "за здоровье!", "proost!", "şerefe!"],
        "happy birthday": ["feliz cumpleaños", "joyeux anniversaire", "alles Gute zum Geburtstag", "buon compleanno", "feliz aniversário", "जन्मदिन मुबारक", "お誕生日おめでとう", "생일 축하해요", "生日快乐", "عيد ميلاد سعيد", "с днём рождения", "gefeliciteerd met je verjaardag", "doğum günün kutlu olsun"],
        "congratulations": ["felicidades", "félicitations", "herzlichen Glückwunsch", "congratulazioni", "parabéns", "बधाई हो", "おめでとう", "축하해요", "恭喜", "مبروك", "поздравляю", "gefeliciteerd", "tebrikler"],
        "good luck": ["buena suerte", "bonne chance", "viel Glück", "buona fortuna", "boa sorte", "शुभकामनाएँ", "頑張って", "행운을 빌어요", "祝你好运", "حظا سعيدا", "удачи", "succes", "iyi şanslar"],
        "nice to meet you": ["mucho gusto", "enchanté", "freut mich", "piacere", "prazer", "आपसे मिलकर खुशी हुई", "はじめまして", "만나서 반가워요", "很高兴认识你", "تشرفت بمعرفتك", "приятно познакомиться", "leuk je te ontmoeten", "tanıştığıma memnun oldum"],
        "i miss you": ["te extraño", "tu me manques", "ich vermisse dich", "mi manchi", "sinto sua falta", "", "会いたい", "보고 싶어요", "我想你", "اشتقت إليك", "я скучаю по тебе", "ik mis je", "seni özledim"],
        "where is the bathroom": ["¿dónde está el baño?", "où sont les toilettes ?", "wo ist die Toilette?", "dov'è il bagno?", "onde fica o banheiro?", "बाथरूम कहाँ है?", "トイレはどこですか？", "화장실이 어디예요?", "洗手间在哪里？", "أين الحمام؟", "где туалет?", "waar is het toilet?", "tuvalet nerede?"],
        "how much is this": ["¿cuánto cuesta?", "combien ça coûte ?", "wie viel kostet das?", "quanto costa?", "quanto custa?", "यह कितने का है?", "いくらですか？", "이거 얼마예요?", "这个多少钱？", "بكم هذا؟", "сколько это стоит?", "hoeveel kost dit?", "bu ne kadar?"],
        "the bill please": ["la cuenta, por favor", "l'addition, s'il vous plaît", "die Rechnung, bitte", "il conto, per favore", "a conta, por favor", "बिल दीजिए", "お会計をお願いします", "계산서 주세요", "请结账", "الحساب من فضلك", "счёт, пожалуйста", "de rekening, alstublieft", "hesap lütfen"],
        "i don't understand": ["no entiendo", "je ne comprends pas", "ich verstehe nicht", "non capisco", "não entendo", "मुझे समझ नहीं आया", "わかりません", "이해가 안 돼요", "我不明白", "لا أفهم", "я не понимаю", "ik begrijp het niet", "anlamıyorum"],
        "do you speak english": ["¿hablas inglés?", "parlez-vous anglais ?", "sprechen Sie Englisch?", "parli inglese?", "você fala inglês?", "क्या आप अंग्रेज़ी बोलते हैं?", "英語を話せますか？", "영어 하세요?", "你会说英语吗？", "هل تتكلم الإنجليزية؟", "вы говорите по-английски?", "spreekt u Engels?", "İngilizce biliyor musunuz?"]
    ]
    private static let phraseAliases: [String: String] = [
        "hi": "hello", "hey": "hello", "thanks": "thank you", "thx": "thank you", "ty": "thank you",
        "thanks so much": "thank you so much", "thank you very much": "thank you so much", "thanks a lot": "thank you so much",
        "bye": "goodbye", "good bye": "goodbye", "goodnight": "good night", "gn": "good night", "gm": "good morning",
        "how are u": "how are you", "how r u": "how are you", "ily": "i love you", "love you": "i love you",
        "see you": "see you later", "see ya": "see you later", "cya": "see you later", "sorry!": "sorry",
        "your welcome": "you're welcome", "youre welcome": "you're welcome", "no problem": "you're welcome",
        "happy bday": "happy birthday", "hbd": "happy birthday", "congrats": "congratulations",
        "where's the bathroom": "where is the bathroom", "where is the toilet": "where is the bathroom",
        "the check please": "the bill please", "check please": "the bill please", "bill please": "the bill please",
        "miss you": "i miss you", "i dont understand": "i don't understand", "do you speak english?": "do you speak english",
    ]

    /// "thank you in spanish", "how do you say good night in japanese",
    /// "what's cheers in german" → gracias / おやすみなさい / prost!, in place,
    /// with no AI run spent. Only the phrases in the table; anything else is
    /// the translate bar's.
    static func phraseIn(in text: String) -> Conversions? {
        let langs = phraseLanguages.flatMap(\.names).joined(separator: "|")
        let say = #"(?:how\s+(?:do|would)\s+(?:you|u|i)\s+say\s+|what(?:'s|s|\s+is)\s+|translate\s+|say\s+)?"#
        guard let g = firstMatch(#"(?<![\w'])"# + say + #"["“']?([a-z' ?!]{2,30}?)["”']?\s+(?:in|to|into)\s+("# + langs + #")\??\s?$"#, in: text),
              let phrase = g[1]?.lowercased().trimmingCharacters(in: .whitespaces),
              let lang = g[2]?.lowercased(),
              let index = phraseLanguages.firstIndex(where: { $0.names.contains(lang) }) else { return nil }
        // "ok thank you in spanish": the phrase is the longest known tail.
        let words = phrase.split(separator: " ").map(String.init)
        for start in 0..<words.count {
            let tail = words[start...].joined(separator: " ")
            let key = phrases[tail] != nil ? tail : (phraseAliases[tail] ?? "")
            guard let row = phrases[key] else { continue }
            guard index < row.count, !row[index].isEmpty else { return nil }
            let said = trimmed(g[0])
            // In place of the phrase and its language, not the words before it.
            let from = said.range(of: tail, options: .caseInsensitive)?.lowerBound ?? said.startIndex
            let source = start == 0 ? said : String(said[from...])
            return Conversions(source: source, results: [row[index]], hows: [.replace])
        }
        return nil
    }
}

// MARK: - Sunrise, sunset and golden hour, worked out on the phone (2026-10-14)

extension Smart {
    /// Where the phone was last seen (the app shares it; nil until then).
    /// The keyboard sets it; nothing here asks for location.
    static var lastLocation: (lat: Double, lon: Double)?

    /// The standard sunrise equation (NOAA), as the server's sun.ts: within a
    /// minute. `lon` is east-positive. nil times inside a polar day or night.
    static func sunTimes(lat: Double, lon: Double, date: Date) -> (rise: Date?, set: Date?, golden: Date?) {
        let rad = Double.pi / 180, j2000 = 2451545.0
        func julian(_ d: Date) -> Double { d.timeIntervalSince1970 / 86400 + 2440587.5 }
        func fromJulian(_ j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }
        let n = (julian(date) - j2000 - 0.0009 + lon / 360).rounded()
        let noon = n + 0.0009 - lon / 360
        let m = (357.5291 + 0.98560028 * noon).truncatingRemainder(dividingBy: 360)
        let c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
        let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = j2000 + noon + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
        let decl = asin(sin(lambda * rad) * sin(23.4397 * rad))
        func hourAngle(_ altitude: Double) -> Double? {
            let cosO = (sin(altitude * rad) - sin(lat * rad) * sin(decl)) / (cos(lat * rad) * cos(decl))
            guard cosO >= -1, cosO <= 1 else { return nil }
            return acos(cosO) / rad
        }
        guard let o = hourAngle(-0.833) else { return (nil, nil, nil) }
        let golden = hourAngle(6).map { fromJulian(transit + $0 / 360) }
        return (fromJulian(transit - o / 360), fromJulian(transit + o / 360), golden)
    }

    /// "sunset", "what time is sunset", "sunrise tomorrow", "golden hour"
    /// (the whole sentence, so "my sunset photo" stays quiet) → Sunset 6:42 PM,
    /// where the phone last was.
    static func sunAnswer(in text: String, now: Date = Date(), here: TimeZone = .current) -> Conversions? {
        guard let place = lastLocation else { return nil }
        let sentence = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? text
        guard let g = firstMatch(#"^\s*(?:(?:what\s+time\s+is|when\s+is|when'?s|whens|what'?s|whats|what\s+is)\s+)?(?:the\s+)?(sunset|sunrise|golden\s+hour)(?:\s+time)?(?:\s+(today|tonight|tomorrow|tmrw))?\s*\??\s*$"#, in: sentence),
              let kind = g[1]?.lowercased() else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = here
        let tomorrow = ["tomorrow", "tmrw"].contains(g[2]?.lowercased() ?? "")
        let day = tomorrow ? (cal.date(byAdding: .day, value: 1, to: now) ?? now) : now
        // Noon that day, so the sun's day is the one asked about.
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let t = sunTimes(lat: place.lat, lon: place.lon, date: noon)
        let (label, when): (String, Date?) = kind.hasPrefix("sunrise") ? ("Sunrise", t.rise)
            : kind.hasPrefix("sunset") ? ("Sunset", t.set) : ("Golden hour", t.golden)
        guard let when else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = here
        f.dateFormat = "h:mm a"
        let said = "\(label) \(f.string(from: when))" + (tomorrow ? " tomorrow" : "")
        return Conversions(source: trimmed(g[0]), results: [said])
    }
}

// MARK: - Weather where the phone is, from Open-Meteo (keyless; 2026-10-14)

extension Smart {
    /// Today's and tomorrow's weather where the phone last was, as Open-Meteo
    /// gave it (WeatherStore fetches; nothing here touches the network).
    struct WeatherSnapshot: Equatable {
        var at: Date
        var fahrenheit: Bool
        var nowTemp: Double
        var nowCode: Int
        var nowRain: Double
        /// [today, tomorrow]
        var high: [Double]
        var low: [Double]
        var rainChance: [Int]
        var code: [Int]
    }
    static var weather: WeatherSnapshot?

    /// What a message asks of the weather: "weather today", "whats the
    /// weather", "is it going to rain", "will it rain tomorrow", "is it
    /// raining". The whole sentence, so "weather was great" stays quiet.
    static func weatherAsk(in text: String) -> (day: Int, rain: Bool, now: Bool, source: String)? {
        let sentence = text.components(separatedBy: CharacterSet(charactersIn: ".!\n")).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? text
        let s = sentence.trimmingCharacters(in: .whitespaces)
        if let g = firstMatch(#"^(?:hows|how's|how\s+is|whats|what's|what\s+is)?\s*(?:the\s+)?(?:weather|forecast)(?:\s+like)?(?:\s+(today|tonight|now|tomorrow|tmrw))?\s*\??$"#, in: s) {
            let tomorrow = ["tomorrow", "tmrw"].contains(g[1]?.lowercased() ?? "")
            return (tomorrow ? 1 : 0, false, false, trimmed(g[0]))
        }
        if let g = firstMatch(#"^(?:is\s+it|will\s+it|is\s+it\s+going\s+to|gonna|does\s+it\s+look\s+like\s+it'?s?\s+going\s+to)\s+(rain|raining|snow|snowing)(?:\s+(today|tonight|tomorrow|tmrw|later))?\s*\??$"#, in: s),
           let verb = g[1]?.lowercased() {
            let tomorrow = ["tomorrow", "tmrw"].contains(g[2]?.lowercased() ?? "")
            let now = verb.hasSuffix("ing") && g[2] == nil && s.lowercased().hasPrefix("is it raining") || s.lowercased().hasPrefix("is it snowing")
            return (tomorrow ? 1 : 0, true, now, trimmed(g[0]))
        }
        return nil
    }

    static func weatherWords(_ code: Int) -> String {
        switch code {
        case 0: return "clear"
        case 1: return "mostly clear"
        case 2: return "partly cloudy"
        case 3: return "cloudy"
        case 45, 48: return "fog"
        case 51...57: return "drizzle"
        case 61...67: return "rain"
        case 71...77: return "snow"
        case 80...82: return "showers"
        case 85, 86: return "snow showers"
        case 95...99: return "thunderstorms"
        default: return "mixed"
        }
    }

    /// The answer, once the snapshot is in hand: "18°, partly cloudy · H 21 L 12",
    /// "Tomorrow: rain 80% · H 19 L 11", "No rain expected today (10%)".
    static func weatherAnswer(in text: String, snapshot w: WeatherSnapshot?) -> Conversions? {
        guard let ask = weatherAsk(in: text), let w, w.high.count > ask.day, w.low.count > ask.day,
              w.rainChance.count > ask.day, w.code.count > ask.day else { return nil }
        func deg(_ v: Double) -> String { "\(Int(v.rounded()))°" }
        let d = ask.day
        let range = "H \(deg(w.high[d])) L \(deg(w.low[d]))"
        let said: String
        if ask.now {
            said = w.nowRain > 0 || (51...99).contains(w.nowCode) ? "Yes, \(weatherWords(w.nowCode)) now · \(deg(w.nowTemp))"
                : "Not now · \(weatherWords(w.nowCode)), \(deg(w.nowTemp))"
        } else if ask.rain {
            let when = d == 1 ? "tomorrow" : "today"
            said = w.rainChance[d] >= 40 ? "Rain likely \(when) (\(w.rainChance[d])%)"
                : w.rainChance[d] >= 20 ? "Some chance of rain \(when) (\(w.rainChance[d])%)"
                : "No rain expected \(when) (\(w.rainChance[d])%)"
        } else if d == 1 {
            said = "Tomorrow: \(weatherWords(w.code[1]))\(w.rainChance[1] >= 30 ? " \(w.rainChance[1])%" : "") · \(range)"
        } else {
            said = "\(deg(w.nowTemp)), \(weatherWords(w.nowCode)) · \(range)"
        }
        return Conversions(source: ask.source, results: [said])
    }
}

// MARK: - Durations, kitchen volumes and writing help (2026-10-14 third probe)

extension Smart {
    /// "90 minutes in hours" → 1.5 h; "2 hours 45 minutes in minutes" → 165 min;
    /// "3.5 hours in minutes" → 210 min.
    static func duration(in text: String) -> Conversions? {
        guard let g = firstMatch(#"(?<![\w.])(?:(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\s*(?:and\s+)?)?(?:(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|m))?\s+(?:in|to|into|as)\s+(hours?|hrs?|minutes?|mins?|seconds?|secs?)\??\s?$"#, in: text),
              g[1] != nil || g[2] != nil, let unit = g[3]?.lowercased() else { return nil }
        let minutes = (Double(g[1] ?? "") ?? 0) * 60 + (Double(g[2] ?? "") ?? 0)
        guard minutes > 0 else { return nil }
        let said: String
        if unit.hasPrefix("h") {
            guard g[2] != nil else { return nil }   // "2 hours in hours" says nothing
            said = oneDecimal(minutes / 60) + " h"
        } else if unit.hasPrefix("m") {
            guard g[1] != nil else { return nil }
            said = "\(Int(minutes.rounded())) min"
        } else {
            said = "\(Int((minutes * 60).rounded())) s"
        }
        return Conversions(source: trimmed(g[0]), results: [said])
    }

    /// US kitchen volumes asked in millilitres or litres: "16 oz in ml" (a
    /// volume asked as one is fluid ounces), "a cup in ml", "2 pints in litres".
    static func kitchenVolume(in text: String) -> Conversions? {
        let ml: [String: Double] = ["oz": 29.5735, "fl oz": 29.5735, "floz": 29.5735, "cup": 236.588, "cups": 236.588,
                                    "pint": 473.176, "pints": 473.176, "quart": 946.353, "quarts": 946.353,
                                    "gallon": 3785.41, "gallons": 3785.41, "tbsp": 14.7868, "tsp": 4.92892]
        guard let g = firstMatch(#"(?<![\w.])(\d+(?:\.\d+)?|an?|one|half\s+an?)\s*(fl\s*oz|floz|oz|cups?|pints?|quarts?|gallons?|tbsp|tsp)\s+(?:in|to|into|as)\s+(ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)\??\s?$"#, in: text),
              let raw = g[1]?.lowercased(), let unit = g[2]?.lowercased().replacingOccurrences(of: " ", with: ""),
              let per = ml[unit] ?? ml[unit.replacingOccurrences(of: "floz", with: "oz")] else { return nil }
        let count = Double(raw) ?? (raw.hasPrefix("half") ? 0.5 : 1)
        let total = count * per
        let toLitres = (g[3] ?? "").lowercased().hasPrefix("l")
        let said = toLitres ? String(format: "%.2f L", total / 1000).replacingOccurrences(of: ".00", with: "") : "\(Int(total.rounded())) ml"
        return Conversions(source: trimmed(g[0]), results: [said])
    }

    /// Words people mix up: "is it affect or effect", "their there or they're".
    private static let confusions: [(Set<String>, String)] = [
        (["affect", "effect"], "affect: to change (it affects me) · effect: the result (the effect)"),
        (["their", "there", "they're"], "their: belongs to them · there: a place · they're: they are"),
        (["your", "you're"], "your: belongs to you · you're: you are"),
        (["its", "it's"], "its: belongs to it · it's: it is"),
        (["then", "than"], "then: next, at that time · than: comparing (bigger than)"),
        (["lose", "loose"], "lose: to misplace or not win · loose: not tight"),
        (["fewer", "less"], "fewer: things you count · less: amounts you don't"),
        (["who", "whom"], "who: does it (who called?) · whom: has it done to them (to whom)"),
        (["lie", "lay"], "lie: to recline (I lie down) · lay: to put something (lay it down)"),
        (["ie", "eg", "i.e.", "e.g."], "i.e.: that is (exactly) · e.g.: for example"),
        (["to", "too", "two"], "to: direction · too: also, very · two: 2"),
        (["accept", "except"], "accept: to receive · except: apart from"),
        (["advice", "advise"], "advice: the noun · advise: the verb"),
        (["principal", "principle"], "principal: main, or a school head · principle: a rule or belief"),
        (["stationary", "stationery"], "stationary: not moving · stationery: paper and pens"),
        (["compliment", "complement"], "compliment: praise · complement: complete, go well with"),
        (["weather", "whether"], "weather: rain or sun · whether: if"),
        (["loose", "lose"], "lose: to misplace or not win · loose: not tight"),
    ]

    /// Irregular past tenses: "past tense of run" → ran, run.
    private static let pastTenses: [String: String] = [
        "be": "was / were · been", "begin": "began · begun", "break": "broke · broken", "bring": "brought · brought",
        "buy": "bought · bought", "catch": "caught · caught", "choose": "chose · chosen", "come": "came · come",
        "cost": "cost · cost", "cut": "cut · cut", "do": "did · done", "draw": "drew · drawn", "drink": "drank · drunk",
        "drive": "drove · driven", "eat": "ate · eaten", "fall": "fell · fallen", "feel": "felt · felt", "fight": "fought · fought",
        "find": "found · found", "fly": "flew · flown", "forget": "forgot · forgotten", "forgive": "forgave · forgiven",
        "freeze": "froze · frozen", "get": "got · got / gotten", "give": "gave · given", "go": "went · gone", "grow": "grew · grown",
        "hang": "hung · hung", "have": "had · had", "hear": "heard · heard", "hide": "hid · hidden", "hit": "hit · hit",
        "hold": "held · held", "hurt": "hurt · hurt", "keep": "kept · kept", "know": "knew · known", "lay": "laid · laid",
        "lead": "led · led", "leave": "left · left", "lend": "lent · lent", "let": "let · let", "lie": "lay · lain",
        "lose": "lost · lost", "make": "made · made", "mean": "meant · meant", "meet": "met · met", "pay": "paid · paid",
        "put": "put · put", "quit": "quit · quit", "read": "read · read", "ride": "rode · ridden", "ring": "rang · rung",
        "rise": "rose · risen", "run": "ran · run", "say": "said · said", "see": "saw · seen", "sell": "sold · sold",
        "send": "sent · sent", "set": "set · set", "shake": "shook · shaken", "shine": "shone · shone", "shoot": "shot · shot",
        "show": "showed · shown", "shut": "shut · shut", "sing": "sang · sung", "sink": "sank · sunk", "sit": "sat · sat",
        "sleep": "slept · slept", "speak": "spoke · spoken", "spend": "spent · spent", "stand": "stood · stood",
        "steal": "stole · stolen", "stick": "stuck · stuck", "sting": "stung · stung", "strike": "struck · struck",
        "swear": "swore · sworn", "swim": "swam · swum", "take": "took · taken", "teach": "taught · taught",
        "tear": "tore · torn", "tell": "told · told", "think": "thought · thought", "throw": "threw · thrown",
        "understand": "understood · understood", "wake": "woke · woken", "wear": "wore · worn", "win": "won · won",
        "write": "wrote · written", "dive": "dove / dived · dived", "lit": "lit · lit", "light": "lit · lit",
        "seek": "sought · sought", "bite": "bit · bitten", "blow": "blew · blown", "build": "built · built",
        "burn": "burned / burnt · burned / burnt", "dream": "dreamed / dreamt · dreamed / dreamt", "spell": "spelled / spelt · spelled / spelt",
    ]

    /// Irregular plurals: "plural of cactus" → cacti (or cactuses).
    private static let plurals: [String: String] = [
        "cactus": "cacti (or cactuses)", "child": "children", "person": "people", "man": "men", "woman": "women",
        "mouse": "mice", "goose": "geese", "tooth": "teeth", "foot": "feet", "ox": "oxen", "fish": "fish",
        "sheep": "sheep", "deer": "deer", "moose": "moose", "series": "series", "species": "species",
        "criterion": "criteria", "phenomenon": "phenomena", "datum": "data", "medium": "media (or mediums)",
        "analysis": "analyses", "crisis": "crises", "thesis": "theses", "hypothesis": "hypotheses",
        "basis": "bases", "diagnosis": "diagnoses", "fungus": "fungi", "nucleus": "nuclei", "radius": "radii",
        "stimulus": "stimuli", "syllabus": "syllabi (or syllabuses)", "octopus": "octopuses", "virus": "viruses",
        "alumnus": "alumni", "index": "indexes (or indices)", "appendix": "appendices (or appendixes)",
        "matrix": "matrices", "vertex": "vertices", "knife": "knives", "life": "lives", "wife": "wives",
        "leaf": "leaves", "half": "halves", "wolf": "wolves", "loaf": "loaves", "shelf": "shelves",
        "potato": "potatoes", "tomato": "tomatoes", "hero": "heroes", "echo": "echoes", "piano": "pianos",
        "photo": "photos", "die": "dice", "louse": "lice", "quiz": "quizzes", "bus": "buses", "box": "boxes",
        "mother-in-law": "mothers-in-law", "passerby": "passersby", "aircraft": "aircraft", "salmon": "salmon",
    ]

    /// "is it affect or effect", "past tense of run", "plural of cactus".
    static func writingHelp(in text: String) -> Conversions? {
        if let g = firstMatch(#"\b(?:is\s+it\s+|which\s+is\s+(?:right|correct)[:,]?\s+|when\s+to\s+use\s+)?([a-z'.]{2,12})(?:\s*,\s*|\s+or\s+|\s+vs\.?\s+|\s+and\s+)([a-z'.]{2,12})(?:(?:\s*,\s*|\s+or\s+)([a-z'.]{2,12}))?\??\s?$"#, in: text),
           let a = g[1]?.lowercased(), let b = g[2]?.lowercased() {
            let asked = Set([a, b] + (g[3].map { [$0.lowercased()] } ?? []))
            if let hit = confusions.first(where: { asked.isSubset(of: $0.0) && asked.count >= 2 }) {
                return Conversions(source: trimmed(g[0]), results: [hit.1])
            }
        }
        if let g = firstMatch(#"\b(?:what(?:'s|s|\s+is)\s+the\s+)?past\s+(?:tense|form)\s+(?:of\s+)?["']?([a-z]{2,12})["']?\??\s?$"#, in: text),
           let verb = g[1]?.lowercased(), let past = pastTenses[verb] {
            return Conversions(source: trimmed(g[0]), results: [past])
        }
        if let g = firstMatch(#"\b(?:what(?:'s|s|\s+is)\s+the\s+)?plural\s+(?:of\s+|for\s+)?(?:an?\s+)?["']?([a-z-]{2,16})["']?\??\s?$"#, in: text),
           let noun = g[1]?.lowercased(), let many = plurals[noun] {
            return Conversions(source: trimmed(g[0]), results: [many])
        }
        return nil
    }
}
