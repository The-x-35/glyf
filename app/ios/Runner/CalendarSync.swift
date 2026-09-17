import EventKit
import Foundation

/// The phone's calendar, for the keyboard. A keyboard extension cannot ask
/// for calendar access, so the app asks once and keeps the next weeks of
/// events in the App Group (`calendar.json`); the keyboard only reads that
/// file. Nothing is sent anywhere.
final class CalendarSync {
    static let shared = CalendarSync()
    private init() {}

    private let store = EKEventStore()
    static let fileName = "calendar.json"

    var permission: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return "granted"
        case .notDetermined: return "notDetermined"
        case .writeOnly: return "writeOnly"
        default: return "denied"
        }
    }

    var enabled: Bool {
        guard let url = AppGroupStore.bridgeDir?.appendingPathComponent(Self.fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func enable(_ done: @escaping ([String: Any]) -> Void) {
        let finish: (Bool) -> Void = { granted in
            DispatchQueue.main.async {
                guard granted else {
                    done(["ok": false, "error": "denied"])
                    return
                }
                done(self.sync())
            }
        }
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { granted, _ in finish(granted) }
        } else {
            store.requestAccess(to: .event) { granted, _ in finish(granted) }
        }
    }

    func disable() {
        if let url = AppGroupStore.bridgeDir?.appendingPathComponent(Self.fileName) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Refreshes the file when calendar is on; called at launch and whenever
    /// the app comes back, so the keyboard sees today's changes.
    func refreshIfEnabled() {
        guard enabled, permission == "granted" else { return }
        _ = sync()
    }

    /// From the start of last week to eight weeks ahead: enough for the
    /// keyboard's month view and "am I free Thursday".
    @discardableResult
    func sync(now: Date = Date()) -> [String: Any] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now
        let end = cal.date(byAdding: .day, value: 56, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(1500)
            .map { e in
                var row: [String: Any] = [
                    "title": e.title ?? "",
                    "start": iso.string(from: e.startDate),
                    "end": iso.string(from: e.endDate),
                    "allDay": e.isAllDay,
                    "calendar": e.calendar?.title ?? "",
                ]
                if let location = e.location, !location.isEmpty { row["location"] = location }
                if let color = e.calendar?.cgColor, let hex = Self.hex(color) { row["color"] = hex }
                return row
            }
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONSerialization.data(withJSONObject: [
                  "syncedAt": iso.string(from: now), "events": rows,
              ])
        else { return ["ok": false, "error": "store failed"] }
        do {
            try data.write(to: dir.appendingPathComponent(Self.fileName), options: .atomic)
        } catch {
            return ["ok": false, "error": "store failed"]
        }
        return ["ok": true, "count": rows.count]
    }

    private static func hex(_ color: CGColor) -> String? {
        guard let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        let r = Int((comps[0] * 255).rounded()), g = Int((comps[1] * 255).rounded()), b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
