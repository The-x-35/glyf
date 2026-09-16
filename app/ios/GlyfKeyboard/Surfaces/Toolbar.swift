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
}

/// §6.2 — the 44pt strip above the keys. When autocorrect candidates show,
/// the toolbar collapses to the Glyf button only and candidates take the
/// strip; tapping the Glyf button restores the tools. Never two strips.
final class GlyfToolbar: UIView {

    weak var delegate: ToolbarDelegate?

    private let glyfButton = UIButton(type: .system)
    private let divider = UIView()
    private let scroll = UIScrollView()
    private let itemsStack = UIStackView()
    private let candidatesStack = UIStackView()
    private let runsChip = UIButton(type: .system)
    private let brandDot = CALayer()
    /// Panel mode (website parity): the strip keeps its place, the brand pill
    /// turns into a close button and the rest becomes "icon + panel name".
    private let panelLabel = UILabel()
    private let panelIcon = UIImageView()
    /// Deeper panel screens keep their way back in the strip, so the panel
    /// itself never spends a row on a chevron.
    private let panelBack = UIButton(type: .system)
    private(set) var panelTitle: String?
    /// Smart chip: one card across the strip, accent key then value.
    private let smartCard = UIControl()
    private let smartKey = UILabel()
    private let smartValue = UILabel()
    private(set) var smartChip: Smart.Chip?
    /// The strip item currently lifted by a hold, if any.
    private var draggingId: String?
    /// Where a dropped tool would land, drawn as a thin accent bar.
    private let dropMarker = UIView()

    /// item id → SF Symbol
    static let icons: [String: String] = [
        "search": "magnifyingglass",
        "clipboard": "doc.on.clipboard",
        "vault": "person.text.rectangle",
        "dictation": "mic",
        "emoji": "face.smiling",
        "translate": "translate",
        "settings": "gearshape",
        "skills": "bolt",
        "rewrite": "wand.and.stars",
        "ask": "sparkles",
    ]

    private(set) var showingCandidates = false
    /// User tapped Glyf to restore tools while candidates were up.
    private var userPinnedTools = false

    init() {
        super.init(frame: .zero)

        // The brand mark IS the button — the same confident black keycap as
        // the app's tab bar: ink ground, bold white g, glowing accent dot.
        glyfButton.setTitle("g", for: .normal)
        glyfButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        glyfButton.setTitleColor(.white, for: .normal)
        // Brand pill is ALWAYS ink — textPrimary flips white on dark chrome
        // and would swallow the white "g".
        glyfButton.backgroundColor = Glass.brandInk
        glyfButton.layer.cornerRadius = 10
        glyfButton.layer.cornerCurve = .continuous
        glyfButton.layer.shadowOpacity = 0.28
        glyfButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        glyfButton.layer.shadowRadius = 3
        glyfButton.layer.shadowColor = UIColor.black.cgColor
        brandDot.backgroundColor = Glass.accentPrimary.cgColor
        brandDot.frame = CGRect(x: 31, y: 6, width: 6, height: 6)
        brandDot.cornerRadius = 3
        brandDot.shadowColor = Glass.accentPrimary.cgColor
        brandDot.shadowOpacity = 0.9
        brandDot.shadowRadius = 3
        brandDot.shadowOffset = .zero
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
        panelBack.addAction(UIAction { [weak self] _ in self?.delegate?.toolbarBackTapped() },
                            for: .touchUpInside)
        addSubview(panelBack)

        smartCard.backgroundColor = Glass.fillKey
        smartCard.layer.cornerRadius = 12
        smartCard.layer.cornerCurve = .continuous
        smartCard.layer.shadowColor = Glass.keyShadowColor.cgColor
        smartCard.layer.shadowOpacity = 1
        smartCard.layer.shadowRadius = 0
        smartCard.layer.shadowOffset = CGSize(width: 0, height: 1)
        smartCard.isHidden = true
        smartCard.accessibilityIdentifier = "strip:smart"
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
        addSubview(smartCard)

        reloadItems()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Re-skins after an appearance flip (items re-tint via reloadItems;
    /// the brand keycap stays constant by design).
    func applyPalette() {
        divider.backgroundColor = Glass.strokeHairline
        // On dark chrome the ink pill needs a faint ring to stay separate
        // from the backdrop (black-on-black otherwise). The website uses a
        // half-point ring at 18% and no drop shadow.
        glyfButton.layer.borderWidth = Glass.chromeDark ? (Glass.siteLook ? 0.5 : 1) : 0
        glyfButton.layer.borderColor = UIColor.white
            .withAlphaComponent(Glass.siteLook ? 0.18 : 0.35).cgColor
        glyfButton.layer.shadowOpacity = Glass.siteLook ? 0 : 0.28
        glyfButton.backgroundColor = Glass.siteLook && Glass.isDark ? .black : Glass.brandInk
        reloadItems()
    }

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
            long.allowableMovement = .greatestFiniteMagnitude
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
    func showPanelHeader(icon: String?, title: String?, canGoBack: Bool = false) {
        panelTitle = title
        panelBack.isHidden = !(title != nil && canGoBack)
        let open = title != nil
        panelLabel.text = title
        panelLabel.isHidden = !open
        panelIcon.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        panelIcon.image = icon.flatMap { UIImage(systemName: $0) }
        panelIcon.isHidden = !open || panelIcon.image == nil
        scroll.isHidden = open
        candidatesStack.isHidden = open || !showingCandidates
        runsChip.isHidden = open || runsRemaining == nil || Glass.solidLook
        divider.isHidden = open || Glass.siteLook
        if open {
            glyfButton.setTitle(nil, for: .normal)
            glyfButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            glyfButton.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
            glyfButton.tintColor = Glass.textPrimary
            glyfButton.backgroundColor = Glass.fillSoft
            glyfButton.accessibilityIdentifier = "toolbar:close"
            glyfButton.accessibilityLabel = "Close"
            brandDot.isHidden = true
        } else {
            glyfButton.setImage(nil, for: .normal)
            glyfButton.setTitle("g", for: .normal)
            glyfButton.backgroundColor = Glass.siteLook && Glass.isDark ? .black : Glass.brandInk
            glyfButton.accessibilityIdentifier = "toolbar:glyf"
            glyfButton.accessibilityLabel = "Glyf"
            brandDot.isHidden = false
        }
        setNeedsLayout()
    }

    /// One chip across the strip, or nil to go back to tools and suggestions.
    func showSmart(_ chip: Smart.Chip?) {
        smartChip = chip
        smartCard.isHidden = chip == nil || panelTitle != nil
        if let chip {
            smartKey.text = chip.key
            smartValue.text = chip.value
            smartCard.backgroundColor = Glass.fillKey
            smartCard.layer.shadowColor = Glass.keyShadowColor.cgColor
            smartCard.accessibilityLabel = "\(chip.key) \(chip.value)"
        }
        let hide = !smartCard.isHidden
        scroll.isHidden = hide || panelTitle != nil
        candidatesStack.isHidden = hide || panelTitle != nil || !showingCandidates
        divider.isHidden = hide || Glass.siteLook
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
        if items == suggestions, showingCandidates == !items.isEmpty { return }
        suggestions = items
        candidatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, item) in items.enumerated() {
            let b = suggestionButton(item)
            b.accessibilityIdentifier = "suggest:\(i)"
            b.addAction(UIAction { [weak self] _ in self?.delegate?.toolbarSuggestionTapped(item) },
                        for: .touchUpInside)
            candidatesStack.addArrangedSubview(b)
        }
        showingCandidates = !items.isEmpty
        if items.isEmpty { userPinnedTools = false }
        applyCandidatesVisibility(toolsVisible: items.isEmpty || userPinnedTools)
    }

    private func applyCandidatesVisibility(toolsVisible: Bool) {
        guard panelTitle == nil else { return }   // a panel owns the strip
        scroll.isHidden = !toolsVisible
        divider.isHidden = !toolsVisible
        candidatesStack.isHidden = toolsVisible || !showingCandidates
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
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: emphasized ? .semibold : .regular)
        b.setTitleColor(item.kind == .literal ? Glass.textSecondary : Glass.textPrimary, for: .normal)
        // The website marks the best candidate by weight alone, no pill.
        b.backgroundColor = (emphasized && !Glass.siteLook) ? Glass.fillBar : .clear
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

    override func layoutSubviews() {
        super.layoutSubviews()
        // Website strip: a g pill 1.18x the strip height wide and 0.78x tall,
        // then the tools spread across the rest. No divider.
        let h = bounds.height
        let pillW = (h * 1.18).rounded()
        let pillH = (h * 0.78).rounded()
        glyfButton.frame = CGRect(x: 5, y: (h - pillH) / 2, width: pillW, height: pillH)
        brandDot.frame = CGRect(x: pillW - pillW * 0.20 - 6, y: pillH * 0.18, width: 6, height: 6)
        divider.isHidden = Glass.siteLook
        divider.frame = CGRect(x: pillW + 11, y: 10, width: Glass.hairlineWidth * 2,
                               height: h - 20)
        let chipW: CGFloat = runsChip.isHidden ? 0 : 64
        if !runsChip.isHidden {
            runsChip.frame = CGRect(x: bounds.width - chipW - 6, y: 11,
                                    width: chipW, height: h - 22)
        }
        let left = pillW + (Glass.siteLook ? 11 : 17)
        let width = bounds.width - left - chipW - 6
        if !smartCard.isHidden {
            let cardH = (h * 0.78).rounded()
            smartCard.frame = CGRect(x: left, y: (h - cardH) / 2,
                                     width: max(0, bounds.width - left - 6), height: cardH)
            let keyW = min(smartKey.intrinsicContentSize.width, 120)
            smartKey.frame = CGRect(x: 14, y: 0, width: keyW, height: cardH)
            smartValue.frame = CGRect(x: 14 + keyW + 10, y: 0,
                                      width: max(0, smartCard.bounds.width - keyW - 38),
                                      height: cardH)
        }
        if panelTitle != nil {
            var x = left
            if !panelBack.isHidden {
                panelBack.frame = CGRect(x: x - 4, y: 0, width: 30, height: h)
                x += 28
            }
            panelIcon.frame = CGRect(x: x, y: (h - 24) / 2, width: 24, height: 24)
            let textX = panelIcon.isHidden ? x : x + 30
            panelLabel.frame = CGRect(x: textX, y: 0, width: bounds.width - textX - 10, height: h)
        }
        scroll.frame = CGRect(x: left, y: 0, width: width, height: h)
        itemsStack.frame = CGRect(x: 0, y: (h - 34) / 2, width: width, height: 34)
        scroll.contentSize = CGSize(width: width, height: h)
        candidatesStack.frame = CGRect(x: left, y: 6, width: bounds.width - left - 8,
                                       height: h - 12)
    }
}
