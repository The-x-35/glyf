package com.demo.glyf.ime.typing

import com.demo.glyf.store.SecretScanner

/**
 * Suggestions, autocorrect and next-word prediction, entirely on device
 * (shared/typing/FORMAT.md). Mirror of Engine/Typing/TypingEngine.swift;
 * shared/typing/golden-cases.json holds both to the same answers.
 */
class TypingEngine(
    base: GlydTrie?,
    personal: PersonalLexicon = PersonalLexicon(),
    val geometry: KeyGeometry = KeyGeometry(),
) {
    companion object {
        const val SUGGESTIONS = 1
        const val AUTOCORRECT = 2
        const val LEARNING = 4

        /** Real words a contraction fix would take ("ill" → "I'll"), kept as
         *  typed after the words that make them the word: "i feel ill" is
         *  sick, never "i feel I'll" (2026-09-29 audit). TypingEngine.swift's twin. */
        val KEPT_AFTER: Map<String, Set<String>> = mapOf(
            "ill" to setOf("feel", "feels", "felt", "feeling", "fell", "fall", "falls", "falling", "get", "gets",
                "got", "getting", "gotten", "is", "was", "are", "were", "be", "been", "being", "am", "seriously",
                "very", "so", "too", "mentally", "terminally", "critically", "chronically", "gravely", "look",
                "looks", "looked", "become", "became", "becoming", "quite", "rather", "really", "the", "these",
                "those", "many", "most", "some"),
        )
        const val ALL = SUGGESTIONS or AUTOCORRECT or LEARNING

        const val AUTOCORRECT_THRESHOLD = 0.185f
        const val AMBIGUITY_GAP = 0.05f
        const val SWAP_GAP = 0.02f
        const val PREDICTION_FLOOR = 150f
        /** A dictionary fix of apostrophes ("cant" → "can't") beats a real word
         *  with the typed spelling only when it's this much more common. */
        const val WHITELIST_GAP = 40f
        const val PACK_PROBABILITY = 160f
        const val CONTACT_PROBABILITY = 40f
        const val PACK_PHRASE_PROBABILITY = 180f

        /** Words, not codes: no digits, no addresses, no secrets. */
        fun isLearnable(word: String): Boolean {
            val count = word.codePointCount(0, word.length)
            return count in 1..32 && !TypingText.hasDigit(word) && !TypingText.isWebish(word) &&
                TypingText.isAlphabetic(word) && SecretScanner.scan(word) == null
        }
    }

    data class Suggestions(
        val typed: String,
        /** A word this person uses — shown plainly, never corrected. */
        val known: Boolean,
        /** What the space bar will put in place of `typed`. */
        val autocorrect: String?,
        /** Other choices, best first; never `typed` or `autocorrect`. */
        val alternatives: List<String>,
    ) {
        companion object { fun empty(typed: String) = Suggestions(typed, false, null, emptyList()) }
    }

    var base: GlydTrie? = base
        private set
    var personal: PersonalLexicon = personal
        private set
    private var extra: GlydTrie? = null
    private var packForms: Map<String, String> = emptyMap()
    private var contactForms: Map<String, String> = emptyMap()
    /** Pack phrases as word pairs: previous key → next forms. */
    private var packPairs: Map<String, List<String>> = emptyMap()

    init { rebuildExtra() }

    fun setBase(trie: GlydTrie?) { base = trie; rebuildExtra() }

    fun setPackWords(forms: List<String>) {
        // First spelling wins, like the Swift engine.
        val out = LinkedHashMap<String, String>()
        for (f in forms) out.putIfAbsent(TypingText.key(f), f)
        packForms = out
        rebuildExtra()
    }

    /** Phrases from switched-on packs ("kya haal hai") teach word order. */
    fun setPackPhrases(phrases: List<String>) {
        val pairs = LinkedHashMap<String, MutableList<String>>()
        for (phrase in phrases) {
            val words = phrase.split(' ').filter { it.isNotEmpty() }
            for (i in 0 until words.size - 1) {
                val pk = TypingText.key(words[i])
                if (pk.isEmpty() || TypingText.key(words[i + 1]).isEmpty()) continue
                val list = pairs.getOrPut(pk) { ArrayList() }
                if (words[i + 1] !in list) list.add(words[i + 1])
            }
        }
        packPairs = pairs
    }

    fun setContacts(forms: List<String>) {
        val out = LinkedHashMap<String, String>()
        for (f in forms) out.putIfAbsent(TypingText.key(f), f)
        contactForms = out
        rebuildExtra()
    }

    fun replacePersonal(lexicon: PersonalLexicon) { personal = lexicon; rebuildExtra() }

    // Suggestions

    private class Candidate(
        val form: String, val key: String, val score: Float, val probability: Float, val kinds: Int,
        val offensive: Boolean, val whitelist: Boolean, val whitelistOnly: Boolean,
    )

    private enum class Source { BASE, EXTRA }

    private fun sources(): List<kotlin.Pair<GlydTrie, Source>> =
        listOfNotNull(base?.let { it to Source.BASE }, extra?.let { it to Source.EXTRA })

    fun suggestions(typed: String, touches: List<FloatArray?>? = null, previous: String?,
                    sentenceStart: Boolean, policy: Int = ALL, today: Int = TypingText.day()): Suggestions {
        if (policy and SUGGESTIONS == 0 || typed.isEmpty() || TypingText.isWebish(typed)) return Suggestions.empty(typed)
        val key = TypingText.key(typed)
        val typedScalars = TypingText.scalars(typed)
        if (key.isEmpty() || typedScalars.size > 48) return Suggestions.empty(typed)

        val points = ArrayList<TouchPoint>()
        typedScalars.forEachIndexed { i, cp ->
            if (cp == '\''.code || cp == 0x2019 || cp == '-'.code) return@forEachIndexed
            val offset = touches?.let { if (i < it.size) it[i] else null }
            points.add(TouchPoint(cp, offset, geometry))
        }
        if (points.isEmpty()) return Suggestions.empty(typed)

        val prevKey = previous?.let { TypingText.key(it) }?.takeIf { it.isNotEmpty() }
        val prevBaseEntry = prevKey?.let { baseEntry(it) }

        val exactForms = ArrayList<Candidate>()
        for ((trie, source) in sources()) {
            val node = trie.node(key)
            if (node == GlydTrie.NONE) continue
            val first = trie.firstEntry(node)
            for (e in first until first + trie.entryCount(node)) {
                val flags = trie.flags(e)
                if (flags and GlydTrie.FLAG_NOT_A_WORD != 0 && flags and GlydTrie.FLAG_WHITELIST == 0) continue
                exactForms.add(candidate(trie, source, e, null, Decoder.Hit(node, 0f, 0), points.size, prevKey, prevBaseEntry, today))
            }
        }

        // A whitelist target spelled differently ("his" under "hid") is not a
        // form of the typed word; everything else under this key is.
        val realForms = exactForms.filter { !it.whitelistOnly && !(it.whitelist && it.key != key) }
        val personalForm = if (personal.isKnown(key)) personal.word(key)?.form else null
        val known = (personalForm?.lowercase() == typed.lowercase()) ||
            realForms.any { TypingText.sameWord(typed, it.form) }

        val best = HashMap<String, Candidate>()
        for ((trie, source) in sources()) {
            for (hit in Decoder.search(trie, points, geometry)) {
                val first = trie.firstEntry(hit.node)
                for (e in first until first + trie.entryCount(hit.node)) {
                    if (trie.flags(e) and GlydTrie.FLAG_NOT_A_WORD != 0) continue
                    val c = candidate(trie, source, e, null, hit, points.size, prevKey, prevBaseEntry, today)
                    if (personal.isBlocked(c.key)) continue
                    val existing = best[c.form]
                    if (existing != null && existing.score >= c.score) continue
                    best[c.form] = c
                }
            }
        }
        val ranked = best.values.sortedWith(compareByDescending<Candidate> { it.score }.thenBy { it.form })

        val autocorrect = if (policy and AUTOCORRECT != 0)
            decide(typed, key, known, sentenceStart, exactForms, realForms, ranked, prevKey) else null
        val seen = HashSet<String>()
        seen.add(typed.lowercase())
        autocorrect?.let { seen.add(it.lowercase()) }
        val alternatives = ArrayList<String>()
        for (c in ranked) {
            if (c.offensive) continue
            // "United States" is no completion for "u".
            if (c.form.contains(' ') && c.key != key) continue
            val shown = TypingText.matchCase(typed, c.form)
            if (!seen.add(shown.lowercase())) continue
            alternatives.add(shown)
            if (alternatives.size == 3) break
        }
        // Their own word first: "cut" offers the "cutee" they keep typing, not
        // "but" and "out" on the strength of English at large. Offered, never
        // put in on its own (2026-09-29: "its not learning from my vocab").
        if (policy and LEARNING != 0 && typedScalars.size >= 3) {
            personal.completion(key, today)?.let { form ->
                val shown = TypingText.matchCase(typed, form)
                if (!shown.equals(autocorrect, ignoreCase = true)) {
                    alternatives.removeAll { it.equals(shown, ignoreCase = true) }
                    alternatives.add(0, shown)
                    while (alternatives.size > 3) alternatives.removeAt(alternatives.size - 1)
                }
            }
        }
        return Suggestions(typed, known, autocorrect, alternatives)
    }

    private fun candidate(trie: GlydTrie, source: Source, entry: Int, key: String?, hit: Decoder.Hit,
                          points: Int, prevKey: String?, prevBaseEntry: Int?, today: Int): Candidate {
        val form = trie.form(entry)
        val formKey = key ?: TypingText.key(form)
        val flags = trie.flags(entry)
        val f = languageProbability(formKey, form,
            if (source == Source.BASE) trie.probability(entry).toFloat() else null,
            if (source == Source.BASE) entry else null, prevKey, prevBaseEntry, today)
        val language = 1.1214f * (255f - f) / 255f
        var score = 1f - (hit.spatial + language) / (1.1214f + 0.1f * points.toFloat())
        if (hit.exact) score += 1.1f
        return Candidate(form, formKey, score, f, hit.kinds,
            flags and GlydTrie.FLAG_OFFENSIVE != 0, flags and GlydTrie.FLAG_WHITELIST != 0,
            flags and GlydTrie.FLAG_NOT_A_WORD != 0)
    }

    private fun languageProbability(key: String, form: String, baseProbability: Float?, entry: Int?,
                                    prevKey: String?, prevBaseEntry: Int?, today: Int): Float {
        var f = baseProbability ?: 0f
        personal.probability(key, today)?.let { f = maxOf(f, it) }
        if (packForms.containsKey(key)) f = maxOf(f, PACK_PROBABILITY)
        if (contactForms.containsKey(key)) f = maxOf(f, CONTACT_PROBABILITY)
        if (prevKey != null) {
            personal.pairProbability(prevKey, key, today)?.let { f = maxOf(f, it) }
            if (packPairs[prevKey]?.any { TypingText.key(it) == key } == true) f = maxOf(f, PACK_PHRASE_PROBABILITY)
            val b = base
            if (prevBaseEntry != null && b != null) {
                val target = entry ?: baseEntry(key, form)
                if (target != null) b.bigramProbability(prevBaseEntry, target)?.let { f = maxOf(f, it.toFloat()) }
            }
        }
        return minOf(f, 255f)
    }

    private fun baseEntry(key: String, form: String? = null): Int? {
        val b = base ?: return null
        val node = b.node(key)
        if (node == GlydTrie.NONE || b.entryCount(node) == 0) return null
        val first = b.firstEntry(node)
        if (form == null) return first
        return (first until first + b.entryCount(node)).firstOrNull { b.form(it) == form }
    }

    /** FORMAT.md "When Glyf autocorrects". */
    private fun decide(typed: String, key: String, known: Boolean, sentenceStart: Boolean,
                       exactForms: List<Candidate>, realForms: List<Candidate>, ranked: List<Candidate>,
                       previous: String? = null): String? {
        if (TypingText.hasDigit(typed) || TypingText.capitalCount(typed) >= 2) return null
        // Stretched for emphasis ("sooo", "yesss"): meant, never "solo".
        if (TypingText.isStretched(typed)) return null

        // Dictionary fixes: apostrophes unless the typed spelling is a real word
        // nearly as common; a different word only when the typed spelling is no
        // word at all (see TypingEngine.swift).
        val typedReal = realForms.filter { TypingText.sameWord(typed, it.form) }.maxOfOrNull { it.probability }
        // "feel ill" is sick: the word before makes the real word the one meant.
        val keptHere = typedReal != null && previous != null && previous in KEPT_AFTER[key].orEmpty()
        exactForms.filter { c ->
            if (!c.whitelist || personal.isRejected(typed, c.form) || keptHere) false
            else if (c.key != key) !known && realForms.isEmpty()
            else if (typedReal != null) c.probability >= typedReal + WHITELIST_GAP
            else !known
        }.maxByOrNull { it.probability }?.let { w ->
            val fixed = TypingText.matchCase(typed, w.form)
            return if (fixed == typed) null else fixed
        }
        if (known) return null

        // Same letters, different apostrophes or capitals — never into an
        // acronym ("HSA") or a capitalized contraction ("BA's").
        realForms.filter { c ->
            !c.offensive && !personal.isRejected(typed, c.form) &&
                (!TypingText.hasUppercase(c.form) ||
                    (TypingText.isTitleCase(c.form) && !c.form.contains('\'') && c.probability >= 60f))
        }
            .maxByOrNull { it.probability }?.let { fix ->
                val fixed = TypingText.matchCase(typed, fix.form)
                if (fixed != typed && (sentenceStart || !TypingText.isCapitalized(typed) || TypingText.hasUppercase(fix.form))) {
                    return fixed
                }
            }

        if (typed.codePointCount(0, typed.length) <= 1) return null
        if (TypingText.isCapitalized(typed) && !sentenceStart) return null

        // Spellings of the typed letters were settled above, and dictionary
        // fixes only ever apply through the rule above.
        val contenders = ranked.filter { !it.offensive && it.key != key && !it.whitelist }
        val first = contenders.firstOrNull() ?: return null
        if (personal.isRejected(typed, first.form)) return null

        val typedKey = TypingText.scalars(key)
        val typedLength = typedKey.size
        fun confidence(c: Candidate): kotlin.Pair<Float, Int> {
            val ck = TypingText.scalars(c.key)
            val distance = TypingText.editDistance(typedKey, ck)
            if (distance >= ck.size || c.score <= 0f) return 0f to distance
            return c.score * (1f - distance.toFloat() / ck.size.toFloat()) to distance
        }
        val (conf, distance) = confidence(first)
        if (distance > (if (typedLength <= 4) 1 else 2) || conf < AUTOCORRECT_THRESHOLD) return null
        contenders.drop(1).firstOrNull { it.key != first.key }?.let { second ->
            // Two letters swapped is the clearest typo there is ("waht").
            val swap = first.kinds == Decoder.TRANSPOSITION && first.probability >= second.probability
            if (conf - confidence(second).first < (if (swap) SWAP_GAP else AMBIGUITY_GAP)) return null
        }

        val kinds = first.kinds
        if (kinds and Decoder.FIRST_LETTER_FAR_SUBSTITUTION != 0) return null
        if (kinds and Decoder.FAR_SUBSTITUTION != 0) {
            // A far-off key in a short word is another word ("yaar" isn't "year").
            if (typedLength <= 4) return null
            if (first.probability < (if (typedLength >= 7) 90f else 150f)) return null
        }
        // A lowercase word becomes a proper noun only if it's a common one,
        // and never an acronym ("ngl" is not "NFL").
        if (TypingText.hasUppercase(first.form) && !TypingText.hasUppercase(typed) &&
            (TypingText.capitalCount(first.form) > 1 || first.probability < 110f)) return null
        val loose = Decoder.OMISSION_OTHER or Decoder.INSERTION_OTHER or Decoder.COMPLETION or Decoder.TRAILING_INSERTION
        if (kinds and loose != 0 && first.probability < 120f) return null
        if (distance == 2 && !((typedLength >= 8 && first.probability >= 100f) || (typedLength >= 6 && first.probability >= 150f))) {
            return null
        }
        if (kinds and Decoder.COMPLETION != 0 && typedLength < 4) return null
        return TypingText.matchCase(typed, first.form)
    }

    /** Top candidates with their numbers, for tuning (tests only). */
    internal fun debugCandidates(typed: String, previous: String?, limit: Int = 5): List<String> {
        val key = TypingText.key(typed)
        val points = TypingText.scalars(typed).filter { it != '\''.code }.map { TouchPoint(it, null, geometry) }
        val prevKey = previous?.let { TypingText.key(it) }
        val prevBaseEntry = prevKey?.let { baseEntry(it) }
        val best = HashMap<String, Candidate>()
        for ((trie, source) in sources()) for (hit in Decoder.search(trie, points, geometry)) {
            val first = trie.firstEntry(hit.node)
            for (e in first until first + trie.entryCount(hit.node)) {
                if (trie.flags(e) and GlydTrie.FLAG_NOT_A_WORD != 0) continue
                val c = candidate(trie, source, e, null, hit, points.size, prevKey, prevBaseEntry, TypingText.day())
                if ((best[c.form]?.score ?: -9f) < c.score) best[c.form] = c
            }
        }
        val typedKey = TypingText.scalars(key)
        return best.values.sortedByDescending { it.score }.take(limit).map { c ->
            val ck = TypingText.scalars(c.key)
            val d = TypingText.editDistance(typedKey, ck)
            val conf = if (d >= ck.size) 0f else c.score * (1f - d.toFloat() / ck.size)
            "%s score=%.3f conf=%.3f f=%.0f dl=%d kinds=%d".format(c.form, c.score, conf, c.probability, d, c.kinds)
        }
    }

    // Next word

    fun predictions(previous: String?, policy: Int = ALL, today: Int = TypingText.day()): List<String> {
        if (policy and SUGGESTIONS == 0 || previous == null || TypingText.isWebish(previous)) return emptyList()
        val prevKey = TypingText.key(previous)
        if (prevKey.isEmpty()) return emptyList()
        val scores = HashMap<String, Float>()
        base?.let { b ->
            val node = b.node(prevKey)
            if (node != GlydTrie.NONE) {
                val first = b.firstEntry(node)
                for (e in first until first + b.entryCount(node)) {
                    for ((target, p) in b.bigrams(e)) {
                        if (b.flags(target) and (GlydTrie.FLAG_OFFENSIVE or GlydTrie.FLAG_NOT_A_WORD) != 0) continue
                        val form = b.form(target)
                        if (personal.isBlocked(TypingText.key(form))) continue
                        scores[form] = maxOf(scores[form] ?: 0f, p.toFloat())
                    }
                }
            }
        }
        for ((form, f) in personal.nextWords(prevKey, today)) scores[form] = maxOf(scores[form] ?: 0f, f)
        for (form in packPairs[prevKey] ?: emptyList()) {
            if (!personal.isBlocked(TypingText.key(form))) scores[form] = maxOf(scores[form] ?: 0f, PACK_PHRASE_PROBABILITY)
        }
        return scores.entries.filter { it.value >= PREDICTION_FLOOR }
            .sortedWith(compareByDescending<Map.Entry<String, Float>> { it.value }.thenBy { it.key })
            .take(3).map { it.key }
    }

    // Learning

    /** A word was committed. Returns true when the searchable word set changed. */
    fun commit(word: String, previous: String?, autoCapitalized: Boolean, policy: Int, today: Int = TypingText.day()): Boolean {
        if (policy and LEARNING == 0 || !isLearnable(word)) return false
        var form = word
        if (autoCapitalized && TypingText.isCapitalized(word)) {
            val lower = TypingText.lowercaseFirst(word)
            if (isWord(lower)) form = lower
        }
        val key = TypingText.key(form)
        val wasKnown = personal.isKnown(key)
        personal.commit(form, previous, today)
        if (!wasKnown && personal.isKnown(key) && baseEntry(key, form) == null) {
            rebuildExtra()
            return true
        }
        return false
    }

    fun revert(typed: String, correction: String, today: Int = TypingText.day()) {
        personal.revert(typed, correction, today)
        rebuildExtra()
    }

    fun keep(typed: String, today: Int = TypingText.day()) {
        if (!isLearnable(typed)) return
        personal.keep(typed, today)
        rebuildExtra()
    }

    fun add(form: String, today: Int = TypingText.day()) { personal.add(form, today); rebuildExtra() }

    fun forget(form: String) { personal.forget(form); rebuildExtra() }

    fun markEditsApplied(at: Double) { personal.editsAppliedAt = at }

    private fun isWord(form: String): Boolean {
        val key = TypingText.key(form)
        if (personal.isKnown(key) || packForms.containsKey(key)) return true
        val b = base ?: return false
        val node = b.node(key)
        if (node == GlydTrie.NONE) return false
        val first = b.firstEntry(node)
        return (first until first + b.entryCount(node)).any {
            b.flags(it) and GlydTrie.FLAG_NOT_A_WORD == 0 && b.form(it) == form
        }
    }

    private fun rebuildExtra() {
        val b = base
        /** The base already has this exact spelling. Same letters aren't
         *  enough: "bas" is not "BA's", "kr" is not "Kr". */
        fun inBase(key: String, form: String): Boolean {
            if (b == null) return false
            val node = b.node(key)
            if (node == GlydTrie.NONE) return false
            val first = b.firstEntry(node)
            return (first until first + b.entryCount(node)).any {
                b.flags(it) and GlydTrie.FLAG_NOT_A_WORD == 0 && b.form(it) == form
            }
        }
        val words = ArrayList<GlydTrie.Word>()
        for ((key, form) in packForms) if (!inBase(key, form)) words.add(GlydTrie.Word(form, PACK_PROBABILITY.toInt()))
        for ((key, form) in contactForms) if (!inBase(key, form)) words.add(GlydTrie.Word(form, CONTACT_PROBABILITY.toInt()))
        val today = TypingText.day()
        for ((key, form) in personal.knownForms()) {
            if (inBase(key, form)) continue
            val f = personal.probability(key, today) ?: 100f
            words.add(GlydTrie.Word(form, f.coerceIn(1f, 255f).toInt()))
        }
        extra = if (words.isEmpty()) null else GlydTrie.build(words)
    }
}
