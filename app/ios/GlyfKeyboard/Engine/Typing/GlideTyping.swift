import Foundation

/// What a glide put in the field and what else it might have been, kept
/// while the caret is still right after it: one backspace takes the whole
/// word and its space back, and a tap on another guess swaps it (Arpit,
/// 2026-10-07: glide typing "like glide typing is on iOS"). Pure state; the
/// VC performs the edits.
struct GlideState: Equatable {
    /// The word put in, as it was cased.
    var word: String
    /// The other guesses, best first.
    var alternatives: [String]
    /// The text before the caret right after the word and its space landed.
    /// Anything typed, deleted or moved to since leaves the glide behind.
    var anchor: String

    /// A space went in after the word, so a backspace removes both.
    var deleteCount: Int { word.count + 1 }

    func isCurrent(before: String?) -> Bool { before == anchor }

    /// The words to offer after `chosen` replaced the glided word.
    func others(after chosen: String) -> [String] {
        ([word] + alternatives).filter { $0 != chosen }
    }

    /// The previous word for learning: what stood before the glided word.
    var previousWord: String? {
        WordTracker.previousWord(beforeContext: String(anchor.dropLast(deleteCount)) + " ")
    }
}
