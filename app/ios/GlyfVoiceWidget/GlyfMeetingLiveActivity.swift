import ActivityKit
import SwiftUI
import WidgetKit

/// The next meeting (GlyfMeetingAttributes): a countdown to its start, then
/// the time left, and Join.
struct GlyfMeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlyfMeetingAttributes.self) { context in
            MeetingLockScreen(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.state.join)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        GlyfTile(size: 30, dark: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(MeetingClock.label(s)).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GlyfStyle.violet)
                            Text(s.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MeetingClock(state: s).font(.system(size: 20, weight: .semibold))
                        .padding(.trailing, 6).frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: s.join) {
                        HStack(spacing: 6) {
                            Image(systemName: "video.fill")
                            Text("Join \(GlyfMeetingAttributes.service(s.join))")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .foregroundStyle(.black)
                        .background(Capsule().fill(.white))
                    }
                    .padding(.horizontal, 4).padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "video.fill").foregroundStyle(GlyfStyle.violet).padding(.leading, 2)
            } compactTrailing: {
                MeetingClock(state: s).font(.system(size: 13, weight: .semibold)).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "video.fill").foregroundStyle(GlyfStyle.violet)
            }
            .keylineTint(GlyfStyle.violet)
            .widgetURL(s.join)
        }
    }
}

/// Counts down to the start, then the minutes left.
private struct MeetingClock: View {
    let state: GlyfMeetingAttributes.ContentState

    var body: some View {
        Group {
            if Date() < state.start {
                Text(timerInterval: Date()...state.start, countsDown: true)
            } else {
                Text(timerInterval: state.start...state.end, countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(.white)
    }

    static func label(_ s: GlyfMeetingAttributes.ContentState) -> String {
        Date() < s.start ? "Starts soon" : "Now"
    }
}

private struct MeetingLockScreen: View {
    let state: GlyfMeetingAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            GlyfTile(size: 34, dark: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(MeetingClock.label(state))
                    Text("·")
                    Text(state.start, style: .time)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                MeetingClock(state: state).font(.system(size: 17, weight: .semibold)).frame(maxWidth: 70)
                Link(destination: state.join) {
                    Text("Join")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 30)
                        .foregroundStyle(.black)
                        .background(Capsule().fill(.white))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

extension GlyfMeetingAttributes.ContentState {
    static let preview = Self(title: "Design review with Mia", start: .now.addingTimeInterval(9 * 60),
                              end: .now.addingTimeInterval(39 * 60),
                              join: URL(string: "https://meet.google.com/abc-defg-hij")!)
}

#Preview("Meeting", as: .content, using: GlyfMeetingAttributes(key: "preview")) {
    GlyfMeetingLiveActivity()
} contentStates: {
    GlyfMeetingAttributes.ContentState.preview
}
