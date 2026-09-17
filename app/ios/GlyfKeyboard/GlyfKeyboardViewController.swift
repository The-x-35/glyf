import UIKit
import os.log

/// iOS grants keyboard extensions arbitrary (often cached, oversized) heights
/// and ignores height constraints — an Apple-acknowledged issue with no
/// sanctioned fix. This root makes the granted size irrelevant: the real
/// keyboard is BOTTOM-ANCHORED at exactly its designed height, everything
/// above is transparent, and touches up there fall through to the host app.
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
    private var actSkill: (glyfId: String, letter: String)?
    /// What a suggestion chip promised to do; nil lets the server decide.
    private var actIntent: String?
    /// The text the run reads (field text, or the clipboard for a skill).
    private var actRunInput = ""
    private var actHasResult = false
    private var actAccepted = false
    private var emoji: EmojiBoard?
    /// Gboard's clipboard: its own header, pinned and recent as card columns.
    private var clipboardPanel: ClipboardPanel?
    private var connector: ConnectorSurface?
    /// The Calendar tool: a month and the chosen day's events.
    private var calendarView: CalendarSurface?
    private var search: SearchSurface?
    private var noteEdit: NoteEditSurface?
    private var pendingNote: (id: String?, text: String)?
    /// §6.13 T — persistent strip above the toolbar while enabled.
    private var hud: TranslationHUD?
    /// §6.13 R — transient overlay over the keys, not a Surface.
    private var tonesPopup: TonesPopup?
    /// §6.15: did the user act on the bar's result (Replace/Insert/Copy)?
    private var barAccepted = false
    /// Text around the cursor, mirrored for the length of a space-bar glide.
    private var cursorMirror: CursorMirror?
    private var lastCursorAdjust: CFTimeInterval = 0

    private enum Surface: Equatable { case none, shell, bar, emoji, connector(String), search, noteEdit, act, clipboard }
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
    }
    private var lastCorrection: Correction?
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
        // The key region is the system keyboard's own, which is taller on
        // Plus/Max-class phones — never a number baked in for one device.
        let w = view.bounds.width > 0 ? view.bounds.width
                                      : UIScreen.main.bounds.width
        let base = Glass.keysHeight(width: w)
        return SettingsStore.current.numberRow ? base + Glass.numberRowExtra : base
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
        case .bar:
            return bar?.expandedForResult == true ? base : base + Glass.barExtra
        // While typing a query the keys stay live under a strip; results
        // become a panel over the keys.
        case .search:
            return search?.expandedForResults == true
                ? base : base + Glass.barExtra + (search?.landingExtra ?? 0)
        case .noteEdit: return base + NoteEditSurface.stripHeight
        case .shell, .connector, .act, .clipboard: return base
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
    }

    /// Apple behavior: the keyboard follows the HOST (field appearance /
    /// system style), unless the user forces light or dark in settings.
    private func resolveAppearance() {
        let pref = SettingsStore.current.appearance ?? "auto"
        // The host's keyboardAppearance is resolved once, when the field
        // takes focus: Messages opened in dark mode keeps reporting .dark
        // after the phone switches to light. The trait (which the system
        // sheet follows) does change, so after a live flip it wins.
        let traitDark = traitCollection.userInterfaceStyle == .dark
        let hostDark = appearanceFlipped
            ? traitDark
            : textDocumentProxy.keyboardAppearance == .dark || traitDark
        let dark = pref == "dark" || (pref == "auto" && hostDark)
        let theme = SettingsStore.current.keyTheme ?? "glass"
        let bg = SettingsStore.current.themeBg ?? ""
        let borders = SettingsStore.current.keyBorders ?? false
        let dim = SettingsStore.current.themeBrightness ?? 0
        overrideUserInterfaceStyle =
            pref == "light" ? .light : pref == "dark" ? .dark : .unspecified
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

    /// Re-skins the long-lived chrome after an appearance flip; transient
    /// surfaces pick the palette up on their next open.
    private func refreshPalette() {
        guard didBuild else { return }
        toolbar.applyPalette()
        keyboardView.rebuild()
    }

    /// Set once light/dark changes while the keyboard is up; cleared when it
    /// goes away, so the next field's own appearance is read fresh.
    private var appearanceFlipped = false

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard let before = previous?.userInterfaceStyle,
              before != traitCollection.userInterfaceStyle else { return }
        if before != .unspecified { appearanceFlipped = true }
        resolveAppearance()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SettingsStore.invalidate()
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
        keyboardView.needsGlobe = needsInputModeSwitchKey
        // A keyboard coming back for a field starts on the letters: a menu,
        // clipboard or answer panel left open last time would greet the next
        // field with something it never asked for.
        if didBuild, surface != .none { setSurface(.none, animated: false) }
        keyboardView.context = KeyboardContext(keyboardType: textDocumentProxy.keyboardType)
        log.log("GLYF_KB ctx autocap=\(self.textDocumentProxy.autocapitalizationType?.rawValue ?? -1) kbType=\(self.textDocumentProxy.keyboardType?.rawValue ?? -1)")
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appearanceFlipped = false
        stopTourWatch()
        TypingStore.shared.saveNow()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
    }

    private func build() {
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Bottom-anchored; the top edge floats — dead space stays clear.
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // No board of our own: iOS draws the keyboard sheet behind every
        // third-party keyboard and its margins cannot be painted, so a board
        // inside it only shows up as a second, mismatched band. The keys sit
        // on the system's sheet, in every theme (see Glass: keys on the sheet).
        backdrop = UIView()
        backdrop.backgroundColor = .clear
        backdrop.isUserInteractionEnabled = false
        backdrop.frame = content.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.addSubview(backdrop)

        toolbar.delegate = self
        content.addSubview(toolbar)

        keyboardView.delegate = self
        keyboardView.clipsToBounds = false
        content.addSubview(keyboardView)
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
        case .bar where bar?.expandedForResult == true: return ("sparkles", "Glyf")
        case .connector where connector?.searchActive != true: return ("calendar", "Calendar")
        default: return (nil, nil)
        }
    }

    /// The model's read on what is being typed, and the work in flight.
    private var suggestTask: URLSessionDataTask?
    private var suggestWork: DispatchWorkItem?
    private var suggestedFor = ""
    private var suggestedChip: Smart.Chip?

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
                    let stripH = SearchSurface.collapsedHeight + sv.landingExtra
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
        case .clipboard:
            // Gboard's clipboard owns the whole keyboard, strip included.
            toolbar.isHidden = true
            keyboardView.isHidden = true
            clipboardPanel?.frame = CGRect(x: 0, y: 0, width: w, height: h)
        case .bar:
            toolbar.isHidden = !(bar?.expandedForResult ?? false)
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            if let bar {
                if bar.expandedForResult {
                    keyboardView.isHidden = true
                    bar.frame = panelRect(w, h)
                } else {
                    keyboardView.isHidden = false
                    let barH = Glass.toolbarHeight + Glass.barExtra
                    bar.frame = CGRect(x: 0, y: 0, width: w, height: barH)
                    keyboardView.frame = CGRect(x: 0, y: barH, width: w,
                                                height: max(0, h - barH))
                }
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
                            self.clipboardPanel] as [UIView?] {
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
        case .shell: shell?.removeFromSuperview(); shell = nil
        case .bar:
            // §6.15: a result the user walked away from is a "discard" signal.
            if !barAccepted, let b = bar, b.hasResult, let id = b.lastRunGlyfId {
                ToneProfile.record(glyfId: id, accepted: false)
            }
            bar?.cancelRun(); bar?.removeFromSuperview(); bar = nil
        case .emoji: emoji?.removeFromSuperview(); emoji = nil
        case .connector:
            connector?.removeFromSuperview(); connector = nil
            calendarView?.removeFromSuperview(); calendarView = nil
        case .search: search?.cancelWork(); search?.removeFromSuperview(); search = nil
        case .noteEdit: noteEdit?.removeFromSuperview(); noteEdit = nil
        case .act:
            actTask?.cancel(); actTask = nil
            act?.removeFromSuperview(); act = nil
        case .clipboard: clipboardPanel?.removeFromSuperview(); clipboardPanel = nil
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
            barAccepted = false
            let b = GlyfBar()
            b.delegate = self
            b.onExpandChange = { [weak self] in self?.applySurfaceLayout(animated: true) }
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
            content.addSubview(c)
            prepareEntrance(c, animated: animated)
            clipboardPanel = c
            MemoryLogger.logSurface("clipboard")
        case .connector(let id) where id == "calendar" || id == "mockcal":
            let c = CalendarSurface()
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
            // Open on recents + trending rather than an empty box (Gboard).
            sv.presentLanding()
        case .noteEdit:
            let n = NoteEditSurface(noteId: pendingNote?.id ?? nil,
                                    text: pendingNote?.text ?? "")
            n.delegate = self
            content.addSubview(n)
            prepareEntrance(n, animated: animated)
            noteEdit = n
            inlineTarget = n.editor
            n.editor.isActive = true
        case .act:
            let a = ActSurface()
            a.delegate = self
            content.addSubview(a)
            prepareEntrance(a, animated: animated)
            act = a
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
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        ensureHUD().draftChanged(before, consumedBefore: before.count)
    }

    // MARK: Tones popup (§6.13 R)

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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // The app may have changed settings while we are up (its tour does).
        if SettingsStore.reloadIfChanged() { keyboardView.refreshBindings() }
        // Field flavor can change per focus (email → number pad → text).
        keyboardView.context = KeyboardContext(keyboardType: textDocumentProxy.keyboardType)
        syncAutoShift()
        updateCandidates()
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
        tourTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.applyTourHint()
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
            // A new step, or the address just copied, changes which chips
            // the strip may show.
            coachedStep = arranged
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
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
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
        case .noteEdit:
            return .other(close: "noteedit:close")
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
            typeForTour(text, append: { [weak self] in self?.textDocumentProxy.insertText($0) }) { [weak self] in
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

    private func syncAutoShift() {
        // Respect the FIELD's capitalization type like the system keyboard:
        // .none fields (usernames, searches) never auto-shift.
        let wants: Bool
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: wants = false
        case .allCharacters: wants = true
        case .words:
            let before = textDocumentProxy.documentContextBeforeInput
            wants = before?.isEmpty != false || before?.hasSuffix(" ") == true
        default:
            wants = WordTracker.wantsCapital(
                beforeContext: textDocumentProxy.documentContextBeforeInput)
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
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let tail = String(before.suffix(120))
        // Something just copied rides in the strip as one chip, never as a
        // second row: history's copy when we already have it, otherwise the
        // offer itself (tapping reads, which is the moment iOS asks).
        // History only knows a copy once it has been read; a newer one shows
        // as an offer instead of the older text.
        let paste: String? = (hasFullAccess && tail.isEmpty && ClipContext.isFresh())
            ? (ClipboardStore.pasteboardHasNewContent()
                ? "Tap to paste what you copied"
                : (ClipboardStore.load().first?.text ?? "Tap to paste what you copied"))
            : nil
        var chip = Smart.chip(for: tail, fields: VaultStore.shared.load().fields,
                              paste: paste, field: fieldHint(emptyField: before.isEmpty))
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
        toolbar.showSmart(chip)
        return chip != nil
    }

    private static func chipKind(_ chip: Smart.Chip) -> String {
        switch chip {
        case .calc: return "calc"
        case .vault(let f): return "vault:\(f.kind)"
        case .paste: return "paste"
        case .pay: return "pay"
        case .action: return "action"
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
        case .URL, .webSearch: kind = "link"
        default: break
        }
        if kind == nil, proxy.autocapitalizationType == .words,
           proxy.returnKeyType == .next {
            kind = "name"
        }
        return Smart.FieldHint(kind: kind, empty: emptyField)
    }

    /// Debounced, cancellable, and never for a half-typed word: a pause of
    /// 700ms on a real sentence is the only thing that spends a request.
    private func askForSuggestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasFullAccess, !isSecureField, surface == .none,
              SettingsStore.current.candidates,
              trimmed.count >= 12, trimmed.split(separator: " ").count >= 3,
              trimmed != suggestedFor
        else { return }
        cancelSuggestion()
        let fields = VaultStore.shared.load().fields
        let kinds = SettingsStore.current.aiUsesVault == false ? [] : Array(Set(fields.map(\.kind))).sorted()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suggestTask = BackendClient.shared.suggestAction(text: trimmed, kinds: kinds) {
                [weak self] intent, label, query in
                guard let self, self.surface == .none else { return }
                let before = self.textDocumentProxy.documentContextBeforeInput ?? ""
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
        defer { applyTourHint() }         // the strip changed under the ring
        if updateSmartChip() { return }   // one chip owns the strip
        let policy = typingPolicy
        guard SettingsStore.current.candidates, policy.contains(.suggestions), surface == .none else {
            toolbar.showSuggestions([])
            return
        }
        let before = textDocumentProxy.documentContextBeforeInput
        let word = WordTracker.currentWord(beforeContext: before)
        if word.isEmpty {
            if let corr = lastCorrection {
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
        guard let s = suggestions(for: word, before: before, policy: policy) else {
            toolbar.showSuggestions([])
            return
        }
        let others = s.alternatives.map { GlyfToolbar.Suggestion(text: $0, kind: .word) }
        if let fix = s.autocorrect {
            toolbar.showSuggestions([.init(text: word, kind: .literal), .init(text: fix, kind: .correction)]
                                    + others.prefix(1))
        } else if others.isEmpty {
            toolbar.showSuggestions([])
        } else {
            toolbar.showSuggestions([.init(text: word, kind: s.known ? .word : .literal)] + others.prefix(2))
        }
    }

    private func suggestions(for word: String, before: String?, policy: TypingEngine.Policy) -> TypingEngine.Suggestions? {
        guard let engine = typing else { return nil }
        let head = String((before ?? "").dropLast(word.count))
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
        let before = textDocumentProxy.documentContextBeforeInput
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
        if policy.contains(.autocorrect),
           let fix = suggestions(for: word, before: before, policy: policy)?.autocorrect, fix != word {
            replaceCurrentWord(with: fix)
            lastCorrection = Correction(original: word, replacement: fix, fromEngine: true)
            kept = fix
        }
        let autoCapitalized = sentenceStart && SettingsStore.current.autocapitalize
            && textDocumentProxy.autocapitalizationType != UITextAutocapitalizationType.none
        engine.commit(word: kept, previous: previous, autoCapitalized: autoCapitalized, policy: policy)
        TypingStore.shared.scheduleSave()
    }

    /// Replace the word being typed (suggestions, autocorrect, replacements).
    private func replaceCurrentWord(with replacement: String) {
        let word = WordTracker.currentWord(
            beforeContext: textDocumentProxy.documentContextBeforeInput)
        for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement)
    }

    /// Put back what was typed before the last correction; an engine
    /// correction is never offered for that word again.
    @discardableResult
    private func undoLastCorrection() -> Bool {
        guard let corr = lastCorrection,
              let before = textDocumentProxy.documentContextBeforeInput else { return false }
        let tail = before.hasSuffix(corr.replacement + " ") ? corr.replacement + " "
            : before.hasSuffix(corr.replacement) ? corr.replacement : nil
        guard let tail else { return false }
        for _ in 0..<tail.count { textDocumentProxy.deleteBackward() }
        let spaced = tail.count > corr.replacement.count
        textDocumentProxy.insertText(spaced ? corr.original + " " : corr.original)
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
        if text.count == 1, let ch = text.first {
            if WordTracker.correctionBoundaries.contains(ch) {
                // Punctuation ends the word: correct it before the mark lands.
                commitCurrentWord()
            } else if !WordTracker.boundaries.contains(ch) || ch == "'" || ch == "’" {
                let current = WordTracker.currentWord(beforeContext: textDocumentProxy.documentContextBeforeInput)
                if current != wordTouchesFor {
                    wordTouches = Array(repeating: nil, count: current.unicodeScalars.count)
                }
                wordTouches.append(keyboardView.lastTapOffset)
                wordTouchesFor = current + text
            }
        }
        textDocumentProxy.insertText(text)
        syncAutoShift()
        updateCandidates()
    }

    func kbDeleteBackward() {
        if let editor = inlineTarget {
            editor.deleteBackward()
            return
        }
        // Backspace right after a correction puts back what was typed (and
        // teaches the engine to leave that word alone).
        if let corr = lastCorrection,
           textDocumentProxy.documentContextBeforeInput?.hasSuffix(corr.replacement + " ") == true {
            for _ in 0..<(corr.replacement.count + 1) { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(corr.original)
            lastCorrection = nil
            if corr.fromEngine {
                typing?.revert(typed: corr.original, correction: corr.replacement)
                TypingStore.shared.scheduleSave()
            }
        } else {
            textDocumentProxy.deleteBackward()
        }
        let current = WordTracker.currentWord(beforeContext: textDocumentProxy.documentContextBeforeInput)
        if wordTouches.count > current.unicodeScalars.count {
            wordTouches.removeLast(wordTouches.count - current.unicodeScalars.count)
        }
        wordTouchesFor = current
        syncAutoShift()
        updateCandidates()
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
           WordTracker.canPeriodShortcut(beforeContext: textDocumentProxy.documentContextBeforeInput) {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpaceTap = .distantPast
            syncAutoShift()
            updateCandidates()
            notifyHUD()
            return
        }
        lastSpaceTap = now

        // §6.7 shorthand: ;sig-style triggers expand on the space commit,
        // before autocorrect gets a look. Undo works like autocorrect undo.
        if !isSecureField,
           let token = Shorthand.pendingToken(
               beforeContext: textDocumentProxy.documentContextBeforeInput),
           let expansion = Shorthand.expansion(for: token, in: VaultStore.shared.load()) {
            for _ in 0..<token.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(expansion)
            lastCorrection = Correction(original: token, replacement: expansion, fromEngine: false)
            textDocumentProxy.insertText(" ")
            syncAutoShift()
            updateCandidates()
            notifyHUD()
            return
        }

        // Autocorrect + learning on commit (§6.1, Engine/Typing) — the
        // policy keeps secure fields untouched (§11.9).
        commitCurrentWord()
        textDocumentProxy.insertText(" ")
        syncAutoShift()
        updateCandidates()
        notifyHUD()
    }

    func kbReturnTapped() {
        if inlineTarget != nil, surface == .search {
            // Return = run the search (Gboard parity); the query stays live.
            search?.submit()
            return
        }
        if inlineTarget != nil, surface == .emoji {
            // Return = done searching; the full grid comes back.
            emoji?.exitSearch()
            return
        }
        if inlineTarget != nil, case .connector = surface {
            connector?.exitSearch()
            return
        }
        if let editor = inlineTarget, surface == .noteEdit {
            editor.append("\n")
            return
        }
        if let editor = inlineTarget {
            editor.isActive = false
            inlineTarget = nil
            return
        }
        commitCurrentWord()
        textDocumentProxy.insertText("\n")
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
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        lastCursorAdjust = CACurrentMediaTime()
    }

    func kbSpaceGestures() -> (glide: Bool, bar: Bool) {
        (glide: inlineTarget == nil, bar: inlineTarget == nil && !isSecureField)
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
        CursorMirror(before: textDocumentProxy.documentContextBeforeInput ?? "",
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
            let before = self.textDocumentProxy.documentContextBeforeInput ?? ""
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

    private func startAct(clipboard text: String) {
        actSkill = nil
        actIntent = nil
        actInput = ("", "") // a copied text is acted on, never deleted from the field
        actRunInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        actAccepted = false
        setSurface(.act)
        runAct()
    }

    private func startAct(before: String, after: String, intent: String? = nil) {
        actSkill = nil
        actIntent = intent
        actInput = (before, after)
        actRunInput = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        actAccepted = false
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
        actRunInput = input.text
        // Field text is swapped on Insert; clipboard or empty input only inserts.
        actInput = input.source == "field"
            ? (textDocumentProxy.documentContextBeforeInput ?? "", input.after) : ("", "")
        actAccepted = false
        setSurface(.act)
        runAct()
    }

    private func runAct() {
        guard let act else { return }
        actTask?.cancel()
        actHasResult = false
        if let skill = actSkill {
            let title = GlyfCatalog.title(for: skill.glyfId)
            act.showWorking(intent: actRunInput, title: title, keyLetter: skill.letter)
            var vars: [String: String] = [:]
            if skill.glyfId == "glyf.translate" {
                vars["target"] = SettingsStore.current.translateTarget
            }
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
                    self.act?.showFailure(message)
                })
            return
        }
        act.showWorking(intent: actRunInput)
        actTask = BackendClient.shared.runAct(text: actRunInput, intent: actIntent,
                                              onResult: { [weak self] result in
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
            self.act?.showFailure(message)
        })
    }

    func kbBoundKeyIgnited(keyId: String, glyfId: String, origin: KeyView) {
        let delay = Glass.reduceMotion ? Glass.Ripple.reducedMotionFlash
                                       : Glass.Ripple.surfaceRiseDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            switch glyfId {
            case "surface:translate-hud":
                // §6.13 T toggles the persistent strip on/off.
                let on = !(SettingsStore.current.translationHUD ?? false)
                SettingsStore.update { $0.translationHUD = on }
                self.applySurfaceLayout(animated: true)
                if on {
                    self.hud?.refreshTarget()
                    self.notifyHUD()
                } else {
                    KeyboardToast.show(in: self.content, text: "Translate off")
                }
            case "surface:tones":
                self.showTonesPopup()
            case let id where id.hasPrefix("surface:"):
                // Other "surface:" bindings open shell screens (M4: S → vault).
                self.setSurface(.shell)
                self.shell?.push(String(id.dropFirst("surface:".count)))
            case let id where id.hasPrefix("connector:"):
                // §6.12 C — the ConnectorSurface picker.
                self.setSurface(.connector(String(id.dropFirst("connector:".count))))
            default:
                self.startSkill(glyfId: glyfId, letter: keyId)
            }
        }
    }

    func kbTextInteraction() {}

    // MARK: Bar

    private func openBar(autoRun: String?, vars: [String: String] = [:]) {
        guard !isSecureField else { return } // §11.9: no AI in secure fields
        setSurface(.bar)
        let input = collectBarInput()
        bar?.present(input: input, hasFullAccess: hasFullAccess)
        if let glyfId = autoRun {
            bar?.autoRun(glyfId: glyfId, vars: vars)
        }
    }

    private func collectBarInput() -> GlyfBar.Input {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let field = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        if !field.isEmpty {
            return GlyfBar.Input(text: before + after, source: "field",
                                 consumedBefore: before.count, after: after)
        }
        if hasFullAccess {
            ClipboardStore.captureNow() // user opened the bar with no draft
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
                textDocumentProxy.adjustTextPosition(byCharacterOffset: input.after.utf16.count)
            }
            for _ in 0..<(input.before.count + input.after.count) {
                textDocumentProxy.deleteBackward()
            }
        }
        textDocumentProxy.insertText(text)
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
        textDocumentProxy.insertText(text)
        updateCandidates()
    }

    func clipboardPanelPasteFresh() {
        setSurface(.none)
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ClipContext.markDone()
        remember(copied: text)
        textDocumentProxy.insertText(text)
        updateCandidates()
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
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ClipContext.markDone()
            removeClipStrip()
            return
        }
        remember(copied: text)
        clipStrip?.show(text: text)
    }

    /// Everything that arrives from the pasteboard lands in history first, so
    /// "what I copied earlier" is there even after the copy itself is gone.
    private func remember(copied text: String) {
        _ = ClipboardStore.inserting(text, into: ClipboardStore.load(), now: Date())
            .map(ClipboardStore.save)
    }

    func clipStripPaste() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ClipContext.markDone()
            removeClipStrip()
            return
        }
        remember(copied: text)
        ClipContext.markDone()
        removeClipStrip()
        textDocumentProxy.insertText(text)
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

    /// Every tool opens the same way from the strip and from the g menu.
    private func openTool(_ id: String) {
        switch id {
        case "search": setSurface(.search)
        case "clipboard": setSurface(.clipboard)
        case "emoji": setSurface(.emoji)
        // Rewrite is the website's list of versions for what is typed; with
        // nothing typed there is nothing to rewrite, so it asks instead.
        case "rewrite":
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
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
        case "pay": setSurface(.none); openApp(path: "wallet")
        case "calendar": setSurface(.connector("calendar"))
        case "vault", "glyfs", "shorthand", "keys", "settings":
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

    func toolbarSmartTapped(_ chip: Smart.Chip) {
        if case .action(_, _, let intent) = chip {
            suggestedChip = nil
            suggestedFor = ""
            toolbar.showSmart(nil)
            // The chip is about what was typed: act on that sentence, the way
            // holding space does, and do what the chip said. Re-reading a
            // rewritten query could land somewhere else (a Google link for
            // "Tidy this up").
            startAct(before: textDocumentProxy.documentContextBeforeInput ?? "",
                     after: textDocumentProxy.documentContextAfterInput ?? "",
                     intent: intent)
            return
        }
        if case .pay(let address, let amount) = chip {
            // The keyboard never signs: the app's Privy wallet does.
            var path = "wallet?to=\(address)"
            if let amount { path += "&amount=\(amount)" }
            openApp(path: path)
            toolbar.showSmart(nil)
            return
        }
        if case .paste(let text) = chip {
            // History's copy types straight out; the placeholder means we do
            // not have the text yet, so the tap is the intent that reads it.
            ClipContext.markDone()
            if text == "Tap to paste what you copied" {
                guard let read = UIPasteboard.general.string, !read.isEmpty else {
                    toolbar.showSmart(nil)
                    return
                }
                remember(copied: read)
                textDocumentProxy.insertText(read)
            } else {
                textDocumentProxy.insertText(text)
            }
        } else {
            textDocumentProxy.insertText(chip.insert)
        }
        toolbar.showSmart(nil)
        updateCandidates()
    }

    func toolbarSuggestionTapped(_ suggestion: GlyfToolbar.Suggestion) {
        let before = textDocumentProxy.documentContextBeforeInput
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
            textDocumentProxy.insertText(" ")
        case .correction, .word:
            if !word.isEmpty { replaceCurrentWord(with: suggestion.text) }
            textDocumentProxy.insertText(word.isEmpty ? suggestion.text + " " : " ")
            typing?.commit(word: suggestion.text, previous: previous, autoCapitalized: false, policy: policy)
        }
        TypingStore.shared.scheduleSave()
        wordTouches = []
        wordTouchesFor = ""
        syncAutoShift()
        updateCandidates()
    }

    private func openApp(path: String) {
        guard let url = URL(string: "glyf://open?path=\(path)") else { return }
        HostAppOpener.open(url, from: self) { _ in }
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
        textDocumentProxy.insertText(transcript)
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
        textDocumentProxy.insertText(text)
    }

    func shellOpenApp(path: String) {
        openApp(path: path)
    }

    func shellStateChanged() {
        // Settings toggles may change layout-affecting state.
        keyboardView.refreshBindings()
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
        startSkill(glyfId: id, letter: "")
    }

    func shellEditNote(id: String?, text: String) {
        pendingNote = (id, text)
        setSurface(.noteEdit)
    }
}

// MARK: - GlyfBarDelegate

extension GlyfKeyboardViewController: GlyfBarDelegate {

    func barClosed() {
        setSurface(.none)
    }

    func barReplace(text: String, input: GlyfBar.Input) {
        recordBarAccepted()
        // §6.4 Replace swaps exactly the text the run read — both sides of
        // the cursor. With the cursor glided mid-sentence, deleting only the
        // before-part left the old tail after the rewrite.
        if !input.after.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: input.after.utf16.count)
        }
        for _ in 0..<(input.consumedBefore + input.after.count) {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(text)
        setSurface(.none)
    }

    func barInsert(text: String) {
        recordBarAccepted()
        textDocumentProxy.insertText(text)
        setSurface(.none)
    }

    func barCopy(text: String) {
        guard hasFullAccess else { return }
        recordBarAccepted()
        UIPasteboard.general.string = text
        _ = ClipboardStore.inserting(text, into: ClipboardStore.load(), now: Date())
            .map(ClipboardStore.save)
    }

    /// §6.15: keeping a result teaches the tone profile.
    private func recordBarAccepted() {
        if !barAccepted, let id = bar?.lastRunGlyfId {
            ToneProfile.record(glyfId: id, accepted: true)
        }
        barAccepted = true
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
    }

    func searchInsert(_ text: String) {
        // Bypass the inline editor — results land in the host field.
        let target = inlineTarget
        inlineTarget = nil
        textDocumentProxy.insertText(text)
        inlineTarget = target
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
    }

    func noteEditSaved() {
        inlineTarget = nil
        setSurface(.shell)
        shell?.push("vault")
    }

    func noteEditClosed() {
        inlineTarget = nil
        setSurface(.shell)
    }
}

// MARK: - EmojiBoardDelegate

extension GlyfKeyboardViewController: EmojiBoardDelegate {

    func emojiPicked(_ emoji: String) {
        textDocumentProxy.insertText(emoji)
    }

    func emojiBackToLetters() {
        setSurface(.none)
    }

    func emojiDeleteBackward() {
        textDocumentProxy.deleteBackward()
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
    }
}

// MARK: - TranslationHUDDelegate (§6.13 T)

extension GlyfKeyboardViewController: TranslationHUDDelegate {

    func hudRequestTranslation(of text: String, target: String?,
                               completion: @escaping (BackendClient.Translation?) -> Void) {
        guard hasFullAccess, !isSecureField else { completion(nil); return }
        BackendClient.shared.translate(text: text, target: target, completion: completion)
    }

    func hudReplaceDraft(with text: String, consumedBefore: Int) {
        for _ in 0..<consumedBefore { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(text)
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
        textDocumentProxy.insertText(text)
        syncAutoShift()
        updateCandidates()
    }

    func connectorClosed() {
        setSurface(.none)
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
