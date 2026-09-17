import Foundation

/// The phone's calendar as the keyboard reads it (the app keeps the coming
/// weeks in `calendar.json`), and the words it puts in a message: an event,
/// or when you are free on a day. Pure, so it is unit tested.
enum CalendarText {

    struct Event: Equatable {
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool
        var location: String?
        var color: String?
    }

    static func events(fromJSON json: [String: Any]?) -> [Event] {
        guard let rows = json?["events"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let s = (row["start"] as? String).flatMap(iso.date(from:)),
                  let e = (row["end"] as? String).flatMap(iso.date(from:)) else { return nil }
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return Event(title: title.isEmpty ? "Busy" : title, start: s, end: max(e, s),
                         allDay: row["allDay"] as? Bool ?? false,
                         location: (row["location"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                         color: row["color"] as? String)
        }
    }

    /// Everything that touches the day, all-day events first.
    static func events(on day: Date, in all: [Event], calendar cal: Calendar = .current) -> [Event] {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return all.filter { $0.start < end && ($0.end > start || ($0.end == $0.start && $0.start >= start)) }
            .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
    }

    static func dayLabel(_ day: Date, calendar cal: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: day)
    }

    static func clock(_ date: Date, calendar cal: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = locale
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    /// "3:00 – 4:30 PM" style, as short as the times allow.
    static func range(_ start: Date, _ end: Date, calendar cal: Calendar = .current, locale: Locale = .current) -> String {
        let a = clock(start, calendar: cal, locale: locale)
        let b = clock(end, calendar: cal, locale: locale)
        let ampm = [" AM", " PM", "\u{202F}AM", "\u{202F}PM"]
        if let suffix = ampm.first(where: { a.hasSuffix($0) && b.hasSuffix($0) }) {
            return "\(a.dropLast(suffix.count))–\(b)"
        }
        return "\(a)–\(b)"
    }

    /// "📅 Design review · Thu 18 Sep, 3:00–4:00 PM · Studio"
    static func insert(_ e: Event, calendar cal: Calendar = .current, locale: Locale = .current) -> String {
        let day = dayLabel(e.start, calendar: cal, locale: locale)
        let when = e.allDay ? day : "\(day), \(range(e.start, e.end, calendar: cal, locale: locale))"
        return ["📅 \(e.title)", when, e.location].compactMap { $0 }.joined(separator: " · ")
    }

    /// When the day has room, between 9 AM and 9 PM, in a sentence.
    static func freeTime(on day: Date, in all: [Event], calendar cal: Calendar = .current,
                         locale: Locale = .current, from: Int = 9, to: Int = 21, now: Date = Date()) -> String {
        let label = dayLabel(day, calendar: cal, locale: locale)
        let dayStart = cal.startOfDay(for: day)
        guard var open = cal.date(byAdding: .hour, value: from, to: dayStart),
              let close = cal.date(byAdding: .hour, value: to, to: dayStart) else { return "" }
        // Today, the free time starts now (at the next half hour).
        var startsNow = false
        if cal.isDate(now, inSameDayAs: day), now > open {
            startsNow = true
            let half = (now.timeIntervalSince(dayStart) / 1800).rounded(.up) * 1800
            open = dayStart.addingTimeInterval(half)
            if open >= close { return "I'm done for today" }
        }
        let busy = events(on: day, in: all, calendar: cal)
        if busy.contains(where: { $0.allDay }) { return "I'm busy all day \(label)" }
        var gaps: [(Date, Date)] = []
        var cursor = open
        for e in busy.sorted(by: { $0.start < $1.start }) {
            let s = max(e.start, open), f = min(e.end, close)
            guard f > s else { continue }
            if s.timeIntervalSince(cursor) >= 30 * 60 { gaps.append((cursor, s)) }
            cursor = max(cursor, f)
        }
        if close.timeIntervalSince(cursor) >= 30 * 60 { gaps.append((cursor, close)) }
        if gaps.isEmpty { return "I'm booked \(label)" }
        if !startsNow, gaps.count == 1, gaps[0].0 == open, gaps[0].1 == close { return "I'm free all day \(label)" }
        let parts = gaps.map { range($0.0, $0.1, calendar: cal, locale: locale) }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts[0]
        return "I'm free \(label), \(list)"
    }
}
