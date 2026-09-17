import UIKit

protocol GlyfBarDelegate: AnyObject {
    func barClosed()
    func barReplace(text: String, input: GlyfBar.Input)
    func barInsert(text: String)
    func barCopy(text: String)
    func barPromptActivated(_ editor: InlineEditor)
    func barNeedsRunsRefresh()
}

/// §6.4 — the Glyf Bar. Rises inside the keyboard frame on space long-press.
/// Input: field content (documentContext) else clipboard. Result lands in a
/// preview strip with Replace / Insert / Copy — NEVER auto-inserts.
final class GlyfBar: UIView {

    weak var delegate: GlyfBarDelegate?

    struct Input {
        var text: String
        var source: String        // "field" | "clipboard" | "empty"
        var consumedBefore: Int   // chars of before-context Replace removes
        /// The after-cursor text the run also read. Replace must remove it
        /// too, or a cursor glided mid-sentence leaves the tail duplicated.
        var after = ""
    }

    private(set) var input = Input(text: "", source: "empty", consumedBefore: 0)
    private var hasFullAccess = false

    /// Compose phase: a 140pt strip above the live keys (prompt typing needs
    /// them). Result phase: expands over the keys to show the preview strip.
    var onExpandChange: (() -> Void)?
    private(set) var expandedForResult = false {
        didSet { if oldValue != expandedForResult { onExpandChange?() } }
    }

    private let sourceChip = UILabel()
    private let promptEditor = InlineEditor(placeholder: "Tell Glyf what to do…")
    private let runButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let chipsScroll = ControlScrollView()
    private let chipsStack = UIStackView()
    private let resultView = UITextView()
    private let statusLabel = UILabel()
    private let actionsStack = UIStackView()
    private var runningTask: URLSessionDataTask?
    private var resultText = ""
    private var lastGlyfId: String?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear

        sourceChip.font = .systemFont(ofSize: 10.5, weight: .bold)
        sourceChip.textColor = Glass.textSecondary
        sourceChip.textAlignment = .center
        sourceChip.layer.cornerRadius = 9
        sourceChip.layer.cornerCurve = .continuous
        sourceChip.layer.masksToBounds = true
        sourceChip.backgroundColor = Glass.surfaceCard
        sourceChip.layer.borderWidth = Glass.hairlineWidth
        sourceChip.layer.borderColor = Glass.strokeHairline.cgColor
        addSubview(sourceChip)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "bar:close"
        closeButton.addAction(UIAction { [weak self] _ in
            self?.cancelRun()
            self?.delegate?.barClosed()
        }, for: .touchUpInside)
        addSubview(closeButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(promptTapped))
        promptEditor.addGestureRecognizer(tap)
        addSubview(promptEditor)

        runButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        runButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 28),
                                                  forImageIn: .normal)
        runButton.tintColor = Glass.textPrimary // ink, like every CTA
        runButton.accessibilityIdentifier = "bar:run"
        runButton.addAction(UIAction { [weak self] _ in self?.runPrompt() }, for: .touchUpInside)
        addSubview(runButton)

        chipsScroll.showsHorizontalScrollIndicator = false
        addSubview(chipsScroll)
        chipsStack.axis = .horizontal
        chipsStack.spacing = 6
        chipsScroll.addSubview(chipsStack)
        buildChips()

        resultView.isEditable = false
        resultView.backgroundColor = Glass.surfaceCard
        resultView.layer.cornerRadius = 14
        resultView.layer.cornerCurve = .continuous
        resultView.layer.borderWidth = Glass.hairlineWidth
        resultView.layer.borderColor = Glass.strokeHairline.cgColor
        resultView.font = .systemFont(ofSize: 15)
        resultView.textColor = Glass.textPrimary
        resultView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        resultView.accessibilityIdentifier = "bar:result"
        resultView.isHidden = true
        addSubview(resultView)

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = Glass.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.isUserInteractionEnabled = true
        statusLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(statusTapped)))
        addSubview(statusLabel)

        actionsStack.axis = .horizontal
        actionsStack.spacing = 8
        actionsStack.distribution = .fillEqually
        actionsStack.isHidden = true
        // Design language: the primary action is the BLACK pill; siblings
        // are quiet white with hairlines. No purple washes.
        for (title, id) in [("Replace", "replace"), ("Insert", "insert"), ("Copy", "copy")] {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14.5, weight: .semibold)
            b.layer.cornerRadius = 17
            b.layer.cornerCurve = .continuous
            b.accessibilityIdentifier = "bar:\(id)"
            if id == "replace" {
                b.backgroundColor = Glass.textPrimary
                b.setTitleColor(Glass.isDark ? Glass.brandInk : .white, for: .normal)
            } else {
                b.backgroundColor = Glass.surfaceCard
                b.setTitleColor(Glass.textPrimary, for: .normal)
                b.layer.borderWidth = Glass.hairlineWidth
                b.layer.borderColor = Glass.strokeHairline.cgColor
            }
            b.addAction(UIAction { [weak self] _ in self?.action(id) }, for: .touchUpInside)
            actionsStack.addArrangedSubview(b)
        }
        addSubview(actionsStack)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildChips() {
        for id in GlyfCatalog.quickGlyfIds {
            guard let info = GlyfCatalog.all.first(where: { $0.id == id }) else { continue }
            let b = UIButton(type: .system)
            b.setTitle(info.title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.backgroundColor = Glass.surfaceCard
            b.layer.cornerRadius = 15
            b.layer.cornerCurve = .continuous
            b.layer.borderWidth = Glass.hairlineWidth
            b.layer.borderColor = Glass.strokeHairline.cgColor
            b.layer.shadowOpacity = 0.06
            b.layer.shadowOffset = CGSize(width: 0, height: 1)
            b.layer.shadowRadius = 2
            b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 13, bottom: 6, right: 13)
            b.accessibilityIdentifier = "chip:\(info.id)"
            b.addAction(UIAction { [weak self] _ in self?.runGlyf(id: info.id) },
                        for: .touchUpInside)
            chipsStack.addArrangedSubview(b)
        }
    }

    // MARK: Lifecycle

    /// Called by the VC when the bar opens.
    func present(input: Input, hasFullAccess: Bool) {
        self.input = input
        self.hasFullAccess = hasFullAccess
        expandedForResult = false
        resultText = ""
        resultView.text = ""
        resultView.isHidden = true
        actionsStack.isHidden = true
        promptEditor.clear()

        switch input.source {
        case "field": sourceChip.text = "  FIELD TEXT  "
        case "clipboard": sourceChip.text = "  CLIPBOARD  "
        default: sourceChip.text = "  NO INPUT — prompt runs alone  "
        }
        setNeedsLayout() // chip sizes from its text

        if !hasFullAccess {
            statusLabel.text = "AI needs Full Access — enable it in Settings → Glyf"
            statusLabel.textColor = Glass.accentWarning
        } else {
            statusLabel.text = "Pick a quick Glyf or describe what you want"
            statusLabel.textColor = Glass.textSecondary
        }
        delegate?.barNeedsRunsRefresh()
    }

    @objc private func promptTapped() {
        promptEditor.isActive = true
        delegate?.barPromptActivated(promptEditor)
    }

    func deactivatePrompt() { promptEditor.isActive = false }

    // MARK: Running

    private func runPrompt() {
        let p = promptEditor.text.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        run(glyfId: "custom.prompt", vars: ["prompt": p])
    }

    /// Bound-key path (§6.5): long-press J etc. lands here already running.
    /// Callers may pin vars (TonesPopup passes the chosen tone).
    func autoRun(glyfId: String, vars: [String: String] = [:]) {
        if vars.isEmpty {
            runGlyf(id: glyfId)
        } else {
            run(glyfId: glyfId, vars: vars)
        }
    }

    /// §6.15 tone learning reads these on close/replace.
    var lastRunGlyfId: String? { lastGlyfId }
    var hasResult: Bool { !resultText.isEmpty }

    private func runGlyf(id: String) {
        var vars: [String: String] = [:]
        if id == "glyf.translate" {
            vars["target"] = SettingsStore.current.translateTarget
        }
        run(glyfId: id, vars: vars)
    }

    private func run(glyfId: String, vars: [String: String]) {
        guard hasFullAccess else {
            statusLabel.text = "AI needs Full Access — enable it in Settings → Glyf"
            statusLabel.textColor = Glass.accentWarning
            return
        }
        cancelRun()
        lastGlyfId = glyfId
        expandedForResult = true
        resultText = ""
        resultView.text = ""
        resultView.isHidden = false
        actionsStack.isHidden = true
        statusLabel.text = "Running \(GlyfCatalog.title(for: glyfId))…"
        statusLabel.textColor = Glass.textSecondary

        runningTask = BackendClient.shared.run(
            glyfId: glyfId, input: input.text, vars: vars,
            onToken: { [weak self] t in
                guard let self else { return }
                self.resultText += t
                self.resultView.text = self.resultText
            },
            onDone: { [weak self] text, remaining in
                guard let self else { return }
                self.resultText = text
                self.resultView.text = text
                self.actionsStack.isHidden = false
                if let remaining {
                    self.statusLabel.text = "\(remaining) free runs left today"
                } else {
                    self.statusLabel.text = " "
                }
                self.delegate?.barNeedsRunsRefresh()
            },
            onError: { [weak self] message in
                guard let self else { return }
                self.resultView.isHidden = self.resultText.isEmpty
                self.statusLabel.text = message
                self.statusLabel.textColor = Glass.accentWarning
            })
    }

    @objc private func statusTapped() {
        // Quiet inline failure → "Tap to retry" (§6.4).
        if let id = lastGlyfId, statusLabel.text?.contains("retry") == true {
            runGlyf(id: id)
        }
    }

    func cancelRun() {
        runningTask?.cancel()
        runningTask = nil
    }

    private func action(_ id: String) {
        guard !resultText.isEmpty else { return }
        switch id {
        case "replace":
            delegate?.barReplace(text: resultText, input: input)
        case "insert":
            delegate?.barInsert(text: resultText)
        case "copy":
            delegate?.barCopy(text: resultText)
            statusLabel.text = "Copied"
            statusLabel.textColor = Glass.textSecondary
        default:
            break
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        sourceChip.frame = CGRect(x: 10, y: 6, width: min(220, sourceChip.intrinsicContentSize.width + 8),
                                  height: 18)
        closeButton.frame = CGRect(x: w - 40, y: 2, width: 34, height: 26)
        promptEditor.frame = CGRect(x: 10, y: 28, width: w - 58, height: 34)
        runButton.frame = CGRect(x: w - 44, y: 28, width: 36, height: 34)
        chipsScroll.frame = CGRect(x: 0, y: 68, width: w, height: 32)
        let chipsW = chipsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        chipsStack.frame = CGRect(x: 10, y: 0, width: max(chipsW, w - 20), height: 30)
        chipsScroll.contentSize = CGSize(width: chipsW + 20, height: 32)

        if expandedForResult {
            resultView.isHidden = false
            statusLabel.frame = CGRect(x: 10, y: bounds.height - 24, width: w - 20, height: 20)
            let resultH = bounds.height - 104 - 28 - 40
            resultView.frame = CGRect(x: 10, y: 104, width: w - 20, height: max(44, resultH))
            actionsStack.frame = CGRect(x: 10, y: bounds.height - 64, width: w - 20, height: 34)
        } else {
            resultView.isHidden = true
            actionsStack.isHidden = true
            statusLabel.frame = CGRect(x: 10, y: bounds.height - 26, width: w - 20, height: 20)
        }
    }
}
