package com.demo.glyf.ime.typing

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * What this person types, kept on the device (FORMAT.md "Learning"). Mirror
 * of Engine/Typing/PersonalLexicon.swift, including the JSON it saves as, so
 * the app can show "My words" on either platform.
 */
class PersonalLexicon {

    data class Word(var form: String, var commits: Double, var total: Int, var day: Int,
                    var kept: Int = 0, var added: Boolean = false)

    data class Pair(var count: Double, var day: Int)

    companion object {
        const val HALF_LIFE_DAYS = 90.0
        const val EXPIRY_DAYS = 300
        const val MAX_WORDS = 10_000
        const val MAX_PAIRS = 30_000
        private const val SEP = "\u001F"

        fun fromJson(json: JSONObject): PersonalLexicon {
            val l = PersonalLexicon()
            l.commitsTotal = json.optDouble("total", 0.0)
            json.optJSONArray("words")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    l.words[o.getString("k")] = Word(o.getString("f"), o.optDouble("c", 0.0), o.optInt("t", 0),
                        o.optInt("d", 0), o.optInt("kept", 0), o.optBoolean("added", false))
                }
            }
            json.optJSONArray("pairs")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    l.pairs[o.getString("p") + SEP + o.getString("k")] = Pair(o.optDouble("c", 0.0), o.optInt("d", 0))
                }
            }
            json.optJSONArray("rejected")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    l.rejected[o.getString("typed") + SEP + o.getString("fix")] = o.optInt("n", 1)
                }
            }
            json.optJSONArray("blocked")?.let { arr -> for (i in 0 until arr.length()) l.blocked.add(arr.getString(i)) }
            l.editsAppliedAt = json.optDouble("editsAt", 0.0)
            return l
        }
    }

    val words = HashMap<String, Word>()
    val pairs = HashMap<String, Pair>()
    val rejected = HashMap<String, Int>()
    val blocked = HashSet<String>()
    var commitsTotal = 0.0
        private set
    /** Newest app edit ("My words": add, forget, reset) already applied. */
    var editsAppliedAt = 0.0

    fun toJson(): JSONObject = JSONObject().apply {
        put("v", 1)
        put("total", commitsTotal)
        put("words", JSONArray().apply {
            for ((k, w) in words.entries.sortedBy { it.key }) put(JSONObject().apply {
                put("k", k); put("f", w.form); put("c", w.commits); put("t", w.total)
                put("d", w.day); put("kept", w.kept); put("added", w.added)
            })
        })
        put("pairs", JSONArray().apply {
            for ((k, p) in pairs.entries.sortedBy { it.key }) {
                val parts = k.split(SEP)
                put(JSONObject().apply { put("p", parts[0]); put("k", parts[1]); put("c", p.count); put("d", p.day) })
            }
        })
        put("rejected", JSONArray().apply {
            for ((k, n) in rejected.entries.sortedBy { it.key }) {
                val parts = k.split(SEP)
                put(JSONObject().apply { put("typed", parts[0]); put("fix", parts[1]); put("n", n) })
            }
        })
        put("blocked", JSONArray(blocked.sorted()))
        put("editsAt", editsAppliedAt)
    }

    // Reading

    fun word(key: String): Word? = words[key]

    /** Typed twice, kept once, or added: never autocorrected away again. */
    fun isKnown(key: String): Boolean {
        val w = words[key] ?: return false
        return w.total >= 2 || w.kept > 0 || w.added
    }

    fun isBlocked(key: String): Boolean = key in blocked

    fun isRejected(typed: String, correction: String): Boolean =
        rejected.containsKey(typed.lowercase() + SEP + correction.lowercase())

    /** AOSP-scale probability (0–255) this person gives the word, if any. */
    fun probability(key: String, today: Int): Float? {
        val w = words[key] ?: return null
        if (key in blocked) return null
        var f = 0f
        if (w.total >= 2) {
            val effective = decayed(w.commits, w.day, today)
            val p = max(effective - 1, 0.5) / max(commitsTotal, 8192.0)
            f = (255 + 8.59 * log2(p) - 32).toFloat()
        }
        if (w.kept > 0) f = max(f, 120f)
        if (w.added) f = max(f, 160f)
        return if (f > 0f) min(f, 255f) else null
    }

    fun pairProbability(previous: String, key: String, today: Int): Float? {
        val pair = pairs[previous + SEP + key] ?: return null
        val prev = words[previous] ?: return null
        if (key in blocked) return null
        val count = decayed(pair.count, pair.day, today)
        val prevCount = max(decayed(prev.commits, prev.day, today), 2.0)
        val f = (255 + 8.59 * log2(min(count / prevCount, 1.0)) - 4).toFloat()
        return if (f > 0f) min(f, 255f) else null
    }

    /** Words this person has followed `previous` with, most frequent first. */
    fun nextWords(previous: String, today: Int): List<kotlin.Pair<String, Float>> {
        val prefix = previous + SEP
        val out = ArrayList<kotlin.Pair<String, Float>>()
        for (k in pairs.keys) {
            if (!k.startsWith(prefix)) continue
            val key = k.substring(prefix.length)
            val w = words[key] ?: continue
            val f = pairProbability(previous, key, today) ?: continue
            out.add(w.form to f)
        }
        return out.sortedByDescending { it.second }
    }

    /** Learned, kept and added words — the ones a dictionary may not have. */
    /** The word this person uses most that starts with what is being typed
     *  (and is longer): "cut" → their "cutee". PersonalLexicon.swift's twin. */
    fun completion(prefix: String, today: Int): String? = words.entries
        .filter { (k, _) -> k.length > prefix.length && k.startsWith(prefix) && isKnown(k) && k !in blocked }
        .maxByOrNull { (_, w) -> decayed(w.commits, w.day, today) + w.kept + (if (w.added) 2.0 else 0.0) }
        ?.value?.form

    fun knownForms(): List<kotlin.Pair<String, String>> =
        words.entries.filter { isKnown(it.key) && it.key !in blocked }.map { it.key to it.value.form }

    // Changing

    fun commit(form: String, previous: String?, today: Int) {
        val key = TypingText.key(form)
        if (key.isEmpty() || key in blocked) return
        val w = words[key] ?: Word(form, 0.0, 0, today)
        w.commits = decayed(w.commits, w.day, today) + 1
        w.total += 1
        w.day = today
        w.form = form
        words[key] = w
        commitsTotal += 1
        if (previous != null) {
            val prev = TypingText.key(previous)
            if (prev.isNotEmpty() && words.containsKey(prev)) {
                val pk = prev + SEP + key
                val pair = pairs[pk] ?: Pair(0.0, today)
                pair.count = decayed(pair.count, pair.day, today) + 1
                pair.day = today
                pairs[pk] = pair
            }
        }
        prune(today)
    }

    /** The user undid `typed` → `correction`: never offer it again, keep the
     *  typed word, and take back the commit the correction earned. */
    fun revert(typed: String, correction: String, today: Int) {
        val rk = typed.lowercase() + SEP + correction.lowercase()
        rejected[rk] = (rejected[rk] ?: 0) + 1
        keep(typed, today)
        val ck = TypingText.key(correction)
        val w = words[ck]
        if (w != null && w.total > 0) {
            w.total -= 1
            w.commits = max(decayed(w.commits, w.day, today) - 1, 0.0)
            w.day = today
            if (w.total == 0 && w.kept == 0 && !w.added) words.remove(ck)
            commitsTotal = max(commitsTotal - 1, 0.0)
        }
    }

    /** The user chose exactly what they typed (a revert or the literal slot). */
    fun keep(typed: String, today: Int) {
        val key = TypingText.key(typed)
        if (key.isEmpty()) return
        blocked.remove(key)
        val w = words[key] ?: Word(typed, 0.0, 0, today)
        w.kept += 1
        w.day = today
        words[key] = w
    }

    fun add(form: String, today: Int) {
        val key = TypingText.key(form)
        if (key.isEmpty()) return
        blocked.remove(key)
        val w = words[key] ?: Word(form, 0.0, 0, today)
        w.added = true
        w.form = form
        w.day = today
        words[key] = w
    }

    /** Removed in the app: forgotten, and never learned or offered again. */
    fun forget(form: String) {
        val key = TypingText.key(form)
        if (key.isEmpty()) return
        words.remove(key)
        pairs.keys.removeAll { it.startsWith(key + SEP) || it.endsWith(SEP + key) }
        // Its corrections come back too: a word forgotten in "My words" is
        // corrected again ("helloo" stayed uncorrected forever).
        val typed = form.lowercase()
        rejected.keys.removeAll { it.startsWith(typed + SEP) }
        blocked.add(key)
    }

    fun unblock(form: String) { blocked.remove(TypingText.key(form)) }

    /** A correction turned down, on its own (a revert also keeps the word). */
    fun reject(typed: String, correction: String) {
        val k = typed.lowercase() + SEP + correction.lowercase()
        rejected[k] = (rejected[k] ?: 0) + 1
    }

    fun reset() {
        words.clear(); pairs.clear(); rejected.clear(); blocked.clear(); commitsTotal = 0.0
    }

    fun prune(today: Int) {
        if (words.size > MAX_WORDS + 500) {
            val keep = words.entries.sortedByDescending { decayed(it.value.commits, it.value.day, today) + it.value.kept * 4.0 }
                .take(MAX_WORDS).map { it.key }.toHashSet()
            words.keys.retainAll(keep)
        }
        if (pairs.size > MAX_PAIRS + 1_500) {
            val keep = pairs.entries.sortedByDescending { decayed(it.value.count, it.value.day, today) }
                .take(MAX_PAIRS).map { it.key }.toHashSet()
            pairs.keys.retainAll(keep)
        }
    }

    /** Drops what hasn't been used in 300 days. Run on load. */
    fun expire(today: Int) {
        words.entries.removeAll { !it.value.added && today - it.value.day > EXPIRY_DAYS }
        pairs.entries.removeAll { today - it.value.day > EXPIRY_DAYS }
    }

    private fun decayed(value: Double, day: Int, today: Int): Double =
        if (today <= day) value else value * 2.0.pow(-(today - day).toDouble() / HALF_LIFE_DAYS)
}
