import Foundation

/// Suggestions, autocorrect and next-word prediction, entirely on device
/// (shared/typing/FORMAT.md). The Kotlin keyboard runs the same engine
/// (ime/typing/TypingEngine.kt); shared/typing/golden-cases.json holds both
/// to the same answers.
final class TypingEngine {

    struct Policy: OptionSet {
        let rawValue: Int
        static let suggestions = Policy(rawValue: 1)
        static let autocorrect = Policy(rawValue: 2)
        static let learning = Policy(rawValue: 4)
        static let all: Policy = [.suggestions, .autocorrect, .learning]
    }

    struct Suggestions: Equatable {
        var typed: String
        /// A word this person uses — shown plainly, never corrected.
        var known: Bool
        /// What the space bar will put in place of `typed`.
        var autocorrect: String?
        /// Other choices, best first; never `typed` or `autocorrect`.
        var alternatives: [String]

        static func empty(_ typed: String) -> Suggestions {
            Suggestions(typed: typed, known: false, autocorrect: nil, alternatives: [])
        }
    }

    static let autocorrectThreshold: Float = 0.16
    static let ambiguityGap: Float = 0.05
    static let swapGap: Float = 0.02
    static let predictionFloor: Float = 150
    /// Next words are the likeliest of each word's pairs: this many are read.
    static let predictionRows = 64
    /// What two words before predict ranks this far above what one does
    /// ("I want" → to, you, a): 38% of next words are among the three, 30%
    /// on the previous word alone (2026-10-05).
    static let tripleLift: Float = 15
    /// A dictionary fix of apostrophes ("cant" → "can't") beats a real word
    /// with the typed spelling only when it's this much more common.
    static let whitelistGap: Float = 40
    /// Real words a contraction fix would take ("ill" → "I'll"), kept as
    /// typed after the words that make them the word: "i feel ill" is sick,
    /// never "i feel I'll" (2026-09-29 audit). TypingEngine.kt's twin.
    static let keptAfter: [String: Set<String>] = [
        "ill": ["feel", "feels", "felt", "feeling", "fell", "fall", "falls", "falling", "get", "gets",
                "got", "getting", "gotten", "is", "was", "are", "were", "be", "been", "being", "am", "seriously",
                "very", "so", "too", "mentally", "terminally", "critically", "chronically", "gravely", "look",
                "looks", "looked", "become", "became", "becoming", "quite", "rather", "really", "the", "these",
                "those", "many", "most", "some"],
    ]
    static let packProbability: Float = 160
    static let contactProbability: Float = 40
    /// A name (Contacts, or a detail saved in the vault) typed in other
    /// capitals is never changed into another word, unless that word is one
    /// of the commonest there are: a contact "Teh" still lets "teh" be "the"
    /// (222), while "arpit" never becomes "armpit" (Arpit, 2026-11-04:
    /// "never correct names").
    static let nameFixFloor: Float = 200
    static let packPhraseProbability: Float = 180
    /// A name (capitalized, not one of I's forms) ranks as if this much rarer
    /// when it isn't what was typed and the typing was lowercase: "I hsven" is
    /// "haven" and "haven't", never "Haven" or "Hagen" (2026-10-05).
    static let namePenalty: Float = 40
    /// What one slip costs a word the previous word expects.
    static let contextEditCost: Float = 0.45
    /// How many of the previous word's likeliest followers are tried against
    /// what's typed so far.
    static let contextFollowers = 256
    /// The previous word ranks the candidates only when it was seen before one
    /// of the likeliest this many of them.
    static let contextTop = 3
    /// A word never seen after the previous word, when that word was seen
    /// before others, ranks no higher than the rarest of them, and at most
    /// this much lower than it would alone: "your my" is no English.
    static let unseenPairMost: Float = 45
    /// A same-letters fix into a name or a rare spelling gives way to a word
    /// this much likelier ("I've ben" is "been", not "Ben")...
    static let rivalGap: Float = 40
    /// ...when the name is this rare, or the previous word says so...
    static let rareName: Float = 100
    /// ...and a spelling with an apostrophe below this is rare ("ne'er").
    static let rareForm: Float = 120
    /// A dictionary spelling of exactly the typed letters below this ranks as
    /// any other word, not first: "wats" offers "was", not "wat's".
    static let exactFloor: Float = 60

    /// Where the letters sit: follows the picked layout (TypingStore.letterRows).
    var geometry: KeyGeometry
    private(set) var base: GlydTrie?
    private(set) var personal: PersonalLexicon
    /// Pack, added, learned and contact words, searchable like the base.
    private var extra: GlydTrie?
    private var packForms: [String: String] = [:]
    private var contactForms: [String: String] = [:]
    /// Pack phrases as word pairs: previous key → next forms.
    private var packPairs: [String: [String]] = [:]

    init(base: GlydTrie?, personal: PersonalLexicon = PersonalLexicon(), geometry: KeyGeometry = KeyGeometry()) {
        self.base = base
        self.personal = personal
        self.geometry = geometry
        rebuildExtra()
    }

    func setBase(_ trie: GlydTrie?) {
        base = trie
        followersOf = nil
        followerMap = [:]
        likelyFollowers = []
        triplesFor = nil
        tripleMap = [:]
        likelyTriples = []
        rebuildExtra()
    }

    func setPackWords(_ forms: [String]) {
        packForms = Dictionary(forms.map { (TypingText.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        rebuildExtra()
    }

    /// Phrases from switched-on packs ("kya haal hai") teach word order.
    func setPackPhrases(_ phrases: [String]) {
        var pairs: [String: [String]] = [:]
        for phrase in phrases {
            let words = phrase.split(whereSeparator: { $0 == " " }).map(String.init)
            for (prev, next) in zip(words, words.dropFirst()) {
                let pk = TypingText.key(prev)
                guard !pk.isEmpty, !TypingText.key(next).isEmpty else { continue }
                if !(pairs[pk]?.contains(next) ?? false) { pairs[pk, default: []].append(next) }
            }
        }
        packPairs = pairs
    }

    func setContacts(_ forms: [String]) {
        contactList = forms
        mergeNames()
    }

    /// The person's own details from the vault (name, first and last name,
    /// company, city, state): names to the engine, like contacts.
    func setOwnNames(_ forms: [String]) {
        guard forms != ownNameList else { return }
        ownNameList = forms
        mergeNames()
    }

    private var contactList: [String] = []
    private var ownNameList: [String] = []

    private func mergeNames() {
        contactForms = Dictionary((contactList + ownNameList).map { (TypingText.key($0), $0) },
                                  uniquingKeysWith: { first, _ in first })
        contactForms[""] = nil
        rebuildExtra()
    }

    func replacePersonal(_ lexicon: PersonalLexicon) {
        personal = lexicon
        rebuildExtra()
    }

    // MARK: Suggestions

    func suggestions(typed: String, touches: [(Float, Float)?]? = nil, previous: String?,
                     beforePrevious: String? = nil, sentenceStart: Bool, policy: Policy = .all,
                     today: Int = TypingText.day()) -> Suggestions {
        guard policy.contains(.suggestions), !typed.isEmpty, !TypingText.isWebish(typed) else { return .empty(typed) }
        // Caps lock ("YES"): the words its letters make, in capitals, and
        // never a fix (caps are deliberate). Read as they stood, "YES" was
        // no word and offered He's and Yesterday (2026-10-14).
        if TypingText.isShouting(typed) {
            let lower = suggestions(typed: typed.lowercased(), touches: touches, previous: previous,
                                    beforePrevious: beforePrevious, sentenceStart: false,
                                    policy: policy.subtracting(.autocorrect), today: today)
            var seen: Set<String> = [typed]
            let shouted = lower.alternatives.map { $0.uppercased() }.filter { seen.insert($0).inserted }
            lastHeldBack = "digit-or-caps"
            return Suggestions(typed: typed, known: lower.known || isWord(typed), autocorrect: nil,
                               alternatives: shouted)
        }
        let key = TypingText.key(typed)
        let typedScalars = Array(typed.unicodeScalars)
        guard !key.isEmpty, typedScalars.count <= 48 else { return .empty(typed) }

        let points = touchPoints(typedScalars, touches: touches)
        guard !points.isEmpty else { return .empty(typed) }

        let prevKey = previous.map(TypingText.key).flatMap { $0.isEmpty ? nil : $0 }
        let prevBaseEntry = prevKey.flatMap { baseEntry(forKey: $0) }
        useTriples(prevBaseEntry: prevBaseEntry, beforePrevious: beforePrevious)

        // Forms spelled by exactly these letters.
        var exactForms: [Candidate] = []
        for (trie, source) in sources() {
            guard let node = trie.node(forKey: key) else { continue }
            let first = trie.firstEntry(node)
            for e in first..<(first + trie.entryCount(node)) {
                let flags = trie.flags(e)
                guard flags & GlydTrie.flagNotAWord == 0 || flags & GlydTrie.flagWhitelist != 0 else { continue }
                exactForms.append(candidate(trie: trie, source: source, entry: e, key: nil,
                                            hit: Decoder.Hit(node: node, spatial: 0, kinds: []),
                                            points: points.count, prevKey: prevKey, prevBaseEntry: prevBaseEntry, today: today))
            }
        }

        let personalForm = self.personalForm(key)
        let (ranked, informative) = rank(typed: typed, key: key, points: points, prevKey: prevKey,
                                         prevBaseEntry: prevBaseEntry, sentenceStart: sentenceStart, today: today)
        // Read against the same evidence as the ranking.
        let exact = informative ? exactForms : exactForms.map { $0.alone() }

        // A whitelist target spelled differently ("his" under "hid") is not a
        // form of the typed word; everything else under this key is.
        let realForms = exact.filter { !$0.whitelistOnly && !($0.whitelist && $0.key != key) }
        // A learned spelling makes its letters known only where it tells the
        // dictionary something new: having typed "I" (the dictionary's own
        // form) never makes a lone "i" a word (2026-10-14, "and i" stayed).
        let known = personalForm.map { p in
            TypingText.sameWord(typed: typed, form: p)
                || (p.lowercased() == typed.lowercased() && baseEntry(forKey: key, form: p) == nil)
        } ?? false
            || realForms.contains { TypingText.sameWord(typed: typed, form: $0.form) }

        var result = Suggestions(typed: typed, known: known, autocorrect: nil, alternatives: [])
        lastHeldBack = nil
        if policy.contains(.autocorrect) {
            result.autocorrect = decide(typed: typed, key: key, known: known, sentenceStart: sentenceStart,
                                        exactForms: exact, realForms: realForms, ranked: ranked,
                                        previous: prevKey)
            // A name in Contacts or the vault stays a name, whatever the
            // capitals: "arpit" never becomes "armpit".
            if let fix = result.autocorrect, contactForms[key] != nil, !nameMayBecome(fix, key: key) {
                result.autocorrect = nil
                lastHeldBack = "name"
            }
        }
        var seen: Set<String> = [typed.lowercased()]
        if let ac = result.autocorrect { seen.insert(ac.lowercased()) }
        let keyScalars = TypingText.scalars(key)
        for c in ranked where !c.offensive {
            // "United States" is no completion for "u".
            if c.form.contains(" ") && c.key != key { continue }
            // A word the person has typed in full wants completions ("the" →
            // "there") or its own apostrophe forms ("its" → "it's"), not its
            // neighbours ("noon" → "moon"), which only fill the strip with
            // noise (Arpit, 2026-10-07: suggestions should be "crazy
            // helpful").
            if known && c.key != key && !c.key.hasPrefix(key) { continue }
            // One letter is the start of a word, not a slip: "k" offers "know",
            // never "I" (2026-10-05).
            if keyScalars.count == 1 && TypingText.scalars(c.key).first != keyScalars[0] { continue }
            let shown = TypingText.matchCase(typed: typed, form: c.form)
            guard seen.insert(shown.lowercased()).inserted else { continue }
            result.alternatives.append(shown)
            if result.alternatives.count == 3 { break }
        }
        // Their own word first: "cut" offers the "cutee" they keep typing, not
        // "but" and "out" on the strength of English at large. Offered, never
        // put in on its own (2026-09-29: "its not learning from my vocab").
        if policy.contains(.learning), typed.unicodeScalars.count >= 3,
           let form = personal.completion(prefix: key, today: today) {
            let shown = TypingText.matchCase(typed: typed, form: form)
            if shown.lowercased() != result.autocorrect?.lowercased() {
                result.alternatives.removeAll { $0.lowercased() == shown.lowercased() }
                result.alternatives.insert(shown, at: 0)
                if result.alternatives.count > 3 { result.alternatives.removeLast(result.alternatives.count - 3) }
            }
        }
        return result
    }

    private struct Candidate {
        let form: String
        let key: String
        let score: Float
        let probability: Float
        let kinds: Decoder.Kind
        let offensive: Bool
        let whitelist: Bool
        /// A not-a-word entry that only exists to point at its whitelist form.
        let whitelistOnly: Bool
        /// What the previous word says for this one, when anything does.
        let pair: Float?
        /// How much rarer it ranks for never following the previous word, and
        /// what that took off its score.
        var unseen: Float = 0
        var unseenScore: Float = 0

        /// As if the previous word said nothing about it.
        func alone() -> Candidate {
            guard unseen != 0 else { return self }
            return Candidate(form: form, key: key, score: score + unseenScore, probability: probability + unseen,
                             kinds: kinds, offensive: offensive, whitelist: whitelist,
                             whitelistOnly: whitelistOnly, pair: pair)
        }
    }

    private enum Source { case base, extra }

    private func sources() -> [(GlydTrie, Source)] {
        var out: [(GlydTrie, Source)] = []
        if let base { out.append((base, .base)) }
        if let extra { out.append((extra, .extra)) }
        return out
    }

    private func personalForm(_ key: String) -> String? {
        personal.isKnown(key) ? personal.word(key)?.form : nil
    }

    private func touchPoints(_ typedScalars: [Unicode.Scalar], touches: [(Float, Float)?]?) -> [TouchPoint] {
        typedScalars.enumerated().compactMap { i, u -> TouchPoint? in
            guard u != "'" && u != "\u{2019}" && u != "-" else { return nil }
            let offset = touches.flatMap { i < $0.count ? $0[i] : nil }
            return TouchPoint(character: u, offset: offset, geometry: geometry)
        }
    }

    /// Every word the touches could have meant, best first, and whether the
    /// previous word had a say in the order.
    private func rank(typed: String, key: String, points: [TouchPoint], prevKey: String?, prevBaseEntry: UInt32?,
                      sentenceStart: Bool, today: Int) -> ([Candidate], Bool) {
        // Typed in lowercase (a capital the sentence start put there counts as
        // lowercase): names then rank lower unless they're what was typed.
        let lowerish = !TypingText.hasUppercase(typed)
            || (sentenceStart && TypingText.capitalCount(typed) == 1 && TypingText.isCapitalized(typed))
        let nameKey = lowerish ? key : nil
        var best: [String: Candidate] = [:]
        for (trie, source) in sources() {
            for hit in Decoder.search(trie, points: points, geometry: geometry) {
                let first = trie.firstEntry(hit.node)
                for e in first..<(first + trie.entryCount(hit.node)) {
                    guard trie.flags(e) & GlydTrie.flagNotAWord == 0 else { continue }
                    let c = candidate(trie: trie, source: source, entry: e, key: nil, hit: hit,
                                      points: points.count, prevKey: prevKey, prevBaseEntry: prevBaseEntry,
                                      today: today, nameKey: nameKey)
                    guard !personal.isBlocked(c.key) else { continue }
                    if let existing = best[c.form], existing.score >= c.score { continue }
                    best[c.form] = c
                }
            }
        }
        // The previous word's likely followers, where what's typed so far fits
        // one with at most a slip: the decoder's completions go by commonness
        // alone, so after "I" an "h" never reached "haven't" (2026-10-05).
        if let prevBaseEntry, let base {
            let typedKey = TypingText.scalars(key)
            let slips = typedKey.count >= 3 ? 1 : 0
            _ = followers(base, prevBaseEntry)
            for follower in likelyTriples + likelyFollowers {
                let (target, form, formKey) = (follower.entry, follower.form, follower.key)
                guard !personal.isBlocked(formKey),
                      let fit = TypingText.prefixFit(typedKey, follower.scalars),
                      fit.edits <= slips, fit.edits > 0 || fit.added > 0 else { continue }
                let spatial = Float(fit.edits) * Self.contextEditCost
                    + (fit.added > 0 ? Decoder.completionCost(fit.added) : 0)
                let existing = best[form]
                // The decoder's own find keeps its account of the slip (a far
                // key stays a far key); a new one is taken as a far slip, so
                // autocorrect stays as careful with it ("I hav" is not "had").
                var kinds: Decoder.Kind = []
                if let existing { kinds = existing.kinds } else {
                    if fit.added > 0 { kinds.insert(.completion) }
                    if fit.edits > 0 { kinds.insert(.farSubstitution) }
                }
                let c = candidate(trie: base, source: .base, entry: target, key: formKey,
                                  hit: Decoder.Hit(node: GlydTrie.none, spatial: spatial, kinds: kinds),
                                  points: points.count, prevKey: prevKey, prevBaseEntry: prevBaseEntry,
                                  today: today, nameKey: nameKey)
                if existing == nil || existing!.score < c.score { best[c.form] = c }
            }
        }
        // When none of the likeliest words ever followed the previous word, it
        // says nothing about them: "the recieve" is still "receive", not a
        // tie with "relieve" (2026-10-05).
        let informative = best.values
            .sorted { a, b in
                let x = a.score + a.unseenScore, y = b.score + b.unseenScore
                return x != y ? x > y : a.form < b.form
            }
            .prefix(Self.contextTop).contains { $0.pair != nil }
        let all = informative ? Array(best.values) : best.values.map { $0.alone() }
        return (all.sorted { $0.score != $1.score ? $0.score > $1.score : $0.form < $1.form }, informative)
    }

    private func candidate(trie: GlydTrie, source: Source, entry: UInt32, key: String?, hit: Decoder.Hit,
                           points: Int, prevKey: String?, prevBaseEntry: UInt32?, today: Int,
                           nameKey: String? = nil) -> Candidate {
        let form = trie.form(entry)
        let formKey = key ?? TypingText.key(form)
        let flags = trie.flags(entry)
        // A fix's target under the misspelling ("have" under "nave") reads the
        // previous word's pairs through the word's own entry.
        let own = source == .base && flags & GlydTrie.flagNotAWord == 0
        let language = languageProbability(key: formKey, form: form,
                                           baseProbability: source == .base ? Float(trie.probability(entry)) : nil,
                                           entry: own ? entry : nil,
                                           prevKey: prevKey, prevBaseEntry: prevBaseEntry, today: today)
        var f = language.f
        if let nameKey, formKey != nameKey, Self.isName(form) { f = max(0, f - Self.namePenalty) }
        let scale = 1.1214 + 0.1 * Float(points)
        var score = 1 - (hit.spatial + 1.1214 * (255 - f) / 255) / scale
        // The typed letters' own spellings come first, unless the dictionary's
        // is junk ("wat's", "di's"): those rank as any other word would.
        if hit.exact && (source == .extra || f >= Self.exactFloor) { score += 1.1 }
        return Candidate(form: form, key: formKey, score: score, probability: f, kinds: hit.kinds,
                         offensive: flags & GlydTrie.flagOffensive != 0,
                         whitelist: flags & GlydTrie.flagWhitelist != 0,
                         whitelistOnly: flags & GlydTrie.flagNotAWord != 0,
                         pair: language.pair, unseen: language.unseen,
                         unseenScore: 1.1214 * language.unseen / 255 / scale)
    }

    /// Capitalized and not one of I's own forms ("I", "I'm"): word pairs never
    /// predict these, so no pair says anything against them either.
    private static func isName(_ form: String) -> Bool {
        TypingText.hasUppercase(form) && form != "I" && !form.hasPrefix("I'")
    }

    private struct Language {
        let f: Float
        let pair: Float?
        let unseen: Float
    }

    /// FORMAT.md "Language f": the best evidence any source has for the word,
    /// what the previous word says for it on its own, and how much rarer it
    /// ranks for never following the previous word.
    private func languageProbability(key: String, form: String, baseProbability: Float?, entry: UInt32?,
                                     prevKey: String?, prevBaseEntry: UInt32?, today: Int) -> Language {
        var f = baseProbability ?? 0
        // What the person types counts for the spelling they type: having
        // written "they were" never lifts "we're" (2026-10-05).
        let theirs = personal.word(key).map { TypingText.sameSpelling($0.form, form) } ?? true
        if theirs, let p = personal.probability(key, today: today) { f = max(f, p) }
        if packForms[key] != nil { f = max(f, Self.packProbability) }
        if contactForms[key] != nil { f = max(f, Self.contactProbability) }
        var pair: Float?
        var unseen: Float = 0
        if let prevKey {
            if theirs, let p = personal.pairProbability(previous: prevKey, key, today: today) { pair = p }
            if packPairs[prevKey]?.contains(where: { TypingText.key($0) == key }) == true {
                pair = max(pair ?? 0, Self.packPhraseProbability)
            }
            if let prevBaseEntry, let base {
                let followers = self.followers(base, prevBaseEntry)
                let target = entry ?? baseEntry(forKey: key, form: form)
                if let target, let p = followers[target] {
                    pair = max(pair ?? 0, Float(p))
                } else if pair == nil && !followers.isEmpty && !Self.isName(form) {
                    // The previous word was seen before plenty of others, never
                    // this one: "your ket" is "key", not "let" (2026-10-05).
                    let capped = max(min(f, Float(followerFloor)), f - Self.unseenPairMost)
                    unseen = f - capped
                    f = capped
                }
                // The two words before, when they were seen together enough.
                if let target, let t = tripleMap[target] { pair = max(pair ?? 0, Float(t)) }
            }
            if let pair { f = max(f, pair) }
        }
        return Language(f: min(max(f, 0), 255), pair: pair, unseen: unseen)
    }

    private struct Follower {
        let entry: UInt32
        let form: String
        let key: String
        let scalars: [UInt32]
    }

    private var triplesFor: (UInt32, UInt32)?
    /// The likeliest words after the word two back and the previous one.
    private var tripleMap: [UInt32: UInt8] = [:]
    private var likelyTriples: [Follower] = []

    /// Reads what the two words before say, once per pair of them.
    private func useTriples(prevBaseEntry: UInt32?, beforePrevious: String?) {
        guard let base, let prevBaseEntry,
              let twoBackKey = beforePrevious.map(TypingText.key), !twoBackKey.isEmpty,
              let twoBack = baseEntry(forKey: twoBackKey) else {
            tripleMap = [:]
            likelyTriples = []
            triplesFor = nil
            return
        }
        if let current = triplesFor, current == (twoBack, prevBaseEntry) { return }
        let rows = base.trigrams(twoBack: twoBack, previous: prevBaseEntry)
            .filter { base.flags($0.target) & (GlydTrie.flagOffensive | GlydTrie.flagNotAWord) == 0 }
        tripleMap = Dictionary(rows.map { ($0.target, $0.probability) }, uniquingKeysWith: { first, _ in first })
        likelyTriples = rows.map { t in
            let form = base.form(t.target)
            let key = TypingText.key(form)
            return Follower(entry: t.target, form: form, key: key, scalars: TypingText.scalars(key))
        }
        triplesFor = (twoBack, prevBaseEntry)
    }

    private var followersOf: UInt32?
    private var followerMap: [UInt32: UInt8] = [:]
    private var followerFloor: UInt8 = 0
    /// The likeliest of them, spelled out for matching what's typed.
    private var likelyFollowers: [Follower] = []

    /// The previous word's followers, read once per word typed after it.
    private func followers(_ base: GlydTrie, _ entry: UInt32) -> [UInt32: UInt8] {
        if entry != followersOf {
            followerMap = base.followers(entry)
            followerFloor = followerMap.values.min() ?? 0
            likelyFollowers = base.bigrams(entry, limit: Self.contextFollowers)
                .filter { base.flags($0.target) & (GlydTrie.flagOffensive | GlydTrie.flagNotAWord) == 0 }
                .map { t in
                    let form = base.form(t.target)
                    let key = TypingText.key(form)
                    return Follower(entry: t.target, form: form, key: key, scalars: TypingText.scalars(key))
                }
            followersOf = entry
        }
        return followerMap
    }

    private func baseEntry(forKey key: String, form: String? = nil) -> UInt32? {
        guard let base, let node = base.node(forKey: key), base.entryCount(node) > 0 else { return nil }
        let first = base.firstEntry(node)
        guard let form else { return first }
        return (first..<(first + base.entryCount(node))).first { base.form($0) == form }
    }

    /// A name's own letters ("mike" → "Mike") or one of the commonest words
    /// (`nameFixFloor`): the only fixes a name typed in other capitals takes.
    private func nameMayBecome(_ fix: String, key: String) -> Bool {
        let fixKey = TypingText.key(fix)
        if fixKey == key { return true }
        guard let base else { return false }
        let p = [fix, TypingText.lowercaseFirst(fix)].compactMap { baseEntry(forKey: fixKey, form: $0) }
            .map { Float(base.probability($0)) }.max() ?? 0
        return p >= Self.nameFixFloor
    }

    /// Tests only: the rule that kept the last suggestions() call from autocorrecting.
    private(set) var lastHeldBack: String?

    /// FORMAT.md "When Glyf autocorrects".
    private func decide(typed: String, key: String, known: Bool, sentenceStart: Bool,
                        exactForms: [Candidate], realForms: [Candidate], ranked: [Candidate],
                        previous: String? = nil) -> String? {
        guard !TypingText.hasDigit(typed), TypingText.capitalCount(typed) < 2 else {
            lastHeldBack = "digit-or-caps"
            return nil
        }
        // Stretched for emphasis ("sooo", "yesss"): meant, never "solo".
        guard !TypingText.isStretched(typed) else {
            lastHeldBack = "stretched"
            return nil
        }

        // Dictionary fixes. Apostrophes ("cant" → "can't") unless the typed
        // spelling is a real word nearly as common ("id" stays "id"); a
        // different word ("alot" → "a lot") only when the typed spelling is no
        // word at all — AOSP's "hum" → "him" and "bot" → "not" never happen —
        // or only a rare one and the word before wants the fix: "it os" is
        // "it is", "the os" stays (OS).
        let typedReal = realForms.filter { TypingText.sameWord(typed: typed, form: $0.form) }.map(\.probability).max()
        // "feel ill" is sick: the word before makes the real word the one meant.
        let keptHere = typedReal != nil && previous.map { Self.keptAfter[key]?.contains($0) ?? false } == true
        let fixes = exactForms.filter { c in
            guard c.whitelist, !personal.isRejected(typed: typed, correction: c.form), !keptHere else { return false }
            if c.key != key {
                return !known && (realForms.isEmpty || (c.pair != nil && realForms.allSatisfy { $0.probability < Self.exactFloor }))
            }
            if let typedReal { return c.probability >= typedReal + Self.whitelistGap }
            return !known
        }
        if let w = fixes.max(by: { $0.probability < $1.probability }) {
            let fixed = TypingText.matchCase(typed: typed, form: w.form)
            if fixed == typed { return nil }
            // A fix into other letters gives way to the word this sentence
            // wants: "they wer" is "were", not AOSP's "we're" (2026-10-05).
            if w.key != key, let rival = contender(typed: typed, key: key, sentenceStart: sentenceStart, ranked: ranked),
               rival.probability > w.probability + (rival.key == w.key ? 0 : Self.rivalGap) {
                return TypingText.matchCase(typed: typed, form: rival.form)
            }
            return fixed
        }
        // A rare lowercase word that is far more often a name is the name:
        // "mike" is Mike, "john" is John; "bill" and "will" stay (2026-10-05).
        let personallyKnown = personalForm(key)?.lowercased() == typed.lowercased()
        if known, let typedReal, !personallyKnown, !TypingText.hasUppercase(typed),
           let name = realForms.filter({ c in
               !c.offensive && TypingText.isTitleCase(c.form) && !c.form.contains("'")
                   && c.probability >= typedReal + Self.whitelistGap
                   && !personal.isRejected(typed: typed, correction: c.form)
           }).max(by: { $0.probability < $1.probability }) {
            return name.form
        }
        if known {
            lastHeldBack = "known"
            return nil
        }
        // A fix the dictionary has for these letters but held back is not put
        // in by a search either.
        let declined = Set(exactForms.filter { $0.whitelist && $0.key != key }.map(\.form))

        // Same letters, different apostrophes or capitals: "thats" → "that's",
        // "delhi" → "Delhi". Never into an acronym ("hsa" is not "HSA") or a
        // capitalized contraction ("bas" is not "BA's").
        if let fix = realForms.filter({ c in
            !c.offensive && !personal.isRejected(typed: typed, correction: c.form)
                && (!TypingText.hasUppercase(c.form)
                    || (TypingText.isTitleCase(c.form) && !c.form.contains("'") && c.probability >= 60))
        }).max(by: { $0.probability < $1.probability }),
           TypingText.matchCase(typed: typed, form: fix.form) != typed,
           sentenceStart || !TypingText.isCapitalized(typed) || TypingText.hasUppercase(fix.form) {
            // A name, or a rare spelling, gives way to a word a slip away that
            // is far likelier here: "I've ben" is "been" and "neer" is "never",
            // never "Ben" or "ne'er"; "call mike" stays Mike (2026-10-05). A
            // contact's name never gives way.
            let name = TypingText.hasUppercase(fix.form) && contactForms[key] == nil
            let rare = !TypingText.hasUppercase(fix.form) && fix.probability < Self.rareForm
            if name || rare {
                let gap = fix.probability + Self.rivalGap
                func strong(_ c: Candidate) -> Bool {
                    c.probability >= gap && (rare || fix.probability < Self.rareName || (c.pair ?? 0) >= gap)
                }
                if let rival = contender(typed: typed, key: key, sentenceStart: sentenceStart, ranked: ranked,
                                         declined: declined), strong(rival) {
                    return TypingText.matchCase(typed: typed, form: rival.form)
                }
                // Not sure enough of the other word to put it in, but too sure
                // of it to put in the rare one: "Tom wats" stays as typed.
                let typedKey = TypingText.scalars(key)
                if ranked.contains(where: { c in
                    !c.offensive && c.key != key && strong(c)
                        && TypingText.editDistance(typedKey, TypingText.scalars(c.key)) <= 1
                }) {
                    lastHeldBack = "contested"
                    return nil
                }
            }
            return TypingText.matchCase(typed: typed, form: fix.form)
        }
        return contender(typed: typed, key: key, sentenceStart: sentenceStart, ranked: ranked, declined: declined)
            .map { TypingText.matchCase(typed: typed, form: $0.form) }
    }

    /// The best word a slip or two from what was typed, when it's sure enough
    /// to put in (FORMAT.md "When Glyf autocorrects").
    private func contender(typed: String, key: String, sentenceStart: Bool, ranked: [Candidate],
                           declined: Set<String> = []) -> Candidate? {
        func hold(_ reason: String) -> Candidate? {
            lastHeldBack = reason
            return nil
        }
        guard typed.unicodeScalars.count > 1 else { return hold("one-letter") }
        if TypingText.isCapitalized(typed) && !sentenceStart { return hold("capitalized") }

        // Spellings of the typed letters were settled before this.
        let contenders = ranked.filter { !$0.offensive && $0.key != key && !declined.contains($0.form) }
        guard let first = contenders.first else { return hold("no-contender") }
        if personal.isRejected(typed: typed, correction: first.form) { return hold("rejected") }

        let typedKey = TypingText.scalars(key)
        let typedLength = typedKey.count
        func confidence(_ c: Candidate) -> (Float, Int) {
            let ck = TypingText.scalars(c.key)
            let distance = TypingText.editDistance(typedKey, ck)
            guard distance < ck.count, c.score > 0 else { return (0, distance) }
            return (c.score * (1 - Float(distance) / Float(ck.count)), distance)
        }
        let (conf, distance) = confidence(first)
        if distance > (typedLength <= 4 ? 1 : 2) { return hold("too-far") }
        if conf < Self.autocorrectThreshold { return hold("low-confidence") }
        if let second = contenders.dropFirst().first(where: { $0.key != first.key }) {
            // Two letters swapped is the clearest typo there is ("waht"): a
            // smaller lead suffices when the swap is also the commoner word.
            let swap = first.kinds == .transposition && first.probability >= second.probability
            if conf - confidence(second).0 < (swap ? Self.swapGap : Self.ambiguityGap) { return hold("ambiguous") }
        }

        let kinds = first.kinds
        if kinds.contains(.firstLetterFarSubstitution) { return hold("first-letter-far") }
        if kinds.contains(.farSubstitution) {
            // A far-off key in a short word is another word ("yaar" isn't
            // "year"); in a long word it's a slip ("definately").
            if typedLength <= 4 { return hold("far-short") }
            if first.probability < (typedLength >= 7 ? 90 : 150) { return hold("far-rare") }
        }
        // A lowercase word becomes a proper noun only if it's a common one
        // ("priya" is not "Oriya"), and never an acronym ("ngl" is not "NFL").
        if TypingText.hasUppercase(first.form) && !TypingText.hasUppercase(typed)
            && (TypingText.capitalCount(first.form) > 1 || first.probability < 110) { return hold("rare-name") }
        if !kinds.isDisjoint(with: [.omissionOther, .insertionOther, .completion, .trailingInsertion])
            && first.probability < (typedLength >= 7 ? 60 : 100) { return hold("loose-rare") }
        if distance == 2 && !((typedLength >= 8 && first.probability >= 100) || (typedLength >= 6 && first.probability >= 150)) {
            return hold("two-edits")
        }
        return first
    }

    // MARK: Next word

    func predictions(previous: String?, beforePrevious: String? = nil, policy: Policy = .all,
                     today: Int = TypingText.day()) -> [String] {
        guard policy.contains(.suggestions), let previous, !TypingText.isWebish(previous) else { return [] }
        let prevKey = TypingText.key(previous)
        guard !prevKey.isEmpty else { return [] }
        var scores: [String: Float] = [:]
        // What the two words before were followed by ("I want" → to, you, a).
        useTriples(prevBaseEntry: baseEntry(forKey: prevKey), beforePrevious: beforePrevious)
        for t in likelyTriples where !personal.isBlocked(t.key) {
            scores[t.form] = max(scores[t.form] ?? 0, Float(tripleMap[t.entry] ?? 0) + Self.tripleLift)
        }
        if let base, let node = base.node(forKey: prevKey) {
            let first = base.firstEntry(node)
            for e in first..<(first + base.entryCount(node)) {
                for (target, p) in base.bigrams(e, limit: Self.predictionRows) {
                    let flags = base.flags(target)
                    guard flags & (GlydTrie.flagOffensive | GlydTrie.flagNotAWord) == 0 else { continue }
                    let form = base.form(target)
                    guard !personal.isBlocked(TypingText.key(form)) else { continue }
                    scores[form] = max(scores[form] ?? 0, Float(p))
                }
            }
        }
        for (form, f) in personal.nextWords(after: prevKey, today: today) {
            scores[form] = max(scores[form] ?? 0, f)
        }
        for form in packPairs[prevKey] ?? [] where !personal.isBlocked(TypingText.key(form)) {
            scores[form] = max(scores[form] ?? 0, Self.packPhraseProbability)
        }
        return scores.filter { $0.value >= Self.predictionFloor }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3).map(\.key)
    }

    // MARK: Learning

    /// A word was committed (space, punctuation, return, or a suggestion).
    /// Returns true when the searchable word set changed.
    @discardableResult
    func commit(word: String, previous: String?, autoCapitalized: Bool, policy: Policy,
                today: Int = TypingText.day()) -> Bool {
        guard policy.contains(.learning), Self.isLearnable(word) else { return false }
        var form = word
        if autoCapitalized, TypingText.isCapitalized(word) {
            let lower = TypingText.lowercaseFirst(word)
            if isWord(lower) { form = lower }
        }
        let key = TypingText.key(form)
        let wasKnown = personal.isKnown(key)
        personal.commit(form, previous: previous, today: today)
        if !wasKnown && personal.isKnown(key) && baseEntry(forKey: key, form: form) == nil {
            rebuildExtra()
            return true
        }
        return false
    }

    /// Autocorrect changed a word typed with its own capital mid-sentence
    /// ("Thier" → "Their"). That capital was deliberate, so the typed word
    /// counts as written: typed like that twice, it is a name the person
    /// uses and is never changed again. A sentence start's capital proves
    /// nothing (the shift key put it there), and neither does a fix of the
    /// same letters ("Im" → "I'm" is punctuation, not a name). Returns true
    /// when the searchable word set changed.
    @discardableResult
    func noteCorrected(typed: String, fix: String, sentenceStart: Bool, policy: Policy,
                       today: Int = TypingText.day()) -> Bool {
        let key = TypingText.key(typed)
        guard policy.contains(.learning), !sentenceStart, TypingText.isTitleCase(typed),
              TypingText.key(fix) != key, Self.isLearnable(typed) else { return false }
        let wasKnown = personal.isKnown(key)
        personal.commit(typed, previous: nil, today: today)
        if !wasKnown && personal.isKnown(key) {
            rebuildExtra()
            return true
        }
        return false
    }

    /// The fix autocorrect would make here, were it on: what a field without
    /// autocorrect must not learn ("teh" typed twice in a search bar was
    /// never corrected anywhere again, RESEARCH-IMPROVEMENTS-APP 12).
    func wouldFix(_ typed: String, previous: String?, beforePrevious: String? = nil,
                  sentenceStart: Bool, today: Int = TypingText.day()) -> Bool {
        guard let fix = suggestions(typed: typed, previous: previous, beforePrevious: beforePrevious,
                                    sentenceStart: sentenceStart, policy: .all, today: today).autocorrect
        else { return false }
        return fix != typed
    }

    func revert(typed: String, correction: String, today: Int = TypingText.day()) {
        personal.revert(typed: typed, correction: correction, today: today)
        rebuildExtra()
    }

    func keep(_ typed: String, today: Int = TypingText.day()) {
        guard Self.isLearnable(typed) else { return }
        personal.keep(typed, today: today)
        rebuildExtra()
    }

    func add(_ form: String, today: Int = TypingText.day()) {
        personal.add(form, today: today)
        rebuildExtra()
    }

    func forget(_ form: String) {
        personal.forget(form)
        rebuildExtra()
    }

    func markEditsApplied(_ at: Double) { personal.editsAppliedAt = at }

    /// Words, not codes: no digits, no addresses, no secrets.
    static func isLearnable(_ word: String) -> Bool {
        let count = word.unicodeScalars.count
        return count > 0 && count <= 32
            && !word.contains(where: \.isWhitespace)
            && !TypingText.hasDigit(word)
            && !TypingText.isWebish(word)
            && word.unicodeScalars.contains { $0.properties.isAlphabetic }
            && SecretScanner.scan(word) == .clean
    }

    private func isWord(_ form: String) -> Bool {
        let key = TypingText.key(form)
        // This spelling, not just these letters: a learned "I" never makes
        // "i" a word, or a sentence-start "I" would be learned as "i" (and a
        // lone "i" never fixed again, 2026-10-14).
        if personal.isKnown(key), personal.word(key)?.form == form { return true }
        if packForms[key] == form { return true }
        guard let base, let node = base.node(forKey: key) else { return false }
        let first = base.firstEntry(node)
        return (first..<(first + base.entryCount(node))).contains {
            base.flags($0) & GlydTrie.flagNotAWord == 0 && base.form($0) == form
        }
    }

    private func rebuildExtra() {
        var words: [GlydTrie.Word] = []
        /// The base already has this exact spelling. Same letters aren't
        /// enough: "bas" is not "BA's", "kr" is not "Kr".
        func inBase(_ key: String, _ form: String) -> Bool {
            guard let base, let node = base.node(forKey: key) else { return false }
            let first = base.firstEntry(node)
            return (first..<(first + base.entryCount(node))).contains {
                base.flags($0) & GlydTrie.flagNotAWord == 0 && base.form($0) == form
            }
        }
        for (key, form) in packForms where !inBase(key, form) {
            words.append(GlydTrie.Word(form: form, probability: UInt8(Self.packProbability)))
        }
        for (key, form) in contactForms where !inBase(key, form) {
            words.append(GlydTrie.Word(form: form, probability: UInt8(Self.contactProbability)))
        }
        for (key, form) in personal.knownForms() where !inBase(key, form) {
            let f = personal.probability(key, today: TypingText.day()) ?? 100
            words.append(GlydTrie.Word(form: form, probability: UInt8(max(1, min(255, f)))))
        }
        extra = words.isEmpty ? nil : GlydTrie.build(words)
    }
}
