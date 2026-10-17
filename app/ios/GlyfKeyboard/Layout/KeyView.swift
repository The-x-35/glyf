import UIKit

/// How the return key looks for the focused field, measured against
/// Apple's keyboard on the iOS 26.5 simulator and an iPhone 16 Pro: its
/// glyph (or a word Apple spells out) and, for go, search, send and done,
/// the blue key with a white glyph.
struct ReturnFace: Equatable {
    var symbol: String?
    var pointSize: CGFloat = 19.5
    var weight: UIImage.SymbolWeight = .light
    var text: String?
    var primary = false

    static let plain = ReturnFace(symbol: "return")
}

/// One key. Glass fill + hairline stroke + shadow per §5.1; press scales to
/// 0.96 and brightens (§5.2). Carries its own charge-ring and ripple-tint
/// layers so RippleEngine never touches the blur backdrop (§5.3).
final class KeyView: UIControl {

    let spec: KeySpec
    private let label = UILabel()
    /// The letters under a pad digit.
    private let subtitle = UILabel()
    private let icon = UIImageView()
    private let accentDot = CALayer()
    /// A theme's key texture, between the fill and the glyphs: Marble's
    /// veins (one shared pattern tile) or Rose Gold's satin on its function
    /// keys. Hidden on every other look.
    private let textureLayer = CAGradientLayer()
    /// A theme's finish (shared/themes/styles.py): the key's face drawn
    /// once per class and size by KeyFaces and shared by every key like it.
    /// Under the glyphs; empty without a theme.
    private let faceLayer = CALayer()
    private var facePressed = false
    private var faceSize = CGSize.zero
    /// A theme's legend style: hairline copies, a glow's second pass and a
    /// foil's gradient, around the label or the symbol.
    private struct LegendExtra { let view: UIView; let dy: CGFloat; let onIcon: Bool }
    private var legendExtras: [LegendExtra] = []
    private var foilView: GradientView?
    let tintLayer = CALayer()          // ripple overlay, opacity 0 at rest
    private var chargeRing: CAShapeLayer?

    var isBound = false { didSet { updateBinding() } }
    /// Set by KeyboardView on shift changes; letters re-render.
    var shifted = false { didSet { updateFace(); setNeedsLayout() } }   // capitals sit 1pt lower
    /// The return key's look for the focused field.
    var returnFace = ReturnFace.plain { didSet { updateFace(); updateFill(pressed: false) } }
    /// Greyed while a field that enables its return key automatically is empty.
    var returnEnabled = true { didSet { updateFace(); updateFill(pressed: false) } }

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        isExclusiveTouch = false
        layer.cornerRadius = Glass.radiusKey
        layer.cornerCurve = .continuous
        layer.borderWidth = Glass.hairlineWidth
        let shadow = Glass.keyFaceShadow
        layer.shadowOpacity = shadow.opacity
        layer.shadowOffset = shadow.offset
        layer.shadowRadius = shadow.radius
        layer.shadowColor = shadow.color.cgColor

        textureLayer.cornerRadius = Glass.radiusKey
        textureLayer.cornerCurve = .continuous
        textureLayer.isHidden = true
        layer.insertSublayer(textureLayer, at: 0)
        faceLayer.isHidden = true
        layer.insertSublayer(faceLayer, at: 0)

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        addSubview(label)
        subtitle.textAlignment = .center
        subtitle.isHidden = true
        addSubview(subtitle)
        icon.contentMode = .center
        // Measured against iOS: shift and delete draw ~19.7 x 17pt, which is
        // this symbol size. Ours used to come out a tenth small.
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 19.5, weight: Glass.glyphWeight(.light))
        icon.tintColor = Glass.keyInk
        addSubview(icon)

        tintLayer.backgroundColor = Glass.accentPrimary.cgColor
        tintLayer.opacity = 0
        tintLayer.cornerRadius = Glass.radiusKey
        tintLayer.cornerCurve = .continuous
        layer.addSublayer(tintLayer)

        accentDot.backgroundColor = Glass.accentPrimary.cgColor
        accentDot.cornerRadius = 2
        accentDot.isHidden = true
        layer.addSublayer(accentDot)

        updateFace()
        updateFill(pressed: false)

        // Match the id XCUITest uses; display strings vary with shift.
        accessibilityIdentifier = "key:\(spec.id)"
        // The number pad's empty corner is not a key at all.
        isAccessibilityElement = !(spec.disabled && spec.char == "")
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let base = padBaseline {
            // Apple's pads, measured: a digit's baseline 2.7pt below the
            // middle and its letters' 18pt below, whether or not the key has
            // letters; the bare corner labels a little higher than centred.
            let f = label.font ?? .systemFont(ofSize: 22)
            label.frame = CGRect(x: 0, y: bounds.midY + base - f.ascender,
                                 width: bounds.width, height: f.lineHeight)
            let sf = subtitle.font ?? .systemFont(ofSize: 9)
            subtitle.frame = CGRect(x: 0, y: bounds.midY + 18 - sf.ascender,
                                    width: bounds.width, height: sf.lineHeight)
        } else {
            // The system keyboard sits its capitals 1pt below where a centred
            // label puts them; lowercase already lands on Apple's row.
            label.frame = spec.isChar && shifted && !spec.pad ? bounds.offsetBy(dx: 0, dy: 1) : bounds
        }
        icon.frame = bounds
        layoutLegend()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        faceLayer.frame = bounds
        CATransaction.commit()
        if bounds.size != faceSize { applyFace(pressed: facePressed) }
        textureLayer.frame = bounds
        tintLayer.frame = bounds
        accentDot.frame = CGRect(x: bounds.width - 10.5, y: 5.5, width: 5, height: 5)
        accentDot.cornerRadius = 2.5
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds, cornerRadius: Glass.radiusKey).cgPath
    }

    // MARK: Face

    private var isSpecial: Bool {
        switch spec.kind {
        case .char: return false
        default: return true
        }
    }

    /// Grey keys on the web: shift, delete, 123, emoji, globe, return.
    /// The space bar keeps the letter colour and wears the "glyf" watermark.
    private var isFunctionKey: Bool {
        switch spec.kind {
        case .char, .space: return false
        default: return true
        }
    }

    /// Blue: the field named go, search, send or done, and it may be sent.
    /// A theme's one accent is its return, so with a theme return always
    /// wears it (keycap sets colour the enter key on every board).
    private var isPrimaryReturn: Bool {
        if case .ret = spec.kind { return (returnFace.primary || Glass.skin != nil) && returnEnabled }
        return false
    }

    /// Which of a theme's key classes this key is (§5.1).
    private var themeClass: ThemeKeyClass {
        if isPrimaryReturn { return .ret }
        switch spec.kind {
        case .char: return .letter
        case .space: return .space
        default: return .function
        }
    }

    /// A theme's own shift or delete colours (Primary), or nil.
    private var keyOverride: ThemeOverride? {
        switch spec.kind {
        case .shift: return Glass.keyOverride(shift: true)
        case .delete: return Glass.keyOverride(shift: false)
        default: return nil
        }
    }

    /// Where a pad label's baseline sits below the key's middle; nil for
    /// labels that are simply centred.
    private var padBaseline: CGFloat? {
        guard spec.pad else { return nil }
        switch spec.kind {
        case .char(let c) where c.count == 1 && c.first?.isNumber == true && spec.title == nil:
            return 2.7
        case .char(let c) where spec.bare && !c.isEmpty:
            return 5.3   // the decimal pad's separator
        case .mode:
            return 6
        default:
            return nil
        }
    }

    /// Letter-spaced text with no spacing after the last character, so it
    /// stays centred.
    private static func spaced(_ text: String, font: UIFont, color: UIColor,
                               kern: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let n = (text as NSString).length
        if n > 1 { out.addAttribute(.kern, value: kern, range: NSRange(location: 0, length: n - 1)) }
        return out
    }

    private func updateFace() {
        var text: String?
        var image: UIImage?
        switch spec.kind {
        case .char(let c) where spec.pad:
            // Apple's pads, measured by ink: digits 22pt, "*", "#" and "+"
            // 30pt, "pause" and "wait" 16.5pt.
            text = spec.title ?? c
            if spec.title != nil {
                label.font = Glass.keyFont(ofSize: 16.5)
            } else if c.count == 1, "*#+".contains(c) {
                label.font = Glass.keyFont(ofSize: 30)
            } else {
                label.font = Glass.keyFont(ofSize: 22)
            }
        case .char(let c) where c.count > 1:
            // ".com": Apple sets it at 19pt, like a word, never in capitals.
            text = c
            label.font = Glass.keyFont(ofSize: 19)
        case .char(let c):
            text = shifted ? c.uppercased() : c
            // Measured against the system keyboard on the same simulator, by
            // ink as well as bounding box: a lowercase a matches 24.5pt (24
            // is 2px short in x-height, 25 carries 7% more ink), a capital A
            // matches 22pt with its 46 px cap height. Apple draws capitals
            // smaller so both cases read as one size; one 25pt face made
            // ours shout.
            // A theme's face keeps these sizes (docs/THEMES.md §0.2).
            label.font = Glass.keyFont(ofSize: shifted ? 22 : 24.5)
        case .space:
            // Watermark, not a label (Acti-style restraint).
            text = "glyf"
            label.font = .systemFont(ofSize: 15, weight: .regular)
        case .ret:
            if let word = returnFace.text {
                text = word
                label.font = Glass.keyFont(ofSize: 16)
            } else {
                image = UIImage(systemName: returnFace.symbol ?? "return")
                icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                    pointSize: returnFace.pointSize, weight: Glass.glyphWeight(returnFace.weight))
            }
        case .delete:
            image = UIImage(systemName: "delete.left")
            if spec.pad {
                // Apple's pad draws a bigger one: 24.7 x 20.3pt of light ink.
                icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                    pointSize: 23.5, weight: Glass.glyphWeight(.light))
            }
        case .shift:
            image = UIImage(systemName: "shift")
        case .globe:
            image = UIImage(systemName: "globe")
        case .mode(let m):
            text = m
            // Apple, by ink: "123" and "ABC" 18pt, "#+=" 13pt; on the phone
            // pad "+*#" 23pt, letter-spaced, and "123" 21pt.
            let size: CGFloat = spec.pad ? (m == "+*#" ? 23 : 21) : (m == "#+=" ? 13 : 18)
            label.font = Glass.keyFont(ofSize: size)
        case .emoji:
            image = UIImage(systemName: "face.smiling")
        }
        label.text = text
        label.isHidden = text == nil
        icon.image = image
        icon.isHidden = image == nil
        // Letters take the keys' ink; function keys a theme's function glyph
        // (the same ink on every other look).
        let base = isFunctionKey ? Glass.fnInk : Glass.keyInk
        var ink = base
        if let o = keyOverride { ink = UIColor(rgb: o.glyph) }
        if isPrimaryReturn { ink = Glass.returnInk }
        // Greyed: the phone pad's digits behind +*#, and a return key the
        // field won't take yet. #A6A6A6 on white, as Apple draws them.
        if spec.disabled { ink = base.withAlphaComponent(0.35) }
        if case .ret = spec.kind, !returnEnabled { ink = base.withAlphaComponent(0.35) }
        label.textColor = ink
        icon.tintColor = ink
        if case .space = spec.kind {
            label.textColor = Glass.watermark
        }
        if spec.pad, case .mode("+*#") = spec.kind, let font = label.font {
            label.attributedText = Self.spaced("+*#", font: font, color: ink, kern: 3)
        }
        if let letters = spec.subtitle {
            // Apple's letters: 9pt semibold, 2pt apart (ABC, PQRS, JKL by ink).
            subtitle.attributedText = Self.spaced(letters, font: .systemFont(ofSize: 9, weight: .semibold),
                                                  color: ink, kern: 2)
            subtitle.isHidden = false
        } else {
            subtitle.isHidden = true
        }
        // XCUITest addressing: letters by face, specials by stable id.
        accessibilityLabel = spec.isChar ? text : spec.id
        applyLegend()
        setNeedsLayout()
    }

    /// Trackpad look during a space-bar glide: glyphs and the binding dot
    /// fade out, the key shapes stay (Apple blanks faces, not the board).
    func setFaceHidden(_ hidden: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        UIView.animate(withDuration: hidden ? 0.12 : 0.18) {
            self.label.alpha = alpha
            self.icon.alpha = alpha
            for e in self.legendExtras { e.view.alpha = alpha }
            self.foilView?.alpha = alpha
        }
        accentDot.opacity = Float(alpha)
    }

    func setShiftState(_ state: ShiftState) {
        guard case .shift = spec.kind else { return }
        let name: String
        switch state {
        case .off: name = "shift"
        case .on: name = "shift.fill"
        case .capsLock: name = "capslock.fill"
        }
        icon.image = UIImage(systemName: name)
        applyLegend()
        setNeedsLayout()
    }

    private func updateBinding() {
        accentDot.isHidden = !isBound
        accentDot.backgroundColor = Glass.boundDot.cgColor
        updateFill(pressed: false)
    }

    func updateFill(pressed: Bool) {
        // A theme's face goes over whatever the branch below sets.
        defer { applyFace(pressed: pressed) }
        if spec.bare {
            // Apple's pad function keys have no cap; a press shows one.
            backgroundColor = pressed && !spec.disabled ? Glass.fillKey : .clear
            layer.borderWidth = 0
            layer.shadowOpacity = 0
            return
        }
        let shadow = Glass.keyFaceShadow
        if isPrimaryReturn {
            backgroundColor = pressed ? Glass.returnBluePressed : Glass.returnBlue
            let border = Glass.skinBorder(for: .ret)
            layer.borderWidth = border?.width ?? 0
            layer.borderColor = border?.color.cgColor
            layer.shadowColor = shadow.color.cgColor
            layer.shadowOpacity = shadow.opacity
            layer.shadowRadius = shadow.radius
            layer.shadowOffset = shadow.offset
            textureLayer.isHidden = true
            return
        }
        if isBound && !pressed && Glass.keyTheme == "glow" {
            // Glow theme: faint wash + accent UNDER-GLOW (Acti's M-key
            // move). Never an outline ring — borders were the noise.
            backgroundColor = Glass.fillKeyBound
            layer.borderWidth = Glass.hairlineWidth
            layer.borderColor = Glass.strokeHairline.cgColor
            layer.shadowColor = Glass.accentPrimary.cgColor
            layer.shadowOpacity = 0.38
            layer.shadowRadius = 5
            layer.shadowOffset = CGSize(width: 0, height: 2.5)
            return
        }
        // Site (default), glass and classic: uniform keys, the DOT alone marks
        // bindings — simple like Apple, just with purple dots. The Gboard
        // "borders" toggle firms the outline; NEVER an accent border. The site
        // look draws no outline at all, only the hard bottom edge.
        // A theme with a border of its own always draws it, inside the
        // key's bounds, so no key grows (§0.1, §5.1).
        if let border = Glass.skinBorder(for: themeClass) {
            layer.borderWidth = border.width
            layer.borderColor = border.color.cgColor
        } else {
            let borderless = Glass.solidLook && !Glass.keyBorders
            layer.borderWidth = Glass.keyBorders ? 1 : (borderless ? 0 : Glass.hairlineWidth)
            layer.borderColor = (Glass.keyBorders ? Glass.strokeKeyBorder
                                                  : Glass.strokeHairline).cgColor
        }
        layer.shadowColor = shadow.color.cgColor
        layer.shadowOpacity = shadow.opacity
        layer.shadowRadius = shadow.radius
        layer.shadowOffset = shadow.offset
        if let o = keyOverride {
            backgroundColor = UIColor(rgb: pressed ? o.pressed : o.fill)
        } else if isFunctionKey {
            backgroundColor = pressed ? Glass.fillKeyFnPressed : Glass.fillKeyFn
        } else if case .space = spec.kind {
            backgroundColor = pressed ? Glass.fillKeySpacePressed : Glass.fillKeySpace
        } else {
            backgroundColor = pressed ? Glass.fillKeyPressed : Glass.fillKey
        }
        updateTexture(pressed: pressed)
    }

    /// Marble's veins on every key cap, at the tile's 3%; Rose Gold's satin
    /// on its function keys at rest (a press shows the plain pressed fill).
    private func updateTexture(pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let texture = Glass.skin?.keyTexture, let v = Glass.skinVariant else {
            textureLayer.isHidden = true
            return
        }
        switch texture.kind {
        case .veins:
            textureLayer.colors = nil
            textureLayer.backgroundColor = ThemeTextures.veins(ink: v.keyText, alpha: texture.amplitude).cgColor
            textureLayer.isHidden = false
        case .satin:
            guard isFunctionKey, keyOverride == nil, !pressed else {
                textureLayer.isHidden = true
                return
            }
            textureLayer.backgroundColor = nil
            textureLayer.colors = ThemeTextures.satin(v.function.fill, glyph: v.functionGlyph)
            textureLayer.startPoint = CGPoint(x: 0.5, y: 0)
            textureLayer.endPoint = CGPoint(x: 0.5, y: 1)
            textureLayer.isHidden = false
        }
    }

    // MARK: A theme's finish (shared/themes/styles.py, tools/theme_mock.py)

    /// The face class a theme draws on this key; nil for no theme and for
    /// the pads' capless keys.
    private var faceClass: KeyFaces.FaceClass? {
        guard Glass.skin != nil, !spec.bare else { return nil }
        switch themeClass {
        case .letter: return .letter
        case .function: return .function
        case .space: return .space
        case .ret: return .ret
        }
    }

    /// The key's name for ornaments; a return that isn't wearing the accent
    /// (greyed for an empty field) takes none.
    private var ornamentTarget: ThemeOrnamentTarget? {
        switch spec.kind {
        case .char: return .letter
        case .space: return .space
        case .shift: return .shift
        case .delete: return .delete
        case .ret: return isPrimaryReturn ? .ret : nil
        default: return .function
        }
    }

    /// Round keycaps go on single letters only, never a pad key or ".com".
    private var allowRound: Bool { spec.isChar && !spec.pad && (spec.char?.count ?? 0) == 1 }

    /// The theme's fill for this key, at rest or pressed.
    private func themeFill(_ v: ThemeVariant, pressed: Bool) -> UInt32 {
        if isPrimaryReturn { return pressed ? v.returnPressed : v.returnFill }
        if let o = keyOverride { return pressed ? o.pressed : o.fill }
        if isFunctionKey { return pressed ? v.function.pressed : v.function.fill }
        if case .space = spec.kind { return pressed ? v.space.pressed : v.space.fill }
        return pressed ? v.letter.pressed : v.letter.fill
    }

    private var displayScale: CGFloat {
        let s = window?.screen.scale ?? traitCollection.displayScale
        return s > 0 ? s : 3
    }

    /// The cached face image for this key's class, fill and size: the key's
    /// own background goes clear under it, the 1pt edge stays (a round
    /// keycap draws its own shadow inside the cell instead).
    private func applyFace(pressed: Bool) {
        facePressed = pressed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let cls = faceClass, let skin = Glass.skin, let v = Glass.skinVariant,
              bounds.width >= 1, bounds.height >= 1 else {
            faceLayer.contents = nil
            faceLayer.isHidden = true
            faceSize = bounds.size
            return
        }
        faceSize = bounds.size
        let face = KeyFaces.face(cls, in: v.style)
        let round = KeyFaces.isRound(face, size: bounds.size, allowed: allowRound)
        let scale = displayScale
        let request = KeyFaces.Request(size: bounds.size, scale: scale, faceClass: cls, target: ornamentTarget,
                                       fill: themeFill(v, pressed: pressed), pressed: pressed, allowRound: allowRound)
        guard let image = KeyFaces.image(theme: skin, dark: Glass.isDark, request: request) else {
            faceLayer.isHidden = true
            return
        }
        faceLayer.contents = image.cgImage
        faceLayer.contentsScale = scale
        faceLayer.isHidden = false
        backgroundColor = .clear
        if round {
            layer.shadowOpacity = 0
            layer.borderWidth = 0
        }
    }

    /// The legend styles of the reference's legendText: engraved and
    /// letterpress hairlines, letterpress's bleed, foil's leaf and glow's
    /// phosphor, on the label or the symbol (SF Symbols take the style
    /// through tinted copies; foil there is its middle colour).
    private func applyLegend() {
        for e in legendExtras { e.view.removeFromSuperview() }
        legendExtras = []
        foilView?.removeFromSuperview()
        foilView = nil
        for l in [label.layer, icon.layer] {
            l.shadowOpacity = 0
            l.shouldRasterize = false
        }
        guard faceClass != nil, let v = Glass.skinVariant else { return }
        if case .space = spec.kind { return }   // the watermark stays plain
        let lg = faceClass == .ret ? v.style.returnLegend : v.style.legend
        guard lg.style != .ink else { return }
        let onIcon: Bool
        if !label.isHidden, label.text?.isEmpty == false {
            onIcon = false
        } else if !icon.isHidden, icon.image != nil {
            onIcon = true
        } else {
            return
        }
        let ink = (onIcon ? icon.tintColor : label.textColor) ?? Glass.keyInk
        let light = KeyFaces.luminance(themeFill(v, pressed: false)) > 0.45
        let src: UIView = onIcon ? icon : label
        switch lg.style {
        case .ink:
            return
        case .engraved, .letterpress:
            if light {
                addLegendCopy(onIcon: onIcon, color: UIColor(white: 1, alpha: 0.75), dy: 0.7)
            } else {
                addLegendCopy(onIcon: onIcon, color: UIColor(white: 0, alpha: 0.6), dy: -0.6)
            }
            if lg.style == .letterpress { setGlow(src, ink, opacity: 0.55, radius: 0.3) }
        case .foil:
            addLegendCopy(onIcon: onIcon, color: UIColor(white: 0, alpha: 0.45), dy: -0.6)
            guard lg.foil.count == 3 else { return }
            if onIcon {
                icon.tintColor = UIColor(rgb: lg.foil[1])
            } else {
                let fv = GradientView()
                fv.isUserInteractionEnabled = false
                fv.gradient.colors = lg.foil.map { UIColor(rgb: $0).cgColor }
                fv.gradient.locations = [0, 0.55, 1]
                fv.mask = legendLabelCopy(color: .black)
                insertSubview(fv, aboveSubview: label)
                foilView = fv
                label.textColor = .clear
            }
        case .glow:
            // The canvas fills the glyph twice under its shadow: a second
            // pass behind doubles the bleed the same way.
            let back = addLegendCopy(onIcon: onIcon, color: ink, dy: 0)
            setGlow(back, ink, opacity: 0.9, radius: 2.8)
            setGlow(src, ink, opacity: 0.9, radius: 2.8)
        }
        layoutLegend()
    }

    /// The canvas's shadowBlur b (points) as a layer's shadowRadius: about
    /// 0.47 b, fitted to the mock's glow on the simulator (b = 6 spreads
    /// like a radius of 2.8; 6 itself spread twice as wide and half as
    /// bright).
    private func setGlow(_ view: UIView, _ ink: UIColor, opacity: Float, radius: CGFloat) {
        view.layer.shadowColor = ink.withAlphaComponent(1).cgColor
        view.layer.shadowOpacity = opacity * Float(ink.cgColor.alpha)
        view.layer.shadowRadius = radius
        view.layer.shadowOffset = .zero
        view.layer.shouldRasterize = true
        view.layer.rasterizationScale = displayScale
    }

    private func legendLabelCopy(color: UIColor) -> UILabel {
        let l = UILabel()
        l.isUserInteractionEnabled = false
        l.font = label.font
        l.textAlignment = label.textAlignment
        l.adjustsFontSizeToFitWidth = label.adjustsFontSizeToFitWidth
        l.minimumScaleFactor = label.minimumScaleFactor
        let text = NSMutableAttributedString(attributedString: label.attributedText
                                             ?? NSAttributedString(string: label.text ?? ""))
        text.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.length))
        l.attributedText = text
        return l
    }

    @discardableResult
    private func addLegendCopy(onIcon: Bool, color: UIColor, dy: CGFloat) -> UIView {
        let view: UIView
        if onIcon {
            let iv = UIImageView(image: icon.image)
            iv.contentMode = icon.contentMode
            iv.preferredSymbolConfiguration = icon.preferredSymbolConfiguration
            iv.tintColor = color
            view = iv
        } else {
            view = legendLabelCopy(color: color)
        }
        view.isUserInteractionEnabled = false
        insertSubview(view, belowSubview: onIcon ? icon : label)
        legendExtras.append(LegendExtra(view: view, dy: dy, onIcon: onIcon))
        return view
    }

    private func layoutLegend() {
        for e in legendExtras {
            e.view.frame = (e.onIcon ? icon.frame : label.frame).offsetBy(dx: 0, dy: e.dy)
        }
        guard let fv = foilView else { return }
        fv.frame = label.frame
        fv.mask?.frame = fv.bounds
        // The leaf runs over the glyphs' ink, top to bottom, as the
        // canvas's gradient over the text's bounding box.
        let font = label.font ?? .systemFont(ofSize: 24.5)
        let h = max(fv.bounds.height, 1)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label.text ?? "", attributes: [.font: font]))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let baseline = (fv.bounds.height - font.lineHeight) / 2 + font.ascender
        let top = baseline - ink.maxY, bottom = baseline - ink.minY
        fv.gradient.startPoint = CGPoint(x: 0.5, y: top / h)
        fv.gradient.endPoint = CGPoint(x: 0.5, y: max(bottom, top + 1) / h)
    }

    func setPressed(_ pressed: Bool) {
        // INSTANT, like Apple: fill change + balloon on the same frame.
        // No scale animation — animated transforms read as lag under fast
        // typing; the balloon/darkening IS the feedback.
        guard !spec.disabled else { return }
        updateFill(pressed: pressed)
        // Apple's pads and its .com key show no balloon.
        if spec.isChar, !spec.pad, (spec.char?.count ?? 0) == 1 {
            if pressed { showPreview() } else { hidePreview() }
        }
    }

    // MARK: Press preview balloon (system-keyboard behavior)

    private var previewView: UIView?

    /// Apple's key callout, measured on its own keyboard on the iOS 26.5
    /// Pro Max simulator (Arpit, 2026-10-17: "why is the feel of key coming
    /// up on touch not same in iphone keyboard and ours, make them same"):
    /// one shape grown out of the key, never a box floating above it. The
    /// bulb is the key's width plus 12pt a side with 12pt top corners, its
    /// top 69pt above the key's top; the sides fall straight to 15pt above
    /// the key, then an S-curve meets the key's own sides 5pt below its top
    /// and runs down to the key's bottom corners. The key's own fill, no
    /// border, no shadow. The letter is 1.5 times the key's (a 24.5pt "f"
    /// shows at 36.75), its baseline 20.7pt above the key's top. A key at
    /// the screen's edge keeps that edge straight and leans the bulb inward
    /// (21.5pt wider than the key). Measured on 45pt keys (Pro Max) and 43pt
    /// ones (17e: bulb 66.7 above, baseline 20 above). Where the keyboard's top edge leaves too
    /// little room (the top row: an extension can't draw above its window,
    /// Apple's own callout can), the neck then the bulb get shorter.
    private func showPreview() {
        guard previewView == nil, let host = superview, bounds.width > 10 else { return }
        let k = frame
        let s = k.height / 45
        let r = Glass.radiusKey
        let corner: CGFloat = 12
        // How far above the key the window lets us draw (1pt kept clear).
        let topInWindow = window.map { host.convert(k.origin, to: $0).y } ?? k.minY
        let room = max(0, topInWindow - 1)
        let fullRise = 69 - (45 - k.height) * 1.15
        let baselineRise = 20.7 - (45 - k.height) * 0.35
        var bulbRise = fullRise, neckTopRise = 15 * s
        let neckDrop = 5 * s
        if bulbRise > room {
            let short = bulbRise - room
            // The neck gives up to 6pt, the bulb the rest.
            let neckGive = min(short, 6 * s)
            neckTopRise -= neckGive
            bulbRise = room
        }
        let bulbTop = k.minY - bulbRise
        let neckTop = k.minY - neckTopRise
        let neckBottom = k.minY + neckDrop

        let edgeGap: CGFloat = 1
        var bx0 = k.midX - (k.width + 24) / 2
        var bx1 = k.midX + (k.width + 24) / 2
        var straightLeft = false, straightRight = false
        if bx0 < edgeGap {
            straightLeft = true
            bx0 = k.minX
            bx1 = k.maxX + 21.5
        } else if bx1 > host.bounds.width - edgeGap {
            straightRight = true
            bx1 = k.maxX
            bx0 = k.minX - 21.5
        }

        let path = UIBezierPath()
        let half = (neckBottom - neckTop) / 2
        // Up the left side.
        path.move(to: CGPoint(x: k.minX, y: k.maxY - r))
        if straightLeft {
            path.addLine(to: CGPoint(x: bx0, y: bulbTop + corner))
        } else {
            path.addLine(to: CGPoint(x: k.minX, y: neckBottom))
            path.addCurve(to: CGPoint(x: bx0, y: neckTop),
                          controlPoint1: CGPoint(x: k.minX, y: neckBottom - half),
                          controlPoint2: CGPoint(x: bx0, y: neckTop + half))
            path.addLine(to: CGPoint(x: bx0, y: bulbTop + corner))
        }
        path.addArc(withCenter: CGPoint(x: bx0 + corner, y: bulbTop + corner), radius: corner,
                    startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: bx1 - corner, y: bulbTop))
        path.addArc(withCenter: CGPoint(x: bx1 - corner, y: bulbTop + corner), radius: corner,
                    startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        // Down the right side.
        if straightRight {
            path.addLine(to: CGPoint(x: bx1, y: k.maxY - r))
        } else {
            path.addLine(to: CGPoint(x: bx1, y: neckTop))
            path.addCurve(to: CGPoint(x: k.maxX, y: neckBottom),
                          controlPoint1: CGPoint(x: bx1, y: neckTop + half),
                          controlPoint2: CGPoint(x: k.maxX, y: neckBottom - half))
            path.addLine(to: CGPoint(x: k.maxX, y: k.maxY - r))
        }
        path.addArc(withCenter: CGPoint(x: k.maxX - r, y: k.maxY - r), radius: r,
                    startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: k.minX + r, y: k.maxY))
        path.addArc(withCenter: CGPoint(x: k.minX + r, y: k.maxY - r), radius: r,
                    startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.close()

        let box = path.bounds
        let balloon = UIView(frame: box)
        balloon.isUserInteractionEnabled = false
        let shape = CAShapeLayer()
        path.apply(CGAffineTransform(translationX: -box.minX, y: -box.minY))
        shape.path = path.cgPath
        // A theme's press popup colour (the key's own colour otherwise).
        shape.fillColor = Glass.fillKeySolid.cgColor
        balloon.layer.addSublayer(shape)
        // A theme's letter texture at the face's own alpha, in the
        // callout's shape (never round, never the sheen: the key's fill).
        if let skin = Glass.skin, let v = Glass.skinVariant,
           let tex = KeyFaces.textureOverlay(theme: skin, dark: Glass.isDark, face: v.style.faces.letter,
                                             size: box.size, scale: displayScale) {
            let texture = CALayer()
            texture.frame = CGRect(origin: .zero, size: box.size)
            texture.contents = tex.cgImage
            texture.contentsScale = displayScale
            let mask = CAShapeLayer()
            mask.path = path.cgPath
            texture.mask = mask
            balloon.layer.addSublayer(texture)
        }

        let keySize = label.font?.pointSize ?? 24.5
        // A shortened bulb takes a smaller letter.
        let fullBulb = fullRise - 15 * s
        let fit = min(1, (neckTop - bulbTop) / fullBulb)
        let font = Glass.keyFont(ofSize: keySize * 1.5 * max(0.82, fit))
        let baseline = bulbTop + (fullRise - baselineRise) * fit
        let big = UILabel(frame: CGRect(x: bx0 - box.minX, y: baseline - font.ascender - box.minY,
                                        width: bx1 - bx0, height: font.lineHeight))
        big.textAlignment = .center
        big.font = font
        big.textColor = Glass.skin != nil ? Glass.popupInk : (label.textColor ?? Glass.keyInk)
        big.text = label.text
        balloon.addSubview(big)
        host.addSubview(balloon)
        previewView = balloon
    }

    private func hidePreview() {
        // Gone the moment the finger lifts, like Apple's.
        previewView?.removeFromSuperview()
        previewView = nil
    }

    // MARK: Charge ring (§5.3: 2pt accent stroke contracting 1.18× → key edge)

    /// `delay` holds the ring back so an ordinary tap never flashes it; it
    /// always finishes `delay + duration` after the press.
    func startChargeRing(duration: TimeInterval = Glass.Ripple.holdThreshold,
                         delay: TimeInterval = 0) {
        guard !Glass.reduceMotion else { return }
        cancelChargeRing()
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(roundedRect: bounds, cornerRadius: Glass.radiusKey).cgPath
        ring.fillColor = nil
        ring.strokeColor = Glass.accentPrimary.cgColor
        ring.lineWidth = 2
        ring.frame = bounds
        layer.addSublayer(ring)
        chargeRing = ring

        // The ring starts as far outside a wide key (the space bar) as it
        // does outside a letter, not 18% of the bar's width past each end.
        let start = Glass.Ripple.chargeRingStartScale - 1
        let scaleX = CABasicAnimation(keyPath: "transform.scale.x")
        scaleX.fromValue = 1 + start * min(1, 40 / max(bounds.width, 1))
        scaleX.toValue = 1.0
        let scaleY = CABasicAnimation(keyPath: "transform.scale.y")
        scaleY.fromValue = 1 + start
        scaleY.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.08
        let group = CAAnimationGroup()
        group.animations = [scaleX, scaleY, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .both
        if delay > 0 {
            ring.opacity = 0
            group.beginTime = ring.convertTime(CACurrentMediaTime(), from: nil) + delay
        }
        ring.add(group, forKey: "charge")
    }

    func cancelChargeRing() {
        chargeRing?.removeFromSuperlayer()
        chargeRing = nil
    }

    /// Ignition (§5.3): origin key goes solid accent.
    func igniteOrigin() {
        cancelChargeRing()
        tintLayer.opacity = 1
        label.textColor = .white
        icon.tintColor = .white
    }

    func settleFromIgnition() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = Glass.Ripple.perKeyTint
        tintLayer.add(fade, forKey: "settle")
        tintLayer.opacity = 0
        updateFace()
    }
}

enum ShiftState { case off, on, capsLock }
