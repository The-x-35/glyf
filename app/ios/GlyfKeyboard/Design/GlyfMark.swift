import UIKit

/// The Glyf mark, exactly as the app icon draws it: the icon's "g" (Inter
/// SemiBold at text size; laid over the 1024pt icon it covers 99.3% of the
/// letter) and the violet dot above its right shoulder. It is drawn from the
/// letter's outline, so the keyboard ships neither the font nor an image and
/// the mark is sharp at any size.
enum GlyfMark {

    /// The letter's ink is this wide for each point of its height.
    static let gAspect: CGFloat = 0.6699
    /// Where the icon puts the dot, in heights of the letter: its centre
    /// 1.0379 right of the letter's left edge and 0.4927 above its top, and
    /// 0.3276 across. From dot top to letter foot the mark is 1.6565 tall.
    static let dotX: CGFloat = 1.0379
    static let dotY: CGFloat = 0.4927
    static let dotSize: CGFloat = 0.3276
    static let markHeight: CGFloat = 1.6565
    /// The icon's ink.
    static let ink = UIColor(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 1)

    /// The g's ink box filling `rect`'s height, from its left edge.
    static func gPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let s = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        func m(_ x: CGFloat, _ y: CGFloat) { path.move(to: p(x, y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: p(x, y)) }
        func q(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) { path.addQuadCurve(to: p(x, y), control: p(cx, cy)) }
        func z() { path.closeSubpath() }
        // Inter 4, wght 600, opsz 14: the outline, normalised to its ink box.
        m(0.3374, 1.0000)
        q(0.2520, 1.0000, 0.1889, 0.9784)
        q(0.1258, 0.9568, 0.0855, 0.9195)
        q(0.0452, 0.8822, 0.0273, 0.8355)
        l(0.1674, 0.7854)
        q(0.1786, 0.8052, 0.1985, 0.8260)
        q(0.2184, 0.8468, 0.2519, 0.8606)
        q(0.2855, 0.8744, 0.3370, 0.8744)
        q(0.4139, 0.8744, 0.4600, 0.8386)
        q(0.5062, 0.8027, 0.5062, 0.7265)
        l(0.5062, 0.5919)
        l(0.4926, 0.5919)
        q(0.4801, 0.6177, 0.4567, 0.6448)
        q(0.4333, 0.6718, 0.3936, 0.6902)
        q(0.3539, 0.7087, 0.2926, 0.7087)
        q(0.2109, 0.7087, 0.1445, 0.6702)
        q(0.0781, 0.6316, 0.0390, 0.5546)
        q(0.0000, 0.4775, 0.0000, 0.3622)
        q(0.0000, 0.2455, 0.0393, 0.1647)
        q(0.0787, 0.0839, 0.1452, 0.0420)
        q(0.2118, 0.0000, 0.2937, 0.0000)
        q(0.3566, 0.0000, 0.3973, 0.0210)
        q(0.4379, 0.0419, 0.4621, 0.0716)
        q(0.4863, 0.1013, 0.4990, 0.1265)
        l(0.5078, 0.1265)
        l(0.5078, 0.0089)
        l(0.6699, 0.0089)
        l(0.6699, 0.7214)
        q(0.6699, 0.8158, 0.6267, 0.8777)
        q(0.5835, 0.9396, 0.5083, 0.9698)
        q(0.4332, 1.0000, 0.3374, 1.0000)
        z()
        m(0.3386, 0.5782)
        q(0.3929, 0.5782, 0.4304, 0.5523)
        q(0.4679, 0.5264, 0.4874, 0.4776)
        q(0.5070, 0.4287, 0.5070, 0.3606)
        q(0.5070, 0.2932, 0.4876, 0.2428)
        q(0.4683, 0.1924, 0.4308, 0.1642)
        q(0.3933, 0.1359, 0.3386, 0.1359)
        q(0.2829, 0.1359, 0.2451, 0.1654)
        q(0.2073, 0.1949, 0.1882, 0.2455)
        q(0.1691, 0.2961, 0.1691, 0.3606)
        q(0.1691, 0.4261, 0.1884, 0.4752)
        q(0.2078, 0.5242, 0.2455, 0.5512)
        q(0.2833, 0.5782, 0.3386, 0.5782)
        z()
        return path
    }

    /// The letter and dot of the icon's mark with the letter at \`letter\`.
    static func dot(for letter: CGRect) -> CGRect {
        let d = letter.height * dotSize
        return CGRect(x: letter.minX + letter.height * dotX - d / 2,
                      y: letter.minY - letter.height * dotY - d / 2, width: d, height: d)
    }

    /// The icon's mark fitted into \`box\`: the letter centred across it, the
    /// whole mark (dot top to letter foot) centred down it, as on the icon.
    static func letter(centredIn box: CGRect, margin: CGFloat) -> CGRect {
        let h = (box.height - margin * 2) / markHeight
        let top = box.midY - h * markHeight / 2
        return CGRect(x: box.midX - h * gAspect / 2, y: top + h * (markHeight - 1), width: h * gAspect, height: h)
    }

    /// The strip's key: the pill, holding the app icon's mark.
    struct Keycap {
        let key: CGRect
        let letter: CGRect
        let dot: CGRect
        let radius: CGFloat

        /// A key \`height\` tall whose left edge is at \`x\`, centred on \`midY\`.
        init(height h: CGFloat, x: CGFloat, midY: CGFloat) {
            key = CGRect(x: x, y: midY - h / 2, width: GlyfMark.keycapWidth(height: h), height: h)
            radius = h / 3
            letter = GlyfMark.letter(centredIn: key, margin: h * 0.083)
            dot = GlyfMark.dot(for: letter)
        }
    }

    /// The key's width for a height (41 by 30 on the strip).
    static func keycapWidth(height: CGFloat) -> CGFloat { (height * 1.367).rounded() }

    /// The logo follows the theme: the app icon on a light sheet (white, with
    /// its black g), its dark twin on a dark sheet (black, with a white g).
    static func face(dark: Bool) -> UIColor { dark ? ink : .white }
    static func letterColor(dark: Bool) -> UIColor { dark ? .white : ink }
    /// A faint edge so the dark key stands off a dark strip.
    static func ring(dark: Bool) -> UIColor? { dark ? UIColor.white.withAlphaComponent(0.16) : nil }
}
