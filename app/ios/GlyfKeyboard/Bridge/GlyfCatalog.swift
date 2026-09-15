import Foundation

/// Client-side view of the shipped Glyf catalog (M2 slice). The DEFINITIONS
/// live server-side as Builder-format JSON (server/src/registry/glyfs/) —
/// per SPEC §13 defaults are never hard-coded behavior in Swift; the keyboard
/// only knows ids + display strings and sends the id to /glyf/run.
struct GlyfInfo {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
}

enum GlyfCatalog {
    static let all: [GlyfInfo] = [
        GlyfInfo(id: "rewrite.polite", title: "Make it polite",
                 subtitle: "Rewrite the draft with a courteous tone", icon: "hand.wave"),
        GlyfInfo(id: "rewrite.tighten", title: "Tighten",
                 subtitle: "Same message, half the words", icon: "scissors"),
        GlyfInfo(id: "rewrite.professional", title: "Professional",
                 subtitle: "Polish for a work audience", icon: "briefcase"),
        GlyfInfo(id: "glyf.translate", title: "Translate",
                 subtitle: "Translate the draft", icon: "translate"),
        GlyfInfo(id: "rewrite.emoji", title: "Emoji-fy",
                 subtitle: "Say it in emoji", icon: "face.smiling"),
        GlyfInfo(id: "glyf.proofread", title: "Proofread",
                 subtitle: "Fix grammar and spelling only", icon: "checkmark.seal"),
        // M5 (§6.13 default map)
        GlyfInfo(id: "rewrite.tone", title: "Tone shift",
                 subtitle: "Rewrite in the tone you pick", icon: "sparkles"),
        GlyfInfo(id: "social.emotion", title: "Emotion check",
                 subtitle: "How will this message land?", icon: "heart.text.square"),
        GlyfInfo(id: "social.xreply", title: "Super X reply",
                 subtitle: "A reply that earns the repost", icon: "arrowshape.turn.up.left"),
        GlyfInfo(id: "keyless.weather", title: "Weather",
                 subtitle: "Live conditions, no login", icon: "cloud.sun"),
        GlyfInfo(id: "keyless.quote", title: "Price check",
                 subtitle: "Live crypto quote, no login", icon: "chart.line.uptrend.xyaxis"),
        GlyfInfo(id: "keyless.define", title: "Define",
                 subtitle: "Dictionary, no login", icon: "character.book.closed"),
        GlyfInfo(id: "keyless.wiki", title: "Wiki lookup",
                 subtitle: "One-paragraph summary", icon: "books.vertical"),
        GlyfInfo(id: "keyless.stock", title: "Stock check",
                 subtitle: "Live quote, no login", icon: "chart.bar"),
    ]

    /// Shown as chips in the Glyf Bar, in this order.
    static let quickGlyfIds = ["rewrite.polite", "rewrite.tighten", "glyf.translate",
                               "rewrite.emoji", "glyf.proofread"]

    static func title(for id: String) -> String {
        switch id {
        case "surface:vault": return "Vault picker"
        case "surface:translate-hud": return "Translation HUD"
        case "surface:tones": return "Humanize"
        case "connector:mockcal": return "Calendar picker"
        default: break
        }
        if let known = all.first(where: { $0.id == id }) { return known.title }
        // Builder/hub glyfs: the app records a display name on bind (§6.8).
        if let custom = SettingsStore.current.customTitles?[id] { return custom }
        return id
    }

    // MARK: Remaining-runs cache (server is the source of truth — §6.16)

    private static let runsFile = "runs-remaining.json"

    static func cacheRunsRemaining(_ n: Int) {
        AppGroupStore.writeJSON(["remaining": n, "ts": Date().timeIntervalSince1970],
                                name: runsFile)
    }

    static func cachedRunsRemaining() -> Int? {
        guard let d = AppGroupStore.readJSON(name: runsFile),
              let n = d["remaining"] as? Int else { return nil }
        return n
    }

    static func runsRemainingText() -> String {
        if let n = cachedRunsRemaining() { return "\(n) runs left today" }
        return "Run a Glyf to see your quota"
    }
}
