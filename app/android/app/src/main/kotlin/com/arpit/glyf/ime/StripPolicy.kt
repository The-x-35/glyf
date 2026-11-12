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

/** The strip's word slots never cut a word with "…" (D108; Arpit,
 *  2026-11-06: "Google reduces the font size of the word ... show the
 *  complete word"): a long word is drawn smaller, down to [SMALLEST]; one
 *  that doesn't fit even then gets the room it needs and the other slots
 *  share the rest, and when that leaves them too little the last word gives
 *  up its slot. Pure: the caller measures. StripPolicy.swift's
 *  SuggestionFit, with the same numbers and the same tests (sizes in sp,
 *  widths in whatever unit `measure`, `total`, `spacing` and `pad` share). */
object SuggestionFit {
    /** The smallest size a word is drawn at: Gboard's shrunk words stop
     *  about here, still easy to read. */
    const val SMALLEST = 11.0
    /** Air left beside a word inside its slot, both sides together (iOS
     *  points; the IME passes it in pixels). */
    const val PAD = 8.0
    const val STEP = 0.5

    /** [item] is the index of what's drawn in it (null for an empty slot),
     *  [size] its font size (0 for an empty slot). */
    data class Slot(val item: Int?, val width: Double, val size: Double)

    /** The biggest size, from [full] down to [SMALLEST] in half points, at
     *  which a word `measure(size)` wide fits [width]; null when even the
     *  smallest doesn't. */
    fun size(full: Double, width: Double, pad: Double = PAD, measure: (Double) -> Double): Double? {
        var s = full
        while (s >= SMALLEST - 0.001) {
            if (measure(s) + pad <= width) return s
            s -= STEP
        }
        return null
    }

    /** Slots for up to three items (best first) across [total], [spacing]
     *  apart: always three slots as the system bar has (an empty one for each
     *  word not offered), equal thirds whenever every word fits one.
     *  `full[i]` is item i's usual size; `measure(i, size)` its width. */
    fun plan(full: List<Double>, total: Double, spacing: Double, pad: Double = PAD,
             measure: (Int, Double) -> Double): List<Slot> {
        val offered = minOf(full.size, 3)
        val items = (0 until offered).toMutableList()
        val empty = 3 - offered
        while (items.isNotEmpty()) {
            val count = items.size + empty
            val inner = total - spacing * (count - 1)
            val equal = inner / count
            fun fitted(i: Int, width: Double) = size(full[i], width, pad) { measure(i, it) }
            val need = mutableMapOf<Int, Double>()
            for (i in items) if (fitted(i, equal) == null) need[i] = measure(i, SMALLEST) + pad
            var widths: List<Double>? = null
            if (need.isEmpty()) {
                widths = List(count) { equal }
            } else {
                val rest = inner - need.values.sum()
                val narrow = count - need.size
                if (narrow == 0) {
                    if (rest >= 0) widths = items.map { need.getValue(it) + rest / need.size }
                } else if (rest > 0) {
                    val share = rest / narrow
                    if (items.all { need[it] != null || fitted(it, share) != null }) {
                        widths = items.map { need[it] ?: share } + List(empty) { share }
                    }
                }
            }
            if (widths != null) {
                return (0 until count).map { j ->
                    if (j >= items.size) Slot(null, widths[j], 0.0)
                    else Slot(items[j], widths[j], fitted(items[j], widths[j]) ?: SMALLEST)
                }
            }
            // Too little room for everything: the last word goes.
            items.removeAt(items.size - 1)
        }
        val equal = (total - spacing * 2) / 3
        return List(3) { Slot(null, equal, 0.0) }
    }
}

/** A strip chip's words never end in "…" either (D108; Arpit, 2026-11-12,
 *  from the emulator: "Stop-loss 0.5 ETH at $2,800 · …"): they are drawn
 *  smaller, from their usual size down to [SMALLEST] in half points; when
 *  even that is too wide, the last " · " part (the chain, a busy note) goes
 *  whole and the rest is tried again from the usual size. Only the last
 *  part ever goes, so a bracket's "TP … · SL …" keeps both prices. Pure:
 *  the caller measures (`measure(text, size)`, in the unit of [width]). */
object ChipFit {
    const val SMALLEST = 11.0
    const val STEP = 0.5
    const val SEPARATOR = " · "

    data class Fit(val text: String, val size: Double, val fits: Boolean)

    /** What may be shown, longest first: the whole, then without its last part. */
    fun candidates(value: String): List<String> {
        val cut = value.lastIndexOf(SEPARATOR)
        return if (cut > 0) listOf(value, value.substring(0, cut)) else listOf(value)
    }

    /** The first candidate that fits [width] at the biggest size from [full]
     *  down to [SMALLEST]. When nothing does, the shortest at [SMALLEST]
     *  (`fits` false: the view clips it, still without a "…"). */
    fun fit(value: String, full: Double, width: Double, measure: (String, Double) -> Double): Fit {
        val all = candidates(value)
        for (text in all) {
            SuggestionFit.size(full, width, pad = 0.0) { measure(text, it) }?.let { return Fit(text, it, true) }
        }
        return Fit(all.last(), SMALLEST, false)
    }
}

/** A chip's words, fitted to the room the chip gives them (ChipFit): never
 *  an ellipsis. [fullSp] is the usual size. */
class FittedText(ctx: android.content.Context, private val value: String, private val fullSp: Float) :
    android.widget.TextView(ctx) {
    init {
        text = value
        textSize = fullSp
        maxLines = 1
        isSingleLine = true
        ellipsize = null
        contentDescription = value
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w == oldw || w <= 0) return
        val room = (w - paddingLeft - paddingRight).toDouble()
        val scale = resources.displayMetrics.scaledDensity
        val probe = android.text.TextPaint(paint)
        val f = ChipFit.fit(value, fullSp.toDouble(), room) { t, sp ->
            probe.textSize = (sp * scale).toFloat()
            probe.measureText(t).toDouble()
        }
        post {
            if (text.toString() != f.text) text = f.text
            if (textSize != (f.size * scale).toFloat()) setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, f.size.toFloat())
        }
    }
}
