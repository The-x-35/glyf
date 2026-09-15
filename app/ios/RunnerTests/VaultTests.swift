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
