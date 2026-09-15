import UIKit

protocol ToolbarDelegate: AnyObject {
    func toolbarGlyfTapped()
    func toolbarItemTapped(_ id: String)
    func toolbarItemLongPressed(_ id: String)
    func toolbarSuggestionTapped(_ suggestion: GlyfToolbar.Suggestion)
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

    /// item id → SF Symbol
    static let icons: [String: String] = [
        "search": "magnifyingglass",
        "clipboard": "doc.on.clipboard",
        "vault": "person.text.rectangle",
        "dictation": "mic",
        "emoji": "face.smiling",
        "translate": "translate",
        "settings": "gearshape",
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
        let dot = CALayer()
        dot.backgroundColor = Glass.accentPrimary.cgColor
        dot.frame = CGRect(x: 31, y: 6, width: 6, height: 6)
        dot.cornerRadius = 3
        dot.shadowColor = Glass.accentPrimary.cgColor
        dot.shadowOpacity = 0.9
        dot.shadowRadius = 3
        dot.shadowOffset = .zero
        glyfButton.layer.addSublayer(dot)
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
        scroll.addSubview(itemsStack)

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

        reloadItems()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Re-skins after an appearance flip (items re-tint via reloadItems;
    /// the brand keycap stays constant by design).
    func applyPalette() {
        divider.backgroundColor = Glass.strokeHairline
        // On dark chrome the ink pill needs a faint ring to stay separate
        // from the backdrop (black-on-black otherwise).
        glyfButton.layer.borderWidth = Glass.chromeDark ? 1 : 0
        glyfButton.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        reloadItems()
    }

    func reloadItems() {
        itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let s = SettingsStore.current
        for id in s.toolbarOrder where !s.toolbarHidden.contains(id) {
            guard let symbol = Self.icons[id] else { continue }
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20),
                                              forImageIn: .normal)
            b.tintColor = Glass.textSecondary
            b.accessibilityIdentifier = "toolbar:\(id)"
            b.accessibilityLabel = id
            b.widthAnchor.constraint(equalToConstant: 42).isActive = true
            b.addAction(UIAction { [weak self] _ in
                self?.delegate?.toolbarItemTapped(id)
            }, for: .touchUpInside)
            let long = UILongPressGestureRecognizer(target: self, action: #selector(itemLong(_:)))
            long.minimumPressDuration = 0.4
            b.addGestureRecognizer(long)
            itemsStack.addArrangedSubview(b)
        }
        setNeedsLayout()
    }

    @objc private func itemLong(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let b = g.view as? UIButton,
              let id = b.accessibilityIdentifier?.split(separator: ":").last
        else { return }
        delegate?.toolbarItemLongPressed(String(id))
    }

    @objc private func glyfTapped() {
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
        scroll.isHidden = !toolsVisible
        divider.isHidden = !toolsVisible
        candidatesStack.isHidden = toolsVisible || !showingCandidates
        runsChip.isHidden = runsRemaining == nil || !toolsVisible
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
        b.backgroundColor = emphasized ? Glass.fillBar : .clear
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
        glyfButton.frame = CGRect(x: 6, y: 6, width: 44, height: bounds.height - 12)
        divider.frame = CGRect(x: 58, y: 10, width: Glass.hairlineWidth * 2,
                               height: bounds.height - 20)
        let chipW: CGFloat = runsChip.isHidden ? 0 : 64
        if !runsChip.isHidden {
            runsChip.frame = CGRect(x: bounds.width - chipW - 6, y: 11,
                                    width: chipW, height: bounds.height - 22)
        }
        let left: CGFloat = 64
        let width = bounds.width - left - chipW - 10
        scroll.frame = CGRect(x: left, y: 0, width: width, height: bounds.height)
        let stackW = max(width, CGFloat(itemsStack.arrangedSubviews.count) * 48)
        itemsStack.frame = CGRect(x: 0, y: 4, width: stackW, height: bounds.height - 8)
        scroll.contentSize = CGSize(width: stackW, height: bounds.height)
        candidatesStack.frame = CGRect(x: left, y: 6, width: bounds.width - left - 8,
                                       height: bounds.height - 12)
    }
}
