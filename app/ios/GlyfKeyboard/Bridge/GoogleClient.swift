import Foundation

/// The keyboard's own calls to Google, on the grant in GoogleAccess: a fresh
/// access token, a Meet link, an event in the person's Google Calendar.
/// Nothing here goes through Glyf's server. Callbacks arrive on the main queue.
final class GoogleClient {
    static let shared = GoogleClient()

    enum Failure: Error, Equatable {
        /// No grant, or none for this.
        case notConnected
        /// Google refused the grant: taken back, or a testing app's weekly expiry.
        case reconnect
        case unreachable
        /// Google answered no.
        case refused
        /// The Calendar API is switched off in Glyf's Google Cloud project.
        case apiOff
        /// The grant doesn't cover it (Calendar was unticked).
        case noScope
        /// Someone else's event: only its organizer can change it.
        case notOrganizer
    }

    /// What to tell the person when Google didn't do it.
    static func say(_ failure: Failure) -> String {
        switch failure {
        case .reconnect: return "Sign in with Google again in Glyf"
        case .unreachable: return "Couldn't reach Google"
        // The project is the one Glyf's iOS client belongs to: its number
        // leads the client id, so the console can be pointed at the right one.
        case .apiOff:
            let project = GoogleAccess.load()?.clientId.split(separator: "-").first.map(String.init)
            return "the Calendar API is off in Google Cloud" + (project.map { " project \($0)" } ?? "")
        case .noScope: return "turn Calendar on again in Glyf › Connected tools"
        case .notOrganizer: return "only the organizer can change it"
        case .refused, .notConnected: return "Google said no"
        }
    }

    struct Added: Equatable {
        /// The event on Google Calendar's web page.
        var link: String?
        /// Its Meet call, when one was asked for.
        var meet: String?
        /// Google's id for it.
        var id: String? = nil
    }

    private var cached: (token: String, expires: Date)?

    private struct Endpoints {
        let token: URL
        let meet: URL
        let events: URL
        /// The calendar's events, for one of them by id.
        let eventsBase: String

        /// One event (or one occurrence of a repeating one); Google emails
        /// its guests about the change.
        func event(_ id: String) -> URL? {
            let path = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
            return URL(string: "\(eventsBase)/\(path)?sendUpdates=all")
        }
    }

    private func endpoints(_ grant: GoogleGrant) -> Endpoints {
        var token = "https://oauth2.googleapis.com/token"
        var meet = "https://meet.googleapis.com/v2/spaces"
        var events = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        #if DEBUG
        if let base = grant.apiBase, !base.isEmpty {
            token = "\(base)/token"
            meet = "\(base)/v2/spaces"
            events = "\(base)/calendar/v3/calendars/primary/events"
        }
        #endif
        return Endpoints(token: URL(string: token)!, meet: URL(string: meet)!,
                         events: URL(string: "\(events)?\(GoogleEvent.query)")!, eventsBase: events)
    }

    private static func main(_ work: @escaping () -> Void) { DispatchQueue.main.async(execute: work) }

    /// A token that is good for a while yet, refreshed from the grant when not.
    func accessToken(_ done: @escaping (Result<String, Failure>) -> Void) {
        guard let grant = GoogleAccess.load() else { return Self.main { done(.failure(.notConnected)) } }
        if let c = cached, c.expires > Date().addingTimeInterval(60) {
            return Self.main { done(.success(c.token)) }
        }
        var req = URLRequest(url: endpoints(grant).token)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = ["client_id": grant.clientId, "refresh_token": grant.refreshToken,
                        "grant_type": "refresh_token"]
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let result: Result<String, Failure>
            if status == 200, let token = json?["access_token"] as? String {
                let life = (json?["expires_in"] as? Double) ?? 3600
                self?.cached = (token, Date().addingTimeInterval(life))
                result = .success(token)
            } else if (json?["error"] as? String) == "invalid_grant" {
                result = .failure(.reconnect)
            } else {
                result = .failure(status == 0 ? .unreachable : .refused)
            }
            Self.main { done(result) }
        }.resume()
    }

    /// A Meet link of the person's own ("https://meet.google.com/abc-defg-hij").
    func newMeet(_ done: @escaping (Result<String, Failure>) -> Void) {
        guard GoogleAccess.hasMeet, let grant = GoogleAccess.load() else {
            return Self.main { done(.failure(.notConnected)) }
        }
        post(endpoints(grant).meet, body: [:]) { result in
            done(result.flatMap { json in
                guard let uri = json["meetingUri"] as? String, uri.hasPrefix("https://") else {
                    return .failure(.refused)
                }
                return .success(uri)
            })
        }
    }

    /// The person's Google Calendar between two dates, each recurrence its
    /// own event, so the keyboard's calendar shows what Google has NOW —
    /// including everything added or changed on other devices.
    func listEvents(from: Date, to: Date, done: @escaping (Result<[CalendarText.Event], Failure>) -> Void) {
        guard GoogleAccess.hasCalendar, let grant = GoogleAccess.load() else {
            return Self.main { done(.failure(.notConnected)) }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var comps = URLComponents(url: endpoints(grant).events, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "timeMin", value: iso.string(from: from)),
            .init(name: "timeMax", value: iso.string(from: to)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "250"),
        ]
        get(comps.url!) { result in
            done(result.map { json in
                GoogleEvent.events(fromList: json)
            })
        }
    }

    /// What Google's error body says went wrong: the API switched off in the
    /// Cloud project, or a scope the grant doesn't have.
    static func failure(fromError json: [String: Any]?) -> Failure {
        let error = json?["error"] as? [String: Any]
        let reasons = (error?["errors"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
        let details = (error?["details"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
        let message = (error?["message"] as? String ?? "").lowercased()
        if reasons.contains("accessNotConfigured") || details.contains("SERVICE_DISABLED")
            || message.contains("has not been used") || message.contains("is disabled") {
            return .apiOff
        }
        if reasons.contains("insufficientPermissions") || details.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT")
            || message.contains("insufficient authentication scopes") {
            return .noScope
        }
        if reasons.contains("forbiddenForNonOrganizer") || message.contains("only be changed by the organizer") {
            return .notOrganizer
        }
        return .refused
    }

    /// Sends with a token, and once more with a fresh one if Google says the
    /// token went stale on the way. Any answer from Google comes back as its
    /// status and body; no answer, or a grant Google refused, as a failure.
    private func send(_ method: String, _ url: URL, body: [String: Any]? = nil, retry: Bool = true,
                      done: @escaping (Result<(status: Int, json: [String: Any]?), Failure>) -> Void) {
        accessToken { [weak self] token in
            guard let self else { return }
            switch token {
            case .failure(let f): done(.failure(f))
            case .success(let token):
                var req = URLRequest(url: url)
                req.httpMethod = method
                req.timeoutInterval = 12
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let body {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                }
                URLSession.shared.dataTask(with: req) { data, response, _ in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    Self.main {
                        if status == 401, retry {
                            self.cached = nil
                            return self.send(method, url, body: body, retry: false, done: done)
                        }
                        if status == 0 { return done(.failure(.unreachable)) }
                        if status == 401 { return done(.failure(.reconnect)) }
                        done(.success((status, json)))
                    }
                }.resume()
            }
        }
    }

    /// A call whose answer is an object: Google's body, or why it said no.
    private func call(_ method: String, _ url: URL, body: [String: Any]? = nil,
                      done: @escaping (Result<[String: Any], Failure>) -> Void) {
        send(method, url, body: body) { result in
            done(result.flatMap { answer in
                if (200..<300).contains(answer.status), let json = answer.json { return .success(json) }
                return .failure(Self.failure(fromError: answer.json))
            })
        }
    }

    private func get(_ url: URL, done: @escaping (Result<[String: Any], Failure>) -> Void) {
        call("GET", url, done: done)
    }

    /// The event in the person's own Google Calendar. Google emails each
    /// guest the invite and makes the Meet call when `video` is on.
    func addEvent(title: String, start: Date, end: Date, allDay: Bool, guests: [String], video: Bool,
                  done: @escaping (Result<Added, Failure>) -> Void) {
        guard GoogleAccess.hasCalendar, let grant = GoogleAccess.load() else {
            return Self.main { done(.failure(.notConnected)) }
        }
        let body = GoogleEvent.body(title: title, start: start, end: end, allDay: allDay,
                                    guests: guests, video: video)
        post(endpoints(grant).events, body: body) { result in
            done(result.map { json in
                Added(link: json["htmlLink"] as? String, meet: json["hangoutLink"] as? String,
                      id: json["id"] as? String)
            })
        }
    }

    private func post(_ url: URL, body: [String: Any],
                      done: @escaping (Result<[String: Any], Failure>) -> Void) {
        call("POST", url, body: body, done: done)
    }

    /// One event changed in place: its title and times (one occurrence of a
    /// repeating event). Google emails its guests the change. Comes back as
    /// Google now lists it.
    func updateEvent(id: String, title: String, start: Date, end: Date, allDay: Bool,
                     done: @escaping (Result<CalendarText.Event?, Failure>) -> Void) {
        guard GoogleAccess.hasCalendar, let grant = GoogleAccess.load(),
              let url = endpoints(grant).event(id) else {
            return Self.main { done(.failure(.notConnected)) }
        }
        let body = GoogleEvent.patch(title: title, start: start, end: end, allDay: allDay)
        call("PATCH", url, body: body) { result in
            done(result.map { GoogleEvent.events(fromList: ["items": [$0]]).first })
        }
    }

    /// One event gone from the calendar (one occurrence of a repeating
    /// event). Google tells its guests. Already gone counts as done.
    func deleteEvent(id: String, done: @escaping (Result<Void, Failure>) -> Void) {
        guard GoogleAccess.hasCalendar, let grant = GoogleAccess.load(),
              let url = endpoints(grant).event(id) else {
            return Self.main { done(.failure(.notConnected)) }
        }
        send("DELETE", url) { result in
            done(result.flatMap { answer in
                if (200..<300).contains(answer.status) || answer.status == 404 || answer.status == 410 {
                    return .success(())
                }
                return .failure(Self.failure(fromError: answer.json))
            })
        }
    }
}

/// A call link: the person's own Google Meet, and nothing else. Without
/// Google connected, or when Google says no, there is no link and `note`
/// says what to do.
enum CallLink {
    static let connectFirst = "Connect Google Meet in Glyf › Connected tools"

    static func make(_ done: @escaping (_ url: String?, _ note: String?) -> Void) {
        guard GoogleAccess.hasMeet else {
            return DispatchQueue.main.async { done(nil, connectFirst) }
        }
        GoogleClient.shared.newMeet { result in
            switch result {
            case .success(let url): done(url, nil)
            case .failure(let failure): done(nil, GoogleClient.say(failure))
            }
        }
    }
}

/// Events the keyboard added to Google Calendar, kept so its calendar can show
/// them before the phone's own calendar has them (CalendarText.withAdded).
enum GoogleAdded {
    private static let file = "google-added.json"

    static func remember(_ event: CalendarText.Event) {
        save(Array((load() + [event]).suffix(30)))
    }

    /// Deleted, or changed (then `with` is how it reads now).
    static func forget(id: String, with changed: CalendarText.Event? = nil) {
        let added = load()
        guard added.contains(where: { $0.id == id }) else { return }
        save(added.compactMap { $0.id == id ? changed : $0 })
    }

    /// `events` with every added event the phone doesn't show yet.
    static func merged(into events: [CalendarText.Event], now: Date = Date()) -> [CalendarText.Event] {
        let added = load()
        guard !added.isEmpty else { return events }
        let shown = CalendarText.withAdded(added, in: events, now: now)
        if shown.pending.count != added.count { save(shown.pending) }
        return shown.events
    }

    private static func load() -> [CalendarText.Event] {
        CalendarText.events(fromJSON: AppGroupStore.readJSON(name: file))
    }

    private static func save(_ events: [CalendarText.Event]) {
        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = events.map { e in
            var row: [String: Any] = ["title": e.title, "start": iso.string(from: e.start),
                                      "end": iso.string(from: e.end), "allDay": e.allDay]
            if let location = e.location { row["location"] = location }
            if let id = e.id { row["id"] = id }
            if let external = e.external { row["external"] = external }
            if e.repeats { row["repeats"] = true }
            return row
        }
        AppGroupStore.writeJSON(["events": rows], name: file)
    }
}

/// Google's last answer, per account: the calendar opens on it at once
/// (then asks Google again), and a different account never shows another
/// one's events.
enum GoogleCache {
    private static let file = "google-calendar.json"

    static func load(for email: String?) -> (events: [CalendarText.Event], at: Date)? {
        guard let json = AppGroupStore.readJSON(name: file),
              let owner = json["email"] as? String, owner == (email ?? ""),
              let at = json["at"] as? Double else { return nil }
        return (CalendarText.events(fromJSON: json), Date(timeIntervalSince1970: at))
    }

    static func save(_ events: [CalendarText.Event], for email: String?) {
        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = events.map { e in
            var row: [String: Any] = ["title": e.title, "start": iso.string(from: e.start),
                                      "end": iso.string(from: e.end), "allDay": e.allDay]
            if let location = e.location { row["location"] = location }
            if let id = e.id { row["id"] = id }
            if let external = e.external { row["external"] = external }
            if e.repeats { row["repeats"] = true }
            return row
        }
        AppGroupStore.writeJSON(["email": email ?? "", "at": Date().timeIntervalSince1970, "events": rows],
                                name: file)
    }
}

// MARK: - Phone tools

/// What a built glyf asks of the phone before it runs (the Builder's Tools):
/// a new Google Meet link, the booking link, today's calendar. Each answer
/// rides to /glyf/run as the var `phone.<tool>`, so Google's grant and the
/// calendar never leave the phone. A tool that can't answer stops the run
/// with where to turn it on.
enum PhoneTools {
    static func resolve(_ tools: [String], hasFullAccess: Bool, now: Date = Date(),
                        done: @escaping (_ vars: [String: String], _ note: String?) -> Void) {
        var vars: [String: String] = [:]
        var pending = tools[...]
        func next() {
            guard let tool = pending.popFirst() else { return done(vars, nil) }
            answer(tool, hasFullAccess: hasFullAccess, now: now) { value, note in
                guard let value, !value.isEmpty else {
                    return done(vars, note ?? "Open this glyf in Glyf to finish setting it up")
                }
                vars["phone.\(tool)"] = value
                next()
            }
        }
        DispatchQueue.main.async { next() }
    }

    private static func answer(_ tool: String, hasFullAccess: Bool, now: Date,
                               _ done: @escaping (String?, String?) -> Void) {
        switch tool {
        case "meet.new":
            CallLink.make(done)
        case "booking.link":
            let link = (SettingsStore.current.bookingLink ?? "").trimmingCharacters(in: .whitespaces)
            done(link.isEmpty ? nil : (link.hasPrefix("http") ? link : "https://\(link)"),
                 "Add your booking link in Glyf › Connected tools")
        case "calendar.day":
            done(dayText(hasFullAccess: hasFullAccess, now: now), "Turn on Calendar in Glyf › Connected tools")
        default:
            done(nil, "Update Glyf to run this glyf")
        }
    }

    /// Today's events, one a line, then when the day has room; nil when the
    /// keyboard can read no calendar at all.
    static func dayText(hasFullAccess: Bool, now: Date = Date(), calendar cal: Calendar = .current) -> String? {
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        var all: [CalendarText.Event]
        if CalendarWriter.access(hasFullAccess: hasFullAccess) == .ready, CalendarWriter.canRead {
            all = CalendarWriter.events(from: start, to: end)
        } else if let json = AppGroupStore.readJSON(name: "calendar.json") {
            all = CalendarText.events(fromJSON: json)
        } else {
            return nil
        }
        all = GoogleAdded.merged(into: all, now: now)
        return lines(for: now, in: all, calendar: cal)
    }

    static func lines(for day: Date, in all: [CalendarText.Event], calendar cal: Calendar = .current,
                      locale: Locale = .current, now: Date = Date()) -> String {
        let today = CalendarText.events(on: day, in: all, calendar: cal)
        let rows = today.map { e in
            e.allDay ? "All day \(e.title)" : "\(CalendarText.range(e.start, e.end, calendar: cal, locale: locale)) \(e.title)"
        }
        let free = CalendarText.freeTime(on: day, in: all, calendar: cal, locale: locale, now: now)
        return ((rows.isEmpty ? ["Nothing on the calendar today"] : rows) + [free])
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
