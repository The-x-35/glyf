import Foundation

/// The person's own repeated sentences: once a sentence has been sent three
/// times ("On my way, be there in 10"), typing its first words offers the
/// rest in the strip (Arpit, 2026-10-14: "make new features"; research:
/// TextExpander's suggested snippets, Gboard's smart compose). Kept on the
/// phone only, never from a password or code field, never anything the
/// secret scanner flags, and forgotten after 60 days unused. PhraseMemory.kt
/// is Android's twin.
struct PhraseMemory: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// The sentence as last typed, capitals and punctuation included.
        var text: String
        var count: Int
        /// TypingText.day() it was last typed.
        var last: Int
    }

    var entries: [String: Entry] = [:]

    static let timesBeforeOffered = 3
    static let keepDays = 60
    static let most = 300

    /// Lowercase, single spaces, no closing punctuation: "On my way!" and
    /// "on my  way" are the same sentence.
    static func key(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?…")))
    }

    /// A sentence worth remembering: four words or more, 15 to 140
    /// characters, no long numbers (codes, phones, cards), no links or
    /// addresses, nothing the secret scanner flags.
    static func worthKeeping(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 15, t.count <= 140, t.split(separator: " ").count >= 4 else { return false }
        if t.range(of: #"\d{4,}|https?://|www\.|@[\w-]+\.\w"#, options: .regularExpression) != nil { return false }
        return SecretScanner.scan(t) == .clean
    }

    /// The sentence a text has just finished: "…ok. On my way, be there in
    /// 10! " → "On my way, be there in 10!".
    static func endedSentence(in text: String) -> String? {
        guard let last = text.last, last == " " || last == "\n" else { return nil }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let end = body.last, ".!?".contains(end) else { return nil }
        return lastSentence(of: body)
    }

    /// The sentence being typed (or the last one): what follows the last
    /// full stop, question or exclamation mark, or line break.
    static func lastSentence(of text: String) -> String {
        var body = Substring(text)
        // A sentence's own closing mark belongs to it.
        while let c = body.last, ".!?".contains(c) || c == " " { body = body.dropLast() }
        let start = body.lastIndex(where: { ".!?\n".contains($0) }).map { body.index(after: $0) } ?? body.startIndex
        let sentence = text[start...]
        return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func record(_ sentence: String, today: Int) {
        guard Self.worthKeeping(sentence) else { return }
        let k = Self.key(sentence)
        var e = entries[k] ?? Entry(text: sentence, count: 0, last: today)
        e.count += 1
        e.last = today
        e.text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[k] = e
        prune(today: today)
    }

    mutating func prune(today: Int) {
        entries = entries.filter { today - $0.value.last <= Self.keepDays }
        if entries.count > Self.most {
            let keep = entries.sorted { ($0.value.count, $0.value.last) > ($1.value.count, $1.value.last) }.prefix(Self.most)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    /// The rest of a remembered sentence that starts with what is being
    /// typed, offered once a word ends: two words at least typed, two at
    /// least to come. The most used one wins.
    func completion(after typed: String, today: Int) -> String? {
        let sentence = Self.lastSentence(of: typed)
        let k = Self.key(sentence)
        guard k.count >= 5, k.split(separator: " ").count >= 2, typed.last != "\n" else { return nil }
        let hits = entries.values.filter {
            $0.count >= Self.timesBeforeOffered && today - $0.last <= Self.keepDays
                && Self.key($0.text).hasPrefix(k) && Self.key($0.text).count > k.count
        }
        guard let best = hits.max(by: { ($0.count, $0.last) < ($1.count, $1.last) }) else { return nil }
        // Offered at a word's end only: the rest goes in after a space.
        guard typed.last?.isWhitespace == true else { return nil }
        let typedWords = sentence.split(separator: " ").count
        let words = best.text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= typedWords + 2 else { return nil }
        return words[typedWords...].joined(separator: " ")
    }
}

/// Where the keyboard keeps PhraseMemory: phrases.json in the App Group.
final class PhraseMemoryStore {
    static let shared = PhraseMemoryStore()
    private static let file = "phrases.json"
    private(set) var memory: PhraseMemory

    private init() {
        if let json = AppGroupStore.readJSON(name: Self.file),
           let data = try? JSONSerialization.data(withJSONObject: json),
           let m = try? JSONDecoder().decode(PhraseMemory.self, from: data) {
            memory = m
        } else {
            memory = PhraseMemory()
        }
    }

    func record(_ sentence: String) {
        let before = memory
        memory.record(sentence, today: TypingText.day())
        guard memory != before,
              let data = try? JSONEncoder().encode(memory),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        _ = AppGroupStore.writeJSON(json, name: Self.file)
    }

    func forgetAll() {
        memory = PhraseMemory()
        _ = AppGroupStore.writeJSON(["entries": [String: Any]()], name: Self.file)
    }
}
