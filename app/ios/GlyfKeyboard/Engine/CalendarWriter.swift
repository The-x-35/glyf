import EventKit
import Foundation

/// The phone's calendar, from inside the keyboard. A keyboard can't show the
/// calendar prompt, so the app asks (Connected tools → Calendar); once it has
/// the answer and Full Access is on, the keyboard reads and adds events
/// through EventKit itself. Checked on the iOS 26.5 simulator: read, save and
/// remove all work from the extension.
enum CalendarWriter {

    enum Access: Equatable {
        case ready
        /// Keyboards without Full Access are kept away from the calendar.
        case needsFullAccess
        /// The app hasn't been allowed to use the calendar (or was refused).
        case needsPermission
    }

    private static var store: EKEventStore?
    private static func eventStore() -> EKEventStore {
        if let s = store { return s }
        let s = EKEventStore()
        store = s
        return s
    }

    static func access(hasFullAccess: Bool) -> Access {
        guard hasFullAccess else { return .needsFullAccess }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: return .ready
        default: return .needsPermission
        }
    }

    /// The app has never asked for the calendar, so Settings has no switch
    /// for it yet.
    static var neverAsked: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    /// Whether events can be read too (write-only access adds but can't list).
    static var canRead: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Events touching the range, straight from the calendar, in the same
    /// shape calendar.json gives.
    static func events(from start: Date, to end: Date) -> [CalendarText.Event] {
        guard canRead else { return [] }
        let s = eventStore()
        let predicate = s.predicateForEvents(withStart: start, end: end, calendars: nil)
        return s.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(1500)
            .map { e in
                CalendarText.Event(
                    title: (e.title ?? "").isEmpty ? "Busy" : (e.title ?? ""),
                    start: e.startDate, end: max(e.endDate, e.startDate), allDay: e.isAllDay,
                    location: (e.location ?? "").isEmpty ? nil : e.location,
                    color: e.calendar?.cgColor.flatMap(hex), id: e.eventIdentifier)
            }
    }

    struct Added {
        let event: CalendarText.Event
        let calendarName: String
    }

    enum Failure: Error, Equatable {
        case noCalendar
        case saveFailed(String)
    }

    /// Saves the event in the default calendar for new events.
    static func add(title: String, start: Date, end: Date, allDay: Bool,
                    location: String? = nil, url: URL? = nil, notes: String? = nil) -> Result<Added, Failure> {
        let s = eventStore()
        guard let calendar = s.defaultCalendarForNewEvents else { return .failure(.noCalendar) }
        let e = EKEvent(eventStore: s)
        e.title = title
        e.startDate = start
        e.endDate = max(end, start)
        e.isAllDay = allDay
        e.calendar = calendar
        if let location, !location.isEmpty { e.location = location }
        if let url { e.url = url }
        if let notes, !notes.isEmpty { e.notes = notes }
        do {
            try s.save(e, span: .thisEvent, commit: true)
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
        let row = CalendarText.Event(title: title, start: e.startDate, end: e.endDate, allDay: allDay,
                                     location: location, color: calendar.cgColor.flatMap(hex), id: e.eventIdentifier)
        return .success(Added(event: row, calendarName: calendar.title))
    }

    private static func hex(_ color: CGColor) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let c = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        let r = Int((comps[0] * 255).rounded()), g = Int((comps[1] * 255).rounded()), b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
