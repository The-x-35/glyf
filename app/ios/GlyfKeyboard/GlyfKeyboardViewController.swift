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
    /// The text the run reads (field text, or the clipboard for a skill).
    private var actRunInput = ""
    private var actHasResult = false
    private var actAccepted = false
    private var emoji: EmojiBoard?
    private var connector: ConnectorSurface?
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

    private enum Surface: Equatable { case none, shell, bar, emoji, connector(String), search, noteEdit, act }
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
        SettingsStore.current.numberRow
            ? Glass.keysHeight + Glass.numberRowExtra : Glass.keysHeight
    }

    /// §6.13 T: the Translation HUD adds a 44pt strip while enabled — never
    /// in secure fields (§11.9), never under another surface.
    private var hudActive: Bool {
        SettingsStore.current.translationHUD == true && !isSecureField
    }

    private var totalHeight: CGFloat {
        let base = Glass.toolbarHeight + keysHeight
        switch surface {
        case .none:
            return base + (hudActive ? Glass.toolbarHeight : 0)
                + (clipStrip != nil ? Glass.toolbarHeight : 0)
        case .emoji:
            // Searching collapses the board to a strip ABOVE the letter
            // keys, so the surface needs room for both.
            return base + (emoji?.searchActive == true ? EmojiBoard.searchStripHeight : 0)
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
        case .shell, .connector, .act: return base
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
        let hostDark = textDocumentProxy.keyboardAppearance == .dark
            || traitCollection.userInterfaceStyle == .dark
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
        if let blur = backdrop as? UIVisualEffectView {
            // Switching to the site look mid-session: drop the material and
            // paint the board colour on the same view.
            blur.effect = Glass.siteLook ? nil : Glass.base
            blur.backgroundColor = Glass.siteLook ? Glass.solidBackdrop : .clear
        } else {
            backdrop?.backgroundColor = Glass.solidBackdrop
        }
        applyThemeBackdrop()
        toolbar.applyPalette()
        keyboardView.rebuild()
    }

    /// Color/gradient themes (Gboard-style picker in the app): a painted
    /// layer over the blur, dimmed by the user's slider. "" = stock glass.
    private var themeLayer: CAGradientLayer?
    private func applyThemeBackdrop() {
        themeLayer?.removeFromSuperlayer()
        themeLayer = nil
        let colors = Glass.themeBgColors()
        // Painted themes replace the blur outright (Gboard renders color as
        // the base); stock glass keeps the material.
        backdrop.isHidden = !colors.isEmpty
        guard !colors.isEmpty else { return }
        let layer = CAGradientLayer()
        let dimmed = colors.map { c -> CGColor in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a)
            let k = 1 - Glass.themeDim
            return UIColor(red: r * k, green: g * k, blue: b * k, alpha: 1).cgColor
        }
        layer.colors = dimmed.count == 1 ? [dimmed[0], dimmed[0]] : dimmed
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        themeLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        themeLayer?.frame = view.bounds
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            resolveAppearance()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SettingsStore.invalidate()
        VaultStore.shared.invalidate() // the app may have edited the vault
        resolveAppearance() // BEFORE building — tokens feed every surface
        if !didBuild {
            didBuild = true
            build()
            applyThemeBackdrop() // painted themes exist from the FIRST frame
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

        // The site look paints a solid board (as on tryglyf.com); the other
        // themes keep Apple's blur. Reduce Transparency forces solid too.
        if Glass.reduceTransparency || Glass.siteLook {
            backdrop = UIView()
            backdrop.backgroundColor = Glass.solidBackdrop
        } else {
            backdrop = UIVisualEffectView(effect: Glass.base)
        }
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
        case .emoji where emoji?.searchActive != true: return ("face.smiling", "Emoji")
        case .act: return ("sparkles", "Glyf")
        case .bar where bar?.expandedForResult == true: return ("sparkles", "Glyf")
        case .connector where connector?.searchActive != true: return ("calendar", "Calendar")
        default: return (nil, nil)
        }
    }

    private var lastPanelTitle: String??

    private func layoutSurfaces() {
        let w = content.bounds.width
        let h = content.bounds.height
        let header = panelHeader()
        if lastPanelTitle != .some(header.1) {
            lastPanelTitle = .some(header.1)
            toolbar.showPanelHeader(icon: header.0, title: header.1,
                                    canGoBack: shell?.canGoBack == true)
        }
        let showHUD = surface == .none && hudActive
        hud?.isHidden = !showHUD
        clipStrip?.isHidden = surface != .none
        switch surface {
        case .none:
            var y: CGFloat = 0
            if showHUD {
                ensureHUD().frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
                y = Glass.toolbarHeight
            }
            if let clipStrip {
                clipStrip.frame = CGRect(x: 0, y: y, width: w, height: Glass.toolbarHeight)
                y += Glass.toolbarHeight
            }
            toolbar.isHidden = false
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
                keyboardView.isHidden = true
                emoji?.frame = CGRect(x: 0, y: Glass.toolbarHeight, width: w,
                                      height: max(0, h - Glass.toolbarHeight))
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
                            self.search, self.noteEdit, self.hud,
                            self.tonesPopup, self.act, self.clipStrip] as [UIView?] {
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
        case .connector: connector?.removeFromSuperview(); connector = nil
        case .search: search?.cancelWork(); search?.removeFromSuperview(); search = nil
        case .noteEdit: noteEdit?.removeFromSuperview(); noteEdit = nil
        case .act:
            actTask?.cancel(); actTask = nil
            act?.removeFromSuperview(); act = nil
        case .none: break
        }
        inlineTarget = nil
        surface = new
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
        // Something just copied is offered while the field is still empty —
        // but only what history already holds, so the chip never has to read
        // the pasteboard (that is the Paste button's job, alert-free).
        let paste: String? = (hasFullAccess && tail.isEmpty && ClipContext.isFresh())
            ? ClipboardStore.load().first?.text : nil
        let chip = Smart.chip(for: tail, fields: VaultStore.shared.load().fields, paste: paste)
        toolbar.showSmart(chip)
        return chip != nil
    }

    private func updateCandidates() {
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
    private func refreshClipStrip(animated: Bool) {
        let wanted = hasFullAccess && !isSecureField && surface == .none && ClipContext.isFresh()
        if wanted, clipStrip == nil {
            let strip = ClipContextStrip()
            strip.delegate = self
            content.addSubview(strip)
            clipStrip = strip
        } else if !wanted, let strip = clipStrip {
            strip.removeFromSuperview()
            clipStrip = nil
        } else {
            return
        }
        applySurfaceLayout(animated: animated)
    }

    private func removeClipStrip() {
        clipStrip?.removeFromSuperview()
        clipStrip = nil
        applySurfaceLayout(animated: true)
    }

    private func startAct(clipboard text: String) {
        actSkill = nil
        actInput = ("", "") // a copied text is acted on, never deleted from the field
        actRunInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        actAccepted = false
        setSurface(.act)
        runAct()
    }

    private func startAct(before: String, after: String) {
        actSkill = nil
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
        actTask = BackendClient.shared.runAct(text: actRunInput, onResult: { [weak self] result in
            guard let self, self.surface == .act else { return }
            self.actHasResult = true
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
                    KeyboardToast.show(in: self.content, text: "Translation HUD off")
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
        switch id {
        case "search":
            setSurface(.search)
        case "clipboard":
            ClipboardStore.captureNow() // user asked for the clipboard
            setSurface(.shell); shell?.push("clipboard")
        case "vault":
            setSurface(.shell); shell?.push("vault")
        case "settings":
            setSurface(.shell); shell?.push("settings")
        case "emoji":
            setSurface(.emoji)
        case "translate":
            toggleTranslateHUD()
        case "dictation":
            startDictationHandoff()
        default:
            break
        }
    }

    func toolbarItemLongPressed(_ id: String) {
        setSurface(.shell)
        shell?.push(id == "settings" ? "settings" : "toolbar")
    }

    /// The strip's close button: whatever panel is open goes away.
    func toolbarBackTapped() {
        shell?.back()
    }

    func toolbarCloseTapped() {
        setSurface(.none)
    }

    func toolbarSmartTapped(_ chip: Smart.Chip) {
        if case .paste(let text) = chip {
            // The chip only ever carries text history already has, so the tap
            // types it straight out with no pasteboard read.
            ClipContext.markDone()
            textDocumentProxy.insertText(text)
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
                                canGoBack: shell?.canGoBack == true)
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

    func shellOpenSurface(_ id: String) {
        switch id {
        case "search": setSurface(.search)
        case "emoji": setSurface(.emoji)
        case "tones": setSurface(.none); showTonesPopup()
        case "translate": setSurface(.none); toggleTranslateHUD()
        case "ask": setSurface(.none); openBar(autoRun: nil)
        default: break
        }
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

    func hudRequestTranslation(of text: String, completion: @escaping (String?) -> Void) {
        guard hasFullAccess, !isSecureField else { completion(nil); return }
        var final = ""
        BackendClient.shared.run(
            glyfId: "glyf.translate", input: text,
            vars: ["target": SettingsStore.current.translateTarget],
            onToken: { final += $0 },
            onDone: { text, _ in completion(text.isEmpty ? final : text) },
            onError: { _ in completion(nil) })
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
