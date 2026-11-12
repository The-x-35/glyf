import UIKit

/// Transient confirmation pill inside the keyboard frame (fades ~1.6s).
enum KeyboardToast {
    static func show(in container: UIView, text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
        label.layer.cornerRadius = 14
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.accessibilityIdentifier = "kb:toast"
        // Never cut with "…" (D108): the words shrink from 13 pt to 11 pt to
        // stay on one line, and wrap to a second line past that.
        let room = max(0, container.bounds.width - 24)
        let fit = fitted(text, width: room - 24)
        label.font = fit.font
        label.numberOfLines = fit.lines
        label.lineBreakMode = .byWordWrapping
        let textW = ceil((text as NSString).size(withAttributes: [.font: fit.font]).width)
        let width = min(textW + 24, room)
        let height: CGFloat = fit.lines == 1 ? 28 : 44
        label.frame = CGRect(x: (container.bounds.width - width) / 2, y: 8,
                             width: width, height: height)
        label.layer.cornerRadius = fit.lines == 1 ? 14 : 12
        label.alpha = 0
        container.addSubview(label)
        // The fade-out starts only once the fade-in is done: queued together,
        // the label's alpha is already 0 to VoiceOver while it is on screen.
        UIView.animate(withDuration: 0.15) { label.alpha = 1 }
        // Held by a timer, not an animation delay, so it is really on screen
        // (to VoiceOver too) the whole time it shows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            UIView.animate(withDuration: 0.3) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// The largest size from 13 pt to 11 pt (half points) that keeps `text`
    /// on one line in `width`; else 12 pt on two lines.
    static func fitted(_ text: String, width: CGFloat) -> (font: UIFont, lines: Int) {
        var size: CGFloat = 13
        while size >= 11 {
            let f = UIFont.systemFont(ofSize: size, weight: .semibold)
            if ceil((text as NSString).size(withAttributes: [.font: f]).width) <= width { return (f, 1) }
            size -= 0.5
        }
        return (.systemFont(ofSize: 12, weight: .semibold), 2)
    }
}
