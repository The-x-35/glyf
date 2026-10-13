import Foundation

/// Google's Noto Animated Emoji as stickers, searched on the phone: the
/// server's catalogue and search (server/src/routes/media.ts, `searchNoto`
/// and `notoItem`) ported as they are, so the Stickers tab needs no request
/// to list them, only the CDN for the images (docs/SERVER-INVENTORY.md,
/// 2026-10-14). Same items, same order, same pages of 30 and the same credit
/// as GET /media/emoji-stickers, which stays for older versions.
enum NotoStickers {

    struct Sticker: Equatable {
        /// Codepoint path segment, e.g. "1f602" or "2764_fe0f_200d_1f525".
        let c: String
        /// Short names, e.g. ["joy"] or ["folded-hands", "pray", "thank-you"].
        let t: [String]
        /// Category: smileys, animals, food, activities, objects, symbols, travel, people, flags.
        let g: String
    }

    struct Item: Equatable {
        let id: String
        let title: String
        let preview: String
        let pw: Double, ph: Double
        let url: String
        let w: Double, h: Double
    }

    struct Page: Equatable {
        let items: [Item]
        let next: String?
        let attribution: String
    }

    static let cdn = "https://fonts.gstatic.com/s/e/notoemoji/latest"
    static let attribution = "Noto Emoji by Google · CC BY 4.0"
    static let pageSize = 30

    /// The catalogue, most popular first (NotoCatalogue.generated.swift).
    static let catalogue: [Sticker] = NotoCatalogue.lines.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return Sticker(c: String(parts[0]),
                       t: parts[2].split(separator: ",").map(String.init),
                       g: String(parts[1]))
    }

    /// The words people search stickers with, in the catalogue's own names.
    private static let synonyms: [String: [String]] = [
        "hello": ["wave"], "hi": ["wave"], "hey": ["wave"], "bye": ["wave"],
        "wow": ["surprised", "hushed", "astonished", "mind-blown", "open-mouth", "star-struck", "exploding-head"],
        "omg": ["scream", "mind-blown", "astonished", "flushed"],
        "love": ["heart", "heart-eyes", "heart-face", "kissing-heart", "love-letter"],
        "laughing": ["joy", "laughing", "rofl", "rolling-on-the-floor-laughing", "grin", "sweat-smile"],
        "haha": ["joy", "laughing", "rofl", "rolling-on-the-floor-laughing", "grin"],
        "lol": ["joy", "laughing", "rofl", "rolling-on-the-floor-laughing"],
        "happy": ["smile", "grin", "blush", "warm-smile", "joy", "partying-face"],
        "sad": ["sad", "cry", "loudly-crying", "pensive", "disappointed", "worried", "pleading"],
        "cry": ["cry", "loudly-crying", "happy-cry"],
        "angry": ["angry", "rage", "steam", "cursing", "triumph"],
        "party": ["partying-face", "party-popper", "confetti", "balloon", "tada"],
        "celebrate": ["partying-face", "party-popper", "confetti", "clap", "fireworks"],
        "thank you": ["thank-you", "folded-hands", "pray", "heart-hands"],
        "thanks": ["thank-you", "folded-hands", "pray", "heart-hands"],
        "please": ["please", "pleading", "folded-hands"],
        "sleepy": ["sleep", "sleepy", "yawn", "zzz"],
        "tired": ["sleep", "sleepy", "yawn", "weary", "tired"],
        "thumbs up": ["thumbs-up", "+1", "ok", "clap"], "yes": ["thumbs-up", "+1", "ok", "check"],
        "no": ["thumbs-down", "-1", "cross", "x", "no"], "ok": ["ok", "thumbs-up", "+1"],
        "cool": ["sunglasses", "cool", "smirk"], "think": ["thinking-face", "monocle"],
        "birthday": ["birthday-cake", "partying-face", "party-popper", "gift", "balloon"],
        "fire": ["fire", "lit"], "hot": ["fire", "hot-face"], "cold": ["cold-face", "snowflake"],
        "kiss": ["kissing", "kissing-heart", "kiss"], "hug": ["hug-face", "hugging"],
        "sick": ["sick", "nauseated", "mask", "thermometer", "sneeze"],
        "money": ["money-face", "money-with-wings", "dollar"], "scared": ["scream", "fearful", "anxious"],
        "dance": ["dancer", "man-dancing"], "music": ["musical-notes", "microphone", "headphone"],
    ]

    private static let categoryWords: [String: String] = [
        "food": "food", "drink": "food", "animal": "animals", "animals": "animals", "pet": "animals",
        "nature": "animals", "sport": "activities", "sports": "activities", "travel": "travel",
        "flag": "flags", "flags": "flags", "object": "objects", "objects": "objects", "symbol": "symbols",
        "symbols": "symbols", "face": "smileys", "faces": "smileys", "smiley": "smileys", "smileys": "smileys",
    ]

    /// Words a name answers to: "loudly-crying" answers "loudly", "crying"
    /// and the whole name.
    private static func words(_ name: String) -> [String] {
        [name] + name.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
    }

    /// Stickers for a search, best first; empty `q` is the whole catalogue by
    /// popularity (the "trending" of a fixed set).
    static func search(_ q: String) -> [Sticker] {
        let all = catalogue
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return all }
        let split = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var wanted: [String] = []
        var seen = Set<String>()
        func add(_ w: String) { if seen.insert(w).inserted { wanted.append(w) } }
        ([query] + split).forEach(add)
        for w in wanted { for s in synonyms[w] ?? [] { add(s) } }
        let category = split.lazy.compactMap { categoryWords[$0] }.first
        var scored: [(s: Sticker, score: Int, rank: Int)] = []
        for (rank, s) in all.enumerated() {
            var score = 0
            for tag in s.t {
                if seen.contains(tag) { score = max(score, 3) }
                else if words(tag).contains(where: seen.contains) { score = max(score, 2) }
                else if wanted.contains(where: { $0.utf16.count >= 3 && tag.hasPrefix($0) }) { score = max(score, 1) }
            }
            if let category, s.g == category { score = max(score, 1) }
            if score > 0 { scored.append((s, score, rank)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
        return scored.map(\.s)
    }

    static func item(_ s: Sticker) -> Item {
        let title = (s.t.first ?? "emoji").replacingOccurrences(of: "-", with: " ")
        return Item(id: "noto:\(s.c)", title: title,
                    preview: "\(cdn)/\(s.c)/128.png", pw: 128, ph: 128,
                    url: "\(cdn)/\(s.c)/512.gif", w: 512, h: 512)
    }

    /// One page of a search, as GET /media/emoji-stickers?q=&page= answers.
    static func page(query: String, page: String?) -> Page {
        let q = String(query.prefix(60))
        let n = max(1, min(Int(page ?? "1") ?? 1, 100))
        let hits = search(q)
        let start = (n - 1) * pageSize
        let slice = start < hits.count ? hits[start..<min(start + pageSize, hits.count)] : []
        return Page(items: slice.map(item),
                    next: start + pageSize < hits.count ? String(n + 1) : nil,
                    attribution: attribution)
    }
}
