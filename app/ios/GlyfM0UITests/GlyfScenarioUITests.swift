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
        // The text is data, never the format: a link's %3A would read as one.
        NSLog("%@", "GLYF_SCENARIO \(name) \(text)")
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

    // MARK: - The strip and the g menu

    /// Every tool, as the g menu and the strip name them.
    private static let tools = ["search", "rewrite", "translate", "vault", "calendar", "tempmail", "clipboard",
                                "gifs", "ask", "dictation", "glyfs", "pay", "games", "settings"]

    /// Any tile of the g menu, once it is open.
    private func menuTile(_ timeout: TimeInterval = 3) -> XCUIElement? {
        let tile = host.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'shell:tile:'")).firstMatch
        return tile.waitForExistence(timeout: timeout) ? tile : nil
    }

    /// The strip scrolls, so XCUITest reports its buttons in the scroll
    /// view's space; tap where the icon is drawn, level with the g key.
    private func tapStripIcon(_ icon: XCUIElement) {
        let g = el("toolbar:glyf").exists ? el("toolbar:glyf") : el("toolbar:close")
        host.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: icon.frame.midX, dy: g.frame.midY)).tap()
    }

    /// Opens a tool wherever it lives, the way a person finds it: on the
    /// strip when it is there, else in the g menu. A tool is in one place,
    /// never both. A chip covering the strip goes when the menu opens, and
    /// the strip shows its tools over the menu.
    private func openTool(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        if let icon = wait("toolbar:\(id)", 1.5) { return tapStripIcon(icon) }
        tap("toolbar:glyf", file: file, line: line)
        var opened = menuTile()
        // With word suggestions up (a message already typed in), g first
        // brings the tools back; the second tap opens the menu.
        if opened == nil, el("toolbar:glyf").exists {
            tap("toolbar:glyf", file: file, line: line)
            opened = menuTile()
        }
        guard let first = opened else { return XCTFail("the g menu did not open", file: file, line: line) }
        let tile = el("shell:tile:\(id)")
        if tile.exists {
            for _ in 0..<4 where !tile.isHittable {
                first.swipeUp()
                usleep(400_000)
            }
            return tile.tap()
        }
        guard let icon = wait("toolbar:\(id)", 2) else {
            return XCTFail("\(id) is on neither the strip nor the menu", file: file, line: line)
        }
        tapStripIcon(icon)
    }

    /// A little of a panel's list at a time, so no row is skipped: a slow
    /// drag that stops before letting go, so the list does not fling on.
    private func nudgeUp(_ list: XCUIElement) {
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        usleep(300_000)
    }

    /// Scrolls the open panel's list until a row is on screen.
    @discardableResult
    private func scrollTo(_ id: String) -> XCUIElement? {
        let row = el(id)
        for _ in 0..<10 where !(row.exists && row.isHittable) { nudgeUp(host.tables.firstMatch) }
        return row.exists ? row : nil
    }

    /// A card in the vault panel whose words start with `text` (a shortcut)
    /// or hold it (a detail's value).
    private func vaultCard(_ text: String, prefix: Bool = false, _ timeout: TimeInterval = 4) -> XCUIElement? {
        let card = host.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'vault:card:' AND label \(prefix ? "BEGINSWITH" : "CONTAINS") %@", text))
            .firstMatch
        return card.waitForExistence(timeout: timeout) ? card : nil
    }

    /// The vault's + in the corner, then one of the options it opens.
    private func tapVaultAdd(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        if !el("vault:new:\(what)").exists { tap("vault:add", file: file, line: line) }
        guard let option = wait("vault:new:\(what)", 4) else {
            return XCTFail("the vault's + offers no \(what)", file: file, line: line)
        }
        option.tap()
    }

    /// The three options the vault's + opens.
    private var vaultOptions: [XCUIElement] {
        ["note", "detail", "shorthand"].map { el("vault:new:\($0)") }
    }

    // MARK: - The keyboard's vault tools (DEBUG, debug-vault.json)

    /// The App Group's bridge folder, found through the simulator's own
    /// files (a simulator's runner can reach them): where the keyboard's
    /// DEBUG vault tools look.
    private lazy var bridgeDir: URL? = {
        let env = ProcessInfo.processInfo.environment
        let data = env["SIMULATOR_SHARED_RESOURCES_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let groups = data.appendingPathComponent("Containers/Shared/AppGroup")
        for dir in (try? FileManager.default.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil)) ?? [] {
            let meta = dir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            if NSDictionary(contentsOf: meta)?["MCMMetadataIdentifier"] as? String == "group.com.arpit.glyf" {
                return dir.appendingPathComponent("bridge")
            }
        }
        return nil
    }()

    /// Hands the keyboard one vault tool ("stash" a kind, "unstash",
    /// "dropdetail" a value, "snippet" ";qa=text", or ";qa=" to remove it)
    /// and waits until it has run. The keyboard must be up: it looks while
    /// it shows.
    @discardableResult
    private func vaultTool(_ op: [String: String]) -> Bool {
        guard let dir = bridgeDir, let data = try? JSONSerialization.data(withJSONObject: op) else {
            note("vault tool \(op): no App Group folder found")
            return false
        }
        let url = dir.appendingPathComponent("debug-vault.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let done = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: done) as? [String: Any],
               json["done"] as? Bool == true { return true }
            usleep(250_000)
        }
        note("vault tool \(op): the keyboard did not answer")
        return false
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
        // Google Calendar and Meet stay off unless a test connects the
        // stand-in (qa/fake-google.mjs): an earlier run must not decide.
        let google = args.contains("--glyf-test-google") ? [] : ["--glyf-test-google", ""]
        app.launchArguments = ["--glyf-skip-onboarding", "--glyf-seed-vault", "--glyf-clear-tour"] + google + args
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
        type("ok")
        // Two quick taps on the same key, the way a thumb does it: looking the
        // key up again between them can take longer than the double-tap window.
        guard let space = wait("key:space", 3) else { return XCTFail("no space bar") }
        space.tap()
        space.tap()
        type("see")
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

    func testS62_AskedForYourWalletAddressItIsOneTapAway() throws {
        open()
        clear()
        type("my wallet address is ")
        guard let chip = wait("strip:smart", 4) else { return XCTFail("no wallet chip") }
        // The vault's Solana address, whichever it is (see S61); the chip may
        // shorten it, so the check is on its first characters.
        let offered = chip.label
        guard let id = offered.split(separator: " ").last(where: { $0.count >= 4 })?.prefix(4) else {
            return XCTFail("chip says '\(offered)'")
        }
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.contains(id) }, "got '\(value)' for chip '\(offered)'")
    }

    /// User, 2026-09-28: "when i type $sol i should see sol price but i see my
    /// wallet address". A cashtag is a price, never the saved wallet.
    func testS141_DollarSolShowsSolsPriceNotYourWallet() throws {
        open()
        clear()
        type("$sol")
        guard let chip = wait("strip:smart", 8) else { return XCTFail("no price chip for $sol") }
        let deadline = Date().addingTimeInterval(6)
        while !chip.label.contains("SOL =") && Date() < deadline { usleep(300_000) }
        note("$sol chip: '\(chip.label)'")
        XCTAssertTrue(chip.label.contains("1 SOL = $"), "chip says '\(chip.label)'")
        XCTAssertFalse(chip.label.lowercased().contains("wallet"), "the wallet must not answer $sol")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.contains("$sol = $") }, "got '\(value)'")
    }

    /// "$appl" (the usual slip for AAPL, or "$apple" half typed) prices Apple
    /// and says AAPL.
    func testS142_DollarApplShowsApplesPrice() throws {
        open()
        clear()
        type("$appl")
        guard let chip = wait("strip:smart", 8) else { return XCTFail("no price chip for $appl") }
        let deadline = Date().addingTimeInterval(6)
        while !chip.label.contains("AAPL") && Date() < deadline { usleep(300_000) }
        note("$appl chip: '\(chip.label)'")
        XCTAssertTrue(chip.label.contains("1 AAPL = $"), "chip says '\(chip.label)'")
    }

    /// The wallet answers when the sentence asks for it.
    func testS143_MySolAddressOffersTheWallet() throws {
        open()
        clear()
        type("my sol address is ")
        guard let chip = wait("strip:smart", 4) else { return XCTFail("no wallet chip") }
        note("typed '\(value)', wallet chip: '\(chip.label)'")
        XCTAssertFalse(chip.label.contains("="), "a price answered instead: '\(chip.label)'")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.count > "my sol address is ".count + 20 }, "got '\(value)'")
    }

    /// User, 2026-09-28: "when we search the keyboard stretches". Opening
    /// search, typing, and the results all keep one height: the keys stay
    /// where they were and the search row never moves.
    func testS144_SearchNeverChangesTheKeyboardsHeight() throws {
        open()
        clear()
        guard let q = wait("key:q", 3) else { return XCTFail("no keys") }
        let keysY = q.frame.minY
        openTool("search")
        guard let close = wait("search:close", 4) else { return XCTFail("search did not open") }
        let rowY = close.frame.minY
        XCTAssertEqual(el("key:q").frame.minY, keysY, accuracy: 1, "opening search moved the keys")
        type("coffee")
        XCTAssertEqual(el("key:q").frame.minY, keysY, accuracy: 1, "typing a query moved the keys")
        XCTAssertEqual(el("search:close").frame.minY, rowY, accuracy: 1, "the search row moved while typing")
        tap("search:go")
        _ = wait("search:card:link", 12) ?? wait("search:card:answer", 1)
        XCTAssertEqual(el("search:close").frame.minY, rowY, accuracy: 1, "the results changed the keyboard's height")
        note("keys at \(keysY), search row at \(rowY), results row at \(el("search:close").frame.minY)")
    }

    /// A store in Maps comes with a picture, like a video's thumbnail: its
    /// photo when Google Places is on, else a little map of where it is.
    func testS145_MapsResultsCarryAPicture() throws {
        open()
        clear()
        openTool("search")
        if let maps = wait("search:tab:maps", 3) { maps.tap() }
        type("coffee near me")
        tap("search:go")
        guard let place = wait("search:card:place", 12) else { return XCTFail("no places") }
        sleep(3)
        note("first place: \(place.label)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "S145 maps results"
        shot.lifetime = .keepAlways
        add(shot)
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
        // Worked out on the phone ("$100 = ₹9,588") when its rates are in
        // hand, by the server ("100 USD is 9,598 INR") when they are not.
        XCTAssertTrue(waitValue(4) { $0.contains("INR") || $0.contains("₹") }, "got '\(value)'")
        note("inserted: '\(value)'")
    }

    /// S215: every chip has a ✕; a dismissed chip stays gone for the same
    /// text, the next change brings one back, and Insert never dismisses
    /// (Arpit, 2026-09-30: "we should add some button to dismiss it").
    func testS215_AChipsCrossDismissesItForThatText() throws {
        open()
        clear()
        type("2+5")
        guard wait("strip:smart", 3) != nil else { return XCTFail("no chip for 2+5") }
        guard let close = wait("strip:smart:close", 2) else { return XCTFail("the chip has no ✕") }
        close.tap()
        XCTAssertTrue(gone("strip:smart", 3), "the chip stayed after its ✕")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(el("strip:smart").exists, "the dismissed chip came back for the same text")
        XCTAssertTrue(value.hasPrefix("2+5") && !value.contains("="), "dismiss changed the text: '\(value)'")
        type("0")
        guard let again = wait("strip:smart", 3) else { return XCTFail("no chip for 2+50") }
        XCTAssertTrue(again.label.contains("52"), "the strip shows '\(again.label)'")
        again.tap()
        XCTAssertTrue(waitValue(3) { $0.contains("2+50 = 52") }, "Insert gave '\(value)'")
        note("dismissed 2+5, then 2+50 inserted '\(value)'")
    }

    /// S219: typing "email" offers every saved email and a temp address;
    /// a tap on a part types it (Arpit, 2026-10-01: "when i type email it
    /// should show my email id from vault, and if i added 2 mail ids i
    /// should see both, and i should also see a temp mail option").
    func testS219_TypingEmailOffersEverySavedEmailAndTempMail() throws {
        open()
        let first = "alex.s219@example.com", second = "alex@acme-s219.example"
        XCTAssertTrue(vaultTool(["op": "adddetail", "kind": "email", "label": "Email", "value": first]))
        XCTAssertTrue(vaultTool(["op": "adddetail", "kind": "email", "label": "Work", "value": second]))
        defer {
            _ = vaultTool(["op": "dropdetail", "value": first])
            _ = vaultTool(["op": "dropdetail", "value": second])
        }
        clear()
        type("email")
        guard wait("strip:smart:choice:0", 6) != nil else {
            return XCTFail("no email parts; the strip shows '\(el("strip:smart").label)'")
        }
        let parts = [el("strip:smart:choice:0").label, el("strip:smart:choice:1").label]
        XCTAssertEqual(Set(parts), Set([first, second]), "the chip offers \(parts)")
        XCTAssertTrue(el("strip:smart:choice:temp").exists, "no Temp mail beside the emails")
        keepScreenshot("email-choices")
        let pick = el("strip:smart:choice:1").label
        el("strip:smart:choice:1").tap()
        // "email" may have taken a capital at the start of the message.
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "email \(pick)".lowercased() }, "the tap typed '\(value)'")
        note("parts \(parts), typed '\(value)'")
    }

    /// S222: a measurement shows in the other system, one chip each, and a
    /// tap adds it in brackets (Arpit, 2026-10-03: "when i write lets 10
    /// inch, i see in cm or meteres, diff strips with suggestions").
    func testS222_AMeasurementShowsInTheOtherSystem() throws {
        open()
        clear()
        type("lets 10 inch")
        guard wait("strip:smart:choice:1", 6) != nil else {
            return XCTFail("no unit chips; the strip shows '\(el("strip:smart").label)'")
        }
        let parts = [el("strip:smart:choice:0").label, el("strip:smart:choice:1").label]
        XCTAssertEqual(parts, ["25.4 cm", "0.254 m"])
        keepScreenshot("unit-chips")
        el("strip:smart:choice:0").tap()
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "lets 10 inch (25.4 cm)" }, "the tap typed '\(value)'")
        note("chips \(parts), typed '\(value)'")
    }

    /// S223: a bill split shows what each pays.
    func testS223_ABillSplitShowsWhatEachPays() throws {
        open()
        clear()
        type("split 120 4 ways")
        guard wait("strip:smart:choice:0", 6) != nil else {
            return XCTFail("no split chip; the strip shows '\(el("strip:smart").label)'")
        }
        XCTAssertEqual(el("strip:smart:choice:0").label, "30 each")
        note("chip '\(el("strip:smart:choice:0").label)'")
    }

    /// S224: a ;date shortcut is replaced by the date.
    func testS224_ADateShortcutIsReplacedByTheDate() throws {
        open()
        clear()
        type("today is ;date")
        guard wait("strip:smart:choice:0", 6) != nil else {
            return XCTFail("no date chip; the strip shows '\(el("strip:smart").label)'")
        }
        let date = el("strip:smart:choice:0").label
        el("strip:smart:choice:0").tap()
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "today is \(date)".lowercased() }, "the tap typed '\(value)'")
        note("chip '\(date)', typed '\(value)'")
    }

    /// S225: g menu → Style: Bold restyles the message (Arpit, 2026-10-03:
    /// "option to stylise text in glyf menu like bold italic underline").
    func testS225_StyleBoldRestylesTheMessage() throws {
        open()
        clear()
        type("hello world")
        openTool("style")
        guard let bold = wait("shell:style:bold", 6) else { return XCTFail("no Style screen") }
        keepScreenshot("style-screen")
        bold.tap()
        // "hello world" may have taken a capital at the start.
        XCTAssertTrue(waitValue(3) { ["𝗛𝗲𝗹𝗹𝗼 𝘄𝗼𝗿𝗹𝗱", "𝗵𝗲𝗹𝗹𝗼 𝘄𝗼𝗿𝗹𝗱"].contains($0) }, "Bold made '\(value)'")
        note("after Bold: '\(value)'")
    }

    // MARK: What launchers work out (Arpit, 2026-10-03: "find more things from raycast etc too")

    /// S226: a link loses its trackers in one tap (Raycast's Link Cleaner).
    func testS226_ALinkLosesItsTrackers() throws {
        open()
        clear()
        type("check https://youtu.be/abc123?si=xyz789")
        guard let chip = wait("strip:smart:choice:0", 6) else {
            keepScreenshot("clean-link-missing")
            return XCTFail("no chip for '\(value)'")
        }
        let label = chip.label
        XCTAssertEqual(label, "Remove tracking")
        keepScreenshot("clean-link")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "check https://youtu.be/abc123" }, "the tap typed '\(value)'")
        note("chip '\(label)', typed '\(value)'")
    }

    /// S227: a face by its name, as Slack has /shrug.
    func testS227_AFaceByItsName() throws {
        open()
        clear()
        type("ok /shrug")
        guard let chip = wait("strip:smart:choice:0", 6) else {
            return XCTFail("no face; the strip shows '\(el("strip:smart").label)'")
        }
        let label = chip.label
        XCTAssertEqual(label, "¯\\_(ツ)_/¯")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "ok ¯\\_(ツ)_/¯" }, "the tap typed '\(value)'")
        note("chip '\(label)', typed '\(value)'")
    }

    /// S228: cups of flour in grams, from King Arthur's weights.
    func testS228_ARecipesCupsInGrams() throws {
        open()
        clear()
        type("2 cups flour")
        guard wait("strip:smart:choice:1", 6) != nil else {
            return XCTFail("no weight chips; the strip shows '\(el("strip:smart").label)'")
        }
        let parts = [el("strip:smart:choice:0").label, el("strip:smart:choice:1").label]
        XCTAssertEqual(parts, ["240 g", "8.47 oz"])
        keepScreenshot("cups-in-grams")
        el("strip:smart:choice:0").tap()
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "2 cups flour (240 g)" }, "the tap typed '\(value)'")
        note("chips \(parts), typed '\(value)'")
    }

    /// S229: a shift on the clock, worked out.
    func testS229_AShiftOnTheClockWorkedOut() throws {
        open()
        clear()
        type("shift 9:30-5:15")
        guard let chip = wait("strip:smart:choice:0", 6) else {
            return XCTFail("no span; the strip shows '\(el("strip:smart").label)' for '\(value)'")
        }
        XCTAssertEqual(chip.label, "7 h 45 min")
        note("chip '\(chip.label)'")
    }

    /// S230: a coin flipped from the strip, added after.
    func testS230_ACoinFlippedFromTheStrip() throws {
        open()
        clear()
        type("flip a coin")
        guard let chip = wait("strip:smart:choice:0", 6) else {
            return XCTFail("no coin; the strip shows '\(el("strip:smart").label)'")
        }
        let label = chip.label
        XCTAssertTrue(["🪙 Heads", "🪙 Tails"].contains(label), "the coin said '\(label)'")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "flip a coin \(label)".lowercased() }, "the tap typed '\(value)'")
        note("chip '\(label)', typed '\(value)'")
    }

    /// S231: g menu → Style: UPPERCASE, with the message's count on top.
    func testS231_StyleUppercaseAndTheCount() throws {
        open()
        clear()
        type("hello world")
        openTool("style")
        guard wait("shell:style:bold", 6) != nil else { return XCTFail("no Style screen") }
        let count = host.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "2 words · 11 characters")).firstMatch
        let counted = count.exists
        XCTAssertTrue(counted, "no count on the Style screen")
        keepScreenshot("style-case")
        // The cases sit under the styles: the list is swiped up, on whichever
        // row shows, until they do.
        // A drag with no fling: the lowest row shown up to the top one.
        let order = ["bold", "italic", "boldItalic", "underline", "strike", "upper", "lower", "titleCase", "sentenceCase",
                     "serifBold", "script", "doubleStruck", "monospace", "bubble", "smallCaps", "wide", "upsideDown", "plain"]
        for _ in 0..<8 where !(el("shell:style:upper").exists && el("shell:style:upper").isHittable) {
            let shown = order.indices.filter { el("shell:style:\(order[$0])").exists && el("shell:style:\(order[$0])").isHittable }
            guard let first = shown.first, let last = shown.last, first != last else { break }
            let top = el("shell:style:\(order[first])"), bottom = el("shell:style:\(order[last])")
            // Held at the end, so the list doesn't fling on past; back down
            // when it went too far.
            if first > order.firstIndex(of: "upper")! {
                top.press(forDuration: 0.1, thenDragTo: bottom, withVelocity: .slow, thenHoldForDuration: 0.3)
            } else {
                bottom.press(forDuration: 0.1, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
            }
        }
        guard let upper = wait("shell:style:upper", 3) else {
            keepScreenshot("style-no-upper")
            return XCTFail("no UPPERCASE in Style")
        }
        upper.tap()
        XCTAssertTrue(waitValue(3) { $0 == "HELLO WORLD" }, "UPPERCASE made '\(value)'")
        note("count shown: \(counted); after UPPERCASE: '\(value)'")
    }

    /// S232: shorthand with blanks: {day} filled in, and {cursor} is where
    /// typing goes on.
    func testS232_ShorthandBlanksFillIn() throws {
        open()
        clear()
        addTeardownBlock { [self] in
            if !(el("toolbar:glyf").exists || el("toolbar:close").exists) { open() }
            vaultTool(["op": "snippet", "text": ";s232="])
            vaultTool(["op": "snippet", "text": ";s232b="])
        }
        XCTAssertTrue(vaultTool(["op": "snippet", "text": ";s232=Today is {day}"]))
        XCTAssertTrue(vaultTool(["op": "snippet", "text": ";s232b=Hi {cursor}, thanks!"]))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE"
        let day = f.string(from: Date())
        type("ok ;s232 ")
        XCTAssertTrue(waitValue(3) { $0.lowercased().contains("today is \(day.lowercased())") && !$0.contains("{") },
                      "';s232' typed '\(value)'")
        let first = value
        clear()
        type(";s232b ")
        type("sam")
        XCTAssertTrue(waitValue(3) { $0.lowercased() == "hi sam, thanks!" }, "';s232b' then 'sam' made '\(value)'")
        note("{day}: '\(first)'; {cursor}: '\(value)'")
    }

    /// S233: an hourly rate as a year and a month (40 hours a week).
    func testS233_AnHourlyRateAsAYear() throws {
        open()
        clear()
        type("$45/hr")
        guard wait("strip:smart:choice:1", 6) != nil else {
            return XCTFail("no pay chips; the strip shows '\(el("strip:smart").label)' for '\(value)'")
        }
        let parts = [el("strip:smart:choice:0").label, el("strip:smart:choice:1").label]
        XCTAssertEqual(parts, ["$93,600/yr", "$7,800/mo"])
        el("strip:smart:choice:0").tap()
        XCTAssertTrue(waitValue(3) { $0 == "$45/hr ($93,600/yr)" }, "the tap typed '\(value)'")
        note("chips \(parts), typed '\(value)'")
    }

    /// S234: the emoji board has every emoji Apple's has, found by its words:
    /// "tears" finds 🥹 first (Arpit, 2026-10-03: "some emoji like happy watery
    /// eyes i couldnt find in ours").
    func testS234_EmojiSearchFindsTheFaceHoldingBackTears() throws {
        open()
        clear()
        tap("key:emojikey")
        if let emoji = wait("emoji:mode:emoji", 3) { emoji.tap() }
        tap("emoji:search")
        type("tears")
        guard let first = wait("emoji:result:0", 6) else { return XCTFail("no results for 'tears'") }
        let found = first.value as? String ?? ""
        XCTAssertEqual(found, "🥹", "the first result was \(first.label)")
        keepScreenshot("emoji-tears")
        first.tap()
        XCTAssertTrue(waitValue(3) { $0.contains("🥹") }, "the tap typed '\(value)'")
        note("first result '\(found)' (\(first.label)), typed '\(value)'")
    }

    /// Not now on the app's "What Glyf sends" (Google Play's prominent
    /// disclosure): the sentence goes to the server on a pause only after a
    /// yes, so S63's message gets no Tidy this up.
    func testS235_NotNowOnWhatGlyfSendsSendsNothingOnAPause() throws {
        open(["--glyf-ai-not-now"])
        clear()
        type("ya ok will send the deck before six tmrw ")
        // S63 sees its chip within 10 s; give this one as long.
        let chip = wait("strip:smart", 10)
        note(chip.map { "a chip showed: '\($0.label)'" } ?? "no AI suggestion after 10 s")
        XCTAssertFalse(chip?.label.localizedCaseInsensitiveContains("tidy") ?? false,
                       "a suggestion showed: '\(chip?.label ?? "")'")
    }

    /// S214: money typed shows in the local currency in the strip (Arpit,
    /// 2026-09-30: "$20 not showing amount in local currency ... i want
    /// rupee, or whatever i set in as local currency here in app").
    func testS214_MoneyShowsInTheLocalCurrencyInTheStrip() throws {
        // Rupees set in the app, whatever the region (an "auto" left by the
        // last run followed a US region to dollars, and $20 had nothing to
        // convert). Back to auto after.
        open(["--glyf-money-currency", "INR"])
        defer { open(["--glyf-money-currency", "auto"]) }
        var seen: [String] = []
        for typed in ["$20", "it costs $20"] {
            clear()
            type(typed)
            let chip = wait("strip:smart", 6)
            let label = chip?.label ?? "none"
            seen.append("\(typed) → \(label)")
            XCTAssertTrue(label.contains("₹"), "\(typed): the strip shows '\(label)'")
        }
        keepScreenshot("money-strip")
        note(seen.joined(separator: "; "))
    }


    /// S198: a sum shows its answer in the strip as it is typed, no hold
    /// (user, 2026-09-29: "why am i needing to hold space, suggest it in strip").
    func testS198_ASumShowsItsAnswerInTheStripAsYouType() throws {
        open()
        clear()
        var seen: [String] = []
        // Every operator on the keys (Arpit, 2026-09-29: "not working on 2-3 ... all maths symbols").
        for (typed, answer) in [("2+5", "7"), ("12*12", "144"), ("100-15%", "85"), ("2^10", "1,024"), ("150-45", "105"),
                                ("24/7", "3.43"), ("2-3", "-1"), ("2x3", "6"), ("5>3", "true")] {
            clear()
            type(typed)
            let chip = wait("strip:smart", 3)
            let label = chip?.label ?? "none"
            seen.append("\(typed) → \(label)")
            XCTAssertTrue(label.contains(answer), "\(typed): the strip shows '\(label)'")
        }
        keepScreenshot("sum-strip")
        note(seen.joined(separator: "; "))
        // Tapping it puts the answer after the sum.
        clear()
        type("2+5")
        guard let chip = wait("strip:smart", 3) else { return XCTFail("no chip for 2+5") }
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.hasPrefix("2+5") && $0.contains("7") }, "got '\(value)'")
        note("inserted '\(value)'")
    }

    /// S210: what only looks like a sum stays quiet: a phone number, a date,
    /// a count (audit 2026-09-29: "page 2 of 10" had offered "= 20").
    func testS210_APhoneNumberADateOrACountShowsNoSum() throws {
        open()
        var seen: [String] = []
        for typed in ["call me at 555-1234", "born 29/09/2024", "page 2 of 10"] {
            clear()
            type(typed)
            Thread.sleep(forTimeInterval: 1.0)
            let chip = el("strip:smart")
            let label = chip.exists ? chip.label : "no chip"
            seen.append("\(typed) → \(label)")
            XCTAssertFalse(chip.exists && label.contains("="), "\(typed): the strip shows '\(label)'")
        }
        note(seen.joined(separator: "; "))
    }

    /// S213: a question offers "AI answer" in the strip, with or without its
    /// "?", and a tap answers it (Arpit, 2026-09-29: "have a strip like ai
    /// answer ? on all questions type"; "what is polynomial" showed nothing
    /// on the simulator, whose local server had not been restarted).
    func testS213_AQuestionOffersAnAIAnswerAndATapAnswersIt() throws {
        open()
        clear()
        type("what is polynomial")
        guard let chip = wait("strip:smart", 8) else { return XCTFail("no chip for 'what is polynomial'") }
        note("chip: '\(chip.label)'")
        XCTAssertTrue(chip.label.contains("AI answer"), "the strip shows '\(chip.label)'")
        keepScreenshot("ai-answer-chip")
        chip.tap()
        guard let insert = wait("act:insert", 15) else { return XCTFail("no answer after the tap") }
        keepScreenshot("ai-answer-card")
        insert.tap()
        XCTAssertTrue(waitValue(4) { $0.lowercased().contains("polynomial") && $0.count > 30 }, "got '\(value)'")
        note("inserted '\(value)'")
        // A question to the person in the chat gets no AI answer.
        clear()
        type("are you coming tonight?")
        Thread.sleep(forTimeInterval: 3)
        let other = el("strip:smart")
        XCTAssertFalse(other.exists && other.label.contains("AI answer"), "a question to a friend offered '\(other.label)'")
    }

    /// S189: hold space on a sum and the answer is there at once, worked
    /// out on the phone (user, 2026-09-29: "i wanna do math 2+5 its taking
    /// long, we dont need ai for this").
    func testS189_HoldSpaceOnASumAnswersAtOnce() throws {
        open()
        clear()
        type("2+5")
        let start = Date()
        holdSpace()
        guard let insert = wait("act:insert", 4) else { return XCTFail("no answer") }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        insert.tap()
        XCTAssertTrue(waitValue(4) { $0.contains("2+5 = 7") }, "got '\(value)'")
        note("answer up \(ms) ms after the hold began; inserted '\(value)'")
        XCTAssertLessThan(ms, 4000, "the hold is 1.2 s; the answer needs no network after it")
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
        XCTAssertNotNil(menuTile(), "g should open the menu of tools")
        XCTAssertFalse(el("vault:card:0").exists, "g must not land on Vault")
        let tiles = Self.tools.filter { el("shell:tile:\($0)").exists }
        note("tiles showing: \(tiles.joined(separator: ", "))")
        tap("toolbar:close")
        XCTAssertNotNil(wait("key:a", 3), "closing the menu brings the letters back")
    }

    /// The vault is on the strip by default, so it opens from there (the g
    /// menu carries only what the strip does not).
    func testS71_MenuThenVaultCardTypesTheDetail() throws {
        open()
        clear()
        openTool("vault")
        guard let card = wait("vault:card:0", 4) else { return XCTFail("vault is empty") }
        note("first vault card: \(card.label)")
        card.tap()
        XCTAssertTrue(waitValue(3) { !$0.isEmpty }, "tapping a vault card should type it")
    }

    /// S199: the g menu carries only what the strip does not (user,
    /// 2026-09-29: "remove items in menu that are in top bar, icon can be
    /// either in top bar or in menu"). Emoji gave its tile to GIFs, which
    /// opens the emoji board on its GIFs tab. A tool taken off the strip
    /// comes back to the menu.
    func testS199_TheMenuLeavesOutTheStripAndOpensGIFs() throws {
        open()
        let onStrip = Self.tools.filter { el("toolbar:\($0)").exists }
        tap("toolbar:glyf")
        guard menuTile() != nil else { return XCTFail("g should open the menu") }
        let inMenu = Self.tools.filter { el("shell:tile:\($0)").exists }
        note("strip: \(onStrip.joined(separator: ", ")); menu: \(inMenu.joined(separator: ", "))")
        keepScreenshot("menu")
        XCTAssertFalse(onStrip.isEmpty, "the strip carries tools")
        for id in onStrip {
            XCTAssertFalse(inMenu.contains(id), "\(id) is on the strip and in the menu")
        }
        XCTAssertEqual(Set(onStrip + inMenu).count, Self.tools.count, "every tool is in one place")
        for id in ["emoji", "keys", "shorthand"] {
            XCTAssertFalse(el("shell:tile:\(id)").exists, "the \(id) tile is gone")
        }
        tap("shell:tile:gifs")
        guard let gifs = wait("emoji:mode:gifs", 4) else { return XCTFail("the emoji board did not open") }
        XCTAssertTrue(gifs.isSelected, "the board should open on its GIFs tab")
        XCTAssertTrue(el("emoji:mode:stickers").exists, "Stickers sits beside it")
        let search = el("emoji:search").label
        XCTAssertTrue(search.contains("GIFs") || search.contains("KLIPY"), "the search field says '\(search)'")
        sleep(2)
        keepScreenshot("gifs-tab")
        note("GIFs opened the board on '\(search)'")
        tap("emoji:letters")

        // Voice off the strip (Settings › Toolbar items) is Voice in the menu.
        guard onStrip.contains("dictation") else { return }
        func flipVoice() {
            openTool("settings")
            guard let items = scrollTo("shell:toolbar") else { return XCTFail("no Toolbar items in Settings") }
            items.tap()
            let row = el("toggle:Voice").exists ? el("toggle:Voice") : host.staticTexts["Voice"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 3), "no Voice row in Toolbar items")
            row.tap()
            tap("toolbar:back")
            tap("toolbar:back")
        }
        flipVoice()
        let moved = wait("shell:tile:dictation", 3) != nil
        keepScreenshot("menu-with-voice")
        XCTAssertFalse(el("toolbar:dictation").exists, "Voice is still on the strip")
        tap("toolbar:close")
        flipVoice()
        let back = gone("shell:tile:dictation", 3)
        tap("toolbar:close")
        XCTAssertTrue(moved, "Voice taken off the strip should show in the menu")
        XCTAssertTrue(back, "Voice back on the strip should leave the menu")
        XCTAssertNotNil(wait("toolbar:dictation", 3), "Voice is back on the strip")
    }

    /// S200: Keys and My glyfs said the same thing (user, 2026-09-29: "my
    /// glyfs and keys are ... showing same thing, and we dont need both").
    /// One tile, My glyfs: each held key's glyf with "Hold X", then the glyfs
    /// on no key, then Build your own. A row does what holding its key does.
    func testS200_MyGlyfsListsTheHeldKeysAndDoesWhatTheyDo() throws {
        open()
        tap("toolbar:glyf")
        guard menuTile() != nil else { return XCTFail("g should open the menu") }
        XCTAssertFalse(el("shell:tile:keys").exists, "no Keys tile")
        tap("shell:tile:glyfs")
        let listed = NSPredicate(format: "identifier BEGINSWITH 'shell:key:' OR identifier BEGINSWITH 'shell:run:' OR identifier == 'shell:app:build'")
        guard host.descendants(matching: .any).matching(listed).firstMatch.waitForExistence(timeout: 4) else {
            return XCTFail("My glyfs did not open")
        }
        keepScreenshot("my-glyfs")
        // The list scrolls; read every row on the way down.
        var rows: [String: String] = [:]
        var order: [String] = []
        let table = host.tables.firstMatch
        for _ in 0..<16 {
            let seen = host.descendants(matching: .any).matching(listed).allElementsBoundByIndex
            for row in seen where row.exists && rows[row.identifier] == nil {
                rows[row.identifier] = row.label
                order.append(row.identifier)
            }
            if rows["shell:app:build"] != nil { break }
            nudgeUp(table)
        }
        note("rows: " + order.map { "\($0)=\(rows[$0] ?? "")" }.joined(separator: "; "))
        XCTAssertEqual(order.last, "shell:app:build", "Build your own ends the list")
        // The keys first, in the keyboard's order; then glyfs on no key.
        let keys = order.filter { $0.hasPrefix("shell:key:") }
        XCTAssertEqual(Array(order.prefix(keys.count)), keys, "held keys lead the list")
        let qwerty = "qwertyuiopasdfghjklzxcvbnm"
        let positions = keys.compactMap { qwerty.firstIndex(of: Character(String($0.suffix(1)))) }
        XCTAssertEqual(positions, positions.sorted(), "in the keys' own order")
        // Every key the settings hold, none missing.
        if let dir = bridgeDir,
           let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")),
           let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let bindings = settings["bindings"] as? [String: String] {
            let bound = qwerty.map(String.init).filter { bindings[$0] != nil }.map { "shell:key:\($0)" }
            XCTAssertEqual(keys, bound, "one row per held key")
        }
        guard let v = rows["shell:key:v"] else { return XCTFail("no row for the V hold (the vault)") }
        XCTAssertTrue(v.contains("Vault") && v.contains("Hold V"), "V reads '\(v)'")
        for (id, label) in rows where id.hasPrefix("shell:key:") {
            let letter = id.dropFirst("shell:key:".count).uppercased()
            XCTAssertTrue(label.hasSuffix("Hold \(letter)"), "\(id) reads '\(label)'")
        }
        keepScreenshot("my-glyfs-end")
        // Tapping V's row does what holding V does: the vault opens.
        let vRow = el("shell:key:v")
        for _ in 0..<8 where !(vRow.exists && vRow.isHittable) {
            table.swipeDown()
            usleep(400_000)
        }
        vRow.tap()
        XCTAssertNotNil(wait("vault:add", 4), "V's row should open the vault")
        keepScreenshot("my-glyfs-v-row-opened-vault")
    }

    /// S201: shorthand is part of the vault now, and a detail is added from
    /// the keyboard, not only a note (user, 2026-09-29: "why cant we add
    /// details or shorthand"). The strip offers it as soon as the sentence
    /// asks, and the app's Vault lists it.
    func testS201_VaultShowsShorthandAndAddsADetailFromTheKeys() throws {
        let email = "s201@example.com"
        open()
        clear()
        // The email added here must be the one offered: saved emails are set
        // aside for the run (kept in the vault as Other, put back after).
        XCTAssertTrue(vaultTool(["op": "unstash"]), "the keyboard's vault tools did not answer")
        addTeardownBlock { [self] in
            if !(el("toolbar:glyf").exists || el("toolbar:close").exists) { open() }
            vaultTool(["op": "dropdetail", "value": email])
            vaultTool(["op": "unstash"])
        }
        XCTAssertTrue(vaultTool(["op": "dropdetail", "value": email]))
        XCTAssertTrue(vaultTool(["op": "stash", "kind": "email"]))

        openTool("vault")
        guard let sig = vaultCard(";sig,", prefix: true) else { return XCTFail("no ;sig card in the vault") }
        note("shorthand card: \(sig.label)")
        keepScreenshot("vault-with-shorthand")
        sig.tap()
        XCTAssertTrue(waitValue(3) { $0.contains("Arpit") }, "tapping ;sig should type it, got '\(value)'")

        clear()
        openTool("vault")
        // One + in the corner (user, 2026-09-29): its three options stay out
        // of sight until it is tapped, and × or the panel behind put them away.
        guard let plus = wait("vault:add", 4) else { return XCTFail("no + in the vault") }
        XCTAssertFalse(vaultOptions.contains { $0.exists }, "the options show before + is tapped")
        keepScreenshot("vault-plus-closed")
        plus.tap()
        XCTAssertTrue(vaultOptions.allSatisfy { $0.waitForExistence(timeout: 2) }, "+ should open all three options")
        XCTAssertEqual(el("vault:add").label, "Close", "the + turns into a ×")
        sleep(1)
        keepScreenshot("vault-plus-open")
        tap("vault:add")
        XCTAssertTrue(gone("vault:new:note", 2), "× should put the options away")
        tap("vault:add")
        XCTAssertNotNil(wait("vault:new:note", 2))
        // Far left on the +'s own line: a card, or the empty panel, behind.
        host.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: plus.frame.midY)).tap()
        XCTAssertTrue(gone("vault:new:note", 2), "a tap on the panel behind should put the options away")
        XCTAssertEqual(value, "", "that tap must not type the card under it")
        tapVaultAdd("detail")
        guard wait("vault:kind:email", 4) != nil else { return XCTFail("no kinds to pick from") }
        keepScreenshot("new-detail-kinds")
        note("kinds: " + ["name", "email", "phone", "address", "wallet", "upi", "link", "custom"]
            .filter { el("vault:kind:\($0)").exists }.joined(separator: ", "))
        tap("vault:kind:email")
        guard wait("noteedit:field", 4) != nil else { return XCTFail("no editor strip for the email") }
        type(email)
        keepScreenshot("detail-strip")
        tap("noteedit:save")
        guard let card = vaultCard(email) else {
            return XCTFail("the new email is not in the vault; the strip says '\(el("noteedit:status").label)'")
        }
        note("added: \(card.label)")
        keepScreenshot("vault-with-new-email")
        tap("toolbar:close")

        clear()
        type("my email is ")
        guard let chip = wait("strip:smart", 4) else { return XCTFail("no chip for 'my email is '") }
        note("chip: \(chip.label)")
        XCTAssertTrue(chip.label.contains(email), "chip says '\(chip.label)'")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0.contains(email) }, "got '\(value)'")

        // The app reads the same vault: its Vault screen lists the email.
        XCUIDevice.shared.system.open(URL(string: "glyf://open?path=vault")!)
        let openIt = springboard.buttons["Open"]
        if openIt.waitForExistence(timeout: 2) { openIt.tap() }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", email)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the app's Vault doesn't list the new email")
        keepScreenshot("app-vault")
    }

    /// S202: a shorthand made on the keyboard expands the moment it is typed.
    func testS202_AShorthandAddedFromTheKeysExpandsWhenTyped() throws {
        open()
        clear()
        addTeardownBlock { [self] in
            if !(el("toolbar:glyf").exists || el("toolbar:close").exists) { open() }
            vaultTool(["op": "snippet", "text": ";s202="])
        }
        openTool("vault")
        tapVaultAdd("shorthand")
        guard let shortcut = wait("noteedit:shortcut", 4) else { return XCTFail("no shortcut field") }
        XCTAssertEqual(shortcut.value as? String, ";", "the shortcut starts with its semicolon")
        type("s202")
        tap("key:return") // on to what it types out
        type("see you at the station")
        keepScreenshot("shorthand-strip")
        tap("noteedit:save")
        guard let card = vaultCard(";s202,", prefix: true) else {
            return XCTFail("the shorthand is not in the vault; the strip says '\(el("noteedit:status").label)'")
        }
        note("added: \(card.label)")
        keepScreenshot("vault-with-new-shorthand")
        tap("toolbar:close")

        clear()
        type("meet me ;s202 ")
        XCTAssertTrue(waitValue(3) { $0.lowercased().contains("see you at the station") && !$0.contains(";s202") },
                      "';s202 ' should expand, got '\(value)'")
        note("typed 'meet me ;s202 ' -> '\(value)'")
    }

    // MARK: - Temp mail (qa/fake-mailtm.mjs on 8798, standing in for mail.tm)

    private static let fakeMailTM = "http://127.0.0.1:8798"

    /// The keyboard asks mail.tm itself; for this scenario it asks the
    /// stand-in instead (the setting `tempMailBase`), and asks mail.tm again
    /// after.
    private func useFakeMailTM() {
        guard let url = bridgeDir?.appendingPathComponent("settings.json") else {
            return XCTFail("no App Group folder found")
        }
        func edit(_ change: (inout [String: Any]) -> Void) {
            guard let data = try? Data(contentsOf: url),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            change(&json)
            if let out = try? JSONSerialization.data(withJSONObject: json) { try? out.write(to: url, options: .atomic) }
        }
        let before = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["tempMailBase"]
        edit { $0["tempMailBase"] = Self.fakeMailTM }
        addTeardownBlock {
            edit { json in
                if let before { json["tempMailBase"] = before } else { json.removeValue(forKey: "tempMailBase") }
            }
        }
    }

    /// Drops a mail into a temp address at the stand-in, the way a sign-up
    /// form's mail arrives.
    @discardableResult
    private func injectMail(_ address: String, subject: String, text: String,
                            from: String = "Acme", fromAddress: String = "no-reply@acme.example") -> Bool {
        guard let url = URL(string: "\(Self.fakeMailTM)/_inject"),
              let body = try? JSONSerialization.data(withJSONObject: [
                  "email": address, "subject": subject, "text": text,
                  "fromName": from, "fromAddress": fromAddress]) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let done = DispatchSemaphore(value: 0)
        var status = 0
        URLSession.shared.dataTask(with: req) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return status == 200
    }

    /// Temp mail open with no address in it: a live one is deleted first.
    private func openTempMailEmpty(file: StaticString = #filePath, line: UInt = #line) {
        openTool("tempmail", file: file, line: line)
        if let delete = wait("tempmail:delete", 2) { delete.tap() }
        XCTAssertNotNil(wait("tempmail:create", 4), "no Create address in Temp mail", file: file, line: line)
    }

    /// No address live, and the panel closed again.
    private func endTempAddress(file: StaticString = #filePath, line: UInt = #line) {
        openTempMailEmpty(file: file, line: line)
        tap("toolbar:close", file: file, line: line)
    }

    /// Create in the open panel; the address, as its card reads in full.
    private func makeTempAddress() -> String? {
        tap("tempmail:create")
        guard let card = wait("tempmail:address", 10) else {
            note("no address after Create")
            return nil
        }
        return card.label
    }

    /// Teardown's fallback: the keyboard forgets the scenario's address the
    /// next time it shows (the stand-in keeps the inbox, which is harmless).
    private func forgetTempMail() {
        guard let dir = bridgeDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("tempmail.json"))
    }

    /// The strip's chip, once it reads what `ok` wants.
    private func waitChip(_ timeout: TimeInterval, _ ok: (String) -> Bool) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let chip = el("strip:smart")
            if chip.exists, ok(chip.label) { return chip }
            usleep(300_000)
        }
        return nil
    }

    /// Messages on a dark sheet (it follows the system; Glyf's own screens
    /// stay light), the Glyf keyboard up in a new message. Light and Glyf
    /// again once the scenario ends.
    private func darkMessages() -> XCUIApplication? {
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        addTeardownBlock { [self] in
            XCUIDevice.shared.appearance = .light
            messages.terminate()
            host = app
        }
        host = messages
        XCUIDevice.shared.appearance = .dark
        XCUIDevice.shared.system.open(URL(string: "sms:+15555648583&body=hi")!)
        guard messages.wait(for: .runningForeground, timeout: 8) else {
            XCTFail("Messages did not open")
            return nil
        }
        sleep(2)
        guard switchToGlyf() else {
            XCTFail("Glyf keyboard not up in Messages")
            return nil
        }
        return messages
    }

    /// Contacts' New Contact with its email box focused and the Glyf
    /// keyboard up: an email field, in an app that follows the system's
    /// look. The contact is never saved.
    private func newContactEmail(_ contacts: XCUIApplication) -> Bool {
        contacts.terminate()
        contacts.launch()
        host = contacts
        guard contacts.wait(for: .runningForeground, timeout: 8) else {
            XCTFail("Contacts did not open")
            return false
        }
        sleep(1)
        for word in ["Continue", "Not Now", "Get Started"] where contacts.buttons[word].exists {
            contacts.buttons[word].tap()
        }
        let add = contacts.buttons.matching(NSPredicate(
            format: "label ==[c] 'Add' OR identifier ==[c] 'Add' OR label ==[c] 'New Contact'")).firstMatch
        guard add.waitForExistence(timeout: 6) else {
            note("Contacts: \(contacts.debugDescription.prefix(4000))")
            XCTFail("no + in Contacts")
            return false
        }
        add.tap()
        let addEmail = contacts.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'add email'")).firstMatch
        guard addEmail.waitForExistence(timeout: 6) else {
            note("New Contact: \(contacts.debugDescription.prefix(4000))")
            XCTFail("no add email in New Contact")
            return false
        }
        for _ in 0..<3 where !addEmail.isHittable {
            contacts.swipeUp()
            usleep(400_000)
        }
        addEmail.tap()
        let box = contacts.textFields.matching(NSPredicate(
            format: "placeholderValue ==[c] 'Email' OR label ==[c] 'Email'")).firstMatch
        guard box.waitForExistence(timeout: 4) else {
            note("New Contact: \(contacts.debugDescription.prefix(4000))")
            XCTFail("no email box in New Contact")
            return false
        }
        field = box
        sleep(1)
        if !switchToGlyf() {
            box.tap()
            sleep(1)
            guard switchToGlyf() else {
                XCTFail("Glyf keyboard not up in Contacts")
                return false
            }
        }
        return true
    }

    /// S216: Temp mail in the g menu makes an address, types it, and shows
    /// what lands at it with its code ready to type (Arpit, 2026-09-30:
    /// "option to enter temporary mail and we will monitor its mails for
    /// next some times and show the mails gotten on it"). The panel on a
    /// light sheet (Glyf) and a dark one (Messages), with its credit to
    /// mail.tm at the foot.
    func testS216_TempMailMakesAnAddressAndShowsWhatComesIn() throws {
        useFakeMailTM()
        open()
        clear()
        addTeardownBlock { [self] in forgetTempMail() }
        XCTAssertFalse(el("toolbar:tempmail").exists, "Temp mail sits in the menu, not on the strip")
        openTempMailEmpty()
        XCTAssertFalse(el("tempmail:address").exists, "no address before Create")
        XCTAssertEqual(el("tempmail:credit").label, "via mail.tm", "mail.tm asks for a link back")
        keepScreenshot("tempmail-empty-light")
        guard let address = makeTempAddress() else { return XCTFail("no address after Create") }
        // A word, six hex digits and the stand-in's domain.
        XCTAssertNotNil(address.range(of: "^[a-z]+[0-9a-f]{6}@glyf-temp\\.example$", options: .regularExpression),
                        "the card reads '\(address)'")
        XCTAssertNotNil(wait("tempmail:empty", 3), "a new address has no mail yet")
        let watching = el("tempmail:watching").label
        XCTAssertTrue(watching.hasPrefix("Watching · 1") && watching.hasSuffix(" left"), "the line reads '\(watching)'")
        keepScreenshot("tempmail-address-light")
        tap("tempmail:insert")
        XCTAssertTrue(waitValue(3) { $0 == address }, "Insert typed '\(value)'")
        // Insert types and stays: the inbox is still being watched (Arpit,
        // 2026-10-01: "should stay here").
        sleep(1)
        XCTAssertTrue(el("tempmail:insert").exists, "Insert closed the panel")
        tap("toolbar:close")

        // A mail with a code and a link: listed, newest first, its code
        // ready to type from the row.
        clear()
        openTool("tempmail")
        XCTAssertTrue(injectMail(address, subject: "Your Acme code",
                                 text: "Your verification code is 482913. Or confirm here: https://acme.example/verify?t=s216"),
                      "the stand-in took no mail (is qa/fake-mailtm.mjs running?)")
        let landed = Date()
        guard wait("tempmail:row:0", 25) != nil else { return XCTFail("the mail did not show in the panel") }
        note(String(format: "listed %.1f s after it landed", Date().timeIntervalSince(landed)))
        XCTAssertFalse(el("tempmail:empty").exists, "No mail yet stays up beside a mail")
        let pill = el("tempmail:rowcode:0")
        XCTAssertTrue(pill.exists && pill.label.contains("482913"), "the row's code reads '\(pill.label)'")
        keepScreenshot("tempmail-inbox-light")
        pill.tap()
        XCTAssertTrue(waitValue(3) { $0 == "482913" }, "the row's Insert typed '\(value)'")
        XCTAssertTrue(el("tempmail:row:0").exists, "the row's Insert closed the panel")

        // Opened: the code big, the link, the words. The panel is still up.
        tap("toolbar:close")
        clear()
        openTool("tempmail")
        tap("tempmail:row:0", 10)
        guard let code = wait("tempmail:code", 4) else { return XCTFail("the mail did not open") }
        XCTAssertEqual(code.label, "482913")
        XCTAssertEqual(el("tempmail:subject").label, "Your Acme code")
        let from = el("tempmail:from").label
        XCTAssertTrue(from.hasPrefix("Acme · "), "the sender reads '\(from)'")
        XCTAssertTrue(el("tempmail:text").label.contains("verification code is 482913"), "the words are missing")
        XCTAssertTrue(el("tempmail:code:insert").exists && el("tempmail:code:copy").exists, "the code has no Insert or Copy")
        XCTAssertTrue(el("tempmail:credit").exists, "the credit stays at the foot of an open mail")
        keepScreenshot("tempmail-mail-light")
        tap("tempmail:link")
        XCTAssertTrue(waitValue(3) { $0 == "https://acme.example/verify?t=s216" }, "Insert link typed '\(value)'")
        XCTAssertTrue(el("tempmail:code").exists, "Insert link closed the mail")
        tap("toolbar:close")

        // The same panel on a dark sheet.
        guard darkMessages() != nil else { return }
        openTool("tempmail")
        guard wait("tempmail:row:0", 20) != nil else { return XCTFail("the dark panel lists no mail") }
        keepScreenshot("tempmail-inbox-dark")
        tap("tempmail:row:0")
        XCTAssertNotNil(wait("tempmail:code", 4), "the mail did not open on the dark sheet")
        keepScreenshot("tempmail-mail-dark")
        tap("toolbar:back")
        tap("tempmail:delete", 4)
        XCTAssertNotNil(wait("tempmail:create", 4), "Delete should bring Create back")
        keepScreenshot("tempmail-empty-dark")
        // The credit opens mail.tm in the browser.
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        addTeardownBlock { safari.terminate() }
        tap("tempmail:credit")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 8), "via mail.tm did not open the browser")
    }

    /// S217: a mail that lands while the panel is closed comes up in the
    /// strip: its code ("482913 · Acme … Insert", a tap types only the
    /// code), or with none the mail ("Mail from Nova … Open", a tap opens
    /// it). Each mail's chip shows once, and its ✕ puts it away.
    func testS217_AMailThatLandsWhileTypingComesUpInTheStrip() throws {
        useFakeMailTM()
        open()
        clear()
        addTeardownBlock { [self] in forgetTempMail() }
        openTempMailEmpty()
        guard let address = makeTempAddress() else { return XCTFail("no address after Create") }
        tap("toolbar:close")

        XCTAssertTrue(injectMail(address, subject: "Your Acme code", text: "Your verification code is 482913."),
                      "the stand-in took no mail (is qa/fake-mailtm.mjs running?)")
        var landed = Date()
        guard let chip = waitChip(30, { $0.contains("482913") }) else {
            return XCTFail("no chip for the code; the strip shows '\(el("strip:smart").label)'")
        }
        note(String(format: "code chip %.1f s after the mail landed", Date().timeIntervalSince(landed)))
        XCTAssertTrue(chip.label.contains("482913 · Acme"), "the chip reads '\(chip.label)'")
        keepScreenshot("tempmail-code-chip-light")
        chip.tap()
        XCTAssertTrue(waitValue(3) { $0 == "482913" }, "the chip typed '\(value)'")
        // Once: the next looks find it again, and say nothing.
        clear()
        sleep(10)
        XCTAssertFalse(el("strip:smart").exists && el("strip:smart").label.contains("482913"), "the code's chip came back")

        // No code: the mail itself, opened in the panel.
        XCTAssertTrue(injectMail(address, subject: "Welcome to Nova", text: "Thanks for joining Nova.",
                                 from: "Nova", fromAddress: "hello@nova.example"))
        guard let mail = waitChip(30, { $0.contains("Nova") }) else {
            return XCTFail("no chip for the mail; the strip shows '\(el("strip:smart").label)'")
        }
        XCTAssertTrue(mail.label.contains("Mail from Nova"), "the chip reads '\(mail.label)'")
        keepScreenshot("tempmail-mail-chip-light")
        mail.tap()
        guard let subject = wait("tempmail:subject", 5) else { return XCTFail("Open did not open the mail") }
        XCTAssertEqual(subject.label, "Welcome to Nova")
        XCTAssertFalse(el("tempmail:code").exists, "a mail with no code shows none")
        XCTAssertTrue(el("tempmail:text").label.contains("Thanks for joining"), "the words are missing")
        tap("toolbar:close")

        // ✕ puts a chip away, and it stays away.
        XCTAssertTrue(injectMail(address, subject: "Your Zeta code", text: "Use 771204 to sign in to Zeta.",
                                 from: "Zeta", fromAddress: "no-reply@zeta.example"))
        guard waitChip(30, { $0.contains("771204") }) != nil else {
            return XCTFail("no chip for Zeta's code; the strip shows '\(el("strip:smart").label)'")
        }
        tap("strip:smart:close")
        XCTAssertTrue(gone("strip:smart", 3), "the chip stayed after its ✕")
        sleep(10)
        XCTAssertFalse(el("strip:smart").exists && el("strip:smart").label.contains("771204"), "the put-away chip came back")
        XCTAssertEqual(value, "", "✕ typed '\(value)'")

        // A code on a dark sheet. Opening the panel starts a fresh watch.
        guard darkMessages() != nil else { return }
        openTool("tempmail")
        tap("toolbar:close")
        XCTAssertTrue(injectMail(address, subject: "Your Orbit code", text: "Your Orbit verification code is 305917.",
                                 from: "Orbit", fromAddress: "no-reply@orbit.example"))
        landed = Date()
        guard let dark = waitChip(30, { $0.contains("305917") }) else {
            return XCTFail("no chip on the dark sheet; the strip shows '\(el("strip:smart").label)'")
        }
        note(String(format: "dark code chip %.1f s after the mail landed: '%@'", Date().timeIntervalSince(landed), dark.label))
        keepScreenshot("tempmail-code-chip-dark")
        tap("strip:smart:close")
        endTempAddress()
    }

    /// S218: an email field with nothing in it offers a temp address. None
    /// live and no email saved: "Temp email … Create" makes one, types it and
    /// watches it. One live: the chip names it ("<address> … Insert") and
    /// types it again, the inbox being watched. An email saved: its chip
    /// carries "Temp" beside it, which types the live one. In Contacts' New
    /// Contact, whose email box is an email field, on a light sheet and a
    /// dark one; the contact is never saved.
    func testS218_AnEmptyEmailFieldOffersATempAddress() throws {
        let saved = "s218@example.com"
        useFakeMailTM()
        open()
        clear()
        // Saved emails are set aside for the run (kept in the vault as
        // Other, put back after), so only the one added here is offered.
        XCTAssertTrue(vaultTool(["op": "unstash"]), "the keyboard's vault tools did not answer")
        XCTAssertTrue(vaultTool(["op": "dropdetail", "value": saved]))
        XCTAssertTrue(vaultTool(["op": "stash", "kind": "email"]))
        let contacts = XCUIApplication(bundleIdentifier: "com.apple.MobileAddressBook")
        addTeardownBlock { [self] in
            XCUIDevice.shared.appearance = .light
            contacts.terminate()
            host = app
            open()
            vaultTool(["op": "dropdetail", "value": saved])
            vaultTool(["op": "unstash"])
            forgetTempMail()
        }
        endTempAddress()

        guard newContactEmail(contacts) else { return }
        // No email saved, none live: Create.
        guard let create = waitChip(6, { $0.contains("Temp email") }) else {
            return XCTFail("no Temp email chip; the strip shows '\(el("strip:smart").label)'")
        }
        XCTAssertFalse(create.label.contains("@"), "the strip offers '\(create.label)', not Create")
        keepScreenshot("tempmail-field-create-light")
        create.tap()
        XCTAssertTrue(waitValue(10) { $0.contains("@") }, "Create typed '\(value)'")
        let address = value

        for look in ["light", "dark"] {
            if look == "dark" {
                XCUIDevice.shared.appearance = .dark
                sleep(1)
            }
            // Live: named on the chip, and typed again.
            clear()
            guard let again = waitChip(6, { $0.contains(address) }) else {
                return XCTFail("\(look): the live address is not offered; the strip shows '\(el("strip:smart").label)'")
            }
            keepScreenshot("tempmail-field-live-\(look)")
            again.tap()
            XCTAssertTrue(waitValue(3) { $0 == address }, "\(look): the live chip typed '\(value)'")

            // An email saved: the chip offers it, and Temp mail beside it.
            XCTAssertTrue(vaultTool(["op": "adddetail", "kind": "email", "label": "Email", "value": saved]))
            clear()
            guard let first = wait("strip:smart:choice:0", 6) else {
                return XCTFail("\(look): the saved email is not offered; the strip shows '\(el("strip:smart").label)'")
            }
            XCTAssertEqual(first.label, saved, "\(look): the first chip")
            let temp = el("strip:smart:choice:temp")
            XCTAssertTrue(temp.exists && temp.isHittable && temp.label == "Temp mail", "\(look): beside the email sits '\(temp.label)'")
            keepScreenshot("tempmail-field-vault-\(look)")
            temp.tap()
            XCTAssertTrue(waitValue(3) { $0 == address }, "\(look): Temp typed '\(value)'")
            XCTAssertTrue(vaultTool(["op": "dropdetail", "value": saved]))
        }

        // The address ended, on the dark sheet: Create again.
        endTempAddress()
        clear()
        guard let createDark = waitChip(6, { $0.contains("Temp email") }) else {
            return XCTFail("dark: no Temp email chip; the strip shows '\(el("strip:smart").label)'")
        }
        XCTAssertFalse(createDark.label.contains("@"), "dark: the strip offers '\(createDark.label)', not Create")
        keepScreenshot("tempmail-field-create-dark")
    }

    // MARK: - Clipboard

    func testS72_CopiedTextShowsInClipboardAndPastes() throws {
        UIPasteboard.general.string = "Flight AI 2021 lands at 6:40, gate 12"
        open()
        clear()
        openTool("clipboard")
        // iOS hands a keyboard the copy only after Allow Paste, so the newest
        // copy is offered as its own card on top.
        guard let fresh = wait("clip:fresh", 5) else { return XCTFail("the new copy is not offered") }
        fresh.tap()
        allowPasteIfAsked()
        XCTAssertTrue(waitValue(4) { $0.contains("AI 2021") }, "got '\(value)'")
        // From now on it lives in the clipboard history.
        clear()
        openTool("clipboard")
        let saved = host.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'clip:card' AND label CONTAINS 'AI 2021'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 3), "the pasted copy should be kept in the clipboard")
        note("pasted '\(value)'")
    }

    func testS73_ScreenshotsShowInClipboard() throws {
        open(["--glyf-screenshots-on"])
        openTool("clipboard")
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

    func testS102_EmoticonsTypeStraightIntoTheField() throws {
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
    func testS103_GIFTabShowsGIFsAndCopiesOne() throws {
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

    func testS104_StickerTabShowsStickersAndCopiesOne() throws {
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

    func testS105_GIFSearchShowsResultsForTheWord() throws {
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

    /// A row in the calendar's day list whose words include `text`.
    /// The event Add just made: earlier runs leave events with the same
    /// name, and the new one says "Just added" until the list is redrawn.
    private func eventRow(_ text: String) -> XCUIElement {
        host.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'calendar:event:' AND label CONTAINS %@ AND value == 'Just added'", text)).firstMatch
    }

    func testS109_NewEventFromTheKeyboardCalendar() throws {
        open()
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        tap("calendar:new", 6)
        tap("event:title", 4)
        type("lunch with sam tomorrow 1pm")
        let hint = el("event:hint").label
        tap("key:return")
        let starts = el("event:starts:time").label
        XCTAssertTrue(starts.contains("1:00"), "starts at '\(starts)', read '\(hint)'")
        // Share in chat off: this one is for the list.
        tap("event:share", 3)
        tap("event:add")
        // Back on that day, the new event in the list, read from the calendar itself.
        let row = eventRow("Lunch with sam")
        XCTAssertTrue(row.waitForExistence(timeout: 6), "the new event isn't in the day's list")
        note("added '\(row.label)'; the title strip read '\(hint)'")
        row.tap()
        XCTAssertTrue(waitValue(4) { $0.contains("Lunch with sam") }, "got '\(value)'")
    }

    func testS110_APlanInAMessageOffersAddToCalendar() throws {
        open()
        clear()
        type("dinner friday 8pm")
        guard let chip = wait("strip:smart", 4) else { return XCTFail("no chip for a plan") }
        let label = chip.label
        XCTAssertTrue(label.contains("Dinner") && label.contains("8:00"), "chip says '\(label)'")
        chip.tap()
        XCTAssertNotNil(wait("event:add", 4), "New Event didn't open")
        let starts = el("event:starts:time").label
        XCTAssertTrue(starts.contains("8:00"), "starts at '\(starts)'")
        tap("event:add")
        // Added, the event goes into the message after the plan (Arpit,
        // 2026-10-01: "creating a calendar event should also send ... in chat
        // with calendar details"); without Google there is no call link.
        XCTAssertTrue(waitValue(8) { $0.lowercased().hasPrefix("dinner friday 8pm") && $0.contains("📅 Dinner") },
                      "got '\(value)'")
        note("chip '\(label)'; message '\(value)'")
    }

    func testS113_CallLinkAndBookATime() throws {
        resetGoogle()
        open(["--glyf-booking-link", "cal.com/rick", "--glyf-test-google", Self.fakeGoogle])
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        // A Google Meet link, straight into the message.
        tap("calendar:call", 6)
        XCTAssertTrue(waitValue(8) { $0.contains("Join me on a call: https://meet.google.com/") }, "got '\(value)'")
        let call = value
        // No clear() here: its tap lands inside a link this long (the field
        // shows the start of it), and the rest of the link would trail the
        // next insert. The time goes in after the call link instead.
        c.press(forDuration: 0.7)
        tap("calendar:book", 6)
        // Rick's open times on Cal.com, live; a day with none steps on.
        var slot = wait("booking:slot:0", 12)
        for _ in 0..<5 where slot == nil {
            tap("booking:next", 2)
            slot = wait("booking:slot:0", 10)
        }
        guard let slot else { return XCTFail("no open time; the sheet says '\(el("booking:status").label)'") }
        let time = slot.label
        slot.tap()
        // Who it's for comes up first; this one just sends the time instead.
        XCTAssertNotNil(wait("booking:who:field", 4), "no who field")
        tap("key:return")
        tap("booking:link", 4)
        XCTAssertTrue(waitValue(4) { $0.hasPrefix(call + " How about ") && $0.contains("Book it here: https://") && $0.contains("slot=") }, "got '\(value)'")
        note("call '\(call)'; sent \(time): '\(value)'")
    }

    /// Clears what the stand-in booked and mailed, so a run can book again.
    private func resetFake() {
        guard let url = URL(string: "http://127.0.0.1:8796/_reset") else { return }
        _ = try? Data(contentsOf: url)
    }

    /// What the stand-in Cal.com and Resend (qa/fake-scheduling.mjs) recorded.
    private func fakeLog() -> [String: Any] {
        guard let url = URL(string: "http://127.0.0.1:8796/_log"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    func testS115_BookATimeForSomeoneWithAGuest() throws {
        resetFake()
        open(["--glyf-booking-link", "cal.com/fake-host/30min"])
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        tap("calendar:book", 6)
        var slot = wait("booking:slot:0", 10)
        for _ in 0..<3 where slot == nil {
            tap("booking:next", 2)
            slot = wait("booking:slot:0", 8)
        }
        guard let slot else { return XCTFail("no open time; the sheet says '\(el("booking:status").label)'") }
        slot.tap()
        XCTAssertNotNil(wait("booking:who:field", 4), "no who field")
        type("sam lee sam@example.com ria@example.com")
        let hint = el("booking:who:hint").label
        tap("key:return")
        tap("booking:book", 4)
        XCTAssertTrue(waitValue(10) { $0.contains("Booked for") && $0.contains("sam@example.com") }, "got '\(value)'")
        let bookings = fakeLog()["bookings"] as? [[String: Any]] ?? []
        let last = bookings.last ?? [:]
        let attendee = last["attendee"] as? [String: Any] ?? [:]
        XCTAssertEqual(attendee["email"] as? String, "sam@example.com")
        XCTAssertEqual((attendee["name"] as? String)?.lowercased(), "sam lee")
        XCTAssertEqual(last["guests"] as? [String], ["ria@example.com"])
        note("hint '\(hint)'; message '\(value)'")
    }

    // MARK: Google Calendar and Meet (qa/fake-google.mjs on 8797)

    private static let fakeGoogle = "http://127.0.0.1:8797"

    private func resetGoogle() {
        guard let url = URL(string: "\(Self.fakeGoogle)/_reset") else { return }
        _ = try? Data(contentsOf: url)
    }

    /// What the stand-in Google recorded: Meet links made, events added.
    private func googleLog() -> [String: Any] {
        guard let url = URL(string: "\(Self.fakeGoogle)/_log"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    func testS121_MeetLinkFromTheCalendar() throws {
        resetGoogle()
        open(["--glyf-test-google", Self.fakeGoogle])
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        tap("calendar:call", 6)
        XCTAssertTrue(waitValue(8) { $0.contains("Join me on a call: https://meet.google.com/") }, "got '\(value)'")
        let made = (googleLog()["spaces"] as? [[String: Any]])?.count ?? 0
        XCTAssertEqual(made, 1, "Meet links made")
        note("message '\(value)'")
    }

    func testS122_NewEventWithAGuestGoesToGoogleCalendar() throws {
        resetGoogle()
        open(["--glyf-test-google", Self.fakeGoogle])
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        tap("calendar:new", 6)
        tap("event:title", 4)
        type("review friday 3pm")
        tap("key:return")
        tap("event:invitees", 4)
        type("sam@example.com")
        tap("key:return")
        // Video call is on from the start with Google connected.
        XCTAssertEqual(el("event:video").value as? String, "1", "Video call starts off")
        tap("event:add")
        // Share in chat is on from +: the event lands in the message too.
        XCTAssertTrue(waitValue(10) { $0.contains("Review") && $0.contains("https://meet.google.com/") }, "got '\(value)'")
        let events = googleLog()["events"] as? [[String: Any]] ?? []
        let last = events.last ?? [:]
        let body = last["body"] as? [String: Any] ?? [:]
        let query = last["query"] as? [String: String] ?? [:]
        XCTAssertEqual((body["attendees"] as? [[String: String]])?.map { $0["email"] }, ["sam@example.com"])
        XCTAssertEqual(query["sendUpdates"], "all", "Google emails the guest")
        XCTAssertNotNil((body["conferenceData"] as? [String: Any])?["createRequest"], "a Meet call was asked for")
        let guests = (body["attendees"] as? [[String: String]])?.compactMap { $0["email"] }.joined(separator: ", ") ?? ""
        note("event '\(body["summary"] ?? "")' for \(guests), sendUpdates=\(query["sendUpdates"] ?? ""); message '\(value)'")
    }

    func testS123_WithoutGoogleNewEventGoesInTheMessage() throws {
        open()
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        // Call links are Google Meet only: without Google nothing goes in.
        tap("calendar:call", 6)
        sleep(2)
        XCTAssertEqual(value, "", "a call link went in without Google")
        tap("calendar:new", 6)
        guard wait("event:title", 4) != nil else { return XCTFail("New Event didn't open") }
        XCTAssertFalse(el("event:invitees").exists, "Invitees shows only with Google Calendar")
        XCTAssertFalse(el("event:video").exists, "Video call is a Google Meet call: only with Google")
        tap("event:title", 4)
        type("lunch with sam tomorrow 1pm")
        tap("key:return")
        tap("event:add")
        XCTAssertTrue(waitValue(8) { $0.contains("📅 Lunch with sam") }, "got '\(value)'")
        note("message '\(value)'")
    }

    func testS124_AKeyHeldForAMeetLink() throws {
        resetGoogle()
        open(["--glyf-test-google", Self.fakeGoogle, "--glyf-bind", "m=connector:meet"])
        clear()
        guard let m = wait("key:m", 3) else { return XCTFail("no M key") }
        m.press(forDuration: 0.8)
        let sent = waitValue(8) { $0.contains("Join me on a call: https://meet.google.com/") }
        let message = value
        // M goes back to typing M.
        open(["--glyf-bind", "m="])
        XCTAssertTrue(sent, "got '\(message)'")
        note("message '\(message)'")
    }

    func testS135_ACalendarNeverAskedForPointsToConnectedTools() throws {
        // Run with the calendar never asked for (`simctl privacy reset
        // calendar`), as after "Not now" in onboarding: Settings has no
        // Calendars switch for Glyf until the app has asked once.
        open()
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        let hint = host.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Connected tools")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 6), "the calendar doesn't say where to turn it on")
        note("calendar says '\(hint.label)'")
        keepScreenshot("calendar-never-asked")
    }

    func testS136_ConnectedToolsTurnsOnCalendarAndGoogleMeetLater() throws {
        // Straight after S135: the calendar still never asked for, and Google
        // Meet connected through the stand-in, as whom it says.
        resetGoogle()
        app.launchArguments = ["--glyf-skip-onboarding", "--glyf-test-signed-in",
                               "--glyf-test-google", Self.fakeGoogle]
        app.launch()
        guard let profile = wait("tab:profile", 10) else { return XCTFail("no Profile tab") }
        sleep(2)
        profile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Connected tools")).firstMatch
        for _ in 0..<4 where !(row.exists && row.isHittable) {
            app.swipeUp()
            usleep(600_000)
        }
        guard row.waitForExistence(timeout: 4) else { return XCTFail("no Connected tools on Profile") }
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        guard let meet = wait("tools:google", 8) else { return XCTFail("no Google Meet in Connected tools") }
        // Each card reads as one label: its title, then the account or the pitch.
        func card(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        XCTAssertTrue(card("sim@example.com").waitForExistence(timeout: 3),
                      "Google Meet doesn't show the connected account")
        XCTAssertEqual("\(meet.value ?? "")", "1", "Google Meet's switch should be on")
        guard let calendar = wait("tools:calendar", 3) else { return XCTFail("no Calendar in Connected tools") }
        XCTAssertTrue(calendar.label.contains("Turn on"), "calendar reads '\(calendar.label)'")
        note("before: calendar '\(calendar.label)', meet switch \(meet.value ?? "?")")

        // The phone's own question, answered yes.
        calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        var asked = ""
        for host in [springboard, app] where host.alerts.firstMatch.waitForExistence(timeout: 5) {
            let alert = host.alerts.firstMatch
            asked = alert.label
            let allow = alert.buttons["Allow Full Access"]
            (allow.exists ? allow : alert.buttons.element(boundBy: alert.buttons.count - 1)).tap()
            break
        }
        XCTAssertFalse(asked.isEmpty, "turning Calendar on didn't ask the phone")
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, el("tools:calendar").label != "On" { usleep(300_000) }
        XCTAssertEqual(el("tools:calendar").label, "On", "Calendar didn't turn on")
        keepScreenshot("tools-on")

        // Off takes the grant back.
        meet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pitch = card("Send a Meet link")
        XCTAssertTrue(pitch.waitForExistence(timeout: 5), "Google Meet didn't turn off")
        XCTAssertFalse(card("sim@example.com").exists, "the account is still shown")
        XCTAssertEqual("\(el("tools:google").value ?? "")", "0", "Google Meet's switch should be off")
        keepScreenshot("tools-meet-off")

        // On again opens Google's own page. The test stops at the phone's
        // "wants to use google.com" and cancels: never a real account.
        el("tools:google").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        var sheet = ""
        for host in [springboard, app] where host.alerts.firstMatch.waitForExistence(timeout: 8) {
            let alert = host.alerts.firstMatch
            sheet = alert.label
            let cancel = alert.buttons["Cancel"]
            (cancel.exists ? cancel : alert.buttons.element(boundBy: 0)).tap()
            break
        }
        XCTAssertTrue(sheet.contains("google.com"), "Connect didn't open Google's sign-in (saw '\(sheet)')")
        XCTAssertTrue(pitch.waitForExistence(timeout: 4), "a cancelled Connect should leave Google Meet off")
        note("calendar asked '\(asked)'; connect asked '\(sheet)'")
    }

    func testS114_NewEventWithAMeetCallOnThePhone() throws {
        // Meet granted, Calendar unticked: the event is the phone's own, with
        // a Google Meet link of the person's.
        resetGoogle()
        open(["--glyf-test-google", Self.fakeGoogle, "--glyf-test-google-scopes", "meet"])
        clear()
        guard let c = wait("key:c", 3) else { return XCTFail("no C key") }
        c.press(forDuration: 0.7)
        tap("calendar:new", 6)
        tap("event:title", 4)
        type("sync tomorrow 4pm")
        tap("key:return")
        XCTAssertFalse(el("event:invitees").exists, "Invitees shows only with Google Calendar")
        guard let video = wait("event:video", 4) else { return XCTFail("no Video call row") }
        // On from the start whenever a call link can be made.
        XCTAssertEqual(video.value as? String, "1", "Video call starts off")
        // Share in chat off: this one is looked for in the day's list.
        tap("event:share", 3)
        tap("event:add")
        let row = eventRow("Sync")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the event isn't in the day's list")
        let label = row.label
        XCTAssertTrue(label.contains("https://meet.google.com/"), "the event has no Meet link: '\(label)'")
        row.tap()
        XCTAssertTrue(waitValue(4) { $0.contains("Sync") && $0.contains("https://meet.google.com/") }, "got '\(value)'")
        note("event '\(label)'")
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
        openTool("translate")
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
        openTool("translate")
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
        openTool("search")
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

    // MARK: - Games

    /// g menu → Games, scrolling the grid to the tile the way a thumb would.
    private func openGames() -> Bool {
        tap("toolbar:glyf")
        guard let first = menuTile() else { return false }
        let tile = el("shell:tile:games")
        for _ in 0..<4 where !(tile.exists && tile.isHittable) {
            first.swipeUp()
            usleep(400_000)
        }
        guard tile.exists else { return false }
        tile.tap()
        return wait("games:snake", 3) != nil
    }

    private var boardState: String { (el("games:board").value as? String) ?? "" }

    func testS131_SnakeFromTheMenuTurnsWithASwipe() throws {
        open()
        XCTAssertTrue(openGames(), "g menu → Games shows the games")
        keepScreenshot("games-picker")
        tap("games:snake")
        guard let board = wait("games:board", 3) else { return XCTFail("no board") }
        XCTAssertTrue(boardState.hasPrefix("ready"), "waits for a swipe: \(boardState)")
        board.swipeUp()
        sleep(1)
        note("after a swipe up: \(boardState)")
        XCTAssertTrue(boardState.contains("playing"), boardState)
        XCTAssertTrue(boardState.contains("heading up"), boardState)
        keepScreenshot("snake")
        board.tap()
        XCTAssertTrue(boardState.hasPrefix("paused"), "a tap pauses: \(boardState)")
        tap("toolbar:close")
        XCTAssertNotNil(wait("key:a", 3), "closing the game brings the letters back")
    }

    func testS132_ChompEatsItsWayAlong() throws {
        open()
        XCTAssertTrue(openGames(), "g menu → Games shows the games")
        tap("games:chomp")
        guard let board = wait("games:board", 3) else { return XCTFail("no board") }
        XCTAssertTrue(boardState.contains("lives 3"), boardState)
        board.tap()
        sleep(2)
        note("two seconds in: \(boardState)")
        let score = Int(boardState.components(separatedBy: "score ").last?.prefix { $0.isNumber } ?? "") ?? 0
        XCTAssertGreaterThan(score, 0, "Chomp eats the pellets in its way")
        board.swipeDown()
        sleep(1)
        keepScreenshot("chomp")
        tap("games:back")
        XCTAssertNotNil(wait("games:chomp", 3), "back goes to the games")
        tap("toolbar:close")
    }

    // MARK: - The brand key

    /// The strip starts with Glyf's own key, as on Android: the app icon's
    /// mark in a pill, black with the g white on a light sheet and white with
    /// the icon's black g on a dark one, the violet dot where the icon has it.
    func testS129_TheStripStartsWithGlyfsKey() throws {
        open()
        guard let key = wait("toolbar:glyf", 3) else { return XCTFail("no Glyf key on the strip") }
        let light = keycapColors(key)
        keepScreenshot("strip-light")
        note(String(format: "light sheet: face %.2f, dot rgb %.0f %.0f %.0f", light.face, light.dot.r, light.dot.g, light.dot.b))
        XCTAssertGreaterThan(light.face, 0.85, "on a light sheet the key is the icon's white")
        XCTAssertTrue(light.violet, "the dot is Glyf violet")
        key.tap()
        XCTAssertNotNil(menuTile(), "the key opens the Glyf menu")
        tap("toolbar:close")

        // Messages follows the system, so it shows the key on a dark sheet.
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        host = messages
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light; messages.terminate() }
        XCUIDevice.shared.system.open(URL(string: "sms:+15555648583&body=hi")!)
        XCTAssertTrue(messages.wait(for: .runningForeground, timeout: 8))
        sleep(2)
        if !switchToGlyf() { return XCTFail("Glyf keyboard not up in Messages") }
        guard let darkKey = wait("toolbar:glyf", 3) else { return XCTFail("no Glyf key on the dark strip") }
        let dark = keycapColors(darkKey)
        keepScreenshot("strip-dark")
        note(String(format: "dark sheet: face %.2f, dot rgb %.0f %.0f %.0f", dark.face, dark.dot.r, dark.dot.g, dark.dot.b))
        XCTAssertLessThan(dark.face, 0.15, "on a dark sheet the key is the icon's dark twin")
        XCTAssertTrue(dark.violet, "the dot is Glyf violet on a dark sheet")
    }

    /// The key's face beside its letter, and the middle of its dot. The key
    /// sits 15pt inside its button (the tools' padding plus a symbol's air)
    /// and, 41 by 30 on iOS 26, stands on the strip's top edge with the
    /// button; the dot is where the icon has it (GlyfMark.Keycap).
    private func keycapColors(_ button: XCUIElement) -> (face: CGFloat, dot: (r: CGFloat, g: CGFloat, b: CGFloat), violet: Bool) {
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return (1, (0, 0, 0), false) }
        let scale = CGFloat(cg.width) / shot.size.width
        let bpp = cg.bitsPerPixel / 8
        func rgb(_ p: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            let i = Int(p.y * scale) * cg.bytesPerRow + Int(p.x * scale) * bpp
            return (CGFloat(bytes[i]), CGFloat(bytes[i + 1]), CGFloat(bytes[i + 2]))
        }
        let f = button.frame
        // The 30pt key stands centred in the button, which is as tall as the
        // strip's box (44pt since the chips grew, 2026-09-30).
        let keyX = f.minX + 15, keyTop = f.minY + max(0, (f.height - 30) / 2)
        let face = rgb(CGPoint(x: keyX + 5, y: keyTop + 15))
        let h = (30 - 30 * 0.083 * 2) / 1.6565
        let letterX = 41 / 2 - h * 0.6699 / 2, letterY = 15 - h * 1.6565 / 2 + h * 0.6565
        let dot = rgb(CGPoint(x: keyX + letterX + h * 1.0379, y: keyTop + letterY - h * 0.4927))
        let lum = (0.299 * face.r + 0.587 * face.g + 0.114 * face.b) / 255
        let violet = dot.b > 200 && dot.r > 80 && dot.r < 175 && dot.g < 140
        return (lum, dot, violet)
    }

    private func keepScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = name
        add(shot)
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

    /// S188: an iPhone on its side. The keys take Apple's shorter rows, so
    /// the page keeps room above them, and stay clear of the rounded corners
    /// and the Dynamic Island. In Safari's address bar: Glyf's own app stays
    /// upright, and Messages' new-message sheet does not turn.
    func testS188_SidewaysTheKeysLeaveRoomAndClearTheIsland() throws {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        host = safari
        defer { XCUIDevice.shared.orientation = .portrait; safari.terminate() }
        XCUIDevice.shared.orientation = .portrait
        safari.launch()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 8))
        sleep(2)
        // The address bar: by name where it has one, else the bar along the foot.
        let address = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@ OR label IN %@",
                                  ["TabBarItemTitle", "URL", "Address"], ["Address", "Search or enter website name"]))
            .firstMatch
        if address.waitForExistence(timeout: 4) { address.tap() }
        else { safari.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap() }
        sleep(1)
        if !switchToGlyf() { return XCTFail("Glyf keyboard not up in Safari") }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        note("device orientation \(XCUIDevice.shared.orientation.rawValue)")
        let screen = safari.windows.firstMatch.frame
        guard let g = wait("toolbar:glyf", 4), let q = wait("key:q", 2), let p = wait("key:p", 2)
        else { return XCTFail("the keyboard is gone on its side") }
        keepScreenshot("sideways")
        // A simulator run without Simulator.app reports the new orientation
        // but never turns the apps (Xcode 27): nothing here can be measured.
        if screen.width <= screen.height {
            throw XCTSkip("the device turned (\(XCUIDevice.shared.orientation.rawValue)) but the app did not: headless simulator")
        }
        let share = (screen.maxY - g.frame.minY) / screen.height
        note(String(format: "screen %.0fx%.0f; strip top %.0f (%.0f%% of the height); q x %.0f, p right %.0f, q %.0fx%.0f",
                    screen.width, screen.height, g.frame.minY, share * 100, q.frame.minX,
                    p.frame.maxX, q.frame.width, q.frame.height))
        XCTAssertLessThan(share, 0.6, "on its side the keyboard covers most of the screen")
        XCTAssertGreaterThan(q.frame.minX - screen.minX, 40, "Q sits under the corner or the island")
        XCTAssertGreaterThan(screen.maxX - p.frame.maxX, 40, "P sits under the corner")
        XCTAssertGreaterThanOrEqual(q.frame.height, 28, "keys this short are hard to hit")
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
        let tools = Self.tools.filter { el("toolbar:\($0)").exists }
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
