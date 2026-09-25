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
    }

    /// What to tell the person when Google didn't do it.
    static func say(_ failure: Failure) -> String {
        switch failure {
        case .reconnect: return "Sign in with Google again in Glyf"
        case .unreachable: return "Couldn't reach Google"
        case .refused, .notConnected: return "Google said no"
        }
    }

    struct Added: Equatable {
        /// The event on Google Calendar's web page.
        var link: String?
        /// Its Meet call, when one was asked for.
        var meet: String?
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
                Added(link: json["htmlLink"] as? String, meet: json["hangoutLink"] as? String)
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
    static let connectFirst = "Sign in with Google in Glyf to make Meet links"

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
