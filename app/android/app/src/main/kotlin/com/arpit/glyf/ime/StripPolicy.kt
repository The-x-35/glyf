package com.arpit.glyf.ime

/** When the strip shows a chip instead of its three word slots, and what a ✕
 *  (or typing past a chip) does to the chips after it. docs/STRIP-POLICY.md
 *  is the decision table; iOS's StripPolicy.swift is the twin, with the same
 *  numbers and the same tests.
 *
 *  Pure: the caller hands in the time (seconds) and the field. Nothing is
 *  stored: a ✕ is a short cooldown, not a rule (Arpit, 2026-11-04). */
class StripPolicy {

    companion object {
        /** A new chip waits for the fingers to stop this long at a word
         *  boundary (a fast typist's keys are 150 to 250 ms apart). */
        const val SETTLE = 0.4
        /** Mid-word the word slots keep the strip; a chip may take over only
         *  after a longer pause, and never over a pending fix. */
        const val MID_WORD_PAUSE = 1.0
        /** After a ✕, no chip at all for this long; then the strip works as
         *  before, and the crossed chip can come again once the text changes
         *  (Arpit, 2026-11-04: "a cooldown of 10 seconds or 5 seconds maybe
         *  to show the strip again"). No longer rests per app or per day. */
        const val CROSS_QUIET = 10.0
        /** Typed past (a softer no than a ✕): no new chip for this long. */
        const val IGNORE_QUIET = 5.0
        /** Typed past = this many new words after the chip came, unused... */
        const val WORDS_PAST = 2
        /** ...and the chip was up at least this long. */
        const val SEEN_FOR = 1.0
        /** A copy is offered in the strip this long after it was made. */
        const val PASTE_FRESH = 3 * 60.0

        fun allowed(kind: Kind, field: Field): Boolean = when (field) {
            Field.NORMAL -> true
            Field.CODE -> kind == Kind.FILL || kind == Kind.PASTE || kind == Kind.MAIL
            Field.SECRET -> false
        }

        /** The end of the text a chip came for: its last 40 characters. */
        fun anchor(before: String): String = before.trimEnd().takeLast(40)

        /** How many new words follow [anchor] in [before], or null when the
         *  anchor is gone. A word glued to the anchor ("2+5" → "2+50") is
         *  the same word growing. */
        fun wordsPast(anchor: String, before: String): Int? {
            val rest = if (anchor.isEmpty()) before else {
                val i = before.lastIndexOf(anchor)
                if (i < 0) return null
                before.substring(i + anchor.length)
            }
            var count = 0
            var afterSpace = anchor.isEmpty()
            for (ch in rest) {
                if (ch.isWhitespace()) afterSpace = true
                else {
                    if (afterSpace) count++
                    afterSpace = false
                }
            }
            return count
        }
    }

    enum class Kind(val id: String) {
        /** A saved detail the field or sentence asks for, a temp address. */
        FILL("fill"),
        /** Something just copied. */
        PASTE("paste"),
        /** Worked out on the phone: sums, money, conversions, dates, weather. */
        ANSWER("answer"),
        /** The AI: "AI answer", the server's suggestion. */
        AI("ai"),
        /** A plan, a booking page, a Meet link. */
        PLAN("plan"),
        /** Send or Buy. */
        PAY("pay"),
        /** A mail at the temp address (its code): asked for, no cooldown. */
        MAIL("mail"),
    }

    enum class Field { NORMAL, CODE, SECRET }

    sealed class Timing {
        object Now : Timing()
        data class Wait(val seconds: Double) : Timing()
        object Words : Timing()
    }

    /** What the strip knows about the typing at this moment. */
    class Typing(
        val sinceEdit: Double,
        val midWord: Boolean,
        val undoOnOffer: Boolean,
        val fixPending: () -> Boolean = { false },
    )

    sealed class Seen {
        object Nothing : Seen()
        data class Ignored(val kind: Kind) : Seen()
        object PasteIgnored : Seen()
    }

    data class Shown(val id: String, val kind: Kind, val tail: String, val at: Double)

    /** This field only, never stored. */
    var field = ""; private set
    /** Crossed chips → the text they were crossed on: each stays away until
     *  that text changes. */
    val crossed = mutableMapOf<String, String>()
    var quietUntil = 0.0; private set
    var onScreen: Shown? = null; private set

    /** A new field forgets the last one's chips. */
    fun enter(field: String) {
        if (field == this.field) return
        this.field = field
        crossed.clear()
        quietUntil = 0.0
        onScreen = null
    }

    /** May this chip come at all (whatever the timing)? */
    fun allows(kind: Kind, id: String, now: Double): Boolean {
        if (id in crossed) return false
        if (kind == Kind.MAIL) return true
        if (quietUntil > now && onScreen?.id != id) return false
        return true
    }

    /** Now, later, or not over the words. */
    fun timing(kind: Kind, id: String, typing: Typing): Timing {
        if (onScreen?.id == id) return Timing.Now
        if (typing.undoOnOffer) return Timing.Words
        if (typing.midWord && kind != Kind.FILL) {
            if (typing.fixPending()) return Timing.Words
            return if (typing.sinceEdit >= MID_WORD_PAUSE) Timing.Now else Timing.Wait(MID_WORD_PAUSE - typing.sinceEdit)
        }
        return if (typing.sinceEdit >= SETTLE) Timing.Now else Timing.Wait(SETTLE - typing.sinceEdit)
    }

    /** A chip went up; [before] is the text before the caret. */
    fun shown(kind: Kind, id: String, before: String, now: Double) {
        if (onScreen?.id == id) return
        onScreen = Shown(id, kind, anchor(before), now)
    }

    /** Each pass, before chips: has the text moved on from a crossed chip,
     *  and has the chip that was up been typed past? */
    fun observe(before: String, now: Double): Seen {
        val tail = anchor(before)
        crossed.entries.removeAll { it.value != tail }
        val shown = onScreen ?: return Seen.Nothing
        if (shown.kind == Kind.PASTE) {
            if (before.isEmpty()) return Seen.Nothing
            onScreen = null
            return Seen.PasteIgnored
        }
        val past = wordsPast(shown.tail, before)
        if (past == null) {
            onScreen = null
            return Seen.Nothing
        }
        if (past < WORDS_PAST) return Seen.Nothing
        onScreen = null
        if (now - shown.at < SEEN_FOR || shown.kind == Kind.MAIL) return Seen.Nothing
        quietUntil = maxOf(quietUntil, now + IGNORE_QUIET)
        return Seen.Ignored(shown.kind)
    }

    /** The ✕: that chip goes until the text changes, and nothing else shows
     *  for [CROSS_QUIET]. */
    fun dismissed(kind: Kind, id: String, now: Double) {
        crossed[id] = onScreen?.takeIf { it.id == id }?.tail ?: ""
        if (onScreen?.id == id) onScreen = null
        if (kind == Kind.MAIL) return
        quietUntil = now + CROSS_QUIET
    }

    /** Tapped: wanted. */
    fun used() {
        onScreen = null
    }
}
