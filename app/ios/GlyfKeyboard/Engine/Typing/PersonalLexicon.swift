import Foundation

/// What this person types, kept on the device (shared/typing/FORMAT.md
/// "Learning"): words and word pairs they commit, words they kept after a
/// correction, words they added, and corrections they turned down.
struct PersonalLexicon: Equatable {

    struct Word: Equatable {
        var form: String
        /// Commits, decayed with a 90-day half-life as of `day`.
        var commits: Double
        /// Raw commits ever — learned status never decays away.
        var total: Int
        var day: Int
        var kept: Int = 0
        var added: Bool = false
    }

    struct Pair: Equatable {
        var count: Double
        var day: Int
    }

    /// An emoji run this person puts after a word or two ("love you" →
    /// ❤️❤️❤️): decayed uses, raw uses, last day.
    struct EmojiHabit: Equatable {
        var count: Double
        var total: Int
        var day: Int
    }

    static let halfLifeDays = 90.0
    static let expiryDays = 300
    static let maxWords = 10_000
    static let maxPairs = 30_000
    static let maxEmoji = 3_000
    /// An emoji run is offered after it followed the same words this often...
    static let emojiTimes = 2
    /// ...and on at least this share of the times those words were typed:
    /// "thank you 🙏" twice says nothing about every other "you".
    static let emojiShare = 0.15
    private static let separator = "\u{1F}"

    private(set) var words: [String: Word] = [:]
    private(set) var pairs: [String: Pair] = [:]
    /// "context␟emoji" → habit; the context is one word key ("haha") or two
    /// joined by a space ("love you").
    private(set) var emoji: [String: EmojiHabit] = [:]
    /// "typed␟correction", both lowercased → times reverted.
    private(set) var rejected: [String: Int] = [:]
    private(set) var blocked: Set<String> = []
    private(set) var commitsTotal: Double = 0
    /// Newest app edit ("My words": add, forget, reset) already applied.
    var editsAppliedAt: Double = 0

    // MARK: Saving — the JSON both platforms write (the app reads it for "My words")

    init() {}

    init(json: [String: Any]) {
        commitsTotal = json["total"] as? Double ?? 0
        for o in json["words"] as? [[String: Any]] ?? [] {
            guard let k = o["k"] as? String, var f = o["f"] as? String,
                  !k.contains(where: \.isWhitespace) else { continue } // "Hi\u{2028}there", 2026-10-14
            let kept = o["kept"] as? Int ?? 0, added = o["added"] as? Bool ?? false
            // A lone "i" learned only because it slipped past the fix is the
            // pronoun (2026-10-14: once learned, "i" was never "I" again).
            if k == "i", f == "i", kept == 0, !added { f = "I" }
            words[k] = Word(form: f, commits: o["c"] as? Double ?? 0, total: o["t"] as? Int ?? 0,
                            day: o["d"] as? Int ?? 0, kept: kept, added: added)
        }
        for o in json["pairs"] as? [[String: Any]] ?? [] {
            guard let p = o["p"] as? String, let k = o["k"] as? String else { continue }
            pairs[p + Self.separator + k] = Pair(count: o["c"] as? Double ?? 0, day: o["d"] as? Int ?? 0)
        }
        for o in json["rejected"] as? [[String: Any]] ?? [] {
            guard let typed = o["typed"] as? String, let fix = o["fix"] as? String else { continue }
            rejected[typed + Self.separator + fix] = o["n"] as? Int ?? 1
        }
        for o in json["emoji"] as? [[String: Any]] ?? [] {
            guard let x = o["x"] as? String, let e = o["e"] as? String, !x.isEmpty, !e.isEmpty else { continue }
            emoji[x + Self.separator + e] = EmojiHabit(count: o["c"] as? Double ?? 0, total: o["t"] as? Int ?? 0,
                                                       day: o["d"] as? Int ?? 0)
        }
        blocked = Set(json["blocked"] as? [String] ?? [])
        editsAppliedAt = json["editsAt"] as? Double ?? 0
    }

    func json() -> [String: Any] {
        [
            "v": 1,
            "total": commitsTotal,
            "words": words.keys.sorted().map { k -> [String: Any] in
                let w = words[k]!
                return ["k": k, "f": w.form, "c": w.commits, "t": w.total, "d": w.day, "kept": w.kept, "added": w.added]
            },
            "pairs": pairs.keys.sorted().map { k -> [String: Any] in
                let parts = k.components(separatedBy: Self.separator)
                return ["p": parts[0], "k": parts.count > 1 ? parts[1] : "", "c": pairs[k]!.count, "d": pairs[k]!.day]
            },
            "rejected": rejected.keys.sorted().map { k -> [String: Any] in
                let parts = k.components(separatedBy: Self.separator)
                return ["typed": parts[0], "fix": parts.count > 1 ? parts[1] : "", "n": rejected[k]!]
            },
            "emoji": emoji.keys.sorted().map { k -> [String: Any] in
                let parts = k.components(separatedBy: Self.separator)
                let h = emoji[k]!
                return ["x": parts[0], "e": parts.count > 1 ? parts[1] : "", "c": h.count, "t": h.total, "d": h.day]
            },
            "blocked": blocked.sorted(),
            "editsAt": editsAppliedAt,
        ]
    }

    // MARK: Reading

    func word(_ key: String) -> Word? { words[key] }

    /// Typed twice, kept once, or added: never autocorrected away again.
    func isKnown(_ key: String) -> Bool {
        guard let w = words[key] else { return false }
        return w.total >= 2 || w.kept > 0 || w.added
    }

    func isBlocked(_ key: String) -> Bool { blocked.contains(key) }

    func isRejected(typed: String, correction: String) -> Bool {
        rejected[typed.lowercased() + Self.separator + correction.lowercased()] != nil
    }

    /// AOSP-scale probability (0–255) this person gives the word, if any.
    func probability(_ key: String, today: Int) -> Float? {
        guard let w = words[key], !blocked.contains(key) else { return nil }
        var f: Float = 0
        if w.total >= 2 {
            let effective = decayed(w.commits, from: w.day, to: today)
            let p = max(effective - 1, 0.5) / max(commitsTotal, 8192)
            f = Float(255 + 8.59 * log2(p) - 32)
        }
        if w.kept > 0 { f = max(f, 120) }
        if w.added { f = max(f, 160) }
        return f > 0 ? min(f, 255) : nil
    }

    func pairProbability(previous: String, _ key: String, today: Int) -> Float? {
        guard let pair = pairs[previous + Self.separator + key], let prev = words[previous],
              !blocked.contains(key) else { return nil }
        let count = decayed(pair.count, from: pair.day, to: today)
        let prevCount = max(decayed(prev.commits, from: prev.day, to: today), 2)
        let f = Float(255 + 8.59 * log2(min(count / prevCount, 1)) - 4)
        return f > 0 ? min(f, 255) : nil
    }

    /// Words this person has followed `previous` with, most frequent first.
    func nextWords(after previous: String, today: Int) -> [(form: String, probability: Float)] {
        let prefix = previous + Self.separator
        var out: [(String, Float)] = []
        for (k, _) in pairs where k.hasPrefix(prefix) {
            let key = String(k.dropFirst(prefix.count))
            guard let w = words[key], let f = pairProbability(previous: previous, key, today: today) else { continue }
            out.append((w.form, f))
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// The word this person uses most that starts with what is being typed
    /// (and is longer): "cut" → their "cutee". PersonalLexicon.kt's twin.
    func completion(prefix: String, today: Int) -> String? {
        words.filter { k, _ in k.count > prefix.count && k.hasPrefix(prefix) && isKnown(k) && !blocked.contains(k) }
            .max { a, b in
                func weight(_ w: Word) -> Double { decayed(w.commits, from: w.day, to: today) + Double(w.kept) + (w.added ? 2 : 0) }
                return weight(a.value) < weight(b.value)
            }?.value.form
    }

    /// The emoji run this person puts after `word` (with `previous` before
    /// it), once it's a habit: the two-word context first ("love you" →
    /// ❤️❤️❤️ while "thank you" → 🙏), then the word alone.
    func emojiRun(after word: String, previous: String?, today: Int) -> String? {
        let w = TypingText.key(word)
        guard !w.isEmpty, !blocked.contains(w) else { return nil }
        var contexts: [(context: String, typed: Double)] = []
        if let previous {
            let p = TypingText.key(previous)
            if !p.isEmpty {
                let typed = pairs[p + Self.separator + w].map { decayed($0.count, from: $0.day, to: today) } ?? 0
                contexts.append((p + " " + w, typed))
            }
        }
        contexts.append((w, words[w].map { decayed($0.commits, from: $0.day, to: today) } ?? 0))
        for (context, typed) in contexts {
            let prefix = context + Self.separator
            let best = emoji.filter { $0.key.hasPrefix(prefix) && $0.value.total >= Self.emojiTimes }
                .max { a, b in
                    let ca = decayed(a.value.count, from: a.value.day, to: today)
                    let cb = decayed(b.value.count, from: b.value.day, to: today)
                    return ca != cb ? ca < cb : a.value.day < b.value.day
                }
            guard let best else { continue }
            let uses = decayed(best.value.count, from: best.value.day, to: today)
            // Typed without a space ("haha😂") the word was never committed.
            guard uses >= Self.emojiShare * max(typed, uses) else { continue }
            return String(best.key.dropFirst(prefix.count))
        }
        return nil
    }

    /// Learned, kept and added words — the ones a dictionary may not have.
    func knownForms() -> [(key: String, form: String)] {
        words.compactMap { key, w in isKnown(key) && !blocked.contains(key) ? (key, w.form) : nil }
    }

    // MARK: Changing

    mutating func commit(_ form: String, previous: String?, today: Int) {
        let key = TypingText.key(form)
        guard !key.isEmpty, !blocked.contains(key) else { return }
        var w = words[key] ?? Word(form: form, commits: 0, total: 0, day: today)
        w.commits = decayed(w.commits, from: w.day, to: today) + 1
        w.total += 1
        w.day = today
        w.form = form
        words[key] = w
        commitsTotal += 1
        if let previous {
            let prev = TypingText.key(previous)
            if !prev.isEmpty, words[prev] != nil {
                let pk = prev + Self.separator + key
                var pair = pairs[pk] ?? Pair(count: 0, day: today)
                pair.count = decayed(pair.count, from: pair.day, to: today) + 1
                pair.day = today
                pairs[pk] = pair
            }
        }
        prune(today: today)
    }

    /// `run` went in after `word` (and `previous` before it): one more use
    /// of the habit for each context.
    mutating func noteEmoji(_ run: String, after word: String, previous: String?, today: Int) {
        let w = TypingText.key(word)
        guard !w.isEmpty, !run.isEmpty, !blocked.contains(w) else { return }
        var contexts = [w]
        if let previous {
            let p = TypingText.key(previous)
            if !p.isEmpty, !blocked.contains(p) { contexts.append(p + " " + w) }
        }
        for context in contexts {
            let k = context + Self.separator + run
            var h = emoji[k] ?? EmojiHabit(count: 0, total: 0, day: today)
            h.count = decayed(h.count, from: h.day, to: today) + 1
            h.total += 1
            h.day = today
            emoji[k] = h
        }
        prune(today: today)
    }

    /// The user undid `typed` → `correction`: never offer it again, keep the
    /// typed word, and take back the commit the correction earned.
    mutating func revert(typed: String, correction: String, today: Int) {
        rejected[typed.lowercased() + Self.separator + correction.lowercased(), default: 0] += 1
        keep(typed, today: today)
        let ck = TypingText.key(correction)
        if var w = words[ck], w.total > 0 {
            w.total -= 1
            w.commits = max(decayed(w.commits, from: w.day, to: today) - 1, 0)
            w.day = today
            if w.total == 0 && w.kept == 0 && !w.added { words[ck] = nil } else { words[ck] = w }
            commitsTotal = max(commitsTotal - 1, 0)
        }
    }

    /// The user chose exactly what they typed (a revert or the literal slot).
    mutating func keep(_ typed: String, today: Int) {
        let key = TypingText.key(typed)
        guard !key.isEmpty else { return }
        blocked.remove(key)
        var w = words[key] ?? Word(form: typed, commits: 0, total: 0, day: today)
        w.kept += 1
        w.day = today
        words[key] = w
    }

    mutating func add(_ form: String, today: Int) {
        let key = TypingText.key(form)
        guard !key.isEmpty else { return }
        blocked.remove(key)
        var w = words[key] ?? Word(form: form, commits: 0, total: 0, day: today)
        w.added = true
        w.form = form
        w.day = today
        words[key] = w
    }

    /// Removed in the app: forgotten, and never learned or offered again.
    mutating func forget(_ form: String) {
        let key = TypingText.key(form)
        guard !key.isEmpty else { return }
        words[key] = nil
        pairs = pairs.filter { k, _ in !k.hasPrefix(key + Self.separator) && !k.hasSuffix(Self.separator + key) }
        emoji = emoji.filter { k, _ in
            !(k.components(separatedBy: Self.separator).first ?? "").split(separator: " ").contains { $0 == key }
        }
        // Its corrections come back too: a word forgotten in "My words" is
        // corrected again ("helloo" stayed uncorrected forever).
        let typed = form.lowercased()
        rejected = rejected.filter { k, _ in !k.hasPrefix(typed + Self.separator) }
        blocked.insert(key)
    }

    mutating func unblock(_ form: String) { blocked.remove(TypingText.key(form)) }

    /// One emoji habit dropped from "My words" ("love you" → "❤️❤️❤️"),
    /// leaving the words themselves. It's learned again only from scratch.
    mutating func forgetEmoji(context: String, run: String) {
        emoji[context + Self.separator + run] = nil
    }

    /// A correction turned down, on its own (a revert also keeps the word).
    mutating func reject(typed: String, correction: String) {
        rejected[typed.lowercased() + Self.separator + correction.lowercased(), default: 0] += 1
    }

    mutating func reset() { self = PersonalLexicon() }

    mutating func prune(today: Int) {
        if words.count > Self.maxWords + 500 {
            let keep = words.sorted {
                decayed($0.value.commits, from: $0.value.day, to: today) + Double($0.value.kept * 4)
                    > decayed($1.value.commits, from: $1.value.day, to: today) + Double($1.value.kept * 4)
            }.prefix(Self.maxWords)
            words = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if pairs.count > Self.maxPairs + 1_500 {
            let keep = pairs.sorted {
                decayed($0.value.count, from: $0.value.day, to: today) > decayed($1.value.count, from: $1.value.day, to: today)
            }.prefix(Self.maxPairs)
            pairs = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if emoji.count > Self.maxEmoji + 200 {
            let keep = emoji.sorted {
                decayed($0.value.count, from: $0.value.day, to: today) > decayed($1.value.count, from: $1.value.day, to: today)
            }.prefix(Self.maxEmoji)
            emoji = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    /// Drops what hasn't been used in 300 days. Run on load.
    mutating func expire(today: Int) {
        words = words.filter { _, w in w.added || today - w.day <= Self.expiryDays }
        pairs = pairs.filter { _, p in today - p.day <= Self.expiryDays }
        emoji = emoji.filter { _, h in today - h.day <= Self.expiryDays }
    }

    private func decayed(_ value: Double, from day: Int, to today: Int) -> Double {
        guard today > day else { return value }
        return value * pow(2, -Double(today - day) / Self.halfLifeDays)
    }
}
