import XCTest

/// §10.9: intent TTL expiry, replay rejection, single-use results — the
/// contract rules M8's value path will stand on (§7.3).
final class IntentStoreTests: XCTestCase {

    private var tmp: URL!
    private var clock: Date!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("intents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        clock = Date()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func store() -> IntentStore {
        IntentStore(baseDir: tmp, now: { self.clock })
    }

    func testRoundTripAndShape() throws {
        let s = store()
        let intent = try XCTUnwrap(s.createIntent(kind: "dictation", source: "glyf"))
        XCTAssertEqual(intent.version, 1)
        XCTAssertEqual(intent.kind, "dictation")
        XCTAssertGreaterThanOrEqual(Data(base64Encoded: intent.nonce)?.count ?? 0, 32)
        XCTAssertEqual(intent.expiresAt.timeIntervalSince(intent.createdAt),
                       IntentStore.ttl, accuracy: 0.5)

        // ISO8601 drops sub-second precision — compare fields, dates with tolerance.
        let loaded = try XCTUnwrap(s.loadIntent(id: intent.id))
        XCTAssertEqual(loaded.id, intent.id)
        XCTAssertEqual(loaded.nonce, intent.nonce)
        XCTAssertEqual(loaded.origin, intent.origin)
        XCTAssertEqual(loaded.createdAt.timeIntervalSince1970,
                       intent.createdAt.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(s.pendingIntent()?.id, intent.id)
    }

    func testTTLExpiryRefused() throws {
        let s = store()
        let intent = try XCTUnwrap(s.createIntent(kind: "dictation", source: "glyf"))
        clock = clock.addingTimeInterval(IntentStore.ttl + 1)
        XCTAssertNil(s.consume(id: intent.id), "expired intent must be refused (§7.3)")
        XCTAssertNil(s.pendingIntent(), "expired pending intent must not surface")
    }

    func testReplayRefused() throws {
        let s = store()
        let intent = try XCTUnwrap(s.createIntent(kind: "dictation", source: "glyf"))
        XCTAssertNotNil(s.consume(id: intent.id), "first consume succeeds")
        XCTAssertNil(s.consume(id: intent.id), "second consume is a replay — refused")
    }

    func testResultSingleRead() throws {
        let s = store()
        let intent = try XCTUnwrap(s.createIntent(kind: "dictation", source: "glyf"))
        _ = s.consume(id: intent.id)
        XCTAssertTrue(s.writeResult(intentId: intent.id, status: "success",
                                    payload: ["transcript": "hello", "mode": "clean"]))

        let taken = try XCTUnwrap(s.takeResultForPending())
        XCTAssertEqual(taken.0.id, intent.id)
        XCTAssertEqual(taken.1.payload["transcript"], "hello")
        XCTAssertEqual(taken.1.status, "success")

        XCTAssertNil(s.takeResultForPending(), "results are single-read")
        XCTAssertNil(s.pendingIntent(), "pending pointer cleared after take")
    }

    func testFinishedResultOutlivesTheIntentTTL() throws {
        // The TTL guards the hop INTO the app. A result the app already wrote
        // is the person's own dictation; reading the review for a couple of
        // minutes must not throw it away.
        let s = store()
        let intent = try XCTUnwrap(s.createIntent(kind: "dictation", source: "glyf"))
        _ = s.consume(id: intent.id)
        _ = s.writeResult(intentId: intent.id, status: "success",
                          payload: ["transcript": "late"])
        clock = clock.addingTimeInterval(IntentStore.ttl + 5)
        XCTAssertEqual(s.pendingIntent()?.id, intent.id, "an answered intent is still pending")
        XCTAssertEqual(s.takeResultForPending()?.1.payload["transcript"], "late")
    }

    func testStaleResultNotDelivered() throws {
        let s = store()
        let intent = try XCTUnwrap(s.createIntent(kind: "dictation", source: "glyf"))
        _ = s.consume(id: intent.id)
        _ = s.writeResult(intentId: intent.id, status: "success",
                          payload: ["transcript": "late"])
        clock = clock.addingTimeInterval(IntentStore.resultGrace + 5)
        XCTAssertNil(s.pendingIntent(), "a result nobody came back for is dropped")
        XCTAssertNil(s.takeResultForPending(), "keyboard must not insert a stale handoff")
    }
}
