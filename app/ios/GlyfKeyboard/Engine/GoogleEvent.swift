import Foundation

/// The Google Calendar event a New Event becomes, in the API's own shape
/// (events.insert). Pure, so both keyboards test it with the same cases.
enum GoogleEvent {
    /// events.insert's query: Google emails every guest, and makes the Meet
    /// call when one is asked for.
    static let query = "sendUpdates=all&conferenceDataVersion=1"

    /// The title, the times (a day for an all-day event, the end day not
    /// included, as Google counts them), the guests, and a Meet call.
    static func body(title: String, start: Date, end: Date, allDay: Bool, guests: [String],
                     video: Bool, timeZone: TimeZone = .current,
                     requestId: String = UUID().uuidString) -> [String: Any] {
        var body: [String: Any] = ["summary": title]
        if allDay {
            let day = DateFormatter()
            day.calendar = Calendar(identifier: .gregorian)
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = timeZone
            day.dateFormat = "yyyy-MM-dd"
            let last = end > start ? end : start.addingTimeInterval(86_400)
            body["start"] = ["date": day.string(from: start)]
            body["end"] = ["date": day.string(from: last)]
        } else {
            let at = ISO8601DateFormatter()
            at.timeZone = timeZone
            at.formatOptions = [.withInternetDateTime]
            body["start"] = ["dateTime": at.string(from: start), "timeZone": timeZone.identifier]
            body["end"] = ["dateTime": at.string(from: max(end, start)), "timeZone": timeZone.identifier]
        }
        if !guests.isEmpty { body["attendees"] = guests.map { ["email": $0] } }
        if video {
            body["conferenceData"] = ["createRequest": [
                "requestId": requestId,
                "conferenceSolutionKey": ["type": "hangoutsMeet"],
            ]]
        }
        return body
    }
}
