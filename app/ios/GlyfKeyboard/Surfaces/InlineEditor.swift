import UIKit

/// A keyboard cannot summon a keyboard: text fields inside the extension
/// can't use the system input path. This is a label-backed mini editor —
/// when active, the key grid routes characters here instead of the host app.
/// Used by the Glyf Bar prompt and the emoji search row.
final class InlineEditor: UIView {

    private let label = UILabel()
    private let caret = UIView()
    private let placeholderText: String
    var onChange: ((String) -> Void)?

    private(set) var text: String = "" {
        didSet { render(); onChange?(text) }
    }

    var isActive = false {
        didSet { updateActive() }
    }

    init(placeholder: String) {
        placeholderText = placeholder
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceCard
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Glass.strokeHairline.cgColor

        label.font = .systemFont(ofSize: 15)
        addSubview(label)
        caret.backgroundColor = Glass.accentPrimary
        caret.layer.cornerRadius = 1
        caret.isHidden = true
        addSubview(caret)
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    func append(_ s: String) { text += s }
    /// Replaces the whole query — used when a suggestion row is tapped.
    func setText(_ s: String) { text = s }

    func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }

    func clear() { text = "" }

    private func render() {
        if text.isEmpty {
            label.text = placeholderText
            label.textColor = Glass.textSecondary
        } else {
            label.text = text
            label.textColor = Glass.textPrimary
        }
        setNeedsLayout()
    }

    private func updateActive() {
        layer.borderColor = isActive
            ? Glass.strokeFocus.cgColor : Glass.strokeHairline.cgColor
        caret.isHidden = !isActive
        if isActive {
            caret.alpha = 1
            UIView.animate(withDuration: 0.55, delay: 0,
                           options: [.repeat, .autoreverse, .curveEaseInOut]) {
                self.caret.alpha = 0.15
            }
        } else {
            caret.layer.removeAllAnimations()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 12, dy: 4)
        let w = min(label.intrinsicContentSize.width, bounds.width - 26)
        let x = text.isEmpty ? 12 : 12 + w + 2
        caret.frame = CGRect(x: x, y: 7, width: 2, height: bounds.height - 14)
    }
}
