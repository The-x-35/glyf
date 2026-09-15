import Foundation

/// File-based bridge over the App Group container (`group.so.glyf.shared`).
/// Compiled into BOTH the keyboard extension and the Runner app — this file is
/// the single implementation of the shared store (SPEC §4).
///
/// M0 scope: JSON ping/pong files proving bidirectional read/write.
/// Later milestones replace the payloads with intents/results/vault/glyfs
/// (SPEC §7) and move bulk data to shared SQLite; keep this API shape.
enum AppGroupStore {
    static let groupID = "group.so.glyf.shared"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    /// bridge/ subdirectory inside the group container; created on first use.
    static var bridgeDir: URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("bridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func writeJSON(_ payload: [String: Any], name: String) -> Bool {
        guard let dir = bridgeDir,
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else { return false }
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func readJSON(name: String) -> [String: Any]? {
        guard let dir = bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(name))
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - M0 ping/pong proof

    /// Keyboard → app. Written on every keyboard appearance.
    @discardableResult
    static func writeKeyboardPing(appearance: Int, footprintMB: Double, hasFullAccess: Bool) -> Bool {
        writeJSON([
            "ts": now(),
            "appearance": appearance,
            "footprintMB": (footprintMB * 10).rounded() / 10,
            "hasFullAccess": hasFullAccess,
            "from": "keyboard",
        ], name: "keyboard-ping.json")
    }

    static func readKeyboardPing() -> [String: Any]? { readJSON(name: "keyboard-ping.json") }

    /// App → keyboard. Written from the M0 debug screen.
    @discardableResult
    static func writeAppPong(message: String) -> Bool {
        writeJSON([
            "ts": now(),
            "message": message,
            "from": "app",
        ], name: "app-pong.json")
    }

    static func readAppPong() -> [String: Any]? { readJSON(name: "app-pong.json") }

    /// Spike A: keyboard records the attempt before trying to open the app,
    /// so the app can correlate the deep link it receives.
    @discardableResult
    static func writeSpikeAAttempt(intentId: String) -> Bool {
        writeJSON([
            "ts": now(),
            "intentId": intentId,
            "from": "keyboard",
        ], name: "spikea-attempt.json")
    }
}
