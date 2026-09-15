import Foundation

/// The user's recent searches, per tab.
///
/// Stored on the device and nowhere else. Google exposes no API for a
/// person's own Search history, and YouTube removed watch-history access from
/// its Data API years ago — signing in with Google would not change that — so
/// "recent" genuinely means "what you typed on this phone". The server's
/// trending/popular rows fill the rest of the landing state.
enum SearchRecents {

    static let fileName = "search-recents.json"
    /// Enough to be useful, few enough that the landing state stays scannable.
    static let maxPerVertical = 6

    private static var cache: [String: [String]]?

    static func list(_ vertical: String) -> [String] {
        load()[vertical] ?? []
    }

    static func record(_ query: String, vertical: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        var all = load()
        var rows = all[vertical] ?? []
        // Re-searching something moves it to the top rather than duplicating.
        rows.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        rows.insert(q, at: 0)
        all[vertical] = Array(rows.prefix(maxPerVertical))
        save(all)
    }

    static func clear() {
        save([:])
    }

    // MARK: storage

    private static func load() -> [String: [String]] {
        if let cache { return cache }
        guard let url = AppGroupStore.bridgeDir?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            cache = [:]
            return [:]
        }
        cache = rows
        return rows
    }

    private static func save(_ rows: [String: [String]]) {
        cache = rows
        guard let url = AppGroupStore.bridgeDir?.appendingPathComponent(fileName),
              let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
