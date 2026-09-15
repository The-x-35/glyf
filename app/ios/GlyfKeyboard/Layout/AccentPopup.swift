import UIKit

/// Long-press accent picker, rendered INSIDE the keyboard frame (§6.1 —
/// extensions cannot draw outside bounds). Slide horizontally to select,
/// release to commit.
final class AccentPopup: UIView {

    private var options: [String] = []
    private var labels: [UILabel] = []
    private(set) var selectedIndex = 0

    var selected: String? {
        options.indices.contains(selectedIndex) ? options[selectedIndex] : nil
    }

    init(base: String, accents: [String], shifted: Bool) {
        super.init(frame: .zero)
        let baseShown = shifted ? base.uppercased() : base
        options = [baseShown] + accents.map { shifted ? $0.uppercased() : $0 }

        if Glass.reduceTransparency {
            backgroundColor = Glass.solidKey
        } else {
            backgroundColor = Glass.fillKeyPressed
        }
        layer.cornerRadius = Glass.radiusKey + 2
        layer.cornerCurve = .continuous
        layer.borderWidth = Glass.hairlineWidth
        layer.borderColor = Glass.strokeHairline.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowColor = UIColor.black.cgColor

        for (i, opt) in options.enumerated() {
            let l = UILabel()
            l.text = opt
            l.font = .systemFont(ofSize: 22)
            l.textAlignment = .center
            l.textColor = Glass.textPrimary
            l.layer.cornerRadius = 7
            l.layer.cornerCurve = .continuous
            l.layer.masksToBounds = true
            l.tag = i
            addSubview(l)
            labels.append(l)
        }
        highlight(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    static let optionWidth: CGFloat = 40
    static let height: CGFloat = 52

    /// Positions the popup above `keyFrame`, clamped into `container`.
    func place(over keyFrame: CGRect, in container: CGRect) {
        let width = CGFloat(options.count) * Self.optionWidth + 8
        var x = keyFrame.midX - width / 2
        x = max(container.minX + 4, min(x, container.maxX - width - 4))
        let y = max(container.minY + 2, keyFrame.minY - Self.height - 6)
        frame = CGRect(x: x, y: y, width: width, height: Self.height)
        for (i, l) in labels.enumerated() {
            l.frame = CGRect(x: 4 + CGFloat(i) * Self.optionWidth, y: 6,
                             width: Self.optionWidth, height: Self.height - 12)
        }
    }

    /// Update selection from a touch location in the popup's superview space.
    func track(pointInSuperview p: CGPoint) {
        let local = convert(p, from: superview)
        let idx = Int((local.x - 4) / Self.optionWidth)
        highlight(max(0, min(options.count - 1, idx)))
    }

    private func highlight(_ idx: Int) {
        selectedIndex = idx
        for (i, l) in labels.enumerated() {
            l.backgroundColor = i == idx ? Glass.accentPrimary : .clear
            l.textColor = i == idx ? .white : Glass.textPrimary
        }
    }
}
