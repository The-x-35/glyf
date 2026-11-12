import Foundation

/// When the strip shows a chip instead of its three word slots, and what a ✕
/// (or typing past a chip) does to the chips after it. docs/STRIP-POLICY.md
/// is the decision table; Android's StripPolicy.kt is the twin, with the same
/// numbers and the same tests.
///
/// Pure: the caller hands in the time and the field. Nothing is stored: a ✕
/// is a short cooldown, not a rule (Arpit, 2026-11-04).
struct StripPolicy {

    // MARK: The numbers (the same on both keyboards)

    /// A new chip waits for the fingers to stop this long at a word boundary
    /// (a fast typist's keys are 150 to 250 ms apart, so 400 ms is a pause).
    static let settle: TimeInterval = 0.4
    /// Mid-word, the word slots keep the strip while typing; a chip may take
    /// over only after a longer pause, and never over a pending fix.
    static let midWordPause: TimeInterval = 1.0
    /// After a ✕, no chip at all for this long; then the strip works as
    /// before, and the chip that was crossed can come again once the text
    /// changes (Arpit, 2026-11-04: "a cooldown of 10 seconds or 5 seconds
    /// maybe to show the strip again"). No longer rests per app or per day.
    static let crossQuiet: TimeInterval = 10
    /// Typed past (a softer no than a ✕): no new chip for this long.
    static let ignoreQuiet: TimeInterval = 5
    /// Typed past = this many new words after the chip came, unused.
    static let wordsPast = 2
    /// ...and the chip was up at least this long (a glimpse is not a no).
    static let seenFor: TimeInterval = 1.0
    /// A copy is offered in the strip this long after it was made.
    static let pasteFresh: TimeInterval = 3 * 60

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
        /// A mail at the temp address (its code): asked for, no cooldown.
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
        /// The chip on screen was typed past: a short quiet began.
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

    // MARK: State (this field only, never stored)

    private(set) var field = ""
    /// Crossed chips → the text they were crossed on: each stays away until
    /// that text changes.
    private(set) var crossed: [String: String] = [:]
    private(set) var quietUntil: Double = 0
    private(set) var onScreen: Shown?

    init() {}

    // MARK: Asking

    /// A new field forgets the last one's chips.
    mutating func enter(field id: String) {
        guard id != field else { return }
        field = id
        crossed = [:]
        quietUntil = 0
        onScreen = nil
    }

    /// May this chip come at all (whatever the timing)?
    func allows(_ kind: Kind, id: String, now: Double) -> Bool {
        if crossed[id] != nil { return false }
        if kind == .mail { return true }
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

    /// Each pass, before chips: has the text moved on from a crossed chip,
    /// and has the chip that was up been typed past?
    mutating func observe(before: String, now: Double) -> Seen {
        let tail = Self.anchor(before)
        crossed = crossed.filter { $0.value == tail }
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
        quietUntil = max(quietUntil, now + Self.ignoreQuiet)
        return .ignored(shown.kind)
    }

    /// The ✕: that chip goes until the text changes, and nothing else shows
    /// for `crossQuiet`.
    mutating func dismissed(_ kind: Kind, id: String, now: Double) {
        crossed[id] = onScreen?.id == id ? onScreen?.tail ?? "" : ""
        if onScreen?.id == id { onScreen = nil }
        guard kind != .mail else { return }
        quietUntil = now + Self.crossQuiet
    }

    /// Tapped: wanted.
    mutating func used() {
        onScreen = nil
    }

    // MARK: Helpers

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
}

// MARK: - How the word slots fit their words

/// The strip's word slots never cut a word with "…" (Arpit, 2026-11-06:
/// "Google reduces the font size of the word ... show the complete word"):
/// a long word is drawn smaller, down to `smallest`; one that doesn't fit
/// even then gets the room it needs and the other slots share the rest, and
/// when that leaves them too little the last word gives up its slot. Pure:
/// the caller measures (Toolbar uses the system font).
enum SuggestionFit {
    /// The smallest size a word is drawn at: Gboard's shrunk words stop
    /// about here, still easy to read.
    static let smallest = 11.0
    /// Air left beside a word inside its slot, both sides together.
    static let pad = 8.0
    static let step = 0.5

    struct Slot: Equatable {
        /// The item drawn in it (an index into what was offered), nil for an
        /// empty slot.
        var item: Int?
        var width: Double
        /// Its font size; 0 for an empty slot.
        var size: Double
    }

    /// The biggest size, from `full` down to `smallest` in half points, at
    /// which a word `measure(size)` wide fits `width`. Nil when even the
    /// smallest doesn't.
    static func size(full: Double, width: Double, measure: (Double) -> Double) -> Double? {
        var s = full
        while s >= smallest - 0.001 {
            if measure(s) + pad <= width { return s }
            s -= step
        }
        return nil
    }

    /// Slots for up to three items (best first) across `total`, `spacing`
    /// apart: always three slots as the system bar has (an empty one for
    /// each word not offered), equal thirds whenever every word fits one.
    /// `full[i]` is item i's usual size; `measure(i, size)` its width.
    static func plan(full: [Double], total: Double, spacing: Double,
                     measure: (Int, Double) -> Double) -> [Slot] {
        let offered = min(full.count, 3)
        var items = Array(0..<offered)
        let empty = 3 - offered
        while !items.isEmpty {
            let count = items.count + empty
            let inner = total - spacing * Double(count - 1)
            let equal = inner / Double(count)
            func fitted(_ i: Int, _ width: Double) -> Double? {
                size(full: full[i], width: width) { measure(i, $0) }
            }
            var need: [Int: Double] = [:]
            for i in items where fitted(i, equal) == nil {
                need[i] = measure(i, smallest) + pad
            }
            var widths: [Double]? = nil
            if need.isEmpty {
                widths = Array(repeating: equal, count: count)
            } else {
                let rest = inner - need.values.reduce(0, +)
                let narrow = count - need.count
                if narrow == 0 {
                    if rest >= 0 {
                        widths = items.map { need[$0]! + rest / Double(need.count) }
                    }
                } else if rest > 0 {
                    let share = rest / Double(narrow)
                    if items.allSatisfy({ need[$0] != nil || fitted($0, share) != nil }) {
                        widths = items.map { need[$0] ?? share } + Array(repeating: share, count: empty)
                    }
                }
            }
            if let widths {
                return (0..<count).map { j in
                    guard j < items.count else { return Slot(item: nil, width: widths[j], size: 0) }
                    let i = items[j]
                    return Slot(item: i, width: widths[j], size: fitted(i, widths[j]) ?? smallest)
                }
            }
            // Too little room for everything: the last word goes.
            items.removeLast()
        }
        let equal = (total - spacing * 2) / 3
        return Array(repeating: Slot(item: nil, width: equal, size: 0), count: 3)
    }
}
