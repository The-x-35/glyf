import UIKit

/// §6.1 clipboard manager: last 20 items, pinnable, 48h expiry unless pinned,
/// App Group storage, refuses secret-shaped content (SecretScanner).
struct ClipItem: Codable, Equatable {
    var text: String
    var ts: Date
    var pinned: Bool
}

enum ClipboardStore {
    static let fileName = "clipboard.json"
    static let maxItems = 20
    /// Unpinned copies keep for two days; pinning is what makes one permanent
    /// (`prune` never drops a pinned item, whatever its age).
    static let expiry: TimeInterval = 48 * 3600

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

    /// Glyf never reads the clipboard on its own.
    ///
    /// `changeCount` and `hasStrings` are probes — they tell us THAT there is
    /// something new without telling us what, and iOS asks nothing for them.
    /// Reading `.string` is what raises "Allow Paste?", and iOS raises it
    /// again for every new copy, which is what made the keyboard feel like it
    /// was constantly asking permission. So the probe decides whether to
    /// OFFER a copy, and the only thing that actually takes it is the system
    /// paste button the person taps (`UIPasteControl` → `paste(itemProviders:)`
    /// on the view controller), where the tap itself is the permission.
    static func pasteboardHasNewContent() -> Bool {
        let cc = UIPasteboard.general.changeCount
        let last = (AppGroupStore.readJSON(name: "clip-cc.json")?["cc"] as? Int) ?? -1
        return cc != last
    }

    private static func markPasteboardSeen() {
        AppGroupStore.writeJSON(["cc": UIPasteboard.general.changeCount],
                                name: "clip-cc.json")
    }

    /// The keyboard just put something there itself (a GIF to paste): that
    /// is not a copy of the person's to offer back or keep.
    static func ignoreNextChange() { markPasteboardSeen() }

    /// Puts a new copy straight into history, asking nothing.
    ///
    /// `detectValues` hands back the ACTUAL text for what iOS can recognise
    /// — a link, something search-shaped, a number — and reaches copies that
    /// a plain `.string` read would only get with Full Access.
    ///
    /// It is NOT silent. Handing over the value is a read, and iOS raises
    /// "Allow Paste?" for it exactly as it does for `.string`; only
    /// `detectPatterns`, which answers with types and no values, stays quiet.
    /// So this sits behind the same switch as the full read.
    static func captureDetected(_ done: @escaping (Bool) -> Void) {
        guard !reading, fullAccessHint, pasteboardHasNewContent(),
              SettingsStore.current.clipboardHistory != false
        else { return done(false) }
        // Only the three iOS 14 patterns are plain `DetectionPattern`s; the
        // later ones (email, phone, address…) are refined onto a different
        // Swift type and are not reachable through this call.
        let patterns: Set<UIPasteboard.DetectionPattern> = [
            .probableWebURL, .probableWebSearch, .number,
        ]
        UIPasteboard.general.detectValues(for: patterns) { result in
            let text: String? = {
                guard case .success(let values) = result else { return nil }
                return firstText(in: values)
            }()
            DispatchQueue.main.async {
                guard let text, !text.isEmpty else { return done(false) }
                markPasteboardSeen()
                guard let next = inserting(text, into: load(), now: Date()) else {
                    return done(false)
                }
                save(next)
                done(true)
            }
        }
    }

    /// Takes a new copy into history the quietest way available: everything,
    /// when that was turned on, and otherwise whatever iOS will name without
    /// asking. Both the panel and the strip chip go through here, so a copy
    /// shows its words in the same places for the same reasons.
    static func captureNewCopy(_ done: @escaping (Bool) -> Void) {
        // Both routes are reads, so both sit behind the same switch. Left
        // off, nothing here touches the clipboard and iOS never asks; the
        // Paste button is how a copy gets in.
        guard SettingsStore.current.clipboardCaptureAll == true else {
            return done(false)
        }
        captureEverything { took, asked in
            if took { done(true) }
            // Asked and refused (or nothing there): "Don't Allow Paste"
            // means that copy stays out, however else it could be read.
            else if asked { done(false) }
            else { captureDetected(done) }
        }
    }

    /// Everything, including prose — the read iOS may ask about.
    ///
    /// Only runs when "Capture everything you copy" is on. Left on Ask, iOS
    /// raises "Allow Paste?" once per copy; set to Allow (Settings → Glyf →
    /// Paste from Other Apps) it never asks again and every copy lands here
    /// by itself. That choice belongs to the person, not to us, which is why
    /// this is opt-in and `captureDetected` is what runs by default.
    /// `done(took, asked)`: whether the copy was taken, and whether iOS was
    /// asked for it at all.
    static func captureEverything(_ done: @escaping (_ took: Bool, _ asked: Bool) -> Void) {
        guard !reading, fullAccessHint, pasteboardHasNewContent(),
              SettingsStore.current.clipboardHistory != false,
              SettingsStore.current.clipboardCaptureAll == true,
              UIPasteboard.general.hasStrings
        else { return done(false, false) }
        // Reading `.string` can raise "Allow Paste?", and the read waits for
        // the answer. On the main thread that froze the whole keyboard (no
        // keys, no strip) until the person answered; off it, the keyboard
        // keeps working while iOS asks.
        let changeCount = UIPasteboard.general.changeCount
        reading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let text = UIPasteboard.general.string
            DispatchQueue.main.async {
                reading = false
                // Seen either way: a refused read is not asked again for the
                // same copy. The count is read again afterwards too: while
                // iOS asks, the simulator re-syncs the Mac's clipboard and
                // bumps it, which made the refused copy look new.
                let seen = max(changeCount, UIPasteboard.general.changeCount)
                AppGroupStore.writeJSON(["cc": seen], name: "clip-cc.json")
                guard let text, !text.isEmpty,
                      let next = inserting(text, into: load(), now: Date()) else {
                    return done(false, true)
                }
                save(next)
                done(true, true)
            }
        }
    }

    /// A read is waiting on iOS (and maybe on the person): no second one.
    /// Main thread only.
    private static var reading = false

    /// A link first: it is what people copy most and what iOS is surest of.
    private static func firstText(in values: [UIPasteboard.DetectionPattern: Any]) -> String? {
        if let url = values[.probableWebURL] as? URL { return url.absoluteString }
        if let url = values[.probableWebURL] as? String, !url.isEmpty { return url }
        if let search = values[.probableWebSearch] as? String, !search.isEmpty {
            return search
        }
        if let number = values[.number] as? NSNumber { return number.stringValue }
        if let number = values[.number] as? String, !number.isEmpty { return number }
        return nil
    }

    /// Whether a copy IS a link — the rule behind the clipboard's Link pill.
    ///
    /// `NSDataDetector` is what iOS itself uses to find links in text, so a
    /// bare domain counts exactly as it does everywhere else on the phone:
    /// tryglyf.com is a link without anyone typing https:// in front of it.
    ///
    /// The match has to cover the WHOLE clip. A sentence that happens to
    /// mention a link is still a sentence, and Text and Link have to stay
    /// exclusive or the pills stop adding up to All.
    ///
    /// An email address is left to Text: `mailto:` is a link to the detector,
    /// but an address is something you paste into a To: field, not something
    /// you follow.
    static func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = linkDetector?.firstMatch(in: trimmed, options: [], range: range),
              match.range == range,
              let url = match.url
        else { return false }
        return url.scheme?.lowercased() != "mailto"
    }

    /// Built once: a detector is expensive to make and this runs per card.
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

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
