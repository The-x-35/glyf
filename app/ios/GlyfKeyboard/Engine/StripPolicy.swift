import Foundation

/// When the strip shows a chip instead of its three word slots, and what a ✕
/// (or typing past a chip) does to the chips after it. docs/STRIP-POLICY.md
/// is the decision table; Android's StripPolicy.kt is the twin, with the same
/// numbers and the same tests.
///
/// Pure: the caller hands in the time, the field and the app, and stores
/// `json` (iOS: strip-policy.json in the App Group; Android: glyf_ime prefs).
struct StripPolicy {

    // MARK: The numbers (the same on both keyboards)

    /// A new chip waits for the fingers to stop this long at a word boundary
    /// (a fast typist's keys are 150 to 250 ms apart, so 400 ms is a pause).
    static let settle: TimeInterval = 0.4
    /// Mid-word, the word slots keep the strip while typing; a chip may take
    /// over only after a longer pause, and never over a pending fix.
    static let midWordPause: TimeInterval = 1.0
    /// After a ✕ or a chip typed past, no other new chip for this long.
    static let gap: TimeInterval = 8
    /// Typed past = this many new words after the chip came, unused.
    static let wordsPast = 2
    /// ...and the chip was up at least this long (a glimpse is not a no).
    static let seenFor: TimeInterval = 1.0
    /// Typed past this many times counts as one ✕ for that kind in that app.
    static let ignoresPerDismissal = 2
    /// A ✕ mutes that kind of chip in that app for this long.
    static let appMute: TimeInterval = 10 * 60
    /// This many ✕ of one kind within `backoffWindow`, anywhere...
    static let backoffAfter = 3
    static let backoffWindow: TimeInterval = 24 * 60 * 60
    /// ...mute that kind everywhere for this long.
    static let backoff: TimeInterval = 24 * 60 * 60
    /// A copy is offered in the strip this long after it was made.
    static let pasteFresh: TimeInterval = 3 * 60
    /// Stored entries kept at most (newest first): the file stays small.
    static let maxEntries = 48

    // MARK: Kinds and fields

    enum Kind: String, CaseIterable {
        /// A saved detail the field or sentence asks for, a temp address.
        case fill
        /// Something just copied.
        case paste
        /// Worked out on the phone: sums, money, conversions, dates, weather.
        case answer
        /// The AI: "AI answer", the server's suggestion.
        case ai
        /// A plan, a booking page, a Meet link.
        case plan
        /// Send or Buy.
        case pay
        /// A mail at the temp address (its code): asked for, never muted.
        case mail
    }

    enum Field {
        case normal
        /// One-time code, card number, digit pads: only what the box is for.
        case code
        /// Passwords and secure entry: nothing.
        case secret
    }

    static func allowed(_ kind: Kind, in field: Field) -> Bool {
        switch field {
        case .normal: return true
        case .code: return kind == .fill || kind == .paste || kind == .mail
        case .secret: return false
        }
    }

    enum Timing: Equatable {
        /// Show it.
        case now
        /// Not yet: ask again in this many seconds.
        case wait(TimeInterval)
        /// The word slots keep the strip (a fix or its undo is on offer).
        case words
    }

    /// What the strip knows about the typing at this moment.
    struct Typing {
        /// Seconds since the text last changed.
        var sinceEdit: TimeInterval
        /// A word is being typed and the slots have words for it.
        var midWord: Bool
        /// The "original" undo slot right after a fix.
        var undoOnOffer: Bool
        /// Space would fix the word being typed (asked only when it matters).
        var fixPending: () -> Bool = { false }
    }

    enum Seen: Equatable {
        case nothing
        /// The chip on screen was typed past: stored state changed.
        case ignored(Kind)
        /// The copy on offer was typed past: that copy is done.
        case pasteIgnored
    }

    struct Shown: Equatable {
        let id: String
        let kind: Kind
        let tail: String
        let at: Double
    }

    // MARK: State

    /// "scope|kind" → until (seconds since 1970).
    private(set) var mutes: [String: Double] = [:]
    /// kind → until.
    private(set) var backoffs: [String: Double] = [:]
    /// kind → when each ✕ was (the last day's).
    private(set) var refusals: [String: [Double]] = [:]
    /// "scope|kind" → (typed-past count, when last).
    private(set) var softs: [String: (count: Int, at: Double)] = [:]

    /// The field's own memory, never stored.
    private(set) var field = ""
    private(set) var gone: Set<String> = []
    private(set) var quietUntil: Double = 0
    private(set) var onScreen: Shown?

    init() {}

    // MARK: Asking

    /// A new field forgets the last one's chips.
    mutating func enter(field id: String) {
        guard id != field else { return }
        field = id
        gone = []
        quietUntil = 0
        onScreen = nil
    }

    /// May this chip come at all (whatever the timing)?
    func allows(_ kind: Kind, id: String, scope: String, now: Double) -> Bool {
        if gone.contains(id) { return false }
        if kind == .mail { return true }
        if (backoffs[kind.rawValue] ?? 0) > now { return false }
        if kind != .paste, (mutes[Self.key(scope, kind)] ?? 0) > now { return false }
        if quietUntil > now, onScreen?.id != id { return false }
        return true
    }

    /// Now, later, or not over the words.
    func timing(_ kind: Kind, id: String, typing: Typing) -> Timing {
        if onScreen?.id == id { return .now }   // already up: no flicker
        if typing.undoOnOffer { return .words }
        // A saved detail completing the word being typed is itself a word.
        if typing.midWord, kind != .fill {
            if typing.fixPending() { return .words }
            return typing.sinceEdit >= Self.midWordPause ? .now : .wait(Self.midWordPause - typing.sinceEdit)
        }
        return typing.sinceEdit >= Self.settle ? .now : .wait(Self.settle - typing.sinceEdit)
    }

    // MARK: Telling

    /// A chip went up (call when it is drawn; the same id again is a no-op).
    /// `before` is the text before the caret.
    mutating func shown(_ kind: Kind, id: String, before: String, now: Double) {
        if onScreen?.id == id { return }
        onScreen = Shown(id: id, kind: kind, tail: Self.anchor(before), at: now)
    }

    /// Each pass, before chips: has the chip that was up been typed past?
    mutating func observe(before: String, scope: String, now: Double) -> Seen {
        guard let shown = onScreen else { return .nothing }
        if shown.kind == .paste {
            // The copy rides an empty field: typing anything there passes it.
            guard !before.isEmpty else { return .nothing }
            onScreen = nil
            return .pasteIgnored
        }
        guard let past = Self.wordsPast(shown.tail, before) else {
            onScreen = nil   // edited, deleted or sent: no verdict
            return .nothing
        }
        guard past >= Self.wordsPast else { return .nothing }
        onScreen = nil
        guard now - shown.at >= Self.seenFor, shown.kind != .mail else { return .nothing }
        gone.insert(shown.id)
        quietUntil = now + Self.gap
        let k = Self.key(scope, shown.kind)
        let count = (softs[k]?.count ?? 0) + 1
        if count >= Self.ignoresPerDismissal {
            softs[k] = nil
            refuse(shown.kind, scope: scope, now: now)
        } else {
            softs[k] = (count, now)
        }
        return .ignored(shown.kind)
    }

    /// The ✕.
    mutating func dismissed(_ kind: Kind, id: String, scope: String, now: Double) {
        gone.insert(id)
        if onScreen?.id == id { onScreen = nil }
        guard kind != .mail else { return }
        quietUntil = now + Self.gap
        refuse(kind, scope: scope, now: now)
    }

    /// Tapped: wanted. Typed-past counts for that kind start over.
    mutating func used(_ kind: Kind, scope: String) {
        onScreen = nil
        softs[Self.key(scope, kind)] = nil
    }

    private mutating func refuse(_ kind: Kind, scope: String, now: Double) {
        // Each copy is news: a ✕ on one says nothing about the next in this app.
        if kind != .paste { mutes[Self.key(scope, kind)] = now + Self.appMute }
        var times = (refusals[kind.rawValue] ?? []).filter { now - $0 < Self.backoffWindow }
        times.append(now)
        if times.count >= Self.backoffAfter {
            backoffs[kind.rawValue] = now + Self.backoff
            refusals[kind.rawValue] = nil
        } else {
            refusals[kind.rawValue] = times
        }
        prune(now: now)
    }

    /// Expired entries go; past `maxEntries` the oldest go.
    mutating func prune(now: Double) {
        mutes = mutes.filter { $0.value > now }
        backoffs = backoffs.filter { $0.value > now }
        refusals = refusals.compactMapValues { times in
            let kept = times.filter { now - $0 < Self.backoffWindow }
            return kept.isEmpty ? nil : kept
        }
        softs = softs.filter { now - $0.value.at < Self.backoffWindow }
        if mutes.count > Self.maxEntries {
            mutes = Dictionary(uniqueKeysWithValues: mutes.sorted { $0.value > $1.value }.prefix(Self.maxEntries).map { ($0.key, $0.value) })
        }
        if softs.count > Self.maxEntries {
            softs = Dictionary(uniqueKeysWithValues: softs.sorted { $0.value.at > $1.value.at }.prefix(Self.maxEntries).map { ($0.key, $0.value) })
        }
    }

    // MARK: Helpers

    static func key(_ scope: String, _ kind: Kind) -> String { "\(scope)|\(kind.rawValue)" }

    /// The end of the text a chip came for: where "typed past" is counted
    /// from. Its last 40 characters, so a long message whose start scrolls
    /// out of what the keyboard can read still finds it.
    static func anchor(_ before: String) -> String {
        var t = Substring(before)
        while let last = t.last, last.isWhitespace { t = t.dropLast() }
        return String(t.suffix(40))
    }

    /// How many new words follow `anchor` in `before`, or nil when the anchor
    /// is gone (deleted, edited, sent). A word glued to the anchor
    /// ("2+5" → "2+50") is the same word growing, not a new one.
    static func wordsPast(_ anchor: String, _ before: String) -> Int? {
        let rest: Substring
        if anchor.isEmpty {
            rest = Substring(before)
        } else {
            guard let r = before.range(of: anchor, options: .backwards) else { return nil }
            rest = before[r.upperBound...]
        }
        var count = 0
        var afterSpace = anchor.isEmpty
        for ch in rest {
            if ch.isWhitespace {
                afterSpace = true
            } else {
                if afterSpace { count += 1 }
                afterSpace = false
            }
        }
        return count
    }

    // MARK: Storage

    var json: [String: Any] {
        [
            "v": 1,
            "mutes": mutes,
            "backoffs": backoffs,
            "refusals": refusals,
            "softs": softs.mapValues { [Double($0.count), $0.at] },
        ]
    }

    init(json: [String: Any]?) {
        restore(json: json)
    }

    /// The stored part again (another process may have written it: the app,
    /// a scenario's reset); the field's own memory stays.
    mutating func restore(json: [String: Any]?) {
        mutes = [:]; backoffs = [:]; refusals = [:]; softs = [:]
        guard let json else { return }
        mutes = (json["mutes"] as? [String: Double]) ?? [:]
        backoffs = (json["backoffs"] as? [String: Double]) ?? [:]
        refusals = (json["refusals"] as? [String: [Double]]) ?? [:]
        let raw = (json["softs"] as? [String: [Double]]) ?? [:]
        softs = raw.compactMapValues { pair in pair.count == 2 ? (Int(pair[0]), pair[1]) : nil }
    }
}
