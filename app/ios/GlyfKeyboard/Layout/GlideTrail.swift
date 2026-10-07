import UIKit

/// What a glide leaves on the keys: the finger's last half second as a
/// ribbon in the accent colour, wide at the finger and tapering to nothing
/// behind it, and the word it is spelling floating above the finger. One
/// shape layer and one label, redrawn per touch, nothing per key (§5.2).
final class GlideTrail: UIView {

    /// How long a point stays in the ribbon.
    static let life: CFTimeInterval = 0.45
    static let headWidth: CGFloat = 7

    private let ribbon = CAShapeLayer()
    private let bubble = UIView()
    private let word = UILabel()
    private var points: [(p: CGPoint, t: CFTimeInterval)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false
        ribbon.fillColor = Glass.accentPrimary.withAlphaComponent(0.6).cgColor
        ribbon.strokeColor = nil
        layer.addSublayer(ribbon)
        // The press balloon's look, so it reads as part of the keyboard.
        bubble.backgroundColor = Glass.fillKeySolid
        bubble.layer.cornerRadius = 12
        bubble.layer.cornerCurve = .continuous
        bubble.layer.borderWidth = Glass.hairlineWidth
        bubble.layer.borderColor = Glass.strokeHairline.cgColor
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.22
        bubble.layer.shadowOffset = CGSize(width: 0, height: 3)
        bubble.layer.shadowRadius = 7
        bubble.isHidden = true
        word.font = .systemFont(ofSize: 20, weight: .semibold)
        word.textColor = Glass.keyInk
        word.textAlignment = .center
        bubble.addSubview(word)
        addSubview(bubble)
    }

    required init?(coder: NSCoder) { fatalError() }

    func begin(at p: CGPoint, time: CFTimeInterval) {
        layer.removeAllAnimations()
        alpha = 1
        points = [(p, time)]
        ribbon.fillColor = Glass.accentPrimary.withAlphaComponent(0.6).cgColor
        bubble.backgroundColor = Glass.fillKeySolid
        word.textColor = Glass.keyInk
        redraw(now: time)
    }

    func extend(to p: CGPoint, time: CFTimeInterval) {
        // A point on top of the last one would bend the ribbon's edge.
        if let last = points.last, hypot(p.x - last.p.x, p.y - last.p.y) < 1.5 {
            points[points.count - 1].t = time
        } else {
            points.append((p, time))
        }
        while points.count > 2, time - points[0].t > Self.life { points.removeFirst() }
        redraw(now: time)
    }

    /// The word the finger is on, above it; nil hides the bubble.
    func show(_ text: String?, over p: CGPoint) {
        guard let text, !text.isEmpty else {
            bubble.isHidden = true
            return
        }
        word.text = text
        let w = max(44, word.intrinsicContentSize.width + 28)
        let h: CGFloat = 40
        var x = p.x - w / 2
        x = min(max(x, 2), bounds.width - 2 - w)
        bubble.frame = CGRect(x: x, y: p.y - 62 - h / 2, width: w, height: h)
        word.frame = bubble.bounds
        bubble.isHidden = false
    }

    /// The finger lifted: the ribbon and the word fade together.
    func end() {
        UIView.animate(withDuration: 0.22, animations: { self.alpha = 0 }) { _ in
            guard self.alpha == 0 else { return }
            self.points = []
            self.ribbon.path = nil
            self.bubble.isHidden = true
        }
    }

    private func redraw(now: CFTimeInterval) {
        guard points.count > 1 else {
            ribbon.path = nil
            return
        }
        // Half-widths grow from the tail to the head; a lone slow point
        // still gets a dot.
        let n = points.count
        var left: [CGPoint] = [], right: [CGPoint] = []
        left.reserveCapacity(n)
        right.reserveCapacity(n)
        for i in 0..<n {
            let p = points[i].p
            let prev = points[max(i - 1, 0)].p, next = points[min(i + 1, n - 1)].p
            var dx = next.x - prev.x, dy = next.y - prev.y
            let len = hypot(dx, dy)
            if len < 0.01 { dx = 1; dy = 0 } else { dx /= len; dy /= len }
            let age = CGFloat(min(max((now - points[i].t) / Self.life, 0), 1))
            let along = CGFloat(i) / CGFloat(n - 1)
            let half = max(0.5, Self.headWidth / 2 * min(along, 1 - age))
            left.append(CGPoint(x: p.x - dy * half, y: p.y + dx * half))
            right.append(CGPoint(x: p.x + dy * half, y: p.y - dx * half))
        }
        let path = UIBezierPath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.close()
        let head = points[n - 1].p
        path.append(UIBezierPath(arcCenter: head, radius: Self.headWidth / 2, startAngle: 0, endAngle: .pi * 2, clockwise: true))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ribbon.path = path.cgPath
        CATransaction.commit()
    }
}
