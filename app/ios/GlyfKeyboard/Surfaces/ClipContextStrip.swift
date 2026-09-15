import UIKit

protocol ClipContextStripDelegate: AnyObject {
    /// The strip was tapped while it only knew *that* something was copied.
    func clipStripRead()
    /// The quoted text was tapped: act on it.
    func clipStripAct(_ text: String)
    func clipStripDismissed()
}

/// Something was just copied → it waits above the toolbar, ready to act on
/// (Acti's copied-context card, Glyf's way).
///
/// Reading the pasteboard can raise Apple's paste prompt, so the strip starts
/// out knowing only that a copy happened (changeCount + hasStrings, both
/// prompt-free). The user's tap is the intent that reads it; from then on the
/// text is quoted, and tapping it acts on it.
final class ClipContextStrip: UIView {

    weak var delegate: ClipContextStripDelegate?

    private let icon = UIImageView(image: UIImage(systemName: "doc.on.clipboard"))
    private let label = UILabel()
    private let closeButton = UIButton(type: .system)
    private(set) var text: String?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear

        icon.tintColor = Glass.textSecondary
        icon.contentMode = .scaleAspectFit
        addSubview(icon)

        label.font = .systemFont(ofSize: 14.5)
        label.textColor = Glass.textPrimary
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        closeButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)),
                             for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "clip:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.clipStripDismissed() }, for: .touchUpInside)
        addSubview(closeButton)

        isAccessibilityElement = false
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "clip:card"
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        showAvailable()
    }

    required init?(coder: NSCoder) { fatalError() }

    func showAvailable() {
        text = nil
        label.text = "Copied text"
        label.textColor = Glass.textSecondary
    }

    func show(text: String) {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        self.text = text
        label.text = "“\(flat)”"
        label.textColor = Glass.textPrimary
    }

    @objc private func tapped() {
        if let text { delegate?.clipStripAct(text) } else { delegate?.clipStripRead() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        icon.frame = CGRect(x: 14, y: (h - 18) / 2, width: 18, height: 18)
        closeButton.frame = CGRect(x: bounds.width - 42, y: 0, width: 38, height: h)
        label.frame = CGRect(x: 42, y: 0, width: bounds.width - 42 - 46, height: h)
    }
}

/// When the strip may show: a copy made recently that the user hasn't
/// dismissed or used. iOS gives no copy timestamp, so "recent" is measured
/// from the first time the keyboard saw this changeCount.
enum ClipContext {
    static let freshFor: TimeInterval = 10 * 60
    private static let file = "clip-context.json"

    static func isFresh(now: Date = Date()) -> Bool {
        let board = UIPasteboard.general
        let cc = board.changeCount
        var state = AppGroupStore.readJSON(name: file) ?? [:]
        if (state["done"] as? Int) == cc { return false }
        if (state["cc"] as? Int) != cc {
            // A copy we haven't seen before starts its clock now.
            state = ["cc": cc, "seen": now.timeIntervalSince1970, "done": state["done"] ?? -1]
            AppGroupStore.writeJSON(state, name: file)
        }
        let seen = (state["seen"] as? Double) ?? now.timeIntervalSince1970
        return now.timeIntervalSince1970 - seen < freshFor && board.hasStrings
    }

    /// Dismissed or used: never offer this copy again.
    static func markDone() {
        var state = AppGroupStore.readJSON(name: file) ?? [:]
        state["done"] = UIPasteboard.general.changeCount
        AppGroupStore.writeJSON(state, name: file)
    }
}
