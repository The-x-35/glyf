import CryptoKit
import XCTest

/// §10.9 "vault blocked-field rules" + encryption round-trip + shorthand.
final class VaultTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func store(key: SymmetricKey = SymmetricKey(size: .bits256)) -> VaultStore {
        VaultStore(baseDir: tmp, key: key)
    }

    // MARK: A vault written before a field existed still opens

    /// Adding a property to `Vault` must never empty vaults written before
    /// it. The synthesized decoder does not use default values, so a missing
    /// key throws, `load()` swallows it and returns nothing — and the next
    /// save writes that nothing back. `images` shipped exactly that bug.
    func testVaultWrittenWithoutNewerKeysStillDecodes() throws {
        let key = SymmetricKey(size: .bits256)
        // A vault file from before `images` existed: the key is simply absent.
        let old = #"{"fields":[{"id":"1","kind":"name","label":"Name","value":"Arpit Singh"}],"combos":[],"snippets":[]}"#
        let sealed = try AES.GCM.seal(Data(old.utf8), using: key)
        try sealed.combined!.write(to: tmp.appendingPathComponent(VaultStore.fileName))

        let s = store(key: key)
        let vault = s.load()
        XCTAssertEqual(vault.fields.count, 1, "an older vault must still open")
        XCTAssertEqual(vault.fields.first?.value, "Arpit Singh")
        XCTAssertTrue(vault.images.isEmpty)
        XCTAssertFalse(s.loadFailed)
    }

    /// A vault that exists but cannot be read must never be saved over.
    func testUnreadableVaultIsNeverOverwritten() throws {
        let url = tmp.appendingPathComponent(VaultStore.fileName)
        try Data("not a sealed box".utf8).write(to: url)
        let before = try Data(contentsOf: url)

        let s = store()
        XCTAssertTrue(s.load().fields.isEmpty)
        XCTAssertTrue(s.loadFailed, "an unreadable vault is not an empty one")
        XCTAssertFalse(s.save(Vault()), "refuses to write over it")
        XCTAssertNotNil(s.upsertField(id: nil, kind: "name", label: "N", value: "V"),
                        "an edit is refused rather than silently losing the vault")
        XCTAssertEqual(try Data(contentsOf: url), before, "bytes untouched")
    }

    /// A vault sealed with a key that is gone for good (the Keychain group
    /// moved with a new signing team, or a phone was restored without it)
    /// can never be opened. It is moved aside and a new vault starts, instead
    /// of every save being refused forever. The real Keychain path, under a
    /// service of its own.
    func testVaultWhoseKeyIsGoneIsSetAside() throws {
        let service = "glyf.test.vault.\(UUID().uuidString)"
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: service] as CFDictionary)
        }
        let old = #"{"fields":[{"id":"1","kind":"name","label":"Name","value":"Gone"}],"combos":[],"snippets":[]}"#
        let sealed = try AES.GCM.seal(Data(old.utf8), using: SymmetricKey(size: .bits256))
        try sealed.combined!.write(to: tmp.appendingPathComponent(VaultStore.fileName))

        let s = VaultStore(baseDir: tmp, keychainService: service)
        XCTAssertTrue(s.load().fields.isEmpty)
        XCTAssertFalse(s.loadFailed, "a vault nothing can open doesn't block a new one")
        XCTAssertNil(s.upsertField(id: nil, kind: "name", label: "Name", value: "Sam"))
        XCTAssertEqual(VaultStore(baseDir: tmp, keychainService: service).load().fields.first?.value, "Sam",
                       "the new vault opens with the new key")
        let aside = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
            .filter { $0.hasPrefix("\(VaultStore.fileName).unreadable-") }
        XCTAssertEqual(aside.count, 1, "the old file is kept, only moved")
    }

    // MARK: Blocked types are BLOCKED (§6.7, §11.3)

    func testBlockedFieldTypes() {
        XCTAssertNotNil(VaultRules.refusalReason(
            kind: "custom", label: "My password", value: "hunter2"))
        XCTAssertNotNil(VaultRules.refusalReason(
            kind: "custom", label: "Visa", value: "4242 4242 4242 4242"))
        XCTAssertNotNil(VaultRules.refusalReason(
            kind: "custom", label: "backup",
            value: "legal winner thank year wave sausage worth useful legal winner thank yellow"))
        XCTAssertNotNil(VaultRules.refusalReason(
            kind: "custom", label: "aadhaar", value: "2345 6789 0123"))
        XCTAssertNotNil(VaultRules.refusalReason(
            kind: "custom", label: "pan", value: "ABCDE1234F"))
        XCTAssertNotNil(VaultRules.refusalReason(
            kind: "custom", label: "ssn", value: "123-45-6789"))
        XCTAssertNotNil(VaultRules.refusalReason(
            kind: "custom", label: "api", value: "sk-or-v1-aaaaaaaaaaaaaaaaaaaa"))
    }

    func testAllowedFields() {
        XCTAssertNil(VaultRules.refusalReason(
            kind: "address", label: "Home",
            value: "42 Glass Lane, Indiranagar, Bengaluru 560038"))
        XCTAssertNil(VaultRules.refusalReason(
            kind: "upi", label: "UPI", value: "arpit@okbank"))
        XCTAssertNil(VaultRules.refusalReason(
            kind: "phone", label: "Mobile", value: "+91 98765 43210"))
        // Solana ADDRESS (32-byte base58, ~44 chars) is fine — it's public.
        XCTAssertNil(VaultRules.refusalReason(
            kind: "wallet", label: "SOL", value: "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"))
    }

    // MARK: Encryption round-trip

    func testEncryptedRoundTripAndCombos() throws {
        let key = SymmetricKey(size: .bits256)
        let s = store(key: key)
        XCTAssertNil(s.upsertField(id: nil, kind: "name", label: "Name", value: "Arpit Singh"))
        XCTAssertNil(s.upsertField(id: nil, kind: "address", label: "Home", value: "42 Glass Lane"))
        XCTAssertNil(s.upsertField(id: nil, kind: "phone", label: "Mobile", value: "+91 98765 43210"))

        let fields = s.load().fields
        XCTAssertEqual(fields.count, 3)
        XCTAssertNil(s.upsertCombo(id: nil, label: "Shipping block",
                                   fieldIds: fields.map(\.id)))

        // On-disk blob is ciphertext — plaintext must not appear.
        let blob = try Data(contentsOf: tmp.appendingPathComponent(VaultStore.fileName))
        XCTAssertNil(String(data: blob, encoding: .utf8)?.range(of: "Glass Lane"))

        // A second store with the SAME key decrypts (keyboard process).
        let s2 = store(key: key)
        XCTAssertEqual(s2.load().fields.count, 3)
        let combo = try XCTUnwrap(s2.load().combos.first)
        XCTAssertEqual(s2.comboText(combo),
                       "Arpit Singh\n42 Glass Lane\n+91 98765 43210")

        // A WRONG key reads as empty, never as garbage.
        let s3 = store(key: SymmetricKey(size: .bits256))
        XCTAssertEqual(s3.load(), Vault())
    }

    // MARK: Shorthand (§6.7 — prefix triggers only, predictable)

    func testShorthandExpansion() {
        var vault = Vault()
        vault.snippets = [
            VaultSnippet(trigger: ";sig", text: "— Arpit · tryglyf.com"),
            VaultSnippet(trigger: ";addr", text: "42 Glass Lane, Bengaluru"),
        ]
        XCTAssertEqual(Shorthand.pendingToken(beforeContext: "hello ;sig"), ";sig")
        XCTAssertNil(Shorthand.pendingToken(beforeContext: "hello sig"))
        XCTAssertNil(Shorthand.pendingToken(beforeContext: "wink ;)... no wait"), "mid-text ; is not a trigger")
        XCTAssertEqual(Shorthand.expansion(for: ";sig", in: vault), "— Arpit · tryglyf.com")
        XCTAssertNil(Shorthand.expansion(for: ";nope", in: vault))
        XCTAssertNil(Shorthand.pendingToken(beforeContext: nil))
    }

    func testSnippetValidation() {
        XCTAssertNil(VaultRules.snippetRefusal(trigger: ";sig", text: "— A"))
        XCTAssertNotNil(VaultRules.snippetRefusal(trigger: "sig", text: "x"))
        XCTAssertNotNil(VaultRules.snippetRefusal(trigger: ";", text: "x"))
        XCTAssertNotNil(VaultRules.snippetRefusal(trigger: ";two words", text: "x"))
        XCTAssertNotNil(VaultRules.snippetRefusal(
            trigger: ";card", text: "4242 4242 4242 4242"))
    }
}
