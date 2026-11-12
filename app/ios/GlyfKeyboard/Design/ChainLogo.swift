import UIKit

/// Each chain's own mark, drawn from the vector files its team publishes,
/// so a chain reads at a glance on the trade panel, its pickers and the
/// sponsor panels; nothing is fetched at run time. Sources: Base's brand kit
/// (github.com/base-org/brand-kit, logo/TheSquare/Digital/Base_square_blue.svg),
/// Arbitrum's docs (github.com/OffchainLabs/arbitrum-docs, public/img/logo.svg),
/// the Solana Foundation's site (github.com/solana-foundation/solana-com,
/// solana-mark-gradient.svg), Uniswap's Unichain icon (github.com/Uniswap/interface,
/// packages/mycelium/src/assets/icons/unichain.svg), Ethereum's diamond as
/// ethereum.org publishes it, and OP Mainnet's red disc with OP.
enum ChainLogo {

    struct Layer {
        var d: String
        var fill: UInt32
        /// A left-to-right sweep of colours (Solana's), in place of `fill`.
        var gradient: [(Double, UInt32)]? = nil
        var gradientLine: (CGPoint, CGPoint)? = nil
        init(d: String, fill: UInt32, gradient: [(Double, UInt32)]? = nil, gradientLine: (CGPoint, CGPoint)? = nil) {
            self.d = d; self.fill = fill; self.gradient = gradient; self.gradientLine = gradientLine
        }
    }

    struct Mark {
        var viewBox: CGSize
        var layers: [Layer]
        /// Drawn on a white disc (the diamond is dark on dark sheets otherwise).
        var disc = false
        /// Drawn as a red disc with "OP" (Optimism's mark is lettering).
        var lettering: String? = nil
        var inset: CGFloat = 0
    }

    static let marks: [String: Mark] = [
        "base": Mark(viewBox: CGSize(width: 1280, height: 1280), layers: [
            .init(d: "M0,101.12c0-34.64,0-51.95,6.53-65.28,6.25-12.76,16.56-23.07,29.32-29.32C49.17,0,66.48,0,101.12,0h1077.76c34.63,0,51.96,0,65.28,6.53,12.75,6.25,23.06,16.56,29.32,29.32,6.52,13.32,6.52,30.64,6.52,65.28v1077.76c0,34.63,0,51.96-6.52,65.28-6.26,12.75-16.57,23.06-29.32,29.32-13.32,6.52-30.65,6.52-65.28,6.52H101.12c-34.64,0-51.95,0-65.28-6.52-12.76-6.26-23.07-16.57-29.32-29.32-6.53-13.32-6.53-30.65-6.53-65.28V101.12Z", fill: 0x0000FF),
        ]),
        "arbitrum": Mark(viewBox: CGSize(width: 1080, height: 1218.5), layers: [
            .init(d: "M41,370.4v477.7c0,30.5,16.3,58.7,42.7,73.9l413.7,238.9c26.4,15.2,58.9,15.2,85.3,0L996.4,922 c26.4-15.2,42.7-43.4,42.7-73.9V370.4c0-30.5-16.3-58.7-42.7-73.9L582.7,57.6c-26.4-15.2-58.9-15.2-85.3,0L83.6,296.5 C57.2,311.7,41,339.9,41,370.4z", fill: 0x213147),
            .init(d: "M630.3,701.9l-59,161.8c-1.6,4.5-1.6,9.4,0,13.9L672.8,1156l117.4-67.8L649.3,701.9 C646.1,693,633.5,693,630.3,701.9z", fill: 0x12AAFF),
            .init(d: "M748.6,429.8c-3.2-8.9-15.8-8.9-19,0l-59,161.8c-1.6,4.5-1.6,9.4,0,13.9l166.3,455.8l117.4-67.8 L748.6,429.8z", fill: 0x12AAFF),
            .init(d: "M540,75.5c2.9,0,5.8,0.8,8.4,2.2l447.7,258.5c5.2,3,8.4,8.6,8.4,14.5v516.9c0,6-3.2,11.5-8.4,14.5 l-447.7,258.5c-2.5,1.5-5.5,2.2-8.4,2.2c-2.9,0-5.8-0.8-8.4-2.2L83.9,882.3c-5.2-3-8.4-8.6-8.4-14.5V350.8c0-6,3.2-11.5,8.4-14.5 L531.6,77.8C534.2,76.3,537.1,75.5,540,75.5 M540,0c-15.9,0-31.9,4.1-46.2,12.4L46.2,270.8c-28.6,16.5-46.2,47-46.2,80v516.9 c0,33,17.6,63.5,46.2,80l447.7,258.5c14.3,8.2,30.2,12.4,46.2,12.4c15.9,0,31.9-4.1,46.2-12.4l447.7-258.5 c28.6-16.5,46.2-47,46.2-80V350.8c0-33-17.6-63.5-46.2-80L586.2,12.4C571.9,4.1,555.9,0,540,0L540,0z", fill: 0x9DCCED),
            .init(d: "M243.9,1061.9 L285.1,949.1 L368,1018 L290.5,1088.8 Z", fill: 0x213147),
            .init(d: "M502.3,313.8H388.8c-8.5,0-16.1,5.3-19,13.3l-243.3,667l117.4,67.8l267.9-734.5 C514.3,320.8,509.4,313.8,502.3,313.8z", fill: 0xFFFFFF),
            .init(d: "M700.9,313.8H587.4c-8.5,0-16.1,5.3-19,13.3l-277.8,761.6l117.4,67.8l302.4-829.1 C712.8,320.8,707.9,313.8,700.9,313.8z", fill: 0xFFFFFF),
        ]),
        "solana": Mark(viewBox: CGSize(width: 120, height: 99), layers: [
            .init(d: "M119.37 78.0655L99.5477 97.658C98.6753 98.508 97.4637 99 96.2036 99H2.27787C1.01777 99 0 98.0159 0 96.8529C0 96.3161 0.242326 95.824 0.630048 95.4215L20.4039 75.8289C21.2763 74.979 22.4879 74.487 23.748 74.487H117.674C118.934 74.487 120 75.3816 120 76.5447C120 77.0814 119.806 77.6182 119.37 78.0208M99.5477 38.5226C98.6753 37.6727 97.4637 37.1807 96.2036 37.1807H2.27787C1.01777 37.2254 0 38.1648 0 39.3278C0 39.8646 0.242326 40.3566 0.630048 40.7592L20.4039 60.3965C21.2763 61.2464 22.4879 61.7384 23.748 61.7384H117.674C118.934 61.7384 119.952 60.7543 119.952 59.5913C119.952 59.0545 119.709 58.5625 119.321 58.1599L99.5477 38.5226ZM2.27787 24.4769H96.1551C97.4152 24.4769 98.6268 23.9848 99.4992 23.1349L119.37 3.54238C120.242 2.69248 120.194 1.35052 119.273 0.545352C119.176 0.455888 119.079 0.366425 118.934 0.321693C118.546 0.0980342 118.11 -0.0361611 117.674 0.00857069H23.748C22.4879 0.00857069 21.2763 0.50062 20.4039 1.35052L0.630048 20.943C-0.242326 21.7929 -0.193861 23.1349 0.775444 23.9401C1.21163 24.2979 1.74475 24.5216 2.32633 24.5216", fill: 0x9945FF,
                  gradient: [(0.08, 0x9945FF), (0.3, 0x8752F3), (0.5, 0x5497D5), (0.6, 0x43B4CA), (0.72, 0x28E0B9), (0.97, 0x19FB9B)],
                  gradientLine: (CGPoint(x: 10.1292, y: 101.371), CGPoint(x: 99.8282, y: -8.25607))),
        ], inset: 0.08),
        "unichain": Mark(viewBox: CGSize(width: 25, height: 25), layers: [
            .init(d: "M24.7441 11.9143C18.2397 11.9143 12.9725 6.6417 12.9725 0.142578H12.5159V11.9143H0.744141V12.3709C7.24858 12.3709 12.5159 17.6435 12.5159 24.1426H12.9725V12.3709H24.7441V11.9143Z", fill: 0xF50DB4),
        ]),
        "ethereum": Mark(viewBox: CGSize(width: 256, height: 417), layers: [
            .init(d: "M127.961 0l-2.795 9.5v275.668l2.795 2.79 127.962-75.638z", fill: 0x343434),
            .init(d: "M127.962 0L0 212.32l127.962 75.639V154.158z", fill: 0x8C8C8C),
            .init(d: "M127.961 312.187l-1.575 1.92v98.199l1.575 4.6L256 236.587z", fill: 0x3C3C3B),
            .init(d: "M127.962 416.905v-104.72L0 236.585z", fill: 0x8C8C8C),
            .init(d: "M127.961 287.958l127.96-75.637-127.96-58.162z", fill: 0x141414),
            .init(d: "M0 212.32l127.96 75.638v-133.8z", fill: 0x393939),
        ], disc: true, inset: 0.2),
        "optimism": Mark(viewBox: CGSize(width: 1, height: 1), layers: [], lettering: "OP"),
    ]

    /// The mark for a chain key ("base", "op" is "optimism"), nil for one
    /// without a mark here.
    static func mark(_ chain: String) -> Mark? { marks[chain == "op" ? "optimism" : chain] }

    private static var cache: [String: UIImage] = [:]

    static func color(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// The mark at `side` points, crisp at the screen's scale.
    static func image(_ chain: String, side: CGFloat) -> UIImage? {
        let key = "\(chain)|\(side)"
        if let hit = cache[key] { return hit }
        guard let mark = mark(chain) else { return nil }
        let size = CGSize(width: side, height: side)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            draw(mark, in: CGRect(origin: .zero, size: size), ctx.cgContext)
        }
        cache[key] = img
        return img
    }

    static func draw(_ mark: Mark, in rect: CGRect, _ cg: CGContext) {
        if let letters = mark.lettering {
            ChainLogo.color(0xFF0420).setFill()
            UIBezierPath(ovalIn: rect).fill()
            let font = UIFont.systemFont(ofSize: rect.height * 0.40, weight: .heavy)
            let italic = font.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]).map { UIFont(descriptor: $0, size: 0) } ?? font
            let text = letters as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: italic, .foregroundColor: UIColor.white, .kern: -rect.height * 0.01]
            let s = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), withAttributes: attrs)
            return
        }
        if mark.disc {
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
        let box = rect.insetBy(dx: rect.width * mark.inset, dy: rect.height * mark.inset)
        let scale = min(box.width / mark.viewBox.width, box.height / mark.viewBox.height)
        let w = mark.viewBox.width * scale, h = mark.viewBox.height * scale
        cg.saveGState()
        cg.translateBy(x: box.midX - w / 2, y: box.midY - h / 2)
        cg.scaleBy(x: scale, y: scale)
        for layer in mark.layers {
            let path = SVGPath.parse(layer.d)
            if let stops = layer.gradient, let line = layer.gradientLine {
                cg.saveGState()
                cg.addPath(path)
                cg.clip()
                let colors = stops.map { ChainLogo.color($0.1).cgColor } as CFArray
                let locations = stops.map { CGFloat($0.0) }
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                    cg.drawLinearGradient(g, start: line.0, end: line.1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                cg.restoreGState()
            } else {
                cg.addPath(path)
                cg.setFillColor(ChainLogo.color(layer.fill).cgColor)
                cg.fillPath()
            }
        }
        cg.restoreGState()
    }
}

/// SVG path data ("M0,101.12c0-34.64…z") as a CGPath: move, line,
/// horizontal, vertical, cubic, smooth cubic, quadratic and close, absolute
/// and relative, with repeated arguments. Arcs aren't used by the marks.
enum SVGPath {
    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens: [Any] = []
        var number = ""
        func flush() { if !number.isEmpty, let v = Double(number) { tokens.append(v) }; number = "" }
        var prev: Character = " "
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush(); tokens.append(ch)
            } else if ch == "-" && !(prev == "e" || prev == "E") {
                flush(); number = "-"
            } else if ch == "." && number.contains(".") {
                flush(); number = "."
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" {
                flush()
            } else {
                number.append(ch)
            }
            prev = ch
        }
        flush()

        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero, lastControl: CGPoint?
        func n() -> CGFloat? {
            guard i < tokens.count, let v = tokens[i] as? Double else { return nil }
            i += 1
            return CGFloat(v)
        }
        while i < tokens.count {
            if let c = tokens[i] as? Character { cmd = c; i += 1 }
            let rel = cmd.isLowercase
            let o = rel ? cur : .zero
            switch cmd {
            case "M", "m":
                guard let x = n(), let y = n() else { i += 1; continue }
                cur = CGPoint(x: o.x + x, y: o.y + y); start = cur
                path.move(to: cur)
                cmd = rel ? "l" : "L"
                lastControl = nil
            case "L", "l":
                guard let x = n(), let y = n() else { i += 1; continue }
                cur = CGPoint(x: o.x + x, y: o.y + y); path.addLine(to: cur); lastControl = nil
            case "H", "h":
                guard let x = n() else { i += 1; continue }
                cur = CGPoint(x: (rel ? cur.x : 0) + x, y: cur.y); path.addLine(to: cur); lastControl = nil
            case "V", "v":
                guard let y = n() else { i += 1; continue }
                cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + y); path.addLine(to: cur); lastControl = nil
            case "C", "c":
                guard let x1 = n(), let y1 = n(), let x2 = n(), let y2 = n(), let x = n(), let y = n() else { i += 1; continue }
                let c1 = CGPoint(x: o.x + x1, y: o.y + y1), c2 = CGPoint(x: o.x + x2, y: o.y + y2)
                cur = CGPoint(x: o.x + x, y: o.y + y)
                path.addCurve(to: cur, control1: c1, control2: c2); lastControl = c2
            case "S", "s":
                guard let x2 = n(), let y2 = n(), let x = n(), let y = n() else { i += 1; continue }
                let c1 = lastControl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + x2, y: o.y + y2)
                cur = CGPoint(x: o.x + x, y: o.y + y)
                path.addCurve(to: cur, control1: c1, control2: c2); lastControl = c2
            case "Q", "q":
                guard let x1 = n(), let y1 = n(), let x = n(), let y = n() else { i += 1; continue }
                let c = CGPoint(x: o.x + x1, y: o.y + y1)
                cur = CGPoint(x: o.x + x, y: o.y + y)
                path.addQuadCurve(to: cur, control: c); lastControl = nil
            case "Z", "z":
                path.closeSubpath(); cur = start; lastControl = nil
            default:
                i += 1
            }
        }
        return path
    }
}
