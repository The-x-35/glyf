import UIKit

/// Voice typing's strip (Android twin: DictationStripView): ✕ throws the
/// words away, the words come in as they are heard, Done types them. It
/// takes the strip's place over live keys, the way Translate does.
final class VoiceStrip: UIView {

    enum Mode: Equatable {
        /// The mic opened the app; nothing heard here yet.
        case opening
        case listening(String)
        /// Done tapped: the last words are being finished.
        case finishing(String)
        /// Typed in: Polish offers a cleaned-up version (dictation.clean).
        case typed(String)
        case polishing(String)
        /// Polished: Undo puts the words back as they were said.
        case polished(String)
    }

    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?
    var onPolish: (() -> Void)?
    var onUndo: (() -> Void)?
    /// The mic beside Polish: say more without going back to the g menu.
    var onAgain: (() -> Void)?

    private let closeButton = UIButton(type: .system)
    private let dot = UIView()
    private let textLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let againButton = UIButton(type: .system)
    private(set) var mode: Mode = .opening

    init() {
        super.init(frame: .zero)
        // Never fully clear: a keyboard drops touches on clear pixels.
        backgroundColor = Glass.solidLook ? Glass.touchableGrid : Glass.fillBar
        accessibilityIdentifier = "voice:strip"

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "voice:cancel"
        closeButton.accessibilityLabel = "Cancel"
        closeButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        addSubview(closeButton)

        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 4
        addSubview(dot)

        textLabel.font = .systemFont(ofSize: 17, weight: .regular)
        textLabel.textColor = Glass.textPrimary
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.accessibilityIdentifier = "voice:text"
        addSubview(textLabel)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = Glass.imBlue
        doneButton.layer.cornerCurve = .continuous
        doneButton.accessibilityIdentifier = "voice:done"
        doneButton.addAction(UIAction { [weak self] _ in self?.actionTapped() }, for: .touchUpInside)
        addSubview(doneButton)

        againButton.setImage(UIImage(systemName: "mic"), for: .normal)
        againButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .medium), forImageIn: .normal)
        againButton.tintColor = Glass.textPrimary
        againButton.accessibilityIdentifier = "voice:again"
        againButton.accessibilityLabel = "Voice"
        againButton.addAction(UIAction { [weak self] _ in self?.onAgain?() }, for: .touchUpInside)
        addSubview(againButton)

        show(.opening)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ mode: Mode) {
        self.mode = mode
        switch mode {
        case .opening:
            textLabel.text = "Opening Glyf…"
            textLabel.textColor = Glass.textSecondary
            doneButton.isEnabled = false
        case .listening(let words):
            textLabel.text = words.isEmpty ? "Listening…" : words
            textLabel.textColor = words.isEmpty ? Glass.textSecondary : Glass.textPrimary
            doneButton.isEnabled = true
        case .finishing(let words):
            textLabel.text = words.isEmpty ? "…" : words
            textLabel.textColor = Glass.textSecondary
            doneButton.isEnabled = false
        case .typed(let words), .polished(let words):
            textLabel.text = words
            textLabel.textColor = Glass.textSecondary
            doneButton.isEnabled = true
        case .polishing(let words):
            textLabel.text = words
            textLabel.textColor = Glass.textSecondary
            doneButton.isEnabled = false
        }
        let title: String
        switch mode {
        case .typed: title = "Polish"
        case .polishing: title = "Polishing…"
        case .polished: title = "Undo"
        default: title = "Done"
        }
        doneButton.setTitle(title, for: .normal)
        doneButton.accessibilityIdentifier = title == "Done" ? "voice:done" : "voice:\(title.lowercased().prefix(6))"
        doneButton.alpha = doneButton.isEnabled ? 1 : 0.4
        let hearing: Bool = {
            switch mode { case .listening, .finishing: return true; default: return false }
        }()
        pulse(hearing)
        againButton.isHidden = !isAfterwords
        setNeedsLayout()
    }

    /// The words are in the field; the strip only offers what comes next.
    var isAfterwords: Bool {
        switch mode { case .typed, .polishing, .polished: return true; default: return false }
    }

    private func actionTapped() {
        switch mode {
        case .typed: onPolish?()
        case .polished: onUndo?()
        default: onDone?()
        }
    }

    private func pulse(_ on: Bool) {
        dot.isHidden = !on
        if on, dot.layer.animation(forKey: "pulse") == nil {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1
            a.toValue = 0.25
            a.duration = 0.7
            a.autoreverses = true
            a.repeatCount = .infinity
            dot.layer.add(a, forKey: "pulse")
        } else if !on {
            dot.layer.removeAnimation(forKey: "pulse")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let band = Glass.stripBand
        let h = bounds.height - band
        let mid = band + h / 2 - Glass.stripLift
        let row = Glass.stripBox(height: h, mid: mid)
        closeButton.frame = CGRect(x: 4, y: row.y, width: 40, height: row.height)
        dot.frame = CGRect(x: closeButton.frame.maxX + 2, y: mid - 4, width: 8, height: 8)
        let doneW: CGFloat = isAfterwords ? 96 : 72, doneH: CGFloat = min(30, h - 10)
        doneButton.frame = CGRect(x: bounds.width - 10 - doneW, y: mid - doneH / 2,
                                  width: doneW, height: doneH)
        doneButton.layer.cornerRadius = doneH / 2
        againButton.frame = CGRect(x: doneButton.frame.minX - 44, y: row.y, width: 40, height: row.height)
        let textEnd = againButton.isHidden ? doneButton.frame.minX : againButton.frame.minX
        let textX = dot.isHidden ? closeButton.frame.maxX + 2 : dot.frame.maxX + 10
        textLabel.frame = CGRect(x: textX, y: row.y,
                                 width: max(20, textEnd - textX - 8), height: row.height)
    }
}
