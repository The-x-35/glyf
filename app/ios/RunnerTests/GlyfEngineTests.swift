import XCTest

/// §10.9 unit checks for the keyboard's pure logic, hosted in RunnerTests.
final class GlyfEngineTests: XCTestCase {

    // MARK: SecretScanner (§11.3/§11.4)

    func testCardNumbersRefused() {
        XCTAssertEqual(SecretScanner.scan("4242 4242 4242 4242"), .cardNumber)
        XCTAssertEqual(SecretScanner.scan("4242-4242-4242-4242"), .cardNumber)
        // Same digits failing Luhn are not a card.
        XCTAssertEqual(SecretScanner.scan("4242 4242 4242 4241"), .clean)
        // A phone number must not be refused.
        XCTAssertEqual(SecretScanner.scan("+91 98765 43210"), .clean)
    }

    func testSeedPhrasesRefused() {
        let seed = "legal winner thank year wave sausage worth useful legal winner thank yellow"
        XCTAssertEqual(SecretScanner.scan(seed), .seedPhrase)
        XCTAssertEqual(SecretScanner.scan("just a normal sentence with a few words"), .clean)
    }

    func testKeysAndTokensRefused() {
        XCTAssertEqual(SecretScanner.scan("sk-or-v1-aaaaaaaaaaaaaaaaaaaa"), .privateKeyOrToken)
        XCTAssertEqual(SecretScanner.scan("privy_app_secret_abcdefgh12345678"), .privateKeyOrToken)
        XCTAssertEqual(SecretScanner.scan(String(repeating: "a1", count: 32)), .privateKeyOrToken)
        XCTAssertEqual(SecretScanner.scan("-----BEGIN PRIVATE KEY-----\nxx"), .privateKeyOrToken)
    }

    func testOTPRefusedButPINsAreNotWorthKeepingEither() {
        XCTAssertEqual(SecretScanner.scan("123456"), .otpCode)
        XCTAssertEqual(SecretScanner.scan("meet at 6"), .clean)
    }

    // MARK: ClipboardStore (§6.1: 20 items, 1h expiry, pins survive)

    func testClipboardExpiryAndCap() {
        let now = Date()
        var items: [ClipItem] = []
        for i in 0..<25 {
            if let next = ClipboardStore.inserting("item \(i)", into: items, now: now) {
                items = next
            }
        }
        XCTAssertEqual(items.count, ClipboardStore.maxItems)

        // Pinned survives expiry; unpinned older than 1h is dropped.
        var aged = items.map { ClipItem(text: $0.text, ts: now.addingTimeInterval(-4000), pinned: false) }
        aged[3].pinned = true
        let pruned = ClipboardStore.prune(aged, now: now)
        XCTAssertEqual(pruned.count, 1)
        XCTAssertTrue(pruned[0].pinned)
    }

    func testClipboardRefusesSecretsAndDuplicates() {
        let items = [ClipItem(text: "hello", ts: Date(), pinned: false)]
        XCTAssertNil(ClipboardStore.inserting("4242 4242 4242 4242", into: items, now: Date()))
        XCTAssertNil(ClipboardStore.inserting("hello", into: items, now: Date()))
        XCTAssertNotNil(ClipboardStore.inserting("world", into: items, now: Date()))
    }

    // MARK: WordTracker (§6.1 autocorrect plumbing)

    func testCurrentWord() {
        XCTAssertEqual(WordTracker.currentWord(beforeContext: "hello wor"), "wor")
        XCTAssertEqual(WordTracker.currentWord(beforeContext: "hello "), "")
        XCTAssertEqual(WordTracker.currentWord(beforeContext: nil), "")
        XCTAssertEqual(WordTracker.currentWord(beforeContext: "line\nnew"), "new")
    }

    func testWantsCapital() {
        XCTAssertTrue(WordTracker.wantsCapital(beforeContext: nil))
        XCTAssertTrue(WordTracker.wantsCapital(beforeContext: "Done. "))
        XCTAssertTrue(WordTracker.wantsCapital(beforeContext: "Really? "))
        XCTAssertFalse(WordTracker.wantsCapital(beforeContext: "mid sentence "))
        XCTAssertFalse(WordTracker.wantsCapital(beforeContext: "e.g. no wait — yes it does"))
        XCTAssertTrue(WordTracker.wantsCapital(beforeContext: "newline\n"))
    }

    func testPeriodShortcutGate() {
        XCTAssertTrue(WordTracker.canPeriodShortcut(beforeContext: "word "))
        XCTAssertFalse(WordTracker.canPeriodShortcut(beforeContext: "word. "))
        XCTAssertFalse(WordTracker.canPeriodShortcut(beforeContext: " "))
        XCTAssertFalse(WordTracker.canPeriodShortcut(beforeContext: "word"))
    }

    // MARK: Layout tables (§6.1)

    func testLayoutShapes() {
        let letters = KeyboardLayout.rows(mode: .letters, numberRow: false, globe: true)
        XCTAssertEqual(letters.count, 4)
        XCTAssertEqual(letters[0].count, 10)
        XCTAssertTrue(letters[3].contains { $0.kind == .globe })
        XCTAssertTrue(letters[3].contains { $0.kind == .space })
        // §1.4: return and globe exist and are never char keys.
        XCTAssertTrue(letters[3].contains { $0.kind == .ret })

        let withNumbers = KeyboardLayout.rows(mode: .letters, numberRow: true, globe: false)
        XCTAssertEqual(withNumbers.count, 5)
        XCTAssertEqual(withNumbers[0].compactMap(\.char).joined(), "1234567890")

        let symbols = KeyboardLayout.rows(mode: .symbols1, numberRow: false, globe: true)
        XCTAssertEqual(symbols[0].compactMap(\.char).joined(), "1234567890")
    }

    func testAccentsExistForCommonVowels() {
        for base in ["a", "e", "i", "o", "u", "n", "c"] {
            XCTAssertFalse(KeyboardLayout.accents[base, default: []].isEmpty, base)
        }
    }

    // MARK: Word context

    func testApostrophesInsideWordsBelongToTheWord() {
        XCTAssertEqual(WordTracker.currentWord(beforeContext: "I don't"), "don't")
        XCTAssertEqual(WordTracker.currentWord(beforeContext: "she said 'hi"), "hi")
        XCTAssertEqual(WordTracker.currentWord(beforeContext: "rock 'n"), "n")
    }

    func testPreviousWordStopsAtSentenceEnds() {
        XCTAssertEqual(WordTracker.previousWord(beforeContext: "thank yo"), "thank")
        XCTAssertEqual(WordTracker.previousWord(beforeContext: "thank "), "thank")
        XCTAssertNil(WordTracker.previousWord(beforeContext: "Done. Tha"))
        XCTAssertNil(WordTracker.previousWord(beforeContext: "hello"))
    }

    // MARK: Settings migration

    /// Old files gain every new toolbar item, and the user's existing order
    /// is preserved — except Search, which leads (Gboard parity).
    func testToolbarOrderMigrationAddsNewItemsAndLeadsWithSearch() {
        var s = GlyfSettings()
        s.toolbarOrder = ["settings"] // simulate an old file
        s = SettingsStore.migrated(s)
        XCTAssertEqual(Set(s.toolbarOrder), Set(GlyfSettings.Toolbar.defaultOrder))
        XCTAssertEqual(s.toolbarOrder.first, "search")
        XCTAssertEqual(s.toolbarOrder.dropFirst().first, "settings",
                       "the user's own order must survive under Search")
    }

    /// v2 → v3 (§6.13): default map fills UNCLAIMED keys only; the old
    /// one-shot T translate upgrades to the HUD; user rebinds survive.
    func testV3MigrationRespectsUserBindings() {
        var old = GlyfSettings()
        old.schemaVersion = 2
        old.bindings = [
            "t": "glyf.translate",       // stock M2 default → upgrades
            "j": "glyf.proofread",       // user's own choice → SURVIVES
            "s": "surface:vault",
        ]
        let s = SettingsStore.migrated(old)
        XCTAssertEqual(s.schemaVersion, 3)
        XCTAssertEqual(s.bindings["t"], "surface:translate-hud")
        XCTAssertEqual(s.bindings["j"], "glyf.proofread")
        XCTAssertEqual(s.bindings["p"], "glyf.proofread")
        // Presets stay deliberately small — unclaimed letters stay FREE.
        XCTAssertNil(s.bindings["w"])
        XCTAssertNil(s.bindings["c"])
        XCTAssertNotNil(s.customTitles)
    }

    /// A user who REBOUND t before v3 keeps their binding — no HUD hijack.
    func testV3MigrationKeepsRetargetedT() {
        var old = GlyfSettings()
        old.schemaVersion = 2
        old.bindings = ["t": "rewrite.polite"]
        let s = SettingsStore.migrated(old)
        XCTAssertEqual(s.bindings["t"], "rewrite.polite")
    }

    /// Running migration on a current file changes nothing (idempotent).
    func testMigrationIdempotent() {
        let once = SettingsStore.migrated(GlyfSettings())
        XCTAssertEqual(SettingsStore.migrated(once), once)
    }

    // MARK: §6.12 search paste format
    //
    // A hand port of the server's composeInsert (searchcards.ts) — these
    // assertions are deliberately identical to server/test/search.test.ts so
    // the two can't drift.

    private func card(title: String, url: String,
                      emoji: String? = nil, extra: String? = nil) -> GlyfKeyboardSearchCard {
        var c = GlyfKeyboardSearchCard(kind: "link", id: "t", title: title, url: url)
        c.emoji = emoji
        c.extra = extra
        return c
    }

    func testPasteStyleTitleAndLinkMatchesGboard() {
        let video = card(title: "lofi hip hop radio",
                         url: "https://youtu.be/jfKfPfyJRdk", emoji: "🎥")
        XCTAssertEqual(video.insertText(style: "titleAndLink"),
                       "https://youtu.be/jfKfPfyJRdk\n🎥 lofi hip hop radio")
    }

    func testPasteStyleLinkOnlyDropsEverythingButTheURL() {
        let video = card(title: "lofi hip hop radio",
                         url: "https://youtu.be/jfKfPfyJRdk", emoji: "🎥")
        XCTAssertEqual(video.insertText(style: "linkOnly"),
                       "https://youtu.be/jfKfPfyJRdk")
    }

    func testPlacePastesAddressAsThirdLine() {
        let place = card(title: "Blue Tokai Coffee",
                         url: "https://maps.google.com/?q=x",
                         emoji: "📍", extra: "45 Church St, Bengaluru")
        XCTAssertEqual(place.insertText(style: "titleAndLink"),
                       "https://maps.google.com/?q=x\n📍 Blue Tokai Coffee\n45 Church St, Bengaluru")
        XCTAssertEqual(place.insertText(style: "linkOnly"), "https://maps.google.com/?q=x")
    }

    func testPlainLinkHasNoEmojiPrefix() {
        XCTAssertEqual(
            card(title: "Sunset times", url: "https://timeanddate.com")
                .insertText(style: "titleAndLink"),
            "https://timeanddate.com\nSunset times")
    }

    func testTitlelessCardFallsBackToTheBareURL() {
        XCTAssertEqual(
            card(title: "   ", url: "https://x.dev").insertText(style: "titleAndLink"),
            "https://x.dev")
    }

    /// A settings.json left behind by a release install must not send a DEBUG
    /// build at production. Found the hard way: the simulator had the live
    /// domain persisted and every search failed with an opaque TLS error.
    func testDebugBuildDoesNotInheritProductionBackend() {
        var s = GlyfSettings()
        s.backendURL = GlyfSettings.productionBackend
        let migrated = SettingsStore.migrated(s)
        #if DEBUG
        XCTAssertEqual(migrated.backendURL, GlyfSettings.defaultBackendURL,
                       "a debug build must fall back to the dev server")
        XCTAssertNotEqual(migrated.backendURL, GlyfSettings.productionBackend)
        #else
        XCTAssertEqual(migrated.backendURL, GlyfSettings.productionBackend)
        #endif
    }

    /// …and the original direction still holds: a shipped build must never be
    /// left pointing at someone's laptop.
    func testPersistedDevURLIsUpgradedInReleaseBuilds() {
        var s = GlyfSettings()
        s.backendURL = "http://127.0.0.1:8787"
        let migrated = SettingsStore.migrated(s)
        #if DEBUG
        XCTAssertEqual(migrated.backendURL, "http://127.0.0.1:8787")
        #else
        XCTAssertEqual(migrated.backendURL, GlyfSettings.productionBackend)
        #endif
    }

    /// New installs must paste the link WITH the title (Gboard's behaviour).
    func testPasteStyleDefaultsToTitleAndLink() {
        XCTAssertEqual(GlyfSettings().pasteStyle, "titleAndLink")
        // …and an older settings file without the field migrates to the same.
        var old = GlyfSettings()
        old.pasteStyle = nil
        XCTAssertEqual(SettingsStore.migrated(old).pasteStyle ?? "titleAndLink",
                       "titleAndLink")
    }

    // MARK: §6.15 tone profile

    func testToneHintNeedsThreeNetAccepts() {
        var counts = ToneCounts()
        counts.accepted["concise"] = 2
        XCTAssertEqual(ToneProfile.hint(from: counts), "")
        counts.accepted["concise"] = 3
        XCTAssertTrue(ToneProfile.hint(from: counts).contains("brief"))
        // Discards subtract: 4 accepted − 2 discarded = 2 net → silent again.
        counts.accepted["concise"] = 4
        counts.discarded["concise"] = 2
        XCTAssertEqual(ToneProfile.hint(from: counts), "")
    }

    func testToneHintPicksStrongestBucket() {
        var counts = ToneCounts()
        counts.accepted["warm"] = 3
        counts.accepted["playful"] = 5
        XCTAssertTrue(ToneProfile.hint(from: counts).contains("playful"))
    }

    func testToneBucketsMapKnownGlyfs() {
        XCTAssertEqual(ToneProfile.bucket(for: "rewrite.tighten"), "concise")
        XCTAssertEqual(ToneProfile.bucket(for: "social.xreply"), "playful")
        XCTAssertNil(ToneProfile.bucket(for: "keyless.weather"))
    }

    // MARK: Space bar — tap / glide / hold (one key, three gestures)

    func testSpaceTapTypesASpace() {
        var g = SpaceGesture(x: 100, y: 20, time: 0)
        XCTAssertEqual(g.moved(x: 104, y: 22, time: 0.05), [], "a wobble is not a glide")
        XCTAssertEqual(g.ended(time: 0.1), [.typeSpace])
    }

    func testImmediateSwipeGlidesTheCursorGboardStyle() {
        var g = SpaceGesture(x: 100, y: 20, time: 0)
        XCTAssertEqual(g.moved(x: 89, y: 20, time: 0.08), [.beginGlide])
        // Slow drag: 9pt per character, exact.
        XCTAssertEqual(g.moved(x: 71, y: 20, time: 0.5), [.moveCursor(-2)])
        XCTAssertEqual(g.ended(time: 0.6), [.endGlide], "a glide never types a space")
    }

    func testPressPauseGlideIsApplesTrackpad() {
        var g = SpaceGesture(x: 100, y: 20, time: 0)
        XCTAssertEqual(g.moved(x: 104, y: 20, time: 0.3), [], "pausing with a resting thumb")
        XCTAssertEqual(g.moved(x: 115, y: 20, time: 0.45), [.beginGlide], "glide before the AI time")
        XCTAssertEqual(g.moved(x: 142, y: 20, time: 1.45), [.moveCursor(3)])
        XCTAssertEqual(g.ended(time: 1.5), [.endGlide], "a glide never launches the AI")
    }

    func testHoldingStillLaunchesTheAIWhileTheFingerIsDown() {
        var g = SpaceGesture(x: 100, y: 20, time: 0)
        XCTAssertEqual(g.holdElapsed(), [.openBar])
        XCTAssertEqual(g.moved(x: 160, y: 20, time: 0.9), [], "movement after launch is ignored")
        XCTAssertEqual(g.ended(time: 1.0), [], "nothing more happens on the lift")
    }

    func testFastFlicksCoverMoreGroundThanSlowDrags() {
        var slow = SpaceGesture(x: 0, y: 0, time: 0)
        _ = slow.moved(x: 11, y: 0, time: 0.05)
        var fast = slow
        XCTAssertEqual(slow.moved(x: 101, y: 0, time: 1.05), [.moveCursor(10)])   // 90pt/s
        XCTAssertEqual(fast.moved(x: 101, y: 0, time: 0.1), [.moveCursor(26)])    // 1800pt/s → 2.6×
    }

    func testLateTimerStillLaunchesByTheTouchClock() {
        // Busy main thread: the lift or a move arrives before the timer ran.
        var lift = SpaceGesture(x: 100, y: 20, time: 10)
        XCTAssertEqual(lift.ended(time: 10.6), [.openBar])
        var move = SpaceGesture(x: 100, y: 20, time: 10)
        XCTAssertEqual(move.moved(x: 130, y: 20, time: 10.6), [.openBar],
                       "the hold completed before the move was seen")
    }

    func testSlidingOffOnlyCancelsBeforeTheHoldByTheTouchClock() {
        let g = SpaceGesture(x: 100, y: 20, time: 5)
        XCTAssertTrue(g.isUndecided(at: 5.3))
        XCTAssertFalse(g.isUndecided(at: 5.6), "held past the ring, even if the timer is late")
    }

    func testReleaseAfterCancelDoesNothing() {
        var g = SpaceGesture(x: 100, y: 20, time: 0)
        _ = g.moved(x: 120, y: 20, time: 0.1)
        XCTAssertEqual(g.cancelled(), [.endGlide])
        XCTAssertEqual(g.ended(time: 2), [])
        XCTAssertEqual(g.holdElapsed(), [])
    }

    // MARK: Cursor mirror — glide by what the user sees

    func testMirrorStepsWholeGraphemesAsUTF16Offsets() {
        // "é" here is e + U+0301: one grapheme, two UTF-16 units.
        let decomposedE = "e\u{301}"
        var m = CursorMirror(before: "ok 👍🏽 " + decomposedE, after: "🇮🇳!")
        XCTAssertEqual(m.offset(forGraphemes: -1), -2, "decomposed é is 2 units")
        XCTAssertEqual(m.offset(forGraphemes: -1), -1, "the space")
        XCTAssertEqual(m.offset(forGraphemes: -1), -4, "thumbs up + skin tone is 4 units")
        XCTAssertEqual(m.offset(forGraphemes: 3), 7, "and back across all three")
        XCTAssertEqual(m.offset(forGraphemes: 1), 4, "a flag is 4 units")
        XCTAssertFalse(m.isStale)
    }

    func testMirrorFallsBackToSingleUnitsAndGoesStaleWhenExhausted() {
        var m = CursorMirror(before: "a", after: "")
        XCTAssertEqual(m.offset(forGraphemes: -3), -3)
        XCTAssertTrue(m.isStale, "the host may hold more text than the proxy showed")
    }
}
