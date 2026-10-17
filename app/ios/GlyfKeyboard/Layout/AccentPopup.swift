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
        // Shift makes capitals of letters, never of ".com" and its domains.
        let caps = { (t: String) in shifted && t.count == 1 ? t.uppercased() : t }
        let baseShown = caps(base)
        options = [baseShown] + accents.map(caps)

        // Apple's accent bubble: a card on the sheet, or a theme's press
        // popup colour.
        backgroundColor = Self.fill
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
            l.font = Glass.keyFont(ofSize: 22)
            l.textAlignment = .center
            l.textColor = Self.ink
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
        applyTexture()
        for (i, l) in labels.enumerated() {
            l.frame = CGRect(x: 4 + CGFloat(i) * Self.optionWidth, y: 6,
                             width: Self.optionWidth, height: Self.height - 12)
        }
    }

    private var textureLayer: CALayer?

    /// A theme's letter texture over the popup's fill, at the face's alpha.
    private func applyTexture() {
        textureLayer?.removeFromSuperlayer()
        textureLayer = nil
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        guard let skin = Glass.skin, let v = Glass.skinVariant,
              let tex = KeyFaces.textureOverlay(theme: skin, dark: Glass.isDark, face: v.style.faces.letter,
                                                size: bounds.size, scale: scale) else { return }
        let t = CALayer()
        t.frame = bounds
        t.contents = tex.cgImage
        t.contentsScale = scale
        t.cornerRadius = layer.cornerRadius
        t.cornerCurve = .continuous
        t.masksToBounds = true
        layer.insertSublayer(t, at: 0)
        textureLayer = t
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
            l.backgroundColor = i == idx ? Self.pick : .clear
            l.textColor = i == idx ? Self.pickInk : Self.ink
        }
    }

    /// Today: the sheet's card, its text, the brand purple under the pick.
    /// A theme: its popup, its popup ink, and its return colour under the
    /// pick (each pair checked at 4.5:1 in docs/THEMES.md §7).
    private static var fill: UIColor {
        Glass.skin != nil ? Glass.fillKeySolid : Glass.surfaceCard
    }
    private static var ink: UIColor {
        Glass.skin != nil ? Glass.popupInk : Glass.textPrimary
    }
    private static var pick: UIColor {
        Glass.skin != nil ? Glass.returnBlue : Glass.accentPrimary
    }
    private static var pickInk: UIColor {
        Glass.skin != nil ? Glass.returnInk : .white
    }
}
