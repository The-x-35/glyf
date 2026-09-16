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
    /// Air the system leaves beside shift/delete/#+= : the key keeps its
    /// column but gives this fraction of a pitch back on one side, which is
    /// what makes the gap next to those keys wider than 6pt.
    var gapUnits: CGFloat = 0
    /// Which side the air is on (delete/return keep their right edge).
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
    /// columns each, with 0.2 of a column given back as air toward the
    /// letters (iOS draws them 45.3pt wide at a 39.5pt pitch).
    private static func side(_ kind: KeySpec.Kind, leading: Bool = false) -> KeySpec {
        KeySpec(kind: kind, units: 1.5, gapUnits: 0.2, gapLeading: leading)
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
