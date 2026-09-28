import UIKit

/// Key model + static layout tables (§6.1: QWERTY, letters/numbers/symbols,
/// long-press accents). Pure data — geometry happens in KeyboardView.
struct KeySpec: Equatable {
    enum Kind: Equatable {
        case char(String)          // taps insert; display follows shift
        case shift
        case delete
        case space
        case ret                   // never rebound (§1.4)
        case globe                 // never rebound (§1.4)
        case mode(String)          // "123" | "ABC" | "#+="
        case emoji
    }

    var kind: Kind
    /// Width in key columns (pitches), the unit the system keyboard is drawn
    /// on: one letter is 1, and every row adds up to 10. -1 = fill remaining
    /// (space bar). Measured against iOS: see KeyboardView.layoutSubviews.
    var units: CGFloat = 1
    /// shift, delete and the third row's mode key: they keep their column
    /// but are drawn at KeyMetrics.sideKeyWidth, which is what leaves the
    /// wider gap iOS draws between them and the letters.
    var sideKey: Bool = false
    /// Which side the air is on (delete keeps its right edge).
    var gapLeading: Bool = false
    var accents: [String] = []
    /// A digit-pad key: Apple's pad typography (22pt digits, their letters
    /// under them) and no press balloon.
    var pad: Bool = false
    /// The letters under a pad digit ("ABC").
    var subtitle: String? = nil
    /// Drawn without a key cap, like the function keys on Apple's pads.
    var bare: Bool = false
    /// Shown instead of what the key types ("pause" types a comma).
    var title: String? = nil
    /// Greyed and inert: the digits under the phone pad's symbols page, and
    /// the number pad's empty corner.
    var disabled: Bool = false

    var isChar: Bool { if case .char = kind { return true }; return false }

    var char: String? { if case let .char(c) = kind { return c }; return nil }

    /// Stable id for bindings + tests: the lowercase char, or a symbol name.
    var id: String {
        switch kind {
        case .char(let c): return c
        case .shift: return "shift"
        case .delete: return "delete"
        case .space: return "space"
        case .ret: return "return"
        case .globe: return "globe"
        case .mode(let m): return "mode:\(m)"
        case .emoji: return "emojikey"
        }
    }
}

enum KeyboardMode { case letters, symbols1, symbols2 }

/// What the focused field asked for (§6.1 "behave like the system keyboard
/// everywhere"): plain text, the keys an email, web address, search or
/// Twitter field needs on the space row, WebKit's number fields, or a
/// digit pad for number/phone/decimal fields.
enum KeyboardContext { case text, email, url, webSearch, twitter, numbers,
                            numberPad, decimalPad, phonePad

    init(keyboardType: UIKeyboardType?) {
        switch keyboardType {
        case .emailAddress: self = .email
        case .URL: self = .url
        // Safari's address bar: it takes searches too, so it keeps a space bar.
        case .webSearch: self = .webSearch
        case .twitter: self = .twitter
        case .numbersAndPunctuation: self = .numbers
        case .numberPad, .asciiCapableNumberPad: self = .numberPad
        case .decimalPad: self = .decimalPad
        case .phonePad, .namePhonePad: self = .phonePad
        default: self = .text
        }
    }

    var isPad: Bool {
        self == .numberPad || self == .decimalPad || self == .phonePad
    }
}

enum KeyboardLayout {

    static let accents: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["î", "ï", "í", "ī", "į", "ì"],
        "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"],
        "u": ["û", "ü", "ù", "ú", "ū"],
        "c": ["ç", "ć", "č"],
        "n": ["ñ", "ń"],
        "s": ["ß", "ś", "š"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
        "l": ["ł"],
        "0": ["°"],
        "-": ["–", "—", "•"],
        "/": ["\\"],
        // $ is the key, like the system keyboard; the rest are under it.
        "$": ["₹", "€", "£", "¥", "₩"],
        "&": ["§"],
        "\"": ["„", "“", "”", "«", "»"],
        "'": ["‘", "’", "‚", "`"],
        "!": ["¡"],
        "?": ["¿"],
        ".": ["…"],
    ]

    static func rows(mode: KeyboardMode, numberRow: Bool, globe: Bool,
                     context: KeyboardContext = .text) -> [[KeySpec]] {
        if context.isPad { return padRows(context: context, mode: mode) }
        var result: [[KeySpec]] = []
        switch mode {
        case .letters:
            if numberRow {
                result.append("1234567890".map { key(String($0)) })
            }
            result.append("qwertyuiop".map { key(String($0)) })
            result.append("asdfghjkl".map { key(String($0)) })
            result.append([side(.shift)]
                + "zxcvbnm".map { key(String($0)) }
                + [side(.delete, leading: true)])
            result.append(bottomRow(modeLabel: "123", globe: globe, context: context))
        case .symbols1:
            result.append("1234567890".map { key(String($0)) })
            result.append(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { key($0) })
            // Apple metrics: the five keys STRETCH between mode and delete.
            result.append([side(.mode("#+="))]
                + [".", ",", "?", "!", "'"].map { wide(key($0)) }
                + [side(.delete, leading: true)])
            result.append(bottomRow(modeLabel: "ABC", globe: globe, context: context))
        case .symbols2:
            result.append(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { key($0) })
            result.append(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map { key($0) })
            result.append([side(.mode("123"))]
                + [".", ",", "?", "!", "'"].map { wide(key($0)) }
                + [side(.delete, leading: true)])
            result.append(bottomRow(modeLabel: "ABC", globe: globe, context: context))
        }
        return result
    }

    private static func key(_ c: String) -> KeySpec {
        KeySpec(kind: .char(c), accents: accents[c] ?? [])
    }

    /// shift, delete and the mode key on the third row: one and a half
    /// columns each, drawn at 1.35 letters so the air beside them matches
    /// the system keyboard on every phone width.
    private static func side(_ kind: KeySpec.Kind, leading: Bool = false) -> KeySpec {
        KeySpec(kind: kind, units: 1.5, sideKey: true, gapLeading: leading)
    }

    private static func wide(_ spec: KeySpec) -> KeySpec {
        var s = spec
        s.units = 1.4 // (10 − two 1.5 specials) ÷ 5, Apple-style stretch
        return s
    }

    /// The long press on .com, like Apple's.
    static let domains = [".net", ".org", ".edu", ".io", ".co"]

    /// 10 columns again: 1.25 + 1.25 + space + 2.5 on iOS, and the globe
    /// takes a column of its own where the system still asks us to draw it.
    /// Each field type gets the row Apple's keyboard shows it, measured on
    /// the iOS 26.5 simulator (402pt) and on an iPhone 16 Pro:
    ///
    ///     text        123 · emoji · space · return
    ///     email       123 · emoji · space (2.5) · @ · . · return
    ///     web address 123 · emoji · . · / · .com (5 columns shared) · return
    ///     search bar  123 · emoji · space · . (1) · return (1.75)
    ///     twitter     123 · emoji · space · @ · # · return
    ///     numbers     ABC (2.5) · space · return, no emoji
    ///
    /// Safari's address bar is the search bar: it takes searches, so it keeps
    /// the space bar and has no slash.
    private static func bottomRow(modeLabel: String, globe: Bool,
                                  context: KeyboardContext = .text) -> [KeySpec] {
        if context == .numbers {
            return [KeySpec(kind: .mode(modeLabel), units: 2.5),
                    KeySpec(kind: .space, units: -1),
                    KeySpec(kind: .ret, units: 2.5)]
        }
        var row: [KeySpec] = [KeySpec(kind: .mode(modeLabel), units: 1.25)]
        if globe { row.append(KeySpec(kind: .globe, units: 1.25)) }
        row.append(KeySpec(kind: .emoji, units: 1.25))
        let dot = KeySpec(kind: .char("."), units: 1.25, accents: accents["."] ?? [])
        switch context {
        case .email:
            row.append(KeySpec(kind: .space, units: -1))
            row.append(KeySpec(kind: .char("@"), units: 1.25))
            row.append(dot)
        case .url:
            // No space bar: a web address has no spaces. The three share
            // what is left.
            row.append(KeySpec(kind: .char("."), units: -1, accents: accents["."] ?? []))
            row.append(KeySpec(kind: .char("/"), units: -1, accents: accents["/"] ?? []))
            row.append(KeySpec(kind: .char(".com"), units: -1, accents: domains))
        case .webSearch:
            row.append(KeySpec(kind: .space, units: -1))
            var narrowDot = dot
            narrowDot.units = 1
            row.append(narrowDot)
            row.append(KeySpec(kind: .ret, units: 1.75))
            return row
        case .twitter:
            row.append(KeySpec(kind: .space, units: -1))
            row.append(KeySpec(kind: .char("@"), units: 1.25))
            row.append(KeySpec(kind: .char("#"), units: 1.25))
        default:
            row.append(KeySpec(kind: .space, units: -1))
        }
        row.append(KeySpec(kind: .ret, units: 2.5))
        return row
    }

    /// The letters under each digit, as on Apple's pads.
    static let padLetters = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
                             "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ"]

    /// Apple's digit pad for number, phone and decimal fields: three wide
    /// keys a row, the corner and delete drawn bare. The number pad's corner
    /// is empty, the decimal pad's is the locale's separator, and the phone
    /// pad's opens a second page (pause, wait, *, #, +) over greyed digits.
    /// iOS itself puts its own keyboard on phone fields (and passwords), so
    /// the phone pad here is only a fallback, drawn like Apple's anyway.
    private static func padRows(context: KeyboardContext, mode: KeyboardMode) -> [[KeySpec]] {
        func digit(_ d: String, disabled: Bool = false) -> KeySpec {
            KeySpec(kind: .char(d), pad: true, subtitle: padLetters[d], disabled: disabled)
        }
        func symbol(_ c: String, title: String? = nil) -> KeySpec {
            KeySpec(kind: .char(c), pad: true, title: title)
        }
        let delete = KeySpec(kind: .delete, pad: true, bare: true)
        if context == .phonePad, mode != .letters {
            return [
                [digit("1", disabled: true), digit("2", disabled: true), digit("3", disabled: true)],
                [symbol(",", title: "pause"), digit("5", disabled: true), symbol(";", title: "wait")],
                [symbol("*"), digit("8", disabled: true), symbol("#")],
                [KeySpec(kind: .mode("123"), pad: true, bare: true), symbol("+"), delete],
            ]
        }
        let corner: KeySpec
        switch context {
        case .decimalPad:
            corner = KeySpec(kind: .char(Locale.current.decimalSeparator ?? "."), pad: true, bare: true)
        case .phonePad:
            corner = KeySpec(kind: .mode("+*#"), pad: true, bare: true)
        default:
            corner = KeySpec(kind: .char(""), pad: true, bare: true, disabled: true)
        }
        return [
            [digit("1"), digit("2"), digit("3")],
            [digit("4"), digit("5"), digit("6")],
            [digit("7"), digit("8"), digit("9")],
            [corner, digit("0"), delete],
        ]
    }

    /// Where every key goes, for KeyboardView and the touch tests alike.
    ///
    /// QWERTY: a 10-column grid with Apple's constant margins and gaps
    /// (KeyMetrics). Keys with `units < 0` share what the fixed keys leave.
    /// Pads: Apple's, measured on the iOS 26.5 simulator at 402pt: three
    /// keys across the full width (5.5pt margins, 6.5pt gaps, 126pt keys),
    /// 48pt tall on the row pitch the letters use.
    static func frames(rows: [[KeySpec]], size: CGSize, context: KeyboardContext,
                       leftInset: CGFloat = 0, rightInset: CGFloat = 0)
        -> (frames: [CGRect], pitch: CGFloat, unitWidth: CGFloat, rowHeight: CGFloat) {
        let pad = context.isPad
        let hGap = pad ? 6.5 : KeyMetrics.hGap
        let margin = pad ? 5.5 : KeyMetrics.sideMargin
        let left = margin + leftInset
        let availW = size.width - left - margin - rightInset
        let columns: CGFloat = pad ? 3 : 10
        let pitch = (availW + hGap) / columns
        let unitWidth = pitch - hGap
        let rowH = rows.isEmpty ? 0 : size.height / CGFloat(rows.count)
        // Short rows (an iPhone on its side) close the gap up, so the keys
        // stay a size a thumb can hit.
        let vGap = rowH < 45 ? 8 : KeyMetrics.vGap
        let keyH = pad ? min(rowH, KeyMetrics.rowPitch(width: size.width)) - 6 : rowH - vGap
        let gapV = rowH - keyH

        var out: [CGRect] = []
        for (r, row) in rows.enumerated() {
            let fixedUnits = row.map(\.units).filter { $0 > 0 }.reduce(0, +)
            let flexCount = CGFloat(row.filter { $0.units < 0 }.count)
            let flexUnits = flexCount > 0 ? max(1, columns - fixedUnits) / flexCount : 0
            let rowUnits = flexCount > 0 ? columns : fixedUnits
            let rowWidth = rowUnits * pitch - hGap
            var x = left + (availW - rowWidth) / 2
            let y = CGFloat(r) * rowH + gapV / 2
            for spec in row {
                let units = spec.units < 0 ? flexUnits : spec.units
                let block = units * pitch - hGap
                // shift / delete / mode sit at 1.35 letters, which leaves the
                // wider gap iOS draws beside them.
                let w = spec.sideKey ? KeyMetrics.sideKeyWidth(keyWidth: unitWidth) : block
                out.append(CGRect(x: spec.gapLeading ? x + block - w : x, y: y, width: w, height: keyH))
                x += units * pitch
            }
        }
        return (out, pitch, unitWidth, rowH)
    }
}

/// Which key a touch belongs to. Pure geometry over the laid-out key frames,
/// so it can be swept point by point in tests — KeyboardView owns the views,
/// this owns the rule.
///
/// The rule is Apple's: the key area has NO dead space. A finger that lands
/// in the gap between two keys, in the margin down the side, or a hair above
/// the top row still types the nearest key. Only a point more than half a key
/// away from everything is not a keystroke at all (the strip above).
enum KeyHit {

    /// Index into `frames` of the key a touch at `point` belongs to.
    ///
    /// `area` is the key region. Inside it there is NO cutoff: the middle row
    /// is indented, so the strip of screen beside A and beside L is further
    /// than half a key from anything, yet tapping there is unmistakably meant
    /// as A or L — Apple types them. A distance limit alone leaves those
    /// edges dead, which is exactly how they felt.
    static func index(at point: CGPoint, frames: [CGRect], pitch: CGFloat,
                      area: CGRect) -> Int? {
        // Directly under a key (with the small give Apple has) wins outright,
        // so a touch never jumps past the key it is visibly on.
        for (i, f) in frames.enumerated() where f.insetBy(dx: -3, dy: -5).contains(point) {
            return i
        }
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, f) in frames.enumerated() {
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDistance { bestDistance = d; best = i }
        }
        // Anywhere in the key region belongs to a key, however far it sits
        // from one. Beyond the region, half a key of overshoot and no more —
        // a tap on the strip above is not a keystroke.
        if area.contains(point) { return best }
        let reach = max(pitch, 1) / 2
        return bestDistance <= reach * reach ? best : nil
    }

    /// Where a touch may wander before it stops counting as `frame`'s key.
    ///
    /// Anchored to WHERE THE FINGER LANDED as well as to the key. A touch
    /// that came down in a gap was snapped to the NEAREST key, so it is
    /// legitimately outside that key's frame — measuring only from the frame
    /// threw the keystroke away on the first tremor, and a real finger always
    /// moves. That was accepted-then-dropped, and it got worse the faster you
    /// typed.
    static func slack(frame: CGRect, start: CGPoint,
                      dx: CGFloat, dy: CGFloat) -> CGRect {
        frame.insetBy(dx: -dx, dy: -dy)
            .union(CGRect(x: start.x - dx, y: start.y - dy,
                          width: dx * 2, height: dy * 2))
    }
}
