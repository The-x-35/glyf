package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject

/** When the strip shows a chip instead of its three word slots, and what a ✕
 *  (or typing past a chip) does to the chips after it. docs/STRIP-POLICY.md
 *  is the decision table; iOS's StripPolicy.swift is the twin, with the same
 *  numbers and the same tests.
 *
 *  Pure: the caller hands in the time (seconds), the field and the app, and
 *  stores [json] (glyf_ime prefs, "stripPolicy"). */
class StripPolicy() {

    companion object {
        /** A new chip waits for the fingers to stop this long at a word
         *  boundary (a fast typist's keys are 150 to 250 ms apart). */
        const val SETTLE = 0.4
        /** Mid-word the word slots keep the strip; a chip may take over only
         *  after a longer pause, and never over a pending fix. */
        const val MID_WORD_PAUSE = 1.0
        /** After a ✕ or a chip typed past, no other new chip for this long. */
        const val GAP = 8.0
        /** Typed past = this many new words after the chip came, unused... */
        const val WORDS_PAST = 2
        /** ...and the chip was up at least this long. */
        const val SEEN_FOR = 1.0
        /** Typed past this many times counts as one ✕ for that kind in that app. */
        const val IGNORES_PER_DISMISSAL = 2
        /** A ✕ mutes that kind of chip in that app for this long. */
        const val APP_MUTE = 10 * 60.0
        /** This many ✕ of one kind within [BACKOFF_WINDOW], anywhere... */
        const val BACKOFF_AFTER = 3
        const val BACKOFF_WINDOW = 24 * 60 * 60.0
        /** ...mute that kind everywhere for this long. */
        const val BACKOFF = 24 * 60 * 60.0
        /** A copy is offered in the strip this long after it was made. */
        const val PASTE_FRESH = 3 * 60.0
        /** Stored entries kept at most (newest first). */
        const val MAX_ENTRIES = 48

        fun allowed(kind: Kind, field: Field): Boolean = when (field) {
            Field.NORMAL -> true
            Field.CODE -> kind == Kind.FILL || kind == Kind.PASTE || kind == Kind.MAIL
            Field.SECRET -> false
        }

        fun key(scope: String, kind: Kind) = "$scope|${kind.id}"

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
        /** A mail at the temp address (its code): asked for, never muted. */
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

    /** "scope|kind" → until (seconds since 1970). */
    val mutes = mutableMapOf<String, Double>()
    /** kind → until. */
    val backoffs = mutableMapOf<String, Double>()
    /** kind → when each ✕ was (the last day's). */
    val refusals = mutableMapOf<String, MutableList<Double>>()
    /** "scope|kind" → (typed-past count, when last). */
    val softs = mutableMapOf<String, Pair<Int, Double>>()

    /** The field's own memory, never stored. */
    var field = ""; private set
    val gone = mutableSetOf<String>()
    var quietUntil = 0.0; private set
    var onScreen: Shown? = null; private set

    /** A new field forgets the last one's chips. */
    fun enter(field: String) {
        if (field == this.field) return
        this.field = field
        gone.clear()
        quietUntil = 0.0
        onScreen = null
    }

    /** May this chip come at all (whatever the timing)? */
    fun allows(kind: Kind, id: String, scope: String, now: Double): Boolean {
        if (id in gone) return false
        if (kind == Kind.MAIL) return true
        if ((backoffs[kind.id] ?: 0.0) > now) return false
        if (kind != Kind.PASTE && (mutes[key(scope, kind)] ?: 0.0) > now) return false
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

    /** Each pass, before chips: has the chip that was up been typed past? */
    fun observe(before: String, scope: String, now: Double): Seen {
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
        gone += shown.id
        quietUntil = now + GAP
        val k = key(scope, shown.kind)
        val count = (softs[k]?.first ?: 0) + 1
        if (count >= IGNORES_PER_DISMISSAL) {
            softs.remove(k)
            refuse(shown.kind, scope, now)
        } else {
            softs[k] = count to now
        }
        return Seen.Ignored(shown.kind)
    }

    /** The ✕. */
    fun dismissed(kind: Kind, id: String, scope: String, now: Double) {
        gone += id
        if (onScreen?.id == id) onScreen = null
        if (kind == Kind.MAIL) return
        quietUntil = now + GAP
        refuse(kind, scope, now)
    }

    /** Tapped: wanted. Typed-past counts for that kind start over. */
    fun used(kind: Kind, scope: String) {
        onScreen = null
        softs.remove(key(scope, kind))
    }

    private fun refuse(kind: Kind, scope: String, now: Double) {
        // Each copy is news: a ✕ on one says nothing about the next in this app.
        if (kind != Kind.PASTE) mutes[key(scope, kind)] = now + APP_MUTE
        val times = (refusals[kind.id] ?: mutableListOf()).filter { now - it < BACKOFF_WINDOW }.toMutableList()
        times += now
        if (times.size >= BACKOFF_AFTER) {
            backoffs[kind.id] = now + BACKOFF
            refusals.remove(kind.id)
        } else {
            refusals[kind.id] = times
        }
        prune(now)
    }

    /** Expired entries go; past [MAX_ENTRIES] the oldest go. */
    fun prune(now: Double) {
        mutes.entries.removeAll { it.value <= now }
        backoffs.entries.removeAll { it.value <= now }
        for (k in refusals.keys.toList()) {
            val kept = refusals[k]!!.filter { now - it < BACKOFF_WINDOW }
            if (kept.isEmpty()) refusals.remove(k) else refusals[k] = kept.toMutableList()
        }
        softs.entries.removeAll { now - it.value.second >= BACKOFF_WINDOW }
        if (mutes.size > MAX_ENTRIES) {
            val keep = mutes.entries.sortedByDescending { it.value }.take(MAX_ENTRIES).map { it.key }.toSet()
            mutes.keys.retainAll(keep)
        }
        if (softs.size > MAX_ENTRIES) {
            val keep = softs.entries.sortedByDescending { it.value.second }.take(MAX_ENTRIES).map { it.key }.toSet()
            softs.keys.retainAll(keep)
        }
    }

    fun json(): JSONObject = JSONObject().apply {
        put("v", 1)
        put("mutes", JSONObject(mutes as Map<*, *>))
        put("backoffs", JSONObject(backoffs as Map<*, *>))
        put("refusals", JSONObject().also { o -> refusals.forEach { (k, v) -> o.put(k, JSONArray(v)) } })
        put("softs", JSONObject().also { o ->
            softs.forEach { (k, v) -> o.put(k, JSONArray().put(v.first.toDouble()).put(v.second)) }
        })
    }

    constructor(json: JSONObject?) : this() {
        restore(json)
    }

    /** The stored part again (a scenario's reset); the field's own memory stays. */
    fun restore(json: JSONObject?) {
        mutes.clear(); backoffs.clear(); refusals.clear(); softs.clear()
        if (json == null) return
        json.optJSONObject("mutes")?.let { o -> o.keys().forEach { mutes[it] = o.getDouble(it) } }
        json.optJSONObject("backoffs")?.let { o -> o.keys().forEach { backoffs[it] = o.getDouble(it) } }
        json.optJSONObject("refusals")?.let { o ->
            o.keys().forEach { k ->
                val a = o.getJSONArray(k)
                refusals[k] = MutableList(a.length()) { a.getDouble(it) }
            }
        }
        json.optJSONObject("softs")?.let { o ->
            o.keys().forEach { k ->
                val a = o.getJSONArray(k)
                if (a.length() == 2) softs[k] = a.getDouble(0).toInt() to a.getDouble(1)
            }
        }
    }
}
