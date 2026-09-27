import Foundation

/// The Google Calendar event a New Event becomes, in the API's own shape
/// (events.insert). Pure, so both keyboards test it with the same cases.
enum GoogleEvent {
    /// events.insert's query: Google emails every guest, and makes the Meet
    /// call when one is asked for.
    static let query = "sendUpdates=all&conferenceDataVersion=1"

    /// events.list's answer as the keyboard's own events: each recurrence
    /// its own row (`singleEvents`), all-day ends exclusive the way Google
    /// counts them, cancelled instances left out.
    static func events(fromList json: [String: Any], timeZone: TimeZone = .current) -> [CalendarText.Event] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"
        var out: [CalendarText.Event] = []
        for item in json["items"] as? [[String: Any]] ?? [] {
            if (item["status"] as? String) == "cancelled" { continue }
            func moment(_ node: Any?) -> (Date, Bool)? {
                guard let d = node as? [String: Any] else { return nil }
                if let s = d["dateTime"] as? String, let t = iso.date(from: s) { return (t, false) }
                if let s = d["date"] as? String, let t = day.date(from: s) { return (t, true) }
                return nil
            }
            guard let (start, allDay) = moment(item["start"]) else { continue }
            let end = moment(item["end"])?.0 ?? start
            let title = (item["summary"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            out.append(CalendarText.Event(
                title: title.isEmpty ? "Busy" : title,
                start: start, end: max(end, start), allDay: allDay,
                location: item["location"] as? String,
                id: (item["id"] as? String).map { "google:\($0)" }))
        }
        return out
    }

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
