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

    static let autocorrectThreshold: Float = 0.185
    static let ambiguityGap: Float = 0.05
    static let swapGap: Float = 0.02
    static let predictionFloor: Float = 150
    /// A dictionary fix of apostrophes ("cant" → "can't") beats a real word
    /// with the typed spelling only when it's this much more common.
    static let whitelistGap: Float = 40
    static let packProbability: Float = 160
    static let contactProbability: Float = 40
    static let packPhraseProbability: Float = 180

    let geometry: KeyGeometry
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
        contactForms = Dictionary(forms.map { (TypingText.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        rebuildExtra()
    }

    func replacePersonal(_ lexicon: PersonalLexicon) {
        personal = lexicon
        rebuildExtra()
    }

    // MARK: Suggestions

    func suggestions(typed: String, touches: [(Float, Float)?]? = nil, previous: String?,
                     sentenceStart: Bool, policy: Policy = .all, today: Int = TypingText.day()) -> Suggestions {
        guard policy.contains(.suggestions), !typed.isEmpty, !TypingText.isWebish(typed) else { return .empty(typed) }
        let key = TypingText.key(typed)
        let typedScalars = Array(typed.unicodeScalars)
        guard !key.isEmpty, typedScalars.count <= 48 else { return .empty(typed) }

        let points = typedScalars.enumerated().compactMap { i, u -> TouchPoint? in
            guard u != "'" && u != "\u{2019}" && u != "-" else { return nil }
            let offset = touches.flatMap { i < $0.count ? $0[i] : nil }
            return TouchPoint(character: u, offset: offset, geometry: geometry)
        }
        guard !points.isEmpty else { return .empty(typed) }

        let prevKey = previous.map(TypingText.key).flatMap { $0.isEmpty ? nil : $0 }
        let prevBaseEntry = prevKey.flatMap { baseEntry(forKey: $0) }

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

        // A whitelist target spelled differently ("his" under "hid") is not a
        // form of the typed word; everything else under this key is.
        let realForms = exactForms.filter { !$0.whitelistOnly && !($0.whitelist && $0.key != key) }
        let personalForm = personal.isKnown(key) ? personal.word(key)?.form : nil
        let known = personalForm.map { $0.lowercased() == typed.lowercased() } ?? false
            || realForms.contains { TypingText.sameWord(typed: typed, form: $0.form) }

        // Everything the touches could have meant, best first.
        var best: [String: Candidate] = [:]
        for (trie, source) in sources() {
            for hit in Decoder.search(trie, points: points, geometry: geometry) {
                let first = trie.firstEntry(hit.node)
                for e in first..<(first + trie.entryCount(hit.node)) {
                    let flags = trie.flags(e)
                    guard flags & GlydTrie.flagNotAWord == 0 else { continue }
                    let c = candidate(trie: trie, source: source, entry: e, key: nil, hit: hit,
                                      points: points.count, prevKey: prevKey, prevBaseEntry: prevBaseEntry, today: today)
                    guard !personal.isBlocked(c.key) else { continue }
                    if let existing = best[c.form], existing.score >= c.score { continue }
                    best[c.form] = c
                }
            }
        }
        let ranked = best.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.form < $1.form }

        var result = Suggestions(typed: typed, known: known, autocorrect: nil, alternatives: [])
        if policy.contains(.autocorrect) {
            result.autocorrect = decide(typed: typed, key: key, known: known, sentenceStart: sentenceStart,
                                        exactForms: exactForms, realForms: realForms, ranked: ranked)
        }
        var seen: Set<String> = [typed.lowercased()]
        if let ac = result.autocorrect { seen.insert(ac.lowercased()) }
        for c in ranked where !c.offensive {
            // "United States" is no completion for "u".
            if c.form.contains(" ") && c.key != key { continue }
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
    }

    private enum Source { case base, extra }

    private func sources() -> [(GlydTrie, Source)] {
        var out: [(GlydTrie, Source)] = []
        if let base { out.append((base, .base)) }
        if let extra { out.append((extra, .extra)) }
        return out
    }

    private func candidate(trie: GlydTrie, source: Source, entry: UInt32, key: String?, hit: Decoder.Hit,
                           points: Int, prevKey: String?, prevBaseEntry: UInt32?, today: Int) -> Candidate {
        let form = trie.form(entry)
        let formKey = key ?? TypingText.key(form)
        let flags = trie.flags(entry)
        let f = languageProbability(key: formKey, form: form,
                                    baseProbability: source == .base ? Float(trie.probability(entry)) : nil,
                                    entry: source == .base ? entry : nil,
                                    prevKey: prevKey, prevBaseEntry: prevBaseEntry, today: today)
        let language = 1.1214 * (255 - f) / 255
        var score = 1 - (hit.spatial + language) / (1.1214 + 0.1 * Float(points))
        if hit.exact { score += 1.1 }
        return Candidate(form: form, key: formKey, score: score, probability: f, kinds: hit.kinds,
                         offensive: flags & GlydTrie.flagOffensive != 0,
                         whitelist: flags & GlydTrie.flagWhitelist != 0,
                         whitelistOnly: flags & GlydTrie.flagNotAWord != 0)
    }

    /// FORMAT.md "Language f": the best evidence any source has for the word.
    private func languageProbability(key: String, form: String, baseProbability: Float?, entry: UInt32?,
                                     prevKey: String?, prevBaseEntry: UInt32?, today: Int) -> Float {
        var f = baseProbability ?? 0
        if let p = personal.probability(key, today: today) { f = max(f, p) }
        if packForms[key] != nil { f = max(f, Self.packProbability) }
        if contactForms[key] != nil { f = max(f, Self.contactProbability) }
        if let prevKey {
            if let p = personal.pairProbability(previous: prevKey, key, today: today) { f = max(f, p) }
            if packPairs[prevKey]?.contains(where: { TypingText.key($0) == key }) == true {
                f = max(f, Self.packPhraseProbability)
            }
            if let prevBaseEntry, let base {
                let target = entry ?? baseEntry(forKey: key, form: form)
                if let target, let p = base.bigramProbability(from: prevBaseEntry, to: target) { f = max(f, Float(p)) }
            }
        }
        return min(f, 255)
    }

    private func baseEntry(forKey key: String, form: String? = nil) -> UInt32? {
        guard let base, let node = base.node(forKey: key), base.entryCount(node) > 0 else { return nil }
        let first = base.firstEntry(node)
        guard let form else { return first }
        return (first..<(first + base.entryCount(node))).first { base.form($0) == form }
    }

    /// FORMAT.md "When Glyf autocorrects".
    private func decide(typed: String, key: String, known: Bool, sentenceStart: Bool,
                        exactForms: [Candidate], realForms: [Candidate], ranked: [Candidate]) -> String? {
        guard !TypingText.hasDigit(typed), TypingText.capitalCount(typed) < 2 else { return nil }
        // Stretched for emphasis ("sooo", "yesss"): meant, never "solo".
        guard !TypingText.isStretched(typed) else { return nil }

        // Dictionary fixes. Apostrophes ("cant" → "can't") unless the typed
        // spelling is a real word nearly as common ("id" stays "id"); a
        // different word ("alot" → "a lot") only when the typed spelling is no
        // word at all — AOSP's "hum" → "him" and "bot" → "not" never happen.
        let typedReal = realForms.filter { TypingText.sameWord(typed: typed, form: $0.form) }.map(\.probability).max()
        let fixes = exactForms.filter { c in
            guard c.whitelist, !personal.isRejected(typed: typed, correction: c.form) else { return false }
            if c.key != key { return !known && realForms.isEmpty }
            if let typedReal { return c.probability >= typedReal + Self.whitelistGap }
            return !known
        }
        if let w = fixes.max(by: { $0.probability < $1.probability }) {
            let fixed = TypingText.matchCase(typed: typed, form: w.form)
            return fixed == typed ? nil : fixed
        }
        if known { return nil }

        // Same letters, different apostrophes or capitals: "thats" → "that's",
        // "delhi" → "Delhi". Never into an acronym ("hsa" is not "HSA") or a
        // capitalized contraction ("bas" is not "BA's").
        if let fix = realForms.filter({ c in
            !c.offensive && !personal.isRejected(typed: typed, correction: c.form)
                && (!TypingText.hasUppercase(c.form)
                    || (TypingText.isTitleCase(c.form) && !c.form.contains("'") && c.probability >= 60))
        }).max(by: { $0.probability < $1.probability }) {
            let fixed = TypingText.matchCase(typed: typed, form: fix.form)
            if fixed != typed && (sentenceStart || !TypingText.isCapitalized(typed) || TypingText.hasUppercase(fix.form)) {
                return fixed
            }
        }

        guard typed.unicodeScalars.count > 1 else { return nil }
        if TypingText.isCapitalized(typed) && !sentenceStart { return nil }

        // Spellings of the typed letters were settled above, and dictionary
        // fixes only ever apply through the rule above.
        let contenders = ranked.filter { !$0.offensive && $0.key != key && !$0.whitelist }
        guard let first = contenders.first,
              !personal.isRejected(typed: typed, correction: first.form) else { return nil }

        let typedKey = TypingText.scalars(key)
        let typedLength = typedKey.count
        func confidence(_ c: Candidate) -> (Float, Int) {
            let ck = TypingText.scalars(c.key)
            let distance = TypingText.editDistance(typedKey, ck)
            guard distance < ck.count, c.score > 0 else { return (0, distance) }
            return (c.score * (1 - Float(distance) / Float(ck.count)), distance)
        }
        let (conf, distance) = confidence(first)
        guard distance <= (typedLength <= 4 ? 1 : 2), conf >= Self.autocorrectThreshold else { return nil }
        if let second = contenders.dropFirst().first(where: { $0.key != first.key }) {
            // Two letters swapped is the clearest typo there is ("waht"): a
            // smaller lead suffices when the swap is also the commoner word.
            let swap = first.kinds == .transposition && first.probability >= second.probability
            guard conf - confidence(second).0 >= (swap ? Self.swapGap : Self.ambiguityGap) else { return nil }
        }

        let kinds = first.kinds
        if kinds.contains(.firstLetterFarSubstitution) { return nil }
        if kinds.contains(.farSubstitution) {
            // A far-off key in a short word is another word ("yaar" isn't
            // "year"); in a long word it's a slip ("definately").
            if typedLength <= 4 { return nil }
            if first.probability < (typedLength >= 7 ? 90 : 150) { return nil }
        }
        // A lowercase word becomes a proper noun only if it's a common one
        // ("priya" is not "Oriya"), and never an acronym ("ngl" is not "NFL").
        if TypingText.hasUppercase(first.form) && !TypingText.hasUppercase(typed)
            && (TypingText.capitalCount(first.form) > 1 || first.probability < 110) { return nil }
        if !kinds.isDisjoint(with: [.omissionOther, .insertionOther, .completion, .trailingInsertion])
            && first.probability < 120 { return nil }
        if distance == 2 && !((typedLength >= 8 && first.probability >= 100) || (typedLength >= 6 && first.probability >= 150)) {
            return nil
        }
        if kinds.contains(.completion) && typedLength < 4 { return nil }
        return TypingText.matchCase(typed: typed, form: first.form)
    }

    // MARK: Next word

    func predictions(previous: String?, policy: Policy = .all, today: Int = TypingText.day()) -> [String] {
        guard policy.contains(.suggestions), let previous, !TypingText.isWebish(previous) else { return [] }
        let prevKey = TypingText.key(previous)
        guard !prevKey.isEmpty else { return [] }
        var scores: [String: Float] = [:]
        if let base, let node = base.node(forKey: prevKey) {
            let first = base.firstEntry(node)
            for e in first..<(first + base.entryCount(node)) {
                for (target, p) in base.bigrams(e) {
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
            && !TypingText.hasDigit(word)
            && !TypingText.isWebish(word)
            && word.unicodeScalars.contains { $0.properties.isAlphabetic }
            && SecretScanner.scan(word) == .clean
    }

    private func isWord(_ form: String) -> Bool {
        let key = TypingText.key(form)
        if personal.isKnown(key) || packForms[key] != nil { return true }
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
