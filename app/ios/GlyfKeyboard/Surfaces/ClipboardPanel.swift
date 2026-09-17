import UIKit

protocol ClipboardPanelDelegate: AnyObject {
    func clipboardPanelClosed()
    func clipboardPanelPaste(_ text: String)
    /// History on/off changed (the toggle in the header).
    func clipboardPanelChanged()
}

/// The clipboard, laid out the way Gboard lays it out — which is the standard
/// people already know: a header with back, an on/off toggle and edit, then
/// PINNED and RECENT as two columns of cards. Tap a card to paste it. Hold one
/// and the rest dim while a menu offers Paste, Pin and Delete.
///
/// Identical on Android (ClipboardPanel in GlyfIME.kt); only sizes follow each
/// platform's own keyboard.
final class ClipboardPanel: UIView, UIGestureRecognizerDelegate {

    weak var delegate: ClipboardPanelDelegate?

    private let header = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let toggleButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private let scrim = UIControl()
    private var menu: UIView?

    private var items: [ClipItem] = []
    private var editing = false
    /// Width the cards were last laid out for; any change lays them out again.
    /// (UIScrollView keeps private indicator subviews, so "no subviews" can
    /// never be the signal.)
    private var laidOutWidth: CGFloat = -1
    private var cardViews: [(card: UIControl, item: ClipItem)] = []

    private enum M {
        static let headerH: CGFloat = 52
        static let side: CGFloat = 12
        static let gap: CGFloat = 10
        static let cardPad: CGFloat = 14
        static let radius: CGFloat = 12
        static let sectionH: CGFloat = 30
        static let textSize: CGFloat = 15
        static let maxLines = 4
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.solidBackdrop

        backButton.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        backButton.setPreferredSymbolConfiguration(
            .init(pointSize: 18, weight: .medium), forImageIn: .normal)
        backButton.tintColor = Glass.textPrimary
        backButton.backgroundColor = Glass.surfaceCard
        backButton.accessibilityIdentifier = "clip:back"
        backButton.addAction(UIAction { [weak self] _ in self?.delegate?.clipboardPanelClosed() },
                             for: .touchUpInside)
        header.addSubview(backButton)

        titleLabel.text = "Clipboard"
        titleLabel.font = .systemFont(ofSize: 22, weight: .medium)
        titleLabel.textColor = Glass.textPrimary
        header.addSubview(titleLabel)

        toggleButton.tintColor = Glass.textPrimary
        toggleButton.backgroundColor = Glass.surfaceCard
        toggleButton.accessibilityIdentifier = "clip:toggle"
        toggleButton.addAction(UIAction { [weak self] _ in self?.toggleHistory() },
                               for: .touchUpInside)
        header.addSubview(toggleButton)

        editButton.setImage(UIImage(systemName: "pencil"), for: .normal)
        editButton.setPreferredSymbolConfiguration(
            .init(pointSize: 17, weight: .medium), forImageIn: .normal)
        editButton.tintColor = Glass.textPrimary
        editButton.backgroundColor = Glass.surfaceCard
        editButton.accessibilityIdentifier = "clip:edit"
        editButton.addAction(UIAction { [weak self] _ in self?.toggleEditing() },
                             for: .touchUpInside)
        header.addSubview(editButton)
        addSubview(header)

        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        addSubview(scroll)

        scrim.backgroundColor = Glass.solidBackdrop.withAlphaComponent(0.72)
        scrim.isHidden = true
        scrim.addAction(UIAction { [weak self] _ in self?.dismissMenu() }, for: .touchUpInside)
        addSubview(scrim)

        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Data

    func reload() {
        items = ClipboardStore.load()
        refreshToggle()
        rebuildCards()
    }

    private var historyOn: Bool { SettingsStore.current.clipboardHistory != false }

    private func refreshToggle() {
        let symbol = historyOn ? "switch.2" : "switch.2"
        toggleButton.setImage(UIImage(systemName: symbol), for: .normal)
        toggleButton.setPreferredSymbolConfiguration(
            .init(pointSize: 17, weight: .medium), forImageIn: .normal)
        toggleButton.alpha = historyOn ? 1 : 0.45
        toggleButton.accessibilityLabel = historyOn ? "Clipboard on" : "Clipboard off"
    }

    private func toggleHistory() {
        let on = !historyOn
        SettingsStore.update { $0.clipboardHistory = on }
        refreshToggle()
        rebuildCards()
        delegate?.clipboardPanelChanged()
    }

    private func toggleEditing() {
        editing.toggle()
        editButton.backgroundColor = editing ? Glass.accentPrimary : Glass.surfaceCard
        editButton.tintColor = editing ? .white : Glass.textPrimary
        rebuildCards()
    }

    // MARK: Cards

    private func rebuildCards() {
        laidOutWidth = -1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        header.frame = CGRect(x: 0, y: 0, width: w, height: M.headerH)
        let b: CGFloat = 38
        backButton.frame = CGRect(x: M.side, y: (M.headerH - b) / 2, width: b, height: b)
        backButton.layer.cornerRadius = b / 2
        editButton.frame = CGRect(x: w - M.side - b, y: (M.headerH - b) / 2, width: b, height: b)
        editButton.layer.cornerRadius = b / 2
        toggleButton.frame = CGRect(x: editButton.frame.minX - 8 - b,
                                    y: (M.headerH - b) / 2, width: b, height: b)
        toggleButton.layer.cornerRadius = b / 2
        titleLabel.frame = CGRect(x: backButton.frame.maxX + 14, y: 0,
                                  width: toggleButton.frame.minX - backButton.frame.maxX - 20,
                                  height: M.headerH)
        scroll.frame = CGRect(x: 0, y: M.headerH, width: w, height: bounds.height - M.headerH)
        scrim.frame = bounds
        if scroll.bounds.width > 0, laidOutWidth != scroll.bounds.width {
            laidOutWidth = scroll.bounds.width
            for v in cardViews.map(\.card) { v.removeFromSuperview() }
            cardViews.removeAll()
            scroll.subviews.filter { $0.tag == Self.contentTag }.forEach { $0.removeFromSuperview() }
            layoutCards()
        }
    }

    /// Marks everything this panel adds to the scroll view.
    private static let contentTag = 7_301

    private func layoutCards() {
        let w = scroll.bounds.width
        let colW = (w - M.side * 2 - M.gap) / 2
        var y: CGFloat = 4

        if !historyOn {
            y = addTip(at: y, width: w - M.side * 2,
                       icon: "switch.2",
                       text: "Clipboard is off. Turn it on to keep what you copy.")
            scroll.contentSize = CGSize(width: w, height: y + 12)
            return
        }

        let pinned = items.filter(\.pinned)
        let recent = items.filter { !$0.pinned }
        if !pinned.isEmpty {
            y = addSection("PINNED", at: y)
            y = addGrid(pinned, at: y, colW: colW)
        }
        if !recent.isEmpty {
            y = addSection("RECENT", at: y)
            y = addGrid(recent, at: y, colW: colW)
        }
        if items.isEmpty {
            y = addSection("TIPS", at: y)
            y = addTip(at: y, width: w - M.side * 2, icon: "doc.on.clipboard",
                       text: "Anything you copy shows up here. Tap a clip to paste it, hold it to pin.")
        }
        scroll.contentSize = CGSize(width: w, height: y + 12)
    }

    private func addSection(_ title: String, at y: CGFloat) -> CGFloat {
        let label = UILabel()
        label.attributedText = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 12.5, weight: .medium),
            .kern: 0.6,
            .foregroundColor: Glass.textSecondary,
        ])
        label.frame = CGRect(x: M.side + 4, y: y, width: 200, height: M.sectionH)
        label.tag = Self.contentTag
        scroll.addSubview(label)
        return y + M.sectionH
    }

    /// Two columns, each card as tall as its text needs (Gboard's masonry):
    /// every card lands in whichever column is shorter.
    private func addGrid(_ clips: [ClipItem], at top: CGFloat, colW: CGFloat) -> CGFloat {
        var colY: [CGFloat] = [top, top]
        let font = UIFont.systemFont(ofSize: M.textSize)
        for item in clips {
            let flat = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let textW = colW - M.cardPad * 2
            let lineH = font.lineHeight
            let bounding = (flat as NSString).boundingRect(
                with: CGSize(width: textW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil)
            let textH = min(ceil(bounding.height), lineH * CGFloat(M.maxLines))
            let h = textH + M.cardPad * 2
            let col = colY[0] <= colY[1] ? 0 : 1
            let x = M.side + CGFloat(col) * (colW + M.gap)

            let card = UIControl(frame: CGRect(x: x, y: colY[col], width: colW, height: h))
            card.backgroundColor = Glass.surfaceCard
            card.layer.cornerRadius = M.radius
            card.layer.cornerCurve = .continuous
            card.accessibilityLabel = flat
            card.accessibilityIdentifier = "clip:card"

            let label = UILabel(frame: CGRect(x: M.cardPad, y: M.cardPad, width: textW, height: textH))
            label.text = flat
            label.font = font
            label.textColor = Glass.textPrimary
            label.numberOfLines = M.maxLines
            label.lineBreakMode = .byTruncatingTail
            label.isUserInteractionEnabled = false
            card.addSubview(label)

            if editing {
                let del = UIButton(type: .system)
                del.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
                del.tintColor = Glass.accentDanger
                del.frame = CGRect(x: colW - 30, y: -6, width: 36, height: 36)
                del.addAction(UIAction { [weak self] _ in
                    ClipboardStore.remove(item.text)
                    self?.reload()
                }, for: .touchUpInside)
                card.addSubview(del)
                card.clipsToBounds = false
            }

            card.addAction(UIAction { [weak self] _ in
                guard let self, !self.editing else { return }
                self.delegate?.clipboardPanelPaste(item.text)
            }, for: .touchUpInside)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(cardHeld(_:)))
            hold.minimumPressDuration = 0.35
            card.addGestureRecognizer(hold)

            card.tag = Self.contentTag
            scroll.addSubview(card)
            cardViews.append((card, item))
            colY[col] += h + M.gap
        }
        return max(colY[0], colY[1])
    }

    private func addTip(at y: CGFloat, width: CGFloat, icon: String, text: String) -> CGFloat {
        let card = UIView()
        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = M.radius
        card.layer.cornerCurve = .continuous
        let badge = UIImageView(image: UIImage(systemName: icon))
        badge.tintColor = Glass.accentPrimary
        badge.contentMode = .center
        badge.backgroundColor = Glass.accentPrimary.withAlphaComponent(0.14)
        badge.layer.cornerRadius = 14
        badge.frame = CGRect(x: M.cardPad, y: M.cardPad, width: 28, height: 28)
        card.addSubview(badge)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: M.textSize)
        label.textColor = Glass.textPrimary
        label.numberOfLines = 0
        let textW = width - M.cardPad * 2
        let size = label.sizeThatFits(CGSize(width: textW, height: .greatestFiniteMagnitude))
        label.frame = CGRect(x: M.cardPad, y: M.cardPad + 38, width: textW, height: size.height)
        card.addSubview(label)
        card.frame = CGRect(x: M.side, y: y, width: width, height: 38 + size.height + M.cardPad * 2)
        card.tag = Self.contentTag
        scroll.addSubview(card)
        return card.frame.maxY + M.gap
    }

    // MARK: Hold menu (Paste · Pin · Delete)

    @objc private func cardHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, !editing, let card = g.view as? UIControl,
              let entry = cardViews.first(where: { $0.card === card }) else { return }
        showMenu(for: entry.item, card: card)
    }

    private func showMenu(for item: ClipItem, card: UIControl) {
        dismissMenu()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scrim.isHidden = false
        bringSubviewToFront(scrim)

        // The held card stays bright above the scrim, where it was.
        let lifted = card.snapshotView(afterScreenUpdates: false) ?? UIView()
        lifted.frame = card.convert(card.bounds, to: self)
        lifted.isUserInteractionEnabled = false
        addSubview(lifted)

        let rows: [(String, String, () -> Void)] = [
            ("doc.on.clipboard", "Paste", { [weak self] in
                self?.dismissMenu()
                self?.delegate?.clipboardPanelPaste(item.text)
            }),
            (item.pinned ? "pin.slash" : "pin", item.pinned ? "Unpin" : "Pin", { [weak self] in
                ClipboardStore.togglePin(item.text)
                self?.dismissMenu()
                self?.reload()
            }),
            ("trash", "Delete", { [weak self] in
                ClipboardStore.remove(item.text)
                self?.dismissMenu()
                self?.reload()
            }),
        ]
        let menuW: CGFloat = 176, rowH: CGFloat = 50
        let box = UIView()
        box.backgroundColor = Glass.surfaceCard
        box.layer.cornerRadius = 14
        box.layer.cornerCurve = .continuous
        box.layer.shadowColor = UIColor.black.cgColor
        box.layer.shadowOpacity = 0.14
        box.layer.shadowRadius = 14
        box.layer.shadowOffset = CGSize(width: 0, height: 4)
        for (i, row) in rows.enumerated() {
            let b = UIButton(type: .system)
            var cfg = UIButton.Configuration.plain()
            cfg.image = UIImage(systemName: row.0)
            cfg.title = row.1
            cfg.imagePadding = 16
            cfg.baseForegroundColor = Glass.textPrimary
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 12)
            b.configuration = cfg
            b.contentHorizontalAlignment = .leading
            b.titleLabel?.font = .systemFont(ofSize: 16)
            b.frame = CGRect(x: 0, y: CGFloat(i) * rowH, width: menuW, height: rowH)
            b.accessibilityIdentifier = "clip:menu:\(row.1.lowercased())"
            let action = row.2
            b.addAction(UIAction { _ in action() }, for: .touchUpInside)
            box.addSubview(b)
            if i > 0 {
                let line = UIView(frame: CGRect(x: 0, y: CGFloat(i) * rowH, width: menuW, height: 0.5))
                line.backgroundColor = Glass.strokeHairline
                box.addSubview(line)
            }
        }
        let cardFrame = lifted.frame
        let h = CGFloat(rows.count) * rowH
        // Beside the card when there is room (Gboard), otherwise below it.
        var x = cardFrame.maxX + 8
        if x + menuW > bounds.width - 8 { x = cardFrame.minX - 8 - menuW }
        if x < 8 { x = min(max(8, cardFrame.minX), bounds.width - menuW - 8) }
        let y = min(max(M.headerH, cardFrame.minY), bounds.height - h - 8)
        box.frame = CGRect(x: x, y: y, width: menuW, height: h)
        addSubview(box)
        menu = box
        liftedCard = lifted
    }

    private var liftedCard: UIView?

    private func dismissMenu() {
        menu?.removeFromSuperview()
        menu = nil
        liftedCard?.removeFromSuperview()
        liftedCard = nil
        scrim.isHidden = true
    }
}
