import XCTest

/// docs/STRIP-POLICY.md. Android's StripPolicyTest.kt has the same cases.
final class StripPolicyTests: XCTestCase {

    private let t0: Double = 1_800_000_000

    private func typing(_ since: TimeInterval, midWord: Bool = false, undo: Bool = false,
                        fix: Bool = false) -> StripPolicy.Typing {
        StripPolicy.Typing(sinceEdit: since, midWord: midWord, undoOnOffer: undo, fixPending: { fix })
    }

    func testTheNumbersAreTheDocs() {
        XCTAssertEqual(StripPolicy.settle, 0.4)
        XCTAssertEqual(StripPolicy.midWordPause, 1.0)
        XCTAssertEqual(StripPolicy.crossQuiet, 10)
        XCTAssertEqual(StripPolicy.ignoreQuiet, 5)
        XCTAssertEqual(StripPolicy.wordsPast, 2)
        XCTAssertEqual(StripPolicy.seenFor, 1.0)
        XCTAssertEqual(StripPolicy.pasteFresh, 180)
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

    func testACrossIsATenSecondCooldown() {
        var p = StripPolicy()
        p.enter(field: "doc1")
        p.shown(.answer, id: "calc|2+5", before: "2+5", now: t0)
        p.dismissed(.answer, id: "calc|2+5", now: t0)
        // Nothing at all inside the cooldown, whatever the kind.
        XCTAssertEqual(p.observe(before: "2+50", now: t0 + 3), .nothing)
        XCTAssertFalse(p.allows(.answer, id: "calc|2+50", now: t0 + 3))
        XCTAssertFalse(p.allows(.ai, id: "ai|1", now: t0 + 9.9))
        // After it, every kind again, in this app as anywhere.
        XCTAssertTrue(p.allows(.answer, id: "calc|2+50", now: t0 + 10))
        XCTAssertTrue(p.allows(.ai, id: "ai|1", now: t0 + 10))
    }

    func testTheCrossedChipComesAgainOnceTheTextChanges() {
        var p = StripPolicy()
        p.shown(.answer, id: "calc|2+5", before: "2+5", now: t0)
        p.dismissed(.answer, id: "calc|2+5", now: t0)
        // Sitting on the same text, it stays away after the cooldown too.
        XCTAssertEqual(p.observe(before: "2+5", now: t0 + 30), .nothing)
        XCTAssertFalse(p.allows(.answer, id: "calc|2+5", now: t0 + 30))
        // Typed on, then back: it may come again.
        _ = p.observe(before: "2+50", now: t0 + 31)
        _ = p.observe(before: "2+5", now: t0 + 32)
        XCTAssertTrue(p.allows(.answer, id: "calc|2+5", now: t0 + 32))
        // And crossing again is the same short cooldown, every time.
        p.shown(.answer, id: "calc|2+5", before: "2+5", now: t0 + 33)
        p.dismissed(.answer, id: "calc|2+5", now: t0 + 33)
        _ = p.observe(before: "2+56", now: t0 + 44)
        XCTAssertTrue(p.allows(.answer, id: "calc|2+56", now: t0 + 44))
    }

    func testTypingPastIsAShortQuiet() {
        var p = StripPolicy()
        p.shown(.ai, id: "ai|q1", before: "what is the capital of france", now: t0)
        XCTAssertEqual(p.observe(before: "what is the capital of france and", now: t0 + 2), .nothing)
        XCTAssertEqual(p.observe(before: "what is the capital of france and its", now: t0 + 3), .ignored(.ai))
        XCTAssertFalse(p.allows(.ai, id: "ai|q2", now: t0 + 7))
        XCTAssertTrue(p.allows(.ai, id: "ai|q2", now: t0 + 8))
    }

    func testAGlimpseOrAnEditIsNoVerdict() {
        var p = StripPolicy()
        p.shown(.answer, id: "a", before: "lets 10 inch", now: t0)
        XCTAssertEqual(p.observe(before: "lets 10 inch of snow", now: t0 + 0.5), .nothing)
        XCTAssertNil(p.onScreen)
        XCTAssertTrue(p.allows(.answer, id: "a", now: t0 + 1))
        p.shown(.answer, id: "b", before: "2+5", now: t0)
        XCTAssertEqual(p.observe(before: "2+", now: t0 + 5), .nothing)
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
        XCTAssertEqual(p.observe(before: "", now: t0 + 1), .nothing)
        XCTAssertEqual(p.observe(before: "h", now: t0 + 2), .pasteIgnored)
    }

    func testCodesAndPasswordsGetOnlyTheirChips() {
        for kind in StripPolicy.Kind.allCases {
            XCTAssertTrue(StripPolicy.allowed(kind, in: .normal))
            XCTAssertFalse(StripPolicy.allowed(kind, in: .secret))
        }
        let code = StripPolicy.Kind.allCases.filter { StripPolicy.allowed($0, in: .code) }
        XCTAssertEqual(Set(code), [.fill, .paste, .mail])
    }

    func testAMailHasNoCooldown() {
        var p = StripPolicy()
        p.shown(.mail, id: "mail|1", before: "", now: t0)
        p.dismissed(.mail, id: "mail|1", now: t0)
        XCTAssertTrue(p.allows(.mail, id: "mail|2", now: t0 + 1))
        XCTAssertFalse(p.allows(.mail, id: "mail|1", now: t0 + 1))
        // And a code is no quiet for the rest.
        XCTAssertTrue(p.allows(.answer, id: "calc|x", now: t0 + 1))
    }

    func testANewFieldStartsClean() {
        var p = StripPolicy()
        p.enter(field: "doc1")
        p.shown(.answer, id: "a", before: "x", now: t0)
        p.dismissed(.answer, id: "a", now: t0)
        p.enter(field: "doc2")
        XCTAssertTrue(p.allows(.answer, id: "a", now: t0 + 1))
    }
}
