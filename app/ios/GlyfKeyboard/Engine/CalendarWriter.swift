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
                    color: e.calendar?.cgColor.flatMap(hex), id: e.eventIdentifier,
                    external: e.calendarItemExternalIdentifier, calendar: e.calendar?.title,
                    repeats: e.hasRecurrenceRules)
            }
    }

    enum Change: Error, Equatable {
        /// Gone from the calendar since the list was read.
        case notFound
        /// A calendar nobody can change here (Birthdays, holidays, subscriptions).
        case readOnly(String)
        case failed(String)
    }

    /// The occurrence on screen. EventKit's id names a whole repeating
    /// series, so its start picks the one.
    private static func occurrence(of e: CalendarText.Event) -> EKEvent? {
        guard canRead, let id = e.id, !id.hasPrefix("google:") else { return nil }
        let s = eventStore()
        let around = s.predicateForEvents(withStart: e.start.addingTimeInterval(-1),
                                          end: max(e.end, e.start).addingTimeInterval(1), calendars: nil)
        if let one = s.events(matching: around).first(where: {
            $0.eventIdentifier == id && abs($0.startDate.timeIntervalSince(e.start)) < 1
        }) {
            return one
        }
        // Only a one-off is safe to take by id alone: for a series it is the first time.
        if let one = s.event(withIdentifier: id), !one.hasRecurrenceRules { return one }
        return nil
    }

    /// The calendar's name when the event can't be changed from here.
    static func readOnly(_ e: CalendarText.Event) -> String? {
        guard let calendar = occurrence(of: e)?.calendar, !calendar.allowsContentModifications else { return nil }
        return calendar.title
    }

    /// Deletes the event (this occurrence only, for a repeating one).
    static func remove(_ e: CalendarText.Event) -> Result<Void, Change> {
        guard let found = occurrence(of: e) else { return .failure(.notFound) }
        if let calendar = found.calendar, !calendar.allowsContentModifications {
            return .failure(.readOnly(calendar.title))
        }
        do {
            try eventStore().remove(found, span: .thisEvent, commit: true)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        return .success(())
    }

    /// The event's title and times changed in place (this occurrence only,
    /// for a repeating one). Comes back as the list shows it now.
    static func update(_ e: CalendarText.Event, title: String, start: Date, end: Date,
                       allDay: Bool) -> Result<CalendarText.Event, Change> {
        guard let found = occurrence(of: e) else { return .failure(.notFound) }
        if let calendar = found.calendar, !calendar.allowsContentModifications {
            return .failure(.readOnly(calendar.title))
        }
        found.title = title
        found.isAllDay = allDay
        found.startDate = start
        // EventKit ends an all-day event within its last day; the composer
        // counts to the midnight after it, as Google does.
        found.endDate = allDay ? max(start, end.addingTimeInterval(-1)) : max(end, start)
        do {
            try eventStore().save(found, span: .thisEvent, commit: true)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        var changed = e
        changed.title = title
        changed.start = found.startDate
        changed.end = max(found.endDate, found.startDate)
        changed.allDay = allDay
        changed.id = found.eventIdentifier ?? e.id
        return .success(changed)
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
