import ActivityKit
import Foundation
import os.log

/// Schedules the next meeting's Live Activity (GlyfMeetingAttributes) each
/// time Glyf comes forward: iOS 26 starts it by itself ten minutes before,
/// with no server and no push. Experimental; only meetings with a call.
enum MeetingActivityHost {
    private static let log = Logger(subsystem: "so.glyf.app", category: "meeting-activity")

    static func refresh(now: Date = Date()) {
        guard #available(iOS 26.0, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let next = GlyfWidgetData.loadNextEvent(now: now)
        let running = Activity<GlyfMeetingAttributes>.activities
        let key = next.map(GlyfMeetingAttributes.key(for:))
        // A meeting that moved or went: its activity goes too.
        for a in running where a.attributes.key != key {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        guard let e = next, let key, let join = e.join,
              let at = GlyfMeetingAttributes.start(for: e, now: now),
              !running.contains(where: { $0.attributes.key == key }) else { return }
        let state = GlyfMeetingAttributes.ContentState(title: e.title, start: e.start, end: e.end, join: join)
        do {
            if at <= now.addingTimeInterval(5) {
                _ = try Activity.request(attributes: GlyfMeetingAttributes(key: key),
                                         content: .init(state: state, staleDate: e.end), pushType: nil)
            } else {
                _ = try Activity.request(attributes: GlyfMeetingAttributes(key: key),
                                         content: .init(state: state, staleDate: e.end), pushType: nil,
                                         style: .standard,
                                         alertConfiguration: .init(title: "\(e.title)", body: "Starts in 10 minutes",
                                                                   sound: .default),
                                         start: at)
            }
            log.log("GLYF_MEETING activity scheduled")
        } catch {
            log.error("GLYF_MEETING activity failed \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
    /// `--glyf-demo-meeting`: a meeting nine minutes away, shown at once.
    static func demo() {
        let now = Date()
        let state = GlyfMeetingAttributes.ContentState(
            title: "Design review with Mia", start: now.addingTimeInterval(9 * 60),
            end: now.addingTimeInterval(39 * 60), join: URL(string: "https://meet.google.com/abc-defg-hij")!)
        _ = try? Activity.request(attributes: GlyfMeetingAttributes(key: "demo"),
                                  content: .init(state: state, staleDate: state.end), pushType: nil)
    }
    #endif
}
