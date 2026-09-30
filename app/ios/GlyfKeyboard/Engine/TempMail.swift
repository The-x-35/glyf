import Foundation

/// Temporary inboxes in the keyboard (Arpit, 2026-09-30: "option to enter
/// temporary mail and we will monitor its mails for next some times and show
/// the mails gotten on it, so user can get temporary mails directly inside
/// their keyboards"). mail.tm makes the address and holds its mail, and the
/// phone asks it directly (MailTM.swift, shared/tempmail/RULES.md). This is
/// what the keyboard keeps, the rules it watches by and how it reads a mail,
/// held to shared/tempmail/cases.json. Pure, so it is unit tested;
/// TempMailWatcher does the asking. Android's TempMail twin.

/// One mail, read. Kept in memory only: a mail's words never reach the disk.
struct TempMailMessage: Equatable {
    let id: String
    /// Who sent it, as a person reads it: the name, else the address.
    let from: String
    let fromAddress: String
    let subject: String
    let text: String
    let receivedAt: Date
    /// A one-time code the mail carries ("482913"), if any.
    let code: String?
    /// The link it asks to be opened (verify, sign in), if any.
    let link: String?

    init(id: String, from: String, fromAddress: String = "", subject: String, text: String,
         receivedAt: Date, code: String? = nil, link: String? = nil) {
        self.id = id
        self.from = from
        self.fromAddress = fromAddress
        self.subject = subject
        self.text = text
        self.receivedAt = receivedAt
        self.code = code
        self.link = link
    }

    /// mail.tm's `GET /messages/{id}`: `{id, from: {address, name}, subject,
    /// text, html: [String], createdAt}`, its code and link read out.
    init?(mailTM json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        let sender = json["from"] as? [String: Any]
        let name = ((sender?["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let address = ((sender?["address"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = ((json["subject"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = (json["html"] as? [String]) ?? (json["html"] as? String).map { [$0] } ?? []
        let html = parts.joined(separator: "\n")
        let text = TempMailText.body(text: (json["text"] as? String) ?? "", html: html)
        self.init(id: id, from: name.isEmpty ? address : name, fromAddress: address, subject: subject,
                  text: text, receivedAt: TempMailText.date(json["createdAt"] as? String) ?? Date(),
                  code: TempMailText.extractCode(subject: subject, text: text),
                  link: TempMailText.extractLink(text: text, html: html))
    }
}

/// What outlives the keyboard, in the App Group, so watching carries on in
/// the next app: the mail.tm account, how long to watch, and which mails
/// were already shown. Never a mail itself.
struct TempMailState: Codable, Equatable {
    var address: String
    /// mail.tm's password for it: 20 random characters, kept only on this
    /// phone. It takes a new token when the old one is turned away.
    var password: String
    /// The bearer token that reads the inbox.
    var token: String
    var accountId: String
    /// When it was made, in ms since 1970.
    var createdAt: Double
    /// When this watch ends, in ms since 1970.
    var watchUntil: Double
    /// Mails already seen, so each one's chip shows once.
    var seenIds: [String] = []
    /// When the first mail with a code landed in this watch: watching stops
    /// two minutes later, unless the panel is open.
    var codeAt: Double? = nil
    /// Three checks in a row went unanswered (429, no connection): the next
    /// waits until then.
    var blockedUntil: Double? = nil

    /// A day after it was made the keyboard lets it go. mail.tm keeps the
    /// account; it is simply no longer offered.
    var expiresAt: Double { createdAt + TempMailRules.life }
}

enum TempMailRules {
    /// How long an address is offered, from when it was made.
    static let life: Double = 24 * 3_600_000
    /// A watch lasts 15 minutes from creating the address, inserting it or
    /// opening the panel.
    static let watch: Double = 15 * 60_000
    /// Every 8 s for the first 3 minutes, then every 20 s, to spare the
    /// provider's requests; 8 s again while the panel is open.
    static let fastFor: Double = 3 * 60_000
    static let fast: TimeInterval = 8
    static let slow: TimeInterval = 20
    /// Once a code has come, the watch has done its job two minutes later.
    static let afterCode: Double = 2 * 60_000
    /// Three checks in a row with no answer pause checking for a minute.
    static let missesToPause = 3
    static let pause: Double = 60_000

    /// How long until the next look, or nil when nothing should look now.
    static func interval(now: Double, state: TempMailState, panelOpen: Bool) -> TimeInterval? {
        guard now < state.expiresAt, now < state.watchUntil else { return nil }
        if !panelOpen, let codeAt = state.codeAt, now >= codeAt + afterCode { return nil }
        let started = state.watchUntil - watch
        let beat = panelOpen || now - started < fastFor ? fast : slow
        // Paused: the next look waits the pause out.
        if let paused = state.blockedUntil, now < paused { return max(beat, (paused - now) / 1000) }
        return beat
    }

    /// Whether the watch is on right now (what the panel's line says).
    static func watching(now: Double, state: TempMailState, panelOpen: Bool) -> Bool {
        interval(now: now, state: state, panelOpen: panelOpen) != nil
    }

    /// "14:32": minutes and seconds left.
    static func left(_ ms: Double) -> String {
        let s = max(0, Int((ms / 1000).rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "now", "2m", "3h", "1d": how long ago a mail came.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// The word an address starts with.
    static let words = ["amber", "maple", "cedar", "cobalt", "ember", "willow", "lunar", "harbor",
                        "meadow", "orbit", "pebble", "river", "sable", "swift", "tidal", "quiet"]

    /// A word, six hex digits and the domain: "maple3f9a2c@uberip.com".
    static func newAddress<R: RandomNumberGenerator>(domain: String, using rng: inout R) -> String {
        let word = words.randomElement(using: &rng) ?? "maple"
        let hex = String(format: "%06x", UInt32.random(in: 0...0xFF_FFFF, using: &rng))
        return "\(word)\(hex)@\(domain)"
    }

    static func newAddress(domain: String) -> String {
        var rng = SystemRandomNumberGenerator()
        return newAddress(domain: domain, using: &rng)
    }

    /// 20 random letters and digits, never shown: only this phone and
    /// mail.tm know it.
    static func newPassword<R: RandomNumberGenerator>(using rng: inout R) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<20).map { _ in chars.randomElement(using: &rng) ?? "a" })
    }

    static func newPassword() -> String {
        var rng = SystemRandomNumberGenerator()
        return newPassword(using: &rng)
    }
}

/// How a mail is read (shared/tempmail/RULES.md, "Reading a mail"): its
/// words, the one-time code it carries and the link it asks to be opened.
/// The rules were written in JavaScript, and every keyboard keeps to its
/// meaning: positions count UTF-16 units, and a word character or a digit is
/// ASCII only.
enum TempMailText {

    /// The mail's words: its text, or with none its HTML read as text;
    /// trimmed, and at most the first 4,000 characters.
    static func body(text: String, html: String) -> String {
        let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let words = (blank ? htmlToText(html) : text).trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = words as NSString
        guard ns.length > 4000 else { return words }
        // Whole characters only: an emoji is never cut in half.
        return ns.substring(with: ns.rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: 4000)))
    }

    /// When mail.tm says it came: ISO 8601, with or without fractions.
    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    // MARK: HTML to text

    private static let hidden = try? NSRegularExpression(
        pattern: #"<(script|style|head)[\s\S]*?</\1>"#, options: [.caseInsensitive])
    private static let breaks = try? NSRegularExpression(
        pattern: #"<br\s*/?>|</(p|div|tr|li|h[1-6])>"#, options: [.caseInsensitive])
    private static let tags = try? NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let entity = try? NSRegularExpression(
        pattern: #"&(#[0-9]+|#x[0-9a-f]+|[a-z]+);"#, options: [.caseInsensitive])
    private static let spaces = try? NSRegularExpression(pattern: "[ \\t\\f\\x{0B}\\x{A0}]+")
    private static let aroundNewline = try? NSRegularExpression(pattern: #"\s*\n\s*"#)
    private static let blankLines = try? NSRegularExpression(pattern: #"\n{3,}"#)
    private static let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "#39": "'"]

    private static func replace(_ re: NSRegularExpression?, in s: String, with template: String) -> String {
        guard let re else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                           withTemplate: template)
    }

    /// Scripts, styles and the head go; a line break or the end of a
    /// paragraph, row or heading is a new line; other tags are a space;
    /// entities are decoded; runs of space close up, with at most one
    /// blank line.
    static func htmlToText(_ html: String) -> String {
        var s = replace(hidden, in: html, with: " ")
        s = replace(breaks, in: s, with: "\n")
        s = replace(tags, in: s, with: " ")
        s = decodeEntities(s)
        s = replace(spaces, in: s, with: " ")
        s = replace(aroundNewline, in: s, with: "\n")
        s = replace(blankLines, in: s, with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        guard let entity else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in entity.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let all = ns.substring(with: m.range)
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            if let word = named[key] {
                out += word
            } else if key.hasPrefix("#"), let value = key.hasPrefix("#x")
                        ? UInt32(key.dropFirst(2), radix: 16) : UInt32(key.dropFirst()),
                      let scalar = Unicode.Scalar(value) {
                out.unicodeScalars.append(scalar)
            } else {
                out += all
            }
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    // MARK: The code

    /// A number that could be a code, standing on its own: 482 913,
    /// 482-913, G-482913 or 4 to 8 digits, never inside a word, a price, a
    /// decimal, a date, a time or a path.
    private static let candidate = try? NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9_$€£₹.,/:\-])((?:[A-Z]{1,3}-)?[0-9]{3}[ \-]?[0-9]{3}|(?:[A-Z]{1,3}-)?[0-9]{4,8})(?![A-Za-z0-9_%$€£₹/:]|[.,][0-9])"#)
    /// Words a code sits next to, in the mails people get when signing up.
    private static let codeWords = try? NSRegularExpression(pattern:
        #"\b(codes?|otp|passcode|pass code|pin|verification|verify|security|confirmation|confirm|one[- ]time|log ?in|sign[- ]?in|2fa|two[- ]factor|token|password)\b"#,
        options: [.caseInsensitive])
    /// Words before a number that make it a phone, an order or a reference.
    private static let notCode = try? NSRegularExpression(pattern:
        #"\b(phone|call|tel|order|invoice|ref|reference|account (?:number|no\.?|#)|zip|postal)\b"#,
        options: [.caseInsensitive])
    private static let prefix = try? NSRegularExpression(pattern: #"^[A-Z]{1,3}-"#)
    private static let year = try? NSRegularExpression(pattern: #"^(19|20)[0-9][0-9]$"#)

    private static func has(_ re: NSRegularExpression?, _ s: String) -> Bool {
        guard let re else { return false }
        return re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// A one-time code in a mail: "Your code is 482913", "G-482913 is your
    /// Google verification code", "123 456". A number counts when the
    /// subject holds it or it stands within a few words of a code word;
    /// years, prices, phone numbers and dates never do.
    static func extractCode(subject: String, text: String) -> String? {
        guard let candidate else { return nil }
        let whole = (subject + "\n" + text) as NSString
        let hay = whole.substring(to: min(whole.length, 6000)) as NSString
        let subjectLength = (subject as NSString).length
        var best: (code: String, score: Int)?
        for m in candidate.matches(in: hay as String, range: NSRange(location: 0, length: hay.length)) {
            let raw = hay.substring(with: m.range(at: 1))
            let prefixed = has(prefix, raw)
            var digits = raw
            if prefixed, let dash = raw.firstIndex(of: "-") { digits = String(raw[raw.index(after: dash)...]) }
            digits = digits.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            let count = (digits as NSString).length
            guard (4...8).contains(count) else { continue }
            // A year on its own is a date, not a code.
            if count == 4, has(year, digits), !prefixed { continue }
            let at = m.range.location
            let rawLength = (raw as NSString).length
            let from = max(0, at - 80)
            let around = hay.substring(with: NSRange(location: from, length: min(hay.length, at + rawLength + 40) - from))
            let before = hay.substring(with: NSRange(location: max(0, at - 30), length: at - max(0, at - 30)))
            var score = 0
            if at < subjectLength { score += 3 }
            if has(codeWords, around) { score += 3 }
            score += count == 6 ? 2 : 1
            if prefixed { score += 1 }
            // A phone number or an order number reads differently.
            if has(notCode, before) { score -= 4 }
            if score >= 4, score > (best?.score ?? Int.min) {
                best = (prefixed ? raw.replacingOccurrences(of: " ", with: "") : digits, score)
            }
        }
        return best?.code
    }

    // MARK: The link

    private static let anchors = try? NSRegularExpression(pattern:
        #"<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, options: [.caseInsensitive])
    private static let bareLinks = try? NSRegularExpression(pattern:
        #"https://[^\s<>"')\]]+"#, options: [.caseInsensitive])
    private static let linkWords = try? NSRegularExpression(pattern:
        #"(verif|confirm|activat|validat|magic|log-?in|sign-?in|signin|auth|reset|token|onboard|welcome|join|invite)"#,
        options: [.caseInsensitive])
    private static let secure = try? NSRegularExpression(pattern: #"^https://"#, options: [.caseInsensitive])
    private static let trailing = try? NSRegularExpression(pattern: #"[.,;]+$"#)

    /// The link a mail asks to be opened: a verify or sign-in link, from the
    /// HTML's links first (their words say what they are), else the text.
    /// A logo or an unsubscribe link is no action: nothing rather than a guess.
    static func extractLink(text: String, html: String) -> String? {
        let page = html as NSString
        for m in anchors?.matches(in: html, range: NSRange(location: 0, length: page.length)) ?? [] {
            let href = page.substring(with: m.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            let words = htmlToText(page.substring(with: m.range(at: 2)))
            if has(secure, href), has(linkWords, href) || has(linkWords, words) { return href }
        }
        let body = text as NSString
        for m in bareLinks?.matches(in: text, range: NSRange(location: 0, length: body.length)) ?? [] {
            let href = replace(trailing, in: body.substring(with: m.range), with: "")
            if has(linkWords, href) { return href }
        }
        return nil
    }
}
