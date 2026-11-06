import Foundation

/// User-facing keyboard settings, persisted in the App Group so both the
/// extension and the Flutter app read/write the same state (§6.2/§6.3).
struct GlyfSettings: Codable, Equatable {
    /// Bumped when defaults change; load() migrates older files additively.
    /// Optional so files written before the field existed still decode.
    var schemaVersion: Int? = 9
    var haptics: Bool = true
    var keyClicks: Bool = true
    var numberRow: Bool = false
    /// The letters' layout (LetterLayout): "qwerty", "qwertz", "azerty" or
    /// "colemak"; nil, or an id this build doesn't know, is QWERTY.
    var keyLayout: String? = nil
    /// A comma key left of the space bar, and a period key right of it, on
    /// the letters of a text field (Gboard's "Comma key" and "Period key").
    /// Nil reads as off: today's bottom row.
    var commaKey: Bool? = nil
    var periodKey: Bool? = nil
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
    /// §6.16 plans: "free" | "plus" ($2) | "max" ($5).
    var plan: String? = "free"
    /// The currency the strip converts money into ("INR", "USD", …), or
    /// "auto" to follow where the phone is. The person picks it in the app.
    var moneyCurrency: String? = "auto"
    /// Whether a correction is applied on the space, or only offered in the
    /// strip. Off is the "don't change my words" setting: iOS gives no
    /// third-party keyboard the underline Apple draws, so the honest version
    /// is to leave the word alone and let a tap take the fix.
    var autocorrectApply: Bool? = true
    /// Glide typing: a finger sliding over the letters types the word
    /// (Arpit, 2026-10-07). Off leaves every letter a tap.
    var glideTyping: Bool? = true
    /// The wallet is a feature people turn on in the app (2026-10-14): off,
    /// no Pay tool, no Send or Buy chips, no Buy beside a price.
    var walletEnabled: Bool? = nil
    /// Keyboard appearance: "auto" follows the host app (Apple behavior);
    /// "light"/"dark" force it.
    var appearance: String? = "auto"
    /// Key style: "site" (the tryglyf.com look, default) | "glass"
    /// (liquid-glass) | "classic" | "glow".
    var keyTheme: String? = "site"
    /// A keyboard theme's id from shared/themes/themes.json ("typewriter",
    /// "baker", …), picked in the app's Look grid; "" or missing is today's
    /// look, and so is an id this build doesn't know (docs/THEMES.md).
    var skin: String? = ""
    /// Whether a theme with a sound pack plays it (nil reads as on); off,
    /// keys click as they do today.
    var skinSound: Bool? = true
    /// Let a Glyf run see the shareable half of your vault (name, email,
    /// phone, address, UPI, links), so "write my address" and form filling
    /// work. Off means runs never carry your details.
    var aiUsesVault: Bool? = true
    /// AI suggestions as you type: on a pause, the sentence before the cursor
    /// goes to the server so the strip can offer an action. Off until the
    /// person agrees on the app's "What Glyf sends" screen (Google Play's
    /// prominent disclosure); nil reads as off.
    var aiSuggest: Bool? = nil
    /// When the person answered "What Glyf sends" (ISO 8601), nil until they
    /// have. Until then no AI request carries saved details either.
    var aiConsent: String? = nil
    /// Keep what you copy in the keyboard's clipboard history.
    var clipboardHistory: Bool? = true
    /// Take every copy into the clipboard, rather than waiting to be handed
    /// one by the Paste button.
    ///
    /// On by default, because a clipboard that misses what you copied reads
    /// as broken. There is no quiet way to do it: any read of the pasteboard
    /// raises "Allow Paste?" once per copy until the person sets Settings →
    /// Glyf → Paste from Other Apps → Allow, and that setting is theirs to
    /// make — no app can write it. So the keyboard asks for each copy, once,
    /// and the clipboard says where the switch is that stops the asking.
    var clipboardCaptureAll: Bool? = true
    /// Recent screenshots in the clipboard, beside what you copied.
    ///
    /// This is the WISH, not the permission: on by default, and the photo
    /// library is a separate yes that only the app can ask for. When the wish
    /// is on and the library is not, the clipboard says so rather than
    /// showing an empty space — which is what it did when the two defaults
    /// disagreed, the app reading false and the keyboard true.
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
    /// The tour's chat and step ("mom:0"); the keyboard's coach reads what
    /// is open and points at the next thing to tap (TourCoach).
    var tourStep: String? = nil
    /// When the tour copied something from the chat (ms since 1970).
    var tourCopiedAt: Double? = nil
    /// The language besides the phone's own that this person types in, as
    /// translate last detected it. Where English drafts get translated to.
    var translateOther: String? = nil
    /// Voice typing's style pill, as last picked (VoiceLink.Style raw value;
    /// nil = As spoken, nothing sent).
    var voiceStyle: String? = nil
    /// false turns off going back to the app the keyboard was in after
    /// Glyf opened for voice (the keyboard stops reading the host app's id,
    /// which uses private API: HostAppID). nil = on.
    var voiceReturn: Bool? = nil
    /// The person's Cal.com or Calendly booking page, set in the app
    /// (Connected tools → Booking link). The calendar's Book a time uses it.
    var bookingLink: String? = nil
    /// The Phantom wallet connected in the app (its public address, never a
    /// key). An address that is your own is one you are sharing, so the
    /// strip offers no Send for it.
    var walletAddress: String? = nil
    /// The Ethereum address that signs the keyboard's trades, the same on
    /// every EVM chain: the Glyf wallet's (its key never leaves the app's
    /// Keychain) or a connected MetaMask's or Phantom's (lib/evm/evm_signer.dart).
    var evmAddress: String? = nil
    /// Which one: "glyf" (or nil), "metamask", "phantom".
    var evmSigner: String? = nil
    /// Private AI: the server answers this phone's AI calls with 0G's
    /// Private Computer (models in TEEs). Unset is on.
    var privateAI: Bool? = nil
    /// How the last payment went, written by the app when Phantom answers
    /// ({"title","detail","at"}); the keyboard says it once and clears it.
    var walletOutcome: String? = nil
    /// A trade shared from the app (lib/evm/trade_share.dart), as
    /// {"text","at"}: the strip offers Share trade once for 10 minutes,
    /// and a tap types the text and clears it.
    var tradeShare: String? = nil
    /// Where temp mail asks: unset is mail.tm itself. Scenarios name the
    /// stand-in here (qa/fake-mailtm.mjs).
    var tempMailBase: String? = nil
    /// Where Book a time asks: unset is Cal.com's API itself. Scenarios name
    /// the stand-in here (qa/fake-scheduling.mjs, its /v2).
    var calcomBase: String? = nil

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
        // The session token rides on every call, so a shipped build talks to
        // production only, whatever a saved setting says.
        return productionBackend
        #endif
    }

    enum Toolbar {
        /// The strip: the tools the keys themselves cannot reach. Emoji is
        /// not among them — the keyboard has an emoji key in its bottom row,
        /// where iOS puts it. Users can add anything back (Toolbar screen).
        /// Arpit, 2026-10-06: "from top bar remove mic and translate and
        /// instead add calendar and temp mail for default".
        static let defaultOrder = ["search", "clipboard", "vault", "calendar", "tempmail"]

        /// Tools folded into another (user, 2026-09-29): the keys have an
        /// emoji key, so the menu offers GIFs; Keys said what My glyfs says;
        /// Shorthand lives in the vault. Android's ToolIcon.canonical twin.
        static let retired = ["emoji": "gifs", "keys": "glyfs", "shorthand": "vault"]

        /// The tool a saved id stands for now.
        static func canonical(_ id: String) -> String { retired[id] ?? id }
    }

    /// The tools on the strip, in its order. Hidden is read as saved before
    /// the rename: a hidden Shorthand must not hide the Vault it became,
    /// while a pinned Emoji becomes a pinned GIFs.
    var stripTools: [String] {
        var out: [String] = []
        for id in toolbarOrder where !toolbarHidden.contains(id) {
            let tool = Toolbar.canonical(id)
            if !out.contains(tool) { out.append(tool) }
        }
        return out
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
            // A fresh install gets two holds (V and C); someone upgrading from
            // the canned glyfs keeps the translate HUD on T, which is where
            // they have been reaching for it. Android's v6 does the same.
            if !s.bindings.values.contains("surface:translate-hud"),
               s.bindings["t"] == nil {
                s.bindings["t"] = "surface:translate-hud"
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
        // v7 → v8: the clipboard fills itself. These two shipped off, which
        // read as a clipboard that loses things, so they are on now — but a
        // file written before this decodes them as nil, not as the new
        // default, so say it here. A stored false is a real answer and is
        // left alone; only "never asked" becomes yes.
        if (s.schemaVersion ?? 1) < 8 {
            if s.clipboardCaptureAll == nil { s.clipboardCaptureAll = true }
            if s.clipboardScreenshots == nil { s.clipboardScreenshots = true }
            s.schemaVersion = 8
        }
        // v8 → v9: every saved strip starts over once from the new default
        // (Calendar and Temp mail where Voice and Translate were).
        if (s.schemaVersion ?? 1) < 9 {
            s.toolbarOrder = GlyfSettings.Toolbar.defaultOrder
            s.toolbarHidden = []
            s.schemaVersion = 9
        }
        // Voice (id "dictation") is back on iOS since 2026-11-04: the app
        // listens for the keyboard (VoiceLink), so it lives in the g menu
        // like Android's, and can be dragged onto the strip.
        // Emoji, Keys and Shorthand left the g menu for the tools that took
        // them in. A saved strip and order move with them, whatever version
        // wrote the file, so nothing is lost and nothing shows twice.
        let retired = GlyfSettings.Toolbar.retired
        if s.toolbarOrder.contains(where: { retired[$0] != nil })
            || s.toolbarHidden.contains(where: { retired[$0] != nil }) {
            let shown = s.stripTools
            var order: [String] = []
            for id in s.toolbarOrder.map(GlyfSettings.Toolbar.canonical) where !order.contains(id) {
                order.append(id)
            }
            s.toolbarOrder = order
            s.toolbarHidden = order.filter { !shown.contains($0) }
        }
        if let saved = s.menuOrder, saved.contains(where: { retired[$0] != nil }) {
            var order: [String] = []
            for id in saved.map(GlyfSettings.Toolbar.canonical) where !order.contains(id) {
                order.append(id)
            }
            s.menuOrder = order
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
        // Our own write is not "the app changed it": remember the stamp so the
        // next reloadIfChanged() does not throw the cache away for nothing.
        loadedStamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
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
        // The app and the keyboard both write this file, and the app writes
        // it from two places (Dart's raw write and the native store). A copy
        // cached before the other side's write would put every old value
        // back, so always start from what is on disk.
        reloadIfChanged()
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
        // Whoever noticed (the tour watch, a keystroke), everyone who shows
        // a setting hears about it once.
        NotificationCenter.default.post(name: changedNote, object: nil)
        return true
    }
}
