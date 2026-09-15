import Foundation

/// User-facing keyboard settings, persisted in the App Group so both the
/// extension and the Flutter app read/write the same state (§6.2/§6.3).
struct GlyfSettings: Codable, Equatable {
    /// Bumped when defaults change; load() migrates older files additively.
    /// Optional so files written before the field existed still decode.
    var schemaVersion: Int? = 3
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
    /// Key style: "glass" (liquid-glass, default) | "classic" | "glow".
    var keyTheme: String? = "glass"
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
    static let defaultBindings: [String: String] = [
        "t": "surface:translate-hud",   // §6.13 T — Translation HUD ★
        "s": "surface:vault",           // §6.13 S — Share My Info
        "p": "glyf.proofread",          // §6.13 P — Proofread
    ]
    /// Backend base URL (dev). Set from the app's debug screen.
    /// Dev builds talk to the Mac; shipped builds talk to tryglyf.com.
    /// GlyfSettings.productionBackend is the single source of truth.
    var backendURL: String = GlyfSettings.defaultBackendURL
    var deviceId: String = UUID().uuidString.lowercased()
    /// Params passed to glyf runs (M2: translate target).
    var translateTarget: String = "English"

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
        static let defaultOrder = ["search", "clipboard", "vault", "dictation", "emoji", "translate", "settings"]
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
        try? data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        NotificationCenter.default.post(name: changedNote, object: nil)
    }

    static func update(_ mutate: (inout GlyfSettings) -> Void) {
        var s = current
        mutate(&s)
        save(s)
    }

    /// Re-read from disk (the app may have written while we were dismissed).
    static func invalidate() { cached = nil }
}
