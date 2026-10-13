import UIKit

/// §6.1: where the word being typed starts and ends, auto-capitalization and
/// the double-space period. Pure logic, unit-tested. Suggestions and
/// autocorrect themselves live in Engine/Typing (TypingEngine).
enum WordTracker {
    /// Line breaks of every kind end a word: hold Return puts in U+2028
    /// where Return sends, and "Hi\u{2028}there" was one word to fix and
    /// learn (2026-10-14). A no-break space is a space.
    static let lineBreaks: Set<Character> = ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}"]
    static let spaces: Set<Character> = [" ", "\u{00A0}"]
    static let boundaries = Set(" \n\t.,!?;:()[]{}\"'“”‘’—–/").union(lineBreaks).union(spaces)

    /// Recomputes the in-progress word from the proxy's before-context.
    static func currentWord(beforeContext: String?) -> String {
        guard let ctx = beforeContext, !ctx.isEmpty else { return "" }
        var word = ""
        var i = ctx.endIndex
        while i > ctx.startIndex {
            i = ctx.index(before: i)
            let ch = ctx[i]
            if boundaries.contains(ch) {
                // An apostrophe between letters is part of the word: "don't".
                let inside = (ch == "'" || ch == "’") && !word.isEmpty
                    && i > ctx.startIndex && ctx[ctx.index(before: i)].isLetter
                if !inside { break }
            }
            word.insert(ch, at: word.startIndex)
            if word.count > 48 { break } // runaway guard: URLs etc.
        }
        return word
    }

    /// Whether the word being typed is part of a link, an email or a
    /// handle: the run since the last space has "://", "@" or "www." in it.
    /// Nothing there is a word to correct or learn ("youtu" of youtu.be
    /// became "youth").
    static func insideLinkOrAddress(beforeContext: String?) -> Bool {
        guard let ctx = beforeContext, !ctx.isEmpty else { return false }
        let run = ctx.split(omittingEmptySubsequences: false,
                            whereSeparator: { spaces.contains($0) || lineBreaks.contains($0) || $0 == "\t" })
            .last.map { $0.lowercased() } ?? ""
        return run.contains("://") || run.contains("@") || run.hasPrefix("www.")
    }

    /// Should the next letter be auto-capitalized? True at text start and
    /// after sentence-ending punctuation + space(s).
    static func wantsCapital(beforeContext: String?) -> Bool {
        guard let ctx = beforeContext?.replacingOccurrences(of: "\u{FFFC}", with: ""),
              !ctx.isEmpty else { return true }
        var i = ctx.endIndex
        var sawSpace = false
        while i > ctx.startIndex {
            i = ctx.index(before: i)
            let ch = ctx[i]
            if lineBreaks.contains(ch) { return true }
            if spaces.contains(ch) { sawSpace = true; continue }
            if ".!?".contains(ch) { return sawSpace }
            return false
        }
        return true
    }

    /// The word before the one being typed ("thank" in "thank yo|"), for
    /// next-word context. Nil across a sentence end.
    static func previousWord(beforeContext: String?) -> String? {
        guard let ctx = beforeContext, !ctx.isEmpty else { return nil }
        let current = currentWord(beforeContext: ctx)
        var rest = ctx.dropLast(current.count)
        while let last = rest.last, spaces.contains(last) { rest = rest.dropLast() }
        guard let last = rest.last, !".!?".contains(last), !lineBreaks.contains(last) else { return nil }
        let word = currentWord(beforeContext: String(rest))
        return word.isEmpty ? nil : word
    }

    /// The word before that one ("I" in "I want t|"), for the word triples.
    /// Nil across a sentence end.
    static func wordBeforePrevious(beforeContext: String?) -> String? {
        guard let ctx = beforeContext, previousWord(beforeContext: ctx) != nil else { return nil }
        var rest = ctx.dropLast(currentWord(beforeContext: ctx).count)
        while let last = rest.last, spaces.contains(last) { rest = rest.dropLast() }
        return previousWord(beforeContext: String(rest))
    }

    /// Characters that end a word and trigger autocorrect before they land.
    static let correctionBoundaries = Set(".,!?;:")

    /// Double-space → ". " applies only after a real word character.
    static func canPeriodShortcut(beforeContext: String?) -> Bool {
        guard let ctx = beforeContext, ctx.hasSuffix(" "), ctx.count >= 2 else { return false }
        let beforeSpace = ctx[ctx.index(ctx.endIndex, offsetBy: -2)]
        return beforeSpace.isLetter || beforeSpace.isNumber
    }
}
