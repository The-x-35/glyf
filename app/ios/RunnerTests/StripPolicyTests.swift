import XCTest

/// docs/STRIP-POLICY.md. Android's StripPolicyTest.kt has the same cases.
final class StripPolicyTests: XCTestCase {

    private let app = "com.apple.MobileSMS"
    private let t0: Double = 1_800_000_000

    private func typing(_ since: TimeInterval, midWord: Bool = false, undo: Bool = false,
                        fix: Bool = false) -> StripPolicy.Typing {
        StripPolicy.Typing(sinceEdit: since, midWord: midWord, undoOnOffer: undo, fixPending: { fix })
    }

    func testTheNumbersAreTheDocs() {
        XCTAssertEqual(StripPolicy.settle, 0.4)
        XCTAssertEqual(StripPolicy.midWordPause, 1.0)
        XCTAssertEqual(StripPolicy.gap, 8)
        XCTAssertEqual(StripPolicy.wordsPast, 2)
        XCTAssertEqual(StripPolicy.seenFor, 1.0)
        XCTAssertEqual(StripPolicy.ignoresPerDismissal, 2)
        XCTAssertEqual(StripPolicy.appMute, 600)
        XCTAssertEqual(StripPolicy.backoffAfter, 3)
        XCTAssertEqual(StripPolicy.backoffWindow, 86_400)
        XCTAssertEqual(StripPolicy.backoff, 86_400)
        XCTAssertEqual(StripPolicy.pasteFresh, 180)
        XCTAssertEqual(StripPolicy.maxEntries, 48)
    }

    func testAChipWaitsForAPause() {
        let p = StripPolicy()
        XCTAssertEqual(p.timing(.answer, id: "a", typing: typing(0)), .wait(0.4))
        XCTAssertEqual(p.timing(.answer, id: "a", typing: typing(0.4)), .now)
        XCTAssertEqual(p.timing(.ai, id: "a", typing: typing(5)), .now)
    }

    func testWordsWinMidWordAndAfterAFix() {
        var p = StripPolicy()
        // Mid-word the slots keep the strip until a longer pause...
        XCTAssertEqual(p.timing(.answer, id: "a", typing: typing(0, midWord: true)), .wait(1.0))
        XCTAssertEqual(p.timing(.answer, id: "a", typing: typing(1.0, midWord: true)), .now)
        // ...and always while space would fix the word, or its undo is on offer.
        XCTAssertEqual(p.timing(.answer, id: "a", typing: typing(9, midWord: true, fix: true)), .words)
        XCTAssertEqual(p.timing(.ai, id: "a", typing: typing(9, undo: true)), .words)
        // A saved detail finishing the word is itself a word.
        XCTAssertEqual(p.timing(.fill, id: "f", typing: typing(0.5, midWord: true, fix: true)), .now)
        // A chip already up stays up while it still applies: no flicker.
        p.shown(.answer, id: "a", before: "2+5", now: t0)
        XCTAssertEqual(p.timing(.answer, id: "a", typing: typing(0, midWord: true, fix: true)), .now)
    }

    func testADismissedChipNeverComesBackInThatField() {
        var p = StripPolicy()
        p.enter(field: "doc1")
        p.dismissed(.answer, id: "calc|2+5 = 7", scope: app, now: t0)
        XCTAssertFalse(p.allows(.answer, id: "calc|2+5 = 7", scope: app, now: t0 + 86_400 * 3))
        p.enter(field: "doc2")
        XCTAssertTrue(p.allows(.answer, id: "calc|2+5 = 7", scope: app, now: t0 + StripPolicy.appMute + 1))
    }

    func testADismissalMutesThatKindInThatAppForTenMinutes() {
        var p = StripPolicy()
        p.dismissed(.ai, id: "ai|1", scope: app, now: t0)
        // Nothing new at all for the gap, then other kinds and other apps.
        XCTAssertFalse(p.allows(.answer, id: "calc|x", scope: app, now: t0 + 7))
        XCTAssertTrue(p.allows(.answer, id: "calc|x", scope: app, now: t0 + 8))
        XCTAssertTrue(p.allows(.ai, id: "ai|2", scope: "com.whatsapp", now: t0 + 8))
        XCTAssertFalse(p.allows(.ai, id: "ai|2", scope: app, now: t0 + 599))
        XCTAssertTrue(p.allows(.ai, id: "ai|2", scope: app, now: t0 + 600))
    }

    func testThreeDismissalsInADayRestTheKindEverywhere() {
        var p = StripPolicy()
        p.dismissed(.ai, id: "ai|1", scope: "a", now: t0)
        p.dismissed(.ai, id: "ai|2", scope: "b", now: t0 + 3600)
        XCTAssertTrue(p.allows(.ai, id: "ai|3", scope: "c", now: t0 + 7200))
        p.dismissed(.ai, id: "ai|3", scope: "c", now: t0 + 7200)
        XCTAssertFalse(p.allows(.ai, id: "ai|4", scope: "d", now: t0 + 7200 + 3600))
        XCTAssertTrue(p.allows(.answer, id: "calc|x", scope: "d", now: t0 + 7200 + 3600))
        XCTAssertTrue(p.allows(.ai, id: "ai|4", scope: "d", now: t0 + 7200 + 86_400))
        // Two a day apart never add up to three.
        var q = StripPolicy()
        q.dismissed(.plan, id: "p1", scope: "a", now: t0)
        q.dismissed(.plan, id: "p2", scope: "a", now: t0 + 86_400)
        q.dismissed(.plan, id: "p3", scope: "b", now: t0 + 86_400 + 60)
        XCTAssertTrue(q.allows(.plan, id: "p4", scope: "c", now: t0 + 86_400 + 120))
    }

    func testTypingPastTwiceCountsAsOneDismissal() {
        var p = StripPolicy()
        p.shown(.ai, id: "ai|q1", before: "what is the capital of france", now: t0)
        XCTAssertEqual(p.observe(before: "what is the capital of france and", scope: app, now: t0 + 2), .nothing)
        XCTAssertEqual(p.observe(before: "what is the capital of france and its", scope: app, now: t0 + 3), .ignored(.ai))
        // That one is gone for the field; the kind isn't muted yet.
        XCTAssertFalse(p.allows(.ai, id: "ai|q1", scope: app, now: t0 + 60))
        XCTAssertTrue(p.allows(.ai, id: "ai|q2", scope: app, now: t0 + 60))
        p.shown(.ai, id: "ai|q2", before: "who won", now: t0 + 60)
        XCTAssertEqual(p.observe(before: "who won the game", scope: app, now: t0 + 62), .ignored(.ai))
        XCTAssertFalse(p.allows(.ai, id: "ai|q3", scope: app, now: t0 + 120))
        XCTAssertTrue(p.allows(.ai, id: "ai|q3", scope: app, now: t0 + 62 + 600))
    }

    func testAGlimpseOrAnEditIsNoVerdict() {
        var p = StripPolicy()
        p.shown(.answer, id: "a", before: "lets 10 inch", now: t0)
        XCTAssertEqual(p.observe(before: "lets 10 inch of snow", scope: app, now: t0 + 0.5), .nothing)
        XCTAssertNil(p.onScreen)
        XCTAssertTrue(p.allows(.answer, id: "a", scope: app, now: t0 + 1))
        p.shown(.answer, id: "b", before: "2+5", now: t0)
        XCTAssertEqual(p.observe(before: "2+", scope: app, now: t0 + 5), .nothing)
        XCTAssertNil(p.onScreen)
    }

    func testAWordGrowingIsNotAWordPast() {
        XCTAssertEqual(StripPolicy.wordsPast("2+5", "2+50"), 0)
        XCTAssertEqual(StripPolicy.wordsPast("2+5", "2+50 is"), 1)
        XCTAssertEqual(StripPolicy.wordsPast("2+5", "2+5 is it"), 2)
        XCTAssertNil(StripPolicy.wordsPast("2+5", "2+"))
        XCTAssertEqual(StripPolicy.wordsPast("", "hi there"), 2)
        XCTAssertEqual(StripPolicy.anchor("my email is  "), "my email is")
        XCTAssertEqual(StripPolicy.anchor(String(repeating: "a", count: 50)).count, 40)
    }

    func testACopyShowsOnce() {
        var p = StripPolicy()
        p.shown(.paste, id: "paste|hello", before: "", now: t0)
        XCTAssertEqual(p.observe(before: "", scope: app, now: t0 + 1), .nothing)
        XCTAssertEqual(p.observe(before: "h", scope: app, now: t0 + 2), .pasteIgnored)
        // A ✕ on one copy doesn't mute the next in this app (after the gap).
        p.dismissed(.paste, id: "paste|a", scope: app, now: t0 + 10)
        XCTAssertFalse(p.allows(.paste, id: "paste|a", scope: app, now: t0 + 100))
        XCTAssertTrue(p.allows(.paste, id: "paste|b", scope: app, now: t0 + 18))
    }

    func testCodesAndPasswordsGetOnlyTheirChips() {
        for kind in StripPolicy.Kind.allCases {
            XCTAssertTrue(StripPolicy.allowed(kind, in: .normal))
            XCTAssertFalse(StripPolicy.allowed(kind, in: .secret))
        }
        let code = StripPolicy.Kind.allCases.filter { StripPolicy.allowed($0, in: .code) }
        XCTAssertEqual(Set(code), [.fill, .paste, .mail])
    }

    func testAMailIsNeverMuted() {
        var p = StripPolicy()
        for i in 0..<5 { p.dismissed(.mail, id: "mail|\(i)", scope: app, now: t0 + Double(i)) }
        XCTAssertTrue(p.allows(.mail, id: "mail|9", scope: app, now: t0 + 6))
        XCTAssertFalse(p.allows(.mail, id: "mail|1", scope: app, now: t0 + 6))
        XCTAssertTrue(p.mutes.isEmpty)
        XCTAssertTrue(p.backoffs.isEmpty)
        // And a code is no gap for the rest.
        XCTAssertTrue(p.allows(.answer, id: "calc|x", scope: app, now: t0 + 6))
    }

    func testUsingAChipStartsTheCountOver() {
        var p = StripPolicy()
        p.shown(.answer, id: "a1", before: "x", now: t0)
        XCTAssertEqual(p.observe(before: "x y z", scope: app, now: t0 + 2), .ignored(.answer))
        p.used(.answer, scope: app)
        p.shown(.answer, id: "a2", before: "q", now: t0 + 20)
        XCTAssertEqual(p.observe(before: "q r s", scope: app, now: t0 + 22), .ignored(.answer))
        XCTAssertTrue(p.allows(.answer, id: "a3", scope: app, now: t0 + 40))
    }

    func testTheStoreStaysSmallAndSurvivesARoundTrip() throws {
        var p = StripPolicy()
        for i in 0..<60 { p.dismissed(.ai, id: "ai|\(i)", scope: "app\(i)", now: t0 + Double(i) * 30_000) }
        XCTAssertLessThanOrEqual(p.mutes.count, StripPolicy.maxEntries)
        p.shown(.answer, id: "a", before: "a", now: t0)
        _ = p.observe(before: "a b c", scope: "s", now: t0 + 2)
        let data = try JSONSerialization.data(withJSONObject: p.json)
        let back = StripPolicy(json: try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(back.mutes, p.mutes)
        XCTAssertEqual(back.backoffs, p.backoffs)
        XCTAssertEqual(back.refusals, p.refusals)
        XCTAssertEqual(back.softs.mapValues { $0.count }, p.softs.mapValues { $0.count })
        // Expired entries go.
        var q = back
        q.prune(now: t0 + 60 * 30_000 + 86_400 * 2)
        XCTAssertTrue(q.mutes.isEmpty)
        XCTAssertTrue(q.refusals.isEmpty)
        XCTAssertTrue(q.softs.isEmpty)
        XCTAssertNotNil(StripPolicy(json: nil).json["v"])
    }
}
