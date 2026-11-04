import XCTest

/// Voice typing's protocol (VoiceLink) and the app's session machine
/// (VoiceMachine), on a fake clock.
final class VoiceLinkTests: XCTestCase {

    private func cmd(_ verb: VoiceLink.Command.Verb, _ id: String = UUID().uuidString,
                     at: Double, utterance: String? = nil) -> VoiceLink.Command {
        .init(id: id, verb: verb, at: at, utterance: utterance)
    }

    // MARK: Session machine

    func testOpenFromTheMicListensAtOnce() {
        var m = VoiceMachine(now: 0)
        let fx = m.open(session: "s", now: 0, listenNow: "u1", engine: "speech")
        XCTAssertEqual(fx, [.beginCapture("u1"), .publish])
        XCTAssertEqual(m.state.phase, .listening)
        XCTAssertEqual(m.state.utterance, "u1")
        XCTAssertEqual(m.state.expiresAt, VoiceLink.idleLifetime)
    }

    func testOpenWithoutAnUtteranceWaitsReady() {
        var m = VoiceMachine(now: 0)
        XCTAssertEqual(m.open(session: "s", now: 0, listenNow: nil, engine: nil), [.publish])
        XCTAssertEqual(m.state.phase, .ready)
    }

    func testStartStopFinishDeliversTheWords() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        XCTAssertEqual(m.handle(cmd(.start, "u2", at: 10), now: 10), [.beginCapture("u2"), .publish])
        XCTAssertEqual(m.partial("hello", utterance: "u2"), [.publish])
        XCTAssertEqual(m.partial("hello", utterance: "u2"), [], "an unchanged partial is not republished")
        XCTAssertEqual(m.partial("other", utterance: "zz"), [], "another utterance's words are ignored")
        XCTAssertEqual(m.handle(cmd(.stop, at: 12, utterance: "u2"), now: 12), [.endCapture("u2"), .publish])
        XCTAssertEqual(m.state.phase, .finishing)
        XCTAssertEqual(m.finished("Hello there.", utterance: "u2", now: 13), [.publish])
        XCTAssertEqual(m.state.phase, .ready)
        XCTAssertEqual(m.state.final, "Hello there.")
        XCTAssertEqual(m.state.finishedAt, 13)
        XCTAssertEqual(m.state.expiresAt, 13 + VoiceLink.idleLifetime, "speaking resets the idle clock")
    }

    func testTheSameCommandTwiceActsOnce() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        let start = cmd(.start, "u3", at: 1)
        XCTAssertFalse(m.handle(start, now: 1).isEmpty)
        XCTAssertEqual(m.handle(start, now: 1.1), [], "a second note for the same file")
        // The open URL's utterance is the same id: it doesn't start twice either.
        XCTAssertEqual(m.open(session: "s", now: 2, listenNow: "u3", engine: nil), [.publish])
    }

    func testStartWhileListeningIsIgnored() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: "u1", engine: nil)
        XCTAssertEqual(m.handle(cmd(.start, "u9", at: 1), now: 1), [])
        XCTAssertEqual(m.state.utterance, "u1")
    }

    func testCancelThrowsTheUtteranceAway() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: "u1", engine: nil)
        _ = m.partial("um so", utterance: "u1")
        XCTAssertEqual(m.handle(cmd(.cancel, at: 3, utterance: "u1"), now: 3), [.abortCapture, .publish])
        XCTAssertEqual(m.state.phase, .ready)
        XCTAssertNil(m.state.final)
        XCTAssertEqual(m.state.partial, "")
        XCTAssertEqual(m.finished("late words", utterance: "u1", now: 4), [], "a cancelled utterance's result is dropped")
    }

    func testIdleSessionEndsAfterItsLifetime() {
        var m = VoiceMachine(now: 0, idleLifetime: 300)
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        XCTAssertEqual(m.tick(now: 299), [.publish])
        XCTAssertEqual(m.state.heartbeat, 299)
        XCTAssertEqual(m.tick(now: 300), [.abortCapture, .shutDown, .publish])
        XCTAssertEqual(m.state.phase, .off)
        XCTAssertEqual(m.tick(now: 301), [], "an ended session is quiet")
        XCTAssertEqual(m.handle(cmd(.start, at: 302), now: 302), [], "commands need a session")
    }

    func testListeningNeverTimesOutTheSessionButCapsTheUtterance() {
        var m = VoiceMachine(now: 0, idleLifetime: 300, maxUtterance: 120)
        _ = m.open(session: "s", now: 0, listenNow: "u1", engine: nil)
        XCTAssertEqual(m.tick(now: 119), [.publish])
        XCTAssertEqual(m.state.phase, .listening)
        XCTAssertEqual(m.tick(now: 120), [.endCapture("u1"), .publish])
        XCTAssertEqual(m.state.phase, .finishing)
    }

    func testARecognizerThatNeverFinishesStillGivesItsWords() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: "u1", engine: nil)
        _ = m.partial("see you at five", utterance: "u1")
        _ = m.handle(cmd(.stop, at: 10, utterance: "u1"), now: 10)
        XCTAssertEqual(m.tick(now: 10 + VoiceLink.finishTimeout - 0.1), [.publish])
        XCTAssertEqual(m.tick(now: 10 + VoiceLink.finishTimeout), [.abortCapture, .publish])
        XCTAssertEqual(m.state.final, "see you at five")
        XCTAssertEqual(m.state.phase, .ready)
    }

    func testQuietMicrophoneStopsTheHeartbeat() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        XCTAssertEqual(m.tick(now: 5, audioFlowing: false), [])
        XCTAssertEqual(m.state.heartbeat, 0, "no audio, no heartbeat: the keyboard sees the app as gone")
        XCTAssertFalse(VoiceLink.alive(m.state, now: 5))
    }

    func testFailureKeepsWhatWasHeard() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: "u1", engine: nil)
        XCTAssertEqual(m.failed("Didn't catch that", utterance: "u1", now: 2), [.abortCapture, .publish])
        XCTAssertEqual(m.state.error, "Didn't catch that")
        _ = m.handle(cmd(.start, "u2", at: 3), now: 3)
        _ = m.partial("half a sentence", utterance: "u2")
        _ = m.failed("Speech recognition isn't available", utterance: "u2", now: 4)
        XCTAssertNil(m.state.error)
        XCTAssertEqual(m.state.final, "half a sentence")
    }

    func testEndCommandShutsDown() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: "u1", engine: nil)
        XCTAssertEqual(m.handle(cmd(.end, at: 1), now: 1), [.abortCapture, .shutDown, .publish])
        XCTAssertFalse(m.isOn)
    }

    // MARK: Keyboard side

    private func state(_ phase: VoiceLink.Phase, heartbeat: Double, utterance: String? = nil) -> VoiceLink.State {
        VoiceLink.State(session: "s", phase: phase, heartbeat: heartbeat, expiresAt: heartbeat + 300,
                        utterance: utterance)
    }

    func testTapActions() {
        XCTAssertEqual(VoiceLink.tapAction(state: nil, now: 0, fullAccess: false), .needsFullAccess)
        XCTAssertEqual(VoiceLink.tapAction(state: nil, now: 0, fullAccess: true), .openApp)
        XCTAssertEqual(VoiceLink.tapAction(state: state(.ready, heartbeat: 100), now: 101, fullAccess: true), .start)
        XCTAssertEqual(VoiceLink.tapAction(state: state(.ready, heartbeat: 100),
                                           now: 100 + VoiceLink.staleAfter, fullAccess: true),
                       .openApp, "a stale heartbeat: the app is gone")
        XCTAssertEqual(VoiceLink.tapAction(state: state(.off, heartbeat: 100), now: 100, fullAccess: true), .openApp)
        XCTAssertEqual(VoiceLink.tapAction(state: state(.listening, heartbeat: 100, utterance: "u"),
                                           now: 101, fullAccess: true), .stop)
    }

    func testDeliverableOnceAndFresh() {
        var s = state(.ready, heartbeat: 100, utterance: "u1")
        XCTAssertNil(VoiceLink.deliverable(s, taken: nil, now: 100), "nothing final yet")
        s.final = "  Hello.  "
        s.finishedAt = 100
        XCTAssertEqual(VoiceLink.deliverable(s, taken: nil, now: 101)?.text, "Hello.")
        XCTAssertNil(VoiceLink.deliverable(s, taken: "u1", now: 101), "already typed")
        XCTAssertNil(VoiceLink.deliverable(s, taken: nil, now: 100 + VoiceLink.deliverWithin), "too old")
        s.final = ""
        XCTAssertNil(VoiceLink.deliverable(s, taken: nil, now: 101), "nothing heard")
    }

    func testFittedWords() {
        XCTAssertEqual(VoiceLink.fitted("hello there.", before: "", after: ""), "Hello there.")
        XCTAssertEqual(VoiceLink.fitted("See you soon.", before: "ok.", after: ""), " See you soon.")
        XCTAssertEqual(VoiceLink.fitted("Tomorrow at five.", before: "lunch ", after: ""), "tomorrow at five.")
        XCTAssertEqual(VoiceLink.fitted("I think so.", before: "well", after: ""), " I think so.")
        XCTAssertEqual(VoiceLink.fitted("NASA called.", before: "so ", after: ""), "NASA called.")
        XCTAssertEqual(VoiceLink.fitted("Really nice.", before: "a ", after: "day"), "really nice ")
        XCTAssertEqual(VoiceLink.fitted("   ", before: "x", after: ""), "")
    }

    func testOpenURL() {
        XCTAssertEqual(VoiceLink.openURL(utterance: "abc").absoluteString, "glyf://voice?u=abc")
        XCTAssertEqual(VoiceLink.openURL(utterance: nil).absoluteString, "glyf://voice")
    }

    func testStateRoundTripsThroughJSON() throws {
        var s = state(.listening, heartbeat: 5, utterance: "u")
        s.partial = "hi"
        let back = try JSONDecoder().decode(VoiceLink.State.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}
