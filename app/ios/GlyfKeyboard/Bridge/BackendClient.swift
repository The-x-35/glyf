import Foundation
import os.log

/// Keyboard → backend. Requires Full Access (§1.3 — network is gated).
/// Streams /glyf/run as SSE so tokens render as they arrive (§6.4).
/// NEVER holds provider keys; the backend owns OpenRouter (§1.6).
final class BackendClient: NSObject, URLSessionDataDelegate {

    static let shared = BackendClient()
    private let log = Logger(subsystem: "so.glyf.keyboard", category: "backend")

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }()

    private struct Stream {
        var buffer = ""
        var onToken: (String) -> Void
        var onDone: (String, Int?) -> Void
        var onError: (String) -> Void
        var fullText = ""
        var finished = false
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
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // §6.15: the tone profile rides along as a var — prompts opt in with
        // {{toneHint}}; it's "" until ≥3 net accepts teach us something.
        var mergedVars = vars
        if mergedVars["toneHint"] == nil {
            mergedVars["toneHint"] = ToneProfile.currentHint()
        }
        let body: [String: Any] = [
            "glyfId": glyfId,
            "input": input,
            "vars": mergedVars,
            "deviceId": s.deviceId,
            "pro": s.proUnlocked ?? false, // legacy flag, still honored
            "plan": s.plan ?? "free",      // §6.16 (receipt validation: M7-ship)
        ]
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
    @discardableResult
    func runSearch(vertical: String, query: String,
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

        var req = URLRequest(url: url)
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

    struct ActResult: Decodable {
        var ok: Bool
        var intent: String?
        var title: String?
        var cards: [SearchCard]?
        var text: String?
        var insert: String?
        var remaining: Int?
        var error: String?
    }

    /// Hands the typed intent to the server, which routes it (place, list,
    /// answer, video, rewrite) and returns cards plus the text Insert drops.
    @discardableResult
    func runAct(text: String,
                onResult: @escaping (ActResult) -> Void,
                onError: @escaping (String) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/act") else {
            onError("Bad backend URL"); return nil
        }
        var body: [String: Any] = [
            "text": text, "deviceId": s.deviceId, "plan": s.plan ?? "free",
            "tz": TimeZone.current.identifier,
        ]
        if let lat = s.lastLat, let lon = s.lastLon { body["lat"] = lat; body["lon"] = lon }
        if let region = s.region, region.count == 2 { body["country"] = region }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: req) { data, response, err in
            DispatchQueue.main.async {
                if let err = err as NSError?, err.code == NSURLErrorCancelled { return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard err == nil, let data,
                      let out = try? JSONDecoder().decode(ActResult.self, from: data) else {
                    self.log.error("act failed http=\(code, privacy: .public)")
                    onError("Couldn't reach Glyf. Tap to retry.")
                    return
                }
                if let remaining = out.remaining { GlyfCatalog.cacheRunsRemaining(remaining) }
                if out.ok { onResult(out) } else { onError(out.error ?? "Couldn't do that right now. Tap to retry.") }
            }
        }
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
        guard var stream = streams[dataTask.taskIdentifier],
              let chunk = String(data: data, encoding: .utf8) else { return }
        stream.buffer += chunk
        while let range = stream.buffer.range(of: "\n\n") {
            let event = String(stream.buffer[..<range.lowerBound])
            stream.buffer.removeSubrange(..<range.upperBound)
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
            if let http = task.response as? HTTPURLResponse, http.statusCode == 429 {
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
        URLSession.shared.dataTask(with: url) { data, _, _ in
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
