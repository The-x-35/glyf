import XCTest

/// Temp mail's rules (TempMail.swift): how often the keyboard asks about the
/// address and when it stops (Arpit, 2026-09-30: every 8 s for the first 3
/// minutes of a watch, then every 20 s until the 15 minutes are up; two
/// minutes after a code unless the panel is open, which keeps 8 s), and how
/// a mail and the countdown read.
final class TempMailTests: XCTestCase {

    private let t0: Double = 1_790_000_000_000
    private let minute: Double = 60_000

    /// An address made at t0, watched from then, alive for an hour.
    private func state(codeAt: Double? = nil, blockedUntil: Double? = nil) -> TempMailState {
        var s = TempMailState(address: "quiet.a1b2c3@glyf-temp.example", token: "1790003600.sig",
                              expiresAt: t0 + 60 * minute, watchUntil: t0 + TempMailRules.watch)
        s.codeAt = codeAt
        s.blockedUntil = blockedUntil
        return s
    }

    private func wait(_ at: Double, _ s: TempMailState, panel: Bool = false) -> TimeInterval? {
        TempMailRules.interval(now: at, state: s, panelOpen: panel)
    }

    func testEightSecondsForThreeMinutesThenTwentyUntilFifteen() {
        let s = state()
        XCTAssertEqual(wait(t0, s), 8)
        XCTAssertEqual(wait(t0 + 2 * minute + 59_000, s), 8)
        XCTAssertEqual(wait(t0 + 3 * minute, s), 20)
        XCTAssertEqual(wait(t0 + 14 * minute + 59_000, s), 20)
        XCTAssertNil(wait(t0 + 15 * minute, s), "the watch is over")
        // The panel open keeps the quick pace, but not past the watch.
        XCTAssertEqual(wait(t0 + 10 * minute, s, panel: true), 8)
        XCTAssertNil(wait(t0 + 15 * minute, s, panel: true))
    }

    func testAWatchRestartedLaterStartsQuickAgain() {
        var s = state()
        s.watchUntil = t0 + 20 * minute + TempMailRules.watch   // Insert at t0 + 20 min
        XCTAssertEqual(wait(t0 + 21 * minute, s), 8)
        XCTAssertEqual(wait(t0 + 23 * minute, s), 20)
    }

    func testACodeStopsTheWatchTwoMinutesLaterUnlessThePanelIsOpen() {
        let s = state(codeAt: t0 + minute)
        XCTAssertEqual(wait(t0 + 2 * minute + 59_000, s), 8)
        XCTAssertNil(wait(t0 + 3 * minute, s), "two minutes after the code")
        XCTAssertFalse(TempMailRules.watching(now: t0 + 3 * minute, state: s, panelOpen: false))
        XCTAssertEqual(wait(t0 + 3 * minute, s, panel: true), 8, "the panel open keeps watching")
        XCTAssertTrue(TempMailRules.watching(now: t0 + 3 * minute, state: s, panelOpen: true))
        // A code late in the watch: the slow pace until its two minutes are up.
        let late = state(codeAt: t0 + 10 * minute)
        XCTAssertEqual(wait(t0 + 11 * minute, late), 20)
        XCTAssertNil(wait(t0 + 12 * minute, late))
    }

    func testAnExpiredAddressOrADayAlreadySpentAsksNothing() {
        var s = state()
        s.expiresAt = t0 + 5 * minute
        XCTAssertEqual(wait(t0 + 4 * minute, s), 20)
        XCTAssertNil(wait(t0 + 5 * minute, s))
        XCTAssertNil(wait(t0 + 5 * minute, s, panel: true), "an ended address is not watched, panel or not")
        let blocked = state(blockedUntil: t0 + 10 * minute)
        XCTAssertNil(wait(t0, blocked))
        XCTAssertNil(wait(t0, blocked, panel: true), "429: no more checks today, panel or not")
        XCTAssertEqual(wait(t0 + 10 * minute, blocked), 20, "the next day asks again")
    }

    func testTimeLeftReadsMinutesAndSeconds() {
        XCTAssertEqual(TempMailRules.left(14 * minute + 32_000), "14:32")
        XCTAssertEqual(TempMailRules.left(14 * minute + 31_200), "14:32", "a part second counts as one")
        XCTAssertEqual(TempMailRules.left(TempMailRules.watch), "15:00")
        XCTAssertEqual(TempMailRules.left(9_000), "0:09")
        XCTAssertEqual(TempMailRules.left(0), "0:00")
        XCTAssertEqual(TempMailRules.left(-4_000), "0:00")
    }

    func testHowLongAgoAMailCame() {
        let now = Date(timeIntervalSince1970: t0 / 1000)
        func ago(_ seconds: Double) -> String {
            TempMailRules.ago(now.addingTimeInterval(-seconds), now: now)
        }
        XCTAssertEqual(ago(0), "now")
        XCTAssertEqual(ago(59), "now")
        XCTAssertEqual(ago(60), "1m")
        XCTAssertEqual(ago(150), "2m")
        XCTAssertEqual(ago(3 * 3600 + 5), "3h")
        XCTAssertEqual(ago(86_400 * 2), "2d")
        XCTAssertEqual(ago(-30), "now", "a clock a little ahead is still now")
    }

    func testAMailFromTheServer() throws {
        let m = try XCTUnwrap(TempMailMessage(json: [
            "id": "m1", "from": "Acme", "fromAddress": "no-reply@acme.example",
            "subject": "Your Acme code", "text": "Your verification code is 482913.",
            "receivedAt": NSNumber(value: t0), "code": "482913",
            "link": "https://acme.example/verify?t=1",
        ]))
        XCTAssertEqual(m.id, "m1")
        XCTAssertEqual(m.from, "Acme")
        XCTAssertEqual(m.fromAddress, "no-reply@acme.example")
        XCTAssertEqual(m.code, "482913")
        XCTAssertEqual(m.link, "https://acme.example/verify?t=1")
        XCTAssertEqual(m.receivedAt.timeIntervalSince1970 * 1000, t0, accuracy: 1)

        // No name: the address stands in; an empty code or link is none.
        let bare = try XCTUnwrap(TempMailMessage(json: [
            "id": "m2", "from": "", "fromAddress": "hello@b.example", "subject": "Hi", "text": "",
            "receivedAt": t0, "code": "", "link": "",
        ]))
        XCTAssertEqual(bare.from, "hello@b.example")
        XCTAssertNil(bare.code)
        XCTAssertNil(bare.link)
        XCTAssertNil(TempMailMessage(json: ["from": "Acme"]), "a mail without an id is nothing to show")
        XCTAssertNil(TempMailMessage(json: ["id": ""]))
    }

    func testWhatIsKeptOnDiskComesBackTheSame() throws {
        var s = state(codeAt: t0 + minute, blockedUntil: t0 + 30 * minute)
        s.seenIds = ["m1", "m2"]
        let back = try JSONDecoder().decode(TempMailState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        let plain = state()
        XCTAssertEqual(try JSONDecoder().decode(TempMailState.self, from: JSONEncoder().encode(plain)), plain)
    }

    func testTheDaysChecksComeBackAtMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let evening = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 22, minute: 15))!
        let midnight = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 0, minute: 0))!
        XCTAssertEqual(TempMailRules.nextMidnight(after: evening, calendar: cal), midnight)
    }
}
