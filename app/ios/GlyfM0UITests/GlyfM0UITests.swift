import XCTest

/// M1–M5 gate automation (SPEC §9). Runs against the REAL keyboard on the
/// iPhone 17 Pro simulator with the backend in MOCK_AI mode (deterministic,
/// zero quota — §8.4). Covers:
///  M1: typing + shift/autocap + autocorrect + candidates, toolbar
///      collapse/restore, shell navigation, emoji board.
///  M2: space-hold → Glyf Bar → mock run → Replace.
///  M3: dictation handoff end to end. M4: vault picker + shorthand + refusals.
///  M5: Translation HUD (T), tones popup (R), keyless weather (W),
///      ConnectorSurface (C), Builder E2E, pack apply, paywall.
///  §6.18: the onboarding funnel end to end.
final class GlyfGateUITests: XCTestCase {

    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    private var hosts: [XCUIApplication] { [app, settings, springboard] }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Element helpers (custom-keyboard elements can surface under the
    // host app, Settings, or SpringBoard depending on OS)

    private func firstExisting(_ elements: [XCUIElement]) -> XCUIElement? {
        elements.first { $0.exists }
    }

    /// Finds a keyboard element by accessibility label or identifier across
    /// hosts and element types (KeyView carries the .keyboardKey trait).
    private func kb(_ label: String) -> XCUIElement? {
        for host in hosts {
            for query in [host.keys[label], host.buttons[label], host.otherElements[label]] {
                let el = query.firstMatch
                if el.exists { return el }
            }
        }
        // Table/collection cells surface as neither keys nor buttons, so fall
        // back to an identifier match over every descendant type. Slower, so
        // it runs only after the fast paths miss.
        for host in hosts {
            let el = host.descendants(matching: .any).matching(identifier: label).firstMatch
            if el.exists { return el }
        }
        return nil
    }

    private func kbWait(_ label: String, timeout: TimeInterval = 4) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let el = kb(label) { return el }
            usleep(300_000)
        }
        return nil
    }

    private func staticTextContaining(_ needle: String, in host: XCUIApplication? = nil) -> XCUIElement {
        (host ?? app).staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
    }

    private func dismissKeyboardInterstitials() {
        for _ in 0..<2 {
            guard let cont = kb("Continue"), cont.isHittable else { return }
            cont.tap()
            usleep(600_000)
        }
    }

    @discardableResult
    private func tapFirst(_ candidates: [XCUIElement], timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for el in candidates where el.exists {
                el.tap()
                return true
            }
            usleep(300_000)
        }
        return false
    }

    private func settingsRow(_ labelPrefix: String) -> [XCUIElement] {
        let p = NSPredicate(format: "label BEGINSWITH %@", labelPrefix)
        return [
            settings.cells.containing(p).firstMatch,
            settings.buttons.matching(p).firstMatch,
            settings.staticTexts.matching(p).firstMatch,
        ]
    }

    /// Grants Full Access via the real Settings UI (reinstalls reset it).
    private func ensureFullAccess() {
        settings.terminate()
        settings.launch()
        sleep(1)
        var ok = tapFirst(settingsRow("General"), timeout: 3)
        if !ok {
            settings.swipeUp()
            ok = tapFirst(settingsRow("General"), timeout: 3)
        }
        NSLog("GLYF_FA step=General ok=\(ok)")
        sleep(1)
        ok = tapFirst(settingsRow("Keyboard"), timeout: 3)
        NSLog("GLYF_FA step=Keyboard ok=\(ok)")
        sleep(1)
        ok = tapFirst(settingsRow("Keyboards"), timeout: 4)
        NSLog("GLYF_FA step=Keyboards ok=\(ok)")
        sleep(1)
        ok = tapFirst(settingsRow("Glyf"), timeout: 4)
        NSLog("GLYF_FA step=GlyfRow ok=\(ok)")
        sleep(1)
        let toggle = firstExisting([settings.switches["Allow Full Access"].firstMatch,
                                    settings.switches.firstMatch])
        NSLog("GLYF_FA step=toggle found=\(toggle != nil) value=\((toggle?.value as? String) ?? "nil")")
        if let toggle, (toggle.value as? String) == "0" {
            // The accessible frame spans the whole row — a center tap hits the
            // LABEL, not the knob. Tap the far-right of the frame instead.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

            // Wait for the confirmation alert (any host) and hit its
            // rightmost button ("Allow"/"Allow Full Access").
            var allowed = false
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline, !allowed {
                for host in hosts {
                    let alert = host.alerts.firstMatch
                    if alert.exists {
                        let buttons = alert.buttons
                        let count = buttons.count
                        if count > 0 {
                            let confirm = buttons.element(boundBy: count - 1)
                            NSLog("GLYF_FA alert confirm='\(confirm.label)'")
                            confirm.tap()
                            allowed = true
                            break
                        }
                    }
                }
                if !allowed { usleep(400_000) }
            }
            sleep(1)
            NSLog("GLYF_FA step=allow tapped=\(allowed) newValue=\((toggle.value as? String) ?? "nil")")
        }
        settings.terminate()
    }

    /// The Glyf keyboard is identified by its toolbar's Glyf button.
    @discardableResult
    private func switchToGlyfKeyboard() -> Bool {
        for _ in 0..<6 {
            dismissKeyboardInterstitials()
            if kb("toolbar:glyf") != nil { return true }
            if let globe = kb("Next keyboard") {
                globe.tap()
            }
            usleep(800_000)
        }
        return kb("toolbar:glyf") != nil
    }

    private func launchToTypingField(extraArgs: [String] = []) -> XCUIElement {
        // Shipping presets are 3 keys; the gate needs the full test map.
        app.launchArguments = ["--glyf-skip-onboarding", "--glyf-seed-bindings"] + extraArgs
        app.launch()
        sleep(1)
        // The keyboard occasionally never attaches to a fresh app launch
        // (wedged appex session — environment flake, not product). One clean
        // relaunch recovers it deterministically.
        var field = focusTypingField()
        if field == nil {
            app.terminate()
            sleep(2)
            app.launch()
            sleep(2)
            field = focusTypingField()
        }
        XCTAssertNotNil(field, "Glyf keyboard unavailable (after relaunch)")
        return field!
    }

    /// Brings Home's typing card FULLY on-screen (it sits under the keyboard
    /// visual — usually visible at launch), then focuses it. Check BEFORE
    /// swiping, and swipe toward the field — Flutter silently no-ops taps on
    /// partially-offscreen elements.
    private func focusTypingField() -> XCUIElement? {
        let field = app.textFields.firstMatch
        let bounds = app.frame
        guard field.waitForExistence(timeout: 6) else { return nil }
        for _ in 0..<6 {
            let f = field.frame
            if f.height > 20, f.minY > bounds.minY + 60,
               f.maxY < bounds.maxY - 110 { break }
            if f.midY <= bounds.minY + 140 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            usleep(700_000)
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        return switchToGlyfKeyboard() ? field : nil
    }

    private func typeOnGlyf(_ text: String) {
        for ch in text {
            if ch == " " {
                kb("space")?.tap()
            } else {
                guard let key = kb(String(ch)) ?? kb(String(ch).uppercased()) else {
                    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    shot.lifetime = .keepAlways
                    add(shot)
                    XCTFail("key '\(ch)' not found"); return
                }
                key.tap()
            }
        }
    }

    private func clearField(_ field: XCUIElement) {
        guard let del = kb("delete") else { return }
        // Delete only removes text BEFORE the cursor, and a space-bar glide
        // can leave it mid-text — park it at the end first.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let count = ((field.value as? String) ?? "").count
        for _ in 0..<(count + 4) { del.tap() }
    }

    private func fieldValue(_ field: XCUIElement) -> String {
        (field.value as? String) ?? ""
    }

    // MARK: - Setup

    func test00_GrantFullAccess() throws {
        // App reinstalls reset the grant; the AI tests need it (§1.3 gating).
        ensureFullAccess()
    }

    // MARK: - M1

    func test01_TypingAutocapAutocorrectAndToolbarCollapse() throws {
        let field = launchToTypingField(extraArgs: ["--glyf-reset-typing"])

        // Autocorrect on space: a confident typo ("teh") becomes "the".
        typeOnGlyf("teh")
        // Candidates visible → toolbar collapsed to the Glyf button (§6.2).
        XCTAssertNil(kb("toolbar:settings"), "toolbar should collapse while candidates show")
        XCTAssertNotNil(kb("toolbar:glyf"), "Glyf button must survive the collapse")

        typeOnGlyf(" there")
        kb("space")?.tap()

        // Case-insensitive: XCUITest's first text session is a PHANTOM that
        // reports autocapitalization NONE (SPIKES #18), and the keyboard now
        // honors the field like Apple's does — so the harness's first letter
        // can land lowercase even though real usage capitalizes. Autocorrect
        // is what this asserts.
        let value = fieldValue(field)
        XCTAssertTrue(value.lowercased().hasPrefix("the there"),
                      "autocorrect expected 'the there…', got '\(value)'")

        // Undo chip restores the original word (§6.1 tap-to-undo).
        XCTAssertNotNil(kb("toolbar:glyf"))

        // Restore tools by tapping the Glyf button while collapsed…
        clearField(field)
        _ = kbWait("toolbar:settings", timeout: 3) // candidates gone → tools back
        XCTAssertNotNil(kb("toolbar:settings"), "toolbar should restore when candidates clear")
    }

    /// Engine/Typing on real key taps: a fix on space, backspace puts the
    /// typed word back AND teaches the keyboard to leave it alone, and the
    /// next word is predicted after a space.
    func test01b_AutocorrectUndoTeachesAndPredictsNextWord() throws {
        let field = launchToTypingField(extraArgs: ["--glyf-reset-typing"])
        clearField(field)
        typeOnGlyf("teh ")
        XCTAssertEqual(fieldValue(field).lowercased(), "the ", "a confident typo should be fixed on space")
        kb("delete")?.tap()
        XCTAssertEqual(fieldValue(field).lowercased(), "teh", "backspace right after a fix puts back what was typed")
        typeOnGlyf(" teh ")
        XCTAssertEqual(fieldValue(field).lowercased(), "teh teh ", "a reverted fix must never come back")

        clearField(field)
        typeOnGlyf("thank ")
        guard let first = kbWait("suggest:0", timeout: 3) else { return XCTFail("no next-word prediction") }
        XCTAssertEqual(first.label, "you", "the next word should be predicted after a space")
        first.tap()
        XCTAssertEqual(fieldValue(field).lowercased(), "thank you ")
    }

    func test02_ShellNavigationAndSettings() throws {
        _ = launchToTypingField()
        kb("toolbar:glyf")?.tap()
        sleep(1)

        // The menu holds the tools the strip doesn't (2026-09-29): Rewrite is
        // one; Clipboard sits on the strip, so it is not a tile. Tiles are one
        // element each, found by id.
        XCTAssertNotNil(kbWait("shell:tile:rewrite"), "the menu has no Rewrite tile")

        // Push Settings (a third row since Temp mail joined, 2026-09-30),
        // flip a toggle, come back.
        guard let settings = kbWait("shell:tile:settings") else { return XCTFail("no Settings tile") }
        if !settings.isHittable {
            kb("shell:tile:rewrite")?.swipeUp()
            sleep(1)
        }
        settings.tap()
        sleep(1)
        // Rows are one element each, and Typing leads (Haptics is further
        // down, not yet drawn): match its first row by label.
        let first = hosts.map {
            $0.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Autocorrect")).firstMatch
        }
        XCTAssertTrue(first.contains { $0.waitForExistence(timeout: 3) }, "settings screen did not render")
        kb("shell:back")?.tap()
        sleep(1)
        kb("shell:close")?.tap()
        sleep(1)
        // Autocap may have shifted the board — keys read "Q" on an empty field.
        XCTAssertTrue(kbWait("q") != nil || kb("Q") != nil,
                      "keys should return after shell closes")
    }

    /// Regression (real-device report): tapping "Search emoji" must bring
    /// the LETTER KEYS up under a collapsed strip — before this fix the
    /// grid kept covering them and there was nothing to type with.
    func test03a_EmojiSearchShowsLetterKeys() throws {
        let field = launchToTypingField()
        clearField(field)
        kb("toolbar:emoji")?.tap()
        sleep(1)
        kb("emoji:search")?.tap()
        sleep(1)
        // Letters visible while searching = the bug is dead.
        XCTAssertTrue(kbWait("q") != nil || kb("Q") != nil,
                      "letter keys must appear under emoji search")
        for ch in ["f", "i", "r", "e"] { (kb(ch) ?? kb(ch.uppercased()))?.tap() }
        sleep(1)
        let fire = firstExisting(hosts.map { $0.staticTexts["🔥"].firstMatch })
        XCTAssertNotNil(fire, "searching 'fire' should surface 🔥")
        fire?.tap()
        XCTAssertTrue(fieldValue(field).contains("🔥"), "picked emoji not inserted")
        kb("emoji:abc")?.tap()
        sleep(1)
        let grid = firstExisting(hosts.map { $0.staticTexts["😀"].firstMatch })
        XCTAssertNotNil(grid, "ABC should restore the full emoji grid")
        kb("emoji:close")?.tap()
    }

    /// §6.12 — the Gboard-parity search suite. Backed by MOCK_AI, so the
    /// cards are fixed and the test asserts rendering + the paste format
    /// rather than an upstream's mood.
    func test03b_SearchSuiteCardsAndPasteFormat() throws {
        let field = launchToTypingField()
        clearField(field)
        kb("toolbar:search")?.tap()
        sleep(1)

        // The tab opens on suggestions, not an empty box (Gboard parity).
        XCTAssertNotNil(kbWait("search:card:query", timeout: 8),
                        "search should open on trending/recent suggestions")

        // Letter keys stay visible while the strip is collapsed.
        XCTAssertTrue(kbWait("q") != nil || kb("Q") != nil,
                      "letter keys must stay under the search strip")
        for ch in ["s", "u", "n"] { (kb(ch) ?? kb(ch.uppercased()))?.tap() }
        kb("search:go")?.tap()

        // Web tab leads with the answer card, then a link row.
        XCTAssertNotNil(kbWait("search:card:answer", timeout: 8),
                        "web search should lead with an answer card")
        XCTAssertNotNil(kb("search:card:link"), "web search should show link rows")

        // YouTube tab: video cards with channel + duration.
        kb("search:tab:youtube")?.tap()
        let video = kbWait("search:card:video", timeout: 8)
        XCTAssertNotNil(video, "YouTube tab should render video cards")

        // Tapping a result pastes link + emoji title (the default style).
        video?.tap()
        sleep(1)
        let pasted = fieldValue(field)
        XCTAssertTrue(pasted.contains("youtu.be/"),
                      "tapping a video must paste its link, got '\(pasted)'")
        XCTAssertTrue(pasted.contains("🎥"),
                      "default paste style is link + emoji title, got '\(pasted)'")
        XCTAssertTrue(pasted.contains("lofi") || pasted.contains("Midnight"),
                      "the title must be pasted with the link, got '\(pasted)'")

        // Maps tab: place cards carrying distance / open-now / rating.
        kb("search:tab:maps")?.tap()
        XCTAssertNotNil(kbWait("search:card:place", timeout: 8),
                        "Maps tab should render place cards")

        // ABC returns to the keys.
        kb("search:abc")?.tap()
        sleep(1)
        XCTAssertTrue(kbWait("q") != nil || kb("Q") != nil,
                      "ABC should bring the letter keys back")
        kb("search:close")?.tap()
    }

    func test03_EmojiBoard() throws {
        let field = launchToTypingField()
        clearField(field)
        kb("toolbar:emoji")?.tap()
        sleep(1)
        let smiley = firstExisting(hosts.map { $0.staticTexts["😀"].firstMatch })
        XCTAssertNotNil(smiley, "emoji grid missing")
        smiley?.tap()
        kb("emoji:close")?.tap()
        sleep(1)
        XCTAssertTrue(fieldValue(field).contains("😀"), "emoji not inserted")
    }

    // MARK: - M2 (backend in MOCK_AI mode on 127.0.0.1:8787)

    func test04_AskGlyf_SpaceHoldOnEmpty_MockRun_Insert() throws {
        let field = launchToTypingField()
        clearField(field)

        // §6.4: hold space with nothing typed → Ask Glyf takes the strip and
        // the keys type into its prompt.
        kb("space")?.press(forDuration: 0.6)
        XCTAssertNotNil(kbWait("bar:prompt", timeout: 5), "Ask Glyf did not open")
        typeOnGlyf("say hi")
        kb("bar:run")?.tap()

        // The answer opens in the act panel; the mock backend is deterministic.
        let answerView = firstExisting(hosts.map { $0.textViews["act:text"].firstMatch })
        XCTAssertNotNil(answerView, "act answer missing")
        let deadline = Date().addingTimeInterval(10)
        var answer = ""
        while Date() < deadline {
            answer = (answerView?.value as? String) ?? ""
            if answer.contains("MOCK") { break }
            usleep(400_000)
        }
        XCTAssertTrue(answer.contains("MOCK"), "no mock answer, got '\(answer)'")

        kb("act:insert")?.tap()
        sleep(1)
        XCTAssertTrue(fieldValue(field).contains("MOCK"),
                      "Insert should add the answer, got '\(fieldValue(field))'")
    }

    /// The space bar carries three gestures: a glide at any point while
    /// holding moves the cursor (Gboard's swipe, Apple's press-pause-glide);
    /// holding still for 0.5s launches the AI with the finger still down;
    /// neither types a space. No backend needed.
    func test04b_SpaceBar_GlideMovesCursor_HoldOpensBar() throws {
        let field = launchToTypingField()
        guard let space = kb("space") else { return XCTFail("space key missing") }
        let center = space.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let left = center.withOffset(CGVector(dx: -70, dy: 0))

        // Apple: press, pause, glide — inside the 0.5s window.
        clearField(field)
        typeOnGlyf("hello world")
        center.press(forDuration: 0.2, thenDragTo: left, withVelocity: .default, thenHoldForDuration: 0.1)
        XCTAssertNil(kb("chip:rewrite.polite"), "a glide must not launch the AI")
        typeOnGlyf("x")
        var value = fieldValue(field).lowercased()
        XCTAssertTrue(value.contains("x") && !value.hasSuffix("x"),
                      "press-pause-glide should move the cursor, got '\(value)'")
        XCTAssertEqual(value.replacingOccurrences(of: "x", with: ""), "hello world",
                       "a glide must only move the cursor, never change the text")
        XCTAssertEqual(value.filter { $0 == " " }.count, 1, "a glide must never type a space")

        // Gboard: swipe straight away.
        clearField(field)
        typeOnGlyf("hello world")
        center.press(forDuration: 0.05, thenDragTo: left, withVelocity: .default, thenHoldForDuration: 0)
        typeOnGlyf("y")
        value = fieldValue(field).lowercased()
        XCTAssertTrue(value.contains("y") && !value.hasSuffix("y"),
                      "an immediate swipe should move the cursor, got '\(value)'")
        XCTAssertEqual(value.replacingOccurrences(of: "y", with: ""), "hello world",
                       "a glide must only move the cursor, never change the text")

        // Hold still on typed text: Glyf acts on it at 0.5s, finger still
        // down — the act surface covers the keys and nothing is typed.
        let before = fieldValue(field)
        space.press(forDuration: 0.9)
        XCTAssertNotNil(kbWait("act:cancel", timeout: 3) ?? kbWait("act:close", timeout: 1),
                        "holding still on text should act on it")
        XCTAssertEqual(fieldValue(field), before, "acting must not type a space")
        (kb("act:cancel") ?? kb("act:close"))?.tap()

        // Hold still on an empty field: the prompt bar instead.
        clearField(field)
        space.press(forDuration: 0.9)
        XCTAssertNotNil(kbWait("chip:rewrite.polite", timeout: 5), "an empty field should open the prompt bar")
        kb("bar:close")?.tap()
    }

    /// Hold space on typed text → the live backend routes it → Insert swaps
    /// the typed intent for the result. Runs against the dev server's real
    /// providers, so it asserts the swap, not the exact words.
    func test04c_ActOnTypedText_InsertReplacesTheIntent() throws {
        let field = launchToTypingField()
        clearField(field)
        typeOnGlyf("helo wrld how r u")
        let typed = fieldValue(field)
        kb("space")?.press(forDuration: 0.9)
        guard let insert = kbWait("act:insert", timeout: 45) else {
            let status = kb("act:status")?.label ?? "none"
            return XCTFail("no act result (status: \(status))")
        }
        insert.tap()
        sleep(1)
        let value = fieldValue(field)
        XCTAssertFalse(value.isEmpty, "Insert should leave the result in the field")
        XCTAssertNotEqual(value, typed, "Insert should replace the typed intent")
        XCTAssertNil(kb("act:insert"), "the act surface should close after Insert")
    }

    /// A bound letter's skill runs as a HUD: the skill's name over its
    /// keycap, then the streamed answer with Insert. Live backend.
    func test04e_BoundKeySkillHUD_ProofreadInserts() throws {
        let field = launchToTypingField()
        clearField(field)
        typeOnGlyf("i has went ther")
        let typed = fieldValue(field)
        (kb("p") ?? kb("P"))?.press(forDuration: 0.6)
        XCTAssertNotNil(kbWait("act:skill", timeout: 4) ?? kbWait("act:insert", timeout: 1),
                        "holding a bound key should open its skill HUD")
        guard let insert = kbWait("act:insert", timeout: 45) else {
            return XCTFail("no skill result (status: \(kb("act:status")?.label ?? "none"))")
        }
        insert.tap() // Insert only appears once the stream has finished
        sleep(1)
        let value = fieldValue(field)
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(value, typed, "Insert should swap the draft for the proofread text")
    }

    /// One place comes back with a real map snapshot above its card.
    func test04d_ActPlace_ShowsMap() throws {
        let field = launchToTypingField()
        clearField(field)
        typeOnGlyf("times square starbucks")
        kb("space")?.press(forDuration: 0.9)
        XCTAssertNotNil(kbWait("act:insert", timeout: 45), "no act result")
        XCTAssertNotNil(kbWait("act:map", timeout: 10), "a single place should show a map")
        sleep(8) // let MapKit fetch its tiles before the screenshot
        NSLog("GLYF_SHOT act-map")
        sleep(4)
        kb("act:close")?.tap()
    }

    func test05_GlyfKey_T_TranslationHUD() throws {
        let field = launchToTypingField()
        clearField(field)
        typeOnGlyf("good morning")

        // §6.13 T (M5): the binding is now the persistent Translation HUD —
        // long-press toggles the strip; it live-translates the draft.
        kb("t")?.press(forDuration: 0.6)
        XCTAssertNotNil(kbWait("hud:translate", timeout: 5), "HUD strip did not appear")

        // Mock backend translates the draft; the strip shows the result.
        let hudText = firstExisting(hosts.map { $0.staticTexts["hud:text"].firstMatch })
        var text = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            text = hudText?.label ?? ""
            if text.contains("MOCK translate") { break }
            usleep(400_000)
        }
        XCTAssertTrue(text.contains("MOCK translate"),
                      "HUD never translated the draft, got '\(text)'")

        // Tap the strip → the draft is REPLACED with the translation (§6.13).
        (kb("hud:translate") ?? kb("hud:text"))?.tap()
        sleep(1)
        XCTAssertTrue(fieldValue(field).contains("MOCK translate"),
                      "tapping the HUD should replace the draft, got '\(fieldValue(field))'")

        // ✕ turns the HUD off again (state is persisted — leave it clean).
        kb("hud:close")?.tap()
        sleep(1)
        XCTAssertNil(kb("hud:text"), "HUD should close via ✕")
    }

    // MARK: - M5 surfaces (tones popup · keyless tools · connector)

    func test10_TonesPopup_R_RewritesCasual() throws {
        let field = launchToTypingField()
        clearField(field)
        typeOnGlyf("hello team")

        // §6.13 R — Humanize: tone picker over the keys.
        (kb("r") ?? kb("R"))?.press(forDuration: 0.6)
        XCTAssertNotNil(kbWait("tones:casual", timeout: 5), "tones popup did not open")
        kb("tones:casual")?.tap()

        // Picks feed rewrite.tone with the tone var → the act panel's answer.
        let result = firstExisting(hosts.map { $0.textViews["act:text"].firstMatch })
        var text = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            text = (result?.value as? String) ?? ""
            if text.contains("MOCK tone") { break }
            usleep(400_000)
        }
        XCTAssertTrue(text.contains("MOCK tone"),
                      "tone rewrite did not run, got '\(text)'")
        kb("act:close")?.tap()
    }

    func test11_KeylessWeather_W() throws {
        let field = launchToTypingField()
        clearField(field)
        typeOnGlyf("paris")

        // §6.13 W → keyless.weather: if/format/tool pipeline, no API key.
        // Bound skills run as a HUD in the act surface.
        (kb("w") ?? kb("W"))?.press(forDuration: 0.6)
        XCTAssertNotNil(kbWait("act:cancel", timeout: 5) ?? kbWait("act:close", timeout: 5),
                        "skill HUD did not open from W")
        var text = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            text = (firstExisting(hosts.map { $0.textViews["act:text"].firstMatch })?.value as? String) ?? ""
            if text.contains("MOCK clear sky") { break }
            usleep(400_000)
        }
        XCTAssertTrue(text.contains("MOCK clear sky"),
                      "weather tool did not run, got '\(text)'")
        kb("act:close")?.tap()
    }

    func test12_ConnectorSurface_C_InsertsEvent() throws {
        let field = launchToTypingField()
        clearField(field)

        // §6.12 C → ConnectorSurface with the demo calendar, default query
        // already run — rows land without typing anything.
        (kb("c") ?? kb("C"))?.press(forDuration: 0.6)
        let row = firstExisting(hosts.flatMap { [
            $0.cells["connector:row:Standup"].firstMatch,
            $0.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Standup")).firstMatch,
        ] })
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, !(row?.exists ?? false) { usleep(400_000) }
        XCTAssertTrue(row?.exists ?? false, "mockcal rows did not load")
        row?.tap()

        // Insert menu: Link · Time+title · Details (§6.12).
        XCTAssertNotNil(kbWait("connector:menu:brief", timeout: 4), "insert menu missing")
        kb("connector:menu:brief")?.tap()
        sleep(1)
        let value = fieldValue(field)
        XCTAssertTrue(value.contains("Standup") && value.contains("09:30"),
                      "event was not inserted, got '\(value)'")
    }

    // MARK: - M5 app: Builder E2E (mock) · Packs · Paywall

    func test13_BuilderMockEndToEnd() throws {
        app.launchArguments = ["--glyf-skip-onboarding"]
        app.launch()
        sleep(2)

        // Build tab → "Build your own" opens the Builder (no ＋ tab anymore).
        let buildTabBtn = firstExisting([
            app.buttons["tab:build"].firstMatch,
            app.otherElements["tab:build"].firstMatch,
        ])
        XCTAssertNotNil(buildTabBtn, "build tab missing")
        buildTabBtn?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        let openBuilder = firstExisting([
            app.buttons["build:open-builder"].firstMatch,
            app.otherElements["build:open-builder"].firstMatch,
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "Build your own")).firstMatch,
        ])
        XCTAssertNotNil(openBuilder, "builder entry missing")
        openBuilder?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)

        // Describe via an example chip (typing would summon the keyboard).
        let example = staticTextContaining("calm, professional")
        XCTAssertTrue(example.waitForExistence(timeout: 6), "builder screen missing")
        example.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        usleep(400_000)

        app.buttons["Generate"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // MOCK builder returns a single-llm def instantly; steps render.
        XCTAssertTrue(staticTextContaining("LLM").waitForExistence(timeout: 10),
                      "generated step card missing")

        // Test drive → deterministic MOCK custom output. ("Run a test" sits
        // below the fold — scroll it fully on-screen first, offscreen Flutter
        // taps no-op.)
        app.swipeUp()
        sleep(1)
        let runTest = app.buttons["Run a test"].firstMatch
        XCTAssertTrue(runTest.waitForExistence(timeout: 4))
        runTest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(staticTextContaining("MOCK custom").waitForExistence(timeout: 12),
                      "builder test run produced no output")

        // Save → letter grid → bind to Z. Flutter dehydrates scrolled-away
        // semantics and XCUITest snapshots go stale between queries — query
        // fresh, tap immediately, retry the whole step if the grid didn't rise.
        app.swipeUp()
        sleep(1)
        let z = app.staticTexts["Z"].firstMatch
        var pickerOpened = false
        for _ in 0..<3 {
            let save = app.buttons["Save & bind to a key"].firstMatch
            if save.waitForExistence(timeout: 3) {
                save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                app.swipeUp()
                usleep(600_000)
                continue
            }
            if z.waitForExistence(timeout: 6) { pickerOpened = true; break }
        }
        XCTAssertTrue(pickerOpened, "key picker did not open")
        z.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Outcome, not toast: save+bind pops the Builder back to the shell,
        // and the glyf appears in the Build tab's MINE section with its
        // generated name ("Turn rant into" from the mock description).
        var buildTab: XCUIElement?
        let popDeadline = Date().addingTimeInterval(10)
        while Date() < popDeadline, buildTab == nil {
            buildTab = firstExisting([
                app.buttons["tab:build"].firstMatch,
                app.otherElements["tab:build"].firstMatch,
            ])
            if buildTab == nil { usleep(500_000) }
        }
        XCTAssertNotNil(buildTab, "builder did not pop back to the shell")
        sleep(1)
        buildTab?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Flutter merges the card row (texts + icon buttons) into one node,
        // so the title is not a standalone StaticText — match ANY role.
        let mineCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Turn rant into")).firstMatch
        XCTAssertTrue(mineCard.waitForExistence(timeout: 8),
                      "saved glyf missing from MINE section")
        let privacy = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Private")).firstMatch
        XCTAssertTrue(privacy.exists,
                      "saved glyf should be private until published (§6.9)")
    }

    func test14_PackApplyWithKeyDiff() throws {
        app.launchArguments = ["--glyf-skip-onboarding"]
        app.launch()
        sleep(2)
        let buildTab = firstExisting([
            app.buttons["tab:build"].firstMatch,
            app.otherElements["tab:build"].firstMatch,
            app.buttons["Build"].firstMatch,
        ])
        XCTAssertNotNil(buildTab, "build tab missing")
        buildTab?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)

        // §6.14: pack card → diff sheet → apply.
        let pack = firstExisting([
            app.otherElements["pack:writer"].firstMatch,
            app.buttons["pack:writer"].firstMatch,
            app.staticTexts["Writer"].firstMatch,
        ])
        XCTAssertNotNil(pack, "writer pack card missing")
        pack?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let apply = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Apply")).firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 6), "pack sheet did not open")
        apply.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)

        // Outcome, not toast: the Writer keys are live — Home lists the
        // K → Tighten binding row.
        let homeTab = firstExisting([
            app.buttons["tab:home"].firstMatch,
            app.otherElements["tab:home"].firstMatch,
        ])
        XCTAssertNotNil(homeTab, "home tab missing")
        homeTab?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let tighten = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Tighten")).firstMatch
        XCTAssertTrue(tighten.waitForExistence(timeout: 8),
                      "Writer pack binding (K → Tighten) not on Home")
    }

    func test15_PaywallRenders() throws {
        app.launchArguments = ["--glyf-skip-onboarding"]
        app.launch()
        sleep(2)
        let profileTab = firstExisting([
            app.buttons["tab:profile"].firstMatch,
            app.otherElements["tab:profile"].firstMatch,
            app.buttons["Profile"].firstMatch,
        ])
        profileTab?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)

        // §6.16: plan card → paywall sheet. Dismiss without unlocking so the
        // meter path stays exercised by the rest of the suite.
        let planCard = app.descendants(matching: .any)["profile:plan"].firstMatch
        XCTAssertTrue(planCard.waitForExistence(timeout: 8), "profile did not load")
        planCard.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        let unlock = app.descendants(matching: .any)["paywall:unlock"].firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 6), "paywall sheet did not render")
        // Nothing on the cards may promise what the server doesn't give.
        // Greyed cards merge their texts into one label, so match any element.
        let labelled = { (needle: String) in
            self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
        }
        XCTAssertTrue(labelled("400 runs a day").waitForExistence(timeout: 4), "Max card lost its runs line")
        XCTAssertFalse(labelled("Unlimited").exists, "a card promises unlimited")
        // No Not now on the sheet: a tap above it closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 4), "no way out of the paywall")
    }

    // MARK: - §6.18 onboarding funnel

    /// PageView keeps neighbor pages alive: label queries match OFFSCREEN
    /// twins, and isHittable misreports on settled pages. The only reliable
    /// recipe: pick the match whose FRAME is inside the screen, then tap the
    /// frame center as a coordinate.
    private func onScreen(_ query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let bounds = app.frame
        while Date() < deadline {
            let count = min(query.count, 8)
            for i in 0..<count {
                let el = query.element(boundBy: i)
                if el.exists {
                    let f = el.frame
                    if f.width > 10, f.midX > bounds.minX + 2, f.midX < bounds.maxX - 2,
                       f.midY > bounds.minY, f.midY < bounds.maxY {
                        return el
                    }
                }
            }
            usleep(400_000)
        }
        return nil
    }

    @discardableResult
    private func funnelTap(_ label: String, timeout: TimeInterval = 8) -> Bool {
        guard let el = onScreen(app.buttons.matching(identifier: label), timeout: timeout)
        else { return false }
        usleep(400_000) // let the page transition finish
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    // MARK: - M3 dictation (§6.6 gate: mic → record in app → transcript at cursor)

    func test07_DictationEndToEnd() throws {
        let field = launchToTypingField(extraArgs: ["--glyf-fake-dictation"])
        clearField(field)

        // Keyboard mic → §7 intent → app foregrounds the recording sheet.
        kb("toolbar:dictation")?.tap()
        XCTAssertTrue(staticTextContaining("Listening").waitForExistence(timeout: 10),
                      "recording sheet did not open from the keyboard")

        // Fake engine streams the canned transcript; let a few words land.
        sleep(3)
        let stop = app.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 4))
        stop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Review: Clean is the default and comes from the mock backend.
        XCTAssertTrue(staticTextContaining("How should it read").waitForExistence(timeout: 8),
                      "review step missing")
        XCTAssertTrue(staticTextContaining("MOCK clean").waitForExistence(timeout: 12),
                      "clean transcript never arrived")

        let insert = app.buttons["Insert to keyboard"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 4))
        insert.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(2)

        // Stay in the SAME app session (a relaunch under XCUITest leaves the
        // keyboard attached to a phantom text session — inserts land in the
        // document but not the visible field). Background + reactivate, bring
        // the field back on-screen, refocus: the keyboard re-appears against
        // the live session and delivers.
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        sleep(2)
        app.swipeUp()
        usleep(500_000)
        var value = ""
        var deadline = Date().addingTimeInterval(4)
        while Date() < deadline { // it may already be there from auto-refocus
            value = fieldValue(app.textFields.firstMatch)
            if value.contains("MOCK clean") { break }
            usleep(500_000)
        }
        if !value.contains("MOCK clean") {
            app.textFields.firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            deadline = Date().addingTimeInterval(16)
            while Date() < deadline {
                value = fieldValue(app.textFields.firstMatch)
                if value.contains("MOCK clean") { break }
                usleep(500_000)
            }
        }
        XCTAssertTrue(value.contains("MOCK clean"),
                      "dictation was not inserted at the cursor, got '\(value)'")

        // Single-use (§7.3): the transcript appears exactly once even though
        // the keyboard re-appeared multiple times during this flow. (The
        // replay/TTL matrix is unit-tested in IntentStoreTests.)
        XCTAssertEqual(value.components(separatedBy: "MOCK clean").count - 1, 1,
                       "result delivered more than once — §7.3 single-use violated")
    }

    // MARK: - M4 vault & shorthand (§6.7 gate)

    func test08_VaultPickerAndShorthand() throws {
        let field = launchToTypingField(extraArgs: ["--glyf-seed-vault"])
        clearField(field)

        // Long-press S → ripple → in-keyboard vault picker (§6.13 'S').
        (kb("s") ?? kb("S"))?.press(forDuration: 0.6)
        sleep(2)
        let homeRow = firstExisting(hosts.map { $0.otherElements["vault:Home"].firstMatch })
            ?? firstExisting(hosts.map { $0.cells["vault:Home"].firstMatch })
            ?? firstExisting(hosts.map { $0.staticTexts["Home"].firstMatch })
        XCTAssertNotNil(homeRow, "vault picker did not show the seeded Home field")
        homeRow?.tap()
        sleep(1)
        XCTAssertTrue(fieldValue(field).contains("42 Glass Lane"),
                      "vault field was not typed, got '\(fieldValue(field))'")

        // Shorthand: ';sig' + space expands inline (§6.7).
        typeOnGlyf(" ")
        kb("mode:123")?.tap()
        kb(";")?.tap()
        kb("mode:ABC")?.tap()
        typeOnGlyf("sig ")
        let value = fieldValue(field)
        XCTAssertTrue(value.contains("tryglyf.com"),
                      "';sig' did not expand, got '\(value)'")
        XCTAssertFalse(value.contains(";sig"), "trigger token should be consumed")
    }

    func test09_VaultBlocksSecrets() throws {
        // The form opens PRE-FILLED with a card number (test hook) — typing
        // would summon the keyboard, whose sheet-lift breaks XCUITest frame
        // math on Flutter modals. The refusal rules matrix itself is fully
        // unit-tested (VaultTests); this proves the end-to-end error surface.
        app.launchArguments = ["--glyf-skip-onboarding", "--glyf-test-prefill-card"]
        app.launch()

        // Vault lives on the Profile tab now (Acti-style shell).
        sleep(2)
        let profileTab = firstExisting([
            app.buttons["Profile"].firstMatch,
            app.buttons["tab:profile"].firstMatch,
            app.otherElements["tab:profile"].firstMatch,
        ])
        XCTAssertNotNil(profileTab, "profile tab missing")
        profileTab?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)

        let vaultCard = staticTextContaining("Your info & shorthand")
        XCTAssertTrue(vaultCard.waitForExistence(timeout: 8), "vault card missing on profile")
        vaultCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8), "prefilled form did not open")
        sleep(1)

        let refusal = staticTextContaining("Card numbers")
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !refusal.waitForExistence(timeout: 3) {
            // Unlifted-sheet screen geometry fallback (header row, right side).
            for dy in [0.655, 0.62, 0.69, 0.58] {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: dy)).tap()
                if refusal.waitForExistence(timeout: 2) { break }
            }
        }

        // §6.7: refused at input, with an explanation.
        XCTAssertTrue(refusal.waitForExistence(timeout: 4),
                      "card number was not refused with an explanation")
    }

    /// The rebuilt onboarding is a single screen with steps behind an
    /// AnimatedSwitcher (no PageView) — identifiers address every control
    /// directly: hello → persona → feel → enable → access → keys → home.
    func test06_OnboardingFunnel() throws {
        app.launchArguments = ["--glyf-reset-onboarding"]
        app.launch()
        sleep(2)

        func tapOnb(_ id: String, timeout: TimeInterval = 6) -> Bool {
            let el = firstExisting([
                app.buttons[id].firstMatch,
                app.otherElements[id].firstMatch,
            ])
            guard let el, el.waitForExistence(timeout: timeout) else { return false }
            el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            usleep(700_000)
            return true
        }

        XCTAssertTrue(tapOnb("onb:next"), "hello step missing")          // Set up
        XCTAssertTrue(tapOnb("onb:persona:working"), "persona cards missing")
        XCTAssertTrue(tapOnb("onb:next"), "persona continue missing")
        XCTAssertTrue(tapOnb("onb:next"), "feel step missing")           // toggles kept
        // Enable + Full Access are live-detected; this suite runs with both
        // granted, so Continue shows — Skip is the fallback either way.
        for _ in 0..<2 {
            if !tapOnb("onb:next", timeout: 3) {
                XCTAssertTrue(tapOnb("onb:skip", timeout: 3),
                              "neither continue nor skip on a permission step")
            }
        }
        XCTAssertTrue(tapOnb("onb:next"), "keys step missing")           // Continue
        // Google connect closes the flow — tests never open a real browser.
        XCTAssertTrue(tapOnb("onb:skip"), "connect step missing")        // Not now

        XCTAssertTrue(staticTextContaining("keys bound").waitForExistence(timeout: 10),
                      "home did not appear after onboarding")
    }
}
