import UIKit

/// §6.1 clipboard manager: last 20 items, pinnable, 1h expiry unless pinned,
/// App Group storage, refuses secret-shaped content (SecretScanner).
struct ClipItem: Codable, Equatable {
    var text: String
    var ts: Date
    var pinned: Bool
}

enum ClipboardStore {
    static let fileName = "clipboard.json"
    static let maxItems = 20
    static let expiry: TimeInterval = 3600

    static func load(now: Date = Date()) -> [ClipItem] {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)),
              let items = try? JSONDecoder().decode([ClipItem].self, from: data)
        else { return [] }
        return prune(items, now: now)
    }

    static func save(_ items: [ClipItem]) {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONEncoder().encode(Array(items.prefix(maxItems)))
        else { return }
        try? data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
    }

    /// Pure so it's unit-testable: drops expired unpinned items, caps count.
    static func prune(_ items: [ClipItem], now: Date) -> [ClipItem] {
        Array(items.filter { $0.pinned || now.timeIntervalSince($0.ts) < expiry }
            .prefix(maxItems))
    }

    /// Pure: returns the new list, or nil when the text is refused/duplicate.
    static func inserting(_ text: String, into items: [ClipItem], now: Date) -> [ClipItem]? {
        guard SecretScanner.scan(text) == .clean else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4000 else { return nil }
        if items.first?.text == trimmed { return nil }
        var next = items.filter { $0.text != trimmed || $0.pinned }
        next.insert(ClipItem(text: trimmed, ts: now, pinned: false), at: 0)
        // Never evict pinned items; trim oldest unpinned beyond the cap.
        while next.count > maxItems, let idx = next.lastIndex(where: { !$0.pinned }) {
            next.remove(at: idx)
        }
        return Array(next.prefix(maxItems))
    }

    /// Set by the VC each appearance; static because screen builders are static.
    static var fullAccessHint = false

    /// `changeCount` never triggers Apple's paste prompt — reading `.string`
    /// does. So the keyboard NEVER reads on appearance; it only probes, and
    /// actually reads at user-intent moments (clipboard screen, bar input),
    /// where a one-time system prompt is legitimate.
    static func pasteboardHasNewContent() -> Bool {
        let cc = UIPasteboard.general.changeCount
        let last = (AppGroupStore.readJSON(name: "clip-cc.json")?["cc"] as? Int) ?? -1
        return cc != last
    }

    private static func markPasteboardSeen() {
        AppGroupStore.writeJSON(["cc": UIPasteboard.general.changeCount],
                                name: "clip-cc.json")
    }

    /// User-intent read (may surface the iOS paste banner once).
    /// Returns true when something new landed in history.
    @discardableResult
    static func captureNow() -> Bool {
        guard fullAccessHint else { return false }
        guard pasteboardHasNewContent() else { return false }
        // Only a read that actually returned something counts as "seen": if
        // iOS refused (or the person said no), the copy stays on offer.
        guard UIPasteboard.general.hasStrings,
              let text = UIPasteboard.general.string else { return false }
        markPasteboardSeen()
        let items = load()
        guard let next = inserting(text, into: items, now: Date()) else { return false }
        save(next)
        return true
    }

    static func togglePin(_ text: String) {
        var items = load()
        if let i = items.firstIndex(where: { $0.text == text }) {
            items[i].pinned.toggle()
            save(items)
        }
    }

    static func remove(_ text: String) {
        save(load().filter { $0.text != text })
    }

    static func clearUnpinned() {
        save(load().filter(\.pinned))
    }
}
