import UIKit

/// Voice typing's level visual, in the keyboard's panel and on the app's
/// listening screen: a luminous ribbon of fine lines that twists between two
/// waves and swells with the voice, with a soft bloom behind it. With Reduce
/// Motion on it is a row of still bars whose heights follow the level.
///
/// Self-contained (no Glass tokens) so the app compiles it too.
final class VoiceRibbon: UIView {

    /// 0…1, as the app publishes it. Smoothed here, so 16 Hz is plenty.
    var level: Float = 0 {
        didSet { target = CGFloat(min(1, max(0, level))); if reduced { layoutBars() } }
    }
    /// Calm: the ribbon settles into a slow, low breath (finishing, a notice).
    var calm = false { didSet { if reduced { layoutBars() } } }

    /// Three colours, left to right (light, accent, deep).
    var colors: [UIColor] = [] { didSet { applyColors() } }

    private let bloom = CAGradientLayer()
    private let fade = CAGradientLayer()
    private let paint = CAGradientLayer()
    private let strands = CALayer()
    private let fine = CAShapeLayer()
    private let glow = CAShapeLayer()
    private let core = CAShapeLayer()
    private var bars: [CALayer] = []

    private var link: CADisplayLink?
    private var phase: CGFloat = 0
    private var shown: CGFloat = 0.08
    private var target: CGFloat = 0
    private var lastTick: CFTimeInterval = 0
    private var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Lines in the ribbon's mesh.
    private let lineCount = 16

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        bloom.type = .radial
        bloom.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloom.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(bloom)

        // The ribbon: a gradient seen through the strands, faded at the ends.
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.white.cgColor,
                       UIColor.white.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, 0.18, 0.82, 1]
        let holder = CALayer()
        holder.mask = fade
        holder.addSublayer(paint)
        layer.addSublayer(holder)
        self.holder = holder

        paint.startPoint = CGPoint(x: 0, y: 0.5)
        paint.endPoint = CGPoint(x: 1, y: 0.5)
        for s in [glow, fine, core] {
            s.fillColor = nil
            s.lineCap = .round
            s.lineJoin = .round
            strands.addSublayer(s)
        }
        glow.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        glow.lineWidth = 3.2
        fine.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        fine.lineWidth = 0.8
        core.strokeColor = UIColor.white.cgColor
        core.lineWidth = 1.6
        paint.mask = strands
        applyColors()
    }

    private var holder = CALayer()

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        running(window != nil)
    }

    override var isHidden: Bool {
        didSet { running(window != nil && !isHidden) }
    }

    private func running(_ on: Bool) {
        if on && !reduced {
            guard link == nil else { return }
            let l = CADisplayLink(target: Proxy(self), selector: #selector(Proxy.tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            l.add(to: .main, forMode: .common)
            link = l
            lastTick = 0
        } else {
            link?.invalidate()
            link = nil
        }
        strands.isHidden = reduced
        bars.forEach { $0.isHidden = !reduced }
        if reduced { layoutBars() }
    }

    deinit { link?.invalidate() }

    /// CADisplayLink holds its target strongly.
    private final class Proxy {
        weak var owner: VoiceRibbon?
        init(_ o: VoiceRibbon) { owner = o }
        @objc func tick(_ l: CADisplayLink) { owner?.tick(l) }
    }

    private func applyColors() {
        let c = colors.isEmpty
            ? [UIColor(red: 0.69, green: 0.60, blue: 1, alpha: 1),
               UIColor(red: 0.49, green: 0.36, blue: 1, alpha: 1),
               UIColor(red: 0.36, green: 0.55, blue: 1, alpha: 1)]
            : colors
        paint.colors = c.map(\.cgColor)
        let mid = c[c.count / 2]
        bloom.colors = [mid.withAlphaComponent(0.34).cgColor, mid.withAlphaComponent(0).cgColor]
        for b in bars { b.backgroundColor = mid.cgColor }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.frame = bounds
        fade.frame = bounds
        paint.frame = bounds
        strands.frame = bounds
        let side = max(bounds.width * 0.7, bounds.height * 2)
        bloom.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 4,
                             width: side, height: side / 2)
        CATransaction.commit()
        if reduced { layoutBars() } else { draw(at: shown) }
    }

    // MARK: Motion

    private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = lastTick == 0 ? 1.0 / 60 : min(0.05, now - lastTick)
        lastTick = now
        let goal = calm ? 0.05 : max(0.12, target)
        // Rise fast, fall slower: a voice's peaks read, its gaps don't flicker.
        let rate: CGFloat = goal > shown ? 14 : 4.5
        shown += (goal - shown) * min(1, rate * CGFloat(dt))
        phase += CGFloat(dt) * (calm ? 0.9 : 1.6 + shown * 3.2)
        draw(at: shown)
    }

    private func draw(at amp: CGFloat) {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let mid = h / 2
        let maxA = h * 0.46
        let a = maxA * (0.14 + 0.86 * amp)
        let steps = max(24, Int(w / 6))
        // Two waves the mesh is strung between; their phases drift apart so
        // the ribbon twists, as a silk band does.
        func waveA(_ t: CGFloat) -> CGFloat {
            sin(t * .pi * 2 * 1.15 + phase) * 0.75 + sin(t * .pi * 2 * 2.3 - phase * 0.6) * 0.25
        }
        func waveB(_ t: CGFloat) -> CGFloat {
            sin(t * .pi * 2 * 1.05 - phase * 0.8 + 2.2) * 0.7 + sin(t * .pi * 2 * 1.9 + phase * 0.5) * 0.3
        }
        let mesh = CGMutablePath()
        let centre = CGMutablePath()
        var envs: [CGFloat] = [], pa: [CGFloat] = [], pb: [CGFloat] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            // Tapers to a thread at both ends.
            let env = pow(sin(t * .pi), 1.6)
            envs.append(env); pa.append(waveA(t)); pb.append(waveB(t))
        }
        for k in 0..<lineCount {
            let f = CGFloat(k) / CGFloat(lineCount - 1)
            for i in 0...steps {
                let x = w * CGFloat(i) / CGFloat(steps)
                let y = mid + a * envs[i] * (pa[i] * (1 - f) + pb[i] * f)
                if i == 0 { mesh.move(to: CGPoint(x: x, y: y)) } else { mesh.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        for i in 0...steps {
            let x = w * CGFloat(i) / CGFloat(steps)
            let y = mid + a * envs[i] * (pa[i] + pb[i]) / 2
            if i == 0 { centre.move(to: CGPoint(x: x, y: y)) } else { centre.addLine(to: CGPoint(x: x, y: y)) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fine.path = mesh
        glow.path = centre
        core.path = centre
        bloom.opacity = Float(0.35 + amp * 0.65)
        CATransaction.commit()
    }

    // MARK: Reduce Motion: still bars

    private func layoutBars() {
        let count = 13
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let b = CALayer()
                b.cornerRadius = 2
                layer.addSublayer(b)
                return b
            }
            applyColors()
        }
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let barW: CGFloat = 4, gap: CGFloat = 7
        let total = CGFloat(count) * barW + CGFloat(count - 1) * gap
        let lvl = calm ? 0.05 : max(0.08, target)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, b) in bars.enumerated() {
            let t = CGFloat(i) / CGFloat(count - 1)
            let shape = 0.25 + 0.75 * sin(t * .pi)
            let bh = max(barW, h * 0.8 * shape * (0.2 + 0.8 * lvl))
            b.frame = CGRect(x: (w - total) / 2 + CGFloat(i) * (barW + gap), y: (h - bh) / 2,
                             width: barW, height: bh)
            b.isHidden = !reduced
        }
        bloom.opacity = Float(0.3 + lvl * 0.5)
        CATransaction.commit()
    }
}
