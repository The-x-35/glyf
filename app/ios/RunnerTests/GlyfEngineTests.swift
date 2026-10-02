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

    /// Emoji, Keys and Shorthand left the g menu (user, 2026-09-29) for GIFs,
    /// My glyfs and the vault. A strip or order saved with them keeps its
    /// places: a pinned Emoji is a pinned GIFs, Keys on the strip is My
    /// glyfs there, and a hidden Shorthand never hides the Vault it became.
    func testRetiredToolsMoveToTheToolsThatTookThemIn() {
        var old = GlyfSettings()
        old.toolbarOrder = ["search", "emoji", "vault", "shorthand", "keys", "clipboard"]
        old.toolbarHidden = ["shorthand", "clipboard"]
        old.menuOrder = ["emoji", "keys", "rewrite", "glyfs", "shorthand", "vault"]
        let s = SettingsStore.migrated(old)
        XCTAssertEqual(s.toolbarOrder.prefix(5), ["search", "gifs", "vault", "glyfs", "clipboard"])
        XCTAssertEqual(s.stripTools.prefix(4), ["search", "gifs", "vault", "glyfs"])
        XCTAssertFalse(s.stripTools.contains("clipboard"), "hidden stays hidden")
        XCTAssertEqual(s.menuOrder, ["gifs", "glyfs", "rewrite", "vault"])
        XCTAssertEqual(SettingsStore.migrated(s), s, "and it happens once")
    }

    /// Emoji hidden from the strip is GIFs hidden from it, so the g menu
    /// offers GIFs.
    func testAHiddenEmojiIsAHiddenGIFs() {
        var old = GlyfSettings()
        old.toolbarOrder = GlyfSettings.Toolbar.defaultOrder + ["emoji"]
        old.toolbarHidden = ["emoji"]
        let s = SettingsStore.migrated(old)
        XCTAssertTrue(s.toolbarOrder.contains("gifs"))
        XCTAssertEqual(s.toolbarHidden, ["gifs"])
        XCTAssertEqual(s.stripTools, GlyfSettings.Toolbar.defaultOrder)
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
        // On the strip it has no tile, and the strip stays up over the menu.
        s.stripTools = ["search"]
        XCTAssertEqual(TourCoach.coach(s), .init(target: "toolbar:search", label: "Search"))
        XCTAssertFalse(TourCoach.allowsChip("paste", step: "sakshi:0"), "a chip would cover the tools")
        XCTAssertTrue(TourCoach.allowsChip("vault:wallet", step: "zoya:1"))
        XCTAssertFalse(TourCoach.allowsChip("paste", step: "semi:0"), "an old copy is not the address")
        XCTAssertTrue(TourCoach.allowsChip("paste", step: "semi:0", copied: true))
    }

    func testCoachOpensTheVaultOnWhicheverKeyHoldsIt() {
        let home = field("address", "Home", "12 Hill Road, Bandra")
        var s = TourCoach.State(step: "mom:0", text: "")
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

    func testCoachRewriteMathAndTranslate() {
        var neha = TourCoach.State(step: "neha:0", text: "ya ill send it by 6 dont worry")
        XCTAssertEqual(TourCoach.coach(neha), .init(target: "key:space", label: "Hold glyf"))
        neha.panel = .act(working: true, options: false)
        XCTAssertNil(TourCoach.coach(neha))
        neha.panel = .act(working: false, options: true)
        XCTAssertEqual(TourCoach.coach(neha), .init(target: "act:option:work", label: "Professional"))

        var zoya = TourCoach.State(step: "zoya:0", text: "236/4")
        zoya.chip = .calc(value: "59", hasEquals: false)
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
        XCTAssertEqual(Smart.chip(for: "$10*3", fields: [], rates: rates), .calc(value: "$30", hasEquals: false, expression: "$10*3"))
        // The strip reads the whole sum: "2+5 = 7".
        XCTAssertEqual(Smart.chip(for: "2+5", fields: [])?.value, "2+5 = 7")
        XCTAssertEqual(Smart.chip(for: "what is 12 * 12", fields: [])?.value, "12 * 12 = 144")
        let home = Smart.RatesSnapshot(fiat: ["USD": 1, "INR": 95.88], crypto: [:], local: "USD")
        XCTAssertNil(Smart.chip(for: "$13", fields: [], rates: home))
    }

    /// Every maths symbol answers in the strip (Arpit, 2026-09-29: "not
    /// working on 2-3 ... work for all maths symbols"); only phone numbers,
    /// whole dates, counts and a "<3" heart stay quiet (SmartTest.kt twin).
    func testEveryOperatorAnswersButPhoneNumbersAndDatesDoNot() {
        let sums: [(String, String)] = [("2-3", "-1"), ("3-2", "1"), ("10-11", "-1"), ("9-5", "4"), ("150-45", "105"),
            ("5 - 2", "3"), ("-5+3", "-2"), ("7−2", "5"), ("2x3", "6"), ("2 x 3", "6"), ("2**10", "1,024"),
            ("2^10", "1,024"), ("√16", "4"), ("√2*√2", "2"), ("π*2", "6.28"), ("10 mod 3", "1"),
            ("24/7", "3.43"), ("20% of 150", "30"), ("the room is 10 x 12", "120")]
        for (t, want) in sums { XCTAssertEqual(Smart.calc(t, indianGrouping: false)?.value, want, t) }
        XCTAssertEqual(Smart.calc("5>3")?.value, "true")
        XCTAssertEqual(Smart.calc("2 < 1")?.value, "false")
        XCTAssertEqual(Smart.calc("10 >= 10")?.value, "true")
        XCTAssertEqual(Smart.calc("10-3=")?.hasEquals, true)
        XCTAssertEqual(Smart.calc("10-3=")?.value, "7")
        XCTAssertEqual(Smart.chip(for: "2-3", fields: [])?.value, "2-3 = -1")
        for t in ["call me at 555-1234", "555-1234", "555-123-4567", "+1-555-123-4567", "98765-43210",
                  "born 29/09/2024", "2024/09/29", "2024-09-29", "29-09-2024", "exp 09/2026", "page 2 of 10",
                  "episode 4 of 8", "love u 2 <3", "its 50%", "we won 3"] {
            XCTAssertNil(Smart.calc(t), t)
        }
    }

    /// Audit 2026-09-28: sums people type, and details a sentence asks for.
    func testCalcReadsSumsNotDatesAndGroupsByRegion() {
        XCTAssertNil(Smart.calc("see you 29/09/2024"), "a whole date is not a sum")
        XCTAssertEqual(Smart.calc("10/2 =")?.value, "5")
        XCTAssertEqual(Smart.calc("200 + 10%")?.value, "220", "a percentage added is a share of the left side")
        XCTAssertEqual(Smart.calc("200 - 10%")?.value, "180")
        XCTAssertEqual(Smart.calc("250*400", indianGrouping: true)?.value, "1,00,000")
        XCTAssertEqual(Smart.calc("250*400", indianGrouping: false)?.value, "100,000")
    }

    func testTheRightSavedDetailForWhatTheSentenceAsks() {
        let fields = [VaultField(id: "a", kind: "address", label: "Home", value: "123 Market St"),
                      VaultField(id: "e", kind: "email", label: "Email", value: "me@example.com"),
                      VaultField(id: "p", kind: "phone", label: "Mobile", value: "+1 415 555 0100")]
        XCTAssertEqual(Smart.vaultMatch("my email address is", fields: fields)?.kind, "email")
        XCTAssertEqual(Smart.vaultMatch("my gmail address is", fields: fields)?.kind, "email")
        XCTAssertEqual(Smart.vaultMatch("my phone number is", fields: fields)?.kind, "phone")
        XCTAssertEqual(Smart.vaultMatch("my number is", fields: fields)?.kind, "phone")
        XCTAssertEqual(Smart.vaultMatch("deliver it to", fields: fields)?.kind, "address")
        XCTAssertNil(Smart.vaultMatch("my account number is", fields: fields))
        XCTAssertNil(Smart.vaultMatch("the order number is", fields: fields))
        XCTAssertNil(Smart.vaultMatch("the ip address is", fields: fields))
    }

    /// "$sol" is SOL's price, never your wallet (user, 2026-09-28: "when i
    /// type $sol i should see sol price but i see my wallet address").
    func testACashtagIsAPriceNeverYourWallet() {
        let wallet = [VaultField(id: "w", kind: "wallet", label: "Solana", value: "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj")]
        // Before the price has come: nothing, not the wallet.
        XCTAssertNil(Smart.chip(for: "$sol", fields: wallet))
        XCTAssertNil(Smart.chip(for: "whats $solana at", fields: wallet))
        // Once it has: the price.
        let rates = Smart.RatesSnapshot(crypto: ["SOL": 117.66, "APPL": 339.43],
                                        tickers: ["SOL": "SOL", "APPL": "AAPL"])
        XCTAssertEqual(Smart.chip(for: "$sol", fields: wallet, rates: rates),
                       .money(shown: "1 SOL = $117.66", insert: " = $117.66"))
        // A slip for AAPL reads as the market's ticker.
        XCTAssertEqual(Smart.chip(for: "$appl", fields: wallet, rates: rates)?.value, "1 AAPL = $339.43")
        // The wallet is for when the sentence asks for it.
        XCTAssertEqual(Smart.chip(for: "my sol address is", fields: wallet), .vault(field: wallet[0]))
        XCTAssertEqual(Smart.chip(for: "solana wallet:", fields: wallet), .vault(field: wallet[0]))
        XCTAssertEqual(Smart.chip(for: "send it to my wallet", fields: wallet), .vault(field: wallet[0]))
        XCTAssertNil(Smart.chip(for: "i bought some sol", fields: wallet))
        XCTAssertNil(Smart.chip(for: "is usdc", fields: wallet))
    }

    /// A saved detail only where the sentence leads into it (2026-09-28 audit:
    /// "wrong address", "can you email" and "i lost my phone" offered yours).
    /// SmartTest.aDetailOnlyWhereTheSentenceLeadsIntoIt, the twin.
    func testADetailOnlyWhereTheSentenceLeadsIntoIt() {
        let all = [VaultField(id: "a", kind: "address", label: "Home", value: "123 Market St"),
                   VaultField(id: "e", kind: "email", label: "Email", value: "me@example.com"),
                   VaultField(id: "p", kind: "phone", label: "Mobile", value: "+1 415 555 0100"),
                   VaultField(id: "w", kind: "wallet", label: "Wallet address", value: "4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA"),
                   VaultField(id: "i", kind: "social", label: "Instagram", value: "@me"),
                   VaultField(id: "u", kind: "upi", label: "UPI", value: "me@okbank")]
        let asks: [(String, String)] = [
            ("my email is", "email"), ("Email ID:", "email"), ("you can email me at", "email"),
            ("address:", "address"), ("our office address:", "address"), ("ship it to", "address"),
            ("my number is", "phone"), ("phone:", "phone"), ("reach me at", "phone"),
            ("my wallet", "wallet"), ("sol address:", "wallet"), ("follow me on insta", "social"),
            ("upi id:", "upi")]
        for (text, kind) in asks {
            XCTAssertEqual(Smart.vaultMatch(text, fields: all)?.kind, kind, text)
        }
        // The word alone offers an email now (Arpit, 2026-10-01); the verb
        // still doesn't.
        XCTAssertEqual(Smart.vaultMatch("email", fields: all)?.kind, "email")
        for text in ["can you email", "i'll email", "please email", "what's the address", "wrong address",
                     "the address is", "ip address:", "i lost my phone", "my phone is dead",
                     "phantom wallet is down", "saw it on insta", "i use paytm", "this is great",
                     "my linkedin is"] {
            XCTAssertNil(Smart.vaultMatch(text, fields: all), text)
        }
    }

    /// "I lost 5 pounds" is weight, never money: kilograms where pounds are
    /// weight (the US), nothing where they are money; a conversion the chip
    /// put in is not converted back.
    /// SmartTest.poundsOfWeightAndInsertedAnswersAreNotMoney.
    func testPoundsOfWeightAndInsertedAnswersAreNotMoney() {
        let usd = Smart.RatesSnapshot(fiat: ["USD": 1, "GBP": 0.75], local: "USD")
        XCTAssertEqual(Smart.chip(for: "it costs 5 pounds", fields: [], rates: usd, region: "US")?.value, "£5 = $6.67")
        XCTAssertEqual(Smart.chip(for: "I lost 5 pounds", fields: [], rates: usd, region: "US"),
                       .convert(source: "5 pounds", results: ["2.27 kg"]))
        XCTAssertNil(Smart.chip(for: "I lost 5 pounds", fields: [], rates: usd, region: "GB"))
        XCTAssertEqual(Smart.chip(for: "bench press 100 pounds", fields: [], rates: usd, region: "US"),
                       .convert(source: "100 pounds", results: ["45.4 kg"]))
        let india = Smart.RatesSnapshot(fiat: ["USD": 1, "INR": 95.88], crypto: ["SOL": 111.77], local: "INR")
        XCTAssertNil(Smart.chip(for: "it costs $13 = ₹1,246.44", fields: [], rates: india))
        XCTAssertNil(Smart.chip(for: "buying $sol = $111.77", fields: [], rates: india))
        XCTAssertEqual(Smart.chip(for: "the total is ₹1,200", fields: [], rates: india)?.value, "₹1,200 = $12.52")
    }

    /// The server's unit cases (server/test/units.test.ts; SmartTest.kt too):
    /// all three convert alike.
    func testUnitsConvertOnThePhone() {
        let cases: [(String, String)] = [
            ("5 km in miles", "5 km is 3.107 miles"),
            ("convert 100 miles to km", "100 miles is 160.9 km"),
            ("100 miles to m", "100 miles is 160,934 m"),
            ("what is 6 ft in cm", "6 feet is 182.9 cm"),
            ("5 in in cm", "5 inches is 12.7 cm"),
            ("how many cm in an inch", "1 inch is 2.54 cm"),
            ("how many feet in a mile?", "1 mile is 5,280 feet"),
            ("100f to c", "100°F is 37.78°C"),
            ("37 c in f", "37°C is 98.6°F"),
            ("-40 celsius to fahrenheit", "-40°C is -40°F"),
            ("70 kg in lbs", "70 kg is 154.3 lb"),
            ("5 pounds in kg", "5 lb is 2.268 kg"),
            ("2 cups in ml", "2 cups is 473.2 ml"),
            ("how many ml are in 2 cups", "2 cups is 473.2 ml"),
            ("1 gallon to liters", "1 gallon is 3.785 litres"),
            ("60 mph in km/h", "60 mph is 96.56 km/h"),
            ("3 hours in minutes", "3 hours is 180 minutes"),
            ("1 acre in sq ft", "1 acre is 43,560 sq ft"),
            ("5 feet 10 inches in cm", "5 ft 10 in is 177.8 cm"),
            ("5'10 in cm", "5 ft 10 in is 177.8 cm"),
            ("178 cm in feet", "178 cm is 5 ft 10 in"),
            ("2 m in ft", "2 m is 6 ft 7 in"),
            ("100 m in feet", "100 m is 328.1 feet"),
        ]
        for (asked, said) in cases {
            XCTAssertEqual(Smart.convertUnits(asked)?.say, said, asked)
        }
        for text in ["5 pounds in dollars", "5 k in miles", "meet in 5 min", "i have 2 hours in the office",
                     "5 km", "km to miles", "5 kg in km"] {
            XCTAssertNil(Smart.convertUnits(text), text)
        }
    }

    /// Hold space on "2+5" answers on the phone, at once: no server, no run
    /// (user, 2026-09-29: "i wanna do math 2+5 its taking long, we dont need
    /// ai for this"). SmartTest.holdSpaceAnswersSumsMoneyAndTheClockOnThePhone.
    func testHoldSpaceAnswersSumsMoneyAndTheClockOnThePhone() {
        XCTAssertEqual(Smart.instantAnswer("2+5")?.say, "2+5 = 7")
        XCTAssertEqual(Smart.instantAnswer("what is 12*12?")?.value, "144")
        XCTAssertEqual(Smart.instantAnswer("18% of 2450")?.say, "18% of 2450 is 441")
        XCTAssertEqual(Smart.instantAnswer("3480/4 =")?.value, "870")
        XCTAssertEqual(Smart.instantAnswer("9/3")?.value, "3")
        XCTAssertEqual(Smart.instantAnswer("5 km in miles")?.say, "5 km is 3.107 miles")
        let rates = Smart.RatesSnapshot(fiat: ["USD": 1, "INR": 95.88], local: "INR")
        XCTAssertEqual(Smart.instantAnswer("100 usd to inr", rates: rates)?.say, "$100 = ₹9,588")
        XCTAssertEqual(Smart.instantAnswer("₹500 in dollars", rates: rates)?.say, "₹500 = $5.21")
        // No rates in hand yet: the server answers it.
        XCTAssertNil(Smart.instantAnswer("100 usd to inr"))
        let at = Date(timeIntervalSince1970: 1790614680)   // 28 Sep 2026, 10:28 PM in India
        let india = TimeZone(identifier: "Asia/Kolkata")!
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(Smart.instantAnswer("what time is it", now: at, timeZone: india, locale: us)?.say, "It's 10:28 PM")
        XCTAssertEqual(Smart.instantAnswer("whats the date?", now: at, timeZone: india, locale: us)?.say,
                       "It's Monday, September 28")
        // A tip, and the days until a day everyone counts to (answers.ts).
        XCTAssertEqual(Smart.instantAnswer("15% tip on 64")?.say, "15% tip on 64 is 9.60 (73.60 in all)")
        let ny = TimeZone(identifier: "America/New_York")!
        func days(_ q: String) -> Smart.InstantAnswer? { Smart.instantAnswer(q, now: at, timeZone: ny, locale: us) }
        XCTAssertEqual(days("how many days until christmas")?.say, "88 days until Christmas")
        XCTAssertEqual(days("how many days until christmas")?.sub, "Friday, December 25")
        XCTAssertEqual(days("days till new years")?.say, "95 days until New Year's Day")
        XCTAssertEqual(days("how long until halloween?")?.say, "33 days until Halloween")
        XCTAssertEqual(days("how many days until dec 25")?.say, "88 days until Dec 25")
        XCTAssertEqual(days("how many weeks until thanksgiving")?.say, "8 weeks and 3 days until Thanksgiving")
        // Messages and questions for the web stay with the server.
        for text in ["hey 2+5 people coming", "split is 3480/4", "call me at 5", "who won the match", "5",
                     "time in tokyo", "how long until the bus comes"] {
            XCTAssertNil(Smart.instantAnswer(text), text)
        }
    }

    // MARK: Google Calendar, live

    func testGoogleListBecomesEventsAndItsCopyWins() {
        let list: [String: Any] = ["items": [
            ["summary": "Standup", "id": "e1", "status": "confirmed",
             "start": ["dateTime": "2026-09-28T11:00:00+05:30"],
             "end": ["dateTime": "2026-09-28T11:30:00+05:30"]],
            ["summary": "Off", "id": "e2",
             "start": ["date": "2026-09-29"], "end": ["date": "2026-09-30"]],
            ["summary": "Gone", "id": "e3", "status": "cancelled",
             "start": ["dateTime": "2026-09-28T15:00:00+05:30"],
             "end": ["dateTime": "2026-09-28T16:00:00+05:30"]],
        ]]
        let zone = TimeZone(identifier: "Asia/Kolkata")!
        let google = GoogleEvent.events(fromList: list, timeZone: zone)
        XCTAssertEqual(google.count, 2, "a cancelled instance is left out")
        XCTAssertEqual(google[0].title, "Standup")
        XCTAssertFalse(google[0].allDay)
        XCTAssertTrue(google[1].allDay)
        XCTAssertEqual(google[1].end.timeIntervalSince(google[1].start), 86_400, "Google's all-day end is exclusive")

        // The phone still has Standup at its OLD time (edited on the web):
        // Google's copy wins for that day; what only the phone knows stays.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let old = CalendarText.Event(title: "Standup",
                                     start: google[0].start.addingTimeInterval(-3600),
                                     end: google[0].end.addingTimeInterval(-3600), allDay: false)
        let dentist = CalendarText.Event(title: "Dentist",
                                         start: google[0].start.addingTimeInterval(7200),
                                         end: google[0].end.addingTimeInterval(7200), allDay: false)
        let merged = CalendarText.withGoogle(google, over: [old, dentist], calendar: cal)
        XCTAssertEqual(merged.filter { $0.title == "Standup" }.count, 1)
        XCTAssertEqual(merged.first { $0.title == "Standup" }?.start, google[0].start, "the web's edit shows")
        XCTAssertTrue(merged.contains(dentist))
        XCTAssertEqual(CalendarText.withGoogle([], over: [dentist], calendar: cal), [dentist])

        // Renamed on the web: same iCalendar UID, new title. One row, Google's.
        var web = google[0]
        web.title = "Standup (moved)"
        web.external = "abc123@google.com"
        let stale = CalendarText.Event(title: "Standup", start: web.start, end: web.end, allDay: false,
                                       external: "abc123@google.com", calendar: "arpit@gmail.com")
        let renamed = CalendarText.withGoogle([web], over: [stale, dentist], calendar: cal)
        XCTAssertEqual(renamed.map(\.title).sorted(), ["Dentist", "Standup (moved)"])

        // Deleted on the web: gone from Google's list, so the phone's copy in
        // the account's own calendar goes too; other calendars stay.
        let holiday = CalendarText.Event(title: "Holiday", start: web.start, end: web.end, allDay: true,
                                         calendar: "Holidays in India")
        let afterDelete = CalendarText.withGoogle([], over: [stale, holiday], primary: "Arpit@gmail.com",
                                                  calendar: cal)
        XCTAssertEqual(afterDelete, [holiday])
    }

    // MARK: Wallet chips

    func testAnAddressIsSentToWhenItIsAWalletAndBoughtWhenItIsAToken() {
        let wallet = "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"
        let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
        var rates = Smart.RatesSnapshot()
        // Not known yet: no chip, and the keyboard is told what to look up.
        XCTAssertNil(Smart.chip(for: "", fields: [], paste: wallet, rates: rates))
        XCTAssertEqual(Smart.addressToCheck(in: "", paste: wallet, rates: rates), wallet)
        rates.addresses = [wallet: .wallet, bonk: .token(symbol: "Bonk", usd: 0.0000036)]
        XCTAssertNil(Smart.addressToCheck(in: "", paste: wallet, rates: rates))

        // Copied: the chip is the paste, with Send beside it.
        let copied = Smart.chip(for: "", fields: [], paste: wallet, rates: rates)
        XCTAssertEqual(copied, .pay(address: wallet, copied: wallet))
        XCTAssertEqual(copied?.label, "Wallet")
        XCTAssertEqual(copied?.value, "7dHb…7ARj")
        XCTAssertEqual(copied?.verb, "Paste")
        XCTAssertEqual(copied?.extra, "Send")
        XCTAssertEqual(copied?.insert, wallet)
        // Typed (or pasted) into the message: the chip is Send itself.
        let send = Smart.chip(for: "here \(wallet)", fields: [], rates: rates)
        XCTAssertEqual(send, .pay(address: wallet))
        XCTAssertEqual(send?.verb, "Send")
        XCTAssertNil(send?.extra)
        // The amount the message asks for comes along, in what Send pays in.
        XCTAssertEqual(Smart.chip(for: "can you send $20 to \(wallet)", fields: [], rates: rates)?.value,
                       "20 USDC to 7dHb…7ARj")
        XCTAssertEqual(Smart.chip(for: "0.5 sol to \(wallet) pls", fields: [], rates: rates),
                       .pay(address: wallet, amount: "0.5", token: "SOL"))
        XCTAssertEqual(Smart.chip(for: "₹500 to \(wallet)", fields: [], rates: rates),
                       .pay(address: wallet), "rupees are not dollars")
        // Your own wallet is one you are sharing: the copy is just a paste.
        XCTAssertEqual(Smart.chip(for: "", fields: [], paste: wallet, rates: rates, ownWallet: wallet),
                       .paste(text: wallet))

        let buy = Smart.chip(for: "ape this \(bonk)", fields: [], rates: rates)
        XCTAssertEqual(buy, .buy(mint: bonk, symbol: "Bonk", price: "$0.0000036"))
        XCTAssertEqual(buy?.label, "Bonk")
        XCTAssertEqual(buy?.value, "$0.0000036")
        XCTAssertEqual(buy?.verb, "Buy")
        XCTAssertEqual(buy?.insert, "", "a tap opens Buy, it types nothing")
        let copiedToken = Smart.chip(for: "", fields: [], paste: bonk, rates: rates)
        XCTAssertEqual(copiedToken?.verb, "Paste")
        XCTAssertEqual(copiedToken?.extra, "Buy")
    }

    func testATickersPriceOffersBuyWhenItCanBeBought() {
        let sol = "So11111111111111111111111111111111111111112"
        let rates = Smart.RatesSnapshot(crypto: ["SOL": 111.77, "BONK": 0.0000036, "JUP": 0.5],
                                        mints: ["SOL": sol])
        XCTAssertEqual(Smart.chip(for: "buying $sol", fields: [], rates: rates),
                       .money(shown: "1 SOL = $111.77", insert: " = $111.77", buy: sol))
        XCTAssertEqual(Smart.chip(for: "$bonk", fields: [], rates: rates),
                       .money(shown: "1 BONK = $0.0000036", insert: " = $0.0000036"), "no address, no Buy")
        XCTAssertEqual(Smart.price(0.5), "$0.50")
        XCTAssertEqual(Smart.price(0.08234), "$0.0823")
        XCTAssertEqual(Smart.price(1234.5), "$1,234.50")
        XCTAssertEqual(Smart.price(0.00000364), "$0.00000364")
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

    /// Typing "email" offers every saved email; one saved stays a plain
    /// chip; asking someone else for theirs offers nothing (Arpit,
    /// 2026-10-01: "if i added 2 mail ids i should see both").
    func testEverySavedDetailOfTheKindIsOffered() {
        let home = VaultField(id: "e1", kind: "email", label: "Email", value: "alex@example.com")
        let work = VaultField(id: "e2", kind: "email", label: "Work", value: "alex@acme.example")
        let cell = VaultField(id: "p1", kind: "phone", label: "Mobile", value: "+1 415 555 0134")
        let desk = VaultField(id: "p2", kind: "phone", label: "Office", value: "+1 415 555 0199")
        let all = [home, cell, work, desk]
        for typed in ["my email is ", "email", "send it to my email", "Email:", "my gmail", "email id"] {
            XCTAssertEqual(Smart.chip(for: typed, fields: all), .details(fields: [home, work], temp: false), typed)
        }
        XCTAssertEqual(Smart.chip(for: "email", fields: [home, cell]), .vault(field: home))
        // The same address saved twice is one chip.
        let again = VaultField(id: "e3", kind: "email", label: "Copy", value: "Alex@Example.com")
        XCTAssertEqual(Smart.chip(for: "email", fields: [home, again, work]), .details(fields: [home, work], temp: false))
        XCTAssertNil(Smart.chip(for: "whats your email", fields: all))
        XCTAssertEqual(Smart.chip(for: "my number is", fields: all), .details(fields: [cell, desk], temp: false))
        // An empty field asking for an email.
        XCTAssertEqual(Smart.chip(for: "", fields: all, field: Smart.FieldHint(kind: "email", empty: true)),
                       .details(fields: [home, work], temp: false))
    }

    /// shared/vault/cases.json: the same cases Android's SmartVaultTest runs
    /// (Arpit, 2026-10-02: "for all data in vault, it should be super fast
    /// using regex").
    func testVaultDetailsComeUpByTheirKindsWordsAndTheirOwnLabels() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/vault/cases.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let fields = (root["fields"] as? [[String: String]] ?? []).map {
            VaultField(id: $0["id"] ?? "", kind: $0["kind"] ?? "", label: $0["label"] ?? "", value: $0["value"] ?? "")
        }
        var failures: [String] = []
        for c in root["cases"] as? [[String: Any]] ?? [] {
            let text = c["text"] as? String ?? ""
            let want = c["values"] as? [String] ?? []
            let got = Smart.vaultMatches(text, fields: fields).map(\.value)
            if got != want { failures.append("'\(text)': got \(got), want \(want)") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// shared/vault/field-cases.json: an empty field of a known kind, and
    /// the postcode read out of an address (Android runs the same file).
    func testAFieldOfAKnownKindIsOfferedItsDetailOrAPartOfIt() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/vault/field-cases.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let fields = (root["fields"] as? [[String: String]] ?? []).map {
            VaultField(id: $0["id"] ?? "", kind: $0["kind"] ?? "", label: $0["label"] ?? "", value: $0["value"] ?? "")
        }
        var failures: [String] = []
        for c in root["cases"] as? [[String: Any]] ?? [] {
            let kind = c["kind"] as? String ?? ""
            let want = c["values"] as? [String] ?? []
            let got = Smart.detailsFor(kind: kind, fields: fields).map(\.value)
            if got != want { failures.append("\(kind): got \(got), want \(want)") }
        }
        for c in root["postcodes"] as? [[String: Any]] ?? [] {
            let address = c["address"] as? String ?? ""
            let want = c["postcode"] as? String
            let got = Smart.postcode(in: address)
            if got != want { failures.append("postcode of '\(address)': got \(got ?? "nil"), want \(want ?? "nil")") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// shared/units/strip-cases.json: a measurement the message ends on, in
    /// the other system, one chip per result (Android runs the same file).
    func testAMeasurementShowsInTheOtherSystem() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/units/strip-cases.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = root["cases"] as? [[String: Any]] ?? []
        XCTAssertGreaterThan(cases.count, 30)
        var failures: [String] = []
        for c in cases {
            let text = c["text"] as? String ?? ""
            let region = c["region"] as? String
            let want = c["results"] as? [String] ?? []
            let got = Smart.conversions(in: text, region: region)?.results ?? []
            if got != want { failures.append("'\(text)' (\(region ?? "-")): got \(got), want \(want)") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// shared/zones/strip-cases.json: a time in someone else's zone, in the
    /// phone's own, with "now" fixed (Android runs the same file).
    func testATimeInAnotherZoneShowsInYours() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/zones/strip-cases.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: root["now"] as? String ?? ""))
        var failures: [String] = []
        for c in root["cases"] as? [[String: Any]] ?? [] {
            let text = c["text"] as? String ?? ""
            let here = try XCTUnwrap(TimeZone(identifier: c["here"] as? String ?? ""))
            let want = c["results"] as? [String] ?? []
            let got = Smart.zoneTimes(in: text, now: now, here: here, region: c["region"] as? String)?.results ?? []
            if got != want { failures.append("'\(text)' in \(here.identifier): got \(got), want \(want)") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// The strip offers a measurement as its own chip, and a tap adds the
    /// result in brackets after what was typed.
    func testAMeasurementIsAChipAndATapAddsItInBrackets() {
        XCTAssertEqual(Smart.chip(for: "lets 10 inch", fields: [], region: "US"),
                       .convert(source: "10 inch", results: ["25.4 cm", "0.254 m"]))
        // A sum is still a sum, and money still money.
        if case .convert? = Smart.chip(for: "12+30", fields: [], region: "US") { XCTFail("a sum became units") }
        XCTAssertEqual(Smart.conversionInsert("25.4 cm", before: "lets 10 inch"), " (25.4 cm)")
        XCTAssertEqual(Smart.conversionInsert("25.4 cm", before: "lets 10 inch "), "(25.4 cm) ")
        XCTAssertEqual(Smart.Chip.convert(source: "10 inch", results: ["25.4 cm"]).choices?.values, ["25.4 cm"])
    }

    /// Money with cents shows both places: "$20 = ₹1,919.6" read as a typo.
    func testMoneyShowsBothCentsPlacesOrNone() {
        XCTAssertEqual(Smart.format(1919.6, in: "INR"), "₹1,919.60")
        XCTAssertEqual(Smart.format(1919.0, in: "INR"), "₹1,919")
        XCTAssertEqual(Smart.format(20, in: "USD"), "$20")
        XCTAssertEqual(Smart.format(12.5, in: "USD"), "$12.50")
        XCTAssertEqual(Smart.format(0.999, in: "USD"), "$1")
    }

    // MARK: Questions (the AI answer chip as it is typed)

    /// shared/questions/cases.json: the same cases Android's SmartTest runs.
    func testQuestionsOfferAnAIAnswerAsTheyAreTyped() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/questions/cases.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var failures: [String] = []
        for c in root["ask"] as? [[String: String]] ?? [] {
            let got = Smart.question(in: c["text"] ?? "")
            if got != c["question"] { failures.append("'\(c["text"] ?? "")' gave \(got ?? "nil"), wanted \(c["question"] ?? "")") }
        }
        for text in root["not"] as? [String] ?? [] {
            if let got = Smart.question(in: text) { failures.append("'\(text)' gave '\(got)', wanted none") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
