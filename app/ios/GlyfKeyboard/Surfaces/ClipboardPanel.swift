import Photos
import UIKit

protocol ClipboardPanelDelegate: AnyObject {
    func clipboardPanelClosed()
    func clipboardPanelPaste(_ text: String)
    /// The copy iOS has not handed over yet: tapping is the moment it asks.
    func clipboardPanelPasteFresh()
    /// A screenshot was copied: iOS keyboards can only type text, so the
    /// image goes on the pasteboard for the person to paste.
    func clipboardPanelCopiedImage()
}

/// The clipboard, laid out the way Gboard lays it out — which is the standard
/// people already know: a header with back and edit, then
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
    private let editButton = UIButton(type: .system)
    private let scroll = ControlScrollView()
    private let scrim = UIControl()
    private var menu: UIView?

    private var items: [ClipItem] = []
    /// Screenshots from the last hour, when turned on and Photos allows it.
    private var shots: [PHAsset] = []
    private var shotViews: [(card: UIControl, asset: PHAsset)] = []
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
        backgroundColor = .clear   // the system sheet is the board

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

        scrim.backgroundColor = Glass.scrim
        scrim.isHidden = true
        scrim.addAction(UIAction { [weak self] _ in self?.dismissMenu() }, for: .touchUpInside)
        addSubview(scrim)

        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Data

    func reload() {
        items = ClipboardStore.load()
        shots = Self.recentScreenshots()
        rebuildCards()
        askForPhotosIfNeeded()
    }

    /// On unless turned off in the app (Keyboard → Keep what you copy).
    private var historyOn: Bool { SettingsStore.current.clipboardHistory != false }

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
        editButton.isHidden = !historyOn
        titleLabel.frame = CGRect(x: backButton.frame.maxX + 14, y: 0,
                                  width: editButton.frame.minX - backButton.frame.maxX - 20,
                                  height: M.headerH)
        scroll.frame = CGRect(x: 0, y: M.headerH, width: w, height: bounds.height - M.headerH)
        scrim.frame = bounds
        if scroll.bounds.width > 0, laidOutWidth != scroll.bounds.width {
            laidOutWidth = scroll.bounds.width
            for v in cardViews.map(\.card) { v.removeFromSuperview() }
            cardViews.removeAll()
            for v in shotViews.map(\.card) { v.removeFromSuperview() }
            shotViews.removeAll()
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
                       icon: "doc.on.clipboard",
                       text: "Clipboard history is off in the Glyf app.")
            scroll.contentSize = CGSize(width: w, height: y + 12)
            return
        }

        // Something copied that iOS only hands over after "Allow Paste":
        // offer it first, the way Gboard shows the latest copy on top.
        if ClipContext.isFresh() {
            y = addFreshCard(at: y, width: w - M.side * 2)
        }

        let pinned = items.filter(\.pinned)
        let recent = items.filter { !$0.pinned }
        if !pinned.isEmpty {
            y = addSection("PINNED", at: y)
            y = addGrid(pinned, at: y, colW: colW)
        }
        if !recent.isEmpty || !shots.isEmpty {
            y = addSection("RECENT", at: y)
            if !shots.isEmpty { y = addShots(at: y, colW: colW) }
            if !recent.isEmpty { y = addGrid(recent, at: y, colW: colW) }
        }
        if items.isEmpty && shots.isEmpty && !ClipContext.isFresh() {
            y = addTip(at: y, width: w - M.side * 2, icon: "doc.on.clipboard",
                       text: "Nothing copied yet")
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
            card.isAccessibilityElement = true
            card.accessibilityTraits = .button

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

    // MARK: Screenshots

    /// iOS keeps the keyboard's Photos permission apart from the app's, and
    /// a keyboard asks on first use. Opening the clipboard with screenshots
    /// turned on is that first use.
    private func askForPhotosIfNeeded() {
        guard SettingsStore.current.clipboardScreenshots == true,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard status == .authorized || status == .limited else { return }
            DispatchQueue.main.async { self?.reload() }
        }
    }

    private static let removedKey = "clip-removed-shots"

    /// Screenshots from the last hour, newest first, as Gboard keeps them.
    static func recentScreenshots() -> [PHAsset] {
        guard SettingsStore.current.clipboardScreenshots == true else { return [] }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        let since = Date().addingTimeInterval(-3600) as NSDate
        #if targetEnvironment(simulator)
        // The simulator cannot take a real screenshot into Photos.
        options.predicate = NSPredicate(format: "creationDate > %@", since)
        #else
        options.predicate = NSPredicate(format: "creationDate > %@ AND (mediaSubtypes & %d) != 0",
                                        since, PHAssetMediaSubtype.photoScreenshot.rawValue)
        #endif
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 6
        let removed = Set(UserDefaults.standard.stringArray(forKey: removedKey) ?? [])
        var out: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            if !removed.contains(asset.localIdentifier) { out.append(asset) }
        }
        return out
    }

    /// Two columns of screenshot cards, each showing the top of the shot.
    private func addShots(at top: CGFloat, colW: CGFloat) -> CGFloat {
        var colY: [CGFloat] = [top, top]
        let h = (colW * 1.25).rounded()
        let scale = UIScreen.main.scale
        for asset in shots {
            let col = colY[0] <= colY[1] ? 0 : 1
            let card = UIControl(frame: CGRect(x: M.side + CGFloat(col) * (colW + M.gap),
                                               y: colY[col], width: colW, height: h))
            card.backgroundColor = Glass.surfaceCard
            card.layer.cornerRadius = M.radius
            card.layer.cornerCurve = .continuous
            card.clipsToBounds = true
            card.accessibilityLabel = "Screenshot"
            card.accessibilityIdentifier = "clip:shot"
            card.isAccessibilityElement = true
            card.accessibilityTraits = [.button, .image]
            let image = UIImageView(frame: card.bounds)
            image.contentMode = .scaleAspectFill
            image.isUserInteractionEnabled = false
            card.addSubview(image)
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: colW * scale, height: h * scale),
                contentMode: .aspectFill, options: opts) { result, _ in
                    if let result { image.image = result }
                }
            card.addAction(UIAction { [weak self] _ in
                guard let self, !self.editing else { return }
                self.copyShot(asset)
            }, for: .touchUpInside)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(shotHeld(_:)))
            hold.minimumPressDuration = 0.35
            card.addGestureRecognizer(hold)
            card.tag = Self.contentTag
            scroll.addSubview(card)
            shotViews.append((card, asset))
            colY[col] += h + M.gap
        }
        return max(colY[0], colY[1])
    }

    private func copyShot(_ asset: PHAsset) {
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = false
        opts.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) {
            [weak self] data, _, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            UIPasteboard.general.image = image
            DispatchQueue.main.async { self?.delegate?.clipboardPanelCopiedImage() }
        }
    }

    @objc private func shotHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, !editing, let card = g.view as? UIControl,
              let entry = shotViews.first(where: { $0.card === card }) else { return }
        let asset = entry.asset
        showMenu(rows: [
            ("doc.on.doc", "Copy", { [weak self] in
                self?.dismissMenu()
                self?.copyShot(asset)
            }),
            ("trash", "Delete", { [weak self] in
                // Off the clipboard only; the screenshot stays in Photos.
                var removed = UserDefaults.standard.stringArray(forKey: Self.removedKey) ?? []
                removed.append(asset.localIdentifier)
                UserDefaults.standard.set(Array(removed.suffix(50)), forKey: Self.removedKey)
                self?.dismissMenu()
                self?.reload()
            }),
        ], card: card)
    }

    private func addFreshCard(at y: CGFloat, width: CGFloat) -> CGFloat {
        let card = UIControl(frame: CGRect(x: M.side, y: y, width: width, height: 48))
        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = M.radius
        card.layer.cornerCurve = .continuous
        card.accessibilityLabel = "Paste what you copied"
        card.accessibilityIdentifier = "clip:fresh"
        card.isAccessibilityElement = true
        card.accessibilityTraits = .button
        let icon = UIImageView(image: UIImage(systemName: "doc.on.clipboard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
        icon.tintColor = Glass.accentPrimary
        icon.contentMode = .center
        icon.frame = CGRect(x: M.cardPad - 2, y: 0, width: 24, height: 48)
        card.addSubview(icon)
        let label = UILabel(frame: CGRect(x: M.cardPad + 30, y: 0, width: width - M.cardPad * 2 - 30, height: 48))
        label.text = "Paste what you copied"
        label.font = .systemFont(ofSize: M.textSize, weight: .semibold)
        label.textColor = Glass.accentPrimary
        card.addSubview(label)
        card.addAction(UIAction { [weak self] _ in
            guard let self, !self.editing else { return }
            self.delegate?.clipboardPanelPasteFresh()
        }, for: .touchUpInside)
        card.tag = Self.contentTag
        scroll.addSubview(card)
        return card.frame.maxY + M.gap
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
        showMenu(rows: [
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
        ], card: card)
    }

    private func showMenu(rows: [(String, String, () -> Void)], card: UIControl) {
        dismissMenu()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scrim.isHidden = false
        bringSubviewToFront(scrim)

        // The held card stays bright above the scrim, where it was.
        let lifted = card.snapshotView(afterScreenUpdates: false) ?? UIView()
        lifted.frame = card.convert(card.bounds, to: self)
        lifted.isUserInteractionEnabled = false
        addSubview(lifted)

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
