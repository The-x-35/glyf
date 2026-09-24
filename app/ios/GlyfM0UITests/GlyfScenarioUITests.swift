import XCTest

/// Everyday situations on the real Glyf keyboard, against the live dev
/// server (real models, real search). Each test is one thing a person does
/// in a chat: taps real keys, holds the real space bar, and checks what
/// landed in the message. Numbered S51 onward; S01 to S50 are the server
/// scenarios in qa/server-scenarios.mjs.
///
/// Run test00 first in any subset: it grants Full Access.
final class GlyfScenarioUITests: XCTestCase {

    private let app = XCUIApplication()
    /** The app whose field the keyboard is typing into (Glyf, or Messages). */
    private lazy var host: XCUIApplication = app
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private var field: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = name
        add(shot)
        super.tearDown()
    }

    // MARK: - Finding things on the keyboard

    /// Keyboard views surface under the host app on iOS 26.
    private func el(_ id: String) -> XCUIElement {
        let fast = host.keys.matching(identifier: id).firstMatch
        if fast.exists { return fast }
        let button = host.buttons.matching(identifier: id).firstMatch
        if button.exists { return button }
        return host.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func wait(_ id: String, _ timeout: TimeInterval = 5) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let e = el(id)
            if e.exists { return e }
            usleep(250_000)
        }
        return nil
    }

    private func gone(_ id: String, _ timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !el(id).exists { return true }
            usleep(250_000)
        }
        return false
    }

    private func tap(_ id: String, _ timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        guard let e = wait(id, timeout) else {
            XCTFail("\(id) not found", file: file, line: line)
            return
        }
        e.tap()
    }

    private var value: String { (field.value as? String) ?? "" }

    private func waitValue(_ timeout: TimeInterval = 6, _ ok: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if ok(value) { return true }
            usleep(300_000)
        }
        return ok(value)
    }

    private func note(_ text: String) {
        NSLog("GLYF_SCENARIO \(name) \(text)")
    }

    // MARK: - Typing like a person

    private static let symbols1 = Set("1234567890-/:;()$&@\".,?!'")
    private static let symbols2 = Set("[]{}#%^*+=_\\|~<>€£¥•")

    /// Taps each key. Letters are typed lowercase and left to autocapitalise.
    private func type(_ text: String) {
        for ch in text {
            if ch == " " { tap("key:space"); continue }
            if ch == "\n" { tap("key:return"); continue }
            let id = "key:\(String(ch).lowercased())"
            if el(id).exists { el(id).tap(); continue }
            if Self.symbols1.contains(ch) || Self.symbols2.contains(ch) {
                if el("key:mode:123").exists { el("key:mode:123").tap() }
                if Self.symbols2.contains(ch), el("key:mode:#+=").exists { el("key:mode:#+=").tap() }
            } else if el("key:mode:ABC").exists {
                el("key:mode:ABC").tap()
            }
            guard let key = wait(id, 2) else {
                XCTFail("key \(id) not on the keyboard")
                return
            }
            key.tap()
        }
    }

    private func clear() {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let n = value.count
        guard n > 0, let del = wait("key:delete", 2) else { return }
        // Holding delete clears a long message quickly, like a person would.
        if n > 12 { del.press(forDuration: 3.5) }
        for _ in 0..<(value.count + 2) { del.tap() }
    }

    private func holdSpace(_ seconds: TimeInterval = 1.2) {
        guard let space = wait("key:space", 3) else { return XCTFail("no space bar") }
        space.press(forDuration: seconds)
    }

    private func allowPasteIfAsked() {
        for host in [springboard, app] {
            let allow = host.buttons["Allow Paste"]
            if allow.waitForExistence(timeout: 1.5) { allow.tap(); return }
        }
    }

    // MARK: - Getting to a message field

    private func dismissInterstitials() {
        for _ in 0..<2 {
            let cont = host.buttons["Continue"]
            guard cont.exists, cont.isHittable else { return }
            cont.tap()
            usleep(600_000)
        }
    }

    private func switchToGlyf() -> Bool {
        for _ in 0..<6 {
            dismissInterstitials()
            if el("toolbar:glyf").exists || el("toolbar:close").exists { return true }
            let globe = host.keys["Next keyboard"]
            if globe.exists { globe.tap() }
            usleep(800_000)
        }
        return el("toolbar:glyf").exists
    }

    private func open(_ args: [String] = []) {
        app.launchArguments = ["--glyf-skip-onboarding", "--glyf-seed-vault", "--glyf-clear-tour"] + args
        app.launch()
        sleep(1)
        for attempt in 0..<2 {
            let f = app.textFields.firstMatch
            if f.waitForExistence(timeout: 8) {
                for _ in 0..<6 {
                    let r = f.frame
                    if r.height > 20, r.minY > app.frame.minY + 60, r.maxY < app.frame.maxY - 110 { break }
                    if r.midY <= app.frame.minY + 140 { app.swipeDown() } else { app.swipeUp() }
                    usleep(700_000)
                }
                f.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                sleep(1)
                if switchToGlyf() { field = f; return }
            }
            if attempt == 0 { app.terminate(); sleep(2); app.launch(); sleep(2) }
        }
        XCTFail("Glyf keyboard did not come up")
    }

    // MARK: - Setup

    func test00_GrantFullAccess() throws {
        settings.terminate()
        settings.launch()
        sleep(1)
        let rows = ["General", "Keyboard", "Keyboards", "Glyf"]
        for row in rows {
            let p = NSPredicate(format: "label BEGINSWITH %@", row)
            let cell = settings.cells.containing(p).firstMatch
            if !cell.waitForExistence(timeout: 4) { settings.swipeUp() }
            let target = [cell, settings.buttons.matching(p).firstMatch,
                          settings.staticTexts.matching(p).firstMatch].first { $0.exists }
            target?.tap()
            sleep(1)
        }
        let toggle = settings.switches["Allow Full Access"].firstMatch
        if toggle.waitForExistence(timeout: 4), (toggle.value as? String) == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            for host in [settings, springboard] {
                let alert = host.alerts.firstMatch
                if alert.waitForExistence(timeout: 3) {
                    alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
                    break
                }
            }
        }
        settings.terminate()
    }

    // MARK: - Typing

    func testS51_TypoInASentenceIsFixedOnSpace() throws {
        open(["--glyf-reset-typing"])
        clear()
        type("i think teh plan works ")
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "i think the plan works " }, "got '\(value)'")
        note("typed 'i think teh plan works' -> '\(value)'")
    }

    func testS52_DoubleSpaceEndsTheSentence() throws {
        open()
        clear()
        type("ok  see")
        XCTAssertTrue(waitValue(3) { $0.lowercased().hasPrefix("ok. see") }, "got '\(value)'")
        XCTAssertTrue(value.contains(". S"), "the next sentence should start with a capital, got '\(value)'")
        note("'ok  see' -> '\(value)'")
    }

    func testS53_NextWordIsPredicted() throws {
        open(["--glyf-reset-typing"])
        clear()
        type("thank ")
        guard let first = wait("suggest:0", 3) else { return XCTFail("no prediction after 'thank '") }
        XCTAssertEqual(first.label, "you")
        first.tap()
        XCTAssertEqual(value.lowercased(), "thank you ")
    }

    func testS54_BackspaceRightAfterAFixPutsTheWordBack() throws {
        open(["--glyf-reset-typing"])
        clear()
        type("teh ")
        XCTAssertEqual(value.lowercased(), "the ")
        tap("key:delete")
        XCTAssertEqual(value.lowercased(), "teh")
    }

    func testS55_NumbersThenBackToLetters() throws {
        open()
        clear()
        type("call at 5 ")
        XCTAssertTrue(waitValue(2) { $0.lowercased() == "call at 5 " }, "got '\(value)'")
        let lettersBack = wait("key:a", 1.5) != nil
        note("after '5 ' letters came back: \(lettersBack)")
        XCTAssertTrue(lettersBack, "like Apple's, a space after a number goes back to letters")
    }

    func testS56_HoldingDeleteClearsWords() throws {
        open()
        clear()
        type("one two three four five six")
        let before = value.count
        el("key:delete").press(forDuration: 2.5)
        XCTAssertLessThan(value.count, before - 6, "holding delete should take out more than a few letters, got '\(value)'")
        note("held delete: \(before) -> \(value.count) characters")
    }

    func testS57_SpaceBarGlideMovesTheCursor() throws {
        open()
        clear()
        type("hello world")
        let space = el("key:space")
        let start = space.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = space.coordinate(withNormalizedOffset: CGVector(dx: -0.4, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: end)
        type("x")
        XCTAssertFalse(value.hasSuffix("x"), "the cursor should have moved left before typing, got '\(value)'")
        note("glide then x -> '\(value)'")
    }

    func testS58_ReturnStartsANewLine() throws {
        open()
        clear()
        type("hi\nthere")
        XCTAssertTrue(value.contains("\n"), "got '\(value)'")
    }

    func testS59_ShorthandExpands() throws {
        open()
        clear()
        type(";sig ")
        XCTAssertTrue(waitValue(3) { $0.contains("Arpit") }, "';sig ' should expand, got '\(value)'")
        note("';sig ' -> '\(value)'")
    }

    // MARK: - The strip

    func testS60_SumInAMessageOffersTheAnswer() throws {
        open()
        clear()
        type("split is 3480/4")
        guard let chip = wait("strip:smart", 4) else { return XCTFail("no answer chip for 3480/4") }
        let label = chip.label
        XCTAssertTrue(label.contains("870"), "chip says '\(label)'")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.contains("870") }, "got '\(value)'")
        note("chip '\(label)' -> '\(value)'")
    }

    func testS61_AskedForYourAddressItIsOneTapAway() throws {
        open()
        clear()
        type("sure my address is ")
        guard let chip = wait("strip:smart", 4) else { return XCTFail("no address chip") }
        // The first address in the vault: the seed on a fresh simulator, or
        // whatever the person saved (the seed never overwrites a vault).
        let offered = chip.label
        XCTAssertTrue(offered.range(of: #"\d"#, options: .regularExpression) != nil,
                      "chip says '\(offered)'")
        chip.tap()
        let tail = String(offered.suffix(12))
        XCTAssertTrue(waitValue(3) { $0.localizedCaseInsensitiveContains(tail) },
                      "got '\(value)' for chip '\(offered)'")
    }

    func testS62_AskedForUPIItIsOneTapAway() throws {
        open()
        clear()
        type("my upi is ")
        guard let chip = wait("strip:smart", 4) else { return XCTFail("no UPI chip") }
        // The vault's UPI id, whichever it is (see S61).
        let offered = chip.label
        guard let id = offered.split(separator: " ").last(where: { $0.contains("@") }) else {
            return XCTFail("chip says '\(offered)'")
        }
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.contains(id) }, "got '\(value)' for chip '\(offered)'")
    }

    func testS63_RoughMessageOffersTidyThisUp() throws {
        open()
        clear()
        type("ya ok will send the deck before six tmrw ")
        guard let chip = wait("strip:smart", 10) else { return XCTFail("no suggestion chip") }
        note("chip: '\(chip.label)'")
        XCTAssertTrue(chip.label.localizedCaseInsensitiveContains("tidy"), "chip says '\(chip.label)'")
        chip.tap()
        XCTAssertNotNil(wait("act:option:work", 15), "tapping the chip should offer versions")
    }

    // MARK: - Hold space

    func testS64_HoldSpaceOffersVersionsAndProfessionalReplacesTheMessage() throws {
        open()
        clear()
        type("ya ok will send deck b4 6")
        holdSpace()
        guard let pro = wait("act:option:work", 15) else { return XCTFail("no Professional version") }
        let ids = ["basic", "work", "polite", "shorter", "hinglish", "emoji"]
        var offered = Set(ids.filter { el("act:option:\($0)").exists })
        // The rest are further down the list.
        app.tables.firstMatch.swipeUp()
        offered.formUnion(ids.filter { el("act:option:\($0)").exists })
        app.tables.firstMatch.swipeDown()
        sleep(2) // a tap on a list that is still gliding only stops it
        note("versions offered: \(ids.filter(offered.contains).joined(separator: ", ")); professional: \(pro.label)")
        XCTAssertGreaterThanOrEqual(offered.count, 4)
        guard let proAgain = wait("act:option:work", 3) else { return XCTFail("Professional scrolled away") }
        proAgain.tap()
        XCTAssertTrue(waitValue(4) { !$0.contains("b4") && $0.lowercased().contains("deck") }, "got '\(value)'")
        XCTAssertTrue(gone("act:option:work"), "the panel should close after picking a version")
        note("inserted: '\(value)'")
    }

    func testS65_HoldingAVersionCopiesItInstead() throws {
        open()
        clear()
        type("sry running late traffic is crazy")
        holdSpace()
        guard let basic = wait("act:option:basic", 15) else { return XCTFail("no Basic version") }
        let copied = String(basic.label.split(separator: ":", maxSplits: 1).last ?? "")
            .trimmingCharacters(in: .whitespaces)
        basic.press(forDuration: 0.8)
        XCTAssertTrue(value.lowercased().contains("sry"), "copying must not change the message, got '\(value)'")
        XCTAssertNotNil(wait("act:option:basic", 2), "holding a version keeps the versions open")
        // The copy is what the strip offers to paste once the panel is closed.
        // The strip turns into the panel's own ✕ in this look.
        if el("act:close").exists { tap("act:close") } else { tap("toolbar:close") }
        clear()
        guard let chip = wait("strip:smart", 4) else { return XCTFail("the copied version is not offered to paste") }
        note("copied '\(copied)'; strip offers '\(chip.label)'")
        XCTAssertTrue(chip.label.contains(String(copied.prefix(12))), "strip offers '\(chip.label)'")
    }

    func testS66_HoldSpaceOnAPlaceSearchSendsPlaces() throws {
        open()
        clear()
        type("best biryani near indiranagar")
        holdSpace()
        guard let insert = wait("act:insert", 20) else { return XCTFail("no places result") }
        insert.tap()
        XCTAssertTrue(waitValue(4) { $0.contains("http") }, "a link to the places should be in the message, got '\(value)'")
        note("inserted: '\(value.prefix(120))'")
    }

    func testS67_HoldSpaceOnATrailerSendsTheVideo() throws {
        open()
        clear()
        type("dune part two trailer")
        holdSpace()
        guard let insert = wait("act:insert", 20) else { return XCTFail("no video result") }
        insert.tap()
        XCTAssertTrue(waitValue(4) { $0.contains("youtu") }, "got '\(value)'")
        note("inserted: '\(value)'")
    }

    func testS68_HoldSpaceOnACurrencySumAnswersIt() throws {
        open()
        clear()
        type("100 usd to inr")
        holdSpace()
        guard let insert = wait("act:insert", 20) else { return XCTFail("no answer") }
        insert.tap()
        XCTAssertTrue(waitValue(4) { $0.contains("INR") }, "got '\(value)'")
        note("inserted: '\(value)'")
    }

    func testS69_HoldSpaceOnAnEmptyMessageOpensAsk() throws {
        open()
        clear()
        holdSpace()
        let bar = wait("bar:close", 4) ?? wait("act:close", 1)
        note("empty hold opened: \(bar?.identifier ?? "nothing")")
        XCTAssertNotNil(bar, "holding space with nothing typed should open the Ask bar")
    }

    // MARK: - The g menu

    func testS70_GButtonOpensTheToolMenuNotVault() throws {
        open()
        tap("toolbar:glyf")
        XCTAssertNotNil(wait("shell:tile:search", 3), "g should open the menu of tools")
        XCTAssertFalse(el("vault:card:0").exists, "g must not land on Vault")
        let tiles = ["search", "rewrite", "translate", "vault", "clipboard", "emoji", "ask",
                     "dictation", "glyfs", "shorthand", "keys", "pay", "settings"].filter { el("shell:tile:\($0)").exists }
        note("tiles showing: \(tiles.joined(separator: ", "))")
        tap("toolbar:close")
        XCTAssertNotNil(wait("key:a", 3), "closing the menu brings the letters back")
    }

    func testS71_MenuThenVaultCardTypesTheDetail() throws {
        open()
        clear()
        tap("toolbar:glyf")
        tap("shell:tile:vault")
        guard let card = wait("vault:card:0", 4) else { return XCTFail("vault is empty") }
        note("first vault card: \(card.label)")
        card.tap()
        XCTAssertTrue(waitValue(3) { !$0.isEmpty }, "tapping a vault card should type it")
    }

    // MARK: - Clipboard

    func testS72_CopiedTextShowsInClipboardAndPastes() throws {
        UIPasteboard.general.string = "Flight AI 2021 lands at 6:40, gate 12"
        open()
        clear()
        tap("toolbar:glyf")
        tap("shell:tile:clipboard")
        // iOS hands a keyboard the copy only after Allow Paste, so the newest
        // copy is offered as its own card on top.
        guard let fresh = wait("clip:fresh", 5) else { return XCTFail("the new copy is not offered") }
        fresh.tap()
        allowPasteIfAsked()
        XCTAssertTrue(waitValue(4) { $0.contains("AI 2021") }, "got '\(value)'")
        // From now on it lives in the clipboard history.
        clear()
        tap("toolbar:glyf")
        tap("shell:tile:clipboard")
        let saved = host.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'clip:card' AND label CONTAINS 'AI 2021'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 3), "the pasted copy should be kept in the clipboard")
        note("pasted '\(value)'")
    }

    func testS73_ScreenshotsShowInClipboard() throws {
        open(["--glyf-screenshots-on"])
        tap("toolbar:glyf")
        tap("shell:tile:clipboard")
        for host in [springboard, app] where host.alerts.firstMatch.waitForExistence(timeout: 2) {
            let alert = host.alerts.firstMatch
            alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
        }
        guard let shot = wait("clip:shot", 6) else { return XCTFail("no recent screenshot card") }
        shot.tap()
        let toast = wait("kb:toast", 3)
        note("screenshot tap toast: \(toast?.label ?? "none")")
        XCTAssertNotNil(toast, "tapping a screenshot should copy it and say so")
    }

    // MARK: - Emoji

    func testS74_EmojiKeyInsertsAnEmoji() throws {
        open()
        clear()
        type("what a finish ")
        tap("key:emojikey")
        let laugh = app.staticTexts["😂"].firstMatch
        XCTAssertTrue(laugh.waitForExistence(timeout: 4), "😂 should be on the first page")
        laugh.tap()
        XCTAssertTrue(waitValue(3) { $0.contains("😂") }, "got '\(value)'")
        if el("emoji:letters").exists { tap("emoji:letters") } else { tap("emoji:abc") }
        XCTAssertNotNil(wait("key:a", 3), "ABC should bring the letters back")
    }

    // MARK: - Stickers, GIFs and emoticons (Gboard's tabs, Apple's look)

    func testS101_EmoticonsTypeStraightIntoTheField() throws {
        open()
        clear()
        tap("key:emojikey")
        tap("emoji:mode:emoticons")
        tap("emoji:chip:classic")
        guard let first = wait("emoji:emoticon:0", 3) else { return XCTFail("no emoticons") }
        let text = first.label
        first.tap()
        XCTAssertTrue(waitValue(3) { $0.contains(text) }, "got '\(value)' after tapping '\(text)'")
        tap("emoji:mode:emoji")
        XCTAssertTrue(app.staticTexts["😂"].firstMatch.waitForExistence(timeout: 3),
                      "the emoji glyph should bring the emoji back")
    }

    /// Needs a GIF provider key on the server; without one the board says so
    /// and this fails with its words (reported as blocked, not a bug).
    func testS102_GIFTabShowsGIFsAndCopiesOne() throws {
        open()
        tap("key:emojikey")
        tap("emoji:mode:gifs")
        tap("emoji:chip:trending")
        guard let gif = wait("emoji:media:0", 12) else {
            return XCTFail("no GIFs; the board says '\(el("emoji:status").label)'")
        }
        gif.tap()
        let toast = wait("kb:toast", 12)
        XCTAssertTrue(toast?.label.contains("copied") == true, "toast '\(toast?.label ?? "none")'")
        XCTAssertTrue(UIPasteboard.general.contains(pasteboardTypes: ["com.compuserve.gif"]),
                      "the GIF should be on the pasteboard, ready to paste")
        note("GIF copied; toast '\(toast?.label ?? "")'")
        tap("emoji:mode:emoji")
    }

    func testS103_StickerTabShowsStickersAndCopiesOne() throws {
        open()
        tap("key:emojikey")
        tap("emoji:mode:stickers")
        tap("emoji:chip:trending")
        guard let sticker = wait("emoji:media:0", 12) else {
            return XCTFail("no stickers; the board says '\(el("emoji:status").label)'")
        }
        sticker.tap()
        let toast = wait("kb:toast", 12)
        XCTAssertTrue(toast?.label.contains("copied") == true, "toast '\(toast?.label ?? "none")'")
        XCTAssertTrue(UIPasteboard.general.contains(pasteboardTypes: ["com.compuserve.gif"])
                      || UIPasteboard.general.contains(pasteboardTypes: ["public.png"]),
                      "the sticker should be on the pasteboard")
        tap("emoji:mode:emoji")
    }

    func testS104_GIFSearchShowsResultsForTheWord() throws {
        open()
        tap("key:emojikey")
        tap("emoji:mode:gifs")
        tap("emoji:search")
        type("cat")
        tap("key:return")
        guard wait("emoji:media:0", 12) != nil else {
            return XCTFail("no results; the board says '\(el("emoji:status").label)'")
        }
        let section = el("emoji:section").label
        XCTAssertTrue(section.contains("CAT"), "section says '\(section)'")
        tap("emoji:mode:emoji")
    }

    func testS75_EmojiPagesSwipeSideways() throws {
        open()
        tap("key:emojikey")
        XCTAssertTrue(app.staticTexts["😂"].firstMatch.waitForExistence(timeout: 4))
        let grid = app.collectionViews.firstMatch
        XCTAssertTrue(grid.exists, "emoji grid")
        let before = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'USED' OR label CONTAINS '&'")).firstMatch.label
        for _ in 0..<3 { grid.swipeLeft() }
        usleep(800_000)
        let after = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '&' OR label == 'PEOPLE'")).firstMatch.label
        note("section before '\(before)' after swiping left '\(after)'")
        XCTAssertNotEqual(before, after, "swiping left should move through the sections")
    }

    func testS76_EmojiSearchFindsPizza() throws {
        open()
        clear()
        tap("key:emojikey")
        tap("emoji:search")
        type("pizza")
        let pizza = app.staticTexts["🍕"].firstMatch
        XCTAssertTrue(pizza.waitForExistence(timeout: 4), "🍕 for 'pizza'")
        pizza.tap()
        XCTAssertTrue(waitValue(3) { $0.contains("🍕") }, "got '\(value)'")
    }

    // MARK: - Translate and search

    func testS77_TranslateAsYouType() throws {
        open()
        clear()
        tap("toolbar:glyf")
        tap("shell:tile:translate")
        guard wait("hud:translate", 4) != nil else { return XCTFail("translate strip did not open") }
        type("kal milte hain office ke baad ")
        let text = el("hud:text")
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline, !text.label.localizedCaseInsensitiveContains("tomorrow") { usleep(400_000) }
        note("direction '\(el("hud:direction").label)', translation '\(text.label)'")
        XCTAssertTrue(text.label.localizedCaseInsensitiveContains("tomorrow"), "got '\(text.label)'")
        tap("hud:replace")
        XCTAssertTrue(waitValue(3) { $0.localizedCaseInsensitiveContains("tomorrow") }, "got '\(value)'")
    }

    func testS78_TranslateDirectionCanBeChanged() throws {
        open()
        clear()
        tap("toolbar:glyf")
        tap("shell:tile:translate")
        guard let dir = wait("hud:direction", 4) else { return XCTFail("no direction") }
        type("see you tomorrow ")
        usleep(2_500_000)
        let first = dir.label
        dir.tap()
        usleep(2_500_000)
        let second = el("hud:direction").label
        note("direction '\(first)' then '\(second)'; text '\(el("hud:text").label)'")
        XCTAssertNotEqual(first, second, "tapping the direction should change the target language")
    }

    func testS79_SearchYouTubeAndSendTheVideo() throws {
        open()
        clear()
        tap("toolbar:glyf")
        tap("shell:tile:search")
        if let yt = wait("search:tab:yt", 3) ?? wait("search:tab:youtube", 1) { yt.tap() }
        type("arijit singh live")
        tap("search:go")
        guard let card = wait("search:card:video", 12) else { return XCTFail("no video cards") }
        note("first video: \(card.label)")
        card.tap()
        XCTAssertTrue(waitValue(4) { $0.contains("youtu") }, "got '\(value)'")
    }

    // MARK: - Held keys

    func testS80_HoldTTranslates() throws {
        open(["--glyf-seed-holds"])
        clear()
        el("key:t").press(forDuration: 0.9)
        XCTAssertNotNil(wait("hud:translate", 4), "holding T should open translate")
    }

    func testS81_HoldSOpensVault() throws {
        open(["--glyf-seed-holds"])
        clear()
        el("key:s").press(forDuration: 0.9)
        XCTAssertNotNil(wait("vault:card:0", 4), "holding S should open the vault")
    }

    // MARK: - Look

    /// Luminance of the key's face, sampled away from its glyph.
    private func keyLuminance(_ id: String) -> CGFloat {
        let key = el(id)
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage else { return -1 }
        let scale = CGFloat(cg.width) / shot.size.width
        let p = CGPoint(x: (key.frame.minX + 5) * scale, y: (key.frame.midY + key.frame.height * 0.3) * scale)
        guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
        let bpp = cg.bitsPerPixel / 8
        let i = (Int(p.y) * cg.bytesPerRow) + Int(p.x) * bpp
        let (r, g, b) = (CGFloat(bytes[i]), CGFloat(bytes[i + 1]), CGFloat(bytes[i + 2]))
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255
    }

    func testS82_DarkModeKeysAreDarkAndLightModeKeysAreWhite() throws {
        // Glyf's own screens stay light; Messages follows the system, like most apps.
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        host = messages
        XCUIDevice.shared.appearance = .dark
        XCUIDevice.shared.system.open(URL(string: "sms:+15555648583&body=hi")!)
        XCTAssertTrue(messages.wait(for: .runningForeground, timeout: 8))
        sleep(2)
        if !switchToGlyf() { return XCTFail("Glyf keyboard not up in Messages") }
        let dark = keyLuminance("key:q")
        XCUIDevice.shared.appearance = .light
        sleep(2)
        let light = keyLuminance("key:q")
        messages.terminate()
        note(String(format: "key luminance dark %.2f light %.2f", dark, light))
        XCTAssertLessThan(dark, 0.35, "dark mode keys should be dark")
        XCTAssertGreaterThan(light, 0.9, "light mode keys should be white")
    }

    func testS83_StripToolsOpenInOneTap() throws {
        open()
        clear()
        // A fresh copy owns the strip as a Paste chip until it is used.
        if let chip = wait("strip:smart", 1.5) {
            note("paste chip was up: \(chip.label)")
            chip.tap()
            allowPasteIfAsked()
            clear()
        }
        let tools = ["search", "rewrite", "translate", "vault", "clipboard", "emoji", "ask", "dictation"]
            .filter { el("toolbar:\($0)").exists }
        note("strip tools: \(tools.joined(separator: ", "))")
        XCTAssertFalse(tools.isEmpty, "the strip should carry tools when nothing is typed")
        if el("toolbar:clipboard").exists {
            // The strip scrolls, so XCUITest reports its buttons in the scroll
            // view's space; tap where the icon is drawn, just above the keys.
            let icon = el("toolbar:clipboard").frame
            let row = el("key:q").frame
            host.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: icon.midX, dy: row.minY - 30)).tap()
            XCTAssertNotNil(wait("clip:back", 4), "clipboard opens from the strip")
        }
    }
}
