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

    private struct Endpoints { let token: URL; let meet: URL; let events: URL }

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
                         events: URL(string: "\(events)?\(GoogleEvent.query)")!)
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
        return .refused
    }

    /// GETs with a token, and once more with a fresh one if Google says the
    /// token went stale on the way.
    private func get(_ url: URL, retry: Bool = true,
                     done: @escaping (Result<[String: Any], Failure>) -> Void) {
        accessToken { [weak self] token in
            guard let self else { return }
            switch token {
            case .failure(let f): done(.failure(f))
            case .success(let token):
                var req = URLRequest(url: url)
                req.timeoutInterval = 12
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: req) { data, response, _ in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    Self.main {
                        if (200..<300).contains(status), let json { return done(.success(json)) }
                        if status == 401, retry {
                            self.cached = nil
                            return self.get(url, retry: false, done: done)
                        }
                        done(.failure(status == 0 ? .unreachable : status == 401 ? .reconnect
                                        : Self.failure(fromError: json)))
                    }
                }.resume()
            }
        }
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

    /// POSTs with a token, and once more with a fresh one if Google says the
    /// token went stale on the way.
    private func post(_ url: URL, body: [String: Any], retry: Bool = true,
                      done: @escaping (Result<[String: Any], Failure>) -> Void) {
        accessToken { [weak self] token in
            guard let self else { return }
            switch token {
            case .failure(let f): done(.failure(f))
            case .success(let token):
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 12
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                URLSession.shared.dataTask(with: req) { data, response, _ in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    Self.main {
                        if (200..<300).contains(status), let json { return done(.success(json)) }
                        if status == 401, retry {
                            self.cached = nil
                            return self.post(url, body: body, retry: false, done: done)
                        }
                        done(.failure(status == 0 ? .unreachable : status == 401 ? .reconnect : .refused))
                    }
                }.resume()
            }
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
            return row
        }
        AppGroupStore.writeJSON(["events": rows], name: file)
    }
}
