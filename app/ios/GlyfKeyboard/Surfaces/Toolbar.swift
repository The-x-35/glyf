import UIKit

protocol ToolbarDelegate: AnyObject {
    func toolbarGlyfTapped()
    func toolbarItemTapped(_ id: String)
    func toolbarItemLongPressed(_ id: String)
    /// A held strip icon being dragged: reorder, or off the strip to remove.
    func toolbarItemDragBegan(_ id: String, at windowPoint: CGPoint)
    func toolbarItemDragMoved(to windowPoint: CGPoint)
    func toolbarItemDragEnded(_ id: String, at windowPoint: CGPoint)
    func toolbarSuggestionTapped(_ suggestion: GlyfToolbar.Suggestion)
    /// The strip's close button while a panel is open (website behaviour).
    func toolbarCloseTapped()
    /// The chevron beside a panel title: go back a screen inside the panel.
    func toolbarBackTapped()
    /// The smart chip (a sum just typed, or a saved detail the sentence asks
    /// for) was tapped.
    func toolbarSmartTapped(_ chip: Smart.Chip)
    /// The ✕ on a clipboard chip: this copy is not wanted.
    func toolbarSmartDismissed()
    /// The second action on a chip: Buy beside a price, Send or Buy beside
    /// a copied address.
    func toolbarSmartExtraTapped(_ chip: Smart.Chip)
}

/// §6.2 — the 44pt strip above the keys. When autocorrect candidates show,
/// the toolbar collapses to the Glyf button only and candidates take the
/// strip; tapping the Glyf button restores the tools. Never two strips.
final class GlyfToolbar: UIView {

    weak var delegate: ToolbarDelegate?

    private let glyfButton = UIButton(type: .system)
    private let divider = UIView()
    /// Between the three suggestion slots, like the system bar's.
    private let slotLines = [UIView(), UIView()]
    private let scroll = ControlScrollView()
    private let itemsStack = UIStackView()
    private let candidatesStack = UIStackView()
    private let runsChip = UIButton(type: .system)
    /// The brand key that opens the Glyf menu: the app icon's g and violet
    /// dot on a black key (GlyfMark). Three layers, drawn from outlines.
    private let keycap = CAShapeLayer()
    private let keycapG = CAShapeLayer()
    private let keycapDot = CAShapeLayer()
    /// True while a panel has turned it into a close button.
    private var panelOpen = false
    /// Panel mode (website parity): the strip keeps its place, the brand pill
    /// turns into a close button and the rest becomes "icon + panel name".
    private let panelLabel = UILabel()
    private let panelIcon = UIImageView()
    /// Deeper panel screens keep their way back in the strip, so the panel
    /// itself never spends a row on a chevron.
    private let panelBack = UIButton(type: .system)
    /// A panel's own action at the strip's right edge (↻ on an answer).
    private let panelAction = UIButton(type: .system)
    private var panelActionHandler: (() -> Void)?
    private(set) var panelTitle: String?
    /// Smart chip: one card across the strip, accent key then value.
    private let smartCard = UIControl()
    private let smartKey = UILabel()
    private let smartValue = UILabel()
    /// Clipboard chips lead with the clipboard mark and end with a way out,
    /// the way Gboard's do: the pill IS the paste, so it needs no verb, and
    /// something that appears because you copied must be dismissable.
    private let smartLead = UIImageView()
    private let smartClose = UIButton(type: .system)
    /// A chip's second action (Smart.Chip.extra), as a small button.
    private let smartExtra = UIButton(type: .system)
    /// Between a chip's action and its ✕, so a thumb going for Insert never
    /// lands on the ✕.
    private let smartRule = UIView()
    private(set) var smartChip: Smart.Chip?
    /// How tall a chip stands: its words 9pt clear of the border above and
    /// below (Arpit, 2026-09-30: "text seems too close to border").
    static let chipHeight: CGFloat = 38

    /// Every chip's border and glow (Arpit, 2026-09-30: "a colourful glowy
    /// border so it feels like its magic, all types of strips"). One conic
    /// gradient in Glyf's colours shows through a 1.5pt stroke on the chip
    /// and, behind the chip, through wider and fainter strokes that fade out
    /// 6pt past its edge. It turns once every 4 s while a chip shows; Core
    /// Animation turns it, so nothing is redrawn frame by frame. Layers take
    /// no touches, and the glow sits behind the card, so the chip's taps are
    /// its own. Android's twin.
    private let glowRing = CALayer()
    private let glowSpin = CAGradientLayer()
    private let glowMask = CALayer()
    /// The strokes, under a fade to nothing at the keyboard's top edge: iOS
    /// cuts off anything drawn above it, and a glow cut there is a hard line.
    private let glowBox = CALayer()
    private let glowFade = CAGradientLayer()
    private let glowStrokes = GlyfToolbar.glowBands.map { _ in CAShapeLayer() }
    private let borderRing = CALayer()
    /// The card's face, on the same squircle as its border (Arpit, 2026-09-30:
    /// "white area leaking out of coloured border": the layer's own corner
    /// curve and the border's path parted at the corners). The view keeps
    /// only the faint colour an extension needs to take touches.
    private let cardFill = CAShapeLayer()
    private let borderSpin = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    /// The keyboard is away: nothing turns until it is back.
    private var magicPaused = false

    /// Violet, magenta, pink, amber, cyan and round to violet again.
    private static let magicColors: [CGColor] = [0x7C5CFF, 0xD35CFF, 0xFF5C8A, 0xFFB547, 0x3CC8FF, 0x7C5CFF]
        .map { UIColor(red: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255,
                       blue: CGFloat($0 & 0xFF) / 255, alpha: 1).cgColor }
    /// How far the glow reaches past the chip's edge.
    static let glowSpread: CGFloat = 6
    /// The glow's strokes, innermost first: each reaches a point further out
    /// than the last and is fainter, so together they fall off softly, with
    /// the square of the distance, to nothing at the spread.
    private static let glowBands: [(width: CGFloat, alpha: Float)] = {
        let n = 6
        let step = glowSpread / CGFloat(n)
        let shown = (0..<n).map { k in 0.85 * pow(1 - (Double(k) + 0.5) / Double(n), 2) }
        var bands: [(width: CGFloat, alpha: Float)] = []
        var through = 1.0   // what the wider, outer strokes already leave clear
        for k in stride(from: n - 1, through: 0, by: -1) {
            let alpha = 1 - (1 - shown[k]) / through
            through *= 1 - alpha
            bands.insert((width: step * CGFloat(k + 1) * 2, alpha: Float(alpha)), at: 0)
        }
        return bands
    }()
    /// The glow's strength over the sheet: a dark one needs more to show.
    private static var glowStrength: Float { Glass.chromeDark ? 0.55 : 0.40 }
    /// The strip item currently lifted by a hold, if any.
    private var draggingId: String?
    /// Where a dropped tool would land, drawn as a thin accent bar.
    private let dropMarker = UIView()

    /// item id → SF Symbol
    /// One icon per tool, shared by the strip and the g menu grid.
    static let icons: [String: String] = [
        "search": "magnifyingglass",
        "rewrite": "wand.and.stars",
        "translate": "translate",
        "vault": "person.text.rectangle",
        "clipboard": "doc.on.clipboard",
        // A stack of moving pictures: the board's GIFs, with Stickers beside.
        "gifs": "play.square.stack",
        "ask": "sparkles",
        "dictation": "mic",
        "glyfs": "square.grid.2x2",
        "pay": "creditcard",
        "calendar": "calendar",
        "games": "gamecontroller",
        "settings": "gearshape",
    ]

    /// The tools the strip shows, in its order. The g menu offers the rest:
    /// a tool lives in one place, never both.
    static var shownTools: [String] {
        SettingsStore.current.stripTools.filter { icons[$0] != nil }
    }

    private(set) var showingCandidates = false
    /// User tapped Glyf to restore tools while candidates were up.
    private var userPinnedTools = false

    /// The air at each end of the strip — and, because the row is spaced by
    /// one gap, the air between any two icons follows from it.
    static let margin: CGFloat = 16
    /// How far each icon's tap target reaches past the icon, sideways. Equal
    /// on both sides of every control, so padding a target never moves an
    /// icon off the rhythm.
    static let itemPad: CGFloat = 12
    /// An SF Symbol does not fill the box it is drawn in — measured on this
    /// strip, about three points of air sit inside each one's edge. The brand
    /// key is a filled shape, so it fills its box exactly, and laid out on the
    /// same arithmetic it would sit three points nearer its neighbour than
    /// they are to each other, and three points nearer the screen edge. This
    /// is the air a symbol would have brought with it.
    static let gridSlack: CGFloat = 3

    init() {
        super.init(frame: .zero)

        // Glyf's own key, the way Android's strip starts: black, the icon's
        // g in white and the violet dot, the same in every look. The button
        // around it is the tap target and is painted, not clear, because iOS
        // throws away touches that land on fully transparent pixels in a
        // keyboard extension.
        glyfButton.backgroundColor = Glass.touchableGrid
        glyfButton.layer.cornerCurve = .continuous
        keycapDot.fillColor = Glass.accentPrimary.cgColor
        for layer in [keycap, keycapG, keycapDot] {
            layer.contentsScale = UIScreen.main.scale
            glyfButton.layer.addSublayer(layer)
        }
        applyKeycapRing()
        glyfButton.accessibilityIdentifier = "toolbar:glyf"
        glyfButton.accessibilityLabel = "Glyf"
        glyfButton.addTarget(self, action: #selector(glyfTapped), for: .touchUpInside)
        addSubview(glyfButton)

        divider.backgroundColor = Glass.strokeHairline
        addSubview(divider)

        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        itemsStack.axis = .horizontal
        itemsStack.spacing = 0
        // Equal GAPS, not equal slots. Slots of one width put each icon in the
        // middle of its own, which spaces the centres evenly but leaves the
        // ends of the row to whatever the first and last icons happen to
        // measure — 14pt of margin at one end against 21 at the other. Spacing
        // by the gap between them puts the same air everywhere, the margins
        // included; `layoutSubviews` solves for the gap and hands the stack
        // exactly the width that produces it.
        itemsStack.distribution = .equalSpacing
        scroll.addSubview(itemsStack)

        dropMarker.backgroundColor = Glass.accentPrimary
        dropMarker.layer.cornerRadius = 1.5
        dropMarker.isHidden = true
        addSubview(dropMarker)

        candidatesStack.axis = .horizontal
        candidatesStack.spacing = 4
        candidatesStack.distribution = .fillEqually
        candidatesStack.isHidden = true
        addSubview(candidatesStack)
        // The system bar rules its three slots off with two hairlines, whether
        // or not a slot has a word in it.
        for line in slotLines {
            line.backgroundColor = Glass.strokeHairline
            line.isHidden = true
            addSubview(line)
        }

        runsChip.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        runsChip.setTitleColor(Glass.accentWarning, for: .normal)
        runsChip.backgroundColor = Glass.accentWarning.withAlphaComponent(0.15)
        runsChip.layer.cornerRadius = 8
        runsChip.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        runsChip.isHidden = true
        runsChip.isUserInteractionEnabled = false
        addSubview(runsChip)

        panelIcon.contentMode = .center
        panelIcon.tintColor = Glass.textPrimary
        panelIcon.isHidden = true
        addSubview(panelIcon)
        panelLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        panelLabel.textColor = Glass.textPrimary
        panelLabel.isHidden = true
        addSubview(panelLabel)
        panelBack.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        panelBack.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        panelBack.tintColor = Glass.textPrimary
        panelBack.backgroundColor = Glass.touchableGrid
        panelBack.isHidden = true
        panelBack.accessibilityIdentifier = "toolbar:back"
        panelBack.accessibilityLabel = "Back"
        panelAction.tintColor = Glass.textPrimary
        panelAction.backgroundColor = Glass.touchableGrid
        panelAction.isHidden = true
        panelAction.addAction(UIAction { [weak self] _ in self?.panelActionHandler?() }, for: .touchUpInside)
        addSubview(panelAction)
        panelBack.addAction(UIAction { [weak self] _ in self?.delegate?.toolbarBackTapped() },
                            for: .touchUpInside)
        addSubview(panelBack)

        paintCardFace()
        smartCard.layer.cornerRadius = 12
        smartCard.layer.cornerCurve = .continuous
        // Flat, like every card on the iOS 26 sheet.
        smartCard.layer.shadowOpacity = 0
        smartCard.isHidden = true
        smartCard.accessibilityIdentifier = "strip:smart"
        smartCard.isAccessibilityElement = true
        smartCard.accessibilityTraits = .button
        smartCard.addAction(UIAction { [weak self] _ in
            guard let self, let chip = self.smartChip else { return }
            self.delegate?.toolbarSmartTapped(chip)
        }, for: .touchUpInside)
        smartKey.font = .systemFont(ofSize: 13, weight: .semibold)
        smartKey.textColor = Glass.accentPrimary
        smartCard.addSubview(smartKey)
        smartValue.font = .systemFont(ofSize: 15)
        smartValue.textColor = Glass.textPrimary
        smartValue.lineBreakMode = .byTruncatingTail
        smartCard.addSubview(smartValue)
        smartLead.contentMode = .scaleAspectFit
        smartLead.tintColor = Glass.accentPrimary
        smartLead.isHidden = true
        smartCard.addSubview(smartLead)
        smartClose.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)),
                            for: .normal)
        smartClose.tintColor = Glass.textSecondary
        smartClose.isHidden = true
        smartClose.accessibilityLabel = "Dismiss"
        smartClose.accessibilityIdentifier = "strip:smart:close"
        smartClose.addAction(UIAction { [weak self] _ in
            self?.delegate?.toolbarSmartDismissed()
        }, for: .touchUpInside)
        smartCard.addSubview(smartClose)
        smartExtra.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        smartExtra.setTitleColor(Glass.accentPrimary, for: .normal)
        smartExtra.backgroundColor = Glass.accentPrimary.withAlphaComponent(0.14)
        smartExtra.layer.cornerCurve = .continuous
        smartExtra.isHidden = true
        smartExtra.accessibilityIdentifier = "strip:smart:extra"
        smartExtra.addAction(UIAction { [weak self] _ in
            guard let self, let chip = self.smartChip else { return }
            self.delegate?.toolbarSmartExtraTapped(chip)
        }, for: .touchUpInside)
        smartCard.addSubview(smartExtra)
        smartRule.isUserInteractionEnabled = false
        smartRule.isHidden = true
        smartCard.addSubview(smartRule)
        addSubview(smartCard)
        buildMagic()

        reloadItems()
    }

    /// The glow behind the chip and the border on its edge: each a turning
    /// conic gradient seen through a stroke-shaped mask. The masks stay put
    /// while the gradients turn under them.
    private func buildMagic() {
        for spin in [glowSpin, borderSpin] {
            spin.type = .conic
            spin.colors = Self.magicColors
            spin.startPoint = CGPoint(x: 0.5, y: 0.5)
            spin.endPoint = CGPoint(x: 0.5, y: 0)
        }
        for (band, stroke) in zip(Self.glowBands, glowStrokes) {
            stroke.fillColor = nil
            stroke.strokeColor = UIColor.black.cgColor
            stroke.lineWidth = band.width
            stroke.opacity = band.alpha
            glowBox.addSublayer(stroke)
        }
        glowFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        glowBox.mask = glowFade
        glowMask.addSublayer(glowBox)
        // Drawn once and kept: only the gradient under it moves.
        glowMask.shouldRasterize = true
        glowMask.rasterizationScale = UIScreen.main.scale
        glowRing.mask = glowMask
        glowRing.addSublayer(glowSpin)
        glowRing.isHidden = true
        glowRing.opacity = Self.glowStrength
        // Behind the card: its own face hides the strokes' inner halves, so
        // only the outside glows.
        layer.insertSublayer(glowRing, below: smartCard.layer)
        borderMask.fillColor = nil
        borderMask.strokeColor = UIColor.black.cgColor
        // 2pt, the card's outermost edge (Arpit: "expand border").
        borderMask.lineWidth = 2
        borderRing.mask = borderMask
        borderRing.addSublayer(borderSpin)
        // Over the card's face, under its words.
        smartCard.layer.insertSublayer(borderRing, at: 0)
        smartCard.layer.insertSublayer(cardFill, at: 0)
    }

    /// The border and glow on the chip's own rounded rect.
    /// The card's face colour, resolved for the current appearance (a
    /// layer's CGColor does not follow dark mode by itself).
    private func paintCardFace() {
        smartCard.backgroundColor = Glass.touchableGrid
        cardFill.fillColor = Glass.surfaceCard.resolvedColor(with: traitCollection).cgColor
    }

    private func layoutMagic() {
        let card = smartCard.frame
        let radius = smartCard.layer.cornerRadius
        let spread = Self.glowSpread
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowRing.frame = card.insetBy(dx: -spread, dy: -spread)
        glowMask.frame = glowRing.bounds
        glowBox.frame = glowMask.bounds
        // Clear at the keyboard's top edge, whole 4pt below it.
        let h = max(1, glowBox.bounds.height)
        glowFade.frame = glowBox.bounds
        glowFade.startPoint = CGPoint(x: 0.5, y: -glowRing.frame.minY / h)
        glowFade.endPoint = CGPoint(x: 0.5, y: (4 - glowRing.frame.minY) / h)
        let edge = UIBezierPath(roundedRect: CGRect(x: spread, y: spread, width: card.width, height: card.height),
                                cornerRadius: radius).cgPath
        for stroke in glowStrokes {
            stroke.frame = glowBox.bounds
            stroke.path = edge
        }
        Self.cover(glowRing.bounds, with: glowSpin)
        // The face 1pt in, under the 2pt border, both on one squircle: no
        // white shows outside the colours.
        cardFill.frame = smartCard.bounds
        cardFill.path = UIBezierPath(roundedRect: smartCard.bounds.insetBy(dx: 1, dy: 1),
                                     cornerRadius: max(0, radius - 1)).cgPath
        borderRing.frame = smartCard.bounds
        borderMask.frame = borderRing.bounds
        // Inset by half the line, so the whole 2pt lies on the card.
        borderMask.path = UIBezierPath(roundedRect: smartCard.bounds.insetBy(dx: 1, dy: 1),
                                       cornerRadius: max(0, radius - 1)).cgPath
        Self.cover(borderRing.bounds, with: borderSpin)
        CATransaction.commit()
    }

    /// A square over the whole diagonal, so it covers the rect at any angle
    /// it turns to. Bounds and position, not frame: it may be mid-turn. Both
    /// gradients share the chip's centre, so their colours line up.
    private static func cover(_ rect: CGRect, with spin: CAGradientLayer) {
        let side = ceil(hypot(rect.width, rect.height))
        spin.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        spin.position = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// With the chip: a chip that has just appeared fades its glow in, and
    /// the colours turn only while one shows. Reduce Motion keeps them still.
    private func setMagic(showing: Bool, fresh: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowRing.isHidden = !showing
        glowRing.opacity = Self.glowStrength
        CATransaction.commit()
        guard showing else { return stopMagic() }
        if fresh, !Glass.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = Self.glowStrength
            fade.duration = 0.25
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            glowRing.add(fade, forKey: "fade")
        }
        startMagic()
    }

    private func startMagic() {
        guard !magicPaused, !Glass.reduceMotion, !smartCard.isHidden,
              glowSpin.animation(forKey: "turn") == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = CGFloat.pi * 2
        turn.duration = 4
        turn.repeatCount = .infinity
        // A slow turn looks as smooth at 30 frames a second as at 120.
        turn.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        // Added in one go, so the border and the glow turn as one.
        glowSpin.add(turn, forKey: "turn")
        borderSpin.add(turn, forKey: "turn")
    }

    private func stopMagic() {
        glowSpin.removeAnimation(forKey: "turn")
        borderSpin.removeAnimation(forKey: "turn")
    }

    /// The keyboard went away, or came back: the colours turn only on screen.
    func setMagicRunning(_ running: Bool) {
        magicPaused = !running
        if running { startMagic() } else { stopMagic() }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The app icon on a light sheet, its dark twin on a dark one.
    private func applyKeycapRing() {
        let dark = Glass.chromeDark
        keycap.fillColor = GlyfMark.face(dark: dark).cgColor
        keycapG.fillColor = GlyfMark.letterColor(dark: dark).cgColor
        keycap.strokeColor = GlyfMark.ring(dark: dark)?.cgColor
        keycap.lineWidth = dark ? 1 : 0
    }

    /// Re-skins after an appearance flip (items re-tint via reloadItems;
    /// the brand keycap turns to the icon's twin for the sheet).
    func applyPalette() {
        divider.backgroundColor = Glass.strokeHairline
        panelIcon.tintColor = Glass.textPrimary
        panelLabel.textColor = Glass.textPrimary
        panelBack.tintColor = Glass.textPrimary
        paintCardFace()
        smartValue.textColor = Glass.textPrimary
        paintChip()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowRing.opacity = Self.glowStrength
        CATransaction.commit()
        // Suggestion words are drawn with the ink of the moment they were
        // made; redraw them or they stay dark on a sheet that just went dark.
        let words = suggestions
        suggestions = []
        if !words.isEmpty { showSuggestions(words) }
        applyKeycapRing()
        if !panelOpen { glyfButton.backgroundColor = Glass.touchableGrid }
        reloadItems()
    }

    /// The chip's frame while it is showing, for the tour's ring.
    var smartFrame: CGRect? { smartCard.isHidden ? nil : smartCard.frame }
    /// Whether the chip showing is the clipboard's (its ✕ forgets the copy).
    var smartIsPaste: Bool { !smartCard.isHidden && smartChip?.copiedText != nil }
    var glyfFrame: CGRect { glyfButton.frame }

    /// Index a tool would take if dropped at this point (strip coordinates),
    /// and the marker that shows it. Nil hides the marker.
    func showDropMarker(at point: CGPoint?) {
        guard let point, !itemsStack.arrangedSubviews.isEmpty else {
            dropMarker.isHidden = true
            return
        }
        let idx = dropIndex(for: point)
        let views = itemsStack.arrangedSubviews
        let x: CGFloat
        if idx >= views.count {
            x = itemsStack.convert(views[views.count - 1].frame, to: self).maxX + 2
        } else {
            x = itemsStack.convert(views[idx].frame, to: self).minX - 4
        }
        dropMarker.frame = CGRect(x: x, y: 8, width: 3, height: bounds.height - 16)
        dropMarker.isHidden = false
        bringSubviewToFront(dropMarker)
    }

    func dropIndex(for point: CGPoint) -> Int {
        let views = itemsStack.arrangedSubviews
        for (i, v) in views.enumerated() {
            let f = itemsStack.convert(v.frame, to: self)
            if point.x < f.midX { return i }
        }
        return views.count
    }

    func reloadItems() {
        itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for id in Self.shownTools {
            guard let symbol = Self.icons[id] else { continue }
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .regular),
                                              forImageIn: .normal)
            b.tintColor = Glass.textPrimary.withAlphaComponent(0.78)
            // The icon is the thing you see; this is the thing you hit. Same
            // on both sides, so padding a target never shifts an icon off the
            // rhythm the gaps set.
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: Self.itemPad,
                                               bottom: 0, right: Self.itemPad)
            b.layer.cornerRadius = 10
            b.layer.cornerCurve = .continuous
            // Touchable everywhere in its box, not just on the icon's lines: a
            // keyboard drops touches on fully clear pixels (Glass.touchableGrid).
            b.backgroundColor = Glass.touchableGrid
            b.accessibilityIdentifier = "toolbar:\(id)"
            b.accessibilityLabel = id
            b.addAction(UIAction { [weak self] _ in
                self?.delegate?.toolbarItemTapped(id)
            }, for: .touchUpInside)
            let long = UILongPressGestureRecognizer(target: self, action: #selector(itemLong(_:)))
            long.minimumPressDuration = 0.32
            long.allowableMovement = 10   // moving first is a scroll, not a pick-up
            b.addGestureRecognizer(long)
            itemsStack.addArrangedSubview(b)
        }
        setNeedsLayout()
    }

    /// Hold an icon and it lifts: slide sideways to reorder, or drag it off
    /// the strip to put it away. (Gboard's gesture, on Glyf's strip.)
    @objc private func itemLong(_ g: UILongPressGestureRecognizer) {
        guard let b = g.view as? UIButton,
              let raw = b.accessibilityIdentifier?.split(separator: ":").last
        else { return }
        let id = String(raw)
        let point = g.location(in: self)
        switch g.state {
        case .began:
            draggingId = id
            b.alpha = 0.25
            delegate?.toolbarItemDragBegan(id, at: convert(point, to: window))
        case .changed:
            delegate?.toolbarItemDragMoved(to: convert(point, to: window))
        case .ended, .cancelled, .failed:
            b.alpha = 1
            draggingId = nil
            delegate?.toolbarItemDragEnded(id, at: convert(point, to: window))
        default:
            break
        }
    }

    /// Panel open: title + icon in the strip, brand pill becomes a close
    /// button. `nil` restores the tools.
    /// - Parameter keepTools: the g menu's own screen leaves the tools on the
    ///   strip, because that is what you drag a tile onto. Deeper panels take
    ///   the strip for their name.
    func showPanelHeader(icon: String?, title: String?, canGoBack: Bool = false,
                         keepTools: Bool = false) {
        panelTitle = title
        panelBack.isHidden = !(title != nil && canGoBack)
        let open = title != nil
        let hideTools = open && !keepTools
        panelLabel.text = title
        panelLabel.isHidden = !open || keepTools
        panelIcon.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        panelIcon.image = icon.flatMap { UIImage(systemName: $0) }
        panelIcon.isHidden = !open || keepTools || panelIcon.image == nil
        if open {
            scroll.isHidden = hideTools
            candidatesStack.isHidden = true
            // The lines between suggestion slots go with the suggestions:
            // a panel's title never has slots.
            for line in slotLines { line.isHidden = true }
            runsChip.isHidden = true
            divider.isHidden = hideTools || Glass.solidLook
        } else {
            // Back to exactly one of tools or suggestions. Setting both here
            // (tools on, suggestions on) drew words over the icons after
            // the emoji page closed.
            setPanelAction(symbol: nil, label: nil, handler: nil)
            applyCandidatesVisibility(toolsVisible: !showingCandidates || userPinnedTools)
        }
        if open {
            // The ✕ stands in the key's slot with no ground of its own, drawn
            // at the size the tools beside it are drawn. It used to sit on a soft fill, and because the
            // slot is a tap target — wider than it is tall — that fill read
            // as a squat pill parked at the end of an otherwise clean row.
            glyfButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            glyfButton.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 21, weight: .regular), forImageIn: .normal)
            glyfButton.tintColor = Glass.textPrimary
            glyfButton.backgroundColor = Glass.touchableGrid
            glyfButton.accessibilityIdentifier = "toolbar:close"
            glyfButton.accessibilityLabel = "Close"
            for layer in [keycap, keycapG, keycapDot] { layer.isHidden = true }
        } else {
            glyfButton.setImage(nil, for: .normal)
            // Back to no ground of its own, but still painted: a clear
            // button would stop taking touches at all (see init).
            glyfButton.backgroundColor = Glass.touchableGrid
            glyfButton.accessibilityIdentifier = "toolbar:glyf"
            glyfButton.accessibilityLabel = "Glyf"
            for layer in [keycap, keycapG, keycapDot] { layer.isHidden = false }
        }
        panelOpen = open
        setNeedsLayout()
    }

    /// The open panel's action at the strip's right edge, or nil for none.
    func setPanelAction(symbol: String?, label: String?, handler: (() -> Void)?) {
        panelActionHandler = handler
        if let symbol {
            panelAction.setImage(UIImage(systemName: symbol), for: .normal)
            panelAction.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold), forImageIn: .normal)
        }
        panelAction.accessibilityLabel = label
        panelAction.accessibilityIdentifier = "toolbar:panelAction"
        panelAction.isHidden = handler == nil || panelTitle == nil
        setNeedsLayout()
    }

    /// The chip's own purple, lighter than the accent, and its quiet greys.
    private func paintChip() {
        let accent = Glass.chipAccent
        smartKey.textColor = accent
        smartLead.tintColor = accent
        smartExtra.setTitleColor(accent, for: .normal)
        smartExtra.backgroundColor = accent.withAlphaComponent(0.14)
        smartClose.tintColor = Glass.textSecondary
        smartRule.backgroundColor = Glass.textSecondary.withAlphaComponent(0.35)
    }

    /// One chip across the strip, or nil to go back to tools and suggestions.
    func showSmart(_ chip: Smart.Chip?) {
        smartChip = chip
        let wasShowing = !smartCard.isHidden
        smartCard.isHidden = chip == nil || panelTitle != nil
        setMagic(showing: !smartCard.isHidden, fresh: !wasShowing)
        if let chip {
            // A copy (plain, or an address with Send or Buy beside it) is the
            // clipboard pill: the tap pastes it.
            let isPaste = chip.copiedText != nil
            let isEvent: Bool = {
                switch chip { case .event, .booking: return true; default: return false }
            }()
            smartLead.isHidden = !isPaste && !isEvent
            // Every chip can be put away, from the same place at its end.
            smartClose.isHidden = false
            smartLead.image = isPaste || isEvent
                ? UIImage(systemName: isPaste ? "doc.on.clipboard" : "calendar",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
                : nil
            // A clipboard pill is the paste: naming the action twice, once as
            // a word and once as the tap, is what made it read as clutter.
            smartKey.isHidden = isPaste
            // Content on the left, the action on the right edge.
            if let verb = chip.verb {
                smartKey.attributedText = nil
                smartKey.text = verb
            } else {
                let spark = NSTextAttachment(image: UIImage(systemName: "sparkles",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))?
                    .withTintColor(Glass.chipAccent, renderingMode: .alwaysOriginal) ?? UIImage())
                smartKey.attributedText = NSAttributedString(attachment: spark)
            }
            smartExtra.isHidden = chip.extra == nil
            smartExtra.setTitle(chip.extra, for: .normal)
            if let label = chip.label {
                let line = NSMutableAttributedString(string: label + "  ", attributes: [
                    .foregroundColor: Glass.textSecondary,
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium)])
                line.append(NSAttributedString(string: chip.value, attributes: [
                    .foregroundColor: Glass.textPrimary, .font: UIFont.systemFont(ofSize: 15)]))
                smartValue.attributedText = line
            } else {
                smartValue.attributedText = nil
                smartValue.font = .systemFont(ofSize: 15)
                smartValue.textColor = Glass.textPrimary
                smartValue.text = chip.value
            }
            paintCardFace()
            smartCard.accessibilityLabel = "\(chip.key) \(chip.value)"
            // The ✕ leads every chip, so the hairline after it always shows.
            smartRule.isHidden = false
            paintChip()
        }
        if smartCard.isHidden {
            // No chip: back to whichever of tools / suggestions the strip was
            // showing. Never both — they share the same space and used to
            // draw over each other when a chip went away.
            applyCandidatesVisibility(toolsVisible: !showingCandidates || userPinnedTools)
        } else {
            scroll.isHidden = true
            candidatesStack.isHidden = true
            for line in slotLines { line.isHidden = true }
            divider.isHidden = true
            runsChip.isHidden = true
        }
        setNeedsLayout()
    }

    @objc private func glyfTapped() {
        if panelTitle != nil {
            delegate?.toolbarCloseTapped()
            return
        }
        if showingCandidates && !candidatesStack.isHidden {
            // Restore tools without opening the shell (§6.2).
            userPinnedTools = true
            applyCandidatesVisibility(toolsVisible: true)
        } else {
            delegate?.toolbarGlyfTapped()
        }
    }

    // MARK: Suggestions (§6.1: three slots — what you typed, what space
    // inserts, the next best — or the undo for a correction just made)

    struct Suggestion: Equatable {
        enum Kind: Equatable {
            /// Exactly what was typed; tapping keeps it.
            case literal
            /// What the space bar is about to insert.
            case correction
            case word
            /// Put back what was typed before the last correction.
            case undo
        }
        let text: String
        let kind: Kind
    }

    private(set) var suggestions: [Suggestion] = []

    func showSuggestions(_ items: [Suggestion]) {
        let items = Array(items.prefix(3))
        if items == suggestions, showingCandidates == !items.isEmpty {
            // Same words, but something else may have moved the strip since.
            applyCandidatesVisibility(toolsVisible: items.isEmpty || userPinnedTools)
            return
        }
        suggestions = items
        candidatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, item) in items.enumerated() {
            let b = suggestionButton(item)
            b.accessibilityIdentifier = "suggest:\(i)"
            b.addAction(UIAction { [weak self] _ in self?.delegate?.toolbarSuggestionTapped(item) },
                        for: .touchUpInside)
            candidatesStack.addArrangedSubview(b)
        }
        // Always three slots, so one word sits in its slot and the lines
        // between slots stay where they are (the system bar's way).
        while !items.isEmpty, candidatesStack.arrangedSubviews.count < 3 {
            candidatesStack.addArrangedSubview(UIView())
        }
        showingCandidates = !items.isEmpty
        if items.isEmpty { userPinnedTools = false }
        applyCandidatesVisibility(toolsVisible: items.isEmpty || userPinnedTools)
    }

    private func applyCandidatesVisibility(toolsVisible: Bool) {
        guard panelTitle == nil else { return }   // a panel owns the strip
        scroll.isHidden = !toolsVisible
        divider.isHidden = !toolsVisible || Glass.solidLook
        candidatesStack.isHidden = toolsVisible || !showingCandidates
        for line in slotLines { line.isHidden = candidatesStack.isHidden }
        // The website's strip is six tools and the g pill, nothing else; the
        // run counter lives in the g menu's Account screen.
        runsChip.isHidden = runsRemaining == nil || !toolsVisible || Glass.solidLook
    }

    private func suggestionButton(_ item: Suggestion) -> UIButton {
        let b = UIButton(type: .system)
        let title: String
        switch item.kind {
        case .literal: title = "“\(item.text)”"
        case .undo: title = "↩ \(item.text)"
        case .correction, .word: title = item.text
        }
        b.setTitle(title, for: .normal)
        let emphasized = item.kind == .correction
        // 17pt: the system bar's "The" stands 12pt tall, which is this size.
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: emphasized ? .semibold : .regular)
        b.setTitleColor(item.kind == .literal ? Glass.textSecondary : Glass.textPrimary, for: .normal)
        // The website marks the best candidate by weight alone, no pill —
        // but never `.clear`. A keyboard extension throws away touches that
        // land on transparent pixels, so a clear slot was only tappable on
        // the letters themselves: you had to hit the word, not its slot,
        // which is why a suggestion took two or three tries to take.
        b.backgroundColor = (emphasized && !Glass.solidLook)
            ? Glass.fillBar : Glass.touchableGrid
        b.layer.cornerRadius = 8
        b.layer.cornerCurve = .continuous
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.accessibilityLabel = item.text
        return b
    }

    // MARK: Runs chip (§6.2 — only when the free cap is low)

    private var runsRemaining: Int?

    func setRunsRemaining(_ n: Int?) {
        runsRemaining = n
        if let n, n <= 8 {
            runsChip.setTitle("\(n) left", for: .normal)
            // The same rule as applyCandidatesVisibility: never in the
            // website's look, where the strip is the tools and the g pill.
            runsChip.isHidden = (showingCandidates && !userPinnedTools) || Glass.solidLook
        } else {
            runsChip.isHidden = true
        }
        setNeedsLayout()
    }

    /// The apps grid is drawn at icon size, which is small for a thumb. The
    /// strip's margin around it belongs to nothing else, so a near-miss that
    /// would otherwise land on the bare toolbar goes to the button instead.
    /// Only points nothing else claimed are taken, so the divider and the
    /// scrolling tools keep their own.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit == nil || hit === self,
           glyfButton.frame.insetBy(dx: -6, dy: -6).contains(point) {
            return glyfButton
        }
        return hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Website strip: the logo at the left, then the tools across the rest.
        // Below the band we had to draw ourselves (nothing on iOS 26, which
        // supplies its own): everything measures off the content box.
        let band = Glass.stripBand
        let h = bounds.height - band
        let mid = band + h / 2 - Glass.stripLift
        // The key is 41 by 30, the site's pill a little taller. The lifted
        // middle leaves only 13pt above it on iOS 26, which clips anything
        // drawn above the strip, so a key this tall stands on the strip's
        // top edge instead: its centre two points under the icons'.
        let target = Glass.stripBox(height: 38, mid: mid)
        let keyH: CGFloat = 30
        let keyMid = max(mid, keyH / 2)
        let keyW = GlyfMark.keycapWidth(height: keyH)
        // The button carries its own target: the key plus the tools' padding
        // sideways, plus the air a symbol keeps inside its box, so the key
        // sits on the same rhythm they do.
        let padX = Self.itemPad + Self.gridSlack
        let inkX = Self.margin + Self.gridSlack
        glyfButton.frame = CGRect(x: inkX - padX, y: target.y,
                                  width: keyW + padX * 2, height: target.height)
        glyfButton.layer.cornerRadius = 9
        let cap = GlyfMark.Keycap(height: keyH, x: padX, midY: keyMid - target.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [keycap, keycapG, keycapDot] { layer.frame = glyfButton.bounds }
        keycap.path = UIBezierPath(roundedRect: cap.key, cornerRadius: cap.radius).cgPath
        keycapG.path = GlyfMark.gPath(in: cap.letter)
        keycapDot.path = CGPath(ellipseIn: cap.dot, transform: nil)
        CATransaction.commit()
        let markRight = inkX + keyW
        // Whatever ends the row on the right ends as far in as the key starts
        // on the left, so the strip sits centred over the keys.
        let rightInk = bounds.width - inkX
        divider.isHidden = Glass.solidLook
        let chipW: CGFloat = runsChip.isHidden ? 0 : 64
        if !runsChip.isHidden {
            runsChip.frame = CGRect(x: rightInk - chipW, y: 11,
                                    width: chipW, height: h - 22)
        }
        let left = markRight + (Glass.solidLook ? 11 : 17)
        if !smartCard.isHidden {
            // Room for the glow inside the strip: iOS cuts off anything drawn
            // above the keyboard's top edge, and a glow cut there reads as a
            // hard line. So the chip is as tall as the 44pt strip allows with
            // the glow spent before either edge (34pt), up to chipHeight.
            let room = Self.glowSpread - 1
            let cardH = min(Self.chipHeight, bounds.height - room * 2)
            let cardY = min(max(room, mid - cardH / 2), bounds.height - room - cardH)
            smartCard.frame = CGRect(x: left, y: cardY,
                                     width: max(0, rightInk - left), height: cardH)
            let lead = !smartLead.isHidden
            // Gboard's clipboard suggestion is a pill; the rest stay cards.
            smartCard.layer.cornerRadius = lead ? cardH / 2 : 12
            let w = smartCard.bounds.width
            // Arpit, 2026-09-30: "add more inner padding, text seems too close
            // to border", a ✕ on every chip, then "no cross on right looks
            // bad, insert should be the default action". So the ✕ leads (as
            // on Safari's Smart App Banner: close at the far left, the action
            // at the far right): its glyph 14pt inside the stroke, a hairline
            // 10pt either side, then the text; the verb ends 16pt inside the
            // right edge, and a tap anywhere but the ✕ does it.
            let c: CGFloat = 32, glyph: CGFloat = 11
            smartClose.frame = CGRect(x: 14 + glyph / 2 - c / 2, y: (cardH - c) / 2, width: c, height: c)
            let ruleX = 14 + glyph + 10
            smartRule.frame = CGRect(x: ruleX, y: (cardH * 0.28).rounded(), width: 0.5, height: (cardH * 0.44).rounded())
            var right = w - 16
            if !smartExtra.isHidden {
                let extraH: CGFloat = min(28, cardH - 8)
                let extraW = smartExtra.intrinsicContentSize.width + 22
                smartExtra.frame = CGRect(x: w - 12 - extraW, y: (cardH - extraH) / 2,
                                          width: extraW, height: extraH)
                smartExtra.layer.cornerRadius = extraH / 2
                right = smartExtra.frame.minX - 10
            }
            let keyW = smartKey.isHidden ? 0 : min(smartKey.intrinsicContentSize.width, 120)
            smartKey.frame = CGRect(x: right - keyW, y: 0, width: keyW, height: cardH)
            if keyW > 0 { right = smartKey.frame.minX - 10 }
            let contentX = ruleX + 0.5 + 10
            if lead { smartLead.frame = CGRect(x: contentX, y: (cardH - 16) / 2, width: 16, height: 16) }
            let textX = lead ? contentX + 16 + 8 : contentX
            smartValue.frame = CGRect(x: textX, y: 0, width: max(0, right - textX), height: cardH)
            layoutMagic()
        }
        if panelTitle != nil {
            var x = left
            let row = Glass.stripBox(height: h, mid: mid)
            if !panelBack.isHidden {
                panelBack.frame = CGRect(x: x - 4, y: row.y, width: 30, height: row.height)
                x += 28
            }
            panelIcon.frame = CGRect(x: x, y: mid - 12, width: 24, height: 24)
            let textX = panelIcon.isHidden ? x : x + 30
            let actionW: CGFloat = panelAction.isHidden ? 0 : 44
            let action = Glass.stripBox(height: 34, mid: mid)
            panelAction.frame = CGRect(x: bounds.width - actionW - 4, y: action.y,
                                       width: actionW, height: action.height)
            panelLabel.frame = CGRect(x: textX, y: row.y,
                                      width: bounds.width - textX - 10 - actionW, height: row.height)
        }
        // One gap for the whole row, margins included.
        //
        // The grid and the tools are one set of controls, so the air between
        // any two of them is the same, and the air at each end is that margin.
        // Everything else falls out of it: the icons keep whatever widths SF
        // Symbols gives them, the stack gets exactly the width that spaces
        // them by `gap`, and the row lands on the right margin on its own.
        //
        //     width - 2 × (margin - itemPad) = every frame + n gaps
        //
        // The pad cancels: each target is padded the same on both sides, so
        // the frames grow inward and the icons stay on the gap's rhythm.
        // With the runs pill showing, the last tool keeps 13 points from it.
        let end = bounds.width - (runsChip.isHidden ? 0 : chipW + 13) - Self.margin + Self.itemPad
        let x0 = glyfButton.frame.minX
        let n = CGFloat(max(itemsStack.arrangedSubviews.count, 1))
        let tools = itemsStack.arrangedSubviews.reduce(CGFloat(0)) {
            $0 + $1.intrinsicContentSize.width
        }
        let gap = max(4, (end - x0 - glyfButton.frame.width - tools) / n)
        let toolsLeft = x0 + glyfButton.frame.width + gap
        // Halfway between the grid and the first tool, when a look draws it.
        divider.frame = CGRect(x: ((markRight + toolsLeft) / 2).rounded(), y: 10,
                               width: Glass.hairlineWidth * 2, height: h - 20)
        // The tools live INSIDE this scroll view, which clips them, so the
        // band has to move the scroll itself — offsetting only the stack
        // pushes the icons out through its bottom edge (that is what ate the
        // magnifier's handle and the mic's stand on iOS 18).
        let toolsW = max(0, end - toolsLeft)
        scroll.frame = CGRect(x: toolsLeft, y: band, width: toolsW, height: h)
        itemsStack.spacing = 0
        // …and inside it the stack is band-relative: the strip's own centring.
        let items = Glass.stripBox(height: min(34, h - 4), mid: mid - band)
        itemsStack.frame = CGRect(x: 0, y: items.y, width: toolsW, height: items.height)
        scroll.contentSize = CGSize(width: toolsW, height: h)
        candidatesStack.frame = CGRect(x: left, y: mid - (h - 12) / 2,
                                       width: bounds.width - left - 8, height: h - 12)
        // A hairline on each boundary between the three equal slots, drawn
        // at the system bar's height: a little over half the strip.
        let slotW = (candidatesStack.bounds.width - 2 * candidatesStack.spacing) / 3
        let lineH = (h * 0.56).rounded()
        for (i, line) in slotLines.enumerated() {
            let x = candidatesStack.frame.minX + slotW * CGFloat(i + 1)
                + candidatesStack.spacing * CGFloat(i) + candidatesStack.spacing / 2
            line.frame = CGRect(x: x.rounded() - 0.5, y: mid - lineH / 2, width: 1, height: lineH)
        }
    }
}
