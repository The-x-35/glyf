import ActivityKit
import Foundation

/// The Live Activity a session started by Start Glyf Voice shows ("Glyf
/// voice is ready", with Turn off). iOS stops an AudioRecordingIntent's
/// recording unless a Live Activity runs for as long as it records.
/// Compiled into the app (which starts and ends it: VoiceActivityHost) and
/// the GlyfVoiceWidget extension (which draws it).
struct GlyfVoiceAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// An utterance is being heard right now.
        var listening: Bool = false
    }
}
