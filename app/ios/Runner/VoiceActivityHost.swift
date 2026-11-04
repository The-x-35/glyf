import ActivityKit
import os.log

/// Starts and ends the Live Activity of a session begun by Start Glyf Voice
/// (VoiceIntents.swift). iOS stops an AudioRecordingIntent's recording if
/// no Live Activity runs while it records. Sessions started from the app or
/// the keyboard's link show none (the orange dot is the indicator there).
///
/// Note: iOS ends any Live Activity after 8 hours. Whether the recording of
/// an intent-started session survives that is not known yet (needs a phone).
final class VoiceActivityHost {
    static let shared = VoiceActivityHost()
    private let log = Logger(subsystem: "so.glyf.app", category: "voice")

    func begin() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.log("GLYF_VOICE live activity: turned off for Glyf")
            return
        }
        if Activity<GlyfVoiceAttributes>.activities.contains(where: { $0.activityState == .active }) { return }
        do {
            _ = try Activity.request(attributes: GlyfVoiceAttributes(),
                                     content: .init(state: .init(), staleDate: nil),
                                     pushType: nil)
            log.log("GLYF_VOICE live activity on")
        } catch {
            log.error("GLYF_VOICE live activity failed \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The listening state on the Lock Screen and in the Dynamic Island.
    func update(listening: Bool) {
        for a in Activity<GlyfVoiceAttributes>.activities where a.content.state.listening != listening {
            Task { await a.update(.init(state: .init(listening: listening), staleDate: nil)) }
        }
    }

    func end() {
        let all = Activity<GlyfVoiceAttributes>.activities
        guard !all.isEmpty else { return }
        for a in all {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        log.log("GLYF_VOICE live activity off")
    }
}
