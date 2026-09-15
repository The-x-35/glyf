import UIKit

/// One key. Glass fill + hairline stroke + shadow per §5.1; press scales to
/// 0.96 and brightens (§5.2). Carries its own charge-ring and ripple-tint
/// layers so RippleEngine never touches the blur backdrop (§5.3).
final class KeyView: UIControl {

    let spec: KeySpec
    private let label = UILabel()
    private let icon = UIImageView()
    private let accentDot = CALayer()
    let tintLayer = CALayer()          // ripple overlay, opacity 0 at rest
    private var chargeRing: CAShapeLayer?

    var isBound = false { didSet { updateBinding() } }
    /// Set by KeyboardView on shift changes; letters re-render.
    var shifted = false { didSet { updateFace() } }

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
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        icon.tintColor = Glass.textPrimary
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
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
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

    private func updateFace() {
        var text: String?
        var image: UIImage?
        switch spec.kind {
        case .char(let c):
            text = shifted ? c.uppercased() : c
            label.font = .systemFont(ofSize: 23, weight: .regular)
        case .space:
            // Watermark, not a label (Acti-style restraint).
            text = "glyf"
            label.font = .systemFont(ofSize: 13, weight: .medium)
        case .ret:
            image = UIImage(systemName: "return")
        case .delete:
            image = UIImage(systemName: "delete.left")
        case .shift:
            image = UIImage(systemName: "shift")
        case .globe:
            image = UIImage(systemName: "globe")
        case .mode(let m):
            text = m
            label.font = .systemFont(ofSize: 15, weight: .medium)
        case .emoji:
            image = UIImage(systemName: "face.smiling")
        }
        label.text = text
        label.isHidden = text == nil
        icon.image = image
        icon.isHidden = image == nil
        label.textColor = Glass.textPrimary
        if case .space = spec.kind {
            label.textColor = Glass.watermark
        }
        // XCUITest addressing: letters by face, specials by stable id.
        accessibilityLabel = spec.isChar ? text : spec.id
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
        updateFill(pressed: false)
    }

    func updateFill(pressed: Bool) {
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
        // Glass (default) + classic: uniform keys, the DOT alone marks
        // bindings — simple like Apple, just with purple dots. The Gboard
        // "borders" toggle firms the outline; NEVER an accent border.
        layer.borderWidth = Glass.keyBorders ? 1 : Glass.hairlineWidth
        layer.borderColor = (Glass.keyBorders ? Glass.strokeKeyBorder
                                              : Glass.strokeHairline).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Glass.keyShadowOpacity
        layer.shadowRadius = Glass.keyShadowRadius
        layer.shadowOffset = Glass.keyShadowOffset
        backgroundColor = pressed ? Glass.fillKeyPressed : Glass.fillKey
    }

    func setPressed(_ pressed: Bool) {
        // INSTANT, like Apple: fill change + balloon on the same frame.
        // No scale animation — animated transforms read as lag under fast
        // typing; the balloon/darkening IS the feedback.
        updateFill(pressed: pressed)
        if spec.isChar {
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
        big.textColor = Glass.textPrimary
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
        label.textColor = Glass.textPrimary
        icon.tintColor = Glass.textPrimary
        if case .space = spec.kind {
            label.textColor = Glass.watermark
        }
    }
}

enum ShiftState { case off, on, capsLock }
