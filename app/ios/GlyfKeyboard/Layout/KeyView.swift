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
        layer.shadowOpacity = Glass.keyShadowOpacity
        layer.shadowOffset = Glass.keyShadowOffset
        layer.shadowRadius = Glass.keyShadowRadius
        layer.shadowColor = UIColor.black.cgColor

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
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19.5, weight: .light)
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
    private var isPrimaryReturn: Bool {
        if case .ret = spec.kind { return returnFace.primary && returnEnabled }
        return false
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
                label.font = .systemFont(ofSize: 16.5, weight: .regular)
            } else if c.count == 1, "*#+".contains(c) {
                label.font = .systemFont(ofSize: 30, weight: .regular)
            } else {
                label.font = .systemFont(ofSize: 22, weight: .regular)
            }
        case .char(let c) where c.count > 1:
            // ".com": Apple sets it at 19pt, like a word, never in capitals.
            text = c
            label.font = .systemFont(ofSize: 19, weight: .regular)
        case .char(let c):
            text = shifted ? c.uppercased() : c
            // Measured against the system keyboard on the same simulator, by
            // ink as well as bounding box: a lowercase a matches 24.5pt (24
            // is 2px short in x-height, 25 carries 7% more ink), a capital A
            // matches 22pt with its 46 px cap height. Apple draws capitals
            // smaller so both cases read as one size; one 25pt face made
            // ours shout.
            label.font = .systemFont(ofSize: shifted ? 22 : 24.5, weight: .regular)
        case .space:
            // Watermark, not a label (Acti-style restraint).
            text = "glyf"
            label.font = .systemFont(ofSize: 15, weight: .regular)
        case .ret:
            if let word = returnFace.text {
                text = word
                label.font = .systemFont(ofSize: 16, weight: .regular)
            } else {
                image = UIImage(systemName: returnFace.symbol ?? "return")
                icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                    pointSize: returnFace.pointSize, weight: returnFace.weight)
            }
        case .delete:
            image = UIImage(systemName: "delete.left")
            if spec.pad {
                // Apple's pad draws a bigger one: 24.7 x 20.3pt of light ink.
                icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 23.5, weight: .light)
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
            label.font = .systemFont(ofSize: size, weight: .regular)
        case .emoji:
            image = UIImage(systemName: "face.smiling")
        }
        label.text = text
        label.isHidden = text == nil
        icon.image = image
        icon.isHidden = image == nil
        var ink = Glass.keyInk
        if isPrimaryReturn { ink = .white }
        // Greyed: the phone pad's digits behind +*#, and a return key the
        // field won't take yet. #A6A6A6 on white, as Apple draws them.
        if spec.disabled { ink = Glass.keyInk.withAlphaComponent(0.35) }
        if case .ret = spec.kind, !returnEnabled { ink = Glass.keyInk.withAlphaComponent(0.35) }
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
        setNeedsLayout()
    }

    /// Trackpad look during a space-bar glide: glyphs and the binding dot
    /// fade out, the key shapes stay (Apple blanks faces, not the board).
    func setFaceHidden(_ hidden: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        UIView.animate(withDuration: hidden ? 0.12 : 0.18) {
            self.label.alpha = alpha
            self.icon.alpha = alpha
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
    }

    private func updateBinding() {
        accentDot.isHidden = !isBound
        accentDot.backgroundColor = Glass.boundDot.cgColor
        updateFill(pressed: false)
    }

    func updateFill(pressed: Bool) {
        if spec.bare {
            // Apple's pad function keys have no cap; a press shows one.
            backgroundColor = pressed && !spec.disabled ? Glass.fillKey : .clear
            layer.borderWidth = 0
            layer.shadowOpacity = 0
            return
        }
        if isPrimaryReturn {
            backgroundColor = pressed ? Glass.returnBluePressed : Glass.returnBlue
            layer.borderWidth = 0
            layer.shadowColor = Glass.keyShadowColor.cgColor
            layer.shadowOpacity = Glass.keyShadowOpacity
            layer.shadowRadius = Glass.keyShadowRadius
            layer.shadowOffset = Glass.keyShadowOffset
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
        let borderless = Glass.solidLook && !Glass.keyBorders
        layer.borderWidth = Glass.keyBorders ? 1 : (borderless ? 0 : Glass.hairlineWidth)
        layer.borderColor = (Glass.keyBorders ? Glass.strokeKeyBorder
                                              : Glass.strokeHairline).cgColor
        layer.shadowColor = Glass.keyShadowColor.cgColor
        layer.shadowOpacity = Glass.keyShadowOpacity
        layer.shadowRadius = Glass.keyShadowRadius
        layer.shadowOffset = Glass.keyShadowOffset
        if isFunctionKey {
            backgroundColor = pressed ? Glass.fillKeyFnPressed : Glass.fillKeyFn
        } else {
            backgroundColor = pressed ? Glass.fillKeyPressed : Glass.fillKey
        }
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

    private func showPreview() {
        guard previewView == nil, let host = superview, bounds.width > 10 else { return }
        let w = bounds.width * 1.55
        let h = bounds.height * 1.35
        let balloon = UIView(frame: CGRect(
            x: frame.midX - w / 2,
            y: frame.minY - h - 4,
            width: w, height: h))
        balloon.backgroundColor = Glass.fillKeySolid // readable over anything
        balloon.layer.cornerRadius = 12
        balloon.layer.cornerCurve = .continuous
        balloon.layer.borderWidth = Glass.hairlineWidth
        balloon.layer.borderColor = Glass.strokeHairline.cgColor
        balloon.layer.shadowColor = UIColor.black.cgColor
        balloon.layer.shadowOpacity = 0.22
        balloon.layer.shadowOffset = CGSize(width: 0, height: 3)
        balloon.layer.shadowRadius = 7
        balloon.isUserInteractionEnabled = false
        let big = UILabel(frame: balloon.bounds)
        big.textAlignment = .center
        big.font = .systemFont(ofSize: 34, weight: .regular)
        big.textColor = Glass.keyInk
        big.text = label.text
        balloon.addSubview(big)
        // Keep the balloon on-screen at the edges.
        if balloon.frame.minX < 2 { balloon.frame.origin.x = 2 }
        if balloon.frame.maxX > host.bounds.width - 2 {
            balloon.frame.origin.x = host.bounds.width - 2 - w
        }
        host.addSubview(balloon)
        previewView = balloon
    }

    private func hidePreview() {
        guard let balloon = previewView else { return }
        previewView = nil
        UIView.animate(withDuration: 0.06, animations: { balloon.alpha = 0 }) { _ in
            balloon.removeFromSuperview()
        }
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

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = Glass.Ripple.chargeRingStartScale
        scale.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.08
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
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
