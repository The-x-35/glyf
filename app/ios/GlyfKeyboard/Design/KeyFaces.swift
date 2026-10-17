import UIKit

/// A theme's finish drawn onto key caps (shared/themes/styles.py). The
/// reference is the canvas code in tools/theme_mock.py (drawFace and
/// ornaments): every value here is that code's, in points.
///
/// A face is drawn once per (theme, mode, class, ornament target, fill,
/// size) into a UIImage that KeyView sets as a layer's contents; nothing is
/// redrawn per frame and keys of one size share one image. Textures load
/// lazily for the active theme only and go with it (§4.1's 45 MB budget).
enum KeyFaces {

    enum FaceClass: String { case letter, function, space, ret }

    struct Request {
        let size: CGSize
        let scale: CGFloat
        let faceClass: FaceClass
        /// The ornaments' key name; nil draws none.
        let target: ThemeOrnamentTarget?
        /// The key's fill: its rest or pressed colour.
        let fill: UInt32
        /// A pressed key: its fill is already the pressed one; a two-colour
        /// face darkens by 12% black too (its second colour has no pressed
        /// shade).
        let pressed: Bool
        /// Only single-character letter keys may be round.
        let allowRound: Bool
    }

    /// Where the texture tiles are; nil reads the keyboard's bundle. Tests
    /// point it at the source folder.
    static var textureDirectory: URL?

    private static var images: [String: UIImage] = [:]
    private static var patterns: [String: UIColor] = [:]
    private static var overlays: [String: UIImage] = [:]
    private static var owner: String?

    static func face(_ cls: FaceClass, in style: ThemeStyle) -> ThemeFace {
        switch cls {
        case .letter: return style.faces.letter
        case .function: return style.faces.function
        case .space: return style.faces.space
        case .ret: return style.faces.ret
        }
    }

    /// Round keycaps need a cell at least as tall as it is wide (a letter);
    /// anything wider keeps the key's own shape.
    static func isRound(_ face: ThemeFace, size: CGSize, allowed: Bool) -> Bool {
        face.round && allowed && size.width <= size.height
    }

    /// Lets the cached faces and the texture tiles go (a theme change).
    static func release() {
        images = [:]
        patterns = [:]
        overlays = [:]
        owner = nil
    }

    private static func own(_ theme: KeyboardTheme, dark: Bool) {
        let id = theme.id + (dark ? "/dark" : "/light")
        if owner == id { return }
        if owner?.hasPrefix(theme.id + "/") != true { patterns = [:] }
        images = [:]
        overlays = [:]
        owner = id
    }

    static func image(theme: KeyboardTheme, dark: Bool, request r: Request) -> UIImage? {
        guard r.size.width >= 1, r.size.height >= 1 else { return nil }
        own(theme, dark: dark)
        let key = String(format: "%@|%@|%06X|%d|%d|%.2fx%.2f@%.0f", r.faceClass.rawValue, r.target?.rawValue ?? "-",
                         r.fill, r.pressed ? 1 : 0, r.allowRound ? 1 : 0, r.size.width, r.size.height, r.scale)
        if let hit = images[key] { return hit }
        let v = theme.variant(dark: dark)
        let img = render(v, dark: dark, request: r)
        // A board's worth of classes and sizes is about twenty; anything
        // past that is a rotation or a layout change, so start over.
        if images.count > 48 { images = [:] }
        images[key] = img
        return img
    }

    // MARK: Drawing

    static func render(_ v: ThemeVariant, dark: Bool, request r: Request) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = r.scale
        fmt.opaque = false
        let f = face(r.faceClass, in: v.style)
        return UIGraphicsImageRenderer(size: r.size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(origin: .zero, size: r.size)
            if isRound(f, size: r.size, allowed: r.allowRound) {
                drawRound(c, rect, fill: r.fill, face: f, dark: dark, scale: r.scale)
            } else {
                drawKey(c, rect, fill: r.fill, face: f, scale: r.scale)
                if r.pressed, f.fill2 != nil {
                    c.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: Glass.radiusKey).addClip()
                    c.setFillColor(UIColor(white: 0, alpha: 0.12).cgColor)
                    c.fill(rect)
                    c.restoreGState()
                }
            }
            if let target = r.target {
                drawOrnaments(c, rect, v: v, target: target, cls: r.faceClass, fill: r.fill)
            }
        }
    }

    private static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func gradient(_ colors: [UIColor], _ locations: [CGFloat]) -> CGGradient? {
        CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: locations)
    }

    private static func white(_ a: Double) -> UIColor { UIColor(white: 1, alpha: CGFloat(a)) }
    private static func black(_ a: Double) -> UIColor { UIColor(white: 0, alpha: CGFloat(a)) }

    /// drawFace's key shape: fill (or fill -> fill2 on the diagonal), the
    /// texture, the sheen, the metal bands, the gloss and the top pixel.
    private static func drawKey(_ c: CGContext, _ rect: CGRect, fill: UInt32, face f: ThemeFace, scale: CGFloat) {
        let w = rect.width, h = rect.height
        c.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: Glass.radiusKey).addClip()
        if let f2 = f.fill2, let g = gradient([UIColor(rgb: fill), UIColor(rgb: f2)], [0, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            c.setFillColor(UIColor(rgb: fill).cgColor)
            c.fill(rect)
        }
        drawTexture(c, rect, face: f, scale: scale)
        if f.sheenTop > 0 || f.sheenBottom > 0,
           let g = gradient([white(f.sheenTop), white(0), black(0), black(f.sheenBottom)], [0, 0.5, 0.5, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }
        if f.metal > 0 {
            for (p, s) in [(0.22, 0.10), (0.58, 0.16), (0.84, 0.08)] {
                let y0 = h * CGFloat(p - s), y1 = h * CGFloat(p + s)
                guard let g = gradient([white(0), white(f.metal), white(0)], [0, 0.5, 1]) else { continue }
                c.saveGState()
                c.clip(to: CGRect(x: 0, y: y0, width: w, height: y1 - y0))
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
                c.restoreGState()
            }
        }
        if f.gloss > 0, let g = gradient([white(f.gloss), white(0)], [0, 1]) {
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: 0, width: w, height: h * 0.48))
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h * 0.48), options: [])
            c.restoreGState()
        }
        if f.highlight > 0 {
            c.setFillColor(white(f.highlight).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: w, height: 1 / scale))
        }
        c.restoreGState()
    }

    /// drawFace's round keycap: its drop shadow, the chrome bezel, then the
    /// face with its texture and a domed light, inside the key's own cell.
    private static func drawRound(_ c: CGContext, _ rect: CGRect, fill: UInt32, face f: ThemeFace, dark: Bool,
                                  scale: CGFloat) {
        let R = rect.width / 2, cx = rect.midX, cy = rect.midY
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
            CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
        }
        c.setFillColor(black(dark ? 0.6 : 0.30).cgColor)
        c.fillEllipse(in: circle(cx, cy + 1.4, R))

        c.saveGState()
        c.addEllipse(in: circle(cx, cy, R))
        c.clip()
        let ring = UIColor(rgb: f.ring ?? 0xA9A9A4)
        if let g = gradient([UIColor(rgb: 0xF4F4F2), ring, UIColor(rgb: 0x6E6E6A), UIColor(rgb: 0xD8D8D4)],
                            [0, 0.45, 0.55, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: cy - R), end: CGPoint(x: 0, y: cy + R), options: [])
        }
        c.restoreGState()

        let ri = R - 2.4
        guard ri > 0 else { return }
        c.saveGState()
        c.addEllipse(in: circle(cx, cy, ri))
        c.clip()
        let box = circle(cx, cy, R)
        c.setFillColor(UIColor(rgb: fill).cgColor)
        c.fill(box)
        drawTexture(c, box, face: f, scale: scale)
        if let g = gradient([white(f.gloss), white(0), black(f.sheenBottom + 0.06)], [0, 0.7, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy - ri * 0.35), startRadius: ri * 0.1,
                                 endCenter: CGPoint(x: cx, y: cy), endRadius: ri,
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        c.restoreGState()
    }

    private static func drawTexture(_ c: CGContext, _ rect: CGRect, face f: ThemeFace, scale: CGFloat) {
        guard f.textureAlpha > 0, let name = f.texture, let p = pattern(name, scale: scale) else { return }
        c.saveGState()
        c.setAlpha(CGFloat(f.textureAlpha))
        p.setFill()
        c.fill(rect)
        c.restoreGState()
    }

    // MARK: Textures

    static func textureURL(_ name: String) -> URL? {
        if let textureDirectory { return textureDirectory.appendingPathComponent(name + ".png") }
        return Bundle(for: KeyFacesBundleToken.self).url(forResource: name, withExtension: "png")
    }

    /// A tile as a pattern colour, one image pixel to one screen pixel.
    static func pattern(_ name: String, scale: CGFloat) -> UIColor? {
        let key = "\(name)@\(scale)"
        if let p = patterns[key] { return p }
        guard let url = textureURL(name), let data = try? Data(contentsOf: url),
              let img = UIImage(data: data, scale: scale) else { return nil }
        let p = UIColor(patternImage: img)
        patterns[key] = p
        return p
    }

    /// A face's texture alone at its alpha, for surfaces drawn in other
    /// shapes (the press callout, the accent popup). nil without one.
    static func textureOverlay(theme: KeyboardTheme, dark: Bool, face f: ThemeFace, size: CGSize,
                               scale: CGFloat) -> UIImage? {
        guard f.textureAlpha > 0, let name = f.texture, size.width >= 1, size.height >= 1 else { return nil }
        own(theme, dark: dark)
        let key = String(format: "%@|%.1fx%.1f", name, size.width, size.height)
        if let hit = overlays[key] { return hit }
        guard pattern(name, scale: scale) != nil else { return nil }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            drawTexture(ctx.cgContext, CGRect(origin: .zero, size: size), face: f, scale: scale)
        }
        if overlays.count > 12 { overlays = [:] }
        overlays[key] = img
        return img
    }

    // MARK: Ornaments (theme_mock.py's ornaments())

    static func hits(_ o: ThemeOrnament, target: ThemeOrnamentTarget, cls: FaceClass) -> Bool {
        o.on == target || (o.on == .function && cls == .function && target != .ret)
    }

    static func color(_ role: ThemeColorRole, v: ThemeVariant, cls: FaceClass, fill: UInt32) -> UInt32 {
        switch role {
        case .ink: return cls == .function ? v.functionGlyph : v.keyText
        case .fnInk: return v.functionGlyph
        case .accent: return v.returnFill
        case .accentInk: return v.returnText
        case .fill: return fill
        case .hex(let h): return h
        }
    }

    private static func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        // The canvas's arcTo outline, corner for corner.
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x + r, y: y))
        p.addArc(tangent1End: CGPoint(x: x + w, y: y), tangent2End: CGPoint(x: x + w, y: y + h), radius: r)
        p.addArc(tangent1End: CGPoint(x: x + w, y: y + h), tangent2End: CGPoint(x: x, y: y + h), radius: r)
        p.addArc(tangent1End: CGPoint(x: x, y: y + h), tangent2End: CGPoint(x: x, y: y), radius: r)
        p.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x + w, y: y), radius: r)
        p.closeSubpath()
        return p
    }

    static func ornamentFont(_ font: ThemeOrnamentFont, size: CGFloat, weight: Int) -> UIFont {
        switch font {
        case .mono:
            return UIFont(name: weight >= 600 ? "Menlo-Bold" : "Menlo-Regular", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        case .theme:
            if let f = ThemeFonts.font(size: size) { return f }
            fallthrough
        case .system:
            let w: UIFont.Weight = weight >= 700 ? .bold : weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
            return .systemFont(ofSize: size, weight: w)
        }
    }

    private static func drawOrnaments(_ c: CGContext, _ rect: CGRect, v: ThemeVariant, target: ThemeOrnamentTarget,
                                      cls: FaceClass, fill: UInt32) {
        let h = rect.height
        for o in v.style.ornaments where hits(o, target: target, cls: cls) {
            let ax: CGFloat
            switch o.anchor {
            case .left: ax = 0
            case .center: ax = rect.width / 2
            case .right: ax = rect.width
            }
            func X(_ u: Double) -> CGFloat { ax + CGFloat(u) * h }
            func Y(_ u: Double) -> CGFloat { CGFloat(u) * h }
            c.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: Glass.radiusKey).addClip()
            c.setLineCap(.round)
            for op in o.ops {
                let col = UIColor(rgb: color(op.color ?? o.color, v: v, cls: cls, fill: fill)).cgColor
                // An op's own hex colour is a material (a seal, a plate):
                // it shows at 0.9 at least.
                var alpha = o.alpha
                if case .hex = op.color, o.alpha < 0.9 { alpha = max(o.alpha, 0.9) }
                c.setAlpha(CGFloat(alpha))
                c.setStrokeColor(col)
                c.setFillColor(col)
                switch op {
                case let .line(x0, y0, x1, y1, w, _):
                    c.setLineWidth(CGFloat(w) * h)
                    c.beginPath()
                    c.move(to: CGPoint(x: X(x0), y: Y(y0)))
                    c.addLine(to: CGPoint(x: X(x1), y: Y(y1)))
                    c.strokePath()
                case let .poly(p, _):
                    guard p.count >= 6 else { continue }
                    c.beginPath()
                    c.move(to: CGPoint(x: X(p[0]), y: Y(p[1])))
                    var i = 2
                    while i + 1 < p.count {
                        c.addLine(to: CGPoint(x: X(p[i]), y: Y(p[i + 1])))
                        i += 2
                    }
                    c.closePath()
                    c.fillPath()
                case let .circle(cx, cy, r, w, _):
                    let rr = CGFloat(r) * h
                    let box = CGRect(x: X(cx) - rr, y: Y(cy) - rr, width: 2 * rr, height: 2 * rr)
                    if let w {
                        c.setLineWidth(CGFloat(w) * h)
                        c.strokeEllipse(in: box)
                    } else {
                        c.fillEllipse(in: box)
                    }
                case let .rect(x, y, rw, rh, radius, w, _):
                    let path = roundedRect(X(x), Y(y), CGFloat(rw) * h, CGFloat(rh) * h, max(0.01, CGFloat(radius) * h))
                    c.beginPath()
                    c.addPath(path)
                    if let w {
                        c.setLineWidth(CGFloat(w) * h)
                        c.strokePath()
                    } else {
                        c.fillPath()
                    }
                case let .text(s, x, y, size, font, weight, _, _):
                    // The canvas's centre alignment and middle baseline;
                    // its letter spacing is left at 0, so is ours.
                    let f = ornamentFont(font, size: CGFloat(size) * h, weight: weight)
                    let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: UIColor(cgColor: col)])
                    let width = str.size().width
                    let baseline = Y(y) + (f.ascender + f.descender) / 2
                    UIGraphicsPushContext(c)
                    str.draw(at: CGPoint(x: X(x) - width / 2, y: baseline - f.ascender))
                    UIGraphicsPopContext()
                }
            }
            c.restoreGState()
        }
    }

    // MARK: Legends

    /// WCAG relative luminance: the canvas's test for a light key.
    static func luminance(_ rgb: UInt32) -> Double {
        let f = { (v: Double) in v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }
}

private final class KeyFacesBundleToken {}

/// A view whose layer is a gradient (the foil legend).
final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
}
