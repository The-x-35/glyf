import UIKit

/// The Glyf key's letter: Inter Bold's "g", the letter tryglyf.com's keyboard
/// draws on its g key (the app icon's is the SemiBold cut of the same
/// design). It is drawn from its outline, so the keyboard ships neither the
/// font nor an image and the key is sharp at any size.
enum GlyfMark {

    /// The letter's ink is this wide for each point of its height.
    static let gAspect: CGFloat = 0.6891
    /// The ink's height, and its bowl (the part above the baseline), per
    /// point of type size: the site sizes the letter as type and centres the
    /// bowl, the tail hanging below it.
    static let inkPerEm: CGFloat = 0.7686
    static let bowlPerEm: CGFloat = 0.5527

    /// The g's ink box filling `rect`'s height, from its left edge.
    static func gPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let s = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        func m(_ x: CGFloat, _ y: CGFloat) { path.move(to: p(x, y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: p(x, y)) }
        func q(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) { path.addQuadCurve(to: p(x, y), control: p(cx, cy)) }
        func z() { path.closeSubpath() }
        // Inter 4, wght 700, opsz 14: the outline, normalised to its ink box.
        m(0.3451, 1.0000)
        q(0.2564, 1.0000, 0.1905, 0.9776)
        q(0.1246, 0.9552, 0.0832, 0.9158)
        q(0.0418, 0.8764, 0.0261, 0.8256)
        l(0.1899, 0.7803)
        q(0.1989, 0.8000, 0.2175, 0.8187)
        q(0.2361, 0.8375, 0.2672, 0.8495)
        q(0.2983, 0.8615, 0.3444, 0.8615)
        q(0.4172, 0.8615, 0.4589, 0.8280)
        q(0.5007, 0.7946, 0.5007, 0.7241)
        l(0.5007, 0.5934)
        l(0.4858, 0.5934)
        q(0.4730, 0.6220, 0.4489, 0.6486)
        q(0.4247, 0.6751, 0.3856, 0.6921)
        q(0.3465, 0.7091, 0.2889, 0.7091)
        q(0.2089, 0.7091, 0.1433, 0.6715)
        q(0.0777, 0.6339, 0.0389, 0.5571)
        q(0.0000, 0.4803, 0.0000, 0.3629)
        q(0.0000, 0.2427, 0.0396, 0.1621)
        q(0.0792, 0.0814, 0.1449, 0.0407)
        q(0.2107, 0.0000, 0.2894, 0.0000)
        q(0.3494, 0.0000, 0.3899, 0.0202)
        q(0.4303, 0.0403, 0.4555, 0.0702)
        q(0.4806, 0.1001, 0.4937, 0.1284)
        l(0.5015, 0.1284)
        l(0.5015, 0.0089)
        l(0.6891, 0.0089)
        l(0.6891, 0.7133)
        q(0.6891, 0.8092, 0.6449, 0.8730)
        q(0.6007, 0.9368, 0.5231, 0.9684)
        q(0.4456, 1.0000, 0.3451, 1.0000)
        z()
        m(0.3484, 0.5642)
        q(0.3975, 0.5642, 0.4315, 0.5402)
        q(0.4655, 0.5161, 0.4834, 0.4707)
        q(0.5013, 0.4252, 0.5013, 0.3618)
        q(0.5013, 0.2985, 0.4835, 0.2516)
        q(0.4658, 0.2048, 0.4318, 0.1787)
        q(0.3977, 0.1527, 0.3484, 0.1527)
        q(0.2986, 0.1527, 0.2645, 0.1796)
        q(0.2303, 0.2065, 0.2129, 0.2535)
        q(0.1955, 0.3005, 0.1955, 0.3618)
        q(0.1955, 0.4235, 0.2131, 0.4691)
        q(0.2306, 0.5147, 0.2647, 0.5395)
        q(0.2989, 0.5642, 0.3484, 0.5642)
        z()
        return path
    }

    /// The strip's key, as tryglyf.com draws it (globals.css .kb-g) and a
    /// little taller: a black pill, the white g centred on its bowl, and the
    /// violet dot 18% down and 20% in from the right, at the letter's
    /// shoulder the way the logo carries it. Proportions are of the key's
    /// height, so it stays one drawing at every size.
    struct Keycap {
        let key: CGRect
        let letter: CGRect
        let dot: CGRect
        let radius: CGFloat

        /// A key \`height\` tall whose left edge is at \`x\`, centred on \`midY\`.
        init(height h: CGFloat, x: CGFloat, midY: CGFloat) {
            let w = GlyfMark.keycapWidth(height: h)
            key = CGRect(x: x, y: midY - h / 2, width: w, height: h)
            radius = h / 3
            let size = h * 0.617
            let ink = size * GlyfMark.inkPerEm, bowl = size * GlyfMark.bowlPerEm
            letter = CGRect(x: key.midX - ink * GlyfMark.gAspect / 2, y: key.midY - bowl / 2,
                            width: ink * GlyfMark.gAspect, height: ink)
            let d = h * 0.2
            dot = CGRect(x: key.maxX - w * 0.2 - d, y: key.minY + h * 0.18, width: d, height: d)
        }
    }

    /// The key's width for a height (41 by 30 on the strip).
    static func keycapWidth(height: CGFloat) -> CGFloat { (height * 1.367).rounded() }

    /// The key's face: the site's near-black on a light sheet, black with a
    /// faint ring on a dark one.
    static func face(dark: Bool) -> UIColor {
        dark ? .black : UIColor(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
    }
}
