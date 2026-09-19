import CryptoKit
import Foundation
import Security

/// §6.7 Vault: preset personal info + shorthand snippets + multi-field combos.
/// Encrypted at rest (AES-GCM) in the App Group; the key lives in the shared
/// Keychain group so both processes decrypt, and NEVER in the App Group.
/// Add/edit happens in the APP only (§6.3); the keyboard reads + inserts.

struct VaultField: Codable, Equatable, Identifiable {
    var id: String
    var kind: String      // name email phone address upi gst wallet link social bio reply custom
    var label: String
    var value: String
}

struct VaultCombo: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var fieldIds: [String]
}

struct VaultSnippet: Codable, Equatable {
    var trigger: String   // ";addr" — must start with ';'
    var text: String
}

/// A picture kept in the vault. Only the description lives in the vault file;
/// the pixels are a separate encrypted file, so opening the vault to read a
/// phone number never decrypts megabytes of screenshots.
struct VaultImage: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var addedAt: Date
    var bytes: Int
}

struct Vault: Codable, Equatable {
    var fields: [VaultField] = []
    var combos: [VaultCombo] = []
    var snippets: [VaultSnippet] = []
    var images: [VaultImage] = []
}

/// §6.7/§11.3 hard blocks — pure logic, unit-tested.
enum VaultRules {
    static let allowedKinds: Set<String> = [
        "name", "email", "phone", "address", "upi", "gst", "wallet",
        "link", "social", "bio", "reply", "custom",
    ]

    /// Returns a human refusal reason, or nil when the value is storable.
    static func refusalReason(kind: String, label: String, value: String) -> String? {
        guard allowedKinds.contains(kind) else {
            return "That field type isn't supported"
        }
        let lowerLabel = label.lowercased()
        if ["password", "passcode", "pin", "otp", "cvv", "seed", "private key",
            "recovery"].contains(where: lowerLabel.contains) {
            return "Glyf never stores passwords, PINs, or recovery secrets — use your password manager"
        }
        switch SecretScanner.scan(value) {
        case .cardNumber:
            return "Card numbers can't be stored in the vault"
        case .seedPhrase:
            return "That looks like a seed phrase — Glyf will never store one"
        case .privateKeyOrToken:
            return "Private keys and API tokens can't be stored in the vault"
        case .otpCode:
            return "One-time codes aren't worth saving"
        case .clean:
            break
        }
        if looksLikeGovernmentId(value) {
            return "Government ID numbers can't be stored in the vault"
        }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Nothing to save"
        }
        if value.count > 2000 {
            return "Too long — vault entries cap at 2000 characters"
        }
        return nil
    }

    /// Aadhaar (12 digits), PAN (AAAAA9999A), US SSN (xxx-xx-xxxx).
    static func looksLikeGovernmentId(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        let digits = v.filter(\.isNumber)
        if digits.count == 12, v.allSatisfy({ $0.isNumber || $0 == " " }) { return true }
        if v.range(of: #"^[A-Z]{5}[0-9]{4}[A-Z]$"#, options: .regularExpression) != nil {
            return true
        }
        if v.range(of: #"^\d{3}-\d{2}-\d{4}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func snippetRefusal(trigger: String, text: String) -> String? {
        guard trigger.hasPrefix(";"), trigger.count >= 2, trigger.count <= 12,
              !trigger.dropFirst().contains(where: { $0 == " " || $0 == ";" })
        else { return "Triggers look like ;sig — a semicolon plus a short word" }
        return refusalReason(kind: "custom", label: "snippet", value: text)
    }
}

final class VaultStore {
    static let shared = VaultStore()
    static let fileName = "vault.enc"

    private let baseDir: URL?
    private let fixedKey: SymmetricKey?  // tests inject a key; prod uses Keychain
    private var cached: Vault?

    init(baseDir: URL? = nil, key: SymmetricKey? = nil) {
        self.baseDir = baseDir
        self.fixedKey = key
    }

    private var root: URL? { baseDir ?? AppGroupStore.bridgeDir }

    // MARK: - Key management (shared Keychain group)

    private static let keychainService = "so.glyf.vault"
    private static let keychainAccount = "vault-key-v1"

    private func loadOrCreateKey() -> SymmetricKey? {
        if let fixedKey { return fixedKey }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        query.removeValue(forKey: kSecReturnData as String)
        query[kSecValueData as String] = keyData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return key }
        if status == errSecDuplicateItem { return loadOrCreateKey() }
        return nil
    }

    // MARK: - Load / save

    func load() -> Vault {
        if let cached { return cached }
        guard let root, let key = loadOrCreateKey(),
              let blob = try? Data(contentsOf: root.appendingPathComponent(Self.fileName)),
              let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key),
              let vault = try? JSONDecoder().decode(Vault.self, from: plain)
        else {
            let empty = Vault()
            cached = empty
            return empty
        }
        cached = vault
        return vault
    }

    @discardableResult
    func save(_ vault: Vault) -> Bool {
        guard let root, let key = loadOrCreateKey(),
              let plain = try? JSONEncoder().encode(vault),
              let box = try? AES.GCM.seal(plain, using: key),
              let blob = box.combined
        else { return false }
        do {
            try blob.write(to: root.appendingPathComponent(Self.fileName), options: .atomic)
            cached = vault
            return true
        } catch { return false }
    }

    func invalidate() { cached = nil }

    // MARK: - Mutations (validated — the blocked types are BLOCKED, §6.7)

    /// Returns a refusal reason, or nil on success.
    func upsertField(id: String?, kind: String, label: String, value: String) -> String? {
        if let reason = VaultRules.refusalReason(kind: kind, label: label, value: value) {
            return reason
        }
        var vault = load()
        if let id, let i = vault.fields.firstIndex(where: { $0.id == id }) {
            vault.fields[i] = VaultField(id: id, kind: kind, label: label, value: value)
        } else {
            vault.fields.append(VaultField(
                id: UUID().uuidString.lowercased(), kind: kind, label: label, value: value))
        }
        return save(vault) ? nil : "Could not save the vault"
    }

    func deleteField(id: String) {
        var vault = load()
        vault.fields.removeAll { $0.id == id }
        for i in vault.combos.indices {
            vault.combos[i].fieldIds.removeAll { $0 == id }
        }
        vault.combos.removeAll { $0.fieldIds.isEmpty }
        save(vault)
    }

    func upsertCombo(id: String?, label: String, fieldIds: [String]) -> String? {
        guard !fieldIds.isEmpty else { return "Pick at least one field" }
        var vault = load()
        let known = Set(vault.fields.map(\.id))
        let ids = fieldIds.filter(known.contains)
        guard !ids.isEmpty else { return "Those fields no longer exist" }
        if let id, let i = vault.combos.firstIndex(where: { $0.id == id }) {
            vault.combos[i] = VaultCombo(id: id, label: label, fieldIds: ids)
        } else {
            vault.combos.append(VaultCombo(
                id: UUID().uuidString.lowercased(), label: label, fieldIds: ids))
        }
        return save(vault) ? nil : "Could not save the vault"
    }

    func deleteCombo(id: String) {
        var vault = load()
        vault.combos.removeAll { $0.id == id }
        save(vault)
    }

    func upsertSnippet(trigger: String, text: String) -> String? {
        if let reason = VaultRules.snippetRefusal(trigger: trigger, text: text) {
            return reason
        }
        var vault = load()
        vault.snippets.removeAll { $0.trigger == trigger }
        vault.snippets.append(VaultSnippet(trigger: trigger, text: text))
        return save(vault) ? nil : "Could not save the vault"
    }

    func deleteSnippet(trigger: String) {
        var vault = load()
        vault.snippets.removeAll { $0.trigger == trigger }
        save(vault)
    }

    // MARK: - Images

    static let imagesDirName = "vault-images"
    static let maxImages = 40
    /// Per picture, after re-encoding. A screenshot lands far under this;
    /// the cap is what stops a photo library being poured into the vault.
    static let maxImageBytes = 6 * 1024 * 1024

    private var imagesDir: URL? {
        guard let root else { return nil }
        let dir = root.appendingPathComponent(Self.imagesDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Stores already-encoded image bytes. Returns a refusal reason, or nil.
    /// The bytes are sealed with the same key as the rest of the vault — a
    /// picture of a boarding pass deserves what a phone number gets.
    func addImage(data: Data, label: String = "Image") -> String? {
        guard !data.isEmpty else { return "That image is empty" }
        guard data.count <= Self.maxImageBytes else {
            return "That image is too large to keep"
        }
        var vault = load()
        guard vault.images.count < Self.maxImages else {
            return "The vault holds \(Self.maxImages) images — delete one first"
        }
        guard let dir = imagesDir, let key = loadOrCreateKey(),
              let box = try? AES.GCM.seal(data, using: key), let blob = box.combined
        else { return "Could not save the image" }
        let id = UUID().uuidString.lowercased()
        do {
            try blob.write(to: dir.appendingPathComponent("\(id).enc"), options: .atomic)
        } catch { return "Could not save the image" }
        vault.images.insert(
            VaultImage(id: id, label: label, addedAt: Date(), bytes: data.count), at: 0)
        guard save(vault) else {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).enc"))
            return "Could not save the vault"
        }
        return nil
    }

    /// The decrypted bytes, read only when something actually shows the image.
    func imageData(id: String) -> Data? {
        guard let dir = imagesDir, let key = loadOrCreateKey(),
              let blob = try? Data(contentsOf: dir.appendingPathComponent("\(id).enc")),
              let box = try? AES.GCM.SealedBox(combined: blob)
        else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    func deleteImage(id: String) {
        var vault = load()
        vault.images.removeAll { $0.id == id }
        save(vault)
        if let dir = imagesDir {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).enc"))
        }
    }

    // MARK: - Reads for insertion

    /// One combo = its fields' values joined line-by-line ("Shipping block").
    func comboText(_ combo: VaultCombo) -> String {
        let vault = load()
        let byId = Dictionary(uniqueKeysWithValues: vault.fields.map { ($0.id, $0) })
        return combo.fieldIds.compactMap { byId[$0]?.value }.joined(separator: "\n")
    }
}

/// §6.7 Shorthand: `;sig`-style prefix triggers, expanded inline on commit.
/// Predictable beats clever — exact trigger match only.
enum Shorthand {
    /// The token the user just finished typing (last run of non-space chars).
    static func pendingToken(beforeContext: String?) -> String? {
        guard let ctx = beforeContext, !ctx.isEmpty else { return nil }
        let token = WordTrackerTokenTail(ctx)
        guard token.hasPrefix(";"), token.count >= 2, token.count <= 12 else { return nil }
        return token
    }

    private static func WordTrackerTokenTail(_ ctx: String) -> String {
        var token = ""
        for ch in ctx.reversed() {
            if ch == " " || ch == "\n" || ch == "\t" { break }
            token.insert(ch, at: token.startIndex)
            if token.count > 14 { break }
        }
        return token
    }

    static func expansion(for token: String, in vault: Vault) -> String? {
        vault.snippets.first { $0.trigger == token }?.text
    }
}
