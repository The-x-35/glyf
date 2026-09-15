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

    static let halfLifeDays = 90.0
    static let expiryDays = 300
    static let maxWords = 10_000
    static let maxPairs = 30_000
    private static let separator = "\u{1F}"

    private(set) var words: [String: Word] = [:]
    private(set) var pairs: [String: Pair] = [:]
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
            guard let k = o["k"] as? String, let f = o["f"] as? String else { continue }
            words[k] = Word(form: f, commits: o["c"] as? Double ?? 0, total: o["t"] as? Int ?? 0,
                            day: o["d"] as? Int ?? 0, kept: o["kept"] as? Int ?? 0, added: o["added"] as? Bool ?? false)
        }
        for o in json["pairs"] as? [[String: Any]] ?? [] {
            guard let p = o["p"] as? String, let k = o["k"] as? String else { continue }
            pairs[p + Self.separator + k] = Pair(count: o["c"] as? Double ?? 0, day: o["d"] as? Int ?? 0)
        }
        for o in json["rejected"] as? [[String: Any]] ?? [] {
            guard let typed = o["typed"] as? String, let fix = o["fix"] as? String else { continue }
            rejected[typed + Self.separator + fix] = o["n"] as? Int ?? 1
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
        blocked.insert(key)
    }

    mutating func unblock(_ form: String) { blocked.remove(TypingText.key(form)) }

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
    }

    /// Drops what hasn't been used in 300 days. Run on load.
    mutating func expire(today: Int) {
        words = words.filter { _, w in w.added || today - w.day <= Self.expiryDays }
        pairs = pairs.filter { _, p in today - p.day <= Self.expiryDays }
    }

    private func decayed(_ value: Double, from day: Int, to today: Int) -> Double {
        guard today > day else { return value }
        return value * pow(2, -Double(today - day) / Self.halfLifeDays)
    }
}
