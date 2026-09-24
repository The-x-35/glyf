import Foundation
import Security

/// What the person let Glyf do with their Google account: make Meet links
/// and add events to their Google Calendar (whose guests Google emails).
/// The grant comes from signing in with Google, or from Connected tools,
/// and lives in the keychain group the app and the keyboard share, beside
/// the Glyf session. It never leaves the phone: the keyboard talks to Google
/// itself, so Glyf's server never sees anyone's calendar.
struct GoogleGrant: Codable, Equatable {
    var refreshToken: String
    /// The iOS client the refresh token was issued to; refreshing needs it.
    var clientId: String
    /// What the person allowed. Google lets them untick either one.
    var scopes: [String]
    var email: String?
    /// Debug builds only: a stand-in for Google's APIs (qa/fake-google.mjs).
    var apiBase: String?
}

enum GoogleAccess {
    /// Events on calendars the person owns: the narrowest write scope, and
    /// the one that also makes a Meet link for an event.
    static let calendarScope = "https://www.googleapis.com/auth/calendar.events.owned"
    /// Meet links on their own (Meet REST API, spaces the app created).
    static let meetScope = "https://www.googleapis.com/auth/meetings.space.created"
    static let scopes = [calendarScope, meetScope]

    private static let service = "so.glyf.google"
    private static let account = "grant-v1"

    private static var base: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group = GlyfSession.group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    static func load() -> GoogleGrant? {
        var query = base
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleGrant.self, from: data)
    }

    @discardableResult
    static func save(_ grant: GoogleGrant) -> Bool {
        clear()
        guard let data = try? JSONEncoder().encode(grant) else { return false }
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }

    static var hasCalendar: Bool { load()?.scopes.contains(calendarScope) == true }
    static var hasMeet: Bool { load()?.scopes.contains(meetScope) == true }

    /// The scopes Google says it granted, out of the token response's
    /// space-separated `scope`, keeping only the ones Glyf asks for.
    static func granted(_ scope: String?) -> [String] {
        let said = Set((scope ?? "").split(separator: " ").map(String.init))
        return scopes.filter { said.contains($0) }
    }
}
