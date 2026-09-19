import Foundation

/// User-facing keyboard settings, persisted in the App Group so both the
/// extension and the Flutter app read/write the same state (§6.2/§6.3).
struct GlyfSettings: Codable, Equatable {
    /// Bumped when defaults change; load() migrates older files additively.
    /// Optional so files written before the field existed still decode.
    var schemaVersion: Int? = 7
    var haptics: Bool = true
    var keyClicks: Bool = true
    var numberRow: Bool = false
    var autocorrect: Bool = true
    var autocapitalize: Bool = true
    var periodShortcut: Bool = true
    var candidates: Bool = true
    /// Vocabulary packs switched on in the app (ids from assets/vocab/packs.json
    /// or custom packs in vocab-custom.json). Nil until the user picks: phones
    /// set to India start with Hinglish (VocabDefaults).
    var vocabPacks: [String]? = nil
    /// Learn words from typing (on device). Off = nothing new is learned.
    var vocabLearning: Bool? = true
    /// off | left | right
    var oneHanded: String = "off"
    /// Toolbar item ids in display order; missing ids are appended on load.
    var toolbarOrder: [String] = Toolbar.defaultOrder
    /// The g menu's tile order, as the person arranged it (nil = default).
    var menuOrder: [String]? = nil
    var toolbarHidden: [String] = []
    /// Key letter (lowercase) → glyf id, "surface:<name>" for in-keyboard
    /// surfaces, or "connector:<id>" for ConnectorSurface pickers (§6.12).
    /// The shipped default map is §6.13; users rebind anything.
    var bindings: [String: String] = GlyfSettings.defaultBindings
    /// Display names for custom/hub glyfs (the app writes these on bind).
    var customTitles: [String: String]? = [:]
    /// §6.13 T — persistent Translation HUD strip, toggled by holding T.
    var translationHUD: Bool? = false
    /// §6.16 — set by the app after a (locally validated) purchase.
    /// Legacy boolean; superseded by `plan` (kept for old files).
    var proUnlocked: Bool? = false
    /// §6.16 plans: "free" | "plus" ($4.99) | "max" ($19.99).
    var plan: String? = "free"
    /// Keyboard appearance: "auto" follows the host app (Apple behavior);
    /// "light"/"dark" force it.
    var appearance: String? = "auto"
    /// Key style: "site" (the tryglyf.com look, default) | "glass"
    /// (liquid-glass) | "classic" | "glow".
    var keyTheme: String? = "site"
    /// Let a Glyf run see the shareable half of your vault (name, email,
    /// phone, address, UPI, links), so "write my address" and form filling
    /// work. Off means runs never carry your details.
    var aiUsesVault: Bool? = true
    /// Keep what you copy in the keyboard's clipboard history. iOS may ask to
    /// allow the paste the first time after a copy from another app.
    var clipboardHistory: Bool? = true
    /// Screenshots from the last hour in the clipboard (Gboard's setting).
    /// The app asks for Photos access when it is turned on.
    var clipboardScreenshots: Bool? = true
    /// "" | "color:#RRGGBB" | "grad:<id>" — Gboard-style painted backdrop.
    var themeBg: String? = ""
    /// Gboard "borders around keys".
    var keyBorders: Bool? = false
    /// 0…0.6 backdrop dim for painted themes.
    var themeBrightness: Double? = 0

    /// What a tapped search result puts in the message.
    /// "titleAndLink" (default, Gboard's behaviour) pastes the link, then the
    /// emoji-prefixed title; "linkOnly" pastes the bare URL.
    var pasteStyle: String? = "titleAndLink"
    /// Coarse location cached by the app after the user grants permission in
    /// onboarding — the keyboard cannot ask for it itself. Used only to make
    /// "near me" mean something; nil keeps place search text-only.
    var lastLat: Double?
    var lastLon: Double?
    /// Two-letter region, for locale-aware web and video results.
    var region: String?

    /// Deliberately SMALL (design decision 2026-09-12: "don't preset a lot").
    /// Three anchors ship bound; onboarding personas and per-key
    /// recommendations fill the rest by choice, never by default.
    /// Two holds, and that is all: V shares your details, C opens the
    /// calendar. Every other letter is the person's to bind; holding space
    /// already does with the model what the canned glyfs used to.
    static let defaultBindings: [String: String] = [
        "v": "surface:vault",
        "c": "connector:calendar",
    ]
    /// Backend base URL (dev). Set from the app's debug screen.
    /// Dev builds talk to the Mac; shipped builds talk to tryglyf.com.
    /// GlyfSettings.productionBackend is the single source of truth.
    var backendURL: String = GlyfSettings.defaultBackendURL
    var deviceId: String = UUID().uuidString.lowercased()
    /// Params passed to glyf runs (M2: translate target).
    var translateTarget: String = "English"
    /// Set by the app's guided tour while it waits for one tap: "chip",
    /// "space", "emojikey", "g" or a letter. The keyboard rings that control.
    var tourHint: String? = nil
    /// When the tour set the hint (ms since 1970). A tour that was closed by
    /// force leaves its hint behind; an old one is ignored.
    var tourHintAt: Double? = nil
    /// The tour's chat and step ("mumma:0"); the keyboard's coach reads what
    /// is open and points at the next thing to tap (TourCoach).
    var tourStep: String? = nil
    /// When the tour copied something from the chat (ms since 1970).
    var tourCopiedAt: Double? = nil
    /// The language besides the phone's own that this person types in, as
    /// translate last detected it. Where English drafts get translated to.
    var translateOther: String? = nil

    /// The deployed API. Changing the domain? This is the only place.
    static let productionBackend = "https://api.tryglyf.com"

    static var defaultBackendURL: String {
        #if DEBUG
        return "http://127.0.0.1:8787"
        #else
        return productionBackend
        #endif
    }

    /// Keeps a persisted URL consistent with the build that reads it.
    ///
    /// A shipped build must never be left pointing at a laptop: old installs
    /// carry a persisted dev URL, so upgrade it in place. The reverse bites
    /// just as hard during development — a settings.json written by a release
    /// install sends the dev keyboard at production (or, before launch, at a
    /// domain that does not resolve), which surfaces as an opaque TLS error.
    static func productionized(_ url: String) -> String {
        #if DEBUG
        return url == productionBackend ? defaultBackendURL : url
        #else
        let dev = ["127.0.0.1", "localhost", "10.0.2.2", "0.0.0.0"]
        return dev.contains(where: url.contains) ? productionBackend : url
        #endif
    }

    enum Toolbar {
        /// The strip: the tools the keys themselves cannot reach. Emoji is
        /// not among them — the keyboard has an emoji key in its bottom row,
        /// where iOS puts it. Users can add anything back (Toolbar screen).
        static let defaultOrder = ["search", "clipboard", "vault", "dictation", "translate"]
    }
}

enum SettingsStore {
    static let fileName = "settings.json"
    static let changedNote = Notification.Name("glyf.settings.changed")

    private static var cached: GlyfSettings?

    static var current: GlyfSettings {
        if let cached { return cached }
        let loaded = load()
        cached = loaded
        return loaded
    }

    static func load() -> GlyfSettings {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)),
              let s = try? JSONDecoder().decode(GlyfSettings.self, from: data)
        else { return GlyfSettings() }
        return migrated(s)
    }

    /// Pure + testable: every additive schema migration, oldest first.
    static func migrated(_ old: GlyfSettings) -> GlyfSettings {
        var s = old
        s.backendURL = GlyfSettings.productionized(s.backendURL)
        // Additive migration: new toolbar items appear even for old files.
        // Search leads (Gboard parity); anything else joins at the end.
        if !s.toolbarOrder.contains("search") {
            s.toolbarOrder.insert("search", at: 0)
        }
        for id in GlyfSettings.Toolbar.defaultOrder where !s.toolbarOrder.contains(id) {
            s.toolbarOrder.append(id)
        }
        // v1 → v2: the S vault binding shipped in M4.
        if (s.schemaVersion ?? 1) < 2 {
            if s.bindings["s"] == nil { s.bindings["s"] = "surface:vault" }
            s.schemaVersion = 2
        }
        // v2 → v3 (M5): the §6.13 default map — only keys the user hasn't
        // claimed, and T's one-shot translate upgrades to the HUD.
        if (s.schemaVersion ?? 1) < 3 {
            if s.bindings["t"] == "glyf.translate" {
                s.bindings["t"] = "surface:translate-hud"
            }
            for (key, glyfId) in GlyfSettings.defaultBindings
            where s.bindings[key] == nil {
                s.bindings[key] = glyfId
            }
            s.schemaVersion = 3
        }
        // v3 → v4: the keyboard wears the website look. Anyone still on the
        // old default moves over; a deliberate pick (classic, glow) stays.
        if (s.schemaVersion ?? 1) < 4 {
            if (s.keyTheme ?? "glass") == "glass" { s.keyTheme = "site" }
            // The gear moved into the g menu, matching the website strip.
            s.toolbarOrder.removeAll { $0 == "settings" }
            s.schemaVersion = 4
        }
        // v4 → v5: emoji leaves the strip; the bottom row already has it.
        if (s.schemaVersion ?? 1) < 5 {
            if !(s.toolbarHidden.contains("emoji")) {
                s.toolbarOrder.removeAll { $0 == "emoji" }
            }
            s.schemaVersion = 5
        }
        // v5 → v6: the canned glyfs go. Hold space does all of it better,
        // so only S, T and the glyfs people built themselves stay on keys.
        if (s.schemaVersion ?? 1) < 6 {
            let built = s.customTitles ?? [:]
            s.bindings = s.bindings.filter { _, target in
                target == "surface:vault" || target == "surface:translate-hud"
                    || built[target] != nil
            }
            for (key, target) in GlyfSettings.defaultBindings where s.bindings[key] == nil {
                s.bindings[key] = target
            }
            s.schemaVersion = 6
        }
        // v6 → v7: the vault moves to V, the letter it is named for.
        if (s.schemaVersion ?? 1) < 7 {
            if s.bindings["s"] == "surface:vault",
               s.bindings["v"] == nil || s.bindings["v"] == "surface:vault" {
                s.bindings["s"] = nil
                s.bindings["v"] = "surface:vault"
            }
            if !s.bindings.values.contains("surface:vault"), s.bindings["v"] == nil {
                s.bindings["v"] = "surface:vault"
            }
            s.schemaVersion = 7
        }
        if s.customTitles == nil { s.customTitles = [:] }
        // Legacy proUnlocked → the plus plan.
        if s.plan == nil {
            s.plan = (s.proUnlocked ?? false) ? "plus" : "free"
        }
        return s
    }

    static func save(_ s: GlyfSettings) {
        cached = s
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONEncoder().encode(s) else { return }
        let url = dir.appendingPathComponent(fileName)
        try? merged(data, over: try? Data(contentsOf: url)).write(to: url, options: .atomic)
        NotificationCenter.default.post(name: changedNote, object: nil)
    }

    /// The file also holds what only the app keeps there (the signed-in
    /// account, its sign-in ids): a keyboard write replaces its own fields and
    /// leaves those alone. A field of ours that is now nil is removed.
    static func merged(_ ours: Data, over existing: Data?) -> Data {
        guard let existing,
              var file = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any],
              let mine = (try? JSONSerialization.jsonObject(with: ours)) as? [String: Any]
        else { return ours }
        let known = Set(Mirror(reflecting: GlyfSettings()).children.compactMap(\.label))
        for key in known where mine[key] == nil { file.removeValue(forKey: key) }
        for (key, value) in mine { file[key] = value }
        return (try? JSONSerialization.data(withJSONObject: file)) ?? ours
    }

    static func update(_ mutate: (inout GlyfSettings) -> Void) {
        var s = current
        mutate(&s)
        save(s)
    }

    /// Re-read from disk (the app may have written while we were dismissed).
    static func invalidate() { cached = nil }

    private static var loadedStamp: Date?

    /// Re-reads the file when the app changed it since the last read: a stat,
    /// not a decode, so it is cheap enough to ask on every text change.
    @discardableResult
    static func reloadIfChanged() -> Bool {
        guard let dir = AppGroupStore.bridgeDir else { return false }
        let path = dir.appendingPathComponent(fileName).path
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        guard stamp != loadedStamp else { return false }
        loadedStamp = stamp
        cached = nil
        return true
    }
}
