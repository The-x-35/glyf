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
        // Found on a real clipboard (2026-09-24): a 38-character webhook
        // signing secret went into history under the old rules.
        XCTAssertEqual(SecretScanner.scan("whsec_Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4z"), .privateKeyOrToken)
        XCTAssertEqual(SecretScanner.scan("github_pat_11ABCDEFG0123456789_abcdefghij"), .privateKeyOrToken)
        XCTAssertEqual(SecretScanner.scan("AIzaSyA1b2C3d4E5f6G7h8I9j0KlMnOpQrStUvW"), .privateKeyOrToken)
        XCTAssertEqual(SecretScanner.scan("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcdefghijklmnop"), .privateKeyOrToken)
        XCTAssertEqual(SecretScanner.scan("Zq8Lr2Tx5Vm9Kc3Pw7Jd1Hs6Gf4Nb0Ya"), .privateKeyOrToken)
        // Ordinary copies stay: words, a link, a skim-length id.
        XCTAssertEqual(SecretScanner.scan("See you at Sunset Boulevard at 7pm"), .clean)
        XCTAssertEqual(SecretScanner.scan("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .clean)
        XCTAssertEqual(SecretScanner.scan("sk-"), .clean)
        // Wallet addresses are for sharing (the pay chip reads a copied one).
        XCTAssertEqual(SecretScanner.scan("8QvSMrFfYYo2RwoDN6bNpS2d3F8JKTzN8Cw2vAh3tNqP"), .clean)
        XCTAssertEqual(SecretScanner.scan("0x52908400098527886E0F7030069857D2E4169EE7"), .clean)
        XCTAssertEqual(SecretScanner.scan("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"), .clean)
        // Their keys are not.
        XCTAssertEqual(SecretScanner.scan(String(repeating: "5KQwrPbwdL6PhXujxW37FSSQZ1JiwsST4cqQzDeyXtP79zkvFD3", count: 1)
            + "4YxN2QkHj7Lm9Pq3Rs6Tv8Wx1Yz2Ab3Cd4Ef"), .privateKeyOrToken)
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

        // A day-old copy is still there to reach for: two days is the window.
        let yesterday = items.map {
            ClipItem(text: $0.text, ts: now.addingTimeInterval(-24 * 3600), pinned: false)
        }
        XCTAssertEqual(ClipboardStore.prune(yesterday, now: now).count, items.count)

        // Past it, only what was pinned survives — pinning is what makes a
        // copy permanent, and it outlives any age.
        var aged = items.map {
            ClipItem(text: $0.text, ts: now.addingTimeInterval(-49 * 3600), pinned: false)
        }
        aged[3].pinned = true
        let pruned = ClipboardStore.prune(aged, now: now)
        XCTAssertEqual(pruned.count, 1)
        XCTAssertTrue(pruned[0].pinned)
        let ancient = [ClipItem(text: "kept", ts: now.addingTimeInterval(-400 * 24 * 3600),
                                pinned: true)]
        XCTAssertEqual(ClipboardStore.prune(ancient, now: now).count, 1)
    }

    /// What counts as a link for the clipboard's Link pill. A bare domain
    /// must count — copying tryglyf.com and not finding it under Link is
    /// what sent this rule back for a rewrite.
    func testWhatCountsAsALink() {
        for link in ["tryglyf.com", "https://www.tryglyf.com",
                     "http://example.co.uk/a/b?c=d", "www.apple.com",
                     "apple.com/watch", "https://x.com/arpitx35"] {
            XCTAssertTrue(ClipboardStore.isLink(link), "\(link) is a link")
        }
        for text in ["Flight PNR QR7GH2 · 14 Oct", "meet me at the pier",
                     "42 glass lane, Delhi", "hello", "3.14",
                     // A sentence that mentions a link is still a sentence:
                     // Text and Link must stay exclusive or the pills stop
                     // adding up to All.
                     "check this out https://apple.com",
                     // An address is something you paste, not something you
                     // follow.
                     "arpit@example.com"] {
            XCTAssertFalse(ClipboardStore.isLink(text), "\(text) is not a link")
        }
        XCTAssertFalse(ClipboardStore.isLink("   "))
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
        XCTAssertEqual(s.schemaVersion, 8)
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

    /// Several keys may point at the same thing, and that is the person's
    /// choice to make. Someone who wants the vault on S as well as V keeps
    /// both — nothing may quietly unbind a key behind their back.
    func testTwoKeysMayOpenTheSameThing() {
        var both = GlyfSettings()
        both.schemaVersion = 7
        both.bindings = ["s": "surface:vault", "v": "surface:vault", "t": "surface:translate-hud"]
        let s = SettingsStore.migrated(both)
        XCTAssertEqual(s.bindings["s"], "surface:vault", "S keeps what it was given")
        XCTAssertEqual(s.bindings["v"], "surface:vault")
    }

    /// The clipboard fills itself now, and an install from before the change
    /// gets that too. A file written earlier has no answer for these at all —
    /// it decodes as nil, not as the new default — so the migration is the
    /// only thing that can hand it one.
    func testOlderInstallsGetTheClipboardFillingItself() {
        var old = GlyfSettings()
        old.schemaVersion = 7
        old.clipboardCaptureAll = nil
        old.clipboardScreenshots = nil
        let s = SettingsStore.migrated(old)
        XCTAssertEqual(s.clipboardCaptureAll, true)
        XCTAssertEqual(s.clipboardScreenshots, true)
    }

    /// …but a no is a no. Someone who turned either off keeps it off: the
    /// migration fills a blank, it does not overrule an answer.
    func testTurningTheClipboardOffSurvivesTheMigration() {
        var said = GlyfSettings()
        said.schemaVersion = 7
        said.clipboardCaptureAll = false
        said.clipboardScreenshots = false
        let s = SettingsStore.migrated(said)
        XCTAssertEqual(s.clipboardCaptureAll, false)
        XCTAssertEqual(s.clipboardScreenshots, false)
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

    func testAnEventAddedToGoogleShowsUntilThePhoneHasIt() {
        let cal = calendarAt()
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        let added = CalendarText.Event(title: "Demo call", start: at(18), end: at(19), allDay: false,
                                       location: "https://meet.google.com/abc-defg-hij", id: "google:e1")
        let lunch = CalendarText.Event(title: "Lunch", start: at(13), end: at(14), allDay: false)

        // Not on the phone yet: the list shows the keyboard's copy, still waiting.
        var shown = CalendarText.withAdded([added], in: [lunch], now: at(12))
        XCTAssertEqual(CalendarText.events(on: day, in: shown.events, calendar: cal).map(\.title),
                       ["Lunch", "Demo call"])
        XCTAssertEqual(shown.pending, [added])

        // Google synced it: the phone's copy (same title, same start) is the one shown.
        let synced = CalendarText.Event(title: "demo call ", start: at(18), end: at(19), allDay: false, id: "EK-9")
        shown = CalendarText.withAdded([added], in: [lunch, synced], now: at(12))
        XCTAssertEqual(shown.events, [lunch, synced])
        XCTAssertTrue(shown.pending.isEmpty)

        // Another event at the same time is not it; an event long over is let go.
        let other = CalendarText.Event(title: "Gym", start: at(18), end: at(19), allDay: false)
        XCTAssertEqual(CalendarText.withAdded([added], in: [other], now: at(12)).pending, [added])
        let nextWeek = cal.date(byAdding: .day, value: 7, to: at(12))!
        XCTAssertTrue(CalendarText.withAdded([added], in: [], now: nextWeek).pending.isEmpty)

        // The app's file keeps the id, so the copy is found again after a reload.
        let json: [String: Any] = ["events": [["title": "Demo call", "start": "2026-09-27T12:30:00Z",
                                               "end": "2026-09-27T13:30:00Z", "id": "google:e1"]]]
        XCTAssertEqual(CalendarText.events(fromJSON: json).first?.id, "google:e1")
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

    // MARK: Money where you are

    func testMoneyChipConvertsWhereYouAreAndNeverGuesses() {
        let rates = Smart.RatesSnapshot(fiat: ["USD": 1, "INR": 95.88, "EUR": 0.8726],
                                        crypto: ["SOL": 111.77], local: "INR")
        XCTAssertEqual(Smart.chip(for: "it costs $13", fields: [], rates: rates),
                       .money(shown: "$13 = ₹1,246.44", insert: " = ₹1,246.44"))
        XCTAssertEqual(Smart.chip(for: "₹500", fields: [], rates: rates),
                       .money(shown: "₹500 = $5.21", insert: " = $5.21"), "local money reads in dollars")
        XCTAssertEqual(Smart.chip(for: "about 20 euros", fields: [], rates: rates)?.value, "€20 = ₹2,197.57")
        XCTAssertEqual(Smart.chip(for: "buying $sol", fields: [], rates: rates),
                       .money(shown: "1 SOL = $111.77", insert: " = $111.77"), "a price is quoted in dollars")
        // No rate, no chip — and the keyboard is told what to fetch.
        XCTAssertNil(Smart.chip(for: "$13", fields: []))
        XCTAssertTrue(Smart.looksLikeMoney("$13"))
        XCTAssertFalse(Smart.looksLikeMoney("flight AI 2021"))
        XCTAssertEqual(Smart.cashtag(in: "send $sol"), "SOL")
        XCTAssertNil(Smart.cashtag(in: "$13"))
        // A name works too, for whoever doesn't know the ticker.
        XCTAssertEqual(Smart.cashtag(in: "whats $apple at"), nil)
        XCTAssertEqual(Smart.cashtag(in: "how is $bitcoin"), "BITCOIN")
        XCTAssertEqual(Smart.cashtag(in: "$microsoft"), "MICROSOFT")
        XCTAssertNil(Smart.chip(for: "$usdc", fields: [], rates: rates), "a ticker with no price yet")
        // A sum still wins over a conversion; a dollar amount at home stays quiet.
        XCTAssertEqual(Smart.chip(for: "$10*3", fields: [], rates: rates), .calc(value: "$30", hasEquals: false))
        let home = Smart.RatesSnapshot(fiat: ["USD": 1, "INR": 95.88], crypto: [:], local: "USD")
        XCTAssertNil(Smart.chip(for: "$13", fields: [], rates: home))
    }

    // MARK: Games

    func testSnakeTurnsWrapsAndNeverDoublesBack() {
        let game = SnakeGame(cols: 10, rows: 5, seed: 7)
        XCTAssertEqual(game.body.first, Games.Cell(x: 5, y: 2))
        game.step()
        XCTAssertEqual(game.body.first, Games.Cell(x: 6, y: 2))
        game.turn(.left)                       // straight back: ignored
        game.turn(.up)
        game.step()
        XCTAssertEqual(game.body.first, Games.Cell(x: 6, y: 1))
        game.step(); game.step()
        XCTAssertEqual(game.body.first, Games.Cell(x: 6, y: 4), "off the top, in at the bottom")
        XCTAssertEqual(game.body.count, 3)
    }

    func testSnakeGrowsWhenItEatsAndFoodNeverLandsOnIt() {
        let game = SnakeGame(cols: 12, rows: 6, seed: 3)
        var steps = 0
        while game.score < 3 && steps < 400 {
            // Head for the food: across first, then up or down.
            let head = game.body[0], food = game.food
            if head.x != food.x { game.turn(food.x > head.x ? .right : .left) }
            else if head.y != food.y { game.turn(food.y > head.y ? .down : .up) }
            XCTAssertFalse(game.body.contains(food))
            if game.step() == .crashed { break }
            steps += 1
        }
        XCTAssertEqual(game.score, 3)
        XCTAssertEqual(game.body.count, 6)
        XCTAssertLessThan(game.interval, 0.151)
    }

    func testSnakeEndsWhenItRunsIntoItself() {
        let body = (0..<6).map { Games.Cell(x: 6 - $0, y: 3) }   // head at 6, heading right
        let game = SnakeGame(cols: 12, rows: 6, seed: 1, body: body)
        game.turn(.up); game.step()
        game.turn(.left); game.step()
        game.turn(.down)
        XCTAssertEqual(game.step(), .crashed)
        XCTAssertTrue(game.over)
    }

    func testChompMazeIsOneWholeMaze() {
        let game = ChompGame(seed: 1)
        XCTAssertEqual(game.pellets.count, 107)
        XCTAssertEqual(game.powers.count, 4)
        // Every pellet can be reached from the start, through the side tunnel too.
        var seen: Set<Games.Cell> = [game.start], queue = [game.start]
        while let c = queue.popLast() {
            for d in Games.Dir.allCases {
                let n = game.next(c, d)
                if game.open(n), seen.insert(n).inserted { queue.append(n) }
            }
        }
        XCTAssertTrue(game.pellets.isSubset(of: seen))
        XCTAssertTrue(game.powers.isSubset(of: seen))
    }

    func testChompEatsAsItRunsAndTurnsWhenTheMazeLetsIt() {
        let game = ChompGame(seed: 1)
        game.wanted = .up                      // a wall above the start: kept for later
        game.step(); game.step(); game.step()
        XCTAssertEqual(game.player, Games.Cell(x: 7, y: 7))
        XCTAssertEqual(game.score, 30)
        game.step()
        XCTAssertEqual(game.player, Games.Cell(x: 7, y: 6), "turned up at the first opening")
        XCTAssertEqual(game.heading, .up)
    }

    func testGhostsLeaveThePenThroughTheDoor() {
        let game = ChompGame(seed: 1)
        var through = false
        for _ in 0..<6 {
            game.step()
            if game.ghosts[0].at == game.door { through = true }
        }
        XCTAssertTrue(through)
        XCTAssertEqual(game.ghosts[0].state, .roaming)
        XCTAssertFalse(game.open(game.door), "Chomp can't go in")
    }

    func testAPowerPelletMakesGhostsEdible() {
        let game = ChompGame(seed: 1)
        game.stage(player: Games.Cell(x: 2, y: 1), heading: .left, ghost: Games.Cell(x: 8, y: 1))
        XCTAssertEqual(game.step(), [.power])
        XCTAssertTrue(game.ghosts[0].scared)
        XCTAssertGreaterThan(game.frightened, 0)
        game.stage(player: Games.Cell(x: 1, y: 1), heading: .right, ghost: Games.Cell(x: 2, y: 1))
        let events = game.step()
        XCTAssertTrue(events.contains(.ghost(200)))
        XCTAssertEqual(game.score, 50 + 10 + 200)
        // An eaten ghost is back in the pen, waiting to come out again.
        XCTAssertEqual(game.ghosts[0].at, game.pen[0])
        if case .home = game.ghosts[0].state {} else { XCTFail("an eaten ghost waits in the pen") }
    }

    func testAGhostCostsALifeAndClearingTheMazeStartsTheNext() {
        let game = ChompGame(seed: 1)
        game.stage(player: Games.Cell(x: 5, y: 3), heading: .right, ghost: Games.Cell(x: 6, y: 3), ghostDir: .left)
        XCTAssertTrue(game.step().contains(.caught))
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.player, game.start)
        XCTAssertGreaterThan(game.pause, 0)
        game.stage(player: Games.Cell(x: 2, y: 3), heading: .left, pellets: [Games.Cell(x: 1, y: 3)])
        XCTAssertEqual(game.step(), [.pellet, .cleared])
        XCTAssertEqual(game.level, 2)
        XCTAssertEqual(game.pellets.count, 107)
        XCTAssertLessThan(game.interval, 0.14)
    }

    // MARK: The brand key

    func testTheKeyCarriesTheAppIconsMark() {
        // The outline spans its ink box exactly: 1 tall, the icon letter's aspect wide.
        let box = GlyfMark.gPath(in: CGRect(x: 0, y: 0, width: 0, height: 100)).boundingBoxOfPath
        XCTAssertEqual(box.height, 100, accuracy: 0.5)
        XCTAssertEqual(box.width / box.height, GlyfMark.gAspect, accuracy: 0.002)
        // The strip's key: 41 by 30; the letter centred across it, the dot
        // where the 1024pt icon has it (centre 1.0379 letter-heights right of
        // the letter, 0.4927 above it, 0.3276 wide), the mark centred down it.
        let cap = GlyfMark.Keycap(height: 30, x: 0, midY: 15)
        let h = cap.letter.height
        XCTAssertEqual(cap.key.size, CGSize(width: 41, height: 30))
        XCTAssertEqual(cap.letter.midX, cap.key.midX, accuracy: 0.01)
        XCTAssertEqual(cap.dot.midX - cap.letter.minX, h * 1.0379, accuracy: 0.01)
        XCTAssertEqual(cap.letter.minY - cap.dot.midY, h * 0.4927, accuracy: 0.01)
        XCTAssertEqual(cap.dot.width, h * 0.3276, accuracy: 0.01)
        XCTAssertEqual((cap.dot.minY + cap.letter.maxY) / 2, cap.key.midY, accuracy: 0.01)
        XCTAssertTrue(cap.key.contains(cap.dot) && cap.key.contains(cap.letter))
    }

    // MARK: The model's suggestion

    func testModelSuggestionIsItsOwnActionAndTypesNothing() {
        let chip = Smart.Chip.action(label: "Tidy this up", query: "ya ok will send the deck", intent: "rewrite")
        XCTAssertNil(chip.verb, "a sparkle marks it: its words are already the action")
        XCTAssertEqual(chip.value, "Tidy this up")
        XCTAssertEqual(chip.insert, "", "a tap runs hold space on the sentence instead of typing")
    }
}
