import UIKit

protocol TranslationHUDDelegate: AnyObject {
    func hudRequestTranslation(of text: String, completion: @escaping (String?) -> Void)
    func hudReplaceDraft(with text: String, consumedBefore: Int)
    func hudClosed()
}

/// §6.13 `T` ★ — the persistent Translation HUD: a 44pt strip ABOVE the
/// toolbar that live-translates the draft while you type (updates on word
/// commits, debounced). Tap the strip to replace the draft with the
/// translation — explicit action, never automatic (§6.4 spirit).
final class TranslationHUD: UIView {

    weak var delegate: TranslationHUDDelegate?

    private let langChip = UILabel()
    private let textLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var pendingWork: DispatchWorkItem?
    private var lastSource = ""
    private var lastTranslation = ""
    private var lastConsumed = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.fillBar
        layer.borderWidth = Glass.hairlineWidth
        layer.borderColor = Glass.strokeHairline.cgColor
        accessibilityIdentifier = "hud:translate"

        langChip.font = .systemFont(ofSize: 11, weight: .bold)
        langChip.textColor = Glass.surfaceCard
        langChip.backgroundColor = Glass.textPrimary
        langChip.textAlignment = .center
        langChip.layer.cornerRadius = 8
        langChip.layer.masksToBounds = true
        addSubview(langChip)

        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textColor = Glass.textPrimary
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.accessibilityIdentifier = "hud:text"
        addSubview(textLabel)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "hud:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.hudClosed() },
                              for: .touchUpInside)
        addSubview(closeButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(applyTapped))
        addGestureRecognizer(tap)

        refreshTarget()
        textLabel.text = "Translating as you type — tap to replace your draft"
        textLabel.textColor = Glass.textSecondary
    }

    required init?(coder: NSCoder) { fatalError() }

    func refreshTarget() {
        let target = SettingsStore.current.translateTarget
        langChip.text = "  → \(String(target.prefix(9)).uppercased())  "
        setNeedsLayout()
    }

    /// Called by the VC on word commits (space/return) with the draft.
    func draftChanged(_ draft: String, consumedBefore: Int) {
        let text = String(draft.suffix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
        lastConsumed = consumedBefore
        guard !text.isEmpty, text != lastSource else { return }
        lastSource = text
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.delegate?.hudRequestTranslation(of: text) { [weak self] translated in
                guard let self, let translated, self.lastSource == text else { return }
                self.lastTranslation = translated
                self.textLabel.text = translated
                self.textLabel.textColor = Glass.textPrimary
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @objc private func applyTapped() {
        guard !lastTranslation.isEmpty else { return }
        delegate?.hudReplaceDraft(with: lastTranslation, consumedBefore: lastConsumed)
        lastSource = ""
        lastTranslation = ""
        textLabel.text = "Replaced — keep typing"
        textLabel.textColor = Glass.textSecondary
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let chipW = min(110, langChip.intrinsicContentSize.width + 6)
        langChip.frame = CGRect(x: 10, y: 12, width: chipW, height: 20)
        closeButton.frame = CGRect(x: bounds.width - 38, y: 8, width: 30, height: 28)
        textLabel.frame = CGRect(x: 18 + chipW, y: 0,
                                 width: bounds.width - chipW - 62, height: bounds.height)
    }
}
