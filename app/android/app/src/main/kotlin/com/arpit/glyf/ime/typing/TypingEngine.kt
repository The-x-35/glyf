package com.arpit.glyf.ime.typing

import com.arpit.glyf.store.SecretScanner

/**
 * Suggestions, autocorrect and next-word prediction, entirely on device
 * (shared/typing/FORMAT.md). Mirror of Engine/Typing/TypingEngine.swift;
 * shared/typing/golden-cases.json holds both to the same answers.
 */
class TypingEngine(
    base: GlydTrie?,
    personal: PersonalLexicon = PersonalLexicon(),
    /** Where the letters sit: follows the picked layout (KeyboardTyping.letterRows). */
    var geometry: KeyGeometry = KeyGeometry(),
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

        const val AUTOCORRECT_THRESHOLD = 0.16f
        const val AMBIGUITY_GAP = 0.05f
        const val SWAP_GAP = 0.02f
        const val PREDICTION_FLOOR = 150f
        /** Next words are the likeliest of each word's pairs: this many are read. */
        const val PREDICTION_ROWS = 64
        /** What two words before predict ranks this far above what one does
         *  ("I want" → to, you, a): 38% of next words are among the three,
         *  30% on the previous word alone (2026-10-05). */
        const val TRIPLE_LIFT = 15f
        /** A dictionary fix of apostrophes ("cant" → "can't") beats a real word
         *  with the typed spelling only when it's this much more common. */
        const val WHITELIST_GAP = 40f
        const val PACK_PROBABILITY = 160f
        const val CONTACT_PROBABILITY = 40f
        /** A name (Contacts, or a detail saved in the vault) typed in other
         *  capitals is never changed into another word, unless that word is
         *  one of the commonest there are: a contact "Teh" still lets "teh"
         *  be "the" (222), while "arpit" never becomes "armpit" (Arpit,
         *  2026-11-04: "never correct names"). iOS twin. */
        const val NAME_FIX_FLOOR = 200f
        const val PACK_PHRASE_PROBABILITY = 180f
        /** A name (capitalized, not one of I's forms) ranks as if this much
         *  rarer when it isn't what was typed and the typing was lowercase:
         *  "I hsven" is "haven" and "haven't", never "Haven" or "Hagen"
         *  (2026-10-05). TypingEngine.swift's twin. */
        const val NAME_PENALTY = 40f
        /** What one slip costs a word the previous word expects. */
        const val CONTEXT_EDIT_COST = 0.45f
        /** How many of the previous word's likeliest followers are tried
         *  against what's typed so far. */
        const val CONTEXT_FOLLOWERS = 256
        /** The previous word ranks the candidates only when it was seen before
         *  one of the likeliest this many of them. */
        const val CONTEXT_TOP = 3
        /** A word never seen after the previous word, when that word was seen
         *  before others, ranks no higher than the rarest of them, and at most
         *  this much lower than it would alone: "your my" is no English. */
        const val UNSEEN_PAIR_MOST = 45f
        /** A same-letters fix into a name or a rare spelling gives way to a
         *  word this much likelier ("I've ben" is "been", not "Ben")... */
        const val RIVAL_GAP = 40f
        /** ...when the name is this rare, or the previous word says so... */
        const val RARE_NAME = 100f
        /** ...and a spelling with an apostrophe below this is rare ("ne'er"). */
        const val RARE_FORM = 120f
        /** A dictionary spelling of exactly the typed letters below this ranks
         *  as any other word, not first: "wats" offers "was", not "wat's". */
        const val EXACT_FLOOR = 60f

        /** Words, not codes: no digits, no addresses, no secrets. */
        fun isLearnable(word: String): Boolean {
            val count = word.codePointCount(0, word.length)
            return count in 1..32 && word.none { it.isWhitespace() } &&
                !TypingText.hasDigit(word) && !TypingText.isWebish(word) &&
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

    fun setBase(trie: GlydTrie?) {
        base = trie
        followersOf = -1
        followerMap = emptyMap()
        likelyFollowers = emptyList()
        triplesFor = -1L
        tripleMap = emptyMap()
        likelyTriples = emptyList()
        rebuildExtra()
    }

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
        contactList = forms
        mergeNames()
    }

    /** The person's own details from the vault (name, first and last name,
     *  company, city, state): names to the engine, like contacts. */
    fun setOwnNames(forms: List<String>) {
        if (forms == ownNameList) return
        ownNameList = forms
        mergeNames()
    }

    private var contactList: List<String> = emptyList()
    private var ownNameList: List<String> = emptyList()

    private fun mergeNames() {
        val out = LinkedHashMap<String, String>()
        for (f in contactList + ownNameList) out.putIfAbsent(TypingText.key(f), f)
        out.remove("")
        contactForms = out
        rebuildExtra()
    }

    fun replacePersonal(lexicon: PersonalLexicon) { personal = lexicon; rebuildExtra() }

    // Suggestions

    private class Candidate(
        val form: String, val key: String, val score: Float, val probability: Float, val kinds: Int,
        val offensive: Boolean, val whitelist: Boolean, val whitelistOnly: Boolean,
        /** What the previous word says for this one, when anything does. */
        val pair: Float?,
        /** How much rarer it ranks for never following the previous word, and
         *  what that took off its score. */
        val unseen: Float = 0f, val unseenScore: Float = 0f,
    ) {
        /** As if the previous word said nothing about it. */
        fun alone() = if (unseen == 0f) this else Candidate(form, key, score + unseenScore, probability + unseen,
            kinds, offensive, whitelist, whitelistOnly, pair)
    }

    private enum class Source { BASE, EXTRA }

    private fun sources(): List<kotlin.Pair<GlydTrie, Source>> =
        listOfNotNull(base?.let { it to Source.BASE }, extra?.let { it to Source.EXTRA })

    fun suggestions(typed: String, touches: List<FloatArray?>? = null, previous: String?,
                    sentenceStart: Boolean, policy: Int = ALL, today: Int = TypingText.day(),
                    beforePrevious: String? = null): Suggestions {
        if (policy and SUGGESTIONS == 0 || typed.isEmpty() || TypingText.isWebish(typed)) return Suggestions.empty(typed)
        // Caps lock ("YES"): the words its letters make, in capitals, and
        // never a fix (caps are deliberate). Read as they stood, "YES" was
        // no word and offered He's and Yesterday (2026-10-14).
        if (TypingText.isShouting(typed)) {
            val lower = suggestions(typed.lowercase(), touches, previous, false, policy and AUTOCORRECT.inv(), today, beforePrevious)
            val shouted = lower.alternatives.map { it.uppercase() }.filter { it != typed }.distinct()
            lastHeldBack = "digit-or-caps"
            return Suggestions(typed, lower.known || isWord(typed), null, shouted)
        }
        val key = TypingText.key(typed)
        val typedScalars = TypingText.scalars(typed)
        if (key.isEmpty() || typedScalars.size > 48) return Suggestions.empty(typed)

        val points = touchPoints(typedScalars, touches)
        if (points.isEmpty()) return Suggestions.empty(typed)

        val prevKey = previous?.let { TypingText.key(it) }?.takeIf { it.isNotEmpty() }
        val prevBaseEntry = prevKey?.let { baseEntry(it) }
        useTriples(prevBaseEntry, beforePrevious)

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

        val personalForm = personalForm(key)

        val (ranked, informative) = rank(typed, key, points, prevKey, prevBaseEntry, sentenceStart, today)
        // Read against the same evidence as the ranking.
        val exact = if (informative) exactForms else exactForms.map { it.alone() }

        // A whitelist target spelled differently ("his" under "hid") is not a
        // form of the typed word; everything else under this key is.
        val realForms = exact.filter { !it.whitelistOnly && !(it.whitelist && it.key != key) }
        // A learned spelling makes its letters known only where it tells the
        // dictionary something new: having typed "I" (the dictionary's own
        // form) never makes a lone "i" a word (2026-10-14, "and i" stayed).
        val known = (personalForm != null && (TypingText.sameWord(typed, personalForm) ||
            (personalForm.lowercase() == typed.lowercase() && baseEntry(key, personalForm) == null))) ||
            realForms.any { TypingText.sameWord(typed, it.form) }

        lastHeldBack = null
        var autocorrect = if (policy and AUTOCORRECT != 0)
            decide(typed, key, known, sentenceStart, exact, realForms, ranked, prevKey) else null
        // A name in Contacts or the vault stays a name, whatever the
        // capitals: "arpit" never becomes "armpit".
        if (autocorrect != null && contactForms.containsKey(key) && !nameMayBecome(autocorrect, key)) {
            autocorrect = null
            lastHeldBack = "name"
        }
        val seen = HashSet<String>()
        seen.add(typed.lowercase())
        autocorrect?.let { seen.add(it.lowercase()) }
        val alternatives = ArrayList<String>()
        val keyScalars = TypingText.scalars(key)
        for (c in ranked) {
            if (c.offensive) continue
            // "United States" is no completion for "u".
            if (c.form.contains(' ') && c.key != key) continue
            // A word typed in full wants completions ("the" → "there") or its
            // own apostrophe forms ("its" → "it's"), never neighbours ("noon"
            // → "moon"): noise in the strip (iOS twin, 2026-10-07).
            if (known && c.key != key && !c.key.startsWith(key)) continue
            // One letter is the start of a word, not a slip: "k" offers "know",
            // never "I" (2026-10-05).
            if (keyScalars.size == 1 && TypingText.scalars(c.key).firstOrNull() != keyScalars[0]) continue
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

    private fun personalForm(key: String): String? = if (personal.isKnown(key)) personal.word(key)?.form else null

    private fun touchPoints(typedScalars: IntArray, touches: List<FloatArray?>?): List<TouchPoint> {
        val points = ArrayList<TouchPoint>()
        typedScalars.forEachIndexed { i, cp ->
            if (cp == '\''.code || cp == 0x2019 || cp == '-'.code) return@forEachIndexed
            val offset = touches?.let { if (i < it.size) it[i] else null }
            points.add(TouchPoint(cp, offset, geometry))
        }
        return points
    }

    /** Every word the touches could have meant, best first, and whether the
     *  previous word had a say in the order. */
    private fun rank(typed: String, key: String, points: List<TouchPoint>, prevKey: String?, prevBaseEntry: Int?,
                     sentenceStart: Boolean, today: Int): kotlin.Pair<List<Candidate>, Boolean> {
        // Typed in lowercase (a capital the sentence start put there counts as
        // lowercase): names then rank lower unless they're what was typed.
        val lowerish = !TypingText.hasUppercase(typed) ||
            (sentenceStart && TypingText.capitalCount(typed) == 1 && TypingText.isCapitalized(typed))
        val nameKey = if (lowerish) key else null
        val best = HashMap<String, Candidate>()
        for ((trie, source) in sources()) {
            for (hit in Decoder.search(trie, points, geometry)) {
                val first = trie.firstEntry(hit.node)
                for (e in first until first + trie.entryCount(hit.node)) {
                    if (trie.flags(e) and GlydTrie.FLAG_NOT_A_WORD != 0) continue
                    val c = candidate(trie, source, e, null, hit, points.size, prevKey, prevBaseEntry, today, nameKey)
                    if (personal.isBlocked(c.key)) continue
                    val existing = best[c.form]
                    if (existing != null && existing.score >= c.score) continue
                    best[c.form] = c
                }
            }
        }
        // The previous word's likely followers, where what's typed so far fits
        // one with at most a slip: the decoder's completions go by commonness
        // alone, so after "I" an "h" never reached "haven't" (2026-10-05).
        val b = base
        if (prevBaseEntry != null && b != null) {
            val typedKey = TypingText.scalars(key)
            val slips = if (typedKey.size >= 3) 1 else 0
            followers(b, prevBaseEntry)
            for (follower in likelyTriples + likelyFollowers) {
                if (personal.isBlocked(follower.key)) continue
                val (edits, added) = TypingText.prefixFit(typedKey, follower.scalars) ?: continue
                if (edits > slips || (edits == 0 && added == 0)) continue
                val spatial = edits * CONTEXT_EDIT_COST + (if (added > 0) Decoder.completionCost(added) else 0f)
                val target = follower.entry
                val formKey = follower.key
                val existing = best[follower.form]
                // The decoder's own find keeps its account of the slip (a far
                // key stays a far key); a new one is taken as a far slip, so
                // autocorrect stays as careful with it ("I hav" is not "had").
                val kinds = existing?.kinds ?: ((if (added > 0) Decoder.COMPLETION else 0) or
                    (if (edits > 0) Decoder.FAR_SUBSTITUTION else 0))
                val c = candidate(b, Source.BASE, target, formKey, Decoder.Hit(GlydTrie.NONE, spatial, kinds),
                    points.size, prevKey, prevBaseEntry, today, nameKey)
                if (existing == null || existing.score < c.score) best[c.form] = c
            }
        }
        // When none of the likeliest words ever followed the previous word, it
        // says nothing about them: "the recieve" is still "receive", not a
        // tie with "relieve" (2026-10-05).
        val informative = best.values
            .sortedWith(compareByDescending<Candidate> { it.score + it.unseenScore }.thenBy { it.form })
            .take(CONTEXT_TOP).any { it.pair != null }
        val all = if (informative) best.values else best.values.map { it.alone() }
        return all.sortedWith(compareByDescending<Candidate> { it.score }.thenBy { it.form }) to informative
    }

    private fun candidate(trie: GlydTrie, source: Source, entry: Int, key: String?, hit: Decoder.Hit,
                          points: Int, prevKey: String?, prevBaseEntry: Int?, today: Int,
                          nameKey: String? = null): Candidate {
        val form = trie.form(entry)
        val formKey = key ?: TypingText.key(form)
        val flags = trie.flags(entry)
        // A fix's target under the misspelling ("have" under "nave") reads the
        // previous word's pairs through the word's own entry.
        val own = source == Source.BASE && flags and GlydTrie.FLAG_NOT_A_WORD == 0
        val language = languageProbability(formKey, form,
            if (source == Source.BASE) trie.probability(entry).toFloat() else null,
            if (own) entry else null, prevKey, prevBaseEntry, today)
        var f = language.f
        if (nameKey != null && formKey != nameKey && isName(form)) f = maxOf(0f, f - NAME_PENALTY)
        val scale = 1.1214f + 0.1f * points.toFloat()
        var score = 1f - (hit.spatial + 1.1214f * (255f - f) / 255f) / scale
        // The typed letters' own spellings come first, unless the dictionary's
        // is junk ("wat's", "di's"): those rank as any other word would.
        if (hit.exact && (source == Source.EXTRA || f >= EXACT_FLOOR)) score += 1.1f
        return Candidate(form, formKey, score, f, hit.kinds,
            flags and GlydTrie.FLAG_OFFENSIVE != 0, flags and GlydTrie.FLAG_WHITELIST != 0,
            flags and GlydTrie.FLAG_NOT_A_WORD != 0, language.pair, language.unseen, 1.1214f * language.unseen / 255f / scale)
    }

    /** Capitalized and not one of I's own forms ("I", "I'm"): word pairs
     *  never predict these, so no pair says anything against them either. */
    private fun isName(form: String) = TypingText.hasUppercase(form) && form != "I" && !form.startsWith("I'")

    private class Language(val f: Float, val pair: Float?, val unseen: Float)

    /** FORMAT.md "Language f": the best evidence any source has for the word,
     *  what the previous word says for it on its own, and how much rarer it
     *  ranks for never following the previous word. */
    private fun languageProbability(key: String, form: String, baseProbability: Float?, entry: Int?,
                                    prevKey: String?, prevBaseEntry: Int?, today: Int): Language {
        var f = baseProbability ?: 0f
        // What the person types counts for the spelling they type: having
        // written "they were" never lifts "we're" (2026-10-05).
        val theirs = personal.word(key)?.form?.let { TypingText.sameSpelling(it, form) } ?: true
        if (theirs) personal.probability(key, today)?.let { f = maxOf(f, it) }
        if (packForms.containsKey(key)) f = maxOf(f, PACK_PROBABILITY)
        if (contactForms.containsKey(key)) f = maxOf(f, CONTACT_PROBABILITY)
        var pair: Float? = null
        var unseen = 0f
        if (prevKey != null) {
            if (theirs) personal.pairProbability(prevKey, key, today)?.let { pair = it }
            if (packPairs[prevKey]?.any { TypingText.key(it) == key } == true) pair = maxOf(pair ?: 0f, PACK_PHRASE_PROBABILITY)
            val b = base
            if (prevBaseEntry != null && b != null) {
                val followers = followers(b, prevBaseEntry)
                val target = entry ?: baseEntry(key, form)
                val p = target?.let { followers[it] }
                if (p != null) pair = maxOf(pair ?: 0f, p.toFloat())
                // The previous word was seen before plenty of others, never this
                // one: "your ket" is "key", not "let" (2026-10-05).
                else if (pair == null && followers.isNotEmpty() && !isName(form)) {
                    val capped = maxOf(minOf(f, followerFloor.toFloat()), f - UNSEEN_PAIR_MOST)
                    unseen = f - capped
                    f = capped
                }
                // The two words before, when they were seen together enough.
                target?.let { tripleMap[it] }?.let { pair = maxOf(pair ?: 0f, it.toFloat()) }
            }
            pair?.let { f = maxOf(f, it) }
        }
        val clamped = f.coerceIn(0f, 255f)
        return Language(clamped, pair, unseen)
    }

    private class Follower(val entry: Int, val form: String, val key: String, val scalars: IntArray)

    private var triplesFor = -1L
    /** The likeliest words after the word two back and the previous one. */
    private var tripleMap: Map<Int, Int> = emptyMap()
    private var likelyTriples: List<Follower> = emptyList()

    /** Reads what the two words before say, once per pair of them. */
    private fun useTriples(prevBaseEntry: Int?, beforePrevious: String?) {
        val b = base
        val twoBack = if (prevBaseEntry == null || b == null) null
            else beforePrevious?.let { TypingText.key(it) }?.takeIf { it.isNotEmpty() }?.let { baseEntry(it) }
        if (twoBack == null || prevBaseEntry == null || b == null) {
            tripleMap = emptyMap()
            likelyTriples = emptyList()
            triplesFor = -1L
            return
        }
        val id = (twoBack.toLong() shl 32) or (prevBaseEntry.toLong() and 0xFFFFFFFFL)
        if (id == triplesFor) return
        val rows = b.trigrams(twoBack, prevBaseEntry)
            .filter { (t, _) -> b.flags(t) and (GlydTrie.FLAG_OFFENSIVE or GlydTrie.FLAG_NOT_A_WORD) == 0 }
        tripleMap = rows.associate { it.first to it.second }
        likelyTriples = rows.map { (t, _) -> val form = b.form(t); val k = TypingText.key(form); Follower(t, form, k, TypingText.scalars(k)) }
        triplesFor = id
    }

    private var followersOf = -1
    private var followerMap: Map<Int, Int> = emptyMap()
    private var followerFloor = 0
    /** The likeliest of them, spelled out for matching what's typed. */
    private var likelyFollowers: List<Follower> = emptyList()

    /** The previous word's followers, read once per word typed after it. */
    private fun followers(b: GlydTrie, entry: Int): Map<Int, Int> {
        if (entry != followersOf) {
            followerMap = b.followers(entry)
            followerFloor = followerMap.values.minOrNull() ?: 0
            likelyFollowers = b.bigrams(entry, CONTEXT_FOLLOWERS)
                .filter { (t, _) -> b.flags(t) and (GlydTrie.FLAG_OFFENSIVE or GlydTrie.FLAG_NOT_A_WORD) == 0 }
                .map { (t, _) -> val form = b.form(t); val k = TypingText.key(form); Follower(t, form, k, TypingText.scalars(k)) }
            followersOf = entry
        }
        return followerMap
    }

    private fun baseEntry(key: String, form: String? = null): Int? {
        val b = base ?: return null
        val node = b.node(key)
        if (node == GlydTrie.NONE || b.entryCount(node) == 0) return null
        val first = b.firstEntry(node)
        if (form == null) return first
        return (first until first + b.entryCount(node)).firstOrNull { b.form(it) == form }
    }

    /** A name's own letters ("mike" → "Mike") or one of the commonest words
     *  ([NAME_FIX_FLOOR]): the only fixes a name typed in other capitals takes. */
    private fun nameMayBecome(fix: String, key: String): Boolean {
        val fixKey = TypingText.key(fix)
        if (fixKey == key) return true
        val b = base ?: return false
        val p = listOf(fix, TypingText.lowercaseFirst(fix)).mapNotNull { baseEntry(fixKey, it) }
            .maxOfOrNull { b.probability(it) } ?: 0
        return p >= NAME_FIX_FLOOR
    }

    /** Tests only: the rule that kept the last suggestions() call from autocorrecting. */
    internal var lastHeldBack: String? = null

    /** FORMAT.md "When Glyf autocorrects". */
    private fun decide(typed: String, key: String, known: Boolean, sentenceStart: Boolean,
                       exactForms: List<Candidate>, realForms: List<Candidate>, ranked: List<Candidate>,
                       previous: String? = null): String? {
        if (TypingText.hasDigit(typed) || TypingText.capitalCount(typed) >= 2) run { lastHeldBack = "digit-or-caps"; return null }
        // Stretched for emphasis ("sooo", "yesss"): meant, never "solo".
        if (TypingText.isStretched(typed)) run { lastHeldBack = "stretched"; return null }

        // Dictionary fixes: apostrophes unless the typed spelling is a real word
        // nearly as common; a different word only when the typed spelling is no
        // word at all (see TypingEngine.swift).
        val typedReal = realForms.filter { TypingText.sameWord(typed, it.form) }.maxOfOrNull { it.probability }
        // "feel ill" is sick: the word before makes the real word the one meant.
        val keptHere = typedReal != null && previous != null && previous in KEPT_AFTER[key].orEmpty()
        exactForms.filter { c ->
            if (!c.whitelist || personal.isRejected(typed, c.form) || keptHere) false
            // Into other letters only when the typed ones are no word, or only
            // a rare one and the word before wants the fix: "it os" is "it is",
            // "the os" stays (OS).
            else if (c.key != key) !known && (realForms.isEmpty() ||
                (c.pair != null && realForms.all { it.probability < EXACT_FLOOR }))
            else if (typedReal != null) c.probability >= typedReal + WHITELIST_GAP
            else !known
        }.maxByOrNull { it.probability }?.let { w ->
            val fixed = TypingText.matchCase(typed, w.form)
            if (fixed == typed) return null
            // A fix into other letters gives way to the word this sentence
            // wants: "they wer" is "were", not AOSP's "we're" (2026-10-05).
            if (w.key != key) contender(typed, key, sentenceStart, ranked)?.let { rival ->
                if (rival.probability > w.probability + (if (rival.key == w.key) 0f else RIVAL_GAP)) {
                    return TypingText.matchCase(typed, rival.form)
                }
            }
            return fixed
        }
        // A rare lowercase word that is far more often a name is the name:
        // "mike" is Mike, "john" is John; "bill" and "will" stay (2026-10-05).
        val personallyKnown = personalForm(key)?.lowercase() == typed.lowercase()
        if (known && typedReal != null && !personallyKnown && !TypingText.hasUppercase(typed)) {
            realForms.filter { c ->
                !c.offensive && TypingText.isTitleCase(c.form) && !c.form.contains('\'') &&
                    c.probability >= typedReal + WHITELIST_GAP && !personal.isRejected(typed, c.form)
            }.maxByOrNull { it.probability }?.let { return it.form }
        }
        if (known) run { lastHeldBack = "known"; return null }
        // A fix the dictionary has for these letters but held back is not
        // put in by a search either.
        val declined = exactForms.filter { it.whitelist && it.key != key }.map { it.form }.toSet()

        // Same letters, different apostrophes or capitals — never into an
        // acronym ("HSA") or a capitalized contraction ("BA's").
        val sameLetters = realForms.filter { c ->
            !c.offensive && !personal.isRejected(typed, c.form) &&
                (!TypingText.hasUppercase(c.form) ||
                    (TypingText.isTitleCase(c.form) && !c.form.contains('\'') && c.probability >= 60f))
        }.maxByOrNull { it.probability }?.takeIf { fix ->
            TypingText.matchCase(typed, fix.form) != typed &&
                (sentenceStart || !TypingText.isCapitalized(typed) || TypingText.hasUppercase(fix.form))
        }
        if (sameLetters != null) {
            // A name, or a rare spelling, gives way to a word a slip away that
            // is far likelier here: "I've ben" is "been" and "neer" is "never",
            // never "Ben" or "ne'er"; "call mike" stays Mike (2026-10-05). A
            // contact's name never gives way.
            val name = TypingText.hasUppercase(sameLetters.form) && !contactForms.containsKey(key)
            val rare = !TypingText.hasUppercase(sameLetters.form) && sameLetters.probability < RARE_FORM
            if (name || rare) {
                val gap = sameLetters.probability + RIVAL_GAP
                fun strong(c: Candidate) = c.probability >= gap &&
                    (rare || sameLetters.probability < RARE_NAME || (c.pair ?: 0f) >= gap)
                val rival = contender(typed, key, sentenceStart, ranked, declined)
                if (rival != null && strong(rival)) return TypingText.matchCase(typed, rival.form)
                // Not sure enough of the other word to put it in, but too sure
                // of it to put in the rare one: "Tom wats" stays as typed.
                val typedKey = TypingText.scalars(key)
                if (ranked.any { !it.offensive && it.key != key && strong(it) &&
                        TypingText.editDistance(typedKey, TypingText.scalars(it.key)) <= 1 }) {
                    run { lastHeldBack = "contested"; return null }
                }
            }
            return TypingText.matchCase(typed, sameLetters.form)
        }
        return contender(typed, key, sentenceStart, ranked, declined)?.let { TypingText.matchCase(typed, it.form) }
    }

    /** The best word a slip or two from what was typed, when it's sure
     *  enough to put in (FORMAT.md "When Glyf autocorrects"). */
    private fun contender(typed: String, key: String, sentenceStart: Boolean, ranked: List<Candidate>,
                          declined: Set<String> = emptySet()): Candidate? {
        if (typed.codePointCount(0, typed.length) <= 1) run { lastHeldBack = "one-letter"; return null }
        if (TypingText.isCapitalized(typed) && !sentenceStart) run { lastHeldBack = "capitalized"; return null }

        // Spellings of the typed letters were settled before this.
        val contenders = ranked.filter { !it.offensive && it.key != key && it.form !in declined }
        val first = contenders.firstOrNull() ?: run { lastHeldBack = "no-contender"; return null }
        if (personal.isRejected(typed, first.form)) run { lastHeldBack = "rejected"; return null }

        val typedKey = TypingText.scalars(key)
        val typedLength = typedKey.size
        fun confidence(c: Candidate): kotlin.Pair<Float, Int> {
            val ck = TypingText.scalars(c.key)
            val distance = TypingText.editDistance(typedKey, ck)
            if (distance >= ck.size || c.score <= 0f) return 0f to distance
            return c.score * (1f - distance.toFloat() / ck.size.toFloat()) to distance
        }
        val (conf, distance) = confidence(first)
        if (distance > (if (typedLength <= 4) 1 else 2)) run { lastHeldBack = "too-far"; return null }
        if (conf < AUTOCORRECT_THRESHOLD) run { lastHeldBack = "low-confidence"; return null }
        contenders.drop(1).firstOrNull { it.key != first.key }?.let { second ->
            // Two letters swapped is the clearest typo there is ("waht").
            val swap = first.kinds == Decoder.TRANSPOSITION && first.probability >= second.probability
            if (conf - confidence(second).first < (if (swap) SWAP_GAP else AMBIGUITY_GAP)) run { lastHeldBack = "ambiguous"; return null }
        }

        val kinds = first.kinds
        if (kinds and Decoder.FIRST_LETTER_FAR_SUBSTITUTION != 0) run { lastHeldBack = "first-letter-far"; return null }
        if (kinds and Decoder.FAR_SUBSTITUTION != 0) {
            // A far-off key in a short word is another word ("yaar" isn't "year").
            if (typedLength <= 4) run { lastHeldBack = "far-short"; return null }
            if (first.probability < (if (typedLength >= 7) 90f else 150f)) run { lastHeldBack = "far-rare"; return null }
        }
        // A lowercase word becomes a proper noun only if it's a common one,
        // and never an acronym ("ngl" is not "NFL").
        if (TypingText.hasUppercase(first.form) && !TypingText.hasUppercase(typed) &&
            (TypingText.capitalCount(first.form) > 1 || first.probability < 110f)) run { lastHeldBack = "rare-name"; return null }
        val loose = Decoder.OMISSION_OTHER or Decoder.INSERTION_OTHER or Decoder.COMPLETION or Decoder.TRAILING_INSERTION
        if (kinds and loose != 0 && first.probability < (if (typedLength >= 7) 60f else 100f)) run { lastHeldBack = "loose-rare"; return null }
        if (distance == 2 && !((typedLength >= 8 && first.probability >= 100f) || (typedLength >= 6 && first.probability >= 150f))) {
            run { lastHeldBack = "two-edits"; return null }
        }
        return first
    }

    /** Top candidates with their numbers, for tuning (tests only). */
    internal fun debugCandidates(typed: String, previous: String?, limit: Int = 5, sentenceStart: Boolean = false,
                                 beforePrevious: String? = null): List<String> {
        val key = TypingText.key(typed)
        val points = touchPoints(TypingText.scalars(typed), null)
        val prevKey = previous?.let { TypingText.key(it) }?.takeIf { it.isNotEmpty() }
        val prevBaseEntry = prevKey?.let { baseEntry(it) }
        useTriples(prevBaseEntry, beforePrevious)
        val typedKey = TypingText.scalars(key)
        return rank(typed, key, points, prevKey, prevBaseEntry, sentenceStart, TypingText.day()).first.take(limit).map { c ->
            val ck = TypingText.scalars(c.key)
            val d = TypingText.editDistance(typedKey, ck)
            val conf = if (d >= ck.size) 0f else c.score * (1f - d.toFloat() / ck.size)
            "%s%s score=%.3f conf=%.3f f=%.0f pair=%s dl=%d kinds=%d".format(c.form, if (c.whitelist) "[w]" else "",
                c.score, conf, c.probability, c.pair?.let { "%.0f".format(it) } ?: "-", d, c.kinds)
        }
    }

    // Next word

    fun predictions(previous: String?, policy: Int = ALL, today: Int = TypingText.day(),
                    beforePrevious: String? = null): List<String> {
        if (policy and SUGGESTIONS == 0 || previous == null || TypingText.isWebish(previous)) return emptyList()
        val prevKey = TypingText.key(previous)
        if (prevKey.isEmpty()) return emptyList()
        val scores = HashMap<String, Float>()
        // What the two words before were followed by ("I want" → to, you, a).
        useTriples(baseEntry(prevKey), beforePrevious)
        for (t in likelyTriples) {
            if (personal.isBlocked(t.key)) continue
            scores[t.form] = maxOf(scores[t.form] ?: 0f, (tripleMap[t.entry] ?: 0) + TRIPLE_LIFT)
        }
        base?.let { b ->
            val node = b.node(prevKey)
            if (node != GlydTrie.NONE) {
                val first = b.firstEntry(node)
                for (e in first until first + b.entryCount(node)) {
                    for ((target, p) in b.bigrams(e, PREDICTION_ROWS)) {
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

    /** Autocorrect changed a word typed with its own capital mid-sentence
     *  ("Thier" → "Their"). That capital was deliberate, so the typed word
     *  counts as written: typed like that twice, it is a name the person
     *  uses and is never changed again. A sentence start's capital proves
     *  nothing, and neither does a fix of the same letters ("Im" → "I'm").
     *  True when the searchable word set changed. iOS twin. */
    fun noteCorrected(typed: String, fix: String, sentenceStart: Boolean, policy: Int,
                      today: Int = TypingText.day()): Boolean {
        val key = TypingText.key(typed)
        if (policy and LEARNING == 0 || sentenceStart || !TypingText.isTitleCase(typed) ||
            TypingText.key(fix) == key || !isLearnable(typed)) return false
        val wasKnown = personal.isKnown(key)
        personal.commit(typed, null, today)
        if (!wasKnown && personal.isKnown(key)) {
            rebuildExtra()
            return true
        }
        return false
    }

    /** The fix autocorrect would make here, were it on: what a field without
     *  autocorrect must not learn ("teh" typed twice where autocorrect was
     *  off was never corrected anywhere again, RESEARCH-IMPROVEMENTS-APP 12). */
    fun wouldFix(typed: String, previous: String?, sentenceStart: Boolean,
                 beforePrevious: String? = null, today: Int = TypingText.day()): Boolean {
        val fix = suggestions(typed, null, previous, sentenceStart, ALL, today, beforePrevious).autocorrect
            ?: return false
        return fix != typed
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
        // This spelling, not just these letters: a learned "I" never makes
        // "i" a word, or a sentence-start "I" would be learned as "i" (and a
        // lone "i" never fixed again, 2026-10-14).
        if (personal.isKnown(key) && personal.word(key)?.form == form) return true
        if (packForms[key] == form) return true
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
