import UIKit

/// Voice typing, the whole keyboard (docs/APPS.md 5.17). While the app
/// listens, the strip and the keys give way to one frosted panel of exactly
/// the keyboard's size: ✕ throws the words away, the style pill picks how
/// they will read, ✓ types them in. The words come in big as they are heard,
/// with their punctuation, over a ribbon that moves with the voice. Nothing
/// else to press: there is no separate Transcribe step.
final class VoicePanel: UIView {

    enum Mode: Equatable {
        /// The mic opened the app; nothing heard here yet.
        case opening
        case listening(String)
        /// ✓ tapped: the recognizer is finishing the last words.
        case finishing(String)
        /// The style's glyf is rewriting the words before they go in.
        case polishing(String)
        /// One short line (no Full Access, the microphone busy…); ✕ closes.
        case notice(String)
    }

    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?
    var onStyle: ((VoiceLink.Style) -> Void)?

    private(set) var mode: Mode = .opening
    var style: VoiceLink.Style = .standard { didSet { updatePill() } }

    /// The panel is on screen and wanted (false while it fades away).
    private(set) var isUp = false

    private let material = UIVisualEffectView(effect: nil)
    private let contents = UIView()
    private let wash = CAGradientLayer()
    private let floorWash = CAGradientLayer()
    private let edge = CALayer()
    private let closeButton = UIButton(type: .custom)
    private let pill = UIButton(type: .custom)
    private let pillLabel = UILabel()
    private let pillChevron = UIImageView()
    private let doneButton = UIButton(type: .custom)
    private let textClip = UIView()
    private let textFade = CAGradientLayer()
    private let textLabel = UILabel()
    private let ribbon = VoiceRibbon()
    private let status = UILabel()
    private var menu: StyleMenu?
    private var shimmer: CAGradientLayer?

    /// The words on screen, and when the newest of them arrived.
    private var shownText = ""
    private var freshFrom = 0
    private var settleWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        // Never fully clear: a keyboard drops touches on clear pixels.
        backgroundColor = Glass.touchableGrid
        accessibilityIdentifier = "voice:panel"
        clipsToBounds = true

        addSubview(material)
        contents.alpha = 0
        addSubview(contents)
        contents.layer.addSublayer(wash)
        contents.layer.addSublayer(floorWash)
        contents.layer.addSublayer(edge)
        wash.type = .radial
        wash.startPoint = CGPoint(x: 0.5, y: 0)
        wash.endPoint = CGPoint(x: 1.05, y: 1.1)
        floorWash.startPoint = CGPoint(x: 0.5, y: 1)
        floorWash.endPoint = CGPoint(x: 0.5, y: 0.35)

        closeButton.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        closeButton.accessibilityIdentifier = "voice:cancel"
        closeButton.accessibilityLabel = "Cancel"
        closeButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        doneButton.setImage(UIImage(systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)), for: .normal)
        doneButton.accessibilityIdentifier = "voice:done"
        doneButton.accessibilityLabel = "Done"
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        for b in [closeButton, doneButton] {
            b.layer.cornerCurve = .continuous
            addPress(b)
        }

        pillLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        pillLabel.isUserInteractionEnabled = false
        pillChevron.image = UIImage(systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        pillChevron.contentMode = .center
        pillChevron.isUserInteractionEnabled = false
        pill.addSubview(pillLabel)
        pill.addSubview(pillChevron)
        pill.layer.cornerCurve = .continuous
        pill.accessibilityIdentifier = "voice:style"
        pill.addAction(UIAction { [weak self] _ in self?.toggleMenu() }, for: .touchUpInside)
        addPress(pill)

        textClip.clipsToBounds = true
        textClip.isUserInteractionEnabled = false
        textClip.layer.mask = textFade
        textFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        textFade.locations = [0, 0.34, 1]
        textLabel.numberOfLines = 0
        textLabel.accessibilityIdentifier = "voice:text"
        textClip.addSubview(textLabel)

        status.font = .systemFont(ofSize: 15, weight: .medium)
        status.textAlignment = .center
        status.accessibilityIdentifier = "voice:status"
        status.isUserInteractionEnabled = false

        for v in [textClip, ribbon, status, closeButton, pill, doneButton] as [UIView] {
            contents.addSubview(v)
        }
        applyPalette()
        show(.opening)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Look

    /// The theme's accent where it has one, else Glyf's violet.
    private var accent: UIColor {
        Glass.skin != nil ? Glass.chipAccent : Glass.accentPrimary
    }

    private var ribbonColors: [UIColor] {
        if Glass.skin != nil {
            let a = Glass.chipAccent
            return [a.mixed(with: .white, 0.35), a, a.mixed(with: UIColor(red: 0.3, green: 0.5, blue: 1, alpha: 1), 0.4)]
        }
        return Glass.chromeDark
            ? [UIColor(red: 0.80, green: 0.73, blue: 1, alpha: 1),
               UIColor(red: 0.58, green: 0.45, blue: 1, alpha: 1),
               UIColor(red: 0.40, green: 0.60, blue: 1, alpha: 1)]
            : [UIColor(red: 0.66, green: 0.55, blue: 1, alpha: 1),
               UIColor(red: 0.49, green: 0.36, blue: 1, alpha: 1),
               UIColor(red: 0.30, green: 0.50, blue: 1, alpha: 1)]
    }

    /// Colours follow the keyboard's light or dark (the host's) and theme.
    func applyPalette() {
        let dark = Glass.chromeDark
        if isUp {
            material.effect = Glass.reduceTransparency ? nil : Self.blur(dark: dark)
        }
        material.backgroundColor = Glass.reduceTransparency
            ? Glass.sheetPaint(dark: dark) : .clear
        let a = accent
        wash.colors = [a.withAlphaComponent(dark ? 0.26 : 0.13).cgColor, a.withAlphaComponent(0).cgColor]
        floorWash.colors = [a.withAlphaComponent(dark ? 0.12 : 0.07).cgColor, a.withAlphaComponent(0).cgColor]
        edge.backgroundColor = (dark ? UIColor.white.withAlphaComponent(0.10)
                                     : UIColor.white.withAlphaComponent(0.7)).cgColor

        let glassFill = dark ? UIColor.white.withAlphaComponent(0.13) : UIColor.white.withAlphaComponent(0.78)
        for b in [closeButton, pill] {
            b.backgroundColor = glassFill
            b.layer.borderWidth = Glass.hairlineWidth
            b.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.12)
                                        : UIColor.black.withAlphaComponent(0.05)).cgColor
            b.layer.shadowColor = UIColor.black.cgColor
            b.layer.shadowOpacity = dark ? 0.28 : 0.10
            b.layer.shadowRadius = 8
            b.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        closeButton.tintColor = Glass.textPrimary
        pillLabel.textColor = Glass.textPrimary
        pillChevron.tintColor = Glass.textSecondary
        doneButton.backgroundColor = a
        doneButton.tintColor = a.glyfLuminance > 0.6 ? UIColor(white: 0.07, alpha: 1) : .white
        doneButton.layer.shadowColor = a.cgColor
        doneButton.layer.shadowOpacity = dark ? 0.55 : 0.40
        doneButton.layer.shadowRadius = 12
        doneButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        status.textColor = Glass.textSecondary
        ribbon.colors = ribbonColors
        menu?.applyPalette(accent: a)
        renderText(animatedFresh: false)
    }

    private static func blur(dark: Bool) -> UIBlurEffect {
        UIBlurEffect(style: dark ? .systemThinMaterialDark : .systemThinMaterialLight)
    }

    private func addPress(_ b: UIButton) {
        b.addAction(UIAction { _ in
            UIView.animate(withDuration: 0.12) { b.transform = CGAffineTransform(scaleX: 0.93, y: 0.93) }
        }, for: [.touchDown, .touchDragEnter])
        b.addAction(UIAction { _ in
            UIView.animate(withDuration: 0.18) { b.transform = .identity }
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    // MARK: In and out

    /// Fades the panel in over the keys, blurring them away (~0.25 s).
    func present(alongside: @escaping () -> Void) {
        isUp = true
        let effect: UIBlurEffect? = Glass.reduceTransparency ? nil : Self.blur(dark: Glass.chromeDark)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.material.effect = effect
            self.contents.alpha = 1
            alongside()
        }
    }

    /// The keys come back; the panel goes when they are in.
    func dismiss(alongside: @escaping () -> Void) {
        isUp = false
        menu?.removeFromSuperview(); menu = nil
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState],
                       animations: {
            self.material.effect = nil
            self.contents.alpha = 0
            alongside()
        }, completion: { _ in
            if !self.isUp { self.removeFromSuperview() }
        })
    }

    // MARK: State

    func show(_ mode: Mode) {
        self.mode = mode
        var words = ""
        switch mode {
        case .opening:
            status.text = "Opening Glyf…"
        case .listening(let w):
            words = w
            status.text = "Listening…"
        case .finishing(let w):
            words = w
            status.text = w.isEmpty ? "Listening…" : ""
        case .polishing(let w):
            words = w
            status.text = "Polishing…"
        case .notice(let line):
            status.text = line
            words = ""
            ribbon.level = 0
        }
        ribbon.calm = {
            if case .listening = mode { return false }
            return true
        }()
        ribbon.alpha = { if case .notice = mode { return 0.35 }; return 1 }()
        let notice: Bool = { if case .notice = mode { return true }; return false }()
        doneButton.isHidden = notice
        pill.isHidden = notice
        if notice { menu?.removeFromSuperview(); menu = nil }
        let canDone: Bool = {
            switch mode { case .listening, .polishing: return true; default: return false }
        }()
        doneButton.isEnabled = canDone
        doneButton.alpha = canDone ? 1 : 0.45
        let hadWords = hasWords
        setWords(words)
        setShimmer({ if case .polishing = mode { return true }; return false }())
        if hadWords != hasWords {
            relayout(animated: window != nil)
        } else {
            setNeedsLayout()
        }
    }

    func setLevel(_ v: Float) {
        if case .listening = mode { ribbon.level = v } else { ribbon.level = 0 }
    }

    private var hasWords: Bool { !shownText.isEmpty }

    private func setWords(_ text: String) {
        guard text != shownText else { return }
        // Where the new words begin: the recognizer revises its last words,
        // so only what differs from before fades in.
        let common = zip(shownText, text).prefix(while: { $0 == $1 }).count
        freshFrom = common
        shownText = text
        renderText(animatedFresh: true)
    }

    private func renderText(animatedFresh: Bool) {
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = textLine
        para.maximumLineHeight = textLine
        para.lineBreakMode = .byWordWrapping
        let font = UIFont.systemFont(ofSize: textSize, weight: .medium)
        let s = NSMutableAttributedString(string: shownText, attributes: [
            .font: font, .foregroundColor: Glass.textPrimary, .paragraphStyle: para,
        ])
        if animatedFresh, freshFrom < shownText.count, !Glass.reduceMotion {
            let start = shownText.index(shownText.startIndex, offsetBy: freshFrom)
            let range = NSRange(start..., in: shownText)
            s.addAttribute(.foregroundColor, value: Glass.textPrimary.withAlphaComponent(0.42), range: range)
            settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                UIView.transition(with: self.textLabel, duration: 0.22, options: .transitionCrossDissolve) {
                    self.freshFrom = self.shownText.count
                    self.renderText(animatedFresh: false)
                }
            }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        }
        textLabel.attributedText = s
        layoutText()
    }

    private var textSize: CGFloat { bounds.height < 230 ? 21 : 24 }
    private var textLine: CGFloat { (textSize * 1.25).rounded() }

    private func setShimmer(_ on: Bool) {
        guard on else {
            textLabel.layer.mask = nil
            shimmer = nil
            textLabel.alpha = 1
            return
        }
        guard shimmer == nil else { return }
        if Glass.reduceMotion { textLabel.alpha = 0.55; return }
        let g = CAGradientLayer()
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        g.colors = [UIColor.black.withAlphaComponent(0.38).cgColor, UIColor.black.cgColor,
                    UIColor.black.withAlphaComponent(0.38).cgColor]
        g.locations = [-0.6, -0.3, 0]
        g.frame = textLabel.bounds.insetBy(dx: -40, dy: 0)
        let a = CABasicAnimation(keyPath: "locations")
        a.fromValue = [-0.6, -0.3, 0]
        a.toValue = [1, 1.3, 1.6]
        a.duration = 1.3
        a.repeatCount = .infinity
        g.add(a, forKey: "shimmer")
        textLabel.layer.mask = g
        shimmer = g
    }

    // MARK: Layout

    private func relayout(animated: Bool) {
        guard animated, !Glass.reduceMotion else { setNeedsLayout(); layoutIfNeeded(); return }
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.layoutSubviews()
        }
    }

    private var topRow: CGRect {
        let top: CGFloat = bounds.height < 230 ? 7 : 10
        return CGRect(x: 0, y: top, width: bounds.width, height: Self.control)
    }

    static let control: CGFloat = 44

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        material.frame = bounds
        contents.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = CGRect(x: -w * 0.1, y: -h * 0.35, width: w * 1.2, height: h * 1.1)
        floorWash.frame = CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)
        edge.frame = CGRect(x: 0, y: 0, width: w, height: Glass.hairlineWidth)
        CATransaction.commit()

        let row = topRow, c = Self.control
        closeButton.frame = CGRect(x: 12, y: row.minY, width: c, height: c)
        doneButton.frame = CGRect(x: w - 12 - c, y: row.minY, width: c, height: c)
        for b in [closeButton, doneButton] { b.layer.cornerRadius = c / 2 }
        let labelW = ceil(pillLabel.intrinsicContentSize.width)
        let pillW = min(w - 2 * (c + 28), labelW + 18 + 8 + 12 + 16)
        let pillH: CGFloat = 40
        pill.frame = CGRect(x: (w - pillW) / 2, y: row.midY - pillH / 2, width: pillW, height: pillH)
        pill.layer.cornerRadius = pillH / 2
        pillLabel.frame = CGRect(x: 18, y: 0, width: pillW - 18 - 30, height: pillH)
        pillChevron.frame = CGRect(x: pillW - 30, y: 0, width: 16, height: pillH)

        let below = row.maxY
        if hasWords {
            let ribbonH: CGFloat = h < 230 ? 28 : 40
            let statusH: CGFloat = 18
            status.font = .systemFont(ofSize: 13, weight: .medium)
            status.frame = CGRect(x: 20, y: h - statusH - 6, width: w - 40, height: statusH)
            ribbon.frame = CGRect(x: 0, y: status.frame.minY - ribbonH - 2, width: w, height: ribbonH)
            // Whole lines only, the newest sitting on the ribbon: a line is
            // never cut in half under the top row.
            let room = max(0, ribbon.frame.minY - below - 10)
            let lines = max(1, floor(room / textLine))
            let clipH = lines * textLine
            textClip.frame = CGRect(x: 22, y: ribbon.frame.minY - 4 - clipH, width: w - 44, height: clipH)
            textClip.alpha = 1
        } else {
            let space = h - below
            let ribbonH = min(96, space * 0.52)
            status.font = .systemFont(ofSize: 16, weight: .medium)
            let statusH: CGFloat = 22
            let block = ribbonH + 4 + statusH
            let top = below + (space - block) / 2 - 4
            ribbon.frame = CGRect(x: 0, y: top, width: w, height: ribbonH)
            status.frame = CGRect(x: 20, y: ribbon.frame.maxY + 4, width: w - 40, height: statusH)
            textClip.frame = CGRect(x: 22, y: below + 8, width: w - 44, height: max(0, top - below - 8))
            textClip.alpha = 0
        }
        layoutText()
        if let menu { layoutMenu(menu) }
    }

    /// The newest line sits at the bottom; older ones rise and fade at the top.
    private func layoutText() {
        let box = textClip.bounds
        guard box.width > 0 else { return }
        let need = ceil(textLabel.sizeThatFits(CGSize(width: box.width, height: .greatestFiniteMagnitude)).height)
        textLabel.frame = CGRect(x: 0, y: box.height - need, width: box.width, height: need)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textFade.frame = box
        textFade.locations = [0, NSNumber(value: Double(min(0.5, textLine * 0.85 / max(1, box.height)))), 1]
        // Fade the top only when lines are hidden behind it.
        textFade.colors = need > box.height + 1
            ? [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
            : [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        shimmer?.frame = textLabel.bounds.insetBy(dx: -40, dy: 0)
        CATransaction.commit()
    }

    private func updatePill() {
        pillLabel.text = style.title
        pill.accessibilityLabel = "Style: \(style.title)"
        menu?.selected = style
        setNeedsLayout()
    }

    // MARK: Style menu

    private func toggleMenu() {
        if let menu {
            closeMenu(menu)
            return
        }
        let m = StyleMenu(selected: style, accent: accent)
        m.onPick = { [weak self] s in
            guard let self else { return }
            self.style = s
            self.onStyle?(s)
            if let menu = self.menu { self.closeMenu(menu) }
        }
        m.onDismiss = { [weak self] in
            guard let self, let menu = self.menu else { return }
            self.closeMenu(menu)
        }
        addSubview(m)
        menu = m
        layoutMenu(m)
        m.card.alpha = 0
        m.card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92).translatedBy(x: 0, y: -8)
        UIView.animate(withDuration: Glass.reduceMotion ? 0.01 : 0.22, delay: 0,
                       usingSpringWithDamping: 0.86, initialSpringVelocity: 0) {
            m.card.alpha = 1
            m.card.transform = .identity
        }
    }

    private func closeMenu(_ m: StyleMenu) {
        menu = nil
        UIView.animate(withDuration: 0.16, animations: {
            m.card.alpha = 0
            m.card.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }, completion: { _ in m.removeFromSuperview() })
    }

    private func layoutMenu(_ m: StyleMenu) {
        m.frame = bounds
        let rows = CGFloat(VoiceLink.Style.allCases.count)
        let top = pill.frame.maxY + 6
        let rowH = min(40, floor((bounds.height - top - 8 - 8) / rows))
        let cardW: CGFloat = 214
        let cardH = rowH * rows + 8
        let y = min(top, bounds.height - cardH - 6)
        m.layoutCard(CGRect(x: (bounds.width - cardW) / 2, y: max(4, y), width: cardW, height: cardH), rowHeight: rowH)
    }
}

/// The pill's menu: the five styles, the current one ticked. A tap outside
/// closes it.
private final class StyleMenu: UIView {
    var onPick: ((VoiceLink.Style) -> Void)?
    var onDismiss: (() -> Void)?
    var selected: VoiceLink.Style { didSet { refreshTicks() } }

    let card = UIView()
    private let cardBlur = UIVisualEffectView(effect: nil)
    private var rows: [(VoiceLink.Style, UIButton, UIImageView, UILabel)] = []
    private var lines: [UIView] = []
    private var accent: UIColor

    init(selected: VoiceLink.Style, accent: UIColor) {
        self.selected = selected
        self.accent = accent
        super.init(frame: .zero)
        // The catcher behind the card: barely there, but touchable.
        backgroundColor = Glass.touchableGrid
        accessibilityIdentifier = "voice:style:menu"
        let catcher = UIButton(type: .custom)
        catcher.frame = .zero
        catcher.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        catcher.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        addSubview(catcher)
        self.catcher = catcher

        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowRadius = 18
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        cardBlur.layer.cornerRadius = 18
        cardBlur.layer.cornerCurve = .continuous
        cardBlur.clipsToBounds = true
        card.addSubview(cardBlur)
        addSubview(card)

        for (i, s) in VoiceLink.Style.allCases.enumerated() {
            let b = UIButton(type: .custom)
            b.accessibilityIdentifier = "voice:style:\(s.rawValue)"
            b.accessibilityLabel = s.title
            let tick = UIImageView(image: UIImage(systemName: "checkmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
            tick.contentMode = .center
            let label = UILabel()
            label.text = s.menuTitle
            label.font = .systemFont(ofSize: 17, weight: .regular)
            b.addSubview(tick)
            b.addSubview(label)
            b.addAction(UIAction { [weak self] _ in self?.onPick?(s) }, for: .touchUpInside)
            b.addAction(UIAction { [weak b] _ in b?.backgroundColor = Glass.fillSoft }, for: [.touchDown, .touchDragEnter])
            b.addAction(UIAction { [weak b] _ in b?.backgroundColor = .clear },
                        for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            card.addSubview(b)
            rows.append((s, b, tick, label))
            if i > 0 {
                let line = UIView()
                card.addSubview(line)
                lines.append(line)
            }
        }
        applyPalette(accent: accent)
        refreshTicks()
    }

    private var catcher: UIButton?

    required init?(coder: NSCoder) { fatalError() }

    func applyPalette(accent: UIColor) {
        self.accent = accent
        let dark = Glass.chromeDark
        cardBlur.effect = Glass.reduceTransparency ? nil
            : UIBlurEffect(style: dark ? .systemThickMaterialDark : .systemThickMaterialLight)
        cardBlur.backgroundColor = Glass.reduceTransparency ? Glass.surfaceCard
            : (dark ? UIColor.white.withAlphaComponent(0.06) : UIColor.white.withAlphaComponent(0.55))
        card.layer.shadowOpacity = dark ? 0.45 : 0.16
        card.layer.borderWidth = Glass.hairlineWidth
        card.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.12)
                                       : UIColor.black.withAlphaComponent(0.06)).cgColor
        for (_, _, tick, label) in rows {
            tick.tintColor = Glass.chromeDark ? Glass.chipAccent : accent
            label.textColor = Glass.textPrimary
        }
        for l in lines { l.backgroundColor = Glass.strokeHairline }
    }

    private func refreshTicks() {
        for (s, b, tick, _) in rows {
            tick.isHidden = s != selected
            b.accessibilityTraits = s == selected ? [.button, .selected] : .button
        }
    }

    func layoutCard(_ frame: CGRect, rowHeight: CGFloat) {
        catcher?.frame = bounds
        card.frame = frame
        cardBlur.frame = card.bounds
        for (i, row) in rows.enumerated() {
            let y = 4 + CGFloat(i) * rowHeight
            row.1.frame = CGRect(x: 0, y: y, width: frame.width, height: rowHeight)
            row.2.frame = CGRect(x: 10, y: 0, width: 26, height: rowHeight)
            row.3.frame = CGRect(x: 40, y: 0, width: frame.width - 52, height: rowHeight)
            if i > 0 {
                lines[i - 1].frame = CGRect(x: 40, y: y, width: frame.width - 40, height: Glass.hairlineWidth)
            }
        }
    }
}

private extension UIColor {
    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
