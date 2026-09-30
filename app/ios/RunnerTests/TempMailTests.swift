import XCTest

/// Temp mail's rules (TempMail.swift): how often the keyboard asks mail.tm
/// about the address and when it stops (Arpit, 2026-09-30: every 8 s for the
/// first 3 minutes of a watch, then every 20 s until the 15 minutes are up;
/// two minutes after a code unless the panel is open, which keeps 8 s), how
/// a mail is read, and shared/tempmail/cases.json, the cases the Android
/// keyboard runs too.
final class TempMailTests: XCTestCase {

    private let t0: Double = 1_790_000_000_000
    private let minute: Double = 60_000

    private static let sharedDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // RunnerTests
        .deletingLastPathComponent()          // ios
        .deletingLastPathComponent()          // app
        .deletingLastPathComponent()          // repo
        .appendingPathComponent("shared/tempmail")

    /// An address made at t0 and watched from then.
    private func state(codeAt: Double? = nil, blockedUntil: Double? = nil) -> TempMailState {
        TempMailState(address: "maple3f9a2c@uberip.com", password: "a1B2c3D4e5F6g7H8i9J0",
                      token: "eyJ0eXAiOiJKV1Qi.sig", accountId: "acct1", createdAt: t0,
                      watchUntil: t0 + TempMailRules.watch, codeAt: codeAt, blockedUntil: blockedUntil)
    }

    private func wait(_ at: Double, _ s: TempMailState, panel: Bool = false) -> TimeInterval? {
        TempMailRules.interval(now: at, state: s, panelOpen: panel)
    }

    // MARK: Watching

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

    func testAnAddressIsOfferedForADayFromWhenItWasMade() {
        var s = state()
        XCTAssertEqual(s.expiresAt, t0 + 24 * 60 * minute)
        s.watchUntil = t0 + 24 * 60 * minute + TempMailRules.watch   // watched past its day
        XCTAssertEqual(wait(t0 + 24 * 60 * minute - 1, s), 8)
        XCTAssertNil(wait(t0 + 24 * 60 * minute, s))
        XCTAssertNil(wait(t0 + 24 * 60 * minute, s, panel: true), "an ended address is not watched, panel or not")
    }

    func testThreeMissesPauseCheckingForAMinute() {
        let paused = state(blockedUntil: t0 + minute)
        XCTAssertEqual(wait(t0, paused), 60, "the next look waits the pause out")
        XCTAssertEqual(wait(t0 + 50_000, paused), 10)
        XCTAssertEqual(wait(t0 + 55_000, paused), 8, "never sooner than the beat")
        XCTAssertEqual(wait(t0, paused, panel: true), 60, "the panel open waits too")
        XCTAssertTrue(TempMailRules.watching(now: t0, state: paused, panelOpen: false), "a pause is still a watch")
        XCTAssertEqual(wait(t0 + minute, paused), 8, "after it, the beat again")
        XCTAssertEqual(TempMailRules.missesToPause, 3)
        XCTAssertEqual(TempMailRules.pause, minute)
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

    // MARK: Making an address

    func testAnAddressIsAWordSixHexDigitsAndTheDomain() {
        for _ in 0..<50 {
            let address = TempMailRules.newAddress(domain: "uberip.com")
            XCTAssertNotNil(address.range(of: "^[a-z]+[0-9a-f]{6}@uberip\\.com$", options: .regularExpression), address)
            XCTAssertTrue(TempMailRules.words.contains { address.hasPrefix($0) }, "\(address) starts with no word of ours")
        }
        let passwords = (0..<20).map { _ in TempMailRules.newPassword() }
        for p in passwords {
            XCTAssertEqual(p.count, 20)
            XCTAssertTrue(p.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }, p)
        }
        XCTAssertEqual(Set(passwords).count, passwords.count, "every password is its own")
    }

    // MARK: Reading a mail

    func testAMailFromMailTM() throws {
        let m = try XCTUnwrap(TempMailMessage(mailTM: [
            "id": "m1", "from": ["name": "Acme", "address": "no-reply@acme.example"],
            "subject": "Your Acme code",
            "text": "Your verification code is 482913.\nOr confirm: https://acme.example/verify?t=1",
            "html": ["<p>ignored while there is text</p>"], "createdAt": "2026-09-30T04:12:00+00:00",
        ]))
        XCTAssertEqual(m.id, "m1")
        XCTAssertEqual(m.from, "Acme")
        XCTAssertEqual(m.fromAddress, "no-reply@acme.example")
        XCTAssertEqual(m.subject, "Your Acme code")
        XCTAssertEqual(m.code, "482913")
        XCTAssertEqual(m.link, "https://acme.example/verify?t=1")
        XCTAssertEqual(m.receivedAt.timeIntervalSince1970, 1_790_741_520, accuracy: 0.001)

        // No name: the address stands in. No text: the HTML, read as text.
        let html = try XCTUnwrap(TempMailMessage(mailTM: [
            "id": "m2", "from": ["name": "", "address": "hello@b.example"], "subject": "Welcome",
            "text": "  ", "html": ["<p>Hi&nbsp;there</p>", "<a href=\"https://b.example/confirm?x=1&amp;y=2\">Confirm</a>"],
            "createdAt": "2026-09-30T04:12:00.250Z",
        ]))
        XCTAssertEqual(html.from, "hello@b.example")
        XCTAssertEqual(html.text, "Hi there\nConfirm")
        XCTAssertNil(html.code)
        XCTAssertEqual(html.link, "https://b.example/confirm?x=1&y=2")
        XCTAssertEqual(html.receivedAt.timeIntervalSince1970, 1_790_741_520.25, accuracy: 0.001)

        XCTAssertNil(TempMailMessage(mailTM: ["subject": "Hi"]), "a mail without an id is nothing to show")
        XCTAssertNil(TempMailMessage(mailTM: ["id": ""]))
    }

    func testAMailsWordsStopAtFourThousand() {
        let long = String(repeating: "word ", count: 1000)
        XCTAssertEqual((TempMailText.body(text: long, html: "") as NSString).length, 4000)
        XCTAssertEqual(TempMailText.body(text: "  hi  ", html: "<p>no</p>"), "hi")
        XCTAssertEqual(TempMailText.body(text: "", html: "<p>yes</p>"), "yes")
    }

    /// shared/tempmail/cases.json: the same cases the Android keyboard runs.
    func testSharedCases() throws {
        let url = Self.sharedDir.appendingPathComponent("cases.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var failures: [String] = []
        for c in root["codes"] as? [[String: Any]] ?? [] {
            let subject = c["subject"] as? String ?? "", text = c["text"] as? String ?? ""
            let got = TempMailText.extractCode(subject: subject, text: text), want = c["code"] as? String
            if got != want { failures.append("code '\(subject)': got \(got ?? "none"), want \(want ?? "none")") }
        }
        for c in root["links"] as? [[String: Any]] ?? [] {
            let got = TempMailText.extractLink(text: c["text"] as? String ?? "", html: c["html"] as? String ?? "")
            let want = c["link"] as? String
            if got != want { failures.append("link: got \(got ?? "none"), want \(want ?? "none")") }
        }
        for c in root["html"] as? [[String: Any]] ?? [] {
            let got = TempMailText.htmlToText(c["html"] as? String ?? "")
            if got != c["text"] as? String { failures.append("html: got \(got.debugDescription)") }
        }
        XCTAssertGreaterThan((root["codes"] as? [Any])?.count ?? 0, 0, "no cases read")
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    // MARK: Kept on disk

    func testWhatIsKeptOnDiskComesBackTheSame() throws {
        var s = state(codeAt: t0 + minute, blockedUntil: t0 + 2 * minute)
        s.seenIds = ["m1", "m2"]
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(TempMailState.self, from: data), s)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["address", "password", "token", "accountId", "createdAt", "watchUntil",
                                   "seenIds", "codeAt", "blockedUntil"], "never a mail")
        let plain = state()
        XCTAssertEqual(try JSONDecoder().decode(TempMailState.self, from: JSONEncoder().encode(plain)), plain)
        // What the Temp-Mail.io version kept is nothing to go on now.
        let old = #"{"address":"a@b.example","token":"x","expiresAt":1,"watchUntil":1,"seenIds":[]}"#
        XCTAssertNil(try? JSONDecoder().decode(TempMailState.self, from: Data(old.utf8)))
    }
}
