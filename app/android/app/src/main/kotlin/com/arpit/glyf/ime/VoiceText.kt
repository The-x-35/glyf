package com.arpit.glyf.ime

/**
 * Voice typing's rules that need no phone, so the unit tests hold them
 * (VoiceTextTest, VoiceMachineTest): how heard words go into a field
 * ([commit]), Gboard's spoken punctuation ([spokenPunctuation]), and what
 * a cleaned-up version keeps of the words it replaces ([polished]).
 */
object VoiceText {

    /** What goes into the field: delete [deleteBefore] characters before
     *  the cursor (spaces a mark should sit against), then type [text]. */
    data class Commit(val text: String, val deleteBefore: Int = 0)

    /**
     * [heard] as typed words at the cursor, between [before] and [after]
     * (the field's text either side, a few dozen characters is plenty).
     * [capitals]: the field takes sentence capitals and the person has
     * Auto-capitalise on. [english]: the recognizer's language is English,
     * so its spoken punctuation can be read.
     *
     * Spaced as typing is: one space from the word before, none after a
     * space, a new line or an opening bracket, none before a mark; a space
     * after when the cursor sits against a word. A capital where a sentence
     * starts; where one doesn't, the recognizer's capital on a plain word
     * ("And then") goes, a name's ("Paris") stays.
     */
    fun commit(heard: String, before: String, after: String, capitals: Boolean, english: Boolean): Commit {
        var t = heard.replace(Regex("[ \\t\\u00A0]+"), " ").trim()
        t = spokenPunctuation(t, english)
        if (t.isEmpty()) return Commit("")
        if (capitals) {
            t = if (sentenceStart(before)) upperFirst(t) else lowerFirstIfPlain(t)
            t = capitaliseSentences(t)
        }
        // A mark said first (", and then") sits against the word before:
        // the spaces typed after that word go.
        var delete = 0
        if (t.first() in GLUED_MARKS) {
            val spaces = before.length - before.trimEnd(' ').length
            if (spaces < before.length) delete = spaces
        }
        val kept = before.dropLast(delete)
        val lead = if (spaceBefore(kept, t)) " " else ""
        val tail = if (spaceAfter(t, after)) " " else ""
        return Commit(lead + t + tail, delete)
    }

    /** The field is at a sentence's start: nothing before, or a full stop,
     *  question or exclamation mark (a closing quote or bracket after it
     *  counts), or a new line. */
    fun sentenceStart(before: String): Boolean {
        if (before.isEmpty()) return true
        if (before.last() == '\n') return true
        val b = before.trimEnd(' ', '\t', ' ')
        if (b.isEmpty()) return true
        if (b.last() == '\n') return true
        val core = b.trimEnd('"', '\'', '”', '’', ')', ']')
        if (core.isEmpty()) return false
        if (core.last() == '!' || core.last() == '?') return true
        if (core.last() != '.') return false
        // A full stop ends a sentence, not a number's ("3.") or an
        // abbreviation's ("e.g.", "a.").
        val token = core.substringAfterLast(' ').substringAfterLast('\n')
        if (token.count { it == '.' } > 1 || token.length <= 2) return false
        return !core[core.length - 2].isDigit()
    }

    // Gboard's spoken punctuation (support.google.com/gboard/answer/2781851):
    // period, comma, exclamation point, question mark, new line, new
    // paragraph; "full stop" and "exclamation mark" as said outside the US.
    private val spoken = listOf(
        Regex("(?i)[ ]*\\bnew paragraph\\b[ ]*") to "\n\n",
        Regex("(?i)[ ]*\\bnew line\\b[ ]*") to "\n",
        Regex("(?i)[ ]*\\b(?:period|full stop)\\b") to ".",
        Regex("(?i)[ ]*\\bcomma\\b") to ",",
        Regex("(?i)[ ]*\\bquestion mark\\b") to "?",
        Regex("(?i)[ ]*\\bexclamation (?:point|mark)\\b") to "!",
    )

    /**
     * "see you soon period" → "see you soon.". Read only when the
     * recognizer wrote no marks of its own: one that punctuates (Android
     * 13's formatting, Gboard's on-device model) already turned a said
     * "period" into "." and left the word "period" where it was meant.
     */
    fun spokenPunctuation(text: String, english: Boolean): String {
        if (!english || text.any { it in ".,!?;:" }) return text
        var out = text
        for ((re, mark) in spoken) out = re.replace(out, mark)
        if (out == text) return text
        // A space after a mark that runs into a word, none before one.
        out = Regex("([.,!?])(?=[^\\s.,!?])").replace(out, "$1 ")
        out = Regex(" +").replace(out, " ")
        out = Regex(" *\\n *").replace(out, "\n")
        return out.trim(' ')
    }

    /** A capital after each sentence's end inside what was said. */
    fun capitaliseSentences(text: String): String =
        Regex("([.!?] +|\\n+)(\\p{Ll})").replace(text) { it.groupValues[1] + it.groupValues[2].uppercase() }

    private fun upperFirst(t: String): String {
        val i = t.indexOfFirst { it.isLetter() }
        if (i < 0 || !t[i].isLowerCase()) return t
        // Only a word at the very front: "(see" → "(See", not "3 apples" → "3 Apples".
        if (t.substring(0, i).any { it.isLetterOrDigit() }) return t
        return t.substring(0, i) + t[i].uppercaseChar() + t.substring(i + 1)
    }

    /** The recognizer capitalises every utterance's first word. Mid-sentence
     *  that capital goes on a plain word; a name, an acronym and "I" keep it. */
    private fun lowerFirstIfPlain(t: String): String {
        val word = Regex("^[A-Za-z']+").find(t)?.value ?: return t
        if (word.length < 2 || !word[0].isUpperCase() || word.drop(1).any { it.isUpperCase() }) return t
        if (word.lowercase() !in PLAIN) return t
        return t[0].lowercaseChar() + t.substring(1)
    }

    private fun spaceBefore(before: String, t: String): Boolean {
        if (before.isEmpty()) return false
        val last = before.last()
        if (last.isWhitespace()) return false
        if (t.first() in GLUED_MARKS || t.first() in ")]}’”" || t.first() == '\n') return false
        if (last in "([{“‘/@#") return false
        // A straight quote opens when nothing but a space or bracket is before it.
        if (last == '"' || last == '\'') {
            val prev = before.getOrNull(before.length - 2)
            if (prev == null || prev.isWhitespace() || prev in "([{") return false
        }
        return true
    }

    private fun spaceAfter(t: String, after: String): Boolean {
        val next = after.firstOrNull() ?: return false
        if (t.last().isWhitespace() || t.last() in "([{“‘") return false
        return next.isLetterOrDigit() || next in "([{“"
    }

    /**
     * The cleaned-up words in place of [original]'s: no quotes the model
     * wrapped them in, and a mid-sentence start stays small ("so we" stays
     * "so we", not "So we") when the model capitalised the same word.
     */
    fun polished(original: String, cleaned: String): String {
        var p = cleaned.trim()
        while (p.length >= 2 && ((p.first() == '"' && p.last() == '"') ||
                (p.first() == '“' && p.last() == '”'))) p = p.substring(1, p.length - 1).trim()
        if (p.isEmpty()) return original
        val o = original.trimStart()
        if (o.isNotEmpty() && o[0].isLowerCase() && p[0].isUpperCase()) {
            val ow = Regex("^[\\p{L}']+").find(o)?.value.orEmpty()
            val pw = Regex("^[\\p{L}']+").find(p)?.value.orEmpty()
            if (ow.isNotEmpty() && ow.equals(pw, ignoreCase = true)) p = p[0].lowercaseChar() + p.substring(1)
        }
        return p
    }

    /** Marks that sit against the word before them. */
    private const val GLUED_MARKS = ".,!?;:…"

    /** Words that are never a name, so a capital on one mid-sentence is
     *  only the recognizer starting a new utterance. */
    private val PLAIN = setOf(
        "a", "an", "the", "and", "but", "or", "so", "then", "also", "because", "if", "when", "while",
        "to", "of", "in", "on", "at", "for", "with", "from", "by", "about", "as", "into", "after", "before",
        "it", "it's", "is", "was", "are", "were", "be", "been", "am", "do", "does", "did", "have", "has", "had",
        "can", "could", "will", "would", "should", "shall", "may", "might", "must",
        "we", "you", "they", "he", "she", "we're", "you're", "they're", "he's", "she's", "let's",
        "this", "that", "these", "those", "there", "here", "my", "your", "our", "their", "his", "her", "its",
        "what", "where", "why", "how", "who", "which", "not", "no", "yes", "just", "maybe", "please",
        "thanks", "thank", "okay", "ok", "well", "now", "too", "very", "really", "all", "some", "any",
        "see", "get", "go", "going", "come", "coming", "let", "make", "take", "need", "want", "know", "think",
    )
}

/**
 * One go of voice typing as states (VoiceMachine): IDLE, STARTING (a
 * recognizer asked to listen), LISTENING, STOPPING (Done tapped or the
 * person went quiet; the last words are coming), ENDED. Each event returns
 * the [Step] Dictation carries out on the phone, so every path here is a
 * unit test instead of a hunch about callbacks.
 *
 * The phone's own recognizer comes first ([hasOnDevice]); its usual one
 * ([hasDefault]) takes over once, when the first fails before a word.
 */
class VoiceMachine(private val hasOnDevice: Boolean, private val hasDefault: Boolean) {

    enum class Phase { IDLE, STARTING, LISTENING, STOPPING, ENDED }

    /** SpeechRecognizer's errors, by what the keyboard does about them. */
    enum class Fault { NO_MATCH, SILENCE, PERMISSION, AUDIO, BUSY, NETWORK, LANGUAGE, OTHER }

    sealed class Step {
        /** Make a recognizer (the phone's own when [onDevice]) and listen. */
        data class Listen(val onDevice: Boolean) : Step()
        /** The recognizer is ready for speech. */
        object Ready : Step()
        /** The words so far, for the strip. */
        data class Words(val text: String) : Step()
        /** Done tapped: tell the recognizer to stop and wait a moment. */
        object Stop : Step()
        /** The recognizer heard the end: the strip shows it's finishing. */
        object Finishing : Step()
        /** Over: [heard] goes in; with nothing heard, [note] says why and
         *  [askMic] opens the app's one-time microphone ask. */
        data class End(val heard: String?, val note: String?, val askMic: Boolean = false) : Step()
        /** Nothing to do (a late or doubled callback). */
        object None : Step()
    }

    var phase = Phase.IDLE
        private set
    var onDevice = false
        private set
    /** The newest words heard: what an end keeps if no final answer comes. */
    var heard = ""
        private set

    private val live get() = phase == Phase.STARTING || phase == Phase.LISTENING || phase == Phase.STOPPING

    fun start(): Step = when {
        phase != Phase.IDLE -> Step.None
        hasOnDevice -> listen(true)
        hasDefault -> listen(false)
        else -> end(NO_VOICE)
    }

    /** Making or starting the recognizer threw. */
    fun couldNotStart(): Step = if (live) fallBack(NO_VOICE) else Step.None

    fun ready(): Step {
        if (phase != Phase.STARTING) return Step.None
        phase = Phase.LISTENING
        return Step.Ready
    }

    fun partial(text: String?): Step {
        val t = text?.trim().orEmpty()
        if (!live || t.isEmpty()) return Step.None
        if (phase == Phase.STARTING) phase = Phase.LISTENING
        heard = t
        return Step.Words(t)
    }

    fun speechEnded(): Step {
        if (phase != Phase.STARTING && phase != Phase.LISTENING) return Step.None
        phase = Phase.STOPPING
        return Step.Finishing
    }

    fun stopTapped(): Step {
        if (phase != Phase.STARTING && phase != Phase.LISTENING) return Step.None
        phase = Phase.STOPPING
        return Step.Stop
    }

    fun results(text: String?): Step {
        if (!live) return Step.None
        text?.trim()?.takeIf { it.isNotEmpty() }?.let { heard = it }
        return end(MISSED)
    }

    /** No final words a while after Done: keep what was heard. */
    fun giveUp(): Step = if (phase == Phase.STOPPING) end(MISSED) else Step.None

    /** ✕, or the keyboard went: nothing goes in. */
    fun cancel(): Step {
        if (phase == Phase.ENDED) return Step.None
        phase = Phase.ENDED
        heard = ""
        return Step.End(null, null)
    }

    fun error(fault: Fault, micGranted: Boolean): Step {
        if (!live) return Step.None
        return when (fault) {
            Fault.NO_MATCH, Fault.SILENCE -> end(MISSED)
            Fault.PERMISSION -> if (micGranted) end(MIC_REFUSED) else end(null, askMic = true)
            Fault.AUDIO -> end(MIC_BUSY)
            Fault.BUSY -> end(BUSY)
            Fault.NETWORK -> fallBack(OFFLINE)
            Fault.LANGUAGE -> fallBack(NO_LANGUAGE)
            // Done before a word was said: nothing more to say about it.
            Fault.OTHER -> if (phase == Phase.STOPPING) end(MISSED) else fallBack(STOPPED)
        }
    }

    /** The phone's own recognizer couldn't, before a word: its usual one, once. */
    private fun fallBack(note: String): Step =
        if (onDevice && heard.isBlank() && phase != Phase.STOPPING && hasDefault) listen(false) else end(note)

    private fun listen(local: Boolean): Step {
        phase = Phase.STARTING
        onDevice = local
        return Step.Listen(local)
    }

    private fun end(note: String?, askMic: Boolean = false): Step {
        phase = Phase.ENDED
        val words = heard.trim().ifEmpty { null }
        return Step.End(words, if (words == null) note else null, askMic && words == null)
    }

    companion object {
        const val MISSED = "Didn't catch that"
        const val NO_VOICE = "No voice typing on this phone"
        const val MIC_REFUSED = "Glyf can't use the microphone"
        const val MIC_BUSY = "The microphone is busy"
        const val BUSY = "Voice typing is busy"
        const val OFFLINE = "Voice typing needs a connection"
        const val NO_LANGUAGE = "Voice typing doesn't have this language yet"
        const val STOPPED = "Voice typing stopped"

        /** SpeechRecognizer.ERROR_* (public constants, the same on every
         *  release) by what the keyboard does about them. */
        fun faultOf(code: Int): Fault = when (code) {
            7 -> Fault.NO_MATCH            // ERROR_NO_MATCH
            6 -> Fault.SILENCE             // ERROR_SPEECH_TIMEOUT
            9 -> Fault.PERMISSION          // ERROR_INSUFFICIENT_PERMISSIONS
            3 -> Fault.AUDIO               // ERROR_AUDIO
            8, 10 -> Fault.BUSY            // ERROR_RECOGNIZER_BUSY, ERROR_TOO_MANY_REQUESTS
            1, 2, 4 -> Fault.NETWORK       // ERROR_NETWORK_TIMEOUT, ERROR_NETWORK, ERROR_SERVER
            12, 13 -> Fault.LANGUAGE       // ERROR_LANGUAGE_NOT_SUPPORTED, ERROR_LANGUAGE_UNAVAILABLE
            else -> Fault.OTHER            // ERROR_CLIENT, ERROR_SERVER_DISCONNECTED, …
        }
    }
}
