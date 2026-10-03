import Foundation
import os.log

/// Keyboard → backend. Requires Full Access (§1.3 — network is gated).
/// Streams /glyf/run as SSE so tokens render as they arrive (§6.4).
/// NEVER holds provider keys; the backend owns OpenRouter (§1.6).
final class BackendClient: NSObject, URLSessionDataDelegate {

    /// Vault kinds the model may see when the person asks it to write or fill
    /// something: the details they hand out every day anyway. Anything
    /// secret-shaped never reaches the vault in the first place (VaultRules),
    /// and nothing here goes out unless "Let AI use your details" is on.
    static let shareableKinds: Set<String> = [
        "name", "email", "phone", "address", "upi", "link", "social",
        "company", "bio",
    ]

    /// nil when the setting is off, before the person has answered "What
    /// Glyf sends" in the app, or when there is nothing worth sending.
    static func shareableProfile() -> [String: String]? {
        guard SettingsStore.current.aiUsesVault != false, SettingsStore.current.aiConsent != nil
        else { return nil }
        var out: [String: String] = [:]
        for field in VaultStore.shared.load().fields
        where shareableKinds.contains(field.kind) {
            // One per kind, labelled so socials stay distinguishable.
            let key = field.kind == "social" ? "social:\(field.label.lowercased())" : field.kind
            if out[key] == nil { out[key] = field.value }
        }
        return out.isEmpty ? nil : out
    }


    static let shared = BackendClient()
    private let log = Logger(subsystem: "so.glyf.keyboard", category: "backend")

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }()

    private struct Stream {
        /// Bytes as they come: a chunk can end halfway through a character
        /// (’, an emoji, Hindi), so events are split on bytes and decoded
        /// whole, never chunk by chunk.
        var buffer = Data()
        var onToken: (String) -> Void
        var onDone: (String, Int?) -> Void
        var onError: (String) -> Void
        var fullText = ""
        var finished = false
        /// A streamed /act: every event goes here with its JSON.
        var onAct: ((String, Data) -> Void)?
    }

    private var streams: [Int: Stream] = [:]

    /// Runs a glyf. Callbacks arrive on the main queue.
    /// Returns the task so callers can cancel (e.g. bar dismissed).
    @discardableResult
    func run(glyfId: String, input: String, vars: [String: String] = [:],
             onToken: @escaping (String) -> Void,
             onDone: @escaping (String, Int?) -> Void,
             onError: @escaping (String) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/glyf/run") else {
            onError("Bad backend URL")
            return nil
        }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // §6.15: the tone profile rides along as a var — prompts opt in with
        // {{toneHint}}; it's "" until ≥3 net accepts teach us something.
        var mergedVars = vars
        if mergedVars["toneHint"] == nil {
            mergedVars["toneHint"] = ToneProfile.currentHint()
        }
        // Translate goes between the person's two languages, whichever way
        // the text is facing: the same pair the T-key strip uses, so the
        // toolbar, the bar and the strip never disagree on the destination.
        if glyfId == "glyf.translate" {
            let pair = Self.translatePair
            if mergedVars["primary"] == nil { mergedVars["primary"] = pair.primary }
            if mergedVars["secondary"] == nil { mergedVars["secondary"] = pair.secondary }
        }
        var body: [String: Any] = [
            "glyfId": glyfId,
            "input": input,
            "vars": mergedVars,
            "deviceId": s.deviceId,
            "pro": s.proUnlocked ?? false, // legacy flag, still honored
            "plan": s.plan ?? "free",      // §6.16 (receipt validation: M7-ship)
        ]
        if let profile = Self.shareableProfile() { body["profile"] = profile }
        // Where the phone is (coarse, the app's one fix), so a skill like
        // Weather can answer for here when the field names no place.
        if let lat = s.lastLat, let lon = s.lastLon { body["lat"] = lat; body["lon"] = lon }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = session.dataTask(with: req)
        streams[task.taskIdentifier] = Stream(onToken: onToken, onDone: onDone, onError: onError)
        task.resume()
        log.log("GLYF_RUN start glyf=\(glyfId, privacy: .public)")
        return task
    }

    // MARK: Direct tool runs (§6.11 — keyboard search suite)

    struct ToolRow: Decodable {
        var title: String
        var snippet: String?
        var url: String?
    }

    /// POST /tools/run for the Gboard-style search surface. Keyless tools
    /// only; rows come back as a JSON-array string. Main-queue callbacks.
    @discardableResult
    func runTool(id: String, args: [String: String],
                 onRows: @escaping ([ToolRow]) -> Void,
                 onError: @escaping (String) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/tools/run") else {
            onError("Bad backend URL"); return nil
        }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": id, "args": args, "deviceId": s.deviceId,
        ])
        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard err == nil, let data,
                      let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = outer["result"] as? String,
                      let rows = try? JSONDecoder().decode([ToolRow].self,
                                                           from: Data(result.utf8))
                else {
                    onError("Couldn't search right now"); return
                }
                onRows(rows)
            }
        }
        task.resume()
        return task
    }

    // MARK: Search suite (POST /search — typed cards)

    /// The card model lives in Engine/SearchCard.swift so its paste logic is
    /// unit-testable without linking the networking layer into the tests.
    typealias SearchCard = GlyfKeyboardSearchCard
    typealias SearchResult = GlyfKeyboardSearchResult

    /// POST /search — the Search / YouTube / Maps tabs. Location is sent only
    /// when the app has cached it (onboarding permission); the server keeps
    /// none of it.
    ///
    /// `dark` is the keyboard's theme: a maps search starts drawing its
    /// places' maps in it before the cards ask for them.
    @discardableResult
    func runSearch(vertical: String, query: String, dark: Bool? = nil,
                   onResult: @escaping (SearchResult) -> Void,
                   onError: @escaping (String) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/search") else {
            onError("Bad backend URL"); return nil
        }
        var body: [String: Any] = [
            "vertical": vertical, "query": query, "deviceId": s.deviceId,
        ]
        if let lat = s.lastLat, let lon = s.lastLon { body["lat"] = lat; body["lon"] = lon }
        if let region = s.region, region.count == 2 { body["country"] = region }
        body["tz"] = TimeZone.current.identifier
        if let dark { body["dark"] = dark }

        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: req) { data, response, err in
            DispatchQueue.main.async {
                if let err = err as NSError?, err.code == NSURLErrorCancelled { return }
                if let err {
                    self.log.error("search transport \(err.localizedDescription, privacy: .public)")
                    onError("Couldn't search right now"); return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let data else {
                    self.log.error("search no body http=\(code, privacy: .public)")
                    onError("Couldn't search right now"); return
                }
                do {
                    onResult(try JSONDecoder().decode(SearchResult.self, from: data))
                } catch {
                    self.log.error("search decode http=\(code, privacy: .public) \(String(describing: error), privacy: .public)")
                    onError("Couldn't search right now")
                }
            }
        }
        task.resume()
        return task
    }

    // MARK: Act (POST /act — hold space on what you typed)

    struct RewriteOption: Decodable, Equatable {
        var id: String
        var label: String
        var text: String
    }

    struct ActResult: Decodable {
        var ok: Bool
        var intent: String?
        var title: String?
        var cards: [SearchCard]?
        var text: String?
        var insert: String?
        /// A rewrite's versions (Basic, Professional, Polite…), when offered.
        var options: [RewriteOption]?
        var remaining: Int?
        var error: String?
    }

    /// Hands the typed intent to the server, which routes it (place, list,
    /// answer, video, rewrite) and returns cards plus the text Insert drops.
    struct Translation {
        let detected: String
        let target: String
        let text: String
    }

    /// The person's two languages, as Google Translate would guess them: the
    /// phone's first language, and the other language they actually type in
    /// (the last one detected), else the next on the phone's list, else the
    /// common second language where they live.
    static var translatePair: (primary: String, secondary: String) {
        let names = Locale.preferredLanguages.compactMap { tag -> String? in
            let code = Locale(identifier: tag).language.languageCode?.identifier ?? tag
            return Locale(identifier: "en").localizedString(forLanguageCode: code)
        }
        let primary = names.first ?? "English"
        let fallback = Locale.current.region?.identifier == "IN"
            ? (primary == "Hindi" ? "English" : "Hindi")
            : (primary == "English" ? "Spanish" : "English")
        let typed = SettingsStore.current.translateOther.flatMap { $0 == primary ? nil : $0 }
        let secondary = typed ?? names.dropFirst().first { $0 != primary } ?? fallback
        return (primary, secondary)
    }

    /// POST /translate — detects the language and picks the direction; an
    /// explicit target overrides the direction.
    @discardableResult
    func translate(text: String, target: String?,
                   completion: @escaping (Translation?) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/translate") else { completion(nil); return nil }
        let pair = Self.translatePair
        var body: [String: Any] = [
            "text": text, "deviceId": s.deviceId,
            "primary": pair.primary, "secondary": pair.secondary,
        ]
        if let target { body["target"] = target }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = session.dataTask(with: req) { data, _, _ in
            var out: Translation?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["translation"] as? String,
               let detected = json["detected"] as? String,
               let target = json["target"] as? String {
                out = Translation(detected: detected, target: target, text: text)
            }
            DispatchQueue.main.async {
                // Remember the other language this person types in.
                if let out, out.detected != pair.primary, out.detected != "Unknown",
                   SettingsStore.current.translateOther != out.detected {
                    SettingsStore.update { $0.translateOther = out.detected }
                }
                completion(out)
            }
        }
        task.resume()
        return task
    }

    struct BookingDay { let date: String; let slots: [(start: Date, url: String)] }
    struct BookingSlots {
        let provider: String
        /// The page itself on the chosen day.
        let bookingUrl: String
        let days: [BookingDay]
    }

    /// Open times on a Cal.com link (Calendly gives only its link), from the
    /// chosen day. The error is the server's own words when it has them.
    func bookingSlots(link: String, date: String, days: Int = 1,
                      done: @escaping (BookingSlots?, String?) -> Void) {
        var comps = URLComponents(string: "\(SettingsStore.current.backendURL)/scheduling/slots")
        comps?.queryItems = [
            URLQueryItem(name: "link", value: link), URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "tz", value: TimeZone.current.identifier),
        ]
        guard let url = comps?.url else { return done(nil, nil) }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.timeoutInterval = 12
        session.dataTask(with: req) { data, response, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let json, let provider = json["provider"] as? String,
                  let page = json["bookingUrl"] as? String else {
                DispatchQueue.main.async { done(nil, json?["error"] as? String) }
                return
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let rows = (json["days"] as? [[String: Any]] ?? []).compactMap { d -> BookingDay? in
                guard let date = d["date"] as? String else { return nil }
                let slots = (d["slots"] as? [[String: Any]] ?? []).compactMap { s -> (Date, String)? in
                    guard let start = (s["start"] as? String).flatMap(iso.date(from:)),
                          let u = s["url"] as? String else { return nil }
                    return (start, u)
                }
                return BookingDay(date: date, slots: slots)
            }
            DispatchQueue.main.async { done(BookingSlots(provider: provider, bookingUrl: page, days: rows), nil) }
        }.resume()
    }

    struct Booked { let start: Date?; let meetingUrl: String?; let invited: [String] }

    /// Books a time on a Cal.com page with the attendee and guests; Cal.com
    /// emails everyone the invite. The error is the server's own words.
    func bookSlot(link: String, start: Date, name: String, email: String, guests: [String],
                  done: @escaping (Booked?, String?) -> Void) {
        guard let url = URL(string: "\(SettingsStore.current.backendURL)/scheduling/book") else { return done(nil, nil) }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let iso = ISO8601DateFormatter()
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "link": link, "start": iso.string(from: start), "name": name, "email": email,
            "guests": guests, "tz": TimeZone.current.identifier,
        ])
        session.dataTask(with: req) { data, response, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && json?["ok"] as? Bool == true
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let booked = ok ? Booked(start: (json?["start"] as? String).flatMap { iso2.date(from: $0) ?? iso.date(from: $0) },
                                     meetingUrl: json?["meetingUrl"] as? String,
                                     invited: json?["invited"] as? [String] ?? []) : nil
            DispatchQueue.main.async { done(booked, ok ? nil : json?["error"] as? String) }
        }.resume()
    }

    @discardableResult
    /// POST /suggest — what Glyf could do about what is being typed. Cheap
    /// and cancellable: the strip asks after a pause, never on every key,
    /// and it never spends one of the person's runs.
    func suggestAction(text: String, kinds: [String] = [],
                       onResult: @escaping (String, String, String) -> Void)
    -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/suggest") else { return nil }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": text, "deviceId": s.deviceId]
        // The kinds of detail saved, never the details.
        if !kinds.isEmpty { body["kinds"] = kinds }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = session.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let suggestion = json["suggestion"] as? [String: Any],
                  let intent = suggestion["intent"] as? String,
                  let label = suggestion["label"] as? String
            else { return }
            let query = suggestion["query"] as? String ?? text
            DispatchQueue.main.async { onResult(intent, label, query) }
        }
        task.resume()
        return task
    }

    /// POST /report: flag an AI result (Google Play's AI-Generated Content
    /// policy). `onDone(true)` once the server has it, on the main queue.
    func report(feature: String, result: String, onDone: @escaping (Bool) -> Void) {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/report") else { onDone(false); return }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "deviceId": s.deviceId, "feature": String(feature.prefix(64)),
            "result": String(result.prefix(4000)), "platform": "ios",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req) { _, response, _ in
            let ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
            DispatchQueue.main.async { onDone(ok) }
        }.resume()
    }

    /// POST /act as a stream: each version of a rewrite the moment the model
    /// finishes it, written text as it comes, then the whole result. A
    /// `reset` means the model was swapped midway: drop what was shown.
    /// Callbacks arrive on the main queue.
    func runAct(text: String,
                intent: String? = nil,
                onOption: @escaping (RewriteOption) -> Void,
                onText: @escaping (String) -> Void,
                onReset: @escaping () -> Void,
                onResult: @escaping (ActResult) -> Void,
                onError: @escaping (String) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/act") else {
            onError("Bad backend URL"); return nil
        }
        var body: [String: Any] = [
            "text": text, "deviceId": s.deviceId, "plan": s.plan ?? "free",
            "tz": TimeZone.current.identifier, "stream": true,
        ]
        if let lat = s.lastLat, let lon = s.lastLon { body["lat"] = lat; body["lon"] = lon }
        if let region = s.region, region.count == 2 { body["country"] = region }
        if let profile = Self.shareableProfile() { body["profile"] = profile }
        if let intent { body["intent"] = intent }

        var req = URLRequest(url: url)
        req.glyfSession()
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let failed = "Couldn't do that right now. Tap to retry."
        let task = session.dataTask(with: req)
        var stream = Stream(onToken: { _ in }, onDone: { _, _ in }, onError: onError)
        stream.onAct = { [weak self] type, data in
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            switch type {
            case "option":
                if let option = try? JSONDecoder().decode(RewriteOption.self, from: data) { onOption(option) }
            case "text":
                if let t = obj?["t"] as? String { onText(t) }
            case "reset":
                onReset()
            case "done":
                guard let out = try? JSONDecoder().decode(ActResult.self, from: data) else {
                    self?.log.error("act done unreadable")
                    return onError(failed)
                }
                if let remaining = out.remaining { GlyfCatalog.cacheRunsRemaining(remaining) }
                onResult(out)
            case "error":
                onError(obj?["error"] as? String ?? failed)
            default:
                break
            }
        }
        streams[task.taskIdentifier] = stream
        task.resume()
        return task
    }

    /// GET /search/suggest — the landing state for a tab (trending searches,
    /// popular videos, nearby places). The user's own recents are local and
    /// never travel.
    @discardableResult
    func runSuggest(vertical: String,
                    onResult: @escaping (SearchResult) -> Void,
                    onError: @escaping (String) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        var items = [
            URLQueryItem(name: "vertical", value: vertical),
            URLQueryItem(name: "deviceId", value: s.deviceId),
        ]
        if let region = s.region, region.count == 2 {
            items.append(URLQueryItem(name: "country", value: region))
        }
        if let lat = s.lastLat, let lon = s.lastLon {
            items.append(URLQueryItem(name: "lat", value: String(lat)))
            items.append(URLQueryItem(name: "lon", value: String(lon)))
        }
        guard var comps = URLComponents(string: "\(s.backendURL)/search/suggest") else {
            onError("Bad backend URL"); return nil
        }
        comps.queryItems = items
        guard let url = comps.url else { onError("Bad backend URL"); return nil }

        var req = URLRequest(url: url)
        req.glyfSession()
        req.timeoutInterval = 12
        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err = err as NSError?, err.code == NSURLErrorCancelled { return }
                guard err == nil, let data,
                      let out = try? JSONDecoder().decode(SearchResult.self, from: data)
                else { onError(""); return }
                onResult(out)
            }
        }
        task.resume()
        return task
    }

    // MARK: SSE parsing

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var stream = streams[dataTask.taskIdentifier] else { return }
        stream.buffer.append(data)
        let separator = Data("\n\n".utf8)
        while let range = stream.buffer.range(of: separator) {
            let event = String(decoding: stream.buffer.subdata(in: stream.buffer.startIndex..<range.lowerBound),
                               as: UTF8.self)
            stream.buffer = stream.buffer.subdata(in: range.upperBound..<stream.buffer.endIndex)
            handle(event: event, stream: &stream)
        }
        streams[dataTask.taskIdentifier] = stream
    }

    private func handle(event: String, stream: inout Stream) {
        var type = "message"
        var payload = ""
        for line in event.split(separator: "\n") {
            if line.hasPrefix("event:") {
                type = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                payload += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let onAct = stream.onAct {
            if type == "done" || type == "error" { stream.finished = true }
            onAct(type, data)
            return
        }

        switch type {
        case "token":
            let t = obj["t"] as? String ?? ""
            stream.fullText += t
            stream.onToken(t)
        case "done":
            stream.finished = true
            let text = obj["text"] as? String ?? stream.fullText
            let remaining = obj["remaining"] as? Int
            if let remaining { GlyfCatalog.cacheRunsRemaining(remaining) }
            stream.onDone(text, remaining)
        case "error":
            stream.finished = true
            stream.onError(obj["message"] as? String ?? "Something went wrong")
        default:
            break
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let stream = streams.removeValue(forKey: task.taskIdentifier) else { return }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            log.log("GLYF_RUN transport error: \(error.localizedDescription, privacy: .public)")
            if !stream.finished { stream.onError("Couldn't reach Glyf. Tap to retry.") }
        } else if !stream.finished {
            // A refusal before the stream opened (the day's runs, a lost
            // session, too many at once) is one JSON body: say what the
            // server said, for every kind of run.
            if let obj = try? JSONSerialization.jsonObject(with: stream.buffer) as? [String: Any],
               let message = (obj["error"] as? String) ?? (obj["message"] as? String) {
                stream.onError(message)
            } else if let http = task.response as? HTTPURLResponse, http.statusCode == 429 {
                stream.onError("Daily free runs used up")
            } else {
                stream.onError("Couldn't reach Glyf. Tap to retry.")
            }
        }
    }

    // MARK: Meter (§6.16)

    func fetchRemaining(completion: @escaping (Int?) -> Void) {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/meter/\(s.deviceId)") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.glyfSession()   // the meter is per account now, and the gate wants it
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var n: Int?
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                n = obj["remaining"] as? Int
            }
            DispatchQueue.main.async {
                if let n { GlyfCatalog.cacheRunsRemaining(n) }
                completion(n)
            }
        }.resume()
    }
}


extension URLRequest {
    /// The server turns away anyone without a session, so every call from the
    /// keyboard carries the one the app signed in with.
    mutating func glyfSession() {
        if let token = GlyfSession.token() {
            setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
