package com.demo.glyf.ime.typing

/** Where the word being typed starts and ends — Kotlin mirror of iOS
 *  WordTracker (Engine/Autocorrect.swift); same boundaries, same answers. */
object WordContext {
    private const val BOUNDARIES = " \n\t.,!?;:()[]{}\"'“”‘’—–/"
    /** Characters that end a word and trigger autocorrect before they land. */
    const val CORRECTION_BOUNDARIES = ".,!?;:"

    fun isBoundary(c: Char): Boolean = c in BOUNDARIES

    fun currentWord(before: String?): String {
        if (before.isNullOrEmpty()) return ""
        val sb = StringBuilder()
        var i = before.length
        while (i > 0) {
            i--
            val ch = before[i]
            if (ch in BOUNDARIES) {
                // An apostrophe between letters is part of the word: "don't".
                val inside = (ch == '\'' || ch == '’') && sb.isNotEmpty() && i > 0 && before[i - 1].isLetter()
                if (!inside) break
            }
            sb.insert(0, ch)
            if (sb.length > 48) break
        }
        return sb.toString()
    }

    /** The word before the one being typed, nil across a sentence end. */
    fun previousWord(before: String?): String? {
        if (before.isNullOrEmpty()) return null
        val current = currentWord(before)
        var rest = before.substring(0, before.length - current.length)
        rest = rest.trimEnd(' ')
        if (rest.isEmpty() || rest.last() in ".!?\n") return null
        return currentWord(rest).ifEmpty { null }
    }

    /** Sentence start: text start, or sentence punctuation then space(s). */
    fun wantsCapital(before: String?): Boolean {
        val ctx = before?.replace("￼", "") ?: return true
        if (ctx.isEmpty()) return true
        var sawSpace = false
        for (i in ctx.indices.reversed()) {
            val ch = ctx[i]
            if (ch == '\n') return true
            if (ch == ' ') { sawSpace = true; continue }
            if (ch in ".!?") return sawSpace
            return false
        }
        return true
    }
}
