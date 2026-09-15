import Foundation

/// Text rules shared by the dictionary, the decoder and learning — the Swift
/// half of shared/typing/FORMAT.md (Kotlin: ime/typing/TypingText.kt).
enum TypingText {

    /// Lookup key: NFC, lowercase, apostrophes and hyphens dropped
    /// ("Don't" → "dont", "follow-up" → "followup").
    static func key(_ word: String) -> String {
        var out = String.UnicodeScalarView()
        for u in word.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars
        where u != "'" && u != "\u{2019}" && u != "-" {
            out.append(u)
        }
        return String(out)
    }

    static func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

    /// Lowercase base letter used for key matching: "É" → "e".
    @inline(__always)
    static func base(_ scalar: UInt32) -> UInt32 {
        if scalar < UInt32(foldTable.count) { return foldTable[Int(scalar)] }
        guard let u = Unicode.Scalar(scalar),
              let lower = u.properties.lowercaseMapping.unicodeScalars.first else { return scalar }
        return lower.value
    }

    private static let foldTable: [UInt32] = (0..<0x250).map { v -> UInt32 in
        guard let u = Unicode.Scalar(UInt32(v)) else { return UInt32(v) }
        let folded = String(Character(u))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let scalars = folded.unicodeScalars
        return scalars.count == 1 ? scalars.first!.value : UInt32(v)
    }

    /// Optimal-string-alignment Damerau-Levenshtein (AOSP's autocorrect weight).
    static func editDistance(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        let w = b.count + 1
        var d = [Int](repeating: 0, count: (a.count + 1) * w)
        for i in 0...a.count { d[i * w] = i }
        for j in 0...b.count { d[j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(d[(i - 1) * w + j] + 1, d[i * w + j - 1] + 1, d[(i - 1) * w + j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = min(v, d[(i - 2) * w + j - 2] + 1)
                }
                d[i * w + j] = v
            }
        }
        return d[a.count * w + b.count]
    }

    static func capitalCount(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { $0 + ($1.properties.isUppercase ? 1 : 0) }
    }

    static func hasDigit(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.numericType != nil }
    }

    /// Tokens that are addresses, handles or codes rather than words.
    static func isWebish(_ s: String) -> Bool {
        s.contains { "@#./:_".contains($0) }
    }

    static func isCapitalized(_ s: String) -> Bool {
        s.unicodeScalars.first?.properties.isUppercase ?? false
    }

    static func hasUppercase(_ s: String) -> Bool { capitalCount(s) > 0 }

    /// "Delhi", not "HSA" or "iPhone": one capital, and it's the first letter.
    static func isTitleCase(_ s: String) -> Bool { isCapitalized(s) && capitalCount(s) == 1 }

    static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    static func lowercaseFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// "Teh" + "the" → "The". Forms with capitals of their own ("I'm",
    /// "Pune", "iPhone") are shown exactly as the dictionary spells them.
    static func matchCase(typed: String, form: String) -> String {
        if hasUppercase(form) { return form }
        return isCapitalized(typed) ? capitalizeFirst(form) : form
    }

    /// The typed text is this form, as far as a reader can tell: exactly, or
    /// a lowercase word with its first letter capitalized.
    static func sameWord(typed: String, form: String) -> Bool {
        if typed == form { return true }
        return !hasUppercase(form) && typed == capitalizeFirst(form)
    }

    /// Days since 1970 — the clock learning decays by.
    static func day(_ date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }
}
