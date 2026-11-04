import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Glyf's widget extension: the Glyf Voice control (Control Center, the Lock
/// Screen, the Action button) and the Live Activity a session started from
/// it shows. iOS 18+.
@main
struct GlyfVoiceWidgets: WidgetBundle {
    var body: some Widget {
        GlyfVoiceControl()
        GlyfVoiceLiveActivity()
    }
}

private let violet = Color(red: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255)

/// One tap: voice typing ready, no trip through Glyf (StartGlyfVoiceIntent).
struct GlyfVoiceControl: ControlWidget {
    static let kind = "com.arpit.glyf.voice.control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartGlyfVoiceIntent()) {
                Label("Glyf Voice", systemImage: "mic.fill")
            }
        }
        .displayName("Glyf Voice")
        .description("Voice typing ready in the Glyf keyboard.")
    }
}

/// "Glyf voice is ready" with Turn off, on the Lock Screen and in the
/// Dynamic Island.
struct GlyfVoiceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlyfVoiceAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(violet)
                Text(context.state.listening ? "Listening…" : "Glyf voice is ready")
                    .font(.headline)
                Spacer()
                Button(intent: StopGlyfVoiceIntent()) {
                    Text("Turn off")
                }
                .buttonStyle(.bordered)
                .tint(violet)
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill").foregroundStyle(violet)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.listening ? "Listening…" : "Glyf voice is ready")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopGlyfVoiceIntent()) {
                        Image(systemName: "xmark")
                    }
                    .tint(violet)
                }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundStyle(violet)
            } compactTrailing: {
                Text("Glyf").font(.caption2)
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(violet)
            }
        }
    }
}
