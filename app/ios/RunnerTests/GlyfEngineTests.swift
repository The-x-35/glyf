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
        s.toolbarOrder = ["dictation", "settings"] // an old file, in the user's order
        s.schemaVersion = 1
        s = SettingsStore.migrated(s)
        XCTAssertEqual(Set(s.toolbarOrder), Set(GlyfSettings.Toolbar.defaultOrder),
                       "the gear left the strip for the g menu")
        XCTAssertEqual(s.toolbarOrder.first, "search")
        XCTAssertEqual(s.toolbarOrder.dropFirst().first, "dictation",
                       "the user's own order must survive under Search")
    }

    /// An old file ends up current: T's one-shot translate upgrades to the
    /// strip, a glyf the person built keeps its key, canned glyfs are gone,
    /// and the vault moves from S to V.
    func testMigrationToCurrentBindings() {
        var old = GlyfSettings()
        old.schemaVersion = 2
        old.customTitles = ["user.abc": "Say No Politely"]
        old.bindings = [
            "t": "glyf.translate",       // stock M2 default → upgrades
            "n": "user.abc",             // built by the person → SURVIVES
            "p": "glyf.proofread",       // canned → removed
            "s": "surface:vault",        // old vault key → moves to V
        ]
        let s = SettingsStore.migrated(old)
        XCTAssertEqual(s.schemaVersion, 7)
        XCTAssertEqual(s.bindings["t"], "surface:translate-hud")
        XCTAssertEqual(s.bindings["n"], "user.abc")
        XCTAssertNil(s.bindings["p"])
        XCTAssertNil(s.bindings["s"])
        XCTAssertEqual(s.bindings["v"], "surface:vault")
    }

    /// Someone who put something else on V keeps it; the vault stays on S.
    func testVaultStaysOnSWhenVIsTaken() {
        var old = GlyfSettings()
        old.schemaVersion = 6
        old.customTitles = ["user.v": "Voice note"]
        old.bindings = ["s": "surface:vault", "v": "user.v", "t": "surface:translate-hud"]
        let s = SettingsStore.migrated(old)
        XCTAssertEqual(s.bindings["s"], "surface:vault")
        XCTAssertEqual(s.bindings["v"], "user.v")
    }

    /// A canned glyf someone had on T is gone with the rest; T translates.
    func testCannedGlyfOnTGivesWayToTranslate() {
        var old = GlyfSettings()
        old.schemaVersion = 2
        old.bindings = ["t": "rewrite.polite"]
        let s = SettingsStore.migrated(old)
        XCTAssertEqual(s.bindings["t"], "surface:translate-hud")
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

    // MARK: Tour coach — the website's steps on the real keyboard

    private func field(_ kind: String, _ label: String, _ value: String) -> VaultField {
        VaultField(id: kind, kind: kind, label: label, value: value)
    }

    func testCoachWalksMapsSearchLikeTheWebsite() {
        var s = TourCoach.State(step: "sakshi:0", text: "")
        XCTAssertEqual(TourCoach.coach(s), .init(target: "toolbar:search", label: "Search"))
        s.panel = .search(tab: "search", view: .landing(rows: 0), query: "")
        XCTAssertEqual(TourCoach.coach(s), .init(target: "search:tab:maps", label: "Maps"))
        s.panel = .search(tab: "maps", view: .landing(rows: 0), query: "coffee near me")
        XCTAssertEqual(TourCoach.coach(s), .init(target: "search:go", label: "Search"))
        s.panel = .search(tab: "maps", view: .results(3), query: "coffee near me")
        XCTAssertEqual(TourCoach.coach(s), .init(target: "search:card:*", label: "Tap to share"))
        s.panel = .none
        s.text = "📍 Blue Tokai · Bandra"
        XCTAssertNil(TourCoach.coach(s), "the chat points at Send")
    }

    func testCoachGoesThroughTheMenuWhenTheToolIsOffTheStrip() {
        var s = TourCoach.State(step: "kabir:0", text: "")
        s.stripTools = []
        XCTAssertEqual(TourCoach.coach(s), .init(target: "toolbar:glyf", label: "Tap g"))
        s.panel = .menu
        XCTAssertEqual(TourCoach.coach(s), .init(target: "shell:tile:search", label: "Search"))
        XCTAssertFalse(TourCoach.allowsChip("paste", step: "sakshi:0"), "a chip would cover the tools")
        XCTAssertTrue(TourCoach.allowsChip("vault:upi", step: "zoya:1"))
        XCTAssertFalse(TourCoach.allowsChip("paste", step: "semi:0"), "an old copy is not the address")
        XCTAssertTrue(TourCoach.allowsChip("paste", step: "semi:0", copied: true))
    }

    func testCoachOpensTheVaultOnWhicheverKeyHoldsIt() {
        let home = field("address", "Home", "12 Hill Road, Bandra")
        var s = TourCoach.State(step: "mumma:0", text: "")
        s.fields = [field("name", "Name", "Arpit"), home]
        s.vaultKey = "v"
        XCTAssertEqual(TourCoach.coach(s), .init(target: "key:v", label: "Hold V"))
        s.vaultKey = "q"
        XCTAssertEqual(TourCoach.coach(s), .init(target: "key:q", label: "Hold Q"))
        s.panel = .vault
        XCTAssertEqual(TourCoach.coach(s), .init(target: "vault:card:1", label: "Tap Home"))
        s.panel = .none
        s.text = "12 Hill Road, Bandra"
        XCTAssertNil(TourCoach.coach(s))
    }

    func testCoachPointsAtTheRightSuggestionForHinglish() {
        var s = TourCoach.State(step: "rohan:0", text: "haan yaar pakak")
        s.suggestions = ["pakak", "pakka", "pakad"]
        XCTAssertEqual(TourCoach.coach(s), .init(target: "suggest:1", label: "Tap pakka"))
        s.text = "haan yaar pakka definately"
        s.suggestions = ["definately", "definitely"]
        XCTAssertEqual(TourCoach.coach(s), .init(target: "suggest:1", label: "Tap definitely"))
    }

    func testCoachRewriteMathAndTranslate() {
        var neha = TourCoach.State(step: "neha:0", text: "ya ill send it by 6 dont worry")
        XCTAssertEqual(TourCoach.coach(neha), .init(target: "key:space", label: "Hold glyf"))
        neha.panel = .act(working: true, options: false)
        XCTAssertNil(TourCoach.coach(neha))
        neha.panel = .act(working: false, options: true)
        XCTAssertEqual(TourCoach.coach(neha), .init(target: "act:option:work", label: "Professional"))

        var zoya = TourCoach.State(step: "zoya:0", text: "3480/4")
        zoya.chip = .calc(value: "870", hasEquals: false)
        XCTAssertEqual(TourCoach.coach(zoya), .init(target: "strip:smart", label: "Tap"))

        var sofia = TourCoach.State(step: "sofia:0", text: "")
        sofia.translateKey = "t"
        XCTAssertEqual(TourCoach.coach(sofia), .init(target: "key:t", label: "Hold T"))
        sofia.panel = .translate(ready: false, target: nil)
        XCTAssertEqual(TourCoach.autotype(sofia), "see you tomorrow")
        sofia.text = "see you tomorrow"
        sofia.panel = .translate(ready: true, target: "Spanish")
        XCTAssertEqual(TourCoach.coach(sofia), .init(target: "hud:replace", label: "Replace"))
    }

    // MARK: Settings file shared with the app

    func testKeyboardWritesKeepTheAppsOwnKeys() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "signedInWith": "google", "privyAppId": "public-id", "tourStep": "semi:0", "haptics": true,
        ])
        var s = GlyfSettings()
        s.haptics = false
        s.tourStep = nil
        let out = SettingsStore.merged(try JSONEncoder().encode(s), over: existing)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
        XCTAssertEqual(json["signedInWith"] as? String, "google", "the app's sign-in survives")
        XCTAssertEqual(json["privyAppId"] as? String, "public-id")
        XCTAssertEqual(json["haptics"] as? Bool, false, "the keyboard's own change lands")
        XCTAssertNil(json["tourStep"], "a field the keyboard cleared is removed")
    }

    // MARK: Calendar words

    private func calendarAt(_ tz: String = "Asia/Kolkata") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    func testCalendarSharesAnEventAndFreeTime() throws {
        let cal = calendarAt()
        let en = Locale(identifier: "en_US")
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        let events = [
            CalendarText.Event(title: "Standup", start: at(10), end: at(10, 30), allDay: false),
            CalendarText.Event(title: "Design review", start: at(15), end: at(16), allDay: false, location: "Studio"),
        ]
        // Time formats use a narrow no-break space before AM/PM.
        func plain(_ t: String) -> String { t.replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(plain(CalendarText.insert(events[1], calendar: cal, locale: en)),
                       "📅 Design review · Fri, Sep 18, 3:00–4:00 PM · Studio")
        XCTAssertEqual(plain(CalendarText.freeTime(on: day, in: events, calendar: cal, locale: en, now: day)),
                       "I'm free Fri, Sep 18, 9:00–10:00 AM, 10:30 AM–3:00 PM and 4:00–9:00 PM")
        XCTAssertEqual(CalendarText.freeTime(on: day, in: [], calendar: cal, locale: en, now: day), "I'm free all day Fri, Sep 18")
        XCTAssertEqual(plain(CalendarText.freeTime(on: day, in: events, calendar: cal, locale: en, now: at(15, 10))),
                       "I'm free Fri, Sep 18, 4:00–9:00 PM", "today starts from now")
        let allDay = [CalendarText.Event(title: "Offsite", start: cal.startOfDay(for: day),
                                         end: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day))!, allDay: true)]
        XCTAssertEqual(CalendarText.freeTime(on: day, in: allDay, calendar: cal, locale: en, now: day), "I'm busy all day Fri, Sep 18")
    }

    func testCalendarReadsTheAppsFile() {
        let json: [String: Any] = ["events": [
            ["title": "Lunch", "start": "2026-09-18T07:30:00Z", "end": "2026-09-18T08:30:00Z", "allDay": false, "color": "#FF9500"],
            ["title": "", "start": "bad", "end": "2026-09-18T08:30:00Z"],
        ]]
        let events = CalendarText.events(fromJSON: json)
        XCTAssertEqual(events.count, 1, "a row it cannot read is skipped")
        XCTAssertEqual(events[0].title, "Lunch")
        XCTAssertEqual(events[0].color, "#FF9500")
        XCTAssertTrue(CalendarText.events(fromJSON: nil).isEmpty)
    }

    // MARK: Saved details in everyday words

    func testVaultChipHearsEverydayWordsButNotQuestions() {
        let fields = [
            VaultField(id: "1", kind: "address", label: "Home", value: "42 Glass Lane"),
            VaultField(id: "2", kind: "upi", label: "UPI", value: "arpit@okbank"),
            VaultField(id: "3", kind: "phone", label: "Mobile", value: "+91 98765 43210"),
            VaultField(id: "4", kind: "email", label: "Email", value: "a@b.co"),
        ]
        func kind(_ t: String) -> String? {
            if case .vault(let f)? = Smart.chip(for: t, fields: fields) { return f.kind }
            return nil
        }
        XCTAssertEqual(kind("just gpay me on"), "upi")
        XCTAssertEqual(kind("haan ship it to"), "address")
        XCTAssertEqual(kind("ok here's my number:"), "phone")
        XCTAssertEqual(kind("you can email me at"), "email")
        XCTAssertNil(kind("what's your address?"), "a question for someone else")
        XCTAssertNil(kind("send me ur upi"))
        XCTAssertNil(kind("my number is 98765"), "already typed")
        XCTAssertNil(kind("my wallet address"), "the wallet was asked for, and none is saved")
    }
}
