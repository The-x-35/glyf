import AppIntents

/// Glyf in the Shortcuts app, Siri, Spotlight and the Action button: the
/// app's one AppShortcutsProvider (iOS allows one). Every phrase names the
/// app. Rewrite, Meet link, Run glyf and voice run without opening Glyf;
/// Open in Glyf opens it.
@available(iOS 18.0, *)
struct GlyfShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RewriteTextIntent(),
                    phrases: ["Rewrite with \(.applicationName)", "\(.applicationName) rewrite"],
                    shortTitle: "Rewrite Text",
                    systemImageName: "wand.and.stars")
        AppShortcut(intent: NewMeetLinkIntent(),
                    phrases: ["New \(.applicationName) Meet link", "Make a Meet link with \(.applicationName)"],
                    shortTitle: "New Meet Link",
                    systemImageName: "video.fill")
        AppShortcut(intent: RunGlyfIntent(),
                    phrases: ["Run a glyf in \(.applicationName)", "Run \(\.$glyf) in \(.applicationName)"],
                    shortTitle: "Run Glyf",
                    systemImageName: "sparkles")
        AppShortcut(intent: OpenGlyfIntent(),
                    phrases: ["Open \(.applicationName) wallet", "Open my \(\.$place) in \(.applicationName)"],
                    shortTitle: "Open Wallet",
                    systemImageName: "wallet.bifold.fill")
        AppShortcut(intent: StartGlyfVoiceIntent(),
                    phrases: ["Start \(.applicationName) voice", "Turn on \(.applicationName) voice"],
                    shortTitle: "Start Glyf Voice",
                    systemImageName: "mic.fill")
    }
}
