import UIKit

/// A keyboard cannot summon a keyboard: text fields inside the extension
/// can't use the system input path. This is a label-backed mini editor —
/// when active, the key grid routes characters here instead of the host app.
/// Used by the Glyf Bar prompt and the emoji search row.
final class InlineEditor: UIView {

    private let label = UILabel()
    private let caret = UIView()
    private let icon = UIImageView()
    /// Grey text shown while empty (the emoji board changes it per mode).
    var placeholder: String {
        didSet { render() }
    }
    private let searchStyle: Bool
    var onChange: ((String) -> Void)?

    private(set) var text: String = "" {
        didSet { render(); onChange?(text) }
    }

    var isActive = false {
        didSet { updateActive() }
    }

    /// Room kept clear on the right, for a button laid over the pill's end.
    var trailingInset: CGFloat = 12 {
        didSet { setNeedsLayout() }
    }

    /// Long text keeps its end in view (where the typing is) instead of its start.
    var showsEnd = false {
        didSet { label.lineBreakMode = showsEnd ? .byTruncatingHead : .byTruncatingTail }
    }

    /// `searchStyle` draws Apple's search pill: a magnifier, no outline.
    /// `symbol` leads an outlined pill with an accent icon (Ask Glyf's sparkle).
    init(placeholder: String, searchStyle: Bool = false, symbol: String? = nil) {
        self.placeholder = placeholder
        self.searchStyle = searchStyle
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceCard
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Glass.strokeHairline.cgColor

        label.font = .systemFont(ofSize: 15)
        addSubview(label)
        if searchStyle {
            backgroundColor = Glass.isDark ? UIColor.white.withAlphaComponent(0.10)
                                           : UIColor.white.withAlphaComponent(0.65)
            layer.borderWidth = 0
            layer.cornerRadius = 17
            label.font = .systemFont(ofSize: 17)
            icon.image = UIImage(systemName: "magnifyingglass")
            icon.preferredSymbolConfiguration = .init(pointSize: 15, weight: .medium)
            icon.tintColor = Glass.textSecondary
            icon.contentMode = .center
            addSubview(icon)
        } else if let symbol {
            icon.image = UIImage(systemName: symbol)
            icon.preferredSymbolConfiguration = .init(pointSize: 14, weight: .semibold)
            icon.tintColor = Glass.accentPrimary
            icon.contentMode = .center
            addSubview(icon)
        }
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
            label.text = placeholder
            label.textColor = Glass.textSecondary
        } else {
            label.text = text
            label.textColor = Glass.textPrimary
        }
        setNeedsLayout()
    }

    private func updateActive() {
        if !searchStyle {
            layer.borderColor = isActive
                ? Glass.strokeFocus.cgColor : Glass.strokeHairline.cgColor
        }
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
        let lead: CGFloat = searchStyle || icon.image != nil ? 36 : 12
        icon.frame = CGRect(x: 10, y: 0, width: 22, height: bounds.height)
        label.frame = CGRect(x: lead, y: 4, width: max(0, bounds.width - lead - trailingInset),
                             height: bounds.height - 8)
        let w = min(label.intrinsicContentSize.width, bounds.width - lead - trailingInset - 2)
        let x = text.isEmpty ? lead : lead + w + 2
        caret.frame = CGRect(x: x, y: 7, width: 2, height: bounds.height - 14)
    }
}
