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
    /// The second action on a chip: Buy beside a price, Send or Buy beside
    /// a copied address.
    func toolbarSmartExtraTapped(_ chip: Smart.Chip)
    /// One part of a details chip: a saved detail (by its place), or Temp
    /// mail after them.
    func toolbarSmartChoiceTapped(_ chip: Smart.Chip, index: Int)
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
    /// The brand key that opens the Glyf menu: the app icon's g and violet
    /// dot on a black key (GlyfMark). Three layers, drawn from outlines.
    private let keycap = CAShapeLayer()
    private let keycapG = CAShapeLayer()
    private let keycapDot = CAShapeLayer()
    /// True while a panel has turned it into a close button.
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
    /// Report (a flag) left of the panel's action: the AI panel's, for a
    /// result the AI wrote (Google Play's AI-Generated Content policy).
    private let panelReport = UIButton(type: .system)
    private var panelReportHandler: (() -> Void)?
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
    /// A chip's second action (Smart.Chip.extra), as a small button.
    private let smartExtra = UIButton(type: .system)
    /// Between a chip's action and its ✕, so a thumb going for Insert never
    /// lands on the ✕.
    private let smartRule = UIView()
    /// A details chip as a row of its own chips (Arpit, 2026-10-01: "it
    /// should be 2-3 diff strips not all in one strip"): one ✕ for the row,
    /// then a glowing glass chip for each saved detail and one for Temp.
    private let choiceRow = UIView()
    private let choiceClose = UIButton(type: .system)
    private let choiceChips = (0..<3).map { _ in GlowChip() }
    private var choiceCount = 0
    /// The row is too narrow for every chip's words: tighter chips.
    private var choiceTight = false
    private(set) var smartChip: Smart.Chip?
    /// How tall a chip stands: its words 9pt clear of the border above and
    /// below (Arpit, 2026-09-30: "text seems too close to border").
    static let chipHeight: CGFloat = 38
    /// The strip chip's border, glow and glass.
    private let magic = ChipMagic()
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
        // A stack of moving pictures: the board's GIFs, with Stickers beside.
        "gifs": "play.square.stack",
        "ask": "sparkles",
        "tempmail": "envelope",
        "style": "bold.italic.underline",
        "glyfs": "square.grid.2x2",
        "pay": "creditcard",
        "calendar": "calendar",
        "games": "gamecontroller",
        "settings": "gearshape",
    ]

    /// The tools the strip shows, in its order. The g menu offers the rest:
    /// a tool lives in one place, never both.
    static var shownTools: [String] {
        SettingsStore.current.stripTools.filter { icons[$0] != nil && ($0 != "pay" || walletOn) }
    }

    /// The wallet turned on in the app (Profile › Keyboard › Wallet).
    static var walletOn: Bool { SettingsStore.current.walletEnabled == true }

    private(set) var showingCandidates = false
    /// User tapped Glyf to restore tools while candidates were up.
    private var userPinnedTools = false

    /// The air at each end of the strip — and, because the row is spaced by
    /// one gap, the air between any two icons follows from it.
    static let margin: CGFloat = 16
    /// How far each icon's tap target reaches past the icon, sideways. Equal
    /// on both sides of every control, so padding a target never moves an
    /// icon off the rhythm.
    static let itemPad: CGFloat = 12
    /// An SF Symbol does not fill the box it is drawn in — measured on this
    /// strip, about three points of air sit inside each one's edge. The brand
    /// key is a filled shape, so it fills its box exactly, and laid out on the
    /// same arithmetic it would sit three points nearer its neighbour than
    /// they are to each other, and three points nearer the screen edge. This
    /// is the air a symbol would have brought with it.
    static let gridSlack: CGFloat = 3

    init() {
        super.init(frame: .zero)

        // Glyf's own key, the way Android's strip starts: black, the icon's
        // g in white and the violet dot, the same in every look. The button
        // around it is the tap target and is painted, not clear, because iOS
        // throws away touches that land on fully transparent pixels in a
        // keyboard extension.
        glyfButton.backgroundColor = Glass.touchableGrid
        glyfButton.layer.cornerCurve = .continuous
        keycapDot.fillColor = Glass.accentPrimary.cgColor
        for layer in [keycap, keycapG, keycapDot] {
            layer.contentsScale = UIScreen.main.scale
            glyfButton.layer.addSublayer(layer)
        }
        applyKeycapRing()
        glyfButton.accessibilityIdentifier = "toolbar:glyf"
        glyfButton.accessibilityLabel = "Glyf"
        glyfButton.addTarget(self, action: #selector(glyfTapped), for: .touchUpInside)
        // Padded as a tool is, for when it is the ✕ (layoutSubviews).
        glyfButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: Self.itemPad,
                                                    bottom: 0, right: Self.itemPad)
        addSubview(glyfButton)

        divider.backgroundColor = Glass.strokeHairline
        addSubview(divider)

        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        itemsStack.axis = .horizontal
        itemsStack.spacing = 0
        // Equal GAPS, not equal slots. Slots of one width put each icon in the
        // middle of its own, which spaces the centres evenly but leaves the
        // ends of the row to whatever the first and last icons happen to
        // measure — 14pt of margin at one end against 21 at the other. Spacing
        // by the gap between them puts the same air everywhere, the margins
        // included; `layoutSubviews` solves for the gap and hands the stack
        // exactly the width that produces it.
        itemsStack.distribution = .equalSpacing
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
        panelBack.backgroundColor = Glass.touchableGrid
        panelBack.isHidden = true
        panelBack.accessibilityIdentifier = "toolbar:back"
        panelBack.accessibilityLabel = "Back"
        panelAction.tintColor = Glass.textPrimary
        panelAction.backgroundColor = Glass.touchableGrid
        panelAction.isHidden = true
        panelAction.addAction(UIAction { [weak self] _ in self?.panelActionHandler?() }, for: .touchUpInside)
        addSubview(panelAction)
        panelReport.setImage(UIImage(systemName: "flag"), for: .normal)
        panelReport.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        panelReport.tintColor = Glass.textSecondary
        panelReport.backgroundColor = Glass.touchableGrid
        panelReport.isHidden = true
        panelReport.accessibilityIdentifier = "act:report"
        panelReport.accessibilityLabel = "Report"
        panelReport.addAction(UIAction { [weak self] _ in self?.panelReportHandler?() }, for: .touchUpInside)
        addSubview(panelReport)
        panelBack.addAction(UIAction { [weak self] _ in self?.delegate?.toolbarBackTapped() },
                            for: .touchUpInside)
        addSubview(panelBack)

        paintCardFace()
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
        smartExtra.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        smartExtra.setTitleColor(Glass.accentPrimary, for: .normal)
        smartExtra.backgroundColor = Glass.accentPrimary.withAlphaComponent(0.14)
        smartExtra.layer.cornerCurve = .continuous
        smartExtra.isHidden = true
        smartExtra.accessibilityIdentifier = "strip:smart:extra"
        smartExtra.addAction(UIAction { [weak self] _ in
            guard let self, let chip = self.smartChip else { return }
            self.delegate?.toolbarSmartExtraTapped(chip)
        }, for: .touchUpInside)
        smartCard.addSubview(smartExtra)
        smartRule.isUserInteractionEnabled = false
        smartRule.isHidden = true
        smartCard.addSubview(smartRule)
        addSubview(smartCard)
        magic.attach(to: smartCard, in: self)
        buildChoiceRow()

        reloadItems()
    }

    /// The row of chips a details chip shows as: its ✕, then a chip each.
    private func buildChoiceRow() {
        choiceRow.isHidden = true
        choiceRow.accessibilityIdentifier = "strip:smart"
        choiceClose.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)), for: .normal)
        choiceClose.tintColor = Glass.textSecondary
        choiceClose.backgroundColor = Glass.touchableGrid
        choiceClose.accessibilityLabel = "Dismiss"
        choiceClose.accessibilityIdentifier = "strip:smart:close"
        choiceClose.addAction(UIAction { [weak self] _ in
            self?.delegate?.toolbarSmartDismissed()
        }, for: .touchUpInside)
        choiceRow.addSubview(choiceClose)
        for (i, chip) in choiceChips.enumerated() {
            chip.isHidden = true
            chip.addAction(UIAction { [weak self] _ in
                guard let self, let smart = self.smartChip else { return }
                self.delegate?.toolbarSmartChoiceTapped(smart, index: i)
            }, for: .touchUpInside)
            choiceRow.addSubview(chip)
            chip.magic.attach(to: chip, in: choiceRow)
        }
        addSubview(choiceRow)
    }

    /// The card's face for the sheet of the moment.
    private func paintCardFace() {
        smartCard.backgroundColor = Glass.touchableGrid
        magic.paint()
    }

    /// The keyboard went away, or came back: the colours turn only on screen.
    func setMagicRunning(_ running: Bool) {
        magic.setRunning(running)
        for chip in choiceChips { chip.magic.setRunning(running) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The app icon on a light sheet, its dark twin on a dark one.
    private func applyKeycapRing() {
        let dark = Glass.chromeDark
        keycap.fillColor = GlyfMark.face(dark: dark).cgColor
        keycapG.fillColor = GlyfMark.letterColor(dark: dark).cgColor
        keycap.strokeColor = GlyfMark.ring(dark: dark)?.cgColor
        keycap.lineWidth = dark ? 1 : 0
    }

    /// Re-skins after an appearance flip (items re-tint via reloadItems;
    /// the brand keycap turns to the icon's twin for the sheet).
    func applyPalette() {
        divider.backgroundColor = Glass.strokeHairline
        panelIcon.tintColor = Glass.textPrimary
        panelLabel.textColor = Glass.textPrimary
        panelBack.tintColor = Glass.textPrimary
        paintCardFace()
        smartValue.textColor = Glass.textPrimary
        paintChip()
        for chip in choiceChips { chip.magic.paint() }
        choiceClose.backgroundColor = Glass.touchableGrid
        // Suggestion words are drawn with the ink of the moment they were
        // made; redraw them or they stay dark on a sheet that just went dark.
        let words = suggestions
        suggestions = []
        if !words.isEmpty { showSuggestions(words) }
        applyKeycapRing()
        if !panelOpen { glyfButton.backgroundColor = Glass.touchableGrid }
        reloadItems()
    }

    /// The chip's frame while it is showing, for the tour's ring.
    var smartFrame: CGRect? {
        if !smartCard.isHidden { return smartCard.frame }
        return choiceRow.isHidden ? nil : choiceRow.frame
    }
    /// Whether the chip showing is the clipboard's (its ✕ forgets the copy).
    var smartIsPaste: Bool { smartChip?.copiedText != nil && (!smartCard.isHidden || !choiceRow.isHidden) }
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
        for id in Self.shownTools {
            guard let symbol = Self.icons[id] else { continue }
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .regular),
                                              forImageIn: .normal)
            b.tintColor = Glass.textPrimary.withAlphaComponent(0.78)
            // The icon is the thing you see; this is the thing you hit. Same
            // on both sides, so padding a target never shifts an icon off the
            // rhythm the gaps set.
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: Self.itemPad,
                                               bottom: 0, right: Self.itemPad)
            b.layer.cornerRadius = 10
            b.layer.cornerCurve = .continuous
            // Touchable everywhere in its box, not just on the icon's lines: a
            // keyboard drops touches on fully clear pixels (Glass.touchableGrid).
            b.backgroundColor = Glass.touchableGrid
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

    /// Hold an icon and it lifts: slide sideways to reorder, or down into the
    /// g menu's grid to keep it there. (Gboard's gesture, on Glyf's strip.)
    /// Its place stays faint until the delegate settles it: `settleItem`,
    /// `removeItem` or `reloadItems`.
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
            draggingId = nil
            delegate?.toolbarItemDragEnded(id, at: convert(point, to: window))
        default:
            break
        }
    }

    private func item(_ id: String) -> UIView? {
        itemsStack.arrangedSubviews.first { $0.accessibilityIdentifier == "toolbar:\(id)" }
    }

    /// A tool's place on the strip, in window coordinates.
    func itemFrame(_ id: String) -> CGRect? {
        item(id).map { $0.convert($0.bounds, to: nil) }
    }

    /// The held tool back at full strength, as its ghost lands on it.
    func settleItem(_ id: String) {
        guard let b = item(id) else { return }
        UIView.animate(withDuration: 0.24) { b.alpha = 1 }
    }

    /// A tool that went down into the g menu: the row closes over its place.
    func removeItem(_ id: String) {
        guard let b = item(id) else { return reloadItems() }
        b.removeFromSuperview()
        setNeedsLayout()
        guard !Glass.reduceMotion else { return }
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.layoutIfNeeded()
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
            // The lines between suggestion slots go with the suggestions:
            // a panel's title never has slots.
            for line in slotLines { line.isHidden = true }
            runsChip.isHidden = true
            divider.isHidden = hideTools || Glass.solidLook
        } else {
            // Back to exactly one of tools or suggestions. Setting both here
            // (tools on, suggestions on) drew words over the icons after
            // the emoji page closed.
            setPanelAction(symbol: nil, label: nil, handler: nil)
            setPanelReport(handler: nil)
            applyCandidatesVisibility(toolsVisible: !showingCandidates || userPinnedTools)
        }
        if open {
            // The ✕ has no ground of its own and is drawn at the size the
            // tools beside it are drawn, as one of their row (layoutSubviews).
            // It used to sit on a soft fill, and because the slot is a tap
            // target — wider than it is tall — that fill read as a squat pill
            // parked at the end of an otherwise clean row.
            glyfButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            glyfButton.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 21, weight: .regular), forImageIn: .normal)
            glyfButton.tintColor = Glass.textPrimary
            glyfButton.backgroundColor = Glass.touchableGrid
            glyfButton.accessibilityIdentifier = "toolbar:close"
            glyfButton.accessibilityLabel = "Close"
            for layer in [keycap, keycapG, keycapDot] { layer.isHidden = true }
            // Drawn where the key was first, so the surface's spring slides
            // it into its place rather than growing it out of a corner.
            UIView.performWithoutAnimation { glyfButton.layoutIfNeeded() }
        } else {
            glyfButton.setImage(nil, for: .normal)
            // Back to no ground of its own, but still painted: a clear
            // button would stop taking touches at all (see init).
            glyfButton.backgroundColor = Glass.touchableGrid
            glyfButton.accessibilityIdentifier = "toolbar:glyf"
            glyfButton.accessibilityLabel = "Glyf"
            for layer in [keycap, keycapG, keycapDot] { layer.isHidden = false }
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

    /// Report beside the open panel's action, or nil for none.
    func setPanelReport(handler: (() -> Void)?) {
        panelReportHandler = handler
        panelReport.isHidden = handler == nil || panelTitle == nil
        setNeedsLayout()
    }

    /// The chip's own purple, lighter than the accent, and its quiet greys.
    private func paintChip() {
        let accent = Glass.chipAccent
        smartKey.textColor = accent
        smartLead.tintColor = accent
        smartExtra.setTitleColor(accent, for: .normal)
        smartExtra.backgroundColor = accent.withAlphaComponent(0.14)
        smartClose.tintColor = Glass.textSecondary
        smartRule.backgroundColor = Glass.textSecondary.withAlphaComponent(0.35)
        paintChoices()
    }

    /// One chip across the strip, or nil to go back to tools and suggestions.
    /// `extra` names a second action the chip itself does not carry ("Temp"
    /// beside your email, in an email field).
    func showSmart(_ chip: Smart.Chip?, extra: String? = nil) {
        smartChip = chip
        let isRow = chip?.choices != nil
        let wasShowing = !smartCard.isHidden || !choiceRow.isHidden
        smartCard.isHidden = chip == nil || panelTitle != nil || isRow
        choiceRow.isHidden = !isRow || panelTitle != nil
        magic.show(!smartCard.isHidden, fresh: !wasShowing)
        showChoices(chip, fresh: !wasShowing)
        if let chip {
            // A copy (plain, or an address with Send or Buy beside it) is the
            // clipboard pill: the tap pastes it.
            let isPaste = chip.copiedText != nil
            let isEvent: Bool = {
                switch chip { case .event, .booking: return true; default: return false }
            }()
            smartLead.isHidden = !isPaste && !isEvent
            // Every chip can be put away, from the same place at its end.
            smartClose.isHidden = false
            smartLead.image = isPaste || isEvent
                ? UIImage(systemName: isPaste ? "doc.on.clipboard" : "calendar",
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
                    .withTintColor(Glass.chipAccent, renderingMode: .alwaysOriginal) ?? UIImage())
                smartKey.attributedText = NSAttributedString(attachment: spark)
            }
            let second = extra ?? chip.extra
            smartExtra.isHidden = second == nil
            smartExtra.setTitle(second, for: .normal)
            if let label = chip.label {
                let line = NSMutableAttributedString(string: label + "  ", attributes: [
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
            paintCardFace()
            smartCard.accessibilityLabel = "\(chip.key) \(chip.value)"
            // The ✕ leads every chip, so the hairline after it always shows.
            smartRule.isHidden = false
            paintChip()
        }
        if smartCard.isHidden && choiceRow.isHidden {
            // No chip: back to whichever of tools / suggestions the strip was
            // showing. Never both — they share the same space and used to
            // draw over each other when a chip went away.
            applyCandidatesVisibility(toolsVisible: !showingCandidates || userPinnedTools)
        } else {
            scroll.isHidden = true
            candidatesStack.isHidden = true
            for line in slotLines { line.isHidden = true }
            divider.isHidden = true
            runsChip.isHidden = true
        }
        setNeedsLayout()
    }

    /// A details chip shows as a row of chips, one per saved detail, then
    /// Temp; a measurement as one per result; any other chip hides the row.
    private func showChoices(_ chip: Smart.Chip?, fresh: Bool) {
        guard let parts = chip?.choices, panelTitle == nil else {
            choiceCount = 0
            for c in choiceChips {
                c.isHidden = true
                c.magic.show(false, fresh: false)
            }
            return
        }
        let values = parts.values, temp = parts.temp
        choiceCount = min(values.count + (temp ? 1 : 0), choiceChips.count)
        for (i, c) in choiceChips.enumerated() {
            let shown = i < choiceCount
            c.isHidden = !shown
            c.magic.show(shown, fresh: fresh)
            guard shown else { continue }
            let isTemp = temp && i == choiceCount - 1
            c.label.text = isTemp ? "Temp" : values[i]
            c.icon.image = isTemp ? UIImage(systemName: "envelope",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)) : nil
            c.accessibilityIdentifier = isTemp ? "strip:smart:choice:temp" : "strip:smart:choice:\(i)"
            c.accessibilityLabel = isTemp ? "Temp mail" : values[i]
        }
        choiceRow.accessibilityLabel = (values + (temp ? ["Temp mail"] : [])).joined(separator: ", ")
        paintChoices()
        setNeedsLayout()
    }

    /// The row from the strip chip's left to its right, level with the g key
    /// and as tall as the strip chip: its ✕, then each chip as wide as its
    /// words. Too wide for the strip, Temp keeps its width and the details
    /// share what is left, the shorter one whole first.
    private func layoutChoiceRow(left: CGFloat, right: CGFloat, keyMid: CGFloat) {
        let cardH = min(Self.chipHeight, keyMid * 2, (bounds.height - keyMid) * 2)
        choiceRow.frame = CGRect(x: left - 6, y: 0, width: max(0, right - left + 6), height: bounds.height)
        let closeW: CGFloat = 28
        choiceClose.frame = CGRect(x: 0, y: keyMid - closeW / 2, width: closeW, height: closeW)
        let start = closeW + 4
        let chips = Array(choiceChips.prefix(choiceCount))
        guard !chips.isEmpty else { return }
        // Tight for room: less air in and between the chips, and the details
        // a point smaller, so more of each shows ("alex.s219@…", not "alex.s…").
        let roomy = choiceRow.bounds.width - start - 10 * CGFloat(chips.count - 1)
        setChoiceTight(false)
        if chips.map(\.naturalWidth).reduce(0, +) > roomy { setChoiceTight(true) }
        let gap: CGFloat = choiceTight ? 8 : 10
        var widths = chips.map(\.naturalWidth)
        let room = choiceRow.bounds.width - start - gap * CGFloat(chips.count - 1)
        if widths.reduce(0, +) > room, let temp = smartChip?.choices?.temp {
            let values = chips.count - (temp ? 1 : 0)
            var rest = room - (temp ? widths[chips.count - 1] : 0)
            var open = Array(0..<values)
            var settled = false
            while !settled {
                settled = true
                let share = rest / CGFloat(max(1, open.count))
                for i in open where widths[i] <= share {
                    rest -= widths[i]
                    open.removeAll { $0 == i }
                    settled = false
                }
            }
            let share = rest / CGFloat(max(1, open.count))
            for i in open { widths[i] = max(44, share) }
        }
        var x = start
        for (chip, w) in zip(chips, widths) {
            chip.frame = CGRect(x: x, y: keyMid - cardH / 2, width: w, height: cardH)
            chip.layer.cornerRadius = 12
            chip.magic.layout(frame: chip.frame, radius: 12)
            x += w + gap
        }
    }

    private func setChoiceTight(_ tight: Bool) {
        choiceTight = tight
        for c in choiceChips { c.padding = tight ? 10 : 14 }
        paintChoices()
    }

    private func paintChoices() {
        choiceClose.tintColor = Glass.textSecondary
        guard let temp = smartChip?.choices?.temp else { return }
        for (i, c) in choiceChips.prefix(choiceCount).enumerated() {
            let isTemp = temp && i == choiceCount - 1
            let size: CGFloat = choiceTight && !isTemp ? 14 : 15
            c.label.font = isTemp ? .systemFont(ofSize: 15, weight: .semibold) : .systemFont(ofSize: size)
            c.label.textColor = isTemp ? Glass.chipAccent : Glass.textPrimary
            c.icon.tintColor = Glass.chipAccent
        }
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
            /// The emoji the word brings to mind; tapping adds it after.
            case emoji
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
        case .correction, .word, .emoji: title = item.text
        }
        b.setTitle(title, for: .normal)
        let emphasized = item.kind == .correction
        // 17pt: the system bar's "The" stands 12pt tall, which is this size.
        // An emoji a little bigger, as Apple's bar draws one.
        b.titleLabel?.font = .systemFont(ofSize: item.kind == .emoji ? 22 : 17, weight: emphasized ? .semibold : .regular)
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
            // The same rule as applyCandidatesVisibility: never in the
            // website's look, where the strip is the tools and the g pill.
            runsChip.isHidden = (showingCandidates && !userPinnedTools) || Glass.solidLook
        } else {
            runsChip.isHidden = true
        }
        setNeedsLayout()
    }

    /// The apps grid is drawn at icon size, which is small for a thumb. The
    /// strip's margin around it belongs to nothing else, so a near-miss that
    /// would otherwise land on the bare toolbar goes to the button instead.
    /// Only points nothing else claimed are taken, so the divider and the
    /// scrolling tools keep their own.
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
        // No band of our own any more (Glass.stripBand is 0): everything
        // measures off the content box, centred as Apple's bar is.
        let band = Glass.stripBand
        let h = bounds.height - band
        let mid = band + h / 2 - Glass.stripLift
        // The key is 41 by 30, the site's pill a little taller. The lifted
        // middle leaves only 13pt above it on iOS 26, which clips anything
        // drawn above the strip, so a key this tall stands on the strip's
        // top edge instead: its centre two points under the icons'.
        let target = Glass.stripBox(height: 38, mid: mid)
        let keyH: CGFloat = 30
        let keyMid = max(mid, keyH / 2)
        let keyW = GlyfMark.keycapWidth(height: keyH)
        // The button carries its own target: the key plus the tools' padding
        // sideways, plus the air a symbol keeps inside its box, so the key
        // sits on the same rhythm they do.
        let padX = Self.itemPad + Self.gridSlack
        let inkX = Self.margin + Self.gridSlack
        if panelOpen {
            // The ✕ is a 21pt symbol as the tools are, so it is one of their
            // row: padded as they are, from the same margin, the same gap to
            // the first of them as between any two. In the key's wider slot
            // it stood 12pt in from the margin with 12pt more air after it
            // (Arpit, 2026-10-06: "why the fuck doesnt it feel centered, why
            // soo much space after cross").
            glyfButton.frame = CGRect(x: Self.margin - Self.itemPad, y: target.y,
                                      width: glyfButton.intrinsicContentSize.width,
                                      height: target.height)
        } else {
            glyfButton.frame = CGRect(x: inkX - padX, y: target.y,
                                      width: keyW + padX * 2, height: target.height)
        }
        glyfButton.layer.cornerRadius = 9
        let cap = GlyfMark.Keycap(height: keyH, x: padX, midY: keyMid - target.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [keycap, keycapG, keycapDot] { layer.frame = glyfButton.bounds }
        keycap.path = UIBezierPath(roundedRect: cap.key, cornerRadius: cap.radius).cgPath
        keycapG.path = GlyfMark.gPath(in: cap.letter)
        keycapDot.path = CGPath(ellipseIn: cap.dot, transform: nil)
        CATransaction.commit()
        // Where the key's ink ends; past the ✕, a panel's name keeps the
        // distance from its middle that it had from the key's.
        let markRight = glyfButton.frame.midX + keyW / 2
        // Whatever ends the row on the right ends as far in as the key starts
        // on the left, so the strip sits centred over the keys.
        let rightInk = bounds.width - inkX
        divider.isHidden = Glass.solidLook
        let chipW: CGFloat = runsChip.isHidden ? 0 : 64
        if !runsChip.isHidden {
            runsChip.frame = CGRect(x: rightInk - chipW, y: 11,
                                    width: chipW, height: h - 22)
        }
        let left = markRight + (Glass.solidLook ? 11 : 17)
        if !smartCard.isHidden {
            // Level with the g key (Arpit, 2026-09-30: "why did the ai strip
            // fall below, have it at same level as glyf logo"; it sat 5pt
            // lower, clear of the top edge for its glow): centred on the
            // key's middle, as tall as the strip allows there, up to
            // chipHeight. The glow above it fades out at the keyboard's edge.
            let cardH = min(Self.chipHeight, keyMid * 2, (bounds.height - keyMid) * 2)
            let cardY = keyMid - cardH / 2
            smartCard.frame = CGRect(x: left, y: cardY,
                                     width: max(0, rightInk - left), height: cardH)
            let lead = !smartLead.isHidden
            // Gboard's clipboard suggestion is a pill; the rest stay cards.
            smartCard.layer.cornerRadius = lead ? cardH / 2 : 12
            let w = smartCard.bounds.width
            // Arpit, 2026-09-30: "add more inner padding, text seems too close
            // to border", a ✕ on every chip, then "no cross on right looks
            // bad, insert should be the default action". So the ✕ leads (as
            // on Safari's Smart App Banner: close at the far left, the action
            // at the far right): its glyph 14pt inside the stroke, a hairline
            // 10pt either side, then the text; the verb ends 16pt inside the
            // right edge, and a tap anywhere but the ✕ does it.
            let c: CGFloat = 32, glyph: CGFloat = 11
            smartClose.frame = CGRect(x: 14 + glyph / 2 - c / 2, y: (cardH - c) / 2, width: c, height: c)
            let ruleX = 14 + glyph + 10
            smartRule.frame = CGRect(x: ruleX, y: (cardH * 0.28).rounded(), width: 0.5, height: (cardH * 0.44).rounded())
            var right = w - 16
            if !smartExtra.isHidden {
                let extraH: CGFloat = min(28, cardH - 8)
                let extraW = smartExtra.intrinsicContentSize.width + 22
                smartExtra.frame = CGRect(x: w - 12 - extraW, y: (cardH - extraH) / 2,
                                          width: extraW, height: extraH)
                smartExtra.layer.cornerRadius = extraH / 2
                right = smartExtra.frame.minX - 10
            }
            let keyW = smartKey.isHidden ? 0 : min(smartKey.intrinsicContentSize.width, 120)
            smartKey.frame = CGRect(x: right - keyW, y: 0, width: keyW, height: cardH)
            if keyW > 0 { right = smartKey.frame.minX - 10 }
            let contentX = ruleX + 0.5 + 10
            if lead { smartLead.frame = CGRect(x: contentX, y: (cardH - 16) / 2, width: 16, height: 16) }
            let textX = lead ? contentX + 16 + 8 : contentX
            smartValue.frame = CGRect(x: textX, y: 0, width: max(0, right - textX), height: cardH)
            magic.layout(frame: smartCard.frame, radius: smartCard.layer.cornerRadius)
        }
        if !choiceRow.isHidden { layoutChoiceRow(left: left, right: rightInk, keyMid: keyMid) }
        if panelTitle != nil {
            var x = left
            let row = Glass.stripBox(height: h, mid: mid)
            if !panelBack.isHidden {
                panelBack.frame = CGRect(x: x - 4, y: row.y, width: 30, height: row.height)
                x += 28
            }
            panelIcon.frame = CGRect(x: x, y: mid - 12, width: 24, height: 24)
            let textX = panelIcon.isHidden ? x : x + 30
            let actionW: CGFloat = panelAction.isHidden ? 0 : 44
            let reportW: CGFloat = panelReport.isHidden ? 0 : 40
            let action = Glass.stripBox(height: 34, mid: mid)
            panelAction.frame = CGRect(x: bounds.width - actionW - 4, y: action.y,
                                       width: actionW, height: action.height)
            panelReport.frame = CGRect(x: bounds.width - actionW - 4 - reportW, y: action.y,
                                       width: reportW, height: action.height)
            panelLabel.frame = CGRect(x: textX, y: row.y,
                                      width: bounds.width - textX - 10 - actionW - reportW, height: row.height)
        }
        // The g key (or the ✕) stays where it is, and the tools share what is
        // left of the strip evenly: the same air before each of them and
        // after the last (Arpit, 2026-10-06: "keep g on left as it is and
        // then place the left over in space left over equally and just make
        // sure they look good"). The stack spaces their frames, each padded
        // by itemPad, so the gap between frames is the ink's gap less two
        // pads. Too many for that, and they pack and scroll as before.
        let end = bounds.width - (runsChip.isHidden ? 0 : chipW + 13) - Self.margin + Self.itemPad
        let count = itemsStack.arrangedSubviews.count
        let tools = itemsStack.arrangedSubviews.reduce(CGFloat(0)) {
            $0 + $1.intrinsicContentSize.width
        }
        let leadRight = glyfButton.frame.maxX - (panelOpen ? Self.itemPad : padX)
        let rightEdge = runsChip.isHidden ? bounds.width : rightInk - chipW
        let inks = tools - 2 * Self.itemPad * CGFloat(count)
        let inkGap = (rightEdge - leadRight - inks) / CGFloat(count + 1)
        let even = count > 0 && inkGap >= 2 * Self.itemPad
        let toolsLeft = even ? leadRight + inkGap - Self.itemPad : glyfButton.frame.maxX
        let group = even ? tools + (inkGap - 2 * Self.itemPad) * CGFloat(count - 1) : tools
        // Halfway between the grid and the first tool, when a look draws it.
        divider.frame = CGRect(x: ((markRight + toolsLeft) / 2).rounded(), y: 10,
                               width: Glass.hairlineWidth * 2, height: h - 20)
        // The tools live INSIDE this scroll view, which clips them, so the
        // band has to move the scroll itself — offsetting only the stack
        // pushes the icons out through its bottom edge (that is what ate the
        // magnifier's handle and the mic's stand on iOS 18).
        let toolsW = max(0, min(group, end - toolsLeft))
        scroll.frame = CGRect(x: toolsLeft, y: band, width: toolsW, height: h)
        itemsStack.spacing = 0
        // …and inside it the stack is band-relative: the strip's own centring.
        let items = Glass.stripBox(height: min(34, h - 4), mid: mid - band)
        itemsStack.frame = CGRect(x: 0, y: items.y, width: toolsW, height: items.height)
        scroll.contentSize = CGSize(width: toolsW, height: h)
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

// MARK: - A chip's magic, for any card in the strip

/// Every strip chip's magic (Arpit, 2026-09-30: "a colourful glowy border so
/// it feels like its magic, all types of strips", "we should make the
/// suggestion strip glassy"): a conic gradient in Glyf's colours turning
/// under a 2pt stroke on the card's edge and, behind the card, under wider,
/// fainter strokes that fade out 6pt past it (the glow, drawn outside the card
/// only); and a glass face: a frosted fill the sheet shows through, the
/// colours drifting through it as a band, a sheen over its top half and a
/// bright rim inside the border. The face and the border go on the card's own
/// layer, under its words; the glow behind the card, on its parent's layer.
/// Core Animation turns and drifts them; nothing is redrawn frame by frame.
/// Android's twin is MagicChip.
final class ChipMagic {

    /// Violet, magenta, pink, amber, cyan and round to violet again.
    static let colors: [CGColor] = [0x7C5CFF, 0xD35CFF, 0xFF5C8A, 0xFFB547, 0x3CC8FF, 0x7C5CFF]
        .map { UIColor(red: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255,
                       blue: CGFloat($0 & 0xFF) / 255, alpha: 1).cgColor }
    /// How far the glow reaches past the chip's edge.
    static let glowSpread: CGFloat = 6
    /// The glow's strokes, innermost first: each reaches a point further out
    /// than the last and is fainter, so together they fall off softly, with
    /// the square of the distance, to nothing at the spread.
    static let glowBands: [(width: CGFloat, alpha: Float)] = {
        let n = 6
        let step = glowSpread / CGFloat(n)
        let shown = (0..<n).map { k in 0.85 * pow(1 - (Double(k) + 0.5) / Double(n), 2) }
        var bands: [(width: CGFloat, alpha: Float)] = []
        var through = 1.0   // what the wider, outer strokes already leave clear
        for k in stride(from: n - 1, through: 0, by: -1) {
            let alpha = 1 - (1 - shown[k]) / through
            through *= 1 - alpha
            bands.insert((width: step * CGFloat(k + 1) * 2, alpha: Float(alpha)), at: 0)
        }
        return bands
    }()
    /// The glow's strength over the sheet: a dark one needs more to show.
    static var glowStrength: Float { Glass.chromeDark ? 0.55 : 0.40 }

    private let glowRing = CALayer()
    private let glowSpin = CAGradientLayer()
    private let glowMask = CALayer()
    /// The strokes, under a fade to nothing at the keyboard's top edge: iOS
    /// cuts off anything drawn above it, and a glow cut there is a hard line.
    private let glowBox = CALayer()
    private let glowFade = CAGradientLayer()
    private let glowStrokes = ChipMagic.glowBands.map { _ in CAShapeLayer() }
    private let borderRing = CALayer()
    private let borderSpin = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    /// The face, on the same squircle as the border (a layer's own corner
    /// curve and the border's path parted at the corners, and white showed
    /// outside the colours).
    private let cardFill = CAShapeLayer()
    private let glassWash = CALayer()
    private let washFlow = CAGradientLayer()
    private let washMask = CAShapeLayer()
    /// One run of the colours through the card: half as long again as it.
    private var washPeriod: CGFloat = 0
    private let glassSheen = CAGradientLayer()
    private let sheenMask = CAShapeLayer()
    private let glassRim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private weak var card: UIView?
    /// The keyboard is away: nothing turns until it is back.
    private var paused = false

    init() {
        for spin in [glowSpin, borderSpin] {
            spin.type = .conic
            spin.colors = Self.colors
            spin.startPoint = CGPoint(x: 0.5, y: 0.5)
            spin.endPoint = CGPoint(x: 0.5, y: 0)
        }
        for (band, stroke) in zip(Self.glowBands, glowStrokes) {
            stroke.fillColor = nil
            stroke.strokeColor = UIColor.black.cgColor
            stroke.opacity = band.alpha
            glowBox.addSublayer(stroke)
        }
        glowFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        glowBox.mask = glowFade
        glowMask.addSublayer(glowBox)
        // Drawn once and kept: only the gradient under it moves.
        glowMask.shouldRasterize = true
        glowMask.rasterizationScale = UIScreen.main.scale
        glowRing.mask = glowMask
        glowRing.addSublayer(glowSpin)
        glowRing.isHidden = true
        glowRing.opacity = Self.glowStrength
        borderMask.fillColor = nil
        borderMask.strokeColor = UIColor.black.cgColor
        // 2pt, the card's outermost edge (Arpit: "expand border").
        borderMask.lineWidth = 2
        borderRing.mask = borderMask
        borderRing.addSublayer(borderSpin)
        // Two runs of the colours side by side: sliding by one run loops.
        washFlow.colors = Self.colors + Self.colors.dropFirst()
        washFlow.startPoint = CGPoint(x: 0, y: 0.5)
        washFlow.endPoint = CGPoint(x: 1, y: 0.5)
        washFlow.anchorPoint = .zero
        glassWash.addSublayer(washFlow)
        glassWash.mask = washMask
        glassSheen.startPoint = CGPoint(x: 0.5, y: 0)
        glassSheen.endPoint = CGPoint(x: 0.5, y: 1)
        glassSheen.locations = [0, 0.6]
        glassSheen.mask = sheenMask
        glassRim.startPoint = CGPoint(x: 0.5, y: 0)
        glassRim.endPoint = CGPoint(x: 0.5, y: 1)
        rimMask.fillColor = nil
        rimMask.strokeColor = UIColor.black.cgColor
        rimMask.lineWidth = 1
        glassRim.mask = rimMask
    }

    /// The glow behind `card` on `parent`'s layer (only outside the card:
    /// its face is glass, and a glow under it would show inside the edge);
    /// the face, wash, sheen, rim and border on the card, under its words.
    func attach(to card: UIView, in parent: UIView) {
        self.card = card
        parent.layer.insertSublayer(glowRing, below: card.layer)
        for glass in [borderRing, glassRim, glassSheen, glassWash, cardFill] as [CALayer] {
            card.layer.insertSublayer(glass, at: 0)
        }
        paint()
    }

    /// The face for the sheet of the moment (a layer's CGColor does not
    /// follow dark mode by itself).
    func paint() {
        let dark = Glass.chromeDark
        let white = { (a: CGFloat) in UIColor.white.withAlphaComponent(a).cgColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardFill.fillColor = white(dark ? 0.10 : 0.55)
        glassWash.opacity = dark ? 0.14 : 0.10
        glassSheen.colors = [white(dark ? 0.12 : 0.6), white(0)]
        glassRim.colors = [white(dark ? 0.32 : 0.95), white(dark ? 0.05 : 0.3)]
        glowRing.opacity = Self.glowStrength
        CATransaction.commit()
    }

    /// The card at `frame` in its parent, with corners of `radius`; `edgeY`
    /// is the keyboard's top edge in the parent's coordinates (the glow is
    /// clear there and whole 4pt below it).
    func layout(frame card: CGRect, radius: CGFloat, edgeY: CGFloat = 0) {
        let spread = Self.glowSpread
        let bounds = CGRect(origin: .zero, size: card.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowRing.frame = card.insetBy(dx: -spread, dy: -spread)
        glowMask.frame = glowRing.bounds
        glowBox.frame = glowMask.bounds
        let h = max(1, glowBox.bounds.height)
        glowFade.frame = glowBox.bounds
        glowFade.startPoint = CGPoint(x: 0.5, y: (edgeY - glowRing.frame.minY) / h)
        glowFade.endPoint = CGPoint(x: 0.5, y: (edgeY + 4 - glowRing.frame.minY) / h)
        // Each band runs from half a point under the border (so no gap shows
        // at the corners) out to its reach.
        let edge = CGRect(x: spread, y: spread, width: card.width, height: card.height)
        for (band, stroke) in zip(Self.glowBands, glowStrokes) {
            let reach = band.width / 2
            let centre = (reach - 0.5) / 2
            stroke.frame = glowBox.bounds
            stroke.lineWidth = reach + 0.5
            stroke.path = UIBezierPath(roundedRect: edge.insetBy(dx: -centre, dy: -centre),
                                       cornerRadius: radius + centre).cgPath
        }
        Self.cover(glowRing.bounds, with: glowSpin)
        let inside = { (inset: CGFloat) in
            UIBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                         cornerRadius: max(0, radius - inset)).cgPath
        }
        // The face 1pt in, under the 2pt border, both on one squircle: no
        // white shows outside the colours. The border inset by half its
        // line, so the whole 2pt lies on the card.
        cardFill.frame = bounds
        cardFill.path = inside(1)
        borderRing.frame = bounds
        borderMask.frame = bounds
        borderMask.path = inside(1)
        Self.cover(bounds, with: borderSpin)
        for (glass, mask) in [(glassWash, washMask), (glassSheen, sheenMask), (glassRim, rimMask)] as [(CALayer, CAShapeLayer)] {
            glass.frame = bounds
            mask.frame = bounds
        }
        washMask.path = inside(1)
        let period = max(1, (card.width * 1.5).rounded())
        washFlow.bounds = CGRect(x: 0, y: 0, width: period * 2, height: card.height)
        washFlow.position = .zero
        if period != washPeriod {
            washPeriod = period
            // A new width is a new run: start the drift over on it.
            if washFlow.animation(forKey: "flow") != nil { startFlow() }
        }
        // Inside the 2pt border; the rim's 1pt line just within it.
        sheenMask.path = inside(2)
        rimMask.path = inside(2.5)
        CATransaction.commit()
    }

    /// A square over the whole diagonal, so it covers the rect at any angle
    /// it turns to. Bounds and position, not frame: it may be mid-turn. The
    /// glow's and the border's share the card's centre, so their colours
    /// line up.
    private static func cover(_ rect: CGRect, with spin: CAGradientLayer) {
        let side = ceil(hypot(rect.width, rect.height))
        spin.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        spin.position = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// With the card: one that has just appeared fades its glow in, and the
    /// colours move only while one shows. Reduce Motion keeps them still.
    func show(_ showing: Bool, fresh: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowRing.isHidden = !showing
        glowRing.opacity = Self.glowStrength
        CATransaction.commit()
        guard showing else { return stop() }
        if fresh, !Glass.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = Self.glowStrength
            fade.duration = 0.25
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            glowRing.add(fade, forKey: "fade")
        }
        start()
    }

    /// The keyboard went away, or came back: the colours move only on screen.
    func setRunning(_ running: Bool) {
        paused = !running
        if running { start() } else { stop() }
    }

    private func start() {
        guard !paused, !Glass.reduceMotion, card?.isHidden == false, !glowRing.isHidden,
              glowSpin.animation(forKey: "turn") == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = CGFloat.pi * 2
        turn.duration = 4
        turn.repeatCount = .infinity
        // A slow turn looks as smooth at 30 frames a second as at 120.
        turn.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        // Added in one go, so the border and the glow turn as one.
        for spin in [glowSpin, borderSpin] { spin.add(turn, forKey: "turn") }
        startFlow()
    }

    /// The colours inside drift one run to the left every 6 s, and loop.
    private func startFlow() {
        let flow = CABasicAnimation(keyPath: "transform.translation.x")
        flow.fromValue = 0
        flow.toValue = -washPeriod
        flow.duration = 6
        flow.repeatCount = .infinity
        flow.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        washFlow.add(flow, forKey: "flow")
    }

    private func stop() {
        for spin in [glowSpin, borderSpin] { spin.removeAnimation(forKey: "turn") }
        washFlow.removeAnimation(forKey: "flow")
    }
}

/// One chip of a row of them (Arpit, 2026-10-01: "it should be 2-3 diff
/// strips not all in one strip"): a saved detail, or Temp, on its own glowing
/// glass card. Its words are the action; the row has the one ✕.
final class GlowChip: UIControl {
    let label = UILabel()
    let icon = UIImageView()
    let magic = ChipMagic()
    /// Room either side of the words: less when a row is tight for space.
    var padding: CGFloat = 14

    override init(frame: CGRect) {
        super.init(frame: frame)
        // A keyboard extension takes no touches on clear pixels.
        backgroundColor = Glass.touchableGrid
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// What it needs to show its words whole.
    var naturalWidth: CGFloat {
        let words = ceil(label.intrinsicContentSize.width)
        let mark: CGFloat = icon.image == nil ? 0 : 17 + 6
        return words + mark + padding * 2
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let mark: CGFloat = icon.image == nil ? 0 : 17
        let gap: CGFloat = mark > 0 ? 6 : 0
        let words = min(ceil(label.intrinsicContentSize.width), bounds.width - padding * 2 - mark - gap)
        let x = max(padding, (bounds.width - mark - gap - words) / 2)
        icon.frame = CGRect(x: x, y: (bounds.height - 17) / 2, width: mark, height: 17)
        label.frame = CGRect(x: x + mark + gap, y: 0, width: max(0, words), height: bounds.height)
    }
}
