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
/// everywhere"): plain text, email/URL (handy keys on the space row), or a
/// digit pad for number/phone/decimal fields.
enum KeyboardContext { case text, email, url, numberPad, decimalPad, phonePad

    init(keyboardType: UIKeyboardType?) {
        switch keyboardType {
        case .emailAddress: self = .email
        case .URL, .webSearch: self = .url
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
        if context.isPad { return padRows(context: context) }
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

    /// 10 columns again: 1.25 + 1.25 + space + 2.5 on iOS, and the globe
    /// takes a column of its own where the system still asks us to draw it.
    private static func bottomRow(modeLabel: String, globe: Bool,
                                  context: KeyboardContext = .text) -> [KeySpec] {
        var row: [KeySpec] = [KeySpec(kind: .mode(modeLabel), units: 1.25)]
        if globe { row.append(KeySpec(kind: .globe, units: 1.25)) }
        // Email/URL fields: the keys those fields actually need, where the
        // system keyboard puts them (§6.1).
        switch context {
        case .email:
            row.append(KeySpec(kind: .char("@"), units: 1.25))
            row.append(KeySpec(kind: .space, units: -1))
            row.append(KeySpec(kind: .char("."), units: 1.25, accents: accents["."] ?? []))
        case .url:
            row.append(KeySpec(kind: .char("."), units: 1.25, accents: accents["."] ?? []))
            row.append(KeySpec(kind: .space, units: -1))
            row.append(KeySpec(kind: .char("/"), units: 1.25, accents: accents["/"] ?? []))
        default:
            row.append(KeySpec(kind: .emoji, units: 1.25))
            row.append(KeySpec(kind: .space, units: -1))
        }
        row.append(KeySpec(kind: .ret, units: 2.5))
        return row
    }

    /// System-style digit pad for number/phone/decimal fields: 3×4 grid.
    private static func padRows(context: KeyboardContext) -> [[KeySpec]] {
        func pad(_ c: String) -> KeySpec { KeySpec(kind: .char(c), units: 1) }
        let corner: KeySpec
        switch context {
        case .decimalPad: corner = pad(".")
        case .phonePad: corner = pad("+")
        default: corner = KeySpec(kind: .space, units: 1)
        }
        return [
            [pad("1"), pad("2"), pad("3")],
            [pad("4"), pad("5"), pad("6")],
            [pad("7"), pad("8"), pad("9")],
            [corner, pad("0"), KeySpec(kind: .delete, units: 1)],
        ]
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
