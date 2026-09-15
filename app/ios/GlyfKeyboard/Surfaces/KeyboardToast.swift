import UIKit

/// Transient confirmation pill inside the keyboard frame (fades ~1.6s).
enum KeyboardToast {
    static func show(in container: UIView, text: String) {
        let label = UILabel()
        label.text = "  \(text)  "
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
        label.layer.cornerRadius = 14
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.accessibilityIdentifier = "kb:toast"
        let width = min(label.intrinsicContentSize.width + 12, container.bounds.width - 24)
        label.frame = CGRect(x: (container.bounds.width - width) / 2, y: 8,
                             width: width, height: 28)
        label.alpha = 0
        container.addSubview(label)
        UIView.animate(withDuration: 0.15) { label.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 1.6, options: []) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
}
