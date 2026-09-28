import UIKit

protocol GlyfBarDelegate: AnyObject {
    func barClosed()
    /// Runs a glyf on the bar's input: the prompt typed here, or one of the
    /// person's own glyfs. The answer plays out in the act panel.
    func barRun(glyfId: String, vars: [String: String], title: String, input: GlyfBar.Input)
    func barPromptActivated(_ editor: InlineEditor)
    /// No Full Access: the app is where it gets turned on.
    func barOpenApp()
    func barHeightChanged()
    func barNeedsRunsRefresh()
}

/// §6.4 Ask Glyf. Holding glyf with nothing typed (or Ask in the g menu)
/// turns the strip into one prompt: close where the g was, "Ask Glyf" and its
/// send arrow across the rest, the keys live underneath and typing into it.
/// A second row shows only when there is something for it: the copied text
/// the prompt will work on (tap it to leave it out) and the person's own
/// glyfs. Answers open in the act panel, like everything else AI.
final class GlyfBar: UIView {

    weak var delegate: GlyfBarDelegate?

    struct Input {
        var text: String
        var source: String        // "field" | "clipboard" | "empty"
        var consumedBefore: Int   // chars of before-context an answer replaces
        /// The after-cursor text the run also read, replaced with it.
        var after = ""
    }

    private(set) var input = Input(text: "", source: "empty", consumedBefore: 0)
    private var hasFullAccess = false

    static let chipsRowHeight: CGFloat = 44
    /// What the bar adds under the strip: the chips row when it has chips.
    var extraHeight: CGFloat {
        chipsStack.arrangedSubviews.isEmpty && !rowShown ? 0 : GlyfBar.chipsRowHeight
    }
    /// The chips row, once shown, keeps its room while the bar is open:
    /// leaving the text out must not shrink the keyboard under the finger.
    private var rowShown = false

    private let closeButton = UIButton(type: .system)
    private let promptEditor = InlineEditor(placeholder: "Ask Glyf", symbol: "sparkles")
    private let runButton = UIButton(type: .system)
    private let accessButton = UIButton(type: .system)
    private let chipsScroll = ControlScrollView()
    private let chipsStack = UIStackView()

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        // Exactly the strip's close: the g pill's place and shape.
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        closeButton.tintColor = Glass.textPrimary
        closeButton.backgroundColor = Glass.fillSoft
        closeButton.layer.cornerRadius = 10
        closeButton.layer.cornerCurve = .continuous
        closeButton.accessibilityIdentifier = "bar:close"
        closeButton.accessibilityLabel = "Close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.barClosed() },
                              for: .touchUpInside)
        addSubview(closeButton)

        promptEditor.showsEnd = true
        promptEditor.accessibilityIdentifier = "bar:prompt"
        promptEditor.onChange = { [weak self] _ in self?.updateRun() }
        promptEditor.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(promptTapped)))
        addSubview(promptEditor)

        runButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        runButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .bold), forImageIn: .normal)
        runButton.accessibilityIdentifier = "bar:run"
        runButton.accessibilityLabel = "Ask"
        runButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        addSubview(runButton)

        accessButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
        accessButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold), forImageIn: .normal)
        accessButton.setTitle("  Allow Full Access to ask Glyf", for: .normal)
        accessButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        accessButton.titleLabel?.lineBreakMode = .byTruncatingTail
        accessButton.setTitleColor(Glass.textPrimary, for: .normal)
        accessButton.tintColor = Glass.accentPrimary
        accessButton.backgroundColor = Glass.surfaceCard
        accessButton.layer.cornerCurve = .continuous
        accessButton.accessibilityIdentifier = "bar:access"
        accessButton.addAction(UIAction { [weak self] _ in self?.delegate?.barOpenApp() },
                               for: .touchUpInside)
        addSubview(accessButton)

        chipsScroll.showsHorizontalScrollIndicator = false
        addSubview(chipsScroll)
        chipsStack.axis = .horizontal
        chipsStack.spacing = 6
        chipsStack.alignment = .center
        chipsScroll.addSubview(chipsStack)
        updateRun()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    /// Called by the VC when the bar opens.
    func present(input: Input, hasFullAccess: Bool) {
        self.input = input
        self.hasFullAccess = hasFullAccess
        promptEditor.clear()
        promptEditor.isHidden = !hasFullAccess
        runButton.isHidden = !hasFullAccess
        accessButton.isHidden = hasFullAccess
        rebuildChips()
        updateRun()
        // Holding glyf to ask means typing the ask next: the keys go here.
        if hasFullAccess { promptTapped() }
        delegate?.barNeedsRunsRefresh()
        setNeedsLayout()
    }

    @objc private func promptTapped() {
        promptEditor.isActive = true
        delegate?.barPromptActivated(promptEditor)
    }

    func deactivatePrompt() { promptEditor.isActive = false }

    /// Send arrow and return both ask.
    func submit() {
        let p = promptEditor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasFullAccess, !p.isEmpty else { return }
        delegate?.barRun(glyfId: "custom.prompt", vars: ["prompt": p], title: p, input: input)
    }

    private func updateRun() {
        let ready = !promptEditor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        runButton.backgroundColor = ready ? Glass.textPrimary : Glass.fillField
        runButton.tintColor = ready ? (Glass.isDark ? Glass.brandInk : .white) : Glass.textSecondary
    }

    // MARK: Chips

    private func rebuildChips() {
        let before = extraHeight
        rowShown = rowShown || !chipsStack.arrangedSubviews.isEmpty
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard hasFullAccess else {
            if extraHeight != before { delegate?.barHeightChanged() }
            return
        }
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.source != "empty", !text.isEmpty {
            let copied = input.source == "clipboard"
            let chip = ContextChip(symbol: copied ? "doc.on.clipboard" : "text.cursor",
                                   text: "“\(GlyfBar.preview(text))”")
            chip.accessibilityIdentifier = "bar:context"
            chip.accessibilityLabel = copied ? "Copied text, tap to leave it out"
                                             : "Your text, tap to leave it out"
            chip.addAction(UIAction { [weak self] _ in self?.dropContext() }, for: .touchUpInside)
            chipsStack.addArrangedSubview(chip)
        }
        // The person's own glyfs, one tap each.
        let mine = (SettingsStore.current.customTitles ?? [:])
            .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        for (glyfId, title) in mine {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.backgroundColor = Glass.surfaceCard
            b.layer.cornerRadius = 16
            b.layer.cornerCurve = .continuous
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 13, bottom: 0, right: 13)
            b.heightAnchor.constraint(equalToConstant: 32).isActive = true
            b.accessibilityIdentifier = "chip:\(glyfId)"
            b.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.barRun(glyfId: glyfId, vars: [:], title: title, input: self.input)
            }, for: .touchUpInside)
            chipsStack.addArrangedSubview(b)
        }
        setNeedsLayout()
        if extraHeight != before { delegate?.barHeightChanged() }
    }

    /// Leave the copied text out: the prompt runs on its own.
    private func dropContext() {
        input = Input(text: "", source: "empty", consumedBefore: 0)
        rebuildChips()
    }

    /// One line of the context, short enough for its chip.
    static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > 30 ? String(flat.prefix(30)) + "…" : flat
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        // The strip's own measures (Toolbar.layoutSubviews): the close sits
        // where the g pill does, the prompt where the tools were.
        let h = Glass.stripContent
        let mid = Glass.stripBand + h / 2 - Glass.stripLift
        let pillW = (h * 1.18).rounded()
        let pill = Glass.stripBox(height: (h * 0.78).rounded(), mid: mid)
        let pillH = pill.height
        closeButton.frame = CGRect(x: 5, y: pill.y, width: pillW, height: pillH)
        let left = pillW + 11
        let field = CGRect(x: left, y: pill.y, width: max(0, w - left - 6), height: pillH)
        promptEditor.frame = field
        promptEditor.layer.cornerRadius = pillH / 2
        let runD = pillH - 6
        runButton.frame = CGRect(x: field.maxX - runD - 3, y: field.midY - runD / 2,
                                 width: runD, height: runD)
        runButton.layer.cornerRadius = runD / 2
        promptEditor.trailingInset = runD + 10
        accessButton.frame = field
        accessButton.layer.cornerRadius = pillH / 2

        // Under the whole strip, band included (iOS 17 and 18 add one above).
        chipsScroll.frame = CGRect(x: 0, y: Glass.toolbarHeight, width: w, height: GlyfBar.chipsRowHeight)
        let fit = chipsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        chipsStack.frame = CGRect(x: 6, y: (GlyfBar.chipsRowHeight - 32) / 2 - 2,
                                  width: fit.width, height: 32)
        chipsScroll.contentSize = CGSize(width: fit.width + 12, height: GlyfBar.chipsRowHeight)
    }
}

/// The text a prompt will work on, quoted, with a cross to leave it out.
private final class ContextChip: UIControl {
    private let icon = UIImageView()
    private let label = UILabel()
    private let cross = UIImageView()

    init(symbol: String, text: String) {
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceCard
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        icon.image = UIImage(systemName: symbol)
        icon.preferredSymbolConfiguration = .init(pointSize: 11, weight: .semibold)
        icon.tintColor = Glass.accentPrimary
        icon.contentMode = .center
        addSubview(icon)
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = Glass.textPrimary
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        cross.image = UIImage(systemName: "xmark")
        cross.preferredSymbolConfiguration = .init(pointSize: 9, weight: .bold)
        cross.tintColor = Glass.textSecondary
        cross.contentMode = .center
        addSubview(cross)
        for v in [icon, label, cross] { v.isUserInteractionEnabled = false }
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private var labelWidth: CGFloat { min(label.intrinsicContentSize.width, 200) }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 11 + 16 + 6 + labelWidth + 8 + 12 + 11, height: 32)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        icon.frame = CGRect(x: 11, y: 0, width: 16, height: h)
        label.frame = CGRect(x: 33, y: 0, width: labelWidth, height: h)
        cross.frame = CGRect(x: bounds.width - 11 - 12, y: 0, width: 12, height: h)
    }
}
