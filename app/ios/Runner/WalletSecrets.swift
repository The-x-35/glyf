import Foundation
import Security

/// The wallet link's secrets: Phantom's session for Glyf and our half of the
/// encryption its deeplinks use, and the Glyf wallet's Ethereum key, in the
/// Keychain on this device only. The vault backup's secret is the one item
/// saved with `sync`: iCloud Keychain carries it to the person's next phone,
/// which is how that phone finds and opens the backup on Arkiv.
enum WalletSecrets {
    private static let service = "so.glyf.wallet"

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name,
         kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
    }

    static func load(_ name: String) -> String? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ name: String, _ value: String, sync: Bool = false) -> Bool {
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query(name) as CFDictionary, update as CFDictionary) == errSecSuccess { return true }
        var add = query(name)
        add[kSecValueData as String] = data
        add[kSecAttrSynchronizable as String] = sync
        add[kSecAttrAccessible as String] = sync
            ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func clear(_ name: String) {
        SecItemDelete(query(name) as CFDictionary)
    }
}
