import UIKit

protocol ToolbarDelegate: AnyObject {
    func toolbarGlyfTapped()
    func toolbarItemTapped(_ id: String)
    func toolbarItemLongPressed(_ id: String)
    /// A held strip icon being dragged: reorder, or off the strip to remove.
    func toolbarItemDragBegan(_ id: String, at windowPoint: CGPoint)
    func toolbarItemDragMoved(to windowPoint: CGPoint)
    func toolbarItemDragEnded(_ id: String, at windowPoint: CGPoint)
    func toolbarSuggestionTapped(_ suggestion: GlyfToolbar.Suggestion)
    /// The strip's close button while a panel is open (website behaviour).
    func toolbarCloseTapped()
    /// The chevron beside a panel title: go back a screen inside the panel.
    func toolbarBackTapped()
    /// The smart chip (a sum just typed, or a saved detail the sentence asks
    /// for) was tapped.
    func toolbarSmartTapped(_ chip: Smart.Chip)
    /// The ✕ on a clipboard chip: this copy is not wanted.
    func toolbarSmartDismissed()
}

/// §6.2 — the 44pt strip above the keys. When autocorrect candidates show,
/// the toolbar collapses to the Glyf button only and candidates take the
/// strip; tapping the Glyf button restores the tools. Never two strips.
final class GlyfToolbar: UIView {

    weak var delegate: ToolbarDelegate?

    private let glyfButton = UIButton(type: .system)
    private let divider = UIView()
    /// Between the three suggestion slots, like the system bar's.
    private let slotLines = [UIView(), UIView()]
    private let scroll = ControlScrollView()
    private let itemsStack = UIStackView()
    private let candidatesStack = UIStackView()
    private let runsChip = UIButton(type: .system)
    /// The logo: the letterform, and the accent dot at its shoulder.
    private let markView = UIImageView()
    private let brandDot = CALayer()
    /// True while a panel has turned the logo into a close button.
    private var panelOpen = false
    /// Panel mode (website parity): the strip keeps its place, the brand pill
    /// turns into a close button and the rest becomes "icon + panel name".
    private let panelLabel = UILabel()
    private let panelIcon = UIImageView()
    /// Deeper panel screens keep their way back in the strip, so the panel
    /// itself never spends a row on a chevron.
    private let panelBack = UIButton(type: .system)
    /// A panel's own action at the strip's right edge (↻ on an answer).
    private let panelAction = UIButton(type: .system)
    private var panelActionHandler: (() -> Void)?
    private(set) var panelTitle: String?
    /// Smart chip: one card across the strip, accent key then value.
    private let smartCard = UIControl()
    private let smartKey = UILabel()
    private let smartValue = UILabel()
    /// Clipboard chips lead with the clipboard mark and end with a way out,
    /// the way Gboard's do: the pill IS the paste, so it needs no verb, and
    /// something that appears because you copied must be dismissable.
    private let smartLead = UIImageView()
    private let smartClose = UIButton(type: .system)
    private(set) var smartChip: Smart.Chip?
    /// The strip item currently lifted by a hold, if any.
    private var draggingId: String?
    /// Where a dropped tool would land, drawn as a thin accent bar.
    private let dropMarker = UIView()

    /// item id → SF Symbol
    /// One icon per tool, shared by the strip and the g menu grid.
    static let icons: [String: String] = [
        "search": "magnifyingglass",
        "rewrite": "wand.and.stars",
        "translate": "translate",
        "vault": "person.text.rectangle",
        "clipboard": "doc.on.clipboard",
        "emoji": "face.smiling",
        "ask": "sparkles",
        "dictation": "mic",
        "glyfs": "square.grid.2x2",
        "shorthand": "text.badge.plus",
        "keys": "keyboard",
        "pay": "creditcard",
        "calendar": "calendar",
        "settings": "gearshape",
    ]

    private(set) var showingCandidates = false
    /// User tapped Glyf to restore tools while candidates were up.
    private var userPinnedTools = false

    init() {
        super.init(frame: .zero)

        // The logo IS the button: the app's own letterform, standing on the
        // strip like every other tool rather than boxed in a tile. No ground
        // of its own — but not a clear one either: iOS throws away touches
        // that land on fully transparent pixels in a keyboard extension, so
        // the button is painted with the grid's near-invisible ink.
        glyfButton.backgroundColor = Glass.touchableGrid
        glyfButton.layer.cornerCurve = .continuous
        markView.image = Glass.brandMark
        markView.tintColor = Glass.textPrimary
        markView.contentMode = .scaleAspectFit
        markView.isUserInteractionEnabled = false
        glyfButton.addSubview(markView)
        brandDot.backgroundColor = Glass.accentPrimary.cgColor
        glyfButton.layer.addSublayer(brandDot)
        glyfButton.accessibilityIdentifier = "toolbar:glyf"
        glyfButton.accessibilityLabel = "Glyf"
        glyfButton.addTarget(self, action: #selector(glyfTapped), for: .touchUpInside)
        addSubview(glyfButton)

        divider.backgroundColor = Glass.strokeHairline
        addSubview(divider)

        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        itemsStack.axis = .horizontal
        itemsStack.spacing = 6
        // The website spreads the six tools evenly across the strip.
        itemsStack.distribution = .fillEqually
        scroll.addSubview(itemsStack)

        dropMarker.backgroundColor = Glass.accentPrimary
        dropMarker.layer.cornerRadius = 1.5
        dropMarker.isHidden = true
        addSubview(dropMarker)

        candidatesStack.axis = .horizontal
        candidatesStack.spacing = 4
        candidatesStack.distribution = .fillEqually
        candidatesStack.isHidden = true
        addSubview(candidatesStack)
        // The system bar rules its three slots off with two hairlines, whether
        // or not a slot has a word in it.
        for line in slotLines {
            line.backgroundColor = Glass.strokeHairline
            line.isHidden = true
            addSubview(line)
        }

        runsChip.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        runsChip.setTitleColor(Glass.accentWarning, for: .normal)
        runsChip.backgroundColor = Glass.accentWarning.withAlphaComponent(0.15)
        runsChip.layer.cornerRadius = 8
        runsChip.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        runsChip.isHidden = true
        runsChip.isUserInteractionEnabled = false
        addSubview(runsChip)

        panelIcon.contentMode = .center
        panelIcon.tintColor = Glass.textPrimary
        panelIcon.isHidden = true
        addSubview(panelIcon)
        panelLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        panelLabel.textColor = Glass.textPrimary
        panelLabel.isHidden = true
        addSubview(panelLabel)
        panelBack.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        panelBack.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        panelBack.tintColor = Glass.textPrimary
        panelBack.isHidden = true
        panelBack.accessibilityIdentifier = "toolbar:back"
        panelBack.accessibilityLabel = "Back"
        panelAction.tintColor = Glass.textPrimary
        panelAction.isHidden = true
        panelAction.addAction(UIAction { [weak self] _ in self?.panelActionHandler?() }, for: .touchUpInside)
        addSubview(panelAction)
        panelBack.addAction(UIAction { [weak self] _ in self?.delegate?.toolbarBackTapped() },
                            for: .touchUpInside)
        addSubview(panelBack)

        smartCard.backgroundColor = Glass.surfaceCard
        smartCard.layer.cornerRadius = 12
        smartCard.layer.cornerCurve = .continuous
        // Flat, like every card on the iOS 26 sheet.
        smartCard.layer.shadowOpacity = 0
        smartCard.isHidden = true
        smartCard.accessibilityIdentifier = "strip:smart"
        smartCard.isAccessibilityElement = true
        smartCard.accessibilityTraits = .button
        smartCard.addAction(UIAction { [weak self] _ in
            guard let self, let chip = self.smartChip else { return }
            self.delegate?.toolbarSmartTapped(chip)
        }, for: .touchUpInside)
        smartKey.font = .systemFont(ofSize: 13, weight: .semibold)
        smartKey.textColor = Glass.accentPrimary
        smartCard.addSubview(smartKey)
        smartValue.font = .systemFont(ofSize: 15)
        smartValue.textColor = Glass.textPrimary
        smartValue.lineBreakMode = .byTruncatingTail
        smartCard.addSubview(smartValue)
        smartLead.contentMode = .scaleAspectFit
        smartLead.tintColor = Glass.accentPrimary
        smartLead.isHidden = true
        smartCard.addSubview(smartLead)
        smartClose.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)),
                            for: .normal)
        smartClose.tintColor = Glass.textSecondary
        smartClose.isHidden = true
        smartClose.accessibilityLabel = "Dismiss"
        smartClose.accessibilityIdentifier = "strip:smart:close"
        smartClose.addAction(UIAction { [weak self] _ in
            self?.delegate?.toolbarSmartDismissed()
        }, for: .touchUpInside)
        smartCard.addSubview(smartClose)
        addSubview(smartCard)

        reloadItems()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Re-skins after an appearance flip (items re-tint via reloadItems;
    /// the brand keycap stays constant by design).
    func applyPalette() {
        divider.backgroundColor = Glass.strokeHairline
        panelIcon.tintColor = Glass.textPrimary
        panelLabel.textColor = Glass.textPrimary
        panelBack.tintColor = Glass.textPrimary
        smartCard.backgroundColor = Glass.surfaceCard
        smartValue.textColor = Glass.textPrimary
        // Suggestion words are drawn with the ink of the moment they were
        // made; redraw them or they stay dark on a sheet that just went dark.
        let words = suggestions
        suggestions = []
        if !words.isEmpty { showSuggestions(words) }
        // The letter stands on the sheet with no ground of its own, so it
        // takes the sheet's ink: dark on the light one, white on the dark.
        markView.tintColor = Glass.textPrimary
        brandDot.backgroundColor = Glass.accentPrimary.cgColor
        if !panelOpen { glyfButton.backgroundColor = Glass.touchableGrid }
        reloadItems()
    }

    /// The chip's frame while it is showing, for the tour's ring.
    var smartFrame: CGRect? { smartCard.isHidden ? nil : smartCard.frame }
    var glyfFrame: CGRect { glyfButton.frame }

    /// Index a tool would take if dropped at this point (strip coordinates),
    /// and the marker that shows it. Nil hides the marker.
    func showDropMarker(at point: CGPoint?) {
        guard let point, !itemsStack.arrangedSubviews.isEmpty else {
            dropMarker.isHidden = true
            return
        }
        let idx = dropIndex(for: point)
        let views = itemsStack.arrangedSubviews
        let x: CGFloat
        if idx >= views.count {
            x = itemsStack.convert(views[views.count - 1].frame, to: self).maxX + 2
        } else {
            x = itemsStack.convert(views[idx].frame, to: self).minX - 4
        }
        dropMarker.frame = CGRect(x: x, y: 8, width: 3, height: bounds.height - 16)
        dropMarker.isHidden = false
        bringSubviewToFront(dropMarker)
    }

    func dropIndex(for point: CGPoint) -> Int {
        let views = itemsStack.arrangedSubviews
        for (i, v) in views.enumerated() {
            let f = itemsStack.convert(v.frame, to: self)
            if point.x < f.midX { return i }
        }
        return views.count
    }

    func reloadItems() {
        itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let s = SettingsStore.current
        for id in s.toolbarOrder where !s.toolbarHidden.contains(id) {
            guard let symbol = Self.icons[id] else { continue }
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .regular),
                                              forImageIn: .normal)
            b.tintColor = Glass.textPrimary.withAlphaComponent(0.78)
            b.layer.cornerRadius = 10
            b.layer.cornerCurve = .continuous
            b.accessibilityIdentifier = "toolbar:\(id)"
            b.accessibilityLabel = id
            b.addAction(UIAction { [weak self] _ in
                self?.delegate?.toolbarItemTapped(id)
            }, for: .touchUpInside)
            let long = UILongPressGestureRecognizer(target: self, action: #selector(itemLong(_:)))
            long.minimumPressDuration = 0.32
            long.allowableMovement = 10   // moving first is a scroll, not a pick-up
            b.addGestureRecognizer(long)
            itemsStack.addArrangedSubview(b)
        }
        setNeedsLayout()
    }

    /// Hold an icon and it lifts: slide sideways to reorder, or drag it off
    /// the strip to put it away. (Gboard's gesture, on Glyf's strip.)
    @objc private func itemLong(_ g: UILongPressGestureRecognizer) {
        guard let b = g.view as? UIButton,
              let raw = b.accessibilityIdentifier?.split(separator: ":").last
        else { return }
        let id = String(raw)
        let point = g.location(in: self)
        switch g.state {
        case .began:
            draggingId = id
            b.alpha = 0.25
            delegate?.toolbarItemDragBegan(id, at: convert(point, to: window))
        case .changed:
            delegate?.toolbarItemDragMoved(to: convert(point, to: window))
        case .ended, .cancelled, .failed:
            b.alpha = 1
            draggingId = nil
            delegate?.toolbarItemDragEnded(id, at: convert(point, to: window))
        default:
            break
        }
    }

    /// Panel open: title + icon in the strip, brand pill becomes a close
    /// button. `nil` restores the tools.
    /// - Parameter keepTools: the g menu's own screen leaves the tools on the
    ///   strip, because that is what you drag a tile onto. Deeper panels take
    ///   the strip for their name.
    func showPanelHeader(icon: String?, title: String?, canGoBack: Bool = false,
                         keepTools: Bool = false) {
        panelTitle = title
        panelBack.isHidden = !(title != nil && canGoBack)
        let open = title != nil
        let hideTools = open && !keepTools
        panelLabel.text = title
        panelLabel.isHidden = !open || keepTools
        panelIcon.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        panelIcon.image = icon.flatMap { UIImage(systemName: $0) }
        panelIcon.isHidden = !open || keepTools || panelIcon.image == nil
        if open {
            scroll.isHidden = hideTools
            candidatesStack.isHidden = true
            runsChip.isHidden = true
            divider.isHidden = hideTools || Glass.solidLook
        } else {
            // Back to exactly one of tools or suggestions. Setting both here
            // (tools on, suggestions on) drew words over the icons after
            // the emoji page closed.
            setPanelAction(symbol: nil, label: nil, handler: nil)
            applyCandidatesVisibility(toolsVisible: !showingCandidates || userPinnedTools)
        }
        if open {
            glyfButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            glyfButton.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
            glyfButton.tintColor = Glass.textPrimary
            glyfButton.backgroundColor = Glass.fillSoft
            glyfButton.accessibilityIdentifier = "toolbar:close"
            glyfButton.accessibilityLabel = "Close"
            markView.isHidden = true
            brandDot.isHidden = true
        } else {
            glyfButton.setImage(nil, for: .normal)
            // Back to no ground of its own, but still painted: a clear
            // button would stop taking touches at all (see init).
            glyfButton.backgroundColor = Glass.touchableGrid
            glyfButton.accessibilityIdentifier = "toolbar:glyf"
            glyfButton.accessibilityLabel = "Glyf"
            markView.isHidden = false
            brandDot.isHidden = false
        }
        panelOpen = open
        setNeedsLayout()
    }

    /// The open panel's action at the strip's right edge, or nil for none.
    func setPanelAction(symbol: String?, label: String?, handler: (() -> Void)?) {
        panelActionHandler = handler
        if let symbol {
            panelAction.setImage(UIImage(systemName: symbol), for: .normal)
            panelAction.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold), forImageIn: .normal)
        }
        panelAction.accessibilityLabel = label
        panelAction.accessibilityIdentifier = "toolbar:panelAction"
        panelAction.isHidden = handler == nil || panelTitle == nil
        setNeedsLayout()
    }

    /// One chip across the strip, or nil to go back to tools and suggestions.
    func showSmart(_ chip: Smart.Chip?) {
        smartChip = chip
        smartCard.isHidden = chip == nil || panelTitle != nil
        if let chip {
            let isPaste: Bool = { if case .paste = chip { return true }; return false }()
            smartLead.isHidden = !isPaste
            smartClose.isHidden = !isPaste
            smartLead.image = isPaste ? UIImage(systemName: "doc.on.clipboard",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
                : nil
            // A clipboard pill is the paste: naming the action twice, once as
            // a word and once as the tap, is what made it read as clutter.
            smartKey.isHidden = isPaste
            // Content on the left, the action on the right edge.
            if let verb = chip.verb {
                smartKey.attributedText = nil
                smartKey.text = verb
            } else {
                let spark = NSTextAttachment(image: UIImage(systemName: "sparkles",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))?
                    .withTintColor(Glass.accentPrimary, renderingMode: .alwaysOriginal) ?? UIImage())
                smartKey.attributedText = NSAttributedString(attachment: spark)
            }
            if case .vault(let field) = chip {
                let line = NSMutableAttributedString(string: field.label + "  ", attributes: [
                    .foregroundColor: Glass.textSecondary,
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium)])
                line.append(NSAttributedString(string: chip.value, attributes: [
                    .foregroundColor: Glass.textPrimary, .font: UIFont.systemFont(ofSize: 15)]))
                smartValue.attributedText = line
            } else {
                smartValue.attributedText = nil
                smartValue.font = .systemFont(ofSize: 15)
                smartValue.textColor = Glass.textPrimary
                smartValue.text = chip.value
            }
            smartCard.backgroundColor = Glass.surfaceCard
            smartCard.accessibilityLabel = "\(chip.key) \(chip.value)"
        }
        if smartCard.isHidden {
            // No chip: back to whichever of tools / suggestions the strip was
            // showing. Never both — they share the same space and used to
            // draw over each other when a chip went away.
            applyCandidatesVisibility(toolsVisible: !showingCandidates || userPinnedTools)
        } else {
            scroll.isHidden = true
            candidatesStack.isHidden = true
            divider.isHidden = true
            runsChip.isHidden = true
        }
        setNeedsLayout()
    }

    @objc private func glyfTapped() {
        if panelTitle != nil {
            delegate?.toolbarCloseTapped()
            return
        }
        if showingCandidates && !candidatesStack.isHidden {
            // Restore tools without opening the shell (§6.2).
            userPinnedTools = true
            applyCandidatesVisibility(toolsVisible: true)
        } else {
            delegate?.toolbarGlyfTapped()
        }
    }

    // MARK: Suggestions (§6.1: three slots — what you typed, what space
    // inserts, the next best — or the undo for a correction just made)

    struct Suggestion: Equatable {
        enum Kind: Equatable {
            /// Exactly what was typed; tapping keeps it.
            case literal
            /// What the space bar is about to insert.
            case correction
            case word
            /// Put back what was typed before the last correction.
            case undo
        }
        let text: String
        let kind: Kind
    }

    private(set) var suggestions: [Suggestion] = []

    func showSuggestions(_ items: [Suggestion]) {
        let items = Array(items.prefix(3))
        if items == suggestions, showingCandidates == !items.isEmpty {
            // Same words, but something else may have moved the strip since.
            applyCandidatesVisibility(toolsVisible: items.isEmpty || userPinnedTools)
            return
        }
        suggestions = items
        candidatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, item) in items.enumerated() {
            let b = suggestionButton(item)
            b.accessibilityIdentifier = "suggest:\(i)"
            b.addAction(UIAction { [weak self] _ in self?.delegate?.toolbarSuggestionTapped(item) },
                        for: .touchUpInside)
            candidatesStack.addArrangedSubview(b)
        }
        // Always three slots, so one word sits in its slot and the lines
        // between slots stay where they are (the system bar's way).
        while !items.isEmpty, candidatesStack.arrangedSubviews.count < 3 {
            candidatesStack.addArrangedSubview(UIView())
        }
        showingCandidates = !items.isEmpty
        if items.isEmpty { userPinnedTools = false }
        applyCandidatesVisibility(toolsVisible: items.isEmpty || userPinnedTools)
    }

    private func applyCandidatesVisibility(toolsVisible: Bool) {
        guard panelTitle == nil else { return }   // a panel owns the strip
        scroll.isHidden = !toolsVisible
        divider.isHidden = !toolsVisible || Glass.solidLook
        candidatesStack.isHidden = toolsVisible || !showingCandidates
        for line in slotLines { line.isHidden = candidatesStack.isHidden }
        // The website's strip is six tools and the g pill, nothing else; the
        // run counter lives in the g menu's Account screen.
        runsChip.isHidden = runsRemaining == nil || !toolsVisible || Glass.solidLook
    }

    private func suggestionButton(_ item: Suggestion) -> UIButton {
        let b = UIButton(type: .system)
        let title: String
        switch item.kind {
        case .literal: title = "“\(item.text)”"
        case .undo: title = "↩ \(item.text)"
        case .correction, .word: title = item.text
        }
        b.setTitle(title, for: .normal)
        let emphasized = item.kind == .correction
        // 17pt: the system bar's "The" stands 12pt tall, which is this size.
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: emphasized ? .semibold : .regular)
        b.setTitleColor(item.kind == .literal ? Glass.textSecondary : Glass.textPrimary, for: .normal)
        // The website marks the best candidate by weight alone, no pill —
        // but never `.clear`. A keyboard extension throws away touches that
        // land on transparent pixels, so a clear slot was only tappable on
        // the letters themselves: you had to hit the word, not its slot,
        // which is why a suggestion took two or three tries to take.
        b.backgroundColor = (emphasized && !Glass.solidLook)
            ? Glass.fillBar : Glass.touchableGrid
        b.layer.cornerRadius = 8
        b.layer.cornerCurve = .continuous
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.accessibilityLabel = item.text
        return b
    }

    // MARK: Runs chip (§6.2 — only when the free cap is low)

    private var runsRemaining: Int?

    func setRunsRemaining(_ n: Int?) {
        runsRemaining = n
        if let n, n <= 8 {
            runsChip.setTitle("\(n) left", for: .normal)
            runsChip.isHidden = showingCandidates && !userPinnedTools
        } else {
            runsChip.isHidden = true
        }
        setNeedsLayout()
    }

    /// The brand tile is a 28pt square because that is what the icon is, and
    /// 28pt is small for a thumb. The strip's margin around it belongs to
    /// nothing else, so a near-miss that would otherwise land on the bare
    /// toolbar goes to the tile instead. Only points nothing else claimed are
    /// taken, so the divider and the scrolling tools keep their own.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit == nil || hit === self,
           glyfButton.frame.insetBy(dx: -6, dy: -6).contains(point) {
            return glyfButton
        }
        return hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Website strip: the logo at the left, then the tools across the rest.
        // Below the band we had to draw ourselves (nothing on iOS 26, which
        // supplies its own): everything measures off the content box.
        let band = Glass.stripBand
        let h = bounds.height - band
        let mid = band + h / 2 - Glass.stripLift
        // Off its tile the letter is free to be a letter: 0.56 of the strip,
        // which is 20pt here — the weight the tool icons beside it carry. In
        // a tile the same strip only bought 14, because a tile has to hold
        // the mark AND its margins.
        let letterH = (h * 0.56).rounded()
        let letterW = Glass.brandMarkWidth(height: letterH)
        let dot = (letterH * 0.20).rounded()
        let gap = (letterH * 0.08).rounded()
        let inkW = letterW + gap + dot
        // Nothing is drawn behind the letter now, so the button has to carry
        // its own target: the ink plus a margin all round.
        let padX: CGFloat = 6, padY: CGFloat = 7
        let inkX: CGFloat = 7
        glyfButton.frame = CGRect(x: inkX - padX, y: mid - letterH / 2 - padY,
                                  width: inkW + padX * 2, height: letterH + padY * 2)
        glyfButton.layer.cornerRadius = 9
        markView.frame = CGRect(x: padX, y: padY, width: letterW, height: letterH)
        // At the letter's shoulder, not the logo's own far corner: see
        // Glass.brandMark for why the mark tucks its dot in at this size.
        brandDot.frame = CGRect(x: padX + letterW + gap, y: padY,
                                width: dot, height: dot)
        brandDot.cornerRadius = dot / 2
        let markRight = inkX + inkW
        divider.isHidden = Glass.solidLook
        divider.frame = CGRect(x: markRight + 10, y: 10, width: Glass.hairlineWidth * 2,
                               height: h - 20)
        let chipW: CGFloat = runsChip.isHidden ? 0 : 64
        if !runsChip.isHidden {
            runsChip.frame = CGRect(x: bounds.width - chipW - 6, y: 11,
                                    width: chipW, height: h - 22)
        }
        let left = markRight + (Glass.solidLook ? 11 : 17)
        let width = bounds.width - left - chipW - 6
        if !smartCard.isHidden {
            let cardH = (h * 0.78).rounded()
            smartCard.frame = CGRect(x: left, y: mid - cardH / 2,
                                     width: max(0, bounds.width - left - 6), height: cardH)
            let paste = !smartLead.isHidden
            // Gboard's clipboard suggestion is a pill; the rest stay cards.
            smartCard.layer.cornerRadius = paste ? cardH / 2 : 12
            let keyW = smartKey.isHidden ? 0 : min(smartKey.intrinsicContentSize.width, 120)
            smartKey.frame = CGRect(x: smartCard.bounds.width - 14 - keyW, y: 0,
                                    width: keyW, height: cardH)
            if paste {
                smartLead.frame = CGRect(x: 13, y: (cardH - 16) / 2, width: 16, height: 16)
                let c: CGFloat = 30
                smartClose.frame = CGRect(x: smartCard.bounds.width - c - 3,
                                          y: (cardH - c) / 2, width: c, height: c)
                smartValue.frame = CGRect(x: 37, y: 0,
                                          width: max(0, smartClose.frame.minX - 43),
                                          height: cardH)
            } else {
                smartValue.frame = CGRect(x: 14, y: 0,
                                          width: max(0, smartCard.bounds.width - keyW - 38),
                                          height: cardH)
            }
        }
        if panelTitle != nil {
            var x = left
            if !panelBack.isHidden {
                panelBack.frame = CGRect(x: x - 4, y: band - Glass.stripLift, width: 30, height: h)
                x += 28
            }
            panelIcon.frame = CGRect(x: x, y: mid - 12, width: 24, height: 24)
            let textX = panelIcon.isHidden ? x : x + 30
            let actionW: CGFloat = panelAction.isHidden ? 0 : 44
            panelAction.frame = CGRect(x: bounds.width - actionW - 4, y: mid - 17,
                                       width: actionW, height: 34)
            panelLabel.frame = CGRect(x: textX, y: band - Glass.stripLift,
                                      width: bounds.width - textX - 10 - actionW, height: h)
        }
        // The tools live INSIDE this scroll view, which clips them, so the
        // band has to move the scroll itself — offsetting only the stack
        // pushes the icons out through its bottom edge (that is what ate the
        // magnifier's handle and the mic's stand on iOS 18).
        scroll.frame = CGRect(x: left, y: band, width: width, height: h)
        let itemH = min(34, h - 4)
        // …and inside it the stack is band-relative: the strip's own centring.
        itemsStack.frame = CGRect(x: 0, y: (mid - band) - itemH / 2, width: width, height: itemH)
        scroll.contentSize = CGSize(width: width, height: h)
        candidatesStack.frame = CGRect(x: left, y: mid - (h - 12) / 2,
                                       width: bounds.width - left - 8, height: h - 12)
        // A hairline on each boundary between the three equal slots, drawn
        // at the system bar's height: a little over half the strip.
        let slotW = (candidatesStack.bounds.width - 2 * candidatesStack.spacing) / 3
        let lineH = (h * 0.56).rounded()
        for (i, line) in slotLines.enumerated() {
            let x = candidatesStack.frame.minX + slotW * CGFloat(i + 1)
                + candidatesStack.spacing * CGFloat(i) + candidatesStack.spacing / 2
            line.frame = CGRect(x: x.rounded() - 0.5, y: mid - lineH / 2, width: 1, height: lineH)
        }
    }

}
