import Foundation

/// §7 contracts as the App Group handoff (keyboard → app → keyboard).
/// M3 uses it for dictation; M8 swaps/sends reuse the same machinery.
/// Rules enforced here (§7.3, tested in RunnerTests):
///   single-use (consumed marker, replay refused) · 120s TTL · nonce-bound.
/// The GlyfIntent/GlyfResult types are GENERATED from shared/contracts
/// (Contracts.generated.swift) — §7: never hand-write both sides.

final class IntentStore {
    static let ttl: TimeInterval = 120  // §7.3
    static let shared = IntentStore()

    private let baseDir: URL?
    private let now: () -> Date

    /// Injectable for tests: temp directory + fake clock.
    init(baseDir: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.baseDir = baseDir
        self.now = now
    }

    private var root: URL? { baseDir ?? AppGroupStore.bridgeDir }

    private func dir(_ name: String) -> URL? {
        guard let root else { return nil }
        let d = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Create (keyboard side)

    @discardableResult
    func createIntent(kind: String, source: String, glyfId: String? = nil,
                      rawText: String = "", payload: [String: String] = [:]) -> GlyfIntent? {
        let created = now()
        var nonceBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes)
        let intent = GlyfIntent(
            id: UUID().uuidString.lowercased(),
            version: 1,
            createdAt: created,
            expiresAt: created.addingTimeInterval(Self.ttl),
            kind: kind,
            origin: IntentOrigin(source: source, glyfId: glyfId, rawText: rawText),
            payload: payload,
            risk: IntentRisk(score: 0, flags: []),
            nonce: Data(nonceBytes).base64EncodedString())
        guard let d = dir("intents"),
              let data = try? Self.encoder.encode(intent) else { return nil }
        do {
            try data.write(to: d.appendingPathComponent("\(intent.id).json"), options: .atomic)
        } catch { return nil }
        // Pending pointer so the keyboard knows what it is waiting on.
        AppGroupStoreWrite(["id": intent.id, "kind": kind], "pending-intent.json")
        return intent
    }

    private func AppGroupStoreWrite(_ dict: [String: Any], _ name: String) {
        guard let root,
              JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: root.appendingPathComponent(name), options: .atomic)
    }

    private func readPointer() -> String? {
        guard let root,
              let data = try? Data(contentsOf: root.appendingPathComponent("pending-intent.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["id"] as? String
    }

    func clearPending() {
        guard let root else { return }
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent("pending-intent.json"))
    }

    // MARK: - Load / validate

    func loadIntent(id: String) -> GlyfIntent? {
        guard let d = dir("intents"),
              let data = try? Data(contentsOf: d.appendingPathComponent("\(id).json"))
        else { return nil }
        return try? Self.decoder.decode(GlyfIntent.self, from: data)
    }

    func isExpired(_ intent: GlyfIntent) -> Bool {
        now() > intent.expiresAt
    }

    func isConsumed(_ id: String) -> Bool {
        guard let d = dir("consumed") else { return true }
        return FileManager.default.fileExists(atPath: d.appendingPathComponent(id).path)
    }

    /// App side: claim the intent for execution. Refuses expiry and replay.
    /// Returns the intent exactly once.
    func consume(id: String) -> GlyfIntent? {
        guard let intent = loadIntent(id: id), !isExpired(intent), !isConsumed(id),
              let d = dir("consumed") else { return nil }
        FileManager.default.createFile(atPath: d.appendingPathComponent(id).path, contents: nil)
        return intent
    }

    /// The keyboard's pending intent, when still valid.
    func pendingIntent() -> GlyfIntent? {
        guard let id = readPointer(), let intent = loadIntent(id: id),
              !isExpired(intent) else { return nil }
        return intent
    }

    // MARK: - Results (§7.2)

    @discardableResult
    func writeResult(intentId: String, status: String, payload: [String: String],
                     errorCode: String? = nil, errorMessage: String? = nil) -> Bool {
        let result = GlyfResult(
            intentId: intentId,
            status: status,
            payload: payload,
            error: errorCode.map { Result_Error(code: $0, message: errorMessage ?? $0) },
            completedAt: now())
        guard let d = dir("results"),
              let data = try? Self.encoder.encode(result) else { return false }
        do {
            try data.write(to: d.appendingPathComponent("\(intentId).json"), options: .atomic)
            return true
        } catch { return false }
    }

    func readResult(intentId: String) -> GlyfResult? {
        guard let d = dir("results"),
              let data = try? Data(contentsOf: d.appendingPathComponent("\(intentId).json"))
        else { return nil }
        return try? Self.decoder.decode(GlyfResult.self, from: data)
    }

    /// Keyboard side: read-and-clear in one step (results are single-read).
    func takeResultForPending() -> (GlyfIntent, GlyfResult)? {
        guard let id = readPointer(), let intent = loadIntent(id: id) else { return nil }
        guard !isExpired(intent) else {
            clearPending()
            return nil
        }
        guard let result = readResult(intentId: id) else { return nil }
        clearPending()
        if let d = dir("results") {
            try? FileManager.default.removeItem(at: d.appendingPathComponent("\(id).json"))
        }
        return (intent, result)
    }
}
