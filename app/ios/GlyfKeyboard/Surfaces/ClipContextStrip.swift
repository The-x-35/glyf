import UIKit

protocol ClipContextStripDelegate: AnyObject {
    /// The strip was tapped while it only knew *that* something was copied.
    func clipStripRead()
    /// Paste was tapped: put the copy in the field (and in history).
    func clipStripPaste()
    /// The quoted text was tapped: act on it.
    func clipStripAct(_ text: String)
    func clipStripDismissed()
}

/// Something was just copied → it waits above the toolbar, ready to act on
/// (Acti's copied-context card, Glyf's way).
///
/// Reading the pasteboard can raise Apple's paste prompt, so the strip starts
/// out knowing only that a copy happened (changeCount + hasStrings, both
/// prompt-free). Paste is the moment the person asks for the text, so that is
/// where the read happens — iOS shows its one alert per copy, and from then
/// on the text lives in Glyf's own history and never needs asking again.
///
/// (UIPasteControl would skip that alert, but inside a keyboard extension it
/// renders inert: it asks canPaste and then never delivers a tap.)
final class ClipContextStrip: UIView {

    weak var delegate: ClipContextStripDelegate?

    private let icon = UIImageView(image: UIImage(systemName: "doc.on.clipboard"))
    private let label = UILabel()
    private let closeButton = UIButton(type: .system)
    private var pasteButton: UIButton?
    private(set) var text: String?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear

        let paste = UIButton(type: .system)
        paste.setTitle("Paste", for: .normal)
        paste.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        paste.setTitleColor(.white, for: .normal)
        paste.backgroundColor = Glass.accentPrimary
        paste.layer.cornerRadius = 10
        paste.layer.cornerCurve = .continuous
        paste.accessibilityIdentifier = "clip:paste"
        paste.addAction(UIAction { [weak self] _ in self?.delegate?.clipStripPaste() },
                        for: .touchUpInside)
        addSubview(paste)
        pasteButton = paste

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
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        showAvailable()
    }

    required init?(coder: NSCoder) { fatalError() }

    func showAvailable() {
        text = nil
        label.text = "Copied text"
        label.textColor = Glass.textSecondary
        pasteButton?.isHidden = false
    }

    func show(text: String) {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        self.text = text
        label.text = "“\(flat)”"
        label.textColor = Glass.textPrimary
        // The text is in hand: the strip is now a thing to act on, not paste.
        pasteButton?.isHidden = true
        setNeedsLayout()
    }

    @objc private func tapped() {
        if let text { delegate?.clipStripAct(text) } else { delegate?.clipStripRead() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        icon.frame = CGRect(x: 14, y: (h - 18) / 2, width: 18, height: 18)
        closeButton.frame = CGRect(x: bounds.width - 42, y: 0, width: 38, height: h)
        var labelRight = bounds.width - 46
        if let pasteButton, !pasteButton.isHidden {
            let w: CGFloat = 72, ph = min(h - 12, 32)
            pasteButton.frame = CGRect(x: labelRight - w - 6, y: (h - ph) / 2,
                                       width: w, height: ph)
            labelRight -= w + 14
        }
        label.frame = CGRect(x: 42, y: 0, width: max(40, labelRight - 42), height: h)
    }
}

extension ClipContextStrip: UIGestureRecognizerDelegate {
    /// The Paste button owns its own taps: without this the strip's gesture
    /// swallows them and Paste would do the same thing as the strip.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let pasteButton, !pasteButton.isHidden else { return true }
        return !pasteButton.frame.contains(touch.location(in: self))
    }
}

/// When the strip may show: a copy made recently that the user hasn't
/// dismissed or used. iOS gives no copy timestamp, so "recent" is measured
/// from the first time the keyboard saw this changeCount.
enum ClipContext {
    /// The clipboard panel's "just copied" card. The strip's chip is shorter
    /// lived (StripPolicy.pasteFresh, docs/STRIP-POLICY.md).
    static let freshFor: TimeInterval = 10 * 60
    private static let file = "clip-context.json"

    static func isFresh(now: Date = Date(), within: TimeInterval = freshFor) -> Bool {
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
        return now.timeIntervalSince1970 - seen < within && board.hasStrings
    }

    /// Dismissed or used: never offer this copy again.
    static func markDone() {
        var state = AppGroupStore.readJSON(name: file) ?? [:]
        state["done"] = UIPasteboard.general.changeCount
        AppGroupStore.writeJSON(state, name: file)
    }
}
