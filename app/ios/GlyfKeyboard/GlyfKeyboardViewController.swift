import UIKit
import os.log

/// iOS grants keyboard extensions arbitrary (often cached, oversized) heights
/// and ignores height constraints — an Apple-acknowledged issue with no
/// sanctioned fix. This root makes the granted size irrelevant: the real
/// keyboard is BOTTOM-ANCHORED at exactly its designed height, everything
/// above is transparent, and touches up there fall through to the host app.
/// Keystroke timing, for the latency work. A keyboard has to answer a key
/// inside a frame or it reads as lag — Fleksy measures ~19ms a key, the next
/// one out ~31ms, so anything over ~16ms of our own work is a problem.
/// Numbers go to the console: `log stream --predicate 'category == "perf"'`.
enum Perf {
    /// Flip off before shipping; the reads themselves are nearly free but
    /// the log line is not worth paying for in someone's pocket.
    static let on = false
    private static let log = Logger(subsystem: "so.glyf.keyboard", category: "perf")

    @inline(__always) static func mark() -> CFAbsoluteTime {
        on ? CFAbsoluteTimeGetCurrent() : 0
    }

    /// Milliseconds since `start`, to one decimal.
    @inline(__always) static func ms(_ start: CFAbsoluteTime) -> Double {
        ((CFAbsoluteTimeGetCurrent() - start) * 1000 * 10).rounded() / 10
    }

    static func say(_ what: String) {
        guard on else { return }
        log.log("GLYF_PERF \(what, privacy: .public)")
    }

    /// How many times this event reached across into the host app. Free on
    /// the simulator, the dominant cost on a phone — so it is counted rather
    /// than timed, and the count is what to keep down.
    nonisolated(unsafe) private static var hostReads = 0

    @inline(__always) static func countHostRead() {
        if on { hostReads += 1 }
    }

    static func reportHostReads() {
        guard on else { return }
        log.log("GLYF_PERF hostReads=\(hostReads, privacy: .public)")
        hostReads = 0
    }
}

final class PassThroughRoot: UIView {
    var contentHeight: CGFloat = 260

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if point.y < bounds.height - contentHeight { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Composition root for the Glyf keyboard (M1+M2).
/// One blur backdrop for the whole surface (§5.2), toolbar + key grid,
/// and three overlay surfaces: GlyfShell (§6.3), GlyfBar (§6.4), EmojiBoard.
/// The keyboard NEVER holds provider keys and never signs (§1.5/§1.6).
final class GlyfKeyboardViewController: UIInputViewController {

    private let log = Logger(subsystem: "so.glyf.keyboard", category: "lifecycle")
    private static var appearances = 0

    // Surfaces
    /// Autolayout content root: iOS derives the keyboard's height from what
    /// it can MEASURE. Manual-frame children give it nothing, so this view is
    /// pinned to all edges and carries the required height constraint — the
    /// system then adopts exactly totalHeight. (Manual frames continue inside.)
    private let content = UIView()
    private var backdrop: UIView!
    private let toolbar = GlyfToolbar()
    private let keyboardView = KeyboardView()
    private var shell: GlyfShell?
    private var bar: GlyfBar?
    /// Hold space on typed text → act on it (ActSurface, POST /act).
    private var act: ActSurface?
    /// A recent copy waiting above the toolbar (Acti's copied-context card).
    private var clipStrip: ClipContextStrip?
    private var actTask: URLSessionDataTask?
    private var actInput: (before: String, after: String)?
    /// Set when a bound letter's skill is running in the act surface.
    private var actSkill: (glyfId: String, letter: String?)?
    /// A bar run's own name (the prompt itself) and its vars.
    private var actSkillTitle: String?
    private var actVars: [String: String] = [:]
    /// What a suggestion chip promised to do; nil lets the server decide.
    private var actIntent: String?
    /// The text the run reads (field text, or the clipboard for a skill).
    private var actRunInput = ""
    private var actHasResult = false
    private var actAccepted = false
    /// Free models answer late or not at all a few times an hour. One run
    /// gets one quiet second try before the person is told anything.
    private var actRetryBudget = 0
    private var emoji: EmojiBoard?
    /// Gboard's clipboard: its own header, pinned and recent as card columns.
    private var clipboardPanel: ClipboardPanel?
    /// g menu → Games: Snake and Chomp over the key area.
    private var games: GamesSurface?
    private var pay: PaySurface?
    /// What the pay strip opens with (set right before setSurface(.pay)).
    private var pendingPay: PaySurface.Intent?
    private var connector: ConnectorSurface?
    /// The Calendar tool: a month and the chosen day's events.
    private var calendarView: CalendarSurface?
    private var search: SearchSurface?
    private var noteEdit: NoteEditSurface?
    /// What the editor strip opens on (set right before setSurface(.noteEdit)).
    private var pendingEdit: NoteEditSurface.Edit?
    /// §6.13 T — persistent strip above the toolbar while enabled.
    private var hud: TranslationHUD?
    /// §6.13 R — transient overlay over the keys, not a Surface.
    private var tonesPopup: TonesPopup?
    /// §6.15: did the user act on the bar's result (Replace/Insert/Copy)?
    /// Text around the cursor, mirrored for the length of a space-bar glide.
    private var cursorMirror: CursorMirror?
    private var lastCursorAdjust: CFTimeInterval = 0

    private enum Surface: Equatable { case none, shell, bar, emoji, connector(String), search, noteEdit, act, clipboard, games, pay }
    private var surface: Surface = .none

    /// When set, key input routes into an inline editor (bar prompt / emoji search).
    private weak var inlineTarget: InlineEditor?

    // Typing: suggestions, autocorrect, next word, learning (Engine/Typing)
    private var typing: TypingEngine? { TypingStore.shared.engine }
    private struct Correction {
        let original: String
        let replacement: String
        /// Engine corrections teach on undo; shorthand expansions don't.
        let fromEngine: Bool
        /// What came before the caret right after the correction and its
        /// space went in. Undo works from exactly there: anything written,
        /// deleted or moved to since leaves the correction behind.
        var anchor: String? = nil
    }
    private var lastCorrection: Correction?

    /// Engine corrections of the last few minutes. Going back into one and
    /// typing the original again is a "no": the word stays as typed and is
    /// learned (user, 2026-09-29: "cutee" became "cute", was deleted and
    /// typed again, and became "cute" every time). A typo typed twice
    /// ("teh") is still fixed: its correction was never gone back into.
    private struct RecentFix {
        let original: String
        let replacement: String
        let at: Date
        var touched = false
    }
    private var recentFixes: [RecentFix] = []

    /// The last correction, while the caret is still right after it and its
    /// space. Otherwise a backspace that later reaches the same word in other
    /// text ("free" in a pasted line) would swap it back.
    private func undoableCorrection(before: String?) -> Correction? {
        guard let corr = lastCorrection, let anchor = corr.anchor, let before,
              before == anchor, before.hasSuffix(corr.replacement + " ") else { return nil }
        return corr
    }
    /// Where each letter of the word being typed was touched.
    private var wordTouches: [(Float, Float)?] = []
    private var wordTouchesFor = ""
    private var lastSpaceTap: Date = .distantPast

    private var heightConstraint: NSLayoutConstraint?
    private var viewHeightConstraint: NSLayoutConstraint?
    private var didBuild = false
    var deliveryInFlight = false
    var deliveryRetries = 0

    // MARK: Heights

    private var keysHeight: CGFloat {
        // An iPhone on its side gets the shorter rows Apple's keyboard has
        // there: portrait's rows left the app about 100 of its 402pt.
        if traitCollection.verticalSizeClass == .compact {
            let numberRow = SettingsStore.current.numberRow && !keyboardView.context.isPad
            return Glass.sidewaysKeysHeight + (numberRow ? Glass.sidewaysNumberRowExtra : 0)
        }
        // The key region is the system keyboard's own, which is taller on
        // Plus/Max-class phones — never a number baked in for one device.
        let w = view.bounds.width > 0 ? view.bounds.width
                                      : UIScreen.main.bounds.width
        let base = Glass.keysHeight(width: w)
        // A digit pad is Apple's four rows whatever the number-row setting.
        let numberRow = SettingsStore.current.numberRow && !keyboardView.context.isPad
        return numberRow ? base + Glass.numberRowExtra : base
    }

    /// §6.13 T: the Translation HUD adds a 44pt strip while enabled — never
    /// in secure fields (§11.9), never under another surface.
    private var hudActive: Bool {
        SettingsStore.current.translationHUD == true && !isSecureField
    }

    private var totalHeight: CGFloat {
        let base = Glass.toolbarHeight + keysHeight
        switch surface {
        // Translate takes the strip's place rather than adding a row over it.
        case .none:
            return base
        case .emoji:
            // Searching collapses the board to a strip ABOVE the letter
            // keys, so the surface needs room for both.
            // Apple's emoji keyboard stands a little taller than its letters,
            // so its five rows get the same 39pt they have there.
            return base + (emoji?.searchActive == true ? EmojiBoard.searchStripHeight : EmojiBoard.extraHeight)
        // Panels take the key area instead of growing the keyboard, exactly
        // like the website: the keys never move, so muscle memory holds.
        // Ask Glyf keeps the keys live under it; its chips row adds height.
        case .bar:
            return base + (bar?.extraHeight ?? 0)
        // While typing a query the keys stay live under a strip; results
        // become a panel over the keys. The same height either way, so the
        // keyboard never jumps while you search.
        case .search:
            return base + SearchSurface.extraHeight
        // The note's strip takes the toolbar's place (it is hidden), so
        // the keys keep their own height instead of stretching.
        case .noteEdit: return base + NoteEditSurface.stripHeight - Glass.toolbarHeight
        // Paying is a panel over the keys; typing the amount collapses it
        // to a strip with the digits below, like a New Event title.
        case .pay where pay?.editingAmount == true: return base + PaySurface.editStripHeight
        // A New Event title being typed: its strip rides over the keys, like
        // emoji search.
        case .connector where calendarView?.editingTitle == true:
            return base + EventComposer.editStripHeight
        case .shell, .connector, .act, .clipboard, .games, .pay: return base
        }
    }

    // MARK: Lifecycle

    override func loadView() {
        view = PassThroughRoot()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        log.log("GLYF_KB viewDidLoad")
        // The settings file changed under us (the app's Keyboard screen, the
        // tour, our own shell): whichever check noticed, the keyboard that is
        // up takes the new look, bindings and appearance. Deferred a turn so
        // a rebuild never lands inside the caller that did the noticing.
        NotificationCenter.default.addObserver(
            forName: SettingsStore.changedNote, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.settingsChanged() }
        }
        // What a UIPasteControl is allowed to hand us. Without this the
        // control stays disabled however much is on the clipboard.
        let paste = UIPasteConfiguration(forAccepting: NSString.self)
        paste.addTypeIdentifiers(forAccepting: UIImage.self)
        pasteConfiguration = paste
        // A mail at the temp address, while it is watched: the strip offers
        // its code, or the mail. Notices are the server's own words.
        TempMailWatcher.shared.onNewMail = { [weak self] mail in
            guard let self else { return }
            self.mailChip = (.tempMail(id: mail.id, from: mail.from, code: mail.code), Date())
            self.updateCandidates()
        }
        TempMailWatcher.shared.onNotice = { [weak self] text in
            guard let self else { return }
            KeyboardToast.show(in: self.content, text: text)
        }
        NotificationCenter.default.addObserver(forName: TempMailWatcher.changed, object: nil,
                                               queue: .main) { [weak self] _ in
            // The address ended: its mail's chip goes with it.
            guard let self, self.mailChip != nil, TempMailWatcher.shared.state == nil else { return }
            self.mailChip = nil
            self.updateCandidates()
        }
    }

    /// Where every system paste button in the keyboard lands.
    override func paste(itemProviders: [NSItemProvider]) {
        acceptPasted(itemProviders)
    }

    /// The keyboard type the traits were last read for, so a focus moving
    /// between fields (Safari's next arrow) is noticed without resetting the
    /// page on every keystroke.
    private var lastKeyboardType: UIKeyboardType?

    /// What the field says about its keys: a return key that names its
    /// action, and WebKit's number fields (numbers-and-punctuation), which
    /// Apple's keyboard opens on the 123 page. A new field starts on the
    /// letters, the way the system keyboard does.
    private func adoptFieldTraits(fresh: Bool) {
        let type = textDocumentProxy.keyboardType
        keyboardView.returnFace = Self.returnFace(for: textDocumentProxy.returnKeyType)
        // Apple greys the key while a field that enables it automatically is
        // empty. Drawn only: the proxy's view of the text can lag, and a
        // return that does nothing would be worse than one drawn a shade off.
        keyboardView.returnEnabled = textDocumentProxy.enablesReturnKeyAutomatically != true
            || textDocumentProxy.hasText
        guard fresh || type != lastKeyboardType else { return }
        lastKeyboardType = type
        keyboardView.setMode(type == .numbersAndPunctuation ? .symbols1 : .letters)
    }

    /// Apple's return key for each action, measured on the iOS 26.5
    /// simulator (web fields with each enterkeyhint, Safari's address bar)
    /// and on an iPhone 16 Pro: go, search, send and done are blue with a
    /// white glyph, next is a chevron, plain return is the ⏎ glyph. Symbol
    /// sizes are matched to Apple's ink (go 17.3 x 14pt, search 18 x 18.3,
    /// send 14 x 17.3, done 16 x 15.7, next 6.7 x 16). The rest were not
    /// measured and keep their word.
    static func returnFace(for type: UIReturnKeyType?) -> ReturnFace {
        switch type {
        case .go:
            return ReturnFace(symbol: "arrow.right", pointSize: 18.5, weight: .medium, primary: true)
        case .search, .google, .yahoo:
            return ReturnFace(symbol: "magnifyingglass", pointSize: 19, weight: .light, primary: true)
        case .send:
            return ReturnFace(symbol: "arrow.up", pointSize: 18.5, weight: .medium, primary: true)
        case .done:
            return ReturnFace(symbol: "checkmark", pointSize: 18.5, weight: .medium, primary: true)
        case .next:
            return ReturnFace(symbol: "chevron.right", pointSize: 19, weight: .light)
        case .join: return ReturnFace(text: "join")
        case .route: return ReturnFace(text: "route")
        case .continue: return ReturnFace(text: "continue")
        case .emergencyCall: return ReturnFace(text: "call")
        default: return .plain
        }
    }

    /// Apple behavior: the keyboard follows the HOST (field appearance /
    /// system style). A forced light or dark is not offered on the iPhone
    /// any more: iOS draws the band above the keyboard and the globe bar
    /// below it in the host's colour, so a board forced the other way looked
    /// cut off between them (user, 2026-09-27). A choice saved before is
    /// ignored.
    private func resolveAppearance() {
        let pref = "auto"
        // The host's keyboardAppearance is resolved once, when the field
        // takes focus: Messages opened in dark mode keeps reporting .dark
        // after the phone switches to light. The trait (which the system
        // sheet follows) does change, so after a live flip it wins.
        // The host's appearance is the trait ABOVE our view: our own
        // override (set a few lines down) reaches our view and everything
        // in it, and reading it back here would make a forced dark look
        // like a dark host, dropping the sheet we paint for the difference.
        if let above = view.superview?.traitCollection {
            hostTraitDark = above.userInterfaceStyle == .dark
        } else if overrideUserInterfaceStyle == .unspecified {
            hostTraitDark = traitCollection.userInterfaceStyle == .dark
        }
        let traitDark = hostTraitDark
        let hostDark = appearanceFlipped
            ? traitDark
            : textDocumentProxy.keyboardAppearance == .dark || traitDark
        let dark = pref == "dark" || (pref == "auto" && hostDark)
        let theme = SettingsStore.current.keyTheme ?? "glass"
        // Painted boards (the colour and gradient themes) are retired for
        // now: iOS draws its own band above every keyboard that nothing can
        // paint, so a coloured board looked cut off under it. One picked
        // before stays in settings and is ignored (user, 2026-09-27).
        let bg = ""
        let borders = SettingsStore.current.keyBorders ?? false
        let dim = SettingsStore.current.themeBrightness ?? 0
        overrideUserInterfaceStyle =
            pref == "light" ? .light : pref == "dark" ? .dark : .unspecified
        // iOS draws the sheet for the HOST's appearance whatever we say, so a
        // forced light or dark that disagrees with it paints its own sheet;
        // in auto the host's sheet is right and nothing is painted.
        forcedSheet = (pref != "auto" && dark != hostDark) ? Glass.sheetPaint(dark: dark) : nil
        backdrop?.backgroundColor = forcedSheet ?? .clear
        if Glass.isDark != dark || Glass.keyTheme != theme
            || Glass.themeBg != bg || Glass.keyBorders != borders
            || Glass.themeDim != dim {
            Glass.isDark = dark
            Glass.keyTheme = theme
            Glass.themeBg = bg
            Glass.keyBorders = borders
            Glass.themeDim = dim
            refreshPalette()
        }
    }

    /// A look, appearance or binding changed on disk: apply what differs
    /// (both calls are no-ops when nothing did).
    private func settingsChanged() {
        guard didBuild else { return }
        keyboardView.refreshBindings()
        resolveAppearance()
    }

    /// Re-skins the long-lived chrome after an appearance flip; transient
    /// surfaces pick the palette up on their next open.
    private func refreshPalette() {
        guard didBuild else { return }
        toolbar.applyPalette()
        keyboardView.rebuild()
        applyBoardPaint()
        emoji?.applyPalette()
    }

    /// The painted board of a colour or gradient theme.
    private var boardLayer: CAGradientLayer?

    /// A colour or gradient theme paints the board the tiles in the app
    /// promise (Gboard's themes do the same); with none, the system's own
    /// sheet shows through, or the forced one when the person overrode the
    /// host's appearance.
    private func applyBoardPaint() {
        guard let backdrop else { return }
        let colors = Glass.boardColors
        guard !colors.isEmpty else {
            boardLayer?.removeFromSuperlayer()
            boardLayer = nil
            backdrop.backgroundColor = forcedSheet ?? .clear
            return
        }
        let layer = boardLayer ?? CAGradientLayer()
        layer.frame = backdrop.bounds
        layer.colors = (colors.count == 1 ? [colors[0], colors[0]] : colors).map(\.cgColor)
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        if boardLayer == nil { backdrop.layer.insertSublayer(layer, at: 0) }
        boardLayer = layer
        backdrop.backgroundColor = .clear
    }

    /// Set once light/dark changes while the keyboard is up; cleared when it
    /// goes away, so the next field's own appearance is read fresh.
    private var appearanceFlipped = false

    /// The last appearance the host handed down (see resolveAppearance).
    private var hostTraitDark = false

    /// The sheet we paint when the person forces an appearance the host does
    /// not have; nil (transparent) whenever the host's own sheet is right.
    private var forcedSheet: UIColor?

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // Turned on its side, or back: the rows change height with it.
        if didBuild, previous?.verticalSizeClass != traitCollection.verticalSizeClass {
            applySurfaceLayout(animated: false)
        }
        guard let before = previous?.userInterfaceStyle,
              before != traitCollection.userInterfaceStyle else { return }
        if before != .unspecified { appearanceFlipped = true }
        resolveAppearance()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SettingsStore.invalidate()
        recentFixes = []   // another field: its corrections are not these
        // The translate strip belongs to the session it was opened in. Left
        // persisted it greets the next app as an unexplained empty band.
        if SettingsStore.current.translationHUD == true {
            SettingsStore.update { $0.translationHUD = false }
            hud?.removeFromSuperview()
            hud = nil
        }
        VaultStore.shared.invalidate() // the app may have edited the vault
        resolveAppearance() // BEFORE building — tokens feed every surface
        if !didBuild {
            didBuild = true
            build()
            toolbar.applyPalette()
        }
        if heightConstraint == nil {
            let c = content.heightAnchor.constraint(equalToConstant: totalHeight)
            c.priority = .required
            c.isActive = true
            heightConstraint = c
        }
        // Best-effort: ask nicely for the exact height too (999 — if iOS
        // adopts it there is zero dead zone; if not, bottom-anchoring wins).
        if viewHeightConstraint == nil {
            let v = view.heightAnchor.constraint(equalToConstant: totalHeight)
            v.priority = UILayoutPriority(999)
            v.isActive = true
            viewHeightConstraint = v
        }
#if DEBUG
        startDebugTapWatch()
#endif
        keyboardView.needsGlobe = needsInputModeSwitchKey
        // A keyboard coming back for a field starts on the letters: a menu,
        // clipboard or answer panel left open last time would greet the next
        // field with something it never asked for.
        if didBuild, surface != .none { setSurface(.none, animated: false) }
        keyboardView.context = KeyboardContext(keyboardType: textDocumentProxy.keyboardType)
        log.log("GLYF_KB ctx autocap=\(self.textDocumentProxy.autocapitalizationType?.rawValue ?? -1) kbType=\(self.textDocumentProxy.keyboardType?.rawValue ?? -1)")
        adoptFieldTraits(fresh: true)
        keyboardView.rebuild()
        keyboardView.refreshBindings()
        toolbar.reloadItems()
        hud?.refreshTarget() // the app may have changed the target language
        refreshClipStrip(animated: false)
        applySurfaceLayout(animated: false)
        syncAutoShift()
        wordTouches = []
        wordTouchesFor = ""
        TypingStore.shared.prepare(
            hasFullAccess: hasFullAccess,
            lexicon: { [weak self] done in self?.requestSupplementaryLexicon(completion: done) },
            ready: { [weak self] _ in self?.updateCandidates() })
    }

#if DEBUG
    private var debugTapTimer: Timer?
    private var lastDebugTapSeq = -1

    /// Watches the App Group for a point to tap, so gap coordinates can be
    /// driven from the command line during testing. DEBUG only.
    private func startDebugTapWatch() {
        debugTapTimer?.invalidate()
        debugTapTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.runDebugVaultTool()
            guard let d = AppGroupStore.readJSON(name: "debug-tap.json"),
                  let seq = d["seq"] as? Int, seq != self.lastDebugTapSeq,
                  let x = d["x"] as? Double, let y = d["y"] as? Double else { return }
            self.lastDebugTapSeq = seq
            // Consume it: a left-behind point replays on every appearance.
            AppGroupStore.writeJSON(["seq": seq, "done": true], name: "debug-tap.json")
            self.keyboardView.debugTap(at: CGPoint(x: x, y: y))
        }
    }

    /// The label a detail set aside by "stash" carries (Android's twin).
    private static let stashed = "qa-stash:"

    /// Scenario tools on the vault, from debug-vault.json (DEBUG only, the
    /// twin of Android's stash, unstash, dropdetail and snippet). "stash"
    /// sets every detail of one kind aside, so the email a scenario adds from
    /// the keys is the one offered; they stay in the vault as Other under a
    /// marked label, so a crash in between loses nothing. "unstash" puts them
    /// back; "dropdetail" removes the detail a scenario added, by its value;
    /// "adddetail" saves one (a kind, a label, a value) without the keys;
    /// "snippet" keeps ";qa=See you" or lets ";qa=" go.
    private func runDebugVaultTool() {
        guard let d = AppGroupStore.readJSON(name: "debug-vault.json"),
              d["done"] as? Bool != true, let op = d["op"] as? String else { return }
        AppGroupStore.writeJSON(["done": true], name: "debug-vault.json")
        let store = VaultStore.shared
        store.invalidate()
        if op == "snippet" {
            let pair = (d["text"] as? String ?? "").split(separator: "=", maxSplits: 1,
                                                          omittingEmptySubsequences: false)
            guard pair.count == 2 else { return }
            if pair[1].isEmpty {
                store.deleteSnippet(trigger: String(pair[0]))
            } else {
                _ = store.upsertSnippet(trigger: String(pair[0]), text: String(pair[1]))
            }
            return
        }
        if op == "adddetail" {
            _ = store.upsertField(id: nil, kind: d["kind"] as? String ?? "custom",
                                  label: d["label"] as? String ?? "", value: d["value"] as? String ?? "")
            return
        }
        for f in store.load().fields {
            switch op {
            case "stash" where f.kind == d["kind"] as? String:
                _ = store.upsertField(id: f.id, kind: "custom",
                                      label: "\(Self.stashed)\(f.kind):\(f.label)", value: f.value)
            case "unstash" where f.label.hasPrefix(Self.stashed):
                let parts = f.label.dropFirst(Self.stashed.count).split(separator: ":", maxSplits: 1,
                                                                         omittingEmptySubsequences: false)
                _ = store.upsertField(id: f.id, kind: String(parts.first ?? "custom"),
                                      label: parts.count > 1 ? String(parts[1]) : "", value: f.value)
            case "dropdetail" where f.value == d["value"] as? String:
                store.deleteField(id: f.id)
            default:
                break
            }
        }
    }
#endif

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
#if DEBUG
        debugTapTimer?.invalidate()
        debugTapTimer = nil
#endif
        appearanceFlipped = false
        stopTourWatch()
        // A chip's colours stop turning with the keyboard away.
        toolbar.setMagicRunning(false)
        TempMailWatcher.shared.setVisible(false)
        TypingStore.shared.saveNow()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        toolbar.setMagicRunning(true)
        TempMailWatcher.shared.fullAccess = hasFullAccess
        TempMailWatcher.shared.setVisible(true)
        Self.appearances += 1
        log.log("GLYF_KB height=\(self.view.bounds.height) target=\(self.totalHeight)")
        let mb = MemoryLogger.logAppearance(Self.appearances)
        AppGroupStore.writeKeyboardPing(
            appearance: Self.appearances, footprintMB: mb, hasFullAccess: hasFullAccess)
        ClipboardStore.fullAccessHint = hasFullAccess && !isSecureField
        if hasFullAccess, !isSecureField {
            // Nothing reads the pasteboard here on purpose: a read the person
            // did not ask for raises Apple's "Allow Paste" alert every single
            // time. The copied-text strip offers a Paste button instead (a
            // system UIPasteControl, no alert), and that is what fills
            // history. The Clipboard screen reads too, since opening it is
            // the ask.
            BackendClient.shared.fetchRemaining { [weak self] n in
                self?.toolbar.setRunsRemaining(n)
            }
        }
        toolbar.setRunsRemaining(GlyfCatalog.cachedRunsRemaining())
        showPayOutcomeIfFresh()
        startTourWatch()
        // Host input sessions (Flutter especially) finish attaching a beat
        // AFTER viewDidAppear — inserting immediately loses the text.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.deliverPendingResult()
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layoutSurfaces()
        if let boardLayer, boardLayer.frame != backdrop.bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            boardLayer.frame = backdrop.bounds
            CATransaction.commit()
        }
    }

    private func build() {
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            // Within the safe area: on its side an iPhone's corners and
            // Dynamic Island would cover the outermost keys (Apple's keys
            // stop short of them too). Portrait has no side insets.
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            // Bottom-anchored; the top edge floats — dead space stays clear.
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // No board of our own: iOS draws the keyboard sheet behind every
        // third-party keyboard and its margins cannot be painted, so a board
        // inside it only shows up as a second, mismatched band. The keys sit
        // on the system's sheet, in every theme (see Glass: keys on the sheet).
        backdrop = UIView()
        backdrop.backgroundColor = forcedSheet ?? .clear
        backdrop.isUserInteractionEnabled = false
        backdrop.frame = content.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.addSubview(backdrop)

        toolbar.delegate = self
        content.addSubview(toolbar)

        keyboardView.delegate = self
        keyboardView.clipsToBounds = false
        content.addSubview(keyboardView)
        applyBoardPaint()
    }

    // MARK: Surface layout

    /// Panels sit in the key area: the strip stays put and the keys are
    /// covered, so the keyboard never changes height (website behaviour).
    private func panelRect(_ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: 0, y: Glass.toolbarHeight, width: w,
               height: max(0, h - Glass.toolbarHeight))
    }

    /// Strip contents while a panel is open: icon + name, close on the left.
    private func panelHeader() -> (String?, String?) {
        switch surface {
        case .shell:
            let title = shell?.headerTitle ?? "Glyf"
            return (title == "Glyf" ? "square.grid.2x2" : nil, title)
        // (The g menu keeps the tools on the strip: see keepTools below.)
        case .emoji where emoji?.searchActive != true: return ("face.smiling", "Emoji")
        case .act: return ("sparkles", "Glyf")
        case .games: return ("gamecontroller", "Games")
        case .pay where pay?.editingAmount != true:
            return ("dollarsign.circle", pay?.headerTitle ?? "Pay")
        case .connector where connector?.searchActive != true: return ("calendar", "Calendar")
        default: return (nil, nil)
        }
    }

    /// The model's read on what is being typed, and the work in flight.
    private var suggestTask: URLSessionDataTask?
    private var suggestWork: DispatchWorkItem?

    /// Suggestions and the smart strip are recomputed once typing settles,
    /// never inside the keystroke itself. At speed the old way put the
    /// engine, two dozen regexes and a strip rebuild between one finger
    /// going down and the next — long enough to lose the tap. Every key
    /// schedules this instead, so a burst collapses into a single pass.
    private var candidatesWork: DispatchWorkItem?
    /// When the settings file was last stat'ed (textDidChange throttles it).
    private var lastSettingsCheck: CFTimeInterval = 0
    /// Slices of the last suggestion pass, for Perf.
    private var tChip: Double = 0
    private var tEngine: Double = 0
    private var tStrip: Double = 0
    /// The clipboard offer, and when it was last worked out.
    private var lastClipProbe: CFTimeInterval = 0
    private var cachedPaste: String?

    /// Whether to offer what was copied. Measured at 14-20ms a call: the
    /// probe is a cross-process read of UIPasteboard plus two App Group
    /// files, and it used to run on every keystroke with an empty field.
    /// Nobody's clipboard changes while they are typing, so it is worked
    /// out once a second and remembered in between.
    private func pasteOffer(tailEmpty: Bool) -> String? {
        guard hasFullAccess, tailEmpty else { return nil }
        let now = CACurrentMediaTime()
        guard now - lastClipProbe > 1.0 else { return cachedPaste }
        lastClipProbe = now
        // History only knows a copy once it has been read; a newer one shows
        // as an offer instead of the older text.
        if ClipboardStore.pasteboardHasNewContent() { nameTheCopy() }
        cachedPaste = ClipContext.isFresh()
            ? (ClipboardStore.load().first?.text ?? "Tap to paste what you copied")
            : nil
        return cachedPaste
    }

    /// Which copy we have already asked iOS to name, so a chip that cannot be
    /// named is not re-asked on every probe.
    private var namedCopy = -1

    /// Puts the new copy into history so the chip can show the WORDS rather
    /// than an offer to paste something unnamed.
    ///
    /// Does nothing at all unless "Capture everything you copy" is on. There
    /// is no quiet way in: `detectValues` names a link or a number, but
    /// handing over the value IS a read and iOS raises "Allow Paste?" for it
    /// exactly as it does for the whole string. Only `detectPatterns`, which
    /// answers with types and no values, stays silent, and a type is not
    /// something a chip can show. So the offer to Paste is the default route
    /// — the tap is the permission — and this is the opt-in one.
    private func nameTheCopy() {
        let cc = UIPasteboard.general.changeCount
        guard namedCopy != cc else { return }
        namedCopy = cc
        ClipboardStore.captureNewCopy { [weak self] added in
            guard added, let self else { return }
            self.cachedPaste = nil
            self.lastClipProbe = 0
            self.updateCandidates()
        }
    }

    private func scheduleCandidates() {
        candidatesWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.candidatesWork = nil
            self.updateCandidates()
        }
        candidatesWork = work
        // Short enough to feel immediate when the fingers stop, long enough
        // that a fast run of keys only pays for it once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }
    private var suggestedFor = ""
    /// The text a chip was dismissed on with its ✕: no chip comes back for it
    /// until the text changes (Arpit, 2026-09-30: "add some button to
    /// dismiss it").
    private var dismissedTail: String?
    /// A mail that landed at the temp address, and when: offered in the
    /// strip until it is used, put away or five minutes old (a code goes
    /// stale), and never again (each mail's chip shows once).
    private var mailChip: (chip: Smart.Chip, at: Date)?
    private var suggestedChip: Smart.Chip?
    /// What Glyf itself just wrote into the field (a rewrite, an answer).
    /// Offering to tidy that up would be asking about its own work.
    private var glyfWrote = ""

    /// The tool being dragged onto or around the strip, and its ghost.
    private var draggingToolId: String?
    private var dragGhost: UIImageView?

    /// The g menu itself is open (its root grid), so the strip keeps showing
    /// the tools — that is the thing a tile gets dragged onto.
    private var shellAtMenu: Bool {
        surface == .shell && shell?.canGoBack == false
    }

    private var lastPanelTitle: String??

    private func layoutSurfaces() {
        defer { applyTourHint() }
        let w = content.bounds.width
        let h = content.bounds.height
        let header = panelHeader()
        if lastPanelTitle != .some(header.1) {
            lastPanelTitle = .some(header.1)
            toolbar.showPanelHeader(icon: header.0, title: header.1,
                                    canGoBack: shell?.canGoBack == true,
                                    keepTools: shellAtMenu)
        }
        let showHUD = surface == .none && hudActive
        hud?.isHidden = !showHUD
        switch surface {
        case .none:
            let y: CGFloat = 0
            if showHUD {
                ensureHUD().frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            }
            toolbar.isHidden = showHUD
            toolbar.frame = CGRect(x: 0, y: y, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = false
            keyboardView.alpha = 1
            keyboardView.frame = CGRect(x: 0, y: y + Glass.toolbarHeight, width: w,
                                        height: max(0, h - y - Glass.toolbarHeight))
            tonesPopup?.frame = keyboardView.frame
        case .emoji:
            toolbar.isHidden = false
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            if emoji?.searchActive == true {
                // Strip + letter keys (Apple's emoji-search behavior).
                keyboardView.isHidden = false
                emoji?.frame = CGRect(x: 0, y: Glass.toolbarHeight, width: w,
                                      height: EmojiBoard.searchStripHeight)
                let keysY = Glass.toolbarHeight + EmojiBoard.searchStripHeight
                keyboardView.frame = CGRect(x: 0, y: keysY, width: w,
                                            height: max(0, h - keysY))
            } else {
                // The board is the whole keyboard, search field where the
                // strip was, the way Apple's emoji keyboard is.
                toolbar.isHidden = true
                keyboardView.isHidden = true
                emoji?.frame = CGRect(x: 0, y: 0, width: w, height: h)
            }
        case .shell:
            toolbar.isHidden = false
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = true
            shell?.frame = panelRect(w, h)
        case .connector where calendarView?.editingTitle == true:
            toolbar.isHidden = false
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = false
            calendarView?.frame = CGRect(x: 0, y: Glass.toolbarHeight, width: w,
                                         height: EventComposer.editStripHeight)
            let keysY = Glass.toolbarHeight + EventComposer.editStripHeight
            keyboardView.frame = CGRect(x: 0, y: keysY, width: w, height: max(0, h - keysY))
        case .pay where pay?.editingAmount == true:
            toolbar.isHidden = false
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = false
            pay?.frame = CGRect(x: 0, y: Glass.toolbarHeight, width: w,
                                height: PaySurface.editStripHeight)
            let payKeysY = Glass.toolbarHeight + PaySurface.editStripHeight
            keyboardView.frame = CGRect(x: 0, y: payKeysY, width: w, height: max(0, h - payKeysY))
        case .pay:
            toolbar.isHidden = false
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = true
            pay?.frame = panelRect(w, h)
        case .connector:
            toolbar.isHidden = connector?.searchActive == true
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            if connector?.searchActive == true {
                keyboardView.isHidden = false
                connector?.frame = CGRect(x: 0, y: 0, width: w,
                                          height: ConnectorSurface.searchStripHeight)
                keyboardView.frame = CGRect(
                    x: 0, y: ConnectorSurface.searchStripHeight, width: w,
                    height: max(0, h - ConnectorSurface.searchStripHeight))
            } else {
                keyboardView.isHidden = true
                connector?.frame = panelRect(w, h)
                calendarView?.frame = panelRect(w, h)
            }
        case .noteEdit:
            toolbar.isHidden = true
            keyboardView.isHidden = false
            noteEdit?.frame = CGRect(x: 0, y: 0, width: w,
                                     height: NoteEditSurface.stripHeight)
            keyboardView.frame = CGRect(x: 0, y: NoteEditSurface.stripHeight,
                                        width: w,
                                        height: max(0, h - NoteEditSurface.stripHeight))
        case .search:
            // Search is the one surface that takes over the strip as well:
            // its own tabs and query field ARE the strip (website 6.1).
            toolbar.isHidden = true
            if let sv = search {
                if sv.expandedForResults {
                    keyboardView.isHidden = true
                    sv.frame = CGRect(x: 0, y: 0, width: w, height: h)
                } else {
                    // Collapsed and landing differ only in how much room the
                    // strip takes; the keys stay visible in both, so you can
                    // start typing straight over a suggestion.
                    keyboardView.isHidden = false
                    let stripH = SearchSurface.stripHeight
                    sv.frame = CGRect(x: 0, y: 0, width: w, height: stripH)
                    keyboardView.frame = CGRect(x: 0, y: stripH, width: w,
                                                height: max(0, h - stripH))
                }
            }
        case .act:
            toolbar.isHidden = false
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = true
            act?.frame = panelRect(w, h)
        case .games:
            toolbar.isHidden = false
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = true
            games?.frame = panelRect(w, h)
        case .clipboard:
            // Gboard's clipboard owns the whole keyboard, strip included.
            toolbar.isHidden = true
            keyboardView.isHidden = true
            clipboardPanel?.frame = CGRect(x: 0, y: 0, width: w, height: h)
        case .bar:
            // The bar is the strip (and its chips row); the keys type into it.
            toolbar.isHidden = true
            keyboardView.isHidden = false
            if let bar {
                let barH = Glass.toolbarHeight + bar.extraHeight
                bar.frame = CGRect(x: 0, y: 0, width: w, height: barH)
                keyboardView.frame = CGRect(x: 0, y: barH, width: w,
                                            height: max(0, h - barH))
            }
        }
    }

    private func applySurfaceLayout(animated: Bool) {
        heightConstraint?.constant = totalHeight
        viewHeightConstraint?.constant = totalHeight
        (view as? PassThroughRoot)?.contentHeight = totalHeight
        let work = {
            self.layoutSurfaces()
            // Entrances fade in inside the same spring; the growing height
            // provides the rise itself.
            for overlay in [self.shell, self.bar, self.emoji, self.connector,
                            self.search, self.noteEdit, self.hud, self.calendarView,
                            self.tonesPopup, self.act, self.clipStrip,
                            self.clipboardPanel, self.games, self.pay] as [UIView?] {
                overlay?.alpha = 1
            }
            self.view.layoutIfNeeded()
        }
        if animated && !Glass.reduceMotion {
            // One soft spring for every surface change — nothing snaps
            // (§5.2), but QUICK: Apple's surface moves land in ~0.3s.
            let spring = UIViewPropertyAnimator(duration: 0.30, dampingRatio: 0.9,
                                                animations: work)
            spring.startAnimation()
        } else {
            work()
        }
    }

    /// Prepares a freshly-added overlay to rise into place (§5.3: surfaces
    /// RISE, they don't pop) — the spring fades it in while the keyboard
    /// height grows underneath it.
    private func prepareEntrance(_ v: UIView, animated: Bool) {
        guard animated, !Glass.reduceMotion else { return }
        v.alpha = 0
    }

    private func setSurface(_ new: Surface, animated: Bool = true) {
        guard surface != new else { return }
        dismissTonesPopup()
        // Tear down the old overlay — pop = discard data (§6.3).
        switch surface {
        case .shell:
            shell?.removeFromSuperview(); shell = nil
            TempMailWatcher.shared.panelOpen = false
        case .bar: bar?.removeFromSuperview(); bar = nil
        case .emoji: emoji?.removeFromSuperview(); emoji = nil
        case .connector:
            connector?.removeFromSuperview(); connector = nil
            calendarView?.removeFromSuperview(); calendarView = nil
        case .search: search?.cancelWork(); search?.removeFromSuperview(); search = nil
        case .noteEdit:
            // A phone number was typed on the digits: the letters come back.
            if noteEdit?.wantsDigits == true { keyboardView.setMode(.letters) }
            noteEdit?.removeFromSuperview(); noteEdit = nil
        case .act:
            actTask?.cancel(); actTask = nil
            act?.removeFromSuperview(); act = nil
        case .clipboard: clipboardPanel?.removeFromSuperview(); clipboardPanel = nil
        case .games: games?.stop(); games?.removeFromSuperview(); games = nil
        case .pay:
            pay?.removeFromSuperview(); pay = nil
            keyboardView.setMode(.letters)
        case .none: break
        }
        inlineTarget = nil
        surface = new
        // A suggestion is about the sentence in the field; once a panel is
        // open it is about something else, so it leaves the strip.
        if new != .none { toolbar.showSmart(nil) }
        switch new {
        case .shell:
            let s = GlyfShell()
            s.delegate = self
            content.addSubview(s)
            prepareEntrance(s, animated: animated)
            shell = s
        case .bar:
            let b = GlyfBar()
            b.delegate = self
            content.addSubview(b)
            prepareEntrance(b, animated: animated)
            bar = b
        case .emoji:
            let e = EmojiBoard()
            e.delegate = self
            content.addSubview(e)
            prepareEntrance(e, animated: animated)
            emoji = e
            MemoryLogger.logSurface("emoji")
        case .clipboard:
            let c = ClipboardPanel()
            c.delegate = self
            c.pasteTarget = self
            content.addSubview(c)
            prepareEntrance(c, animated: animated)
            clipboardPanel = c
            MemoryLogger.logSurface("clipboard")
        case .connector(let id) where id == "calendar" || id == "mockcal":
            let c = CalendarSurface(hasFullAccess: hasFullAccess)
            c.delegate = self
            content.addSubview(c)
            prepareEntrance(c, animated: animated)
            calendarView = c
        case .connector(let id):
            let c = ConnectorSurface(connectorId: id)
            c.delegate = self
            content.addSubview(c)
            prepareEntrance(c, animated: animated)
            connector = c
        case .search:
            let sv = SearchSurface(hasFullAccess: hasFullAccess)
            sv.delegate = self
            content.addSubview(sv)
            prepareEntrance(sv, animated: animated)
            search = sv
            inlineTarget = sv.queryEditor
            sv.queryEditor.isActive = true
            // A search starts in lowercase, as Apple's and Gboard's do,
            // whatever capital the message field was about to get.
            keyboardView.syncAutoShift(wantsCapital: false)
            // Open on recents + trending rather than an empty box (Gboard).
            sv.presentLanding()
        case .noteEdit:
            let n = NoteEditSurface(edit: pendingEdit ?? .note(id: nil, text: ""))
            pendingEdit = nil
            n.delegate = self
            content.addSubview(n)
            prepareEntrance(n, animated: animated)
            noteEdit = n
            if n.wantsDigits { keyboardView.setMode(.symbols1) }
            n.activate(n.activeEditor)
        case .act:
            let a = ActSurface()
            a.delegate = self
            content.addSubview(a)
            prepareEntrance(a, animated: animated)
            act = a
        case .games:
            let g = GamesSurface()
            content.addSubview(g)
            prepareEntrance(g, animated: animated)
            games = g
            MemoryLogger.logSurface("games")
        case .pay:
            let p = PaySurface(intent: pendingPay ?? .send(to: nil, amount: nil, token: nil))
            pendingPay = nil
            p.delegate = self
            content.addSubview(p)
            prepareEntrance(p, animated: animated)
            pay = p
            MemoryLogger.logSurface("pay")
        case .none:
            break
        }
        applySurfaceLayout(animated: animated)
    }

    // MARK: Translation HUD (§6.13 T)

    private func ensureHUD() -> TranslationHUD {
        if let hud { return hud }
        let h = TranslationHUD()
        h.delegate = self
        content.addSubview(h)
        hud = h
        return h
    }

    /// Word-commit hook: hand the current draft to the HUD (debounced there).
    private func notifyHUD() {
        guard surface == .none, hudActive else { return }
        let before = beforeContext ?? ""
        ensureHUD().draftChanged(before)
    }

    // MARK: Tones popup (§6.13 R)

    /// A payment finished while the keyboard was away (the app wrote how
    /// it went into shared settings): said once, back in the chat.
    private func showPayOutcomeIfFresh() {
        _ = SettingsStore.reloadIfChanged()
        guard let raw = SettingsStore.current.walletOutcome, !raw.isEmpty else { return }
        SettingsStore.update { $0.walletOutcome = nil }
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = obj["title"] as? String else { return }
        let at = obj["at"] as? Double ?? 0
        guard Date().timeIntervalSince1970 - at < 5 * 60 else { return }
        let detail = obj["detail"] as? String
        KeyboardToast.show(in: content, text: detail.map { "\(title) · \($0)" } ?? title)
    }

    private func showTonesPopup() {
        guard surface == .none, !isSecureField else { return }
        dismissTonesPopup()
        let p = TonesPopup()
        p.delegate = self
        p.frame = keyboardView.frame
        p.autoresizingMask = [.flexibleWidth]
        content.addSubview(p)
        tonesPopup = p
        if !Glass.reduceMotion {
            p.alpha = 0
            p.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.9) {
                p.alpha = 1
                p.transform = .identity
            }.startAnimation()
        }
    }

    private func dismissTonesPopup() {
        tonesPopup?.removeFromSuperview()
        tonesPopup = nil
    }

    // MARK: Text context

    private var isSecureField: Bool {
        textDocumentProxy.isSecureTextEntry ?? false
    }

    // MARK: The host round trip

    /// `documentContextBeforeInput` reaches across into the host app. On a
    /// phone that crossing is the most expensive thing a keystroke does — and
    /// it is invisible on the simulator, where the host is in the same
    /// process and the same read costs 0.0ms. A single keystroke used to make
    /// that crossing a dozen times over, once per place that wanted to know
    /// what came before the caret.
    ///
    /// Within one event the answer cannot change, so it is read once and kept
    /// until the document actually moves. Every edit we make goes through
    /// `hostInsert`/`hostDelete`/`hostAdjust`, and anything the HOST changes
    /// arrives as textDidChange or selectionDidChange — all of which drop it.
    private var cachedBefore: String??

    var beforeContext: String? {
        if let cachedBefore { return cachedBefore }
        let value = textDocumentProxy.documentContextBeforeInput
        cachedBefore = .some(value)
        Perf.countHostRead()
        return value
    }

    /// Forgets the cached context. Cheap, and the safe thing to do whenever
    /// there is any doubt — a stale answer here edits the wrong text.
    func forgetBefore() { cachedBefore = nil }

    func hostInsert(_ text: String) {
        textDocumentProxy.insertText(text)
        forgetBefore()
    }

    func hostDelete() {
        textDocumentProxy.deleteBackward()
        forgetBefore()
    }

    func hostAdjust(byCharacterOffset offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        forgetBefore()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        forgetBefore()
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        super.selectionWillChange(textInput)
        forgetBefore()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let t0 = Perf.mark()
        forgetBefore() // the document moved — whoever moved it
        Perf.reportHostReads()
        // The app may have changed settings while we are up (its tour does),
        // but that is a stat of a file on disk and this runs on EVERY
        // keystroke — a few times a second is as often as it can matter.
        if CACurrentMediaTime() - lastSettingsCheck > 0.5 {
            lastSettingsCheck = CACurrentMediaTime()
            SettingsStore.reloadIfChanged() // settingsChanged() does the rest
        }
        // Field flavor can change per focus (email → number pad → text).
        keyboardView.context = KeyboardContext(keyboardType: textDocumentProxy.keyboardType)
        adoptFieldTraits(fresh: false)
        syncAutoShift()
        // Scheduled, not immediate: this fires after our own insert too, so
        // running the engine and the strip here undid the coalescing that
        // kbInsert was careful to do.
        scheduleCandidates()
        Perf.say("textDidChange=\(Perf.ms(t0))ms")
        // Secure-field entry/exit changes whether the HUD may show (§11.9).
        if surface == .none, heightConstraint?.constant != totalHeight {
            applySurfaceLayout(animated: false)
        }
        notifyHUD()
        // Fires when the REAL input session (re)attaches — retry delivery.
        deliverPendingResult()
        applyTourHint()
    }

    // MARK: Tour coach

    /// The website's coach, on the real keyboard: while the app's tour waits
    /// on a step, a pulsing ring around the one thing to tap and a label
    /// saying what to do with it (TourCoach decides both).
    private var tourRing: CAShapeLayer?
    private var tourLabel: TourLabelView?
    private var tourTimer: Timer?
    private var tourTyping = false
    /// What the keyboard already typed for the tour, so it types it once.
    private var tourTyped: String?

    private var tourCopied: Bool {
        (SettingsStore.current.tourCopiedAt ?? 0) > (Date().timeIntervalSince1970 - 10 * 60) * 1000
    }

    private var tourStep: String? {
        let s = SettingsStore.current
        let fresh = (s.tourHintAt ?? 0) > (Date().timeIntervalSince1970 - 15 * 60) * 1000
        return fresh ? s.tourStep : nil
    }

    /// The app moves the tour along without touching the text, so the
    /// keyboard looks again a few times a second while it is up.
    private func startTourWatch() {
        tourTimer?.invalidate()
        // A few times a second while a tour is coaching; otherwise only
        // often enough to notice one starting. Each tick is a stat of the
        // settings file, and the idle keyboard used to do it 13 times a
        // second across the App Group.
        let interval: TimeInterval = tourStep != nil ? 0.4 : 2.0
        tourTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.applyTourHint()
            let wanted: TimeInterval = self.tourStep != nil ? 0.4 : 2.0
            if self.tourTimer?.timeInterval != wanted { self.startTourWatch() }
        }
    }

    private func stopTourWatch() {
        tourTimer?.invalidate()
        tourTimer = nil
        clearTourCoach()
    }

    /// The step (and copy) the strip was last arranged for.
    private var coachedStep: String?

    private func applyTourHint() {
        SettingsStore.reloadIfChanged()
        let arranged = tourStep.map { "\($0)|\(tourCopied)" }
        if didBuild, arranged != coachedStep {
            // A new chat in the tour starts clean: a panel the previous one
            // left open (its search results, say) would sit over the keys.
            let chat = tourStep?.split(separator: ":").first.map(String.init)
            let previous = coachedStep?.split(separator: ":").first.map(String.init)
            if let chat, let previous, chat != previous, surface != .none {
                setSurface(.none)
                applySurfaceLayout(animated: true)
            }
            // A new step, or the address just copied, changes which chips
            // the strip may show. The copy is looked at NOW, not when the
            // pasteboard probe's throttle next allows it: the tour's Pay chip
            // used to wait for the next keystroke.
            coachedStep = arranged
            lastClipProbe = 0
            cachedPaste = nil
            updateCandidates()
            return
        }
        guard didBuild, let step = tourStep else {
            clearTourCoach()
            return
        }
        let state = tourState(step: step)
        tourAutotype(state)
        guard let coach = TourCoach.coach(state), let rect = coachRect(coach.target) else {
            clearTourCoach()
            return
        }
        showTourCoach(rect: rect, label: coach.label)
    }

    private func tourState(step: String) -> TourCoach.State {
        let before = beforeContext ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        var state = TourCoach.State(step: step, text: before + after)
        state.panel = coachPanel()
        state.chip = toolbar.smartFrame == nil ? nil : toolbar.smartChip
        state.suggestions = toolbar.showingCandidates ? toolbar.suggestions.map(\.text) : []
        state.fields = VaultStore.shared.load().fields
        let bindings = SettingsStore.current.bindings.sorted { $0.key < $1.key }
        state.vaultKey = bindings.first { $0.value == "surface:vault" }?.key
        state.translateKey = bindings.first { $0.value == "surface:translate-hud" }?.key
        state.stripTools = Set(["search", "vault", "translate"].filter { findCoachView("toolbar:\($0)") != nil })
        state.copied = tourCopied
        return state
    }

    private func coachPanel() -> TourCoach.Panel {
        switch surface {
        case .none:
            if tonesPopup != nil { return .tones }
            if hudActive, let hud, !hud.isHidden {
                return .translate(ready: hud.ready, target: hud.targetLanguage)
            }
            return .none
        case .search:
            guard let sv = search else { return .other(close: "search:close") }
            return .search(tab: sv.tab.rawValue.lowercased(), view: sv.coachView,
                           query: sv.queryEditor.text)
        case .shell:
            switch shell?.screenId {
            case "vault": return .vault
            case "root": return .menu
            default: return .other(close: "toolbar:close|shell:close")
            }
        case .act:
            return .act(working: act?.isWorking ?? true, options: act?.hasOptions ?? false)
        case .clipboard:
            return .other(close: "clip:back")
        case .emoji:
            return .other(close: emoji?.searchActive == true ? "emoji:close" : "emoji:abc|emoji:letters")
        case .connector:
            return .other(close: "toolbar:close|connector:close")
        case .games:
            return .other(close: "toolbar:close")
        case .noteEdit:
            return .other(close: "noteedit:close")
        case .pay:
            return .other(close: "pay:close")
        case .bar:
            return .other(close: "bar:close|toolbar:close")
        }
    }

    /// Types what the tour needs typed, a letter at a time, the way the
    /// website's keyboard does: the search query, or Sofía's reply.
    private func tourAutotype(_ state: TourCoach.State) {
        guard !tourTyping else { return }
        if case .search(let tab, let view, let query) = state.panel, let sv = search,
           tab == TourCoach.searchTab(step: state.step),
           let q = TourCoach.searchQuery(step: state.step) {
            if case .loading = view { return }
            // Once per step on this tab: the step's own query, replacing
            // whatever an earlier chat left in the box.
            let key = "\(state.step):search:\(ObjectIdentifier(sv).hashValue):\(tab)"
            guard tourTyped != key else { return }
            tourTyped = key
            guard query != q else { return }
            if !query.isEmpty { sv.startOver() }
            typeForTour(q, append: { [weak sv] in sv?.queryEditor.append($0) })
            return
        }
        if let text = TourCoach.autotype(state) {
            let key = "\(state.step):field:\(ObjectIdentifier(hud ?? content).hashValue)"
            guard tourTyped != key else { return }
            tourTyped = key
            typeForTour(text, append: { [weak self] in self?.hostInsert($0) }) { [weak self] in
                self?.updateCandidates()
                self?.notifyHUD()
            }
        }
    }

    private func typeForTour(_ text: String, append: @escaping (String) -> Void,
                             done: (() -> Void)? = nil) {
        tourTyping = true
        let letters = text.map(String.init)
        for (i, letter) in letters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(i) * 0.045) { [weak self] in
                guard let self else { return }
                append(letter)
                if i == letters.count - 1 {
                    self.tourTyping = false
                    done?()
                    self.applyTourHint()
                }
            }
        }
    }

    /// Where a coach target is, in `content`'s coordinates. "a|b" tries each;
    /// a trailing "*" takes the topmost visible match.
    private func coachRect(_ target: String) -> CGRect? {
        for id in target.split(separator: "|").map(String.init) {
            if let v = findCoachView(id), let r = visibleRect(of: v) { return r }
        }
        return nil
    }

    private func findCoachView(_ id: String) -> UIView? {
        let prefix: String? = id.hasSuffix("*") ? String(id.dropLast()) : nil
        var best: (view: UIView, y: CGFloat)?
        func visit(_ v: UIView) -> Bool {
            if v.isHidden || v.alpha < 0.02 { return false }
            if let ident = v.accessibilityIdentifier {
                if let prefix {
                    if ident.hasPrefix(prefix), let r = visibleRect(of: v), r.height > 8,
                       best == nil || r.minY < best!.y {
                        best = (v, r.minY)
                    }
                } else if ident == id, visibleRect(of: v) != nil {
                    best = (v, 0)
                    return true
                }
            }
            for sub in v.subviews where visit(sub) { return true }
            return false
        }
        _ = visit(content)
        return best?.view
    }

    /// The part of a view that can actually be seen: clipped by every
    /// scrolling or clipping ancestor, nil when nothing is left.
    private func visibleRect(of v: UIView) -> CGRect? {
        var rect = v.convert(v.bounds, to: content)
        var node = v.superview
        while let n = node, n !== content {
            if n.isHidden || n.alpha < 0.02 { return nil }
            if n.clipsToBounds || n is UIScrollView {
                rect = rect.intersection(n.convert(n.bounds, to: content))
            }
            node = n.superview
        }
        guard node === content else { return nil }
        rect = rect.intersection(content.bounds)
        return rect.isNull || rect.width < 4 || rect.height < 4 ? nil : rect
    }

    private func showTourCoach(rect: CGRect, label: String) {
        let ring = tourRing ?? {
            let r = CAShapeLayer()
            r.fillColor = nil
            r.strokeColor = Glass.accentPrimary.cgColor
            r.lineWidth = 2.5
            if !Glass.reduceMotion {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1
                pulse.toValue = 0.3
                pulse.duration = 0.75
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                r.add(pulse, forKey: "pulse")
            }
            r.zPosition = 50
            content.layer.addSublayer(r)
            tourRing = r
            return r
        }()
        ring.frame = content.bounds
        // Along the top strip a ring outside the target is cut off by the
        // sheet's edge, so it hugs the target's own outline there.
        let onStrip = rect.minY < 6
        let inset: CGFloat = onStrip ? 1.25 : -3
        let radius: CGFloat = onStrip ? min(rect.height / 2, 12) - 1.25
                                      : min(Glass.radiusKey + 3, rect.height / 2 + 3)
        ring.path = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                                 cornerRadius: radius).cgPath

        let tag = tourLabel ?? {
            let l = TourLabelView()
            l.layer.zPosition = 51
            content.addSubview(l)
            tourLabel = l
            return l
        }()
        if tag.superview !== content { content.addSubview(tag) }
        content.bringSubviewToFront(tag)
        tag.text = label
        let size = tag.sizeThatFits(.zero)
        let gap: CGFloat = 5
        // Above the target when there is room (keys, cards), below it along
        // the strip, like the website's pill.
        let above = rect.minY - size.height - gap >= 0 && rect.minY > Glass.toolbarHeight - 4
        let x = min(max(6, rect.midX - size.width / 2), content.bounds.width - size.width - 6)
        let y = above ? rect.minY - size.height - gap : rect.maxY + gap
        tag.pointsUp = !above
        tag.arrowX = rect.midX - x
        tag.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func clearTourCoach() {
        tourRing?.removeFromSuperlayer()
        tourRing = nil
        tourLabel?.removeFromSuperview()
        tourLabel = nil
    }

    /// `knownBefore` is the text before the cursor when the caller already
    /// knows it. Reading it from the proxy is a round trip to the HOST app —
    /// the most expensive thing a keyboard does per key — so a caller that
    /// just inserted something passes what the field now holds instead of
    /// asking across the process a second time.
    private func syncAutoShift(knownBefore: String? = nil) {
        // Respect the FIELD's capitalization type like the system keyboard:
        // .none fields (usernames, searches) never auto-shift.
        let wants: Bool
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: wants = false
        case .allCharacters: wants = true
        case .words:
            let before = knownBefore ?? beforeContext
            wants = before?.isEmpty != false || before?.hasSuffix(" ") == true
        default:
            wants = WordTracker.wantsCapital(
                beforeContext: knownBefore ?? beforeContext)
        }
        keyboardView.syncAutoShift(wantsCapital: wants)
    }

    /// What this field allows (FORMAT.md "When Glyf autocorrects"): nothing
    /// in secure, email, URL, username, code and number fields; no
    /// autocorrect where the field or the user turned it off; no learning in
    /// fields that hold names or when learning is paused.
    private var typingPolicy: TypingEngine.Policy {
        let proxy = textDocumentProxy
        if isSecureField { return [] }
        switch proxy.keyboardType ?? .default {
        case .URL, .emailAddress, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad, .namePhonePad:
            return []
        default: break
        }
        let quiet: [UITextContentType] = [.URL, .emailAddress, .username, .password, .newPassword, .oneTimeCode,
                                          .creditCardNumber, .telephoneNumber]
        let contentType = proxy.textContentType ?? nil
        if let type = contentType, quiet.contains(type) { return [] }
        let s = SettingsStore.current
        var policy: TypingEngine.Policy = .all
        if !s.autocorrect || proxy.autocorrectionType == .no || proxy.keyboardType == .twitter
            || proxy.keyboardType == .webSearch {
            policy.remove(.autocorrect)
        }
        if let type = contentType, [.name, .givenName, .familyName, .nickname].contains(type) {
            policy.remove(.autocorrect)
        }
        if s.vocabLearning == false { policy.remove(.learning) }
        return policy
    }

    /// The website's smart strip: a sum you just typed, or the saved detail
    /// the sentence is asking for, offered as one chip above the keys.
    private func updateSmartChip() -> Bool {
        guard surface == .none, !isSecureField else {
            toolbar.showSmart(nil)
            return false
        }
        // A mail that just landed at the temp address comes first: its code
        // is what the field is waiting for.
        if let mail = mailChip {
            if Date().timeIntervalSince(mail.at) < 300, tourStep == nil {
                cancelSuggestion()
                toolbar.showSmart(mail.chip)
                return true
            }
            mailChip = nil
        }
        let before = beforeContext ?? ""
        let tail = String(before.suffix(120))
        if let gone = dismissedTail {
            if gone == tail.trimmingCharacters(in: .whitespacesAndNewlines) {
                cancelSuggestion()
                toolbar.showSmart(nil)
                return false
            }
            dismissedTail = nil
        }
        // Something just copied rides in the strip as one chip, never as a
        // second row: history's copy when we already have it, otherwise the
        // offer itself (tapping reads, which is the moment iOS asks).
        // History only knows a copy once it has been read; a newer one shows
        // as an offer instead of the older text.
        var paste = pasteOffer(tailEmpty: tail.isEmpty)
        // A digit pad can only take digits: a copied link is no offer there.
        if keyboardView.context.isPad, let p = paste,
           !p.allSatisfy({ $0.isNumber || "+-() .".contains($0) }) {
            paste = nil
        }
        let rates = RatesStore.shared.snapshot()
        let ownWallet = SettingsStore.current.walletAddress
        var chip = Smart.chip(for: tail, fields: VaultStore.shared.load().fields,
                              paste: paste, field: fieldHint(emptyField: before.isEmpty),
                              rates: rates, ownWallet: ownWallet,
                              indianGrouping: (SettingsStore.current.region ?? "IN") == "IN")
        // An email field with nothing in it: a temp address in one tap, or,
        // beside your own email, "Temp" for one.
        var extra: String?
        if before.isEmpty, (textDocumentProxy.documentContextAfterInput ?? "").isEmpty,
           hasFullAccess, GlyfSession.token() != nil, fieldHint(emptyField: true).kind == "email" {
            if chip == nil {
                chip = .tempAddress(live: TempMailWatcher.shared.address)
            } else if case .vault(let f)? = chip, f.kind == "email" {
                extra = "Temp"
            }
        }
        // An address on screen or copied: a wallet (Send) or a token (Buy)?
        // Only a lookup can tell; the strip is arranged again when it lands.
        if chip == nil, hasFullAccess,
           let address = Smart.addressToCheck(in: tail, paste: paste, rates: rates, ownWallet: ownWallet) {
            RatesStore.shared.ensureAddress(address) { [weak self] in self?.updateCandidates() }
        }
        // An amount or a ticker with no rate yet: ask for one; the strip is
        // arranged again when it lands.
        // A character test first: neither pattern can match without one, and
        // this runs on text that is usually just words.
        if chip == nil, hasFullAccess, tail.contains(where: { $0 == "$" || $0.isNumber }) {
            if tail.contains("$"), let ticker = Smart.cashtag(in: tail) {
                RatesStore.shared.ensureToken(ticker) { [weak self] in self?.updateCandidates() }
                RatesStore.shared.ensureFiat { [weak self] in self?.updateCandidates() }
            } else if tail.contains(where: \.isNumber), Smart.looksLikeMoney(tail) {
                RatesStore.shared.ensureFiat { [weak self] in self?.updateCandidates() }
            }
        }
        // The tour keeps the strip for the step it is coaching.
        if let step = tourStep {
            if let c = chip, !TourCoach.allowsChip(Self.chipKind(c), step: step, copied: tourCopied) { chip = nil }
            toolbar.showSmart(chip)
            return chip != nil
        }
        // Nothing local to say? Let the model look at the sentence and name
        // the thing Glyf could do with it (the website's coach).
        if chip == nil {
            // The answer is stored for the trimmed sentence: people end with a space.
            if let cached = suggestedChip,
               suggestedFor == tail.trimmingCharacters(in: .whitespacesAndNewlines) {
                chip = cached
            } else {
                askForSuggestion(tail)
            }
        } else {
            cancelSuggestion()
        }
        toolbar.showSmart(chip, extra: extra)
        return chip != nil
    }

    private static func chipKind(_ chip: Smart.Chip) -> String {
        switch chip {
        case .calc: return "calc"
        case .money: return "money"
        case .vault(let f): return "vault:\(f.kind)"
        case .paste: return "paste"
        case .pay: return "pay"
        case .buy: return "buy"
        case .action: return "action"
        case .event: return "event"
        case .booking: return "booking"
        case .tempMail: return "tempmail"
        case .tempAddress: return "tempaddress"
        }
    }

    /// What the focused field is asking for. iOS tells a keyboard extension
    /// nothing about labels, so this reads the signals it does give: the
    /// keyboard type, and for names the pairing of word-capitalisation with a
    /// Next key. (Android reads the real hint — see Autofill.kt.)
    private func fieldHint(emptyField: Bool) -> Smart.FieldHint {
        guard !isSecureField else { return .none }
        let proxy = textDocumentProxy
        var kind: String?
        switch proxy.keyboardType {
        case .emailAddress: kind = "email"
        case .phonePad, .namePhonePad: kind = "phone"
        // A web address field may want your site; a search box (Safari's
        // address bar) is asking what to look for, not for your link.
        case .URL: kind = "link"
        default: break
        }
        if kind == nil, proxy.autocapitalizationType == .words,
           proxy.returnKeyType == .next {
            kind = "name"
        }
        return Smart.FieldHint(kind: kind, empty: emptyField)
    }

    /// Debounced, cancellable, and never for a half-typed word: a pause of
    /// 700ms on a real sentence is the only thing that asks. It never spends
    /// a run: suggestions have their own allowance on the server.
    private func askForSuggestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasFullAccess, !isSecureField, surface == .none,
              SettingsStore.current.candidates,
              trimmed.count >= 12, trimmed.split(separator: " ").count >= 3,
              trimmed != suggestedFor,
              glyfWrote.isEmpty || !trimmed.hasSuffix(glyfWrote)
        else { return }
        cancelSuggestion()
        let fields = VaultStore.shared.load().fields
        let kinds = SettingsStore.current.aiUsesVault == false ? [] : Array(Set(fields.map(\.kind))).sorted()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suggestTask = BackendClient.shared.suggestAction(text: trimmed, kinds: kinds) {
                [weak self] intent, label, query in
                guard let self, self.surface == .none else { return }
                let before = self.beforeContext ?? ""
                // The sentence moved on while we were asking: drop it.
                guard String(before.suffix(120))
                    .trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                if intent == "detail" {
                    // The model named the kind; the value is this phone's own.
                    guard let field = fields.first(where: { $0.kind == label }) else { return }
                    self.suggestedFor = trimmed
                    self.suggestedChip = .vault(field: field)
                } else {
                    self.suggestedFor = trimmed
                    self.suggestedChip = .action(label: label, query: query, intent: intent)
                }
                self.updateCandidates()
            }
        }
        suggestWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func cancelSuggestion() {
        suggestWork?.cancel()
        suggestWork = nil
        suggestTask?.cancel()
        suggestTask = nil
    }

    private func updateCandidates() {
        // A scheduled pass is now redundant, whoever asked for this one.
        candidatesWork?.cancel()
        candidatesWork = nil
        let tC = Perf.mark()
        defer {
            Perf.say("candidates=\(Perf.ms(tC))ms chip=\(self.tChip)ms engine=\(self.tEngine)ms strip=\(self.tStrip)ms")
            Perf.reportHostReads() // end of the cycle: the whole keystroke's crossings
        }
        defer { applyTourHint() }         // the strip changed under the ring
        let tCh = Perf.mark()
        let chipOwns = updateSmartChip()
        tChip = Perf.ms(tCh)
        if chipOwns { return }            // one chip owns the strip
        let policy = typingPolicy
        guard SettingsStore.current.candidates, policy.contains(.suggestions), surface == .none else {
            toolbar.showSuggestions([])
            return
        }
        let before = beforeContext
        let word = WordTracker.currentWord(beforeContext: before)
        if word.isEmpty {
            if let corr = undoableCorrection(before: before) {
                toolbar.showSuggestions([.init(text: corr.original, kind: .undo)])
            } else if let engine = typing, before?.hasSuffix(" ") == true,
                      let previous = WordTracker.previousWord(beforeContext: before) {
                toolbar.showSuggestions(engine.predictions(previous: previous, policy: policy)
                    .map { .init(text: $0, kind: .word) })
            } else {
                toolbar.showSuggestions([])
            }
            return
        }
        lastCorrection = nil
        let tE = Perf.mark()
        let sMaybe = suggestions(for: word, before: before, policy: policy)
        tEngine = Perf.ms(tE)
        guard let s = sMaybe else {
            toolbar.showSuggestions([])
            return
        }
        let tSt = Perf.mark()
        defer { tStrip = Perf.ms(tSt) }
        let others = s.alternatives.map { GlyfToolbar.Suggestion(text: $0, kind: .word) }
        if let fix = s.autocorrect {
            // With "Correct automatically" off the space keeps the word, so
            // the fix is offered as a plain word rather than promised in bold.
            let fixKind: GlyfToolbar.Suggestion.Kind =
                SettingsStore.current.autocorrectApply == false ? .word : .correction
            toolbar.showSuggestions([.init(text: word, kind: .literal), .init(text: fix, kind: fixKind)]
                                    + others.prefix(1))
        } else if others.isEmpty {
            toolbar.showSuggestions([])
        } else {
            toolbar.showSuggestions([.init(text: word, kind: s.known ? .word : .literal)] + others.prefix(2))
        }
    }

    private func suggestions(for word: String, before: String?, policy: TypingEngine.Policy) -> TypingEngine.Suggestions? {
        guard let engine = typing else { return nil }
        // A number is not a misspelt word, and a ;trigger is on its way to
        // becoming shorthand: neither wants the dictionary's guesses.
        guard let first = word.first, !first.isNumber, first != ";" else { return nil }
        let head = String((before ?? "").dropLast(word.count))
        // ";" splits words, so a trigger reaches here as "otw" with the
        // semicolon just before it.
        if head.last == ";" { return nil }
        return engine.suggestions(
            typed: word,
            touches: wordTouchesFor == word ? wordTouches : nil,
            previous: WordTracker.previousWord(beforeContext: before),
            sentenceStart: WordTracker.wantsCapital(beforeContext: head),
            policy: policy)
    }

    /// A word just ended (space, punctuation, return): expand a text
    /// replacement, or autocorrect it when the engine is sure, then learn
    /// what was actually kept.
    private func commitCurrentWord() {
        let before = beforeContext
        let word = WordTracker.currentWord(beforeContext: before)
        defer {
            wordTouches = []
            wordTouchesFor = ""
        }
        guard !word.isEmpty else { return }
        let policy = typingPolicy
        let previous = WordTracker.previousWord(beforeContext: before)
        let head = String((before ?? "").dropLast(word.count))
        let sentenceStart = WordTracker.wantsCapital(beforeContext: head)

        if !policy.isEmpty, let phrase = TypingStore.shared.replacements[word.lowercased()] {
            replaceCurrentWord(with: phrase)
            lastCorrection = Correction(original: word, replacement: phrase, fromEngine: false)
            return
        }
        guard let engine = typing else { return }
        var kept = word
        recentFixes.removeAll { Date().timeIntervalSince($0.at) > 300 }
        if let i = recentFixes.firstIndex(where: { $0.touched && $0.original.lowercased() == word.lowercased() }) {
            // Corrected, gone back into, and typed the same again: keep it.
            let refused = recentFixes.remove(at: i)
            engine.revert(typed: word, correction: refused.replacement)
        } else if policy.contains(.autocorrect),
           let fix = suggestions(for: word, before: before, policy: policy)?.autocorrect, fix != word {
            // "Correct automatically" off: the word stands exactly as typed.
            // The strip is already offering the fix, so a tap still takes it
            // — nothing is changed behind the writer's back.
            if SettingsStore.current.autocorrectApply != false {
                replaceCurrentWord(with: fix)
                lastCorrection = Correction(original: word, replacement: fix, fromEngine: true)
                recentFixes.append(RecentFix(original: word, replacement: fix, at: Date()))
                if recentFixes.count > 8 { recentFixes.removeFirst(recentFixes.count - 8) }
                kept = fix
            }
        }
        let autoCapitalized = sentenceStart && SettingsStore.current.autocapitalize
            && textDocumentProxy.autocapitalizationType != UITextAutocapitalizationType.none
        engine.commit(word: kept, previous: previous, autoCapitalized: autoCapitalized, policy: policy)
        TypingStore.shared.scheduleSave()
    }

    /// Replace the word being typed (suggestions, autocorrect, replacements).
    private func replaceCurrentWord(with replacement: String) {
        let word = WordTracker.currentWord(
            beforeContext: beforeContext)
        for _ in 0..<word.count { hostDelete() }
        hostInsert(replacement)
    }

    // MARK: Why there is no underline under a flagged word
    //
    // `UITextDocumentProxy` does carry `setMarkedText` — the provisional run
    // an IME composes in — and it works: marking a word and reading back
    // `documentContextBeforeInput` returns the text WITHOUT it, which is
    // exactly what a composing run should do.
    //
    // That is also why it cannot be used here. Everything this keyboard
    // knows about what you are writing comes from that context: the word
    // being typed, the previous word, whether a sentence is starting. Mark
    // the current word and the keyboard stops being able to see it.
    //
    // And it buys nothing: Messages draws no underline under marked text, so
    // the flag is invisible in the very place it was meant for. The honest
    // version of "don't change my words" is the one that ships — with
    // "Correct automatically" off the word stands exactly as typed and the
    // strip offers the fix for a tap.

    /// Put back what was typed before the last correction; an engine
    /// correction is never offered for that word again.
    @discardableResult
    private func undoLastCorrection() -> Bool {
        guard let corr = undoableCorrection(before: beforeContext),
              let before = beforeContext else { return false }
        let tail = before.hasSuffix(corr.replacement + " ") ? corr.replacement + " "
            : before.hasSuffix(corr.replacement) ? corr.replacement : nil
        guard let tail else { return false }
        for _ in 0..<tail.count { hostDelete() }
        let spaced = tail.count > corr.replacement.count
        hostInsert(spaced ? corr.original + " " : corr.original)
        lastCorrection = nil
        if corr.fromEngine {
            typing?.revert(typed: corr.original, correction: corr.replacement)
            TypingStore.shared.scheduleSave()
        }
        return true
    }
}

// MARK: - KeyboardViewDelegate

extension GlyfKeyboardViewController: KeyboardViewDelegate {

    func kbInsert(_ text: String) {
        if let editor = inlineTarget {
            editor.append(text)
            return
        }
        // The host round trip below is the costliest part of a keystroke, so
        // it happens at most once: what the field will hold afterwards is
        // just what it held plus this character.
        let t0 = Perf.mark()
        var tHost: Double = 0
        var before: String?
        var readBefore = false
        if text.count == 1, let ch = text.first {
            if WordTracker.correctionBoundaries.contains(ch) {
                // Punctuation ends the word: correct it before the mark lands.
                commitCurrentWord()
            } else if !WordTracker.boundaries.contains(ch) || ch == "'" || ch == "’" {
                let th = Perf.mark()
                before = beforeContext
                tHost = Perf.ms(th)
                readBefore = true
                let current = WordTracker.currentWord(beforeContext: before)
                if current != wordTouchesFor {
                    wordTouches = Array(repeating: nil, count: current.unicodeScalars.count)
                }
                wordTouches.append(keyboardView.lastTapOffset)
                wordTouchesFor = current + text
            }
        }
        let tI = Perf.mark()
        hostInsert(text)
        let tInsert = Perf.ms(tI)
        let tS = Perf.mark()
        syncAutoShift(knownBefore: readBefore ? (before ?? "") + text : nil)
        let tShift = Perf.ms(tS)
        scheduleCandidates()
        Perf.say("key total=\(Perf.ms(t0))ms host=\(tHost)ms insert=\(tInsert)ms shift=\(tShift)ms")
    }

    func kbDeleteBackward() {
        if let editor = inlineTarget {
            editor.deleteBackward()
            return
        }
        // Backspace right after a correction puts back what was typed (and
        // teaches the engine to leave that word alone).
        if let corr = undoableCorrection(before: beforeContext) {
            for _ in 0..<(corr.replacement.count + 1) { hostDelete() }
            hostInsert(corr.original)
            lastCorrection = nil
            if corr.fromEngine {
                typing?.revert(typed: corr.original, correction: corr.replacement)
                TypingStore.shared.scheduleSave()
            }
        } else {
            lastCorrection = nil
            hostDelete()
        }
        // One read of the host's text, reused below: the delete has already
        // happened, so this IS what the field holds now.
        let before = beforeContext
        let current = WordTracker.currentWord(beforeContext: before)
        // Backing into a word the engine corrected ("cute" → "cut"): if the
        // original comes back, that correction was a mistake.
        if current.count >= 2 {
            let lower = current.lowercased()
            for i in recentFixes.indices where recentFixes[i].replacement.lowercased().hasPrefix(lower) {
                recentFixes[i].touched = true
            }
        }
        if wordTouches.count > current.unicodeScalars.count {
            wordTouches.removeLast(wordTouches.count - current.unicodeScalars.count)
        }
        wordTouchesFor = current
        syncAutoShift(knownBefore: before)
        scheduleCandidates()
    }

    func kbSpaceTapped() {
        if let editor = inlineTarget {
            editor.append(" ")
            return
        }
        let s = SettingsStore.current
        let now = Date()
        // Double-space → ". " (§6.1)
        if s.periodShortcut, now.timeIntervalSince(lastSpaceTap) < 0.45,
           WordTracker.canPeriodShortcut(beforeContext: beforeContext) {
            hostDelete()
            hostInsert(". ")
            lastSpaceTap = .distantPast
            syncAutoShift()
            scheduleCandidates()
            notifyHUD()
            return
        }
        lastSpaceTap = now

        // §6.7 shorthand: ;sig-style triggers expand on the space commit,
        // before autocorrect gets a look. Undo works like autocorrect undo.
        if !isSecureField,
           let token = Shorthand.pendingToken(
               beforeContext: beforeContext),
           let expansion = Shorthand.expansion(for: token, in: VaultStore.shared.load()) {
            for _ in 0..<token.count { hostDelete() }
            hostInsert(expansion)
            lastCorrection = Correction(original: token, replacement: expansion, fromEngine: false)
            hostInsert(" ")
            lastCorrection?.anchor = beforeContext
            syncAutoShift()
            scheduleCandidates()
            notifyHUD()
            return
        }

        // Autocorrect + learning on commit (§6.1, Engine/Typing) — the
        // policy keeps secure fields untouched (§11.9).
        commitCurrentWord()
        hostInsert(" ")
        // A correction this space just made is undoable from here only.
        if let corr = lastCorrection, corr.anchor == nil { lastCorrection?.anchor = beforeContext }
        syncAutoShift()
        scheduleCandidates()
        notifyHUD()
    }

    func kbReturnTapped() {
        if inlineTarget != nil, surface == .pay {
            // Return = done typing the amount; Send stays a deliberate tap.
            pay?.endAmount()
            return
        }
        if inlineTarget != nil, surface == .search {
            // Return = run the search (Gboard parity); the query stays live.
            search?.submit()
            return
        }
        if inlineTarget != nil, surface == .emoji {
            // Return = done searching: emoji go back to the full grid, a
            // GIF or sticker query runs and its results become the board.
            emoji?.returnPressed()
            return
        }
        if inlineTarget != nil, case .connector = surface {
            connector?.exitSearch()
            calendarView?.returnPressed()
            return
        }
        if inlineTarget != nil, surface == .noteEdit {
            // A new line in a note, on from a shortcut, Save for a detail.
            noteEdit?.returnPressed()
            return
        }
        if inlineTarget != nil, surface == .bar {
            // Return asks, like the send arrow.
            bar?.submit()
            return
        }
        if let editor = inlineTarget {
            editor.isActive = false
            inlineTarget = nil
            return
        }
        commitCurrentWord()
        hostInsert("\n")
        syncAutoShift()
        updateCandidates()
    }

    func kbGlobe(event: UIEvent?, key: KeyView, longPress: Bool) {
        if longPress, let event {
            handleInputModeList(from: key, with: event)
        } else {
            advanceToNextInputMode()
        }
    }

    func kbOpenEmoji() {
        setSurface(.emoji)
    }

    // MARK: Cursor glide (space-bar trackpad)

    func kbCursorGlideBegan() {
        cursorMirror = currentCursorMirror()
    }

    func kbMoveCursor(graphemes: Int) {
        // The proxy's context lags a move by a frame or two, so it's only
        // re-read once the mirror has run out AND the host has had time.
        if cursorMirror?.isStale ?? true,
           CACurrentMediaTime() - lastCursorAdjust > 0.15 {
            cursorMirror = currentCursorMirror()
        }
        let offset = cursorMirror?.offset(forGraphemes: graphemes) ?? graphemes
        guard offset != 0 else { return }
        hostAdjust(byCharacterOffset: offset)
        lastCursorAdjust = CACurrentMediaTime()
    }

    func kbSpaceGestures() -> (glide: Bool, bar: Bool) {
        (glide: inlineTarget == nil, bar: inlineTarget == nil && !isSecureField)
    }

    func kbBindingsLive() -> Bool {
        inlineTarget == nil && !isSecureField
    }

    func kbCursorGlideEnded() {
        cursorMirror = nil
        // Keyboard-driven moves don't come back as textDidChange, so caps
        // and candidates re-read the new position once the host settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.syncAutoShift()
            self?.updateCandidates()
        }
    }

    private func currentCursorMirror() -> CursorMirror {
        CursorMirror(before: beforeContext ?? "",
                     after: textDocumentProxy.documentContextAfterInput ?? "")
    }

    func kbSpaceHoldIgnited(origin: KeyView) {
        // §5.3: the surface starts rising 60ms after ignition — caused by the
        // ripple, not queued behind it.
        let delay = Glass.reduceMotion ? Glass.Ripple.reducedMotionFlash
                                       : Glass.Ripple.surfaceRiseDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // Typed text is the intent: act on it straight away. An empty
            // field (or no Full Access, which the bar explains) gets the
            // prompt bar instead.
            let before = self.beforeContext ?? ""
            let after = self.textDocumentProxy.documentContextAfterInput ?? ""
            let typed = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty, self.hasFullAccess, !self.isSecureField {
                self.startAct(before: before, after: after)
            } else {
                self.openBar(autoRun: nil)
            }
        }
    }

    // MARK: Act (hold space on what you typed)

    // MARK: Copied-text strip

    /// Offers a recent copy above the toolbar — without reading it: only the
    /// user's tap reads the pasteboard (§ paste-prompt rule).
    /// Kept as the one place that reacts to a fresh copy: the offer now
    /// lives in the strip as a chip, so there is never a second row.
    private func refreshClipStrip(animated: Bool) {
        updateCandidates()
    }

    private func removeClipStrip() {
        clipStrip?.removeFromSuperview()
        clipStrip = nil
        applySurfaceLayout(animated: true)
    }

    /// Spends the retry on a failed run; true when the run is being tried again.
    private func retryAct(after message: String) -> Bool {
        guard actRetryBudget > 0, surface == .act else { return false }
        actRetryBudget -= 1
        log.log("GLYF_RUN retry after: \(message, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.surface == .act else { return }
            self.runAct()
        }
        return true
    }

    private func startAct(clipboard text: String) {
        actSkill = nil
        actSkillTitle = nil
        actVars = [:]
        actIntent = nil
        actInput = ("", "") // a copied text is acted on, never deleted from the field
        actRunInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        actAccepted = false
        actRetryBudget = 1
        setSurface(.act)
        runAct()
    }

    private func startAct(before: String, after: String, intent: String? = nil) {
        actSkill = nil
        actSkillTitle = nil
        actVars = [:]
        actIntent = intent
        actInput = (before, after)
        actRunInput = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        actAccepted = false
        actRetryBudget = 1
        setSurface(.act)
        runAct()
    }

    /// A bound letter held → its skill runs as a HUD: the skill's name over
    /// the letter's keycap while it works, then the answer with ↻ Copy Insert.
    private func startSkill(glyfId: String, letter: String) {
        guard !isSecureField else { return } // §11.9: no AI in secure fields
        guard hasFullAccess else { openBar(autoRun: glyfId); return } // the bar explains Full Access
        let input = collectBarInput()
        actSkill = (glyfId, letter)
        actSkillTitle = nil
        actVars = [:]
        actRunInput = input.text
        actRetryBudget = 1
        // Field text is swapped on Insert; clipboard or empty input only inserts.
        actInput = input.source == "field"
            ? (beforeContext ?? "", input.after) : ("", "")
        actAccepted = false
        setSurface(.act)
        runAct()
    }

    private func runAct() {
        guard let act else { return }
        actTask?.cancel()
        actHasResult = false
        if let skill = actSkill {
            let title = actSkillTitle ?? GlyfCatalog.title(for: skill.glyfId)
            act.showWorking(intent: actRunInput, title: title, keyLetter: skill.letter)
            let vars = actVars   // BackendClient adds the two languages for glyf.translate
            var streamed = ""
            actTask = BackendClient.shared.run(
                glyfId: skill.glyfId, input: actRunInput, vars: vars,
                onToken: { [weak self] token in
                    guard let self, self.surface == .act else { return }
                    streamed += token
                    self.act?.showStreaming(title: title, text: streamed)
                },
                onDone: { [weak self] text, _ in
                    guard let self, self.surface == .act else { return }
                    self.actHasResult = true
                    self.act?.showResult(title: title, cards: [], text: text, insert: text)
                },
                onError: { [weak self] message in
                    guard let self, self.surface == .act else { return }
                    if self.retryAct(after: message) { return }
                    self.act?.showFailure(message)
                })
            return
        }
        // A sum, a conversion, money at the rates in hand, the time or the
        // date: answered here at once, no server and no run ("2+5" held for
        // a moment went to the server and back).
        if actIntent == nil || actIntent == "answer",
           let local = Smart.instantAnswer(actRunInput, rates: RatesStore.shared.snapshot(),
                                           indianGrouping: (SettingsStore.current.region ?? "IN") == "IN") {
            actHasResult = true
            let card = BackendClient.SearchCard(kind: "answer", id: "local", title: local.title, url: "",
                                                say: local.say, value: local.value, sub: local.sub, art: "calc")
            act.showResult(title: local.title, cards: [card], text: nil, insert: local.say)
            return
        }
        act.showWorking(intent: actRunInput)
        // Versions show one by one as the model finishes each, and written
        // text as it comes: the first row is up well before the last.
        var written = ""
        actTask = BackendClient.shared.runAct(text: actRunInput, intent: actIntent,
                                              onOption: { [weak self] option in
            guard let self, self.surface == .act else { return }
            self.act?.addOption(option)
        }, onText: { [weak self] t in
            guard let self, self.surface == .act else { return }
            written += t
            let shown = written.trimmingCharacters(in: .whitespacesAndNewlines)
            if !shown.isEmpty { self.act?.showStreaming(title: self.actRunInput, text: shown) }
        }, onReset: { [weak self] in
            guard let self, self.surface == .act else { return }
            written = ""
            self.act?.showWorking(intent: self.actRunInput)
        }, onResult: { [weak self] result in
            guard let self, self.surface == .act else { return }
            self.actHasResult = true
            if let options = result.options, !options.isEmpty {
                self.act?.showOptions(options)
                return
            }
            self.act?.showResult(title: result.title ?? "", cards: result.cards ?? [],
                                 text: result.text, insert: result.insert ?? result.text ?? "")
        }, onError: { [weak self] message in
            guard let self, self.surface == .act else { return }
            if self.retryAct(after: message) { return }
            self.act?.showFailure(message)
        })
    }

    func kbBoundKeyIgnited(keyId: String, glyfId: String, origin: KeyView) {
        let delay = Glass.reduceMotion ? Glass.Ripple.reducedMotionFlash
                                       : Glass.Ripple.surfaceRiseDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runBinding(glyfId, letter: keyId)
        }
    }

    /// What a bound key does: held on the keys, or tapped in My glyfs.
    private func runBinding(_ glyfId: String, letter: String) {
        switch glyfId {
        case "surface:translate-hud":
            // §6.13 T toggles the persistent strip on/off. It lives over the
            // keys, so a panel it was started from goes.
            setSurface(.none)
            let on = !(SettingsStore.current.translationHUD ?? false)
            SettingsStore.update { $0.translationHUD = on }
            applySurfaceLayout(animated: true)
            if on {
                hud?.refreshTarget()
                notifyHUD()
            } else {
                KeyboardToast.show(in: content, text: "Translate off")
            }
        case "surface:tones":
            setSurface(.none)
            showTonesPopup()
        case "connector:meet":
            setSurface(.none)
            // A fresh Google Meet link, straight into the message.
            CallLink.make { [weak self] url, note in
                guard let self else { return }
                if let url {
                    self.hostInsert(Self.spaced("Join me on a call: \(url)", after: self.beforeContext))
                    self.syncAutoShift()
                    self.updateCandidates()
                } else if let note {
                    KeyboardToast.show(in: self.content, text: note)
                }
            }
        case let id where id.hasPrefix("surface:"):
            // Other "surface:" bindings open shell screens (M4: S → vault);
            // from My glyfs the open menu goes there, with its way back.
            if surface != .shell { setSurface(.shell) }
            shell?.push(String(id.dropFirst("surface:".count)))
        case let id where id.hasPrefix("connector:"):
            // §6.12 C — the ConnectorSurface picker.
            setSurface(.connector(String(id.dropFirst("connector:".count))))
        default:
            startSkill(glyfId: glyfId, letter: letter)
        }
    }

    func kbTextInteraction() {}

    // MARK: Bar

    /// Ask Glyf. A tool that already knows what to run (translate, a tone)
    /// goes straight to the act panel; without Full Access the bar says how
    /// to get it.
    private func openBar(autoRun: String?, vars: [String: String] = [:]) {
        guard !isSecureField else { return } // §11.9: no AI in secure fields
        let input = collectBarInput()
        if let glyfId = autoRun, hasFullAccess {
            runFromBar(glyfId: glyfId, vars: vars, title: GlyfCatalog.title(for: glyfId), input: input)
            return
        }
        setSurface(.bar)
        bar?.present(input: input, hasFullAccess: hasFullAccess)
        applySurfaceLayout(animated: true)
    }

    /// A bar run plays out like a held key's skill: working, the answer, and
    /// Insert (which swaps the field text it read; copied text only adds).
    private func runFromBar(glyfId: String, vars: [String: String], title: String,
                            input: GlyfBar.Input) {
        actSkill = (glyfId, nil)
        actSkillTitle = title
        actVars = vars
        actIntent = nil
        actRunInput = input.text
        actRetryBudget = 1
        actInput = input.source == "field"
            ? (beforeContext ?? "", input.after) : ("", "")
        actAccepted = false
        setSurface(.act)
        runAct()
    }

    private func collectBarInput() -> GlyfBar.Input {
        let before = beforeContext ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let field = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        if !field.isEmpty {
            return GlyfBar.Input(text: before + after, source: "field",
                                 consumedBefore: before.count, after: after)
        }
        if hasFullAccess {
            if let clip = ClipboardStore.load().first?.text, !clip.isEmpty {
                return GlyfBar.Input(text: clip, source: "clipboard", consumedBefore: 0)
            }
        }
        return GlyfBar.Input(text: "", source: "empty", consumedBefore: 0)
    }
}

// MARK: - ActSurfaceDelegate

extension GlyfKeyboardViewController: ActSurfaceDelegate {

    func actInsert(_ text: String) {
        recordSkillOutcome(accepted: true)
        // Swap exactly what the run read — both sides of the cursor.
        if let input = actInput {
            if !input.after.isEmpty {
                hostAdjust(byCharacterOffset: input.after.utf16.count)
            }
            for _ in 0..<(input.before.count + input.after.count) {
                hostDelete()
            }
        }
        hostInsert(text)
        glyfWrote = text.trimmingCharacters(in: .whitespacesAndNewlines)
        actInput = nil
        setSurface(.none)
        syncAutoShift()
        updateCandidates()
    }

    func actCopy(_ text: String) {
        guard hasFullAccess else { return }
        recordSkillOutcome(accepted: true)
        UIPasteboard.general.string = text
        _ = ClipboardStore.inserting(text, into: ClipboardStore.load(), now: Date())
            .map(ClipboardStore.save)
        if let act { KeyboardToast.show(in: act, text: "Copied") }
    }

    func actRetry() { runAct() }

    func actRetryAvailable(_ available: Bool) {
        guard surface == .act, Glass.solidLook else { return }
        toolbar.setPanelAction(symbol: "arrow.clockwise", label: "Try again",
                               handler: available ? { [weak self] in self?.actRetry() } : nil)
    }

    func actOpen(_ url: URL) {
        HostAppOpener.open(url, from: self) { _ in }
    }

    func actClosed() {
        // §6.15: a skill result the user walked away from is a "discard".
        if actHasResult, !actAccepted { recordSkillOutcome(accepted: false) }
        actInput = nil
        setSurface(.none)
    }

    /// §6.15 tone learning, once per result — same signal the bar recorded.
    private func recordSkillOutcome(accepted: Bool) {
        guard let skill = actSkill, !actAccepted else { return }
        ToneProfile.record(glyfId: skill.glyfId, accepted: accepted)
        if accepted { actAccepted = true }
    }
}

// MARK: - ClipboardPanelDelegate

extension GlyfKeyboardViewController: ClipboardPanelDelegate {
    func clipboardPanelClosed() { setSurface(.none) }

    func clipboardPanelPaste(_ text: String) {
        setSurface(.none)
        // A copy is its own piece of text: it never glues onto the word
        // before it ("10.8QvS…").
        hostInsert(Self.spaced(text, after: beforeContext))
        updateCandidates()
    }

    /// The system paste button handed content over. Reaching the clipboard
    /// this way is the ONE route iOS does not put a banner in front of: the
    /// tap IS the permission, so there is nothing to approve afterwards.
    /// Everywhere else, reading `UIPasteboard.general.string` asks again each
    /// time the copy changes — which is what made Glyf feel like it was
    /// forever begging.
    func acceptPasted(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { [weak self] value, _ in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setSurface(.none)
                    ClipContext.markDone()
                    self.remember(copied: value)
                    self.hostInsert(Self.spaced(value, after: self.beforeContext))
                    self.updateCandidates()
                }
            }
            return
        }
        // An image cannot go into a host text box from any keyboard (the proxy
        // types text and nothing else), so it goes where it CAN be used again:
        // the vault, which is ours to draw.
        if provider.canLoadObject(ofClass: UIImage.self) {
            _ = provider.loadObject(ofClass: UIImage.self) { [weak self] value, _ in
                guard let image = value as? UIImage else { return }
                DispatchQueue.main.async { self?.keepImage(image) }
            }
        }
    }

    /// Saves a pasted or picked image into the vault and says where it went.
    func keepImage(_ image: UIImage, label: String = "Image") {
        // JPEG at 0.85: a screenshot keeps its text crisp and a photo lands
        // well under the cap, where the original PNG often would not.
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            KeyboardToast.show(in: content, text: "Could not read that image")
            return
        }
        if let why = VaultStore.shared.addImage(data: data, label: label) {
            KeyboardToast.show(in: content, text: why)
            return
        }
        KeyboardToast.show(in: content, text: "Saved to vault")
        shell?.render()
    }

    func clipboardPanelSavedToVault(refusal: String?) {
        KeyboardToast.show(in: content, text: refusal ?? "Saved to vault")
    }

    func clipboardPanelCopiedImage() {
        setSurface(.none)
        // iOS lets no keyboard put an image in a text box: it is on the
        // clipboard, one hold of the box away.
        KeyboardToast.show(in: content, text: "Copied. Hold the text box to paste")
    }

}

// MARK: - ClipContextStripDelegate

extension GlyfKeyboardViewController: ClipContextStripDelegate {

    func clipStripRead() {
        // The user's tap is the intent that may surface Apple's paste prompt.
        // (The Paste button beside this label goes through UIPasteControl and
        // never prompts; this path is the fallback for the rest of the strip.)
        ClipboardStore.readCopy { [weak self] text in
            guard let self else { return }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                ClipContext.markDone()
                self.removeClipStrip()
                return
            }
            self.remember(copied: text)
            self.clipStrip?.show(text: text)
        }
    }

    /// Everything that arrives from the pasteboard lands in history first, so
    /// "what I copied earlier" is there even after the copy itself is gone.
    private func remember(copied text: String) {
        _ = ClipboardStore.inserting(text, into: ClipboardStore.load(), now: Date())
            .map(ClipboardStore.save)
    }

    func clipStripPaste() {
        ClipboardStore.readCopy { [weak self] text in
            guard let self else { return }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                ClipContext.markDone()
                self.removeClipStrip()
                return
            }
            self.pasteFromStrip(text)
        }
    }

    private func pasteFromStrip(_ text: String) {
        remember(copied: text)
        ClipContext.markDone()
        removeClipStrip()
        hostInsert(text)
        updateCandidates()
    }

    func clipStripAct(_ text: String) {
        ClipContext.markDone()
        clipStrip?.removeFromSuperview()
        clipStrip = nil
        startAct(clipboard: text)
    }

    func clipStripDismissed() {
        ClipContext.markDone()
        removeClipStrip()
    }
}

// MARK: - ToolbarDelegate

extension GlyfKeyboardViewController: ToolbarDelegate {

    func toolbarGlyfTapped() {
        setSurface(surface == .shell ? .none : .shell)
    }

    func toolbarItemTapped(_ id: String) {
        openTool(id)
    }

    /// Every tool opens the same way from the strip and from the g menu. A
    /// strip or route that still says Emoji, Keys or Shorthand opens what
    /// took them in: GIFs, My glyfs and the vault.
    private func openTool(_ requested: String) {
        let id = GlyfSettings.Toolbar.canonical(requested)
        switch id {
        case "search": setSurface(.search)
        case "clipboard": setSurface(.clipboard)
        // The emoji board opens on Emoji from its own key; from the menu it
        // opens on GIFs, with Stickers beside it.
        case "gifs":
            setSurface(.emoji)
            emoji?.setMode(.gifs, animated: false)
        // Rewrite is the website's list of versions for what is typed; with
        // nothing typed there is nothing to rewrite, so it asks instead.
        case "rewrite":
            let before = beforeContext ?? ""
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            if (before + after).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setSurface(.none); openBar(autoRun: nil)
            } else {
                startAct(before: before, after: after, intent: "rewrite")
            }
        case "translate": setSurface(.none); toggleTranslateHUD()
        case "ask": setSurface(.none); openBar(autoRun: nil)
        case "dictation": setSurface(.none); startDictationHandoff()
        // Paying is signed in the app's wallet, never in the keyboard.
        // Paying stays in the keyboard; only the signature is Phantom's.
        case "pay":
            pendingPay = .send(to: nil, amount: nil, token: nil)
            setSurface(.pay)
        case "calendar": setSurface(.connector("calendar"))
        case "games": setSurface(.games)
        case "vault", "glyfs", "settings", "tempmail":
            if surface != .shell { setSurface(.shell) }
            shell?.push(id)
        default: break
        }
    }

    func toolbarItemLongPressed(_ id: String) {
        // Superseded by the drag gesture; kept so a plain hold with no drag
        // still opens the place where the strip is edited by hand.
        setSurface(.shell)
        shell?.push(id == "settings" ? "settings" : "toolbar")
    }

    // MARK: Strip customising (hold a tool, drag it)

    func toolbarItemDragBegan(_ id: String, at windowPoint: CGPoint) {
        beginToolDrag(id: id, icon: GlyfToolbar.icons[id] ?? "square", at: windowPoint)
    }

    func toolbarItemDragMoved(to windowPoint: CGPoint) { moveToolDrag(to: windowPoint) }

    func toolbarItemDragEnded(_ id: String, at windowPoint: CGPoint) {
        let inStrip = toolbarContains(windowPoint)
        endToolDrag()
        SettingsStore.update { s in
            s.toolbarOrder.removeAll { $0 == id }
            if inStrip {
                let idx = min(max(0, toolbar.dropIndex(for: toolbar.convert(windowPoint, from: nil))),
                              s.toolbarOrder.count)
                s.toolbarOrder.insert(id, at: idx)
                s.toolbarHidden.removeAll { $0 == id }
            } else {
                // Dragged off the strip: put it away, findable in the g menu.
                if !s.toolbarHidden.contains(id) { s.toolbarHidden.append(id) }
                s.toolbarOrder.append(id)
            }
        }
        toolbar.reloadItems()
        if !inStrip { KeyboardToast.show(in: content, text: "Removed from the strip") }
    }

    func shellTileDragBegan(_ id: String, icon: String, at windowPoint: CGPoint) {
        beginToolDrag(id: id, icon: GlyfToolbar.icons[id] ?? icon, at: windowPoint)
    }

    func shellTileDragMoved(to windowPoint: CGPoint) { moveToolDrag(to: windowPoint) }

    func shellTileDragEnded(at windowPoint: CGPoint) {
        guard let id = draggingToolId else { return }
        let inStrip = toolbarContains(windowPoint)
        endToolDrag()
        guard inStrip else { return }
        SettingsStore.update { s in
            s.toolbarHidden.removeAll { $0 == id }
            s.toolbarOrder.removeAll { $0 == id }
            let idx = min(max(0, toolbar.dropIndex(for: toolbar.convert(windowPoint, from: nil))),
                          s.toolbarOrder.count)
            s.toolbarOrder.insert(id, at: idx)
        }
        toolbar.reloadItems()
        setSurface(.none)
        KeyboardToast.show(in: content, text: "Added to the strip")
    }

    private func beginToolDrag(id: String, icon: String, at windowPoint: CGPoint) {
        draggingToolId = id
        let ghost = UIImageView(image: UIImage(systemName: icon))
        ghost.preferredSymbolConfiguration = .init(pointSize: 22, weight: .regular)
        ghost.tintColor = Glass.textPrimary
        ghost.contentMode = .center
        ghost.backgroundColor = Glass.surfaceCard
        ghost.layer.cornerRadius = 12
        ghost.layer.cornerCurve = .continuous
        ghost.layer.shadowColor = UIColor.black.cgColor
        ghost.layer.shadowOpacity = 0.18
        ghost.layer.shadowRadius = 8
        ghost.layer.shadowOffset = CGSize(width: 0, height: 3)
        ghost.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        ghost.center = content.convert(windowPoint, from: nil)
        content.addSubview(ghost)
        dragGhost = ghost
        moveToolDrag(to: windowPoint)
    }

    private func moveToolDrag(to windowPoint: CGPoint) {
        dragGhost?.center = content.convert(windowPoint, from: nil)
        toolbar.showDropMarker(at: toolbarContains(windowPoint)
                               ? toolbar.convert(windowPoint, from: nil) : nil)
    }

    private func endToolDrag() {
        dragGhost?.removeFromSuperview()
        dragGhost = nil
        draggingToolId = nil
        toolbar.showDropMarker(at: nil)
    }

    private func toolbarContains(_ windowPoint: CGPoint) -> Bool {
        let p = toolbar.convert(windowPoint, from: nil)
        return toolbar.bounds.insetBy(dx: -8, dy: -10).contains(p)
    }

    /// The strip's close button: whatever panel is open goes away.
    func toolbarBackTapped() {
        shell?.back()
    }

    func toolbarCloseTapped() {
        setSurface(.none)
    }

    /// The ✕ on a clipboard chip. The copy is not wanted here, so it is
    /// marked done and never offered again — it is still in the clipboard
    /// panel if it turns out it was wanted after all.
    func toolbarSmartDismissed() {
        if case .tempMail? = toolbar.smartChip {
            // Each mail's chip shows once: put away, it is gone.
            mailChip = nil
            toolbar.showSmart(nil)
            updateCandidates()
            return
        }
        if toolbar.smartIsPaste {
            ClipContext.markDone()
            // The paste probe keeps its copy for a second: forget it too, or
            // the chip comes straight back until the next key.
            cachedPaste = nil
            lastClipProbe = 0
        } else {
            // Any other chip (a sum, money, an AI answer, a detail, a plan)
            // stays gone for this text; the next change can bring one back.
            dismissedTail = (beforeContext ?? "").suffix(120).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        suggestedChip = nil
        suggestedFor = ""
        toolbar.showSmart(nil)
        updateCandidates()
    }

    func toolbarSmartTapped(_ chip: Smart.Chip) {
        switch chip {
        case .tempMail(let id, _, let code):
            mailChip = nil
            toolbar.showSmart(nil)
            if let code {
                // Only the code: that is what the field is waiting for.
                hostInsert(code)
                syncAutoShift()
                updateCandidates()
            } else {
                // No code: the panel, on that mail.
                TempMailWatcher.shared.openedId = id
                setSurface(.shell)
                shell?.push("tempmail")
                shell?.push("tempmail:mail")
            }
            return
        case .tempAddress:
            toolbar.showSmart(nil)
            useTempAddress()
            return
        default:
            break
        }
        if case .action(_, _, let intent) = chip {
            suggestedChip = nil
            suggestedFor = ""
            toolbar.showSmart(nil)
            // The chip is about what was typed: act on that sentence, the way
            // holding space does, and do what the chip said. Re-reading a
            // rewritten query could land somewhere else (a Google link for
            // "Tidy this up").
            startAct(before: beforeContext ?? "",
                     after: textDocumentProxy.documentContextAfterInput ?? "",
                     intent: intent)
            return
        }
        if case .booking(let link) = chip {
            // Their page, with the person's own details ready to book.
            toolbar.showSmart(nil)
            setSurface(.connector("calendar"))
            calendarView?.openBooking(link: link)
            return
        }
        if case .event(let plan) = chip {
            // Nothing is typed: the plan becomes a New Event to check and add.
            toolbar.showSmart(nil)
            setSurface(.connector("calendar"))
            calendarView?.compose(plan: plan)
            return
        }
        switch chip {
        case .pay(_, _, _, let copied?), .buy(_, _, _, let copied?):
            // A copied address pastes, like any copy; Send or Buy is the
            // button beside it.
            ClipContext.markDone()
            hostInsert(Self.spaced(copied, after: beforeContext))
            toolbar.showSmart(nil)
            updateCandidates()
            return
        case .pay, .buy:
            toolbarSmartExtraTapped(chip)
            return
        default:
            break
        }
        if case .paste(let text) = chip {
            // History's copy types straight out; the placeholder means we do
            // not have the text yet, so the tap is the intent that reads it.
            ClipContext.markDone()
            if text == "Tap to paste what you copied" {
                ClipboardStore.readCopy { [weak self] read in
                    guard let self else { return }
                    guard let read, !read.isEmpty else {
                        self.toolbar.showSmart(nil)
                        return
                    }
                    self.remember(copied: read)
                    self.hostInsert(Self.spaced(read, after: self.beforeContext))
                    self.toolbar.showSmart(nil)
                    self.updateCandidates()
                }
                return
            } else {
                hostInsert(Self.spaced(text, after: beforeContext))
            }
        } else {
            hostInsert(chip.insert)
        }
        toolbar.showSmart(nil)
        updateCandidates()
    }

    func toolbarSuggestionTapped(_ suggestion: GlyfToolbar.Suggestion) {
        let before = beforeContext
        let word = WordTracker.currentWord(beforeContext: before)
        let previous = WordTracker.previousWord(beforeContext: before)
        let policy = typingPolicy
        switch suggestion.kind {
        case .undo:
            undoLastCorrection()
        case .literal:
            // Exactly what they typed, on purpose: keep it and never fix it.
            typing?.keep(word)
            typing?.commit(word: word, previous: previous, autoCapitalized: false, policy: policy)
            hostInsert(" ")
        case .correction, .word:
            if !word.isEmpty { replaceCurrentWord(with: suggestion.text) }
            hostInsert(word.isEmpty ? suggestion.text + " " : " ")
            typing?.commit(word: suggestion.text, previous: previous, autoCapitalized: false, policy: policy)
        }
        TypingStore.shared.scheduleSave()
        wordTouches = []
        wordTouchesFor = ""
        syncAutoShift()
        updateCandidates()
    }

    /// Send and Buy stay in the keyboard: the chip opens the pay strip over
    /// the keys, and only the signature leaves for Phantom (through the app,
    /// the one hop iOS allows). A copy that was used this way must not bring
    /// its chip back on every empty field until something else is copied.
    /// The tour still practises on the app's sheet, never for real.
    func toolbarSmartExtraTapped(_ chip: Smart.Chip) {
        switch chip {
        case .pay(let address, let amount, let token, _):
            ClipContext.markDone()
            cachedPaste = nil
            if tourStep != nil {
                var query = ["to": address]
                if let amount { query["amount"] = amount }
                if let token { query["token"] = token }
                openApp(path: "wallet", query: query)
                toolbar.showSmart(nil)
                return
            }
            pendingPay = .send(to: address, amount: amount, token: token)
        case .buy(let mint, let symbol, let price, _):
            ClipContext.markDone()
            cachedPaste = nil
            pendingPay = .buy(mint: mint, symbol: symbol, price: price)
        case .vault(let f) where f.kind == "email":
            // "Temp", beside your own email in an email field.
            toolbar.showSmart(nil)
            useTempAddress()
            return
        case .money(let shown, _, let mint?):
            // "1 SOL = $121.39": the ticker and its price, off the chip.
            let parts = shown.split(separator: " ")
            pendingPay = .buy(mint: mint,
                              symbol: parts.count > 1 ? String(parts[1]) : "",
                              price: parts.count > 3 ? String(parts[3]) : nil)
        default:
            return
        }
        setSurface(.pay)
    }

    /// An email field's temp address: the live one, or a new one, typed in
    /// and watched from now.
    private func useTempAddress() {
        let watcher = TempMailWatcher.shared
        if let live = watcher.address {
            hostInsert(live)
            watcher.restartWatch()
            updateCandidates()
            return
        }
        watcher.create { [weak self] address in
            guard let self, let address else { return }
            self.hostInsert(address)
            self.updateCandidates()
        }
    }

    /// glyf://open?path=… with the path and its query as ONE encoded value,
    /// so "wallet?to=…&amount=5" arrives whole (a bare & cut the amount off).
    private func openApp(path: String, query: [String: String] = [:]) {
        var inner = path
        if !query.isEmpty {
            inner += "?" + query.keys.sorted().map { "\($0)=\(Self.urlEncoded(query[$0] ?? ""))" }
                .joined(separator: "&")
        }
        guard let url = URL(string: "glyf://open?path=\(Self.urlEncoded(inner))") else { return }
        HostAppOpener.open(url, from: self) { _ in }
    }

    private static let urlSafe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func urlEncoded(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: urlSafe) ?? s
    }

    // MARK: Dictation (§6.6 path 1: in-app capture + handoff via §7 intents)

    private func startDictationHandoff() {
        guard !isSecureField else { return } // §11.9
        guard let intent = IntentStore.shared.createIntent(
            kind: "dictation", source: "glyf") else { return }
        guard let url = URL(string: "glyf://intent?id=\(intent.id)") else { return }
        HostAppOpener.open(url, from: self) { [weak self] strategy in
            guard let self else { return }
            if strategy == .none {
                // M0 fallback UX: the intent is already in the App Group —
                // manual app launch picks it up.
                KeyboardToast.show(in: self.content, text: "Open the Glyf app to record")
            }
        }
    }

    /// On return from the app: insert the finished dictation exactly once.
    /// The keyboard can appear against a DEAD placeholder session while the
    /// host app is still launching — inserts vanish there. So: insert, VERIFY
    /// the document actually took it, and only then consume the handoff
    /// (§7.3 single-use). textDidChange retries when the real session attaches.
    private func deliverPendingResult() {
        guard !deliveryInFlight else { return }
        guard let intent = IntentStore.shared.pendingIntent(),
              intent.kind == "dictation",
              let result = IntentStore.shared.readResult(intentId: intent.id),
              result.status == "success",
              let transcript = result.payload["transcript"], !transcript.isEmpty,
              !isSecureField
        else { return }

        // TAKE-ONCE, INSERT-ONCE. Retries are categorically unsafe: an insert
        // that looks lost may be BUFFERED by a detaching session and flush
        // later, doubling the text. One consume, one insert (§7.3).
        deliveryInFlight = true
        guard IntentStore.shared.takeResultForPending() != nil else {
            deliveryInFlight = false
            return
        }
        hostInsert(transcript)
        log.log("GLYF_DICT delivered chars=\(transcript.count)")
        KeyboardToast.show(in: content, text: "Dictation inserted")
        syncAutoShift()
        updateCandidates()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.deliveryInFlight = false
        }
    }
}

// MARK: - GlyfShellDelegate

extension GlyfKeyboardViewController: GlyfShellDelegate {

    func shellClosed() {
        setSurface(.none)
        keyboardView.rebuild()
        toolbar.reloadItems()
    }

    func shellInsertText(_ text: String) {
        setSurface(.none)
        hostInsert(text)
    }

    func shellOpenApp(path: String) {
        openApp(path: path)
    }

    func shellStateChanged() {
        // A setting changed under the menu: appearance and one-handed re-skin
        // the keys, the number row changes the height. All of it lands now,
        // not the next time the keyboard comes up.
        resolveAppearance()
        keyboardView.rebuild()
        keyboardView.refreshBindings()
        if heightConstraint?.constant != totalHeight { applySurfaceLayout(animated: true) }
        toolbar.reloadItems()
        // The strip shows which panel screen is open.
        let header = panelHeader()
        lastPanelTitle = .some(header.1)
        toolbar.showPanelHeader(icon: header.0, title: header.1,
                                canGoBack: shell?.canGoBack == true,
                                keepTools: shellAtMenu)
    }

    func shellOpenSearch() {
        setSurface(.search)
    }

    /// The website's translate: a strip over live keys, not a panel.
    func toggleTranslateHUD() {
        let on = !(SettingsStore.current.translationHUD ?? false)
        SettingsStore.update { $0.translationHUD = on }
        applySurfaceLayout(animated: true)
        if on {
            hud?.refreshTarget()
            notifyHUD()
        }
    }

    func shellOpenTool(_ id: String) {
        openTool(id)
    }

    func shellRunGlyf(_ id: String) {
        setSurface(.none)
        // The HUD shows the letter the glyf sits on; one with no key wears the g.
        let letter = SettingsStore.current.bindings.first { $0.value == id }?.key ?? ""
        startSkill(glyfId: id, letter: letter)
    }

    func shellEditNote(id: String?, text: String) {
        pendingEdit = .note(id: id, text: text)
        setSurface(.noteEdit)
    }

    func shellAddDetail(_ kind: DetailKind) {
        pendingEdit = .detail(kind)
        setSurface(.noteEdit)
    }

    func shellAddShorthand() {
        pendingEdit = .shorthand
        setSurface(.noteEdit)
    }

    func shellRunKey(_ letter: String) {
        guard let target = SettingsStore.current.bindings[letter] else { return }
        runBinding(target, letter: letter)
    }

    func shellCopyImage(id: String) {
        guard let data = VaultStore.shared.imageData(id: id),
              let image = UIImage(data: data) else {
            KeyboardToast.show(in: content, text: "That image could not be opened")
            return
        }
        UIPasteboard.general.image = image
        setSurface(.none)
        KeyboardToast.show(in: content, text: "Copied. Hold the text box to paste")
    }

    func shellCopyText(_ text: String) {
        UIPasteboard.general.string = text
        // Our own copy: the strip must not offer it back as a paste.
        ClipboardStore.ignoreNextChange()
        KeyboardToast.show(in: content, text: "Copied")
    }
}

// MARK: - GlyfBarDelegate

extension GlyfKeyboardViewController: GlyfBarDelegate {

    func barClosed() {
        setSurface(.none)
    }

    func barRun(glyfId: String, vars: [String: String], title: String, input: GlyfBar.Input) {
        inlineTarget = nil
        runFromBar(glyfId: glyfId, vars: vars, title: title, input: input)
    }

    func barOpenApp() {
        setSurface(.none)
        openApp(path: "home")
    }

    func barHeightChanged() {
        applySurfaceLayout(animated: true)
    }

    func barPromptActivated(_ editor: InlineEditor) {
        inlineTarget = editor
    }

    func barNeedsRunsRefresh() {
        toolbar.setRunsRemaining(GlyfCatalog.cachedRunsRemaining())
    }
}

// MARK: - SearchSurfaceDelegate

extension GlyfKeyboardViewController: SearchSurfaceDelegate {

    func searchActivated(_ editor: InlineEditor) {
        inlineTarget = editor
        keyboardView.syncAutoShift(wantsCapital: false)
    }

    func searchInsert(_ text: String) {
        // Bypass the inline editor — results land in the host field.
        let target = inlineTarget
        inlineTarget = nil
        hostInsert(Self.spaced(text, after: beforeContext))
        inlineTarget = target
    }

    /// A pasted card or contact must not weld itself onto the word before
    /// the caret ("...ooSunset is at" was what a tap gave).
    static func spaced(_ text: String, after before: String?) -> String {
        guard let last = before?.last, !last.isWhitespace, !last.isNewline else { return text }
        return " " + text
    }

    func searchOpenTranslate() {
        setSurface(.none)
        openBar(autoRun: "glyf.translate")
    }

    func searchClosed() {
        inlineTarget = nil
        setSurface(.none)
    }

    func searchLayoutChanged() {
        applySurfaceLayout(animated: true)
    }
}

// MARK: - NoteEditSurfaceDelegate

extension GlyfKeyboardViewController: NoteEditSurfaceDelegate {

    func noteEditActivated(_ editor: InlineEditor) {
        inlineTarget = editor
        // A shortcut or an email starts in lowercase, whatever capital the
        // message field was about to get; a note or a name starts with one.
        keyboardView.syncAutoShift(wantsCapital: noteEdit?.startsWithCapital ?? false)
    }

    /// Saved or not, back to the vault it was opened from, where what was
    /// just added shows.
    func noteEditSaved() {
        inlineTarget = nil
        setSurface(.shell)
        shell?.push("vault")
    }

    func noteEditClosed() {
        inlineTarget = nil
        setSurface(.shell)
        shell?.push("vault")
    }
}

// MARK: - EmojiBoardDelegate

extension GlyfKeyboardViewController: EmojiBoardDelegate {

    func emojiPicked(_ emoji: String) {
        hostInsert(emoji)
    }

    func emojiBackToLetters() {
        setSurface(.none)
    }

    func emojiDeleteBackward() {
        hostDelete()
        syncAutoShift()
        updateCandidates()
    }

    func emojiBoardClosed() {
        inlineTarget = nil
        setSurface(.none)
    }

    func emojiLayoutChanged() {
        applySurfaceLayout(animated: true)
    }

    func emojiSearchDismissed() {
        inlineTarget = nil
    }

    func emojiSearchActivated(_ editor: InlineEditor) {
        inlineTarget = editor
        // Apple's emoji search starts in lowercase, whatever capital the
        // message field was about to get.
        keyboardView.syncAutoShift(wantsCapital: false)
    }

    var emojiBoardHasFullAccess: Bool { hasFullAccess }

    func emojiBoardType(_ text: String) {
        // ":-)" is a word of its own: glued to the one before it reads as
        // "later:-)". Emoji need no space; emoticons do.
        hostInsert(Self.spaced(text, after: beforeContext))
        syncAutoShift()
        updateCandidates()
    }

    /// No keyboard can type a picture into another app, so a GIF or sticker
    /// goes on the pasteboard and the person pastes it, which is how Gboard
    /// for iPhone does it. The board stays up for the next one.
    func emojiBoardSend(_ item: MediaItem, kind: MediaKind, done: @escaping (Bool) -> Void) {
        let noun = kind == .gifs ? "GIF" : "Sticker"
        guard hasFullAccess else {
            KeyboardToast.show(in: content, text: "Turn on Full Access to send a \(noun.lowercased())")
            done(false)
            return
        }
        MediaClient.shared.fullData(item.url) { [weak self] data in
            guard let self else { return }
            guard let data, MediaClient.copyToPasteboard(data) else {
                KeyboardToast.show(in: self.content, text: "That \(noun.lowercased()) didn't download. Try again")
                done(false)
                return
            }
            ClipboardStore.ignoreNextChange()
            MediaRecents.push(item, kind: kind)
            KeyboardToast.show(in: self.content, text: "\(noun) copied. Hold the text box and tap Paste")
            done(true)
        }
    }
}

// MARK: - TranslationHUDDelegate (§6.13 T)

extension GlyfKeyboardViewController: TranslationHUDDelegate {

    func hudRequestTranslation(of text: String, target: String?,
                               completion: @escaping (BackendClient.Translation?) -> Void) {
        guard hasFullAccess, !isSecureField else { completion(nil); return }
        BackendClient.shared.translate(text: text, target: target, completion: completion)
    }

    func hudReplaceDraft(with text: String, replacing span: String) {
        // Only what was translated goes, and only if it is still what ends
        // the text: typing since then, or a longer draft, stays untouched.
        guard !span.isEmpty, (beforeContext ?? "").hasSuffix(span) else {
            KeyboardToast.show(in: content, text: "The text changed since the translation")
            return
        }
        for _ in 0..<span.count { hostDelete() }
        hostInsert(text)
        syncAutoShift()
        updateCandidates()
    }

    func hudClosed() {
        SettingsStore.update { $0.translationHUD = false }
        applySurfaceLayout(animated: true)
    }
}

// MARK: - TonesPopupDelegate (§6.13 R)

extension GlyfKeyboardViewController: TonesPopupDelegate {

    func tonesPicked(_ tone: String) {
        dismissTonesPopup()
        openBar(autoRun: "rewrite.tone", vars: ["tone": tone])
    }

    func tonesClosed() {
        dismissTonesPopup()
    }
}

// MARK: - ConnectorSurfaceDelegate (§6.12 C)

extension GlyfKeyboardViewController: ConnectorSurfaceDelegate {

    func connectorInsert(_ text: String) {
        setSurface(.none)
        hostInsert(Self.spaced(text, after: beforeContext))
        syncAutoShift()
        updateCandidates()
    }

    func connectorClosed() {
        setSurface(.none)
    }

    func connectorToast(_ text: String) {
        KeyboardToast.show(in: content, text: text)
    }

    func connectorSearchActivated(_ editor: InlineEditor) {
        inlineTarget = editor
    }

    func connectorLayoutChanged() {
        applySurfaceLayout(animated: true)
    }

    func connectorSearchDismissed() {
        inlineTarget = nil
    }

    func connectorOpenApp(path: String) {
        openApp(path: path)
    }
}

// MARK: - PaySurfaceDelegate

extension GlyfKeyboardViewController: PaySurfaceDelegate {

    /// The panel and its amount strip trade places: the keys come up on
    /// the digits while the amount is typed, and leave again after.
    func payLayoutChanged() {
        guard surface == .pay else { return }
        let editor = pay?.activeEditor
        inlineTarget = editor
        pay?.amountEditor.isActive = editor != nil
        keyboardView.setMode(editor != nil ? .symbols1 : .letters)
        applySurfaceLayout(animated: true)
    }

    /// The one hop iOS forces: the app opens, builds the payment and opens
    /// Phantom at once; the keyboard is back on the keys for the return.
    func payHandOff(query: [String: String]) {
        setSurface(.none)
        openApp(path: "pay", query: query)
    }

    func payConnect() {
        setSurface(.none)
        openApp(path: "wallet")
    }

    func payToast(_ text: String) {
        KeyboardToast.show(in: content, text: text)
    }
}
