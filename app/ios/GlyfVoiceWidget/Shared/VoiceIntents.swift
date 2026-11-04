import AppIntents
import Foundation

// Start Glyf Voice without opening Glyf: from Control Center (the
// GlyfVoiceControl button), the Action button, Siri or Shortcuts. iOS 18's
// AudioRecordingIntent is the one way an app may start the microphone from
// the background; iOS asks for a Live Activity for as long as it records
// (GlyfVoiceAttributes, started by VoiceActivityHost).
//
// Compiled into the app AND the GlyfVoiceWidget extension (the control and
// the Live Activity's button name these types). LiveActivityIntent makes
// iOS run perform() in the app's process (launched in the background if it
// isn't running), which is where VoiceHost and the microphone live; the
// extension's copy (GLYF_WIDGET) does nothing.
//
// The keyboard can't run these: an intent's perform() runs in the process
// that calls it, and in the keyboard that has no microphone; the only
// public way to ask the system to run one is the Shortcuts app's URL, which
// opens Shortcuts in front, a worse trip than opening Glyf.

@available(iOS 18.0, *)
struct StartGlyfVoiceIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Glyf Voice"
    static let description = IntentDescription("Voice typing ready in the Glyf keyboard.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !GLYF_WIDGET
        guard await VoiceHost.shared.startFromIntent() else {
            throw GlyfVoiceIntentError.needsGlyf
        }
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
struct StopGlyfVoiceIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn Off Glyf Voice"

    init() {}

    func perform() async throws -> some IntentResult {
        #if !GLYF_WIDGET
        await MainActor.run { VoiceHost.shared.end() }
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
enum GlyfVoiceIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The microphone or Speech Recognition was never allowed: only Glyf in
    /// front can ask (the keyboard's Voice does, once).
    case needsGlyf

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .needsGlyf: return "Open Glyf to allow the microphone"
        }
    }
}

#if !GLYF_WIDGET
/// "Start Glyf voice" for Siri, and the Action button's and Shortcuts'
/// list. Only the app may declare these.
@available(iOS 18.0, *)
struct GlyfVoiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartGlyfVoiceIntent(),
                    phrases: ["Start \(.applicationName) voice", "Turn on \(.applicationName) voice"],
                    shortTitle: "Start Glyf Voice",
                    systemImageName: "mic.fill")
    }
}
#endif
