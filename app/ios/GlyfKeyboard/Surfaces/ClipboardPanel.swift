import OSLog
import Photos
import UIKit

protocol ClipboardPanelDelegate: AnyObject {
    func clipboardPanelClosed()
    func clipboardPanelPaste(_ text: String)
    /// A screenshot was copied: iOS keyboards can only type text, so the
    /// image goes on the pasteboard for the person to paste.
    func clipboardPanelCopiedImage()
    /// A clip went into the vault as a note, or `refusal` says why not.
    func clipboardPanelSavedToVault(refusal: String?)
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
    /// Who receives `paste(itemProviders:)` from the system paste button.
    /// A keyboard extension's view controller is not in the responder chain
    /// the control searches by default, so it is handed over explicitly.
    weak var pasteTarget: UIResponder?

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

    /// What the list is showing. All / Text / Link / Image are parallel
    /// kinds, which is what a row of pills is for; pinned is NOT one of them
    /// — it is a priority, so it stays a section at the top of whichever
    /// kind is selected rather than becoming a fourth pill that hides the
    /// rest.
    private enum Filter: CaseIterable {
        case all, text, link, image

        var title: String {
            switch self {
            case .all: return "All"
            case .text: return "Text"
            case .link: return "Link"
            case .image: return "Image"
            }
        }

        var symbol: String {
            switch self {
            case .all: return "line.3.horizontal"
            case .text: return "textformat"
            case .link: return "link"
            case .image: return "photo"
            }
        }

        /// A clip is a link or it is text, never both, so the pills add up to
        /// All. `ClipboardStore.isLink` owns the rule (and is unit-tested).
        func accepts(_ clip: ClipItem) -> Bool {
            switch self {
            case .all: return true
            case .image: return false
            case .link: return ClipboardStore.isLink(clip.text)
            case .text: return !ClipboardStore.isLink(clip.text)
            }
        }

        var showsShots: Bool { self == .all || self == .image }
        var showsClips: Bool { self != .image }
    }

    private var filter: Filter = .all
    private let filterRow = UIView()
    private var filterPills: [Filter: UIControl] = [:]

    private enum M {
        static let headerH: CGFloat = 52
        static let filterH: CGFloat = 34
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
        backgroundColor = Glass.touchableGrid // sheet shows through; still tappable

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

        for kind in Filter.allCases {
            let pill = UIControl()
            pill.layer.cornerCurve = .continuous
            pill.accessibilityIdentifier = "clip:filter:\(kind.title.lowercased())"
            pill.isAccessibilityElement = true
            pill.accessibilityLabel = kind.title
            pill.accessibilityTraits = .button
            let icon = UIImageView(image: UIImage(systemName: kind.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
            icon.tag = 1
            icon.contentMode = .center
            icon.isUserInteractionEnabled = false
            pill.addSubview(icon)
            let title = UILabel()
            title.tag = 2
            title.text = kind.title
            title.font = .systemFont(ofSize: 13.5, weight: .medium)
            title.isUserInteractionEnabled = false
            pill.addSubview(title)
            pill.addAction(UIAction { [weak self] _ in self?.select(kind) },
                           for: .touchUpInside)
            filterRow.addSubview(pill)
            filterPills[kind] = pill
        }
        addSubview(filterRow)
        paintPills()

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
        // Draw what we already have FIRST. What you copied lives in the App
        // Group and is ready immediately; screenshots need Photos, which is
        // another process and answers when it answers. Waiting for it before
        // drawing anything is what made the panel feel slow to show a copy.
        rebuildCards()
        askForPhotosIfNeeded()
        loadScreenshots()
        // A new copy iOS can name — a link, an address, a number — joins the
        // list on its own, without the banner that reading it outright
        // raises. Anything else keeps waiting behind the Paste button.
        let folded: (Bool) -> Void = { [weak self] added in
            guard added, let self else { return }
            self.items = ClipboardStore.load()
            self.rebuildCards()
        }
        ClipboardStore.captureNewCopy(folded)
    }

    /// Asks Photos off the main thread and folds the answer in when it
    /// arrives. `shotsRequest` drops a reply that a newer reload replaced.
    private var shotsRequest = 0

    private func loadScreenshots() {
        guard SettingsStore.current.clipboardScreenshots != false else {
            if !shots.isEmpty { shots = []; rebuildCards() }
            return
        }
        shotsRequest += 1
        let request = shotsRequest
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.recentScreenshots()
            DispatchQueue.main.async {
                guard let self, self.shotsRequest == request else { return }
                let before = self.shots.map(\.localIdentifier)
                guard before != found.map(\.localIdentifier) else { return }
                self.shots = found
                self.rebuildCards()
            }
        }
    }

    /// On unless turned off in the app (Keyboard → Keep what you copy).
    private var historyOn: Bool { SettingsStore.current.clipboardHistory != false }

    private func select(_ kind: Filter) {
        guard filter != kind else { return }
        filter = kind
        paintPills()
        rebuildCards()
    }

    private func paintPills() {
        for (kind, pill) in filterPills {
            let on = kind == filter
            pill.backgroundColor = on ? Glass.brandInk : Glass.surfaceCard
            (pill.viewWithTag(1) as? UIImageView)?.tintColor = on ? .white : Glass.textPrimary
            (pill.viewWithTag(2) as? UILabel)?.textColor = on ? .white : Glass.textPrimary
            pill.accessibilityTraits = on ? [.button, .selected] : .button
        }
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
        editButton.isHidden = !historyOn
        titleLabel.frame = CGRect(x: backButton.frame.maxX + 14, y: 0,
                                  width: editButton.frame.minX - backButton.frame.maxX - 20,
                                  height: M.headerH)
        filterRow.frame = CGRect(x: 0, y: M.headerH, width: w, height: M.filterH)
        var px = M.side
        for kind in Filter.allCases {
            guard let pill = filterPills[kind] else { continue }
            let label = pill.viewWithTag(2) as? UILabel
            let textW = label?.intrinsicContentSize.width ?? 30
            let pw = 18 + 16 + 6 + textW + 14
            let ph = M.filterH - 8
            pill.frame = CGRect(x: px, y: 4, width: pw, height: ph)
            pill.layer.cornerRadius = ph / 2
            pill.viewWithTag(1)?.frame = CGRect(x: 11, y: 0, width: 16, height: ph)
            label?.frame = CGRect(x: 11 + 16 + 6, y: 0, width: textW, height: ph)
            px += pw + 7
        }
        let top = M.headerH + M.filterH
        scroll.frame = CGRect(x: 0, y: top, width: w, height: bounds.height - top)
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

        // Pinned still leads, but only within the kind being shown: picking
        // Link should not scroll you past pinned text to reach the links.
        let clips = filter.showsClips ? items.filter(filter.accepts) : []
        let visibleShots = filter.showsShots ? shots : []
        let pinned = clips.filter(\.pinned)
        let recent = clips.filter { !$0.pinned }
        if !pinned.isEmpty {
            y = addSection("PINNED", at: y)
            y = addGrid(pinned, at: y, colW: colW)
        }
        if !recent.isEmpty || !visibleShots.isEmpty {
            y = addSection("RECENT", at: y)
            // Newest first, whichever kind it is. Screenshots used to sit in
            // a block above every copy however old they were, so a shot from
            // yesterday buried the thing you copied a minute ago.
            let entries = (recent.map(Recent.clip) + visibleShots.map(Recent.shot))
                .sorted { $0.when > $1.when }
            y = addRecent(entries, at: y, colW: colW)
        }
        if clips.isEmpty && visibleShots.isEmpty && !ClipContext.isFresh() {
            y = addTip(at: y, width: w - M.side * 2, icon: filter.symbol,
                       text: filter == .all
                           ? "Nothing copied yet"
                           : "No \(filter.title.lowercased()) copied yet")
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

    /// One thing in the list, whichever kind it is — they interleave by when
    /// they happened rather than sitting in blocks by type.
    private enum Recent {
        case clip(ClipItem)
        case shot(PHAsset)

        var when: Date {
            switch self {
            case .clip(let item): return item.ts
            case .shot(let asset): return asset.creationDate ?? .distantPast
            }
        }
    }

    /// Two columns, each card as tall as it needs (Gboard's masonry): every
    /// card lands in whichever column is shorter, in the order given.
    private func addRecent(_ entries: [Recent], at top: CGFloat, colW: CGFloat) -> CGFloat {
        var colY: [CGFloat] = [top, top]
        for entry in entries {
            let col = colY[0] <= colY[1] ? 0 : 1
            let x = M.side + CGFloat(col) * (colW + M.gap)
            let h: CGFloat
            switch entry {
            case .clip(let item): h = addClipCard(item, x: x, y: colY[col], colW: colW)
            case .shot(let asset): h = addShotCard(asset, x: x, y: colY[col], colW: colW)
            }
            colY[col] += h + M.gap
        }
        return max(colY[0], colY[1])
    }

    /// Pinned copies, which stay in their own block above the rest.
    private func addGrid(_ clips: [ClipItem], at top: CGFloat, colW: CGFloat) -> CGFloat {
        addRecent(clips.map(Recent.clip), at: top, colW: colW)
    }

    /// Returns the card's height so the column it landed in can move down.
    @discardableResult
    private func addClipCard(_ item: ClipItem, x: CGFloat, y cardY: CGFloat,
                             colW: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: M.textSize)
        do {
            let flat = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let textW = colW - M.cardPad * 2
            let lineH = font.lineHeight
            let bounding = (flat as NSString).boundingRect(
                with: CGSize(width: textW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil)
            let textH = min(ceil(bounding.height), lineH * CGFloat(M.maxLines))
            let h = textH + M.cardPad * 2
            let card = UIControl(frame: CGRect(x: x, y: cardY, width: colW, height: h))
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
            return h
        }
    }

    // MARK: Screenshots

    /// iOS keeps the keyboard's Photos permission apart from the app's, and
    /// a keyboard asks on first use. Opening the clipboard with screenshots
    /// turned on is that first use.
    private func askForPhotosIfNeeded() {
        guard SettingsStore.current.clipboardScreenshots != false,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard status == .authorized || status == .limited else { return }
            DispatchQueue.main.async { self?.reload() }
        }
    }

    private static let removedKey = "clip-removed-shots"

    /// Screenshots from the last two days, newest first, as Gboard keeps
    /// them. Runs off the main thread — see `loadScreenshots`.
    static func recentScreenshots() -> [PHAsset] {
        guard SettingsStore.current.clipboardScreenshots != false else { return [] }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        // The same two days a copy keeps for: a screenshot you took yesterday
        // is exactly the thing you come to the clipboard looking for.
        let since = Date().addingTimeInterval(-ClipboardStore.expiry) as NSDate
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
    @discardableResult
    private func addShotCard(_ asset: PHAsset, x: CGFloat, y cardY: CGFloat,
                             colW: CGFloat) -> CGFloat {
        let h = (colW * 1.25).rounded()
        let scale = UIScreen.main.scale
        do {
            let card = UIControl(frame: CGRect(x: x, y: cardY, width: colW, height: h))
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
            return h
        }
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

    /// The newest copy, which iOS has not handed over yet.
    ///
    /// The button is a UIPasteControl rather than one of ours on purpose: a
    /// tap on it IS the permission, so nothing is asked afterwards. Reading
    /// `UIPasteboard.general.string` ourselves puts up "Allow Paste?" every
    /// time the copy changes, which is the banner that kept appearing.
    private func addFreshCard(at y: CGFloat, width: CGFloat) -> CGFloat {
        let card = UIView(frame: CGRect(x: M.side, y: y, width: width, height: 48))
        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = M.radius
        card.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: "doc.on.clipboard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
        icon.tintColor = Glass.textSecondary
        icon.contentMode = .center
        icon.frame = CGRect(x: M.cardPad - 2, y: 0, width: 24, height: 48)
        card.addSubview(icon)

        // Let the control pick its own size. Forced into a smaller frame it
        // draws as an empty rectangle — the system reserves the right to
        // refuse a paste button that has been shrunk or disguised.
        let cfg = UIPasteControl.Configuration()
        cfg.displayMode = .iconAndLabel
        cfg.cornerStyle = .capsule
        let paste = UIPasteControl(configuration: cfg)
        paste.target = pasteTarget
        let fit = Self.pasteSize(paste)
        paste.frame = CGRect(x: width - M.cardPad - fit.width,
                             y: (48 - fit.height) / 2,
                             width: fit.width, height: fit.height)
        paste.accessibilityIdentifier = "clip:fresh"
        card.addSubview(paste)

        let labelX = M.cardPad + 30
        let label = UILabel(frame: CGRect(x: labelX, y: 0,
                                          width: max(0, paste.frame.minX - labelX - 8), height: 48))
        // Quiet: the button is the thing to press, so the line beside it is a
        // label and not a headline competing with it.
        label.text = "Something you copied"
        label.font = .systemFont(ofSize: M.textSize - 1)
        label.textColor = Glass.textSecondary
        card.addSubview(label)

        card.tag = Self.contentTag
        scroll.addSubview(card)
        return card.frame.maxY + M.gap
    }

    /// The size a UIPasteControl actually wants. `sizeThatFits` answers zero
    /// before the control is in a window; the compressed fitting size reads
    /// its intrinsic size, which is defined from the start.
    static func pasteSize(_ control: UIPasteControl) -> CGSize {
        var fit = control.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if fit.width < 40 { fit.width = control.intrinsicContentSize.width }
        if fit.height < 24 { fit.height = control.intrinsicContentSize.height }
        if fit.width < 40 || fit.height < 24 { fit = CGSize(width: 104, height: 38) }
        Logger(subsystem: "so.glyf.keyboard", category: "lifecycle")
            .log("GLYF_KB pasteSize=\(fit.width)x\(fit.height)")
        return fit
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
            ("person.text.rectangle", "Save to vault", { [weak self] in
                let refusal = NotesStore.shared.upsert(id: nil, text: item.text)
                self?.dismissMenu()
                self?.delegate?.clipboardPanelSavedToVault(refusal: refusal)
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
