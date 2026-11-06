import UIKit

protocol TranslationHUDDelegate: AnyObject {
    func hudClosed()
    func hudRequestTranslation(of text: String, target: String?,
                               completion: @escaping (BackendClient.Translation?) -> Void)
    /// `span` is exactly what was translated, as it stands before the cursor.
    func hudReplaceDraft(with text: String, replacing span: String)
}

/// §6.13 T / website 6.6 — translate never covers the keys. It takes the
/// strip: the direction on the left, the live translation in the middle,
/// Replace on the right. Typing keeps working underneath the whole time.
///
/// Like Google Translate, nothing asks which language this is: the server
/// detects it and picks the direction from the person's two languages.
/// Tapping the direction points the translation somewhere else instead.
final class TranslationHUD: UIView {

    weak var delegate: TranslationHUDDelegate?

    private let directionButton = UIButton(type: .system)
    private let textLabel = UILabel()
    private let replaceButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var pendingWork: DispatchWorkItem?
    private var lastSource = ""
    private var lastTranslation = ""
    /// The end of the draft that was translated, as it stands in the field:
    /// Replace swaps exactly this, never anything before it.
    private var lastWindow = ""
    /// What Replace just put in: the draft is now a translation, and asking
    /// to translate it back would leave the strip on "…" for nothing.
    private var justReplaced = ""
    private var detected: String?
    private var target: String?
    /// Set when the person tapped the direction; nil lets detection decide.
    private var forcedTarget: String?

    init() {
        super.init(frame: .zero)
        // Never fully clear: a keyboard drops touches on clear pixels, and
        // the ✕ and the gaps around it must answer.
        backgroundColor = Glass.solidLook ? Glass.touchableGrid : Glass.fillBar
        accessibilityIdentifier = "hud:translate"

        directionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        directionButton.setTitleColor(Glass.textPrimary, for: .normal)
        directionButton.backgroundColor = Glass.surfaceCard
        directionButton.layer.cornerCurve = .continuous
        directionButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        directionButton.accessibilityIdentifier = "hud:direction"
        directionButton.addAction(UIAction { [weak self] _ in self?.cycleTarget() },
                                  for: .touchUpInside)
        addSubview(directionButton)

        textLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        textLabel.textColor = Glass.textPrimary
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.accessibilityIdentifier = "hud:text"
        textLabel.text = "…"
        addSubview(textLabel)

        replaceButton.setTitle("Replace", for: .normal)
        replaceButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        replaceButton.setTitleColor(.white, for: .normal)
        replaceButton.backgroundColor = Glass.imBlue
        replaceButton.layer.cornerCurve = .continuous
        replaceButton.accessibilityIdentifier = "hud:replace"
        replaceButton.addAction(UIAction { [weak self] _ in self?.applyTapped() },
                                for: .touchUpInside)
        addSubview(replaceButton)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold), forImageIn: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "hud:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.hudClosed() },
                              for: .touchUpInside)
        addSubview(closeButton)

        refreshTarget()
        updateReplaceEnabled()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A translation is showing and Replace would put it in.
    var ready: Bool { !lastTranslation.isEmpty }
    /// Where translations go, once the server has said.
    var targetLanguage: String? { target }

    /// Translations go to `language` ("Spanish"), as a tap on the direction
    /// would set it (the strip's recommended action).
    func translate(into language: String) {
        forcedTarget = language
        target = language
        updateDirection()
        lastSource = ""
        if !lastWindow.isEmpty { draftChanged(lastWindow) }
    }

    /// A fresh strip decides the direction itself again.
    func refreshTarget() {
        forcedTarget = nil
        updateDirection()
    }

    private func updateDirection() {
        let title: String
        if let detected, let target {
            title = "\(detected) → \(target)"
        } else {
            title = "Translate"
        }
        directionButton.setTitle(title, for: .normal)
        setNeedsLayout()
    }

    /// Where a tap on the direction sends the translation next: the person's
    /// two languages, then the common ones, never the language being typed.
    private func cycleTarget() {
        let pair = BackendClient.translatePair
        var options = [pair.primary, pair.secondary, "English", "Hindi", "Spanish", "French"]
        var seen = Set<String>()
        options = options.filter { seen.insert($0).inserted && $0 != detected }
        guard !options.isEmpty else { return }
        let current = target ?? options[0]
        let next = options[((options.firstIndex(of: current) ?? -1) + 1) % options.count]
        forcedTarget = next
        target = next
        updateDirection()
        let window = lastWindow
        lastSource = ""
        if !window.isEmpty { draftChanged(window) }
    }

    /// What of a draft gets translated: all of it up to 280 characters, else
    /// its end from the start of a sentence (or at least of a word), so no
    /// word is cut in half and Replace swaps only what it translated.
    static func window(of draft: String) -> String {
        guard draft.count > 280 else { return draft }
        let tail = String(draft.suffix(280))
        if let r = tail.range(of: #"[.!?\n]\s+"#, options: .regularExpression), r.upperBound < tail.endIndex {
            return String(tail[r.upperBound...])
        }
        if let space = tail.firstIndex(of: " ") { return String(tail[tail.index(after: space)...]) }
        return tail
    }

    /// Called by the VC on word commits (space/return) with the draft.
    func draftChanged(_ draft: String) {
        let window = Self.window(of: draft)
        let text = window.trimmingCharacters(in: .whitespacesAndNewlines)
        lastWindow = window
        guard !text.isEmpty, text != lastSource, text != justReplaced else { return }
        justReplaced = ""
        lastSource = text
        // The draft moved on: never leave the previous translation standing.
        lastTranslation = ""
        textLabel.text = "…"
        setNeedsLayout()
        updateReplaceEnabled()
        pendingWork?.cancel()
        let forced = forcedTarget
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.delegate?.hudRequestTranslation(of: text, target: forced) { [weak self] result in
                guard let self, let result, self.lastSource == text else { return }
                self.detected = result.detected
                self.target = result.target
                self.updateDirection()
                self.lastTranslation = result.text
                self.textLabel.text = result.text
                self.textLabel.textColor = Glass.textPrimary
                self.setNeedsLayout()
                self.updateReplaceEnabled()
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func updateReplaceEnabled() {
        let on = !lastTranslation.isEmpty
        replaceButton.isEnabled = on
        replaceButton.alpha = on ? 1 : 0.3
    }

    private func applyTapped() {
        guard !lastTranslation.isEmpty else { return }
        let replaced = lastTranslation
        // The space the draft ended on stays after the translation.
        let trailing = String(lastWindow.reversed().prefix(while: { $0.isWhitespace }).reversed())
        delegate?.hudReplaceDraft(with: replaced + trailing, replacing: lastWindow)
        justReplaced = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSource = ""
        lastTranslation = ""
        // Done, not waiting: the strip rests until the next word is typed.
        textLabel.text = ""
        updateReplaceEnabled()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let band = Glass.stripBand
        let h = bounds.height - band
        let mid = band + h / 2 - Glass.stripLift
        let pillH: CGFloat = min(30, h - 10)
        let dirW = min(directionButton.intrinsicContentSize.width, bounds.width * 0.42)
        directionButton.frame = CGRect(x: 8, y: mid - pillH / 2, width: dirW, height: pillH)
        directionButton.layer.cornerRadius = pillH / 2

        let row = Glass.stripBox(height: h, mid: mid)
        closeButton.frame = CGRect(x: bounds.width - 32, y: row.y, width: 28, height: row.height)
        let replaceW: CGFloat = 84, replaceH: CGFloat = min(30, h - 10)
        replaceButton.frame = CGRect(x: bounds.width - 32 - replaceW - 6,
                                     y: mid - replaceH / 2,
                                     width: replaceW, height: replaceH)
        replaceButton.layer.cornerRadius = replaceH / 2
        let textX = directionButton.frame.maxX + 10
        let textW = max(20, replaceButton.frame.minX - textX - 8)
        let lines = fitText(width: textW)
        let textH = lines == 2 ? max(row.height, ceil(textLabel.font.lineHeight * 2) + 2) : row.height
        textLabel.frame = CGRect(x: textX, y: lines == 2 ? mid - textH / 2 : row.y, width: textW, height: textH)
    }

    /// The translation: one line at 17, shrinking to 14; then two lines at 14
    /// when they hold all of it; else one line at 14 with its start cut, the
    /// newest words in view. Beside the direction pill a phone's width left
    /// only "…emos a las 8!" of "¡Nos vemos a las 8!" (Android twin:
    /// GlyfIME.fitTranslation). Returns the number of lines.
    private func fitText(width: CGFloat) -> Int {
        let s = (textLabel.text ?? "") as NSString
        func font(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .semibold) }
        var size: CGFloat = 17
        while size > 14, s.size(withAttributes: [.font: font(size)]).width > width { size -= 0.5 }
        textLabel.font = font(size)
        let tooLong = s.size(withAttributes: [.font: font(size)]).width > width
        let twoLines = tooLong && s.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: font(size)], context: nil
        ).height <= font(size).lineHeight * 2 + 1
        textLabel.numberOfLines = twoLines ? 2 : 1
        textLabel.lineBreakMode = twoLines ? .byWordWrapping : .byTruncatingHead
        return twoLines ? 2 : 1
    }
}
