package com.arpit.glyf.ime.typing

/** Where the word being typed starts and ends — Kotlin mirror of iOS
 *  WordTracker (Engine/Autocorrect.swift); same boundaries, same answers. */
object WordContext {
    /** Line breaks of every kind end a word (U+2028 is what iOS's hold
     *  Return puts in where Return sends; pasted text carries it too). A
     *  no-break space is a space. */
    private const val LINE_BREAKS = "\n\r\u2028\u2029"
    private const val SPACES = " \u00A0"
    private const val BOUNDARIES = " \n\t.,!?;:()[]{}\"'“”‘’—–/\r\u2028\u2029\u00A0"
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

    /** Whether the word being typed is part of a link, an email or a
     *  handle: the run since the last space has "://", "@" or "www." in it.
     *  Nothing there is a word to correct or learn ("youtu" of youtu.be
     *  became "youth"). */
    fun insideLinkOrAddress(before: String?): Boolean {
        if (before.isNullOrEmpty()) return false
        val run = before.split(' ', '\n', '\t', '\r', '\u2028', '\u2029', '\u00A0').last().lowercase()
        return "://" in run || '@' in run || run.startsWith("www.")
    }

    /** The word before the one being typed, nil across a sentence end. */
    fun previousWord(before: String?): String? {
        if (before.isNullOrEmpty()) return null
        val current = currentWord(before)
        var rest = before.substring(0, before.length - current.length)
        rest = rest.trimEnd { it in SPACES }
        if (rest.isEmpty() || rest.last() in ".!?" || rest.last() in LINE_BREAKS) return null
        return currentWord(rest).ifEmpty { null }
    }

    /** The word before that one ("I" in "I want t"), for the word triples;
     *  null across a sentence end. */
    fun wordBeforePrevious(before: String?): String? {
        if (before.isNullOrEmpty() || previousWord(before) == null) return null
        val current = currentWord(before)
        return previousWord(before.substring(0, before.length - current.length).trimEnd { it in SPACES })
    }

    // Undo of an autocorrect (shared/typing/FORMAT.md "Undo"): what follows
    // the fixed word rides along with it, its space ("the ") or the
    // punctuation that made the fix and then one space ("the, ").

    /** The tail after one more character, or null when that character leaves
     *  the correction behind: punctuation only before the space, one space,
     *  three characters at most. iOS WordTracker.undoTail's twin. */
    fun undoTail(tail: String, adding: Char): String? {
        if (tail.length >= 3 || tail.endsWith(" ")) return null
        return if (adding == ' ' || adding in CORRECTION_BOUNDARIES) tail + adding else null
    }

    /** UTF-16 units to delete and the text to put back for an undo, while
     *  the text before the cursor still ends with the fix and its tail. */
    fun undo(before: String, original: String, replacement: String, tail: String): Pair<Int, String>? {
        if (replacement.isEmpty() || !before.endsWith(replacement + tail)) return null
        return (replacement.length + tail.length) to (original + tail)
    }

    /** Sentence start: text start, or sentence punctuation then space(s). */
    fun wantsCapital(before: String?): Boolean {
        val ctx = before?.replace("￼", "") ?: return true
        if (ctx.isEmpty()) return true
        var sawSpace = false
        for (i in ctx.indices.reversed()) {
            val ch = ctx[i]
            if (ch in LINE_BREAKS) return true
            if (ch in SPACES) { sawSpace = true; continue }
            if (ch in ".!?") return sawSpace
            return false
        }
        return true
    }
}
