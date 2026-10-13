import Foundation

/// mail.tm, asked by the phone itself (shared/tempmail/RULES.md). Free and
/// keyless; its terms forbid putting its API behind another domain, so no
/// Glyf server sits in between and a mail never passes through Glyf. Nothing
/// here logs an address, a sender, a subject or a code, and nothing it
/// fetches is cached: a mail's words never reach the disk.
struct MailTM {
    static let defaultBase = "https://api.mail.tm"

    /// What came back. Status 0 is no answer at all (no connection, a
    /// timeout).
    struct Reply {
        let status: Int
        let json: Any?

        var object: [String: Any]? { json as? [String: Any] }
        /// A list: plain with `Accept: application/json`, JSON-LD's
        /// `hydra:member` otherwise.
        var list: [[String: Any]]? {
            json as? [[String: Any]] ?? object?["hydra:member"] as? [[String: Any]]
        }
    }

    /// No cache and no cookies: the inbox is asked fresh every time, and its
    /// answers stay in memory.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    let base: String

    /// `base` is the setting `tempMailBase` (a stand-in, in tests), else
    /// mail.tm itself.
    init(base: String?) {
        #if DEBUG
        let given = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        // A shipped build sends the inbox login to mail.tm only.
        let given = ""
        #endif
        var b = given.isEmpty ? Self.defaultBase : given
        while b.hasSuffix("/") { b.removeLast() }
        self.base = b
    }

    /// One call. Answers on the main queue.
    func call(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil,
              done: @escaping (Reply) -> Void) {
        guard let url = URL(string: base + path) else {
            return DispatchQueue.main.async { done(Reply(status: 0, json: nil)) }
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        Self.session.dataTask(with: req) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { $0.isEmpty ? nil : try? JSONSerialization.jsonObject(with: $0) }
            DispatchQueue.main.async { done(Reply(status: status, json: json)) }
        }.resume()
    }

    /// A made address and what reads it.
    struct Account {
        let address: String
        let password: String
        let token: String
        let id: String
    }

    /// A new address: a random active public domain, a free name on it (422
    /// means taken: another name, three tries in all) and the token that
    /// reads it. The failing reply otherwise, for what to tell the person.
    func create(done: @escaping (Result<Account, Failure>) -> Void) {
        call("GET", "/domains") { reply in
            let domains = (reply.list ?? []).filter {
                $0["isActive"] as? Bool != false && $0["isPrivate"] as? Bool != true
            }.compactMap { $0["domain"] as? String }
            guard reply.status == 200, let domain = domains.randomElement() else {
                return done(.failure(Failure(status: reply.status)))
            }
            register(domain: domain, tries: 3, done: done)
        }
    }

    struct Failure: Error {
        let status: Int
    }

    private func register(domain: String, tries: Int, done: @escaping (Result<Account, Failure>) -> Void) {
        let address = TempMailRules.newAddress(domain: domain)
        let password = TempMailRules.newPassword()
        call("POST", "/accounts", body: ["address": address, "password": password]) { reply in
            if reply.status == 422, tries > 1 { return register(domain: domain, tries: tries - 1, done: done) }
            guard reply.status == 200 || reply.status == 201, let id = reply.object?["id"] as? String else {
                return done(.failure(Failure(status: reply.status)))
            }
            call("POST", "/token", body: ["address": address, "password": password]) { reply in
                guard reply.status == 200, let token = reply.object?["token"] as? String else {
                    return done(.failure(Failure(status: reply.status)))
                }
                done(.success(Account(address: address, password: password, token: token,
                                      id: reply.object?["id"] as? String ?? id)))
            }
        }
    }

    /// A call made with an address's token. A 401 takes a new one with its
    /// password and tries once more; `gone` is the second 401, when the
    /// address no longer exists. `fresh` is the new token, when one was taken.
    func authed(_ method: String, _ path: String, address: String, password: String, token: String,
                done: @escaping (_ reply: Reply, _ gone: Bool, _ fresh: String?) -> Void) {
        call(method, path, token: token) { reply in
            guard reply.status == 401 else { return done(reply, false, nil) }
            call("POST", "/token", body: ["address": address, "password": password]) { taken in
                guard taken.status == 200, let token = taken.object?["token"] as? String else {
                    return done(taken, taken.status == 401, nil)
                }
                call(method, path, token: token) { again in
                    done(again, again.status == 401, token)
                }
            }
        }
    }
}
