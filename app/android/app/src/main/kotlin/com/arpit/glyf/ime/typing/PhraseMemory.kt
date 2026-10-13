package com.arpit.glyf.ime.typing

import android.content.Context
import org.json.JSONObject
import java.io.File

/** The person's own repeated sentences: once a sentence has been sent three
 *  times ("On my way, be there in 10"), typing its first words offers the
 *  rest in the strip. Kept on the phone only, never from a password field
 *  or anything the secret scanner flags, forgotten after 60 days unused.
 *  The twin of PhraseMemory.swift. */
class PhraseMemory {
    data class Entry(var text: String, var count: Int, var last: Int)

    val entries = LinkedHashMap<String, Entry>()

    companion object {
        const val TIMES_BEFORE_OFFERED = 3
        const val KEEP_DAYS = 60
        const val MOST = 300

        fun key(s: String): String =
            s.lowercase().replace(Regex("""\s+"""), " ").trim().trimEnd('.', '!', '?', '…').trim()

        fun worthKeeping(s: String): Boolean {
            val t = s.trim()
            if (t.length < 15 || t.length > 140 || t.split(" ").filter { it.isNotEmpty() }.size < 4) return false
            if (Regex("""\d{4,}|https?://|www\.|@[\w-]+\.\w""").containsMatchIn(t)) return false
            return com.arpit.glyf.store.SecretScanner.scan(t) == null
        }

        /** The sentence a text has just finished ("…ok. On my way! " → "On my way!"). */
        fun endedSentence(text: String): String? {
            val last = text.lastOrNull() ?: return null
            if (last != ' ' && last != '\n') return null
            val body = text.trim()
            if (body.isEmpty() || body.last() !in ".!?") return null
            return lastSentence(body)
        }

        /** What follows the last full stop, question or exclamation mark, or line break. */
        fun lastSentence(text: String): String {
            var end = text.length
            while (end > 0 && (text[end - 1] in ".!?" || text[end - 1] == ' ')) end--
            var start = end
            while (start > 0 && text[start - 1] !in ".!?\n") start--
            return text.substring(start).trim()
        }

        fun fromJson(json: JSONObject?): PhraseMemory {
            val m = PhraseMemory()
            val all = json?.optJSONObject("entries") ?: return m
            for (k in all.keys()) {
                val e = all.optJSONObject(k) ?: continue
                m.entries[k] = Entry(e.optString("text"), e.optInt("count"), e.optInt("last"))
            }
            return m
        }
    }

    fun toJson(): JSONObject = JSONObject().put("entries", JSONObject().also { o ->
        for ((k, e) in entries) o.put(k, JSONObject().put("text", e.text).put("count", e.count).put("last", e.last))
    })

    fun record(sentence: String, today: Int) {
        if (!worthKeeping(sentence)) return
        val k = key(sentence)
        val e = entries.getOrPut(k) { Entry(sentence, 0, today) }
        e.count += 1
        e.last = today
        e.text = sentence.trim()
        prune(today)
    }

    fun prune(today: Int) {
        entries.entries.removeAll { today - it.value.last > KEEP_DAYS }
        if (entries.size > MOST) {
            val keep = entries.entries.sortedWith(compareByDescending<Map.Entry<String, Entry>> { it.value.count }
                .thenByDescending { it.value.last }).take(MOST).map { it.key to it.value }
            entries.clear(); keep.forEach { (k, v) -> entries[k] = v }
        }
    }

    /** The rest of a remembered sentence that starts with what is being
     *  typed, offered once a word ends: two words typed, two to come. */
    fun completion(typed: String, today: Int): String? {
        if (typed.lastOrNull()?.isWhitespace() != true || typed.endsWith("\n")) return null
        val sentence = lastSentence(typed)
        val k = key(sentence)
        if (k.length < 5 || k.split(" ").size < 2) return null
        val best = entries.values.filter {
            it.count >= TIMES_BEFORE_OFFERED && today - it.last <= KEEP_DAYS &&
                key(it.text).startsWith(k) && key(it.text).length > k.length
        }.maxWithOrNull(compareBy<Entry> { it.count }.thenBy { it.last }) ?: return null
        val typedWords = sentence.split(" ").filter { it.isNotEmpty() }.size
        val words = best.text.split(" ").filter { it.isNotEmpty() }
        if (words.size < typedWords + 2) return null
        return words.drop(typedWords).joinToString(" ")
    }
}

/** Where the keyboard keeps PhraseMemory: files/phrases.json, never backed up. */
object PhraseMemoryStore {
    private const val FILE = "phrases.json"
    @Volatile private var memory: PhraseMemory? = null

    private fun file(ctx: Context) = File(ctx.noBackupFilesDir, FILE)

    fun get(ctx: Context): PhraseMemory = memory ?: synchronized(this) {
        memory ?: PhraseMemory.fromJson(runCatching { JSONObject(file(ctx).readText()) }.getOrNull()).also { memory = it }
    }

    fun record(ctx: Context, sentence: String) {
        val m = get(ctx)
        val before = m.toJson().toString()
        m.record(sentence, TypingText.day())
        val after = m.toJson().toString()
        if (after != before) runCatching { file(ctx).writeText(after) }
    }
}
