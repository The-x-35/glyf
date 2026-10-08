package com.arpit.glyf.ime.typing

/**
 * What a glide put in the field and what else it might have been, kept
 * while the caret is still right after it: one backspace takes the whole
 * word and its space back, and a tap on another guess swaps it (Arpit,
 * 2026-10-07). Pure state; GlyfIME performs the edits. Mirror of
 * Engine/Typing/GlideTyping.swift.
 */
data class GlideState(
    /** The word put in, as it was cased. */
    val word: String,
    /** The other guesses, best first. */
    val alternatives: List<String>,
    /** The text before the caret right after the word and its space landed.
     *  Anything typed, deleted or moved to since leaves the glide behind. */
    val anchor: String,
) {
    /** A space went in after the word, so a backspace removes both (UTF-16 units). */
    val deleteCount: Int get() = word.length + 1

    fun isCurrent(before: String?): Boolean = before == anchor

    /** The words to offer after [chosen] replaced the glided word. */
    fun others(chosen: String): List<String> = (listOf(word) + alternatives).filter { it != chosen }

    /** The previous word for learning: what stood before the glided word. */
    val previousWord: String?
        get() = WordContext.previousWord(anchor.dropLast(deleteCount) + " ")
}
