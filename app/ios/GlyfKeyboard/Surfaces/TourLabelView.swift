import UIKit

/// The website's coach label (.kb-coach): a purple pill with a small point
/// toward the thing to tap. Touches pass straight through it.
final class TourLabelView: UIView {

    var text: String = "" {
        didSet { label.text = text; setNeedsLayout() }
    }
    /// The point sits on the top edge (label below its target) or the bottom.
    var pointsUp = false { didSet { setNeedsLayout() } }
    /// Where the point sits, from the label's left edge.
    var arrowX: CGFloat = 0 { didSet { setNeedsLayout() } }

    private let pill = UIView()
    private let label = UILabel()
    private let point = CAShapeLayer()
    private static let pointH: CGFloat = 5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        pill.backgroundColor = Glass.accentPrimary
        pill.layer.cornerCurve = .continuous
        pill.layer.shadowColor = Glass.accentPrimary.cgColor
        pill.layer.shadowOpacity = 0.45
        pill.layer.shadowRadius = 7
        pill.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(pill)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        pill.addSubview(label)
        point.fillColor = Glass.accentPrimary.cgColor
        layer.addSublayer(point)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let w = ceil((text as NSString).size(withAttributes: [.font: label.font!]).width)
        return CGSize(width: w + 22, height: 26 + Self.pointH)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pillH = bounds.height - Self.pointH
        pill.frame = CGRect(x: 0, y: pointsUp ? Self.pointH : 0, width: bounds.width, height: pillH)
        pill.layer.cornerRadius = pillH / 2
        label.frame = pill.bounds
        let x = min(max(10, arrowX), bounds.width - 10)
        let path = UIBezierPath()
        if pointsUp {
            path.move(to: CGPoint(x: x - 5.5, y: Self.pointH + 0.5))
            path.addLine(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + 5.5, y: Self.pointH + 0.5))
        } else {
            path.move(to: CGPoint(x: x - 5.5, y: pillH - 0.5))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            path.addLine(to: CGPoint(x: x + 5.5, y: pillH - 0.5))
        }
        path.close()
        point.path = path.cgPath
    }
}
