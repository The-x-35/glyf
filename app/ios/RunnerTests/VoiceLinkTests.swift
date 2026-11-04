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
        XCTAssertEqual(m.state.expiresAt, VoiceLink.never, "a session has no idle end")
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
        XCTAssertEqual(m.state.expiresAt, VoiceLink.never)
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

    func testTheSessionLastsForever() {
        XCTAssertNil(VoiceLink.idleLifetime)
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        let tenYears = 10 * 365 * 86_400.0
        XCTAssertEqual(m.tick(now: tenYears), [.publish], "still beating, ten idle years on")
        XCTAssertEqual(m.state.phase, .ready)
        XCTAssertTrue(VoiceLink.alive(m.state, now: tenYears + 1))
        XCTAssertFalse(VoiceLink.alive(m.state, now: tenYears + VoiceLink.staleAfter),
                       "a dead app is still caught by its heartbeat")
        XCTAssertEqual(m.handle(cmd(.end, at: tenYears + 2), now: tenYears + 2),
                       [.abortCapture, .shutDown, .publish], "Turn off still ends it")
    }

    func testSessionLengthSetting() {
        XCTAssertNil(VoiceLink.lifetime(setting: nil))
        XCTAssertNil(VoiceLink.lifetime(setting: "always"))
        XCTAssertNil(VoiceLink.lifetime(setting: "garbage"))
        XCTAssertEqual(VoiceLink.lifetime(setting: "1h"), 3600)
        XCTAssertEqual(VoiceLink.lifetime(setting: "15m"), 900)
        var m = VoiceMachine(now: 0, idleLifetime: VoiceLink.lifetime(setting: "15m"))
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        XCTAssertEqual(m.state.expiresAt, 900)
        XCTAssertEqual(m.tick(now: 900), [.abortCapture, .shutDown, .publish])
    }

    func testAQuietMicrophoneAfterAnInterruptionKeepsTheSession() {
        // A call took the microphone: no heartbeat, the keyboard sees the app
        // as gone, but the session itself is still on and beats again once
        // audio comes back.
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        XCTAssertEqual(m.tick(now: 60, audioFlowing: false), [])
        XCTAssertTrue(m.isOn)
        XCTAssertFalse(VoiceLink.alive(m.state, now: 60))
        XCTAssertEqual(m.tick(now: 61, audioFlowing: true), [.publish])
        XCTAssertTrue(VoiceLink.alive(m.state, now: 61))
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
        let url = VoiceLink.openURL(utterance: "abc", host: "net.whatsapp.WhatsApp")
        XCTAssertEqual(url.absoluteString, "glyf://voice?u=abc&h=net.whatsapp.WhatsApp")
        XCTAssertEqual(VoiceLink.openURL(utterance: "abc", host: "").absoluteString, "glyf://voice?u=abc")
        let back = VoiceLink.parseOpenURL(url)
        XCTAssertEqual(back.utterance, "abc")
        XCTAssertEqual(back.host, "net.whatsapp.WhatsApp")
        let bare = VoiceLink.parseOpenURL(URL(string: "glyf://voice")!)
        XCTAssertNil(bare.utterance)
        XCTAssertNil(bare.host)
    }

    // MARK: Back to the app the keyboard was in

    func testReturnAppsMapBundleIdsToTheirLinks() {
        let cases: [(String, String, String)] = [
            ("com.apple.MobileSMS", "Messages", "sms:"),
            ("net.whatsapp.WhatsApp", "WhatsApp", "whatsapp://"),
            ("ph.telegra.Telegraph", "Telegram", "tg://"),
            ("com.burbn.instagram", "Instagram", "instagram://"),
            ("com.tinyspeck.chatlyio", "Slack", "slack://"),
            ("com.apple.mobilemail", "Mail", "message:"),
            ("com.apple.mobilenotes", "Notes", "mobilenotes://"),
            ("notion.id", "Notion", "notion://"),
            ("com.hammerandchisel.discord", "Discord", "discord://"),
            ("com.atebits.Tweetie2", "X", "twitter://"),
            ("com.google.Gmail", "Gmail", "googlegmail://"),
        ]
        for (id, name, link) in cases {
            let app = VoiceLink.returnApp(forHost: id)
            XCTAssertEqual(app?.name, name, id)
            XCTAssertEqual(app?.url.absoluteString, link, id)
        }
        XCTAssertNil(VoiceLink.returnApp(forHost: "com.apple.mobilesafari"),
                     "Safari: any link opens a new page, not the tab")
        XCTAssertNil(VoiceLink.returnApp(forHost: "com.example.unknown"))
        XCTAssertNil(VoiceLink.returnApp(forHost: nil))
        XCTAssertNil(VoiceLink.returnApp(forHost: ""))
        for (id, entry) in VoiceLink.returnApps {
            XCTAssertNotNil(URL(string: entry.url), id)
            XCTAssertFalse(entry.url.hasPrefix("http"), "\(id): a web link would open Safari")
            XCTAssertFalse(entry.name.isEmpty, id)
        }
    }

    func testGoingBackWaitsForAudioThenGivesUp() {
        XCTAssertEqual(VoiceLink.returnStep(sinceOpen: 0, audioFlowing: true), .wait, "the person sees Glyf take it")
        XCTAssertEqual(VoiceLink.returnStep(sinceOpen: VoiceLink.returnAfter, audioFlowing: true), .go)
        XCTAssertEqual(VoiceLink.returnStep(sinceOpen: 1, audioFlowing: false), .wait, "no audio yet")
        XCTAssertEqual(VoiceLink.returnStep(sinceOpen: 1.5, audioFlowing: true), .go)
        XCTAssertEqual(VoiceLink.returnStep(sinceOpen: VoiceLink.returnGiveUp, audioFlowing: false), .stay)
        XCTAssertLessThanOrEqual(VoiceLink.returnAfter, 1, "a minimum 1 second open and close")
    }

    func testStateRoundTripsThroughJSON() throws {
        var s = state(.listening, heartbeat: 5, utterance: "u")
        s.partial = "hi"
        let back = try JSONDecoder().decode(VoiceLink.State.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    // MARK: The panel: style, punctuation, level

    func testStylesMapToExistingGlyfs() {
        XCTAssertNil(VoiceLink.Style.asSpoken.run, "as spoken sends nothing")
        XCTAssertEqual(VoiceLink.Style.clean.run?.glyfId, "dictation.clean")
        XCTAssertEqual(VoiceLink.Style.formal.run?.glyfId, "dictation.formal")
        XCTAssertEqual(VoiceLink.Style.casual.run?.glyfId, "rewrite.tone")
        XCTAssertEqual(VoiceLink.Style.excited.run?.glyfId, "rewrite.tone")
        XCTAssertNotNil(VoiceLink.Style.casual.run?.vars["tone"])
        XCTAssertNotEqual(VoiceLink.Style.casual.run?.vars["tone"], VoiceLink.Style.excited.run?.vars["tone"])
        XCTAssertEqual(VoiceLink.Style.allCases.map(\.title),
                       ["As spoken", "Clean", "Formal", "Casual", "Excited"])
        XCTAssertEqual(VoiceLink.Style.excited.menuTitle, "Excited!")
    }

    func testStyleIsRememberedAndDefaultsToAsSpoken() {
        XCTAssertEqual(VoiceLink.Style.from(nil), .asSpoken)
        XCTAssertEqual(VoiceLink.Style.from("nonsense"), .asSpoken)
        XCTAssertEqual(VoiceLink.Style.from("formal"), .formal)
        XCTAssertNil(GlyfSettings().voiceStyle, "a new install is As spoken")
        var s = GlyfSettings()
        s.voiceStyle = VoiceLink.Style.casual.rawValue
        let back = try? JSONDecoder().decode(GlyfSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(VoiceLink.Style.from(back?.voiceStyle), .casual)
    }

    func testPolishedTakesOffWrapping() {
        XCTAssertEqual(VoiceLink.polished(original: "um hi", cleaned: "\"Hi.\""), "Hi.")
        XCTAssertEqual(VoiceLink.polished(original: "um hi", cleaned: "“Hi there.”\n"), "Hi there.")
        XCTAssertEqual(VoiceLink.polished(original: "um hi", cleaned: "Cleaned text: Hi."), "Hi.")
        XCTAssertEqual(VoiceLink.polished(original: "um hi", cleaned: "  "), "um hi", "nothing back: as said")
        XCTAssertEqual(VoiceLink.polished(original: "x", cleaned: "\"Go\" she said, \"now\""),
                       "\"Go\" she said, \"now\"", "quotes inside stay")
    }

    func testSpokenPunctuation() {
        XCTAssertEqual(VoiceLink.spokenPunctuation("see you soon period"), "see you soon.")
        XCTAssertEqual(VoiceLink.spokenPunctuation("hi comma how are you question mark"), "hi, how are you?")
        XCTAssertEqual(VoiceLink.spokenPunctuation("wow exclamation point that was fun full stop"),
                       "wow! That was fun.")
        XCTAssertEqual(VoiceLink.spokenPunctuation("first new line second"), "first\nSecond")
        XCTAssertEqual(VoiceLink.spokenPunctuation("one new paragraph two"), "one\n\nTwo")
        XCTAssertEqual(VoiceLink.spokenPunctuation("The period ended."), "The period ended.",
                       "a recognizer that punctuates already read the marks")
        XCTAssertEqual(VoiceLink.spokenPunctuation("periodic table"), "periodic table", "whole words only")
    }

    func testLiveWordsAreCapitalisedAndPunctuated() {
        XCTAssertEqual(VoiceLink.live("  hey, are you free?"), "Hey, are you free?")
        XCTAssertEqual(VoiceLink.live("call me period thanks"), "Call me. Thanks")
        XCTAssertEqual(VoiceLink.live(""), "")
    }

    func testJoinedStretches() {
        XCTAssertEqual(VoiceLink.joined("Hello there.", "How are you?"), "Hello there. How are you?")
        XCTAssertEqual(VoiceLink.joined("", "Hi"), "Hi")
        XCTAssertEqual(VoiceLink.joined("Hi ", " "), "Hi")
    }

    func testNormalizedLevel() {
        XCTAssertEqual(VoiceLink.normalizedLevel(rms: 0), 0)
        XCTAssertEqual(VoiceLink.normalizedLevel(rms: .nan), 0)
        XCTAssertEqual(VoiceLink.normalizedLevel(rms: 0.0005), 0, "a quiet room is nothing")
        XCTAssertEqual(VoiceLink.normalizedLevel(rms: 0.5), 1, "close speech is full")
        let mid = VoiceLink.normalizedLevel(rms: 0.02)
        XCTAssertGreaterThan(mid, 0.3)
        XCTAssertLessThan(mid, 0.8)
    }

    func testLevelIsPublishedOnlyWhileListeningAndWhenItMoves() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: nil, engine: nil)
        XCTAssertEqual(m.level(0.5), [], "nothing is being heard")
        XCTAssertNil(m.state.level)
        _ = m.handle(cmd(.start, "u1", at: 1), now: 1)
        XCTAssertEqual(m.level(0.5), [.publish])
        XCTAssertEqual(m.state.level, 0.5)
        XCTAssertEqual(m.level(0.51), [], "a small move isn't worth a write")
        XCTAssertEqual(m.level(1.7), [.publish])
        XCTAssertEqual(m.state.level, 1, "clamped")
        _ = m.handle(cmd(.stop, at: 2, utterance: "u1"), now: 2)
        XCTAssertEqual(m.state.level, 0, "stopping drops the wave")
        XCTAssertEqual(m.level(0.8), [])
    }

    func testAStretchEndingMidUtteranceCarriesOn() {
        var m = VoiceMachine(now: 0)
        _ = m.open(session: "s", now: 0, listenNow: "u1", engine: nil)
        XCTAssertTrue(m.continues(utterance: "u1"), "still listening: a new stretch, not the end")
        XCTAssertFalse(m.continues(utterance: "u2"))
        _ = m.handle(cmd(.stop, at: 1, utterance: "u1"), now: 1)
        XCTAssertFalse(m.continues(utterance: "u1"), "after ✓ the final is the end")
    }

    func testStateFromAnOlderAppDecodesWithoutALevel() throws {
        let json = #"{"session":"s","phase":"listening","heartbeat":1,"expiresAt":2,"partial":"hi"}"#
        let s = try JSONDecoder().decode(VoiceLink.State.self, from: Data(json.utf8))
        XCTAssertNil(s.level)
        XCTAssertEqual(s.partial, "hi")
    }
}
