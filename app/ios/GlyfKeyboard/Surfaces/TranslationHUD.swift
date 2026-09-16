import UIKit

protocol TranslationHUDDelegate: AnyObject {
    func hudClosed()
    func hudRequestTranslation(of text: String, completion: @escaping (String?) -> Void)
    func hudReplaceDraft(with text: String, consumedBefore: Int)
}

/// §6.13 T / website 6.6 — translate never covers the keys. It takes the
/// strip: a language track on the left, the live translation in the middle,
/// and Replace on the right. Typing keeps working underneath the whole time.
final class TranslationHUD: UIView {

    weak var delegate: TranslationHUDDelegate?

    /// The website's three, with the short codes it shows at phone widths.
    private static let languages: [(code: String, name: String)] = [
        ("HI", "Hindi"), ("ES", "Spanish"), ("FR", "French"),
    ]

    private let track = UIView()
    private let thumb = UIView()
    private var pills: [UIButton] = []
    private let textLabel = UILabel()
    private let replaceButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var pendingWork: DispatchWorkItem?
    private var lastSource = ""
    private var lastTranslation = ""
    private var lastConsumed = 0
    private var selected = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.solidLook ? .clear : Glass.fillBar
        if !Glass.solidLook {
            layer.borderWidth = Glass.hairlineWidth
            layer.borderColor = Glass.strokeHairline.cgColor
        }
        accessibilityIdentifier = "hud:translate"

        track.backgroundColor = Glass.fillSoft
        track.layer.cornerCurve = .continuous
        addSubview(track)

        thumb.backgroundColor = Glass.fillKey
        thumb.layer.cornerCurve = .continuous
        thumb.layer.shadowColor = Glass.keyShadowColor.cgColor
        thumb.layer.shadowOpacity = Glass.keyShadowOpacity
        thumb.layer.shadowOffset = Glass.keyShadowOffset
        thumb.layer.shadowRadius = 0
        track.addSubview(thumb)

        for (i, lang) in Self.languages.enumerated() {
            let pill = UIButton(type: .system)
            pill.setTitle(lang.code, for: .normal)
            pill.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            pill.accessibilityIdentifier = "hud:lang:\(lang.code)"
            pill.addAction(UIAction { [weak self] _ in self?.select(i) }, for: .touchUpInside)
            track.addSubview(pill)
            pills.append(pill)
        }

        textLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        textLabel.textColor = Glass.textPrimary
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.accessibilityIdentifier = "hud:text"
        textLabel.text = "…"
        addSubview(textLabel)

        replaceButton.setTitle("Replace", for: .normal)
        replaceButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        replaceButton.setTitleColor(.white, for: .normal)
        replaceButton.backgroundColor = Glass.imBlue
        replaceButton.layer.cornerCurve = .continuous
        replaceButton.accessibilityIdentifier = "hud:replace"
        replaceButton.addAction(UIAction { [weak self] _ in self?.applyTapped() },
                                for: .touchUpInside)
        addSubview(replaceButton)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold), forImageIn: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "hud:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.hudClosed() },
                              for: .touchUpInside)
        addSubview(closeButton)

        refreshTarget()
        updateReplaceEnabled()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Follows whatever the app (or a T hold) set as the target language.
    func refreshTarget() {
        let target = SettingsStore.current.translateTarget
        selected = Self.languages.firstIndex { $0.name == target } ?? 0
        applySelection(animated: false)
    }

    private func select(_ i: Int) {
        guard i != selected else { return }
        selected = i
        SettingsStore.update { $0.translateTarget = Self.languages[i].name }
        applySelection(animated: true)
        // The language changed: translate the same draft again.
        let source = lastSource
        lastSource = ""
        lastTranslation = ""
        textLabel.text = "…"
        updateReplaceEnabled()
        if !source.isEmpty { draftChanged(source, consumedBefore: lastConsumed) }
    }

    private func applySelection(animated: Bool) {
        for (i, pill) in pills.enumerated() {
            pill.setTitleColor(i == selected ? Glass.textPrimary : Glass.textSecondary,
                               for: .normal)
        }
        setNeedsLayout()
        guard animated else { return }
        layoutIfNeeded()
    }

    /// Called by the VC on word commits (space/return) with the draft.
    func draftChanged(_ draft: String, consumedBefore: Int) {
        let text = String(draft.suffix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
        lastConsumed = consumedBefore
        guard !text.isEmpty, text != lastSource else { return }
        lastSource = text
        // The draft moved on: never leave the previous translation standing.
        lastTranslation = ""
        textLabel.text = "…"
        updateReplaceEnabled()
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.delegate?.hudRequestTranslation(of: text) { [weak self] translated in
                guard let self, let translated, self.lastSource == text else { return }
                self.lastTranslation = translated
                self.textLabel.text = translated
                self.textLabel.textColor = Glass.textPrimary
                self.updateReplaceEnabled()
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func updateReplaceEnabled() {
        let on = !lastTranslation.isEmpty
        replaceButton.isEnabled = on
        replaceButton.alpha = on ? 1 : 0.3
    }

    private func applyTapped() {
        guard !lastTranslation.isEmpty else { return }
        delegate?.hudReplaceDraft(with: lastTranslation, consumedBefore: lastConsumed)
        lastSource = ""
        lastTranslation = ""
        textLabel.text = "…"
        updateReplaceEnabled()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        // Track: 3pt padding, 2pt gaps, 30pt pills — the search tab track.
        let pillW: CGFloat = 35, pad: CGFloat = 3, gap: CGFloat = 2, pillH: CGFloat = 30
        let trackW = pillW * CGFloat(pills.count) + gap * CGFloat(pills.count - 1) + pad * 2
        let trackH = pillH + pad * 2
        track.frame = CGRect(x: 8, y: (h - trackH) / 2, width: trackW, height: trackH)
        track.layer.cornerRadius = trackH / 2
        for (i, pill) in pills.enumerated() {
            pill.frame = CGRect(x: pad + CGFloat(i) * (pillW + gap), y: pad,
                                width: pillW, height: pillH)
        }
        thumb.frame = pills.indices.contains(selected) ? pills[selected].frame : .zero
        thumb.layer.cornerRadius = pillH / 2
        track.sendSubviewToBack(thumb)

        closeButton.frame = CGRect(x: bounds.width - 32, y: 0, width: 28, height: h)
        let replaceW: CGFloat = 84, replaceH: CGFloat = 30
        replaceButton.frame = CGRect(x: bounds.width - 32 - replaceW - 6,
                                     y: (h - replaceH) / 2,
                                     width: replaceW, height: replaceH)
        replaceButton.layer.cornerRadius = replaceH / 2
        let textX = track.frame.maxX + 8
        textLabel.frame = CGRect(x: textX, y: 0,
                                 width: max(20, replaceButton.frame.minX - textX - 8), height: h)
    }
}
