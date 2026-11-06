import ActivityKit
import Foundation

/// The next meeting with a call, as a Live Activity that iOS 26 starts on
/// its own ten minutes before (a scheduled start, no server): a countdown,
/// then the time left, and Join. The app schedules it whenever it comes
/// forward (MeetingActivityHost) from the calendars it keeps for the
/// keyboard. Compiled into the app and the widget extension.
struct GlyfMeetingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var join: URL
    }

    /// The event this is for: title and start, so a moved meeting is a new one.
    var key: String

    static func key(for e: GlyfWidgetData.Event) -> String {
        "\(e.title)|\(Int(e.start.timeIntervalSince1970))"
    }

    /// How early iOS shows it.
    static let lead: TimeInterval = 10 * 60

    /// When to start it for `e`, or nil when there is nothing to show: no
    /// call to join, over already, or more than iOS's eight hours away.
    static func start(for e: GlyfWidgetData.Event, now: Date = Date()) -> Date? {
        guard e.join != nil, e.end > now else { return nil }
        let at = e.start.addingTimeInterval(-lead)
        guard at < now.addingTimeInterval(8 * 3600) else { return nil }
        return max(at, now)
    }

    /// "Meet", "Zoom", "Teams", for the Join button.
    static func service(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        return "Meet"
    }
}
