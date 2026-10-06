package com.arpit.glyf.ime

/**
 * The emoji board's data, generated from the iOS keyboard's EmojiData.swift
 * and EmoticonData.swift (2026-09-24) so both keyboards carry the same lists,
 * in Apple's nine tabs. Regenerate rather than edit by hand.
 */
/**
 * The emoji board's data: every emoji on Apple's keyboard (iOS 26.5), in its
 * eight tabs and its order (Arpit, 2026-10-03: "make sure we are not missing
 * any emoji compared to apple"), with Unicode's name and Emoji version for
 * each, CLDR's English keywords for search, and its skin tones. The table is
 * shared/emoji/emoji.tsv (tools/emoji/build.py), shipped in assets; iOS
 * embeds the same table. An emoji this phone's font can't draw is left out:
 * by its Emoji version until the font has been asked (Paint.hasGlyph, once
 * per system build), then by the font's own answer.
 */
object EmojiData {

    class Emoji(val emoji: String, val version: String, val name: String, val keywords: List<String>,
                /** Skin-tone variants with their own Emoji versions. */
                val tones: List<Pair<String, String>>)

    class Table(val tabs: List<Pair<String, List<Emoji>>>, val byEmoji: Map<String, Emoji>,
                /** A toned emoji's own ("👍🏽" → "👍"). */
                val toneBase: Map<String, String>, val seed: List<String>)

    @Volatile private var table: Table? = null
    @Volatile private var text: String? = null

    /** The newest Emoji version each Android release draws (Noto Color Emoji). */
    fun newestFor(sdk: Int): Double = when {
        sdk >= 37 -> 17.0
        sdk >= 36 -> 16.0
        sdk >= 35 -> 15.1
        sdk >= 34 -> 15.0
        sdk >= 32 -> 14.0
        sdk >= 31 -> 13.1
        sdk >= 30 -> 13.0
        else -> 12.1
    }

    /** Reads the table once; asks the font about every emoji in the background
     *  when this system build hasn't been asked yet. */
    fun load(context: android.content.Context) {
        if (table != null) return
        val raw = text ?: context.assets.open("emoji.tsv").bufferedReader().use { it.readText() }.also { text = it }
        val cache = java.io.File(context.filesDir, "emoji-missing.txt")
        val build = android.os.Build.FINGERPRINT ?: ""
        val cached = runCatching { cache.readLines() }.getOrNull()?.takeIf { it.firstOrNull() == build }
        if (cached != null) {
            val missing = cached.drop(1).toHashSet()
            table = parse(raw) { e, _ -> e !in missing }
            return
        }
        val newest = newestFor(android.os.Build.VERSION.SDK_INT)
        table = parse(raw) { _, v -> (v.toDoubleOrNull() ?: 99.0) <= newest }
        Thread {
            val paint = android.graphics.Paint()
            val all = parse(raw) { _, _ -> true }
            val missing = mutableListOf<String>()
            for (e in all.byEmoji.values) {
                if (!paint.hasGlyph(e.emoji)) missing += e.emoji
                for ((t, _) in e.tones) if (!paint.hasGlyph(t)) missing += t
            }
            runCatching { cache.writeText((listOf(build) + missing).joinToString("\n")) }
            val gone = missing.toHashSet()
            table = parse(raw) { e, _ -> e !in gone }
        }.start()
    }

    /** The table, with [drawable] deciding what this phone can show. */
    fun parse(text: String, drawable: (emoji: String, version: String) -> Boolean): Table {
        val tabs = linkedMapOf<String, MutableList<Emoji>>()
        val byEmoji = HashMap<String, Emoji>()
        val toneBase = HashMap<String, String>()
        var seed = emptyList<String>()
        for (line in text.lineSequence()) {
            if (line.startsWith("# seed: ")) { seed = line.removePrefix("# seed: ").split(" ").filter { it.isNotEmpty() }; continue }
            if (line.isEmpty() || line.startsWith("#")) continue
            val f = line.split("\t")
            if (f.size < 7 || !drawable(f[1], f[2])) continue
            val variants = if (f[5].isEmpty()) emptyList() else f[5].split(",")
            val versions = f[6].split(",")
            val tones = variants.mapIndexed { i, v -> v to (if (versions.size == variants.size) versions[i] else versions.firstOrNull() ?: f[2]) }
                .filter { (v, ver) -> drawable(v, ver) }
            val e = Emoji(f[1], f[2], f[3], if (f[4].isEmpty()) emptyList() else f[4].split("|"), tones)
            tabs.getOrPut(f[0]) { mutableListOf() }.add(e)
            byEmoji[f[1]] = e
            for ((t, _) in tones) toneBase[t] = f[1]
        }
        return Table(tabs.map { it.key to it.value }, byEmoji, toneBase, seed.filter { it in byEmoji })
    }

    /** For tests: a table read from text, everything drawable. */
    fun use(text: String) { table = parse(text) { _, _ -> true } }

    /** Apple's eight tabs after Frequently Used: the tab and its emoji. */
    val categories: List<Pair<String, List<String>>>
        get() = table?.tabs?.map { (id, list) -> id to list.map { it.emoji } }.orEmpty()

    val titles = mapOf(
        "recents" to "FREQUENTLY USED",
        "smileys" to "SMILEYS & PEOPLE",
        "animals" to "ANIMALS & NATURE",
        "food" to "FOOD & DRINK",
        "activity" to "ACTIVITY",
        "travel" to "TRAVEL & PLACES",
        "objects" to "OBJECTS",
        "symbols" to "SYMBOLS",
        "flags" to "FLAGS",
    )

    /** Frequently Used before anything has been used: the world's most used
     *  emoji (Unicode's 2021 ranking). */
    val seed: List<String> get() = table?.seed.orEmpty()

    fun info(emoji: String): Emoji? = table?.byEmoji?.get(emoji)

    /** The emoji and its five tones, as a long press shows them. Two-person
     *  emoji have 25 (a tone each); the five where both match are shown. */
    fun variants(base: String): List<String> {
        val e = table?.byEmoji?.get(base) ?: return listOf(base)
        val one = e.tones.map { it.first }.filter { v ->
            v.codePoints().filter { it in 0x1F3FB..0x1F3FF }.distinct().count() == 1L
        }
        return if (one.isEmpty()) listOf(base) else listOf(base) + one.take(5)
    }

    /** The emoji a toned one belongs to ("👍🏽" → "👍"). */
    fun base(emoji: String): String = table?.toneBase?.get(emoji) ?: emoji

    /** Names people use that Unicode's don't say (a country's short name). */
    private val aliases = listOf(
        "usa" to "🇺🇸", "us" to "🇺🇸", "america" to "🇺🇸", "uk" to "🇬🇧", "britain" to "🇬🇧", "england" to "🏴\uDB40\uDC67\uDB40\uDC62\uDB40\uDC65\uDB40\uDC6E\uDB40\uDC67\uDB40\uDC7F",
        "uae" to "🇦🇪", "lol" to "😂", "rofl" to "🤣", "lmao" to "😂", "ty" to "🙏", "thanks" to "🙏", "omg" to "😱",
        "xd" to "😆", "dino" to "🦖", "boba" to "🧋", "hotdog" to "🌭", "ok" to "👌", "haha" to "😂",
    )

    /** Search by name and keyword, best first: the name itself, a name that
     *  ends with it ("red heart" for "heart"), one that starts with it, every
     *  word starting a word of the name, then of a keyword ("tears" → 🥹 😂
     *  😭 …). The most used emoji (the seed) break ties, then board order
     *  (iOS twin). */
    fun search(query: String, limit: Int = 24): List<String> {
        val t = table ?: return emptyList()
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        val words = q.split(" ").filter { it.isNotEmpty() }
        fun split(s: String) = s.split(Regex("[^\\p{L}\\p{N}']+")).filter { it.isNotEmpty() }
        data class Hit(val score: Int, val index: Int, val emoji: String)
        val popular = t.seed.withIndex().associate { (i, e) -> e to i }
        val hits = mutableListOf<Hit>()
        var index = 0
        for ((_, list) in t.tabs) for (e in list) {
            val i = index++
            val name = e.name.lowercase()
            val nameWords = split(name)
            val keyWords = e.keywords.flatMap { split(it) }
            fun starts(pool: List<String>) = words.all { w -> pool.any { it.startsWith(w) } }
            val score = when {
                name == q || name.endsWith(": $q") -> 100
                name.endsWith(" $q") -> 85
                name.startsWith(q) -> 80
                starts(nameWords) -> 60
                starts(nameWords + keyWords) -> 40
                name.contains(q) -> 20
                else -> 0
            }
            if (score > 0) hits += Hit(score, i, e.emoji)
        }
        for ((alias, emoji) in aliases) {
            if (alias == q || (q.length >= 3 && alias.startsWith(q))) hits += Hit(if (alias == q) 90 else 50, -1, emoji)
        }
        val out = mutableListOf<String>()
        for (h in hits.sortedWith(compareByDescending<Hit> { it.score }.thenBy { popular[it.emoji] ?: 999 }.thenBy { it.index })) {
            if (h.emoji !in t.byEmoji || h.emoji in out) continue
            out += h.emoji
            if (out.size >= limit) break
        }
        return out
    }
}

/** Text emoticons for the board's :-) page: plain text, typed as it is. */
object EmoticonData {
    val categories: List<Triple<String, String, List<String>>> = listOf(
        Triple("classic", "Classic", listOf(
            ":-)", ":)", ";-)", ";)", ":-D", ":D", "XD", ":-P",
            ":P", ":-(", ":(", ":'(", ":-O", ":O", ":-*", ":*",
            ":-|", ":/", ":-/", ">:(", "B-)", "8-)", "<3", "</3",
            "^_^", "^^", "-_-", "o_O", "O_o", ">_<", "T_T", ":3",
            "=)", "=D", "xD", "(:", "D:", ":-]", ":-[", "o:-)",
            "}:-)",
        )),
        Triple("smiling", "Smiling", listOf(
            "(◕‿◕)", "(^‿^)", "(｡◕‿◕｡)", "(✿◠‿◠)", "(◠‿◠)", "(＾▽＾)", "(ᵔ◡ᵔ)", "(´▽`)",
            "٩(◕‿◕)۶", "(o^▽^o)", "(⌒‿⌒)", "(✧ω✧)", "ヽ(´▽`)/", "(*^▽^*)", "(^_^)", "(^o^)",
            "(≧▽≦)", "(⁀ᗢ⁀)", "(´∀`)", "(•‿•)", "ʘ‿ʘ", "(≧◡≦)", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "\\(^o^)/",
            "(^▽^)",
        )),
        Triple("love", "Love", listOf(
            "(♥ω♥)", "(´∀`)♡", "(｡♥‿♥｡)", "(˘³˘)♥", "(*♡∀♡)", "♥‿♥", "(◍•ᴗ•◍)❤", "(灬º‿º灬)♡",
            "(づ￣ ³￣)づ", "(っ˘з(˘⌣˘ )", "♡(ˊ͈ ॢ꒳ ॢˋ͈)", "(´ε｀ )♡", "(ღ˘⌣˘ღ)", "(♡°▽°♡)", "♡＾▽＾♡", "(*˘︶˘*).｡.:*♡",
            "( ˘ ³˘)♥", "(✿ ♥‿♥)", "♡", "❤(ɔˆз(ˆ⌣ˆc)",
        )),
        Triple("hugs", "Hugs", listOf(
            "(っ´▽`)っ", "(づ｡◕‿‿◕｡)づ", "⊂(・▽・⊂)", "(つ≧▽≦)つ", "(っ＾▽＾)っ", "⊂(´・ω・｀⊂)", "(⊃｡•́‿•̀｡)⊃", "(づ ◕‿◕ )づ",
            "(っ◕‿◕)っ", "ლ(╹◡╹ლ)", "(ɔˆ ³(ˆ⌣ˆc)", "(⊃・ᴗ・)⊃",
        )),
        Triple("sad", "Sad", listOf(
            "(╥﹏╥)", "(T_T)", "(ಥ﹏ಥ)", "(;﹏;)", "(´；ω；`)", "(ㅠ﹏ㅠ)", "(｡•́︿•̀｡)", "(´・_・`)",
            "(-_-;)", "(︶︹︺)", "(ノ_<。)", "(｡╯︵╰｡)", "(>_<)", "(ಥ_ಥ)", "(´°̥̥̥̥̥̥̥̥ω°̥̥̥̥̥̥̥̥｀)", "(-_-)",
            "(ᗒᗣᗕ)՞",
        )),
        Triple("angry", "Angry", listOf(
            "(╬ Ò﹏Ó)", "(ノಠ益ಠ)ノ彡┻━┻", "(╯°□°）╯︵ ┻━┻", "(ಠ_ಠ)", "(¬_¬)", "ヽ(`Д´)ﾉ", "(＃`Д´)", "(`皿´＃)",
            "ಠ╭╮ಠ", "(ง'̀-'́)ง", "(눈_눈)", "(╯‵□′)╯︵┻━┻", "┬─┬ノ( º _ ºノ)", "(ꐦ°᷄д°᷅)",
        )),
        Triple("surprised", "Surprised", listOf(
            "(⊙_⊙)", "(°ロ°)", "(O_O)", "(ﾟДﾟ;)", "Σ(°△°|||)", "(゜-゜)", "(⊙０⊙)", "(°o°)",
            "w(°ｏ°)w", "(o_O)", "Σ(ﾟДﾟ)", "(＠_＠;)", "(ʘᗩʘ')",
        )),
        Triple("cool", "Cool", listOf(
            "(⌐■_■)", "( •_•)>⌐■-■", "(☞ﾟヮﾟ)☞", "☜(ﾟヮﾟ☜)", "ᕦ(ò_óˇ)ᕤ", "(ง •̀_•́)ง", "(•̀ᴗ•́)و", "( ͡° ͜ʖ ͡°)",
            "(>‿◠)✌", "ᕕ( ᐛ )ᕗ", "(ಠ‿ಠ)", "(￣ー￣)b", "d(^_^)b", "(b ᵔ▽ᵔ)b",
        )),
        Triple("shrug", "Shrug", listOf(
            "¯\\_(ツ)_/¯", "¯\\(°_o)/¯", "┐(´ー｀)┌", "ヽ(ー_ー )ノ", "┐(︶▽︶)┌", "(・_・ヾ", "(￣ヘ￣)", "(•_•)",
            "(・・?", "ʅ(°_°)ʃ",
        )),
        Triple("animals", "Animals", listOf(
            "ʕ•ᴥ•ʔ", "(=^･ω･^=)", "(=^‥^=)", "ʕ·ᴥ·ʔ", "(ᵔᴥᵔ)", "U・ᴥ・U", "∪･ω･∪", "(・⊝・)",
            "><(((('>", "(`・ω・´)", "(=ↀωↀ=)", "₍ᐢ•ﻌ•ᐢ₎", "ʕっ•ᴥ•ʔっ", "(•ө•)♡", "~(˘▾˘~)", "くコ:彡",
        )),
    )

    fun items(id: String): List<String> = categories.firstOrNull { it.first == id }?.third ?: emptyList()
}
