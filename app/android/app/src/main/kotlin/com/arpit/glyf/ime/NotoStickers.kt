package com.arpit.glyf.ime

/**
 * Google's Noto Animated Emoji as stickers, searched on the phone (twin of
 * NotoStickers.swift): the server's catalogue and search
 * (server/src/routes/media.ts, `searchNoto` and `notoItem`) ported as they
 * are, so the Stickers tab needs no request to list them, only the CDN for
 * the images (docs/SERVER-INVENTORY.md, 2026-10-14). Same items, same order,
 * same pages of 30 and the same credit as GET /media/emoji-stickers, which
 * stays for older versions.
 */
object NotoStickers {

    /** `c` codepoints ("1f602"), `t` short names, `g` category. */
    data class Sticker(val c: String, val t: List<String>, val g: String)

    const val CDN = "https://fonts.gstatic.com/s/e/notoemoji/latest"
    const val ATTRIBUTION = "Noto Emoji by Google · CC BY 4.0"
    const val PAGE = 30

    /** The catalogue, most popular first (NotoCatalogue.kt). */
    val catalogue: List<Sticker> by lazy {
        NotoCatalogue.LINES.split('\n').mapNotNull { line ->
            val parts = line.split('|')
            if (parts.size != 3) null
            else Sticker(parts[0], parts[2].split(',').filter { it.isNotEmpty() }, parts[1])
        }
    }

    /** The words people search stickers with, in the catalogue's own names. */
    private val SYNONYMS: Map<String, List<String>> = mapOf(
        "hello" to listOf("wave"), "hi" to listOf("wave"), "hey" to listOf("wave"), "bye" to listOf("wave"),
        "wow" to listOf("surprised", "hushed", "astonished", "mind-blown", "open-mouth", "star-struck", "exploding-head"),
        "omg" to listOf("scream", "mind-blown", "astonished", "flushed"),
        "love" to listOf("heart", "heart-eyes", "heart-face", "kissing-heart", "love-letter"),
        "laughing" to listOf("joy", "laughing", "rofl", "rolling-on-the-floor-laughing", "grin", "sweat-smile"),
        "haha" to listOf("joy", "laughing", "rofl", "rolling-on-the-floor-laughing", "grin"),
        "lol" to listOf("joy", "laughing", "rofl", "rolling-on-the-floor-laughing"),
        "happy" to listOf("smile", "grin", "blush", "warm-smile", "joy", "partying-face"),
        "sad" to listOf("sad", "cry", "loudly-crying", "pensive", "disappointed", "worried", "pleading"),
        "cry" to listOf("cry", "loudly-crying", "happy-cry"),
        "angry" to listOf("angry", "rage", "steam", "cursing", "triumph"),
        "party" to listOf("partying-face", "party-popper", "confetti", "balloon", "tada"),
        "celebrate" to listOf("partying-face", "party-popper", "confetti", "clap", "fireworks"),
        "thank you" to listOf("thank-you", "folded-hands", "pray", "heart-hands"),
        "thanks" to listOf("thank-you", "folded-hands", "pray", "heart-hands"),
        "please" to listOf("please", "pleading", "folded-hands"),
        "sleepy" to listOf("sleep", "sleepy", "yawn", "zzz"),
        "tired" to listOf("sleep", "sleepy", "yawn", "weary", "tired"),
        "thumbs up" to listOf("thumbs-up", "+1", "ok", "clap"), "yes" to listOf("thumbs-up", "+1", "ok", "check"),
        "no" to listOf("thumbs-down", "-1", "cross", "x", "no"), "ok" to listOf("ok", "thumbs-up", "+1"),
        "cool" to listOf("sunglasses", "cool", "smirk"), "think" to listOf("thinking-face", "monocle"),
        "birthday" to listOf("birthday-cake", "partying-face", "party-popper", "gift", "balloon"),
        "fire" to listOf("fire", "lit"), "hot" to listOf("fire", "hot-face"), "cold" to listOf("cold-face", "snowflake"),
        "kiss" to listOf("kissing", "kissing-heart", "kiss"), "hug" to listOf("hug-face", "hugging"),
        "sick" to listOf("sick", "nauseated", "mask", "thermometer", "sneeze"),
        "money" to listOf("money-face", "money-with-wings", "dollar"), "scared" to listOf("scream", "fearful", "anxious"),
        "dance" to listOf("dancer", "man-dancing"), "music" to listOf("musical-notes", "microphone", "headphone"),
    )

    private val CATEGORY_WORDS: Map<String, String> = mapOf(
        "food" to "food", "drink" to "food", "animal" to "animals", "animals" to "animals", "pet" to "animals",
        "nature" to "animals", "sport" to "activities", "sports" to "activities", "travel" to "travel",
        "flag" to "flags", "flags" to "flags", "object" to "objects", "objects" to "objects", "symbol" to "symbols",
        "symbols" to "symbols", "face" to "smileys", "faces" to "smileys", "smiley" to "smileys", "smileys" to "smileys",
    )

    /** Words a name answers to: "loudly-crying" answers "loudly", "crying"
     *  and the whole name. */
    private fun words(name: String): List<String> = listOf(name) + name.split('-', '_')

    private val SPACES = Regex("\\s+")

    /** Stickers for a search, best first; empty `q` is the whole catalogue
     *  by popularity (the "trending" of a fixed set). */
    fun search(q: String): List<Sticker> {
        val all = catalogue
        val query = q.trim().lowercase()
        if (query.isEmpty()) return all
        val split = query.split(SPACES)
        val wanted = LinkedHashSet<String>().apply { add(query); addAll(split) }
        for (w in wanted.toList()) SYNONYMS[w]?.let { wanted.addAll(it) }
        val category = split.firstNotNullOfOrNull { CATEGORY_WORDS[it] }
        data class Scored(val s: Sticker, val score: Int, val rank: Int)
        val scored = ArrayList<Scored>()
        all.forEachIndexed { rank, s ->
            var score = 0
            for (tag in s.t) {
                if (tag in wanted) score = maxOf(score, 3)
                else if (words(tag).any { it in wanted }) score = maxOf(score, 2)
                else if (wanted.any { it.length >= 3 && tag.startsWith(it) }) score = maxOf(score, 1)
            }
            if (category != null && s.g == category) score = maxOf(score, 1)
            if (score > 0) scored += Scored(s, score, rank)
        }
        return scored.sortedWith(compareByDescending<Scored> { it.score }.thenBy { it.rank }).map { it.s }
    }

    fun item(s: Sticker): MediaItem = MediaItem(
        id = "noto:${s.c}",
        title = (s.t.firstOrNull() ?: "emoji").replace("-", " "),
        preview = "$CDN/${s.c}/128.png", pw = 128.0, ph = 128.0,
        url = "$CDN/${s.c}/512.gif", w = 512.0, h = 512.0,
    )

    /** One page of a search, as GET /media/emoji-stickers?q=&page= answers. */
    fun page(query: String, page: String?): MediaPage {
        val n = (page?.toIntOrNull() ?: 1).coerceIn(1, 100)
        val hits = search(query.take(60))
        val start = (n - 1) * PAGE
        val items = if (start < hits.size) hits.subList(start, minOf(start + PAGE, hits.size)).map(::item) else emptyList()
        return MediaPage(items, if (start + PAGE < hits.size) (n + 1).toString() else null, ATTRIBUTION)
    }
}
