import Foundation

/// The server and Google calls Glyf's App Intents make from the app's
/// process (Shortcuts, Siri, the widgets' buttons), with the session the
/// app signed in with (GlyfSession, the shared keychain) and the settings
/// the keyboard uses (backend, device id, plan, Private AI).
enum GlyfIntentAPI {
    private static func request(_ path: String, body: [String: Any]) throws -> URLRequest {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)\(path)") else { throw GlyfIntentError.failed("Bad server address") }
        guard let token = GlyfSession.token() else { throw GlyfIntentError.signedOut }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        // As the keyboard's calls carry them (BackendClient's glyfSession()).
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let on = s.privateAI { req.setValue(on ? "0g" : "off", forHTTPHeaderField: "X-Glyf-AI") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var b = body
        b["deviceId"] = s.deviceId
        b["plan"] = s.plan ?? "free"
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        return req
    }

    /// POST /act with intent rewrite, in one reply (no stream).
    static func rewrite(_ text: String, style: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlyfIntentError.failed("Nothing to rewrite") }
        let req = try request("/act", body: [
            "text": String(trimmed.prefix(2000)), "intent": "rewrite", "tz": TimeZone.current.identifier,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return try GlyfIntentParsing.pickRewrite(json, style: style)
    }

    static func runGlyf(_ id: String, input: String) async throws -> String {
        var req = try request("/glyf/run", body: ["glyfId": id, "input": String(input.prefix(4000)), "vars": [String: String]()])
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try GlyfIntentParsing.streamText(String(decoding: data, as: UTF8.self))
    }
}

/// A Meet link of the person's own, made on the phone with the Google grant
/// the keyboard uses (GoogleAccess): nothing goes through Glyf's server.
enum GlyfMeetLink {
    static func make() async throws -> String {
        guard GoogleAccess.hasMeet, let grant = GoogleAccess.load() else { throw GlyfIntentError.meetNotConnected }
        var tokenURL = "https://oauth2.googleapis.com/token"
        var spacesURL = "https://meet.googleapis.com/v2/spaces"
        #if DEBUG
        if let base = grant.apiBase, !base.isEmpty {
            tokenURL = "\(base)/token"
            spacesURL = "\(base)/v2/spaces"
        }
        #endif
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        var tokenReq = URLRequest(url: URL(string: tokenURL)!)
        tokenReq.httpMethod = "POST"
        tokenReq.timeoutInterval = 10
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenReq.httpBody = ["client_id": grant.clientId, "refresh_token": grant.refreshToken, "grant_type": "refresh_token"]
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (tokenData, _) = try await URLSession.shared.data(for: tokenReq)
        let tokenJSON = (try? JSONSerialization.jsonObject(with: tokenData)) as? [String: Any]
        guard let token = tokenJSON?["access_token"] as? String else {
            throw tokenJSON?["error"] as? String == "invalid_grant" ? GlyfIntentError.reconnectGoogle
                : GlyfIntentError.failed("Google didn't answer")
        }
        var req = URLRequest(url: URL(string: spacesURL)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let uri = json?["meetingUri"] as? String, uri.hasPrefix("https://") else {
            throw GlyfIntentError.failed("Google didn't make a link")
        }
        return uri
    }
}
