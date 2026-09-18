import Foundation
import Security

/// The Glyf session, shared by the app and the keyboard.
///
/// The server now wants it on every call, and the keyboard makes most of
/// them, so the token lives in the keychain group both targets carry
/// (`$(AppIdentifierPrefix)so.glyf.shared`) rather than in the app's own.
/// The app writes it at sign-in and clears it at sign-out; the keyboard only
/// ever reads it.
enum GlyfSession {
    private static let service = "so.glyf.session"
    private static let account = "session-v1"

    /// The access group both targets share. It carries the team prefix, which
    /// differs between a personal build and a team one, so it is learned from
    /// the keychain itself rather than hard-coded. nil means "this build has
    /// no group" (the simulator, where every item is reachable anyway).
    private static let group: String? = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "so.glyf.group-probe",
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("probe".utf8),
            kSecReturnAttributes as String: true,
        ]
        var out: CFTypeRef?
        var status = SecItemAdd(probe as CFDictionary, &out)
        if status == errSecDuplicateItem {
            var lookup = probe
            lookup.removeValue(forKey: kSecValueData as String)
            status = SecItemCopyMatching(lookup as CFDictionary, &out)
        }
        guard status == errSecSuccess,
              let attrs = out as? [String: Any],
              let found = attrs[kSecAttrAccessGroup as String] as? String else { return nil }
        return found.hasSuffix(".so.glyf.shared") ? found : nil
    }()

    private static var base: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    /// The stored session JSON, or nil when nobody is signed in.
    static func loadJSON() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Just the bearer token, and only while it is still good: an expired one
    /// would be refused anyway, and sending it would only burn a request.
    static func token(now: Date = Date()) -> String? {
        guard let json = loadJSON(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String, !token.isEmpty else { return nil }
        return expired(token, now: now) ? nil : token
    }

    /// Reads `exp` out of the session's own claims. A token we can't read is
    /// left to the server to judge.
    private static func expired(_ token: String, now: Date) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double else { return false }
        return Date(timeIntervalSince1970: exp) <= now
    }

    @discardableResult
    static func save(_ json: String) -> Bool {
        clear()
        var query = base
        query[kSecValueData as String] = Data(json.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
        // A session written before the move to the shared group would outlive
        // sign-out; take that one too.
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
