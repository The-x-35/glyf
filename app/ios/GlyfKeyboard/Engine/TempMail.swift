import Foundation

/// Temporary inboxes in the keyboard (Arpit, 2026-09-30: "option to enter
/// temporary mail and we will monitor its mails for next some times and show
/// the mails gotten on it, so user can get temporary mails directly inside
/// their keyboards"). The server makes the address and reads it
/// (server/src/routes/tempmail.ts); this is what the keyboard keeps and the
/// rules it watches by. Pure, so it is unit tested; TempMailWatcher does the
/// asking. Android's TempMail twin.

/// One mail, as the server hands it over. Kept in memory only: a mail's
/// words never reach the disk.
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

    /// `{id, from, fromAddress, subject, text, receivedAt (ms), code?, link?}`.
    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        let at = (json["receivedAt"] as? NSNumber)?.doubleValue ?? 0
        let from = (json["from"] as? String) ?? ""
        let code = (json["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let link = (json["link"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.init(id: id, from: from.isEmpty ? ((json["fromAddress"] as? String) ?? "") : from,
                  fromAddress: (json["fromAddress"] as? String) ?? "",
                  subject: (json["subject"] as? String) ?? "", text: (json["text"] as? String) ?? "",
                  receivedAt: Date(timeIntervalSince1970: at / 1000), code: code, link: link)
    }
}

/// What outlives the keyboard, in the App Group, so watching carries on in
/// the next app: the address, the token that reads it, how long to watch,
/// and which mails were already shown. Never a mail itself.
struct TempMailState: Codable, Equatable {
    var address: String
    var token: String
    /// When the address stops existing, in ms since 1970.
    var expiresAt: Double
    /// When this watch ends, in ms since 1970.
    var watchUntil: Double
    /// Mails already seen, so each one's chip shows once.
    var seenIds: [String] = []
    /// When the first mail with a code landed in this watch: watching stops
    /// two minutes later, unless the panel is open.
    var codeAt: Double? = nil
    /// The server said "no more checks today" (429): nothing asks until then.
    var blockedUntil: Double? = nil
}

enum TempMailRules {
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

    /// How long until the next look, or nil when nothing should look now.
    static func interval(now: Double, state: TempMailState, panelOpen: Bool) -> TimeInterval? {
        guard now < state.expiresAt, now < state.watchUntil else { return nil }
        if let blocked = state.blockedUntil, now < blocked { return nil }
        if panelOpen { return fast }
        if let codeAt = state.codeAt, now >= codeAt + afterCode { return nil }
        let started = state.watchUntil - watch
        return now - started < fastFor ? fast : slow
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

    /// Local midnight after `now`: when a day's allowance comes back.
    static func nextMidnight(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                          matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    }
}
