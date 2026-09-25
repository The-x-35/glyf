import UIKit

protocol EmojiBoardDelegate: AnyObject {
    func emojiPicked(_ emoji: String)
    func emojiBoardClosed()
    /// The ABC key: back to the letters, exactly like the system keyboard.
    func emojiBackToLetters()
    /// The backspace at the far end of the category row, also Apple's.
    func emojiDeleteBackward()
    func emojiSearchActivated(_ editor: InlineEditor)
    /// Search opened/closed — the board collapses to a strip so the LETTER
    /// KEYS can show underneath (Apple/Gboard behavior).
    func emojiLayoutChanged()
    func emojiSearchDismissed()
    /// A GIF or sticker was tapped: put it on the pasteboard, `done(true)`
    /// once it is there.
    func emojiBoardSend(_ item: MediaItem, kind: MediaKind, done: @escaping (Bool) -> Void)
    /// An emoticon was tapped: type it, like a key.
    func emojiBoardType(_ text: String)
    /// Loading GIFs and handing one over both need Full Access.
    var emojiBoardHasFullAccess: Bool { get }
}

/// §6.1 emoji keyboard, laid out like Apple's: the search field on top, the
/// section's name under it, the grid, and ABC · categories · delete along
/// the bottom. Beside the search field, four glyphs switch what the board
/// holds, the way Gboard's bottom row does: Emoji, Stickers, GIFs and
/// Emoticons. Every mode keeps Apple's shape: the same field, the same
/// small-capitals section name, the same bottom bar with ABC and delete, the
/// same grey circle behind whatever is chosen.
///
/// Emoji are text cells in one horizontally paging grid (no images, for
/// memory). GIFs and stickers are small animated previews from our server,
/// in a masonry grid that scrolls down like Messages' #images; tapping one
/// copies it for pasting, since no keyboard can type a picture. Emoticons
/// are text and type straight into the field.
final class EmojiBoard: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    weak var delegate: EmojiBoardDelegate?

    enum Mode: Int, CaseIterable {
        case emoji, stickers, gifs, emoticons

        var kind: MediaKind? {
            switch self {
            case .gifs: return .gifs
            case .stickers: return .stickers
            default: return nil
            }
        }
        var placeholder: String {
            switch self {
            case .emoji: return "Search Emoji"
            case .stickers: return "Search Stickers"
            case .gifs: return "Search GIFs"
            case .emoticons: return "Search Emoticons"
            }
        }
        var name: String {
            switch self {
            case .emoji: return "emoji"
            case .stickers: return "stickers"
            case .gifs: return "gifs"
            case .emoticons: return "emoticons"
            }
        }
    }

    /// Always Emoji when the board opens: the key has a smiley on it, and
    /// Apple's opens on emoji every time. The other modes are one tap away
    /// and remember which chip was chosen for as long as the board is up.
    private(set) var mode: Mode = .emoji

    private let searchEditor = InlineEditor(placeholder: "Search Emoji", searchStyle: true)
    private let closeButton = UIButton(type: .system)
    private let abcButton = UIButton(type: .system)
    /// Apple's emoji keyboard keeps ABC bottom-left and ⌫ bottom-right, on
    /// either side of the category row. People reach for both without
    /// looking, so they are here too.
    private let lettersButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    /// While true the board is a strip (field + one result row) and the
    /// keyboard's letter keys are visible below it.
    private(set) var searchActive = false
    /// Strip height in search mode (field row + results row).
    static let searchStripHeight: CGFloat = 96
    /// How much taller than the letters the grid stands (Apple's does too).
    static let extraHeight: CGFloat = 44

    // Emoji
    private var collection: UICollectionView!
    private let tabs = UIStackView()
    private let tabThumb = UIView()
    private let sectionLabel = UILabel()
    /// Frequently used, then every category, as one horizontal run.
    private var sections: [(title: String, emoji: [String])] = []
    private var currentCategory = 0
    private var searchResults: [String]?
    private var tonePopup: UIView?

    // The mode switch: four glyphs with Apple's grey circle behind one.
    private let modeBar = UIView()
    private var modeButtons: [UIButton] = []
    private let modeThumb = UIView()

    // GIFs, stickers and emoticons
    private var mediaGrid: UICollectionView!
    private let masonry = MasonryLayout()
    private var emoticonGrid: UICollectionView!
    private let chipBar = UIScrollView()
    /// Holds the chip bar and fades its ends, so a chip scrolled half out of
    /// sight dissolves instead of being cut at ABC or delete.
    private let chipFade = UIView()
    private let chipFadeMask = CAGradientLayer()
    private var chipButtons: [UIButton] = []
    private let chipThumb = UIView()
    private let suggestionBar = UIScrollView()
    private let statusLabel = UILabel()
    /// The line over an empty or failed grid. It lies over the grid, so it
    /// is only there (and only takes a tap, to retry) while it says
    /// something; an empty label on top would swallow every tap on a GIF.
    private var statusText: String? {
        didSet {
            statusLabel.text = statusText
            statusLabel.isHidden = statusText == nil || mode == .emoji || searchActive
        }
    }
    private let attributionLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    /// What the media grid shows: a chip's feed or a search, from one
    /// source (KLIPY's results never share a grid with anything else).
    private struct Feed {
        var key: String
        var title: String
        var source: MediaSource = .noto
        var items: [MediaItem] = []
        var next: String?
        /// The search behind the feed; "" is trending, nil is the recents.
        var query: String?
        var loading = false
    }
    private var feed = Feed(key: "", title: "")
    private var feedTask: URLSessionDataTask?
    private var suggestTask: URLSessionDataTask?
    private var suggestWork: DispatchWorkItem?
    private var sendingIndex: Int?
    private var selectedChip: [Mode: String] = [:]
    private var emoticonItems: [String] = []

    /// One entry on the bottom bar of a media or emoticon page.
    private struct Chip {
        let id: String
        /// Shown as text ("Haha"), as an emoji glyph ("😂"), or as an SF
        /// Symbol (the clock).
        var title: String?
        var glyph: String?
        var symbol: String?
        /// What it searches; "" is trending, nil is the recents.
        var query: String?
        var label: String
        /// Always Noto's animated emoji, whatever else is set up.
        var noto = false
    }

    private static let recentsChip = Chip(id: "recents", symbol: "clock", query: nil,
                                          label: "Recently used")

    private static let gifChips: [Chip] = [recentsChip,
        Chip(id: "trending", title: "Trending", query: "", label: "Trending")] + [
        ("Haha", "haha"), ("Love", "love"), ("Sad", "sad"), ("Yes", "yes"), ("No", "no"),
        ("Wow", "wow"), ("OMG", "omg"), ("Thanks", "thank you"), ("Hi", "hello"),
        ("Bye", "bye"), ("Miss you", "miss you"), ("Hug", "hug"), ("Party", "party"),
        ("Dance", "dance"), ("Congrats", "congratulations"), ("Birthday", "happy birthday"),
        ("Good night", "good night"), ("Facepalm", "facepalm"), ("Sleepy", "sleepy"),
        ("Hungry", "hungry"), ("Awkward", "awkward"),
    ].map { Chip(id: $0.1, title: $0.0, query: $0.1, label: $0.0) }

    private static let feelingChips: [Chip] = [
        ("😂", "laughing"), ("❤️", "love"), ("👍", "thumbs up"), ("😢", "sad"),
        ("😡", "angry"), ("🎉", "party"), ("🙏", "thank you"), ("👋", "hello"),
        ("😴", "sleepy"), ("😮", "wow"), ("🐶", "dog"), ("🐱", "cat"),
        ("🍕", "food"), ("🎂", "birthday"),
    ].map { Chip(id: $0.1, glyph: $0.0, query: $0.1, label: $0.1.capitalized) }

    /// KLIPY's stickers when the server has a key, with Noto's animated
    /// emoji as a page of their own at the end; Noto's alone otherwise.
    private var stickerChips: [Chip] {
        let klipy = MediaClient.shared.config?.klipy != nil
        var list = [Self.recentsChip,
                    Chip(id: "trending", symbol: klipy ? "flame" : "star", query: "",
                         label: klipy ? "Trending" : "Popular")] + Self.feelingChips
        if klipy {
            list.append(Chip(id: "noto", symbol: "face.smiling", query: "",
                             label: "Animated emoji", noto: true))
        }
        return list
    }

    /// The source a chip reads: stickers fall back to Noto without KLIPY.
    private func source(for chip: Chip?) -> MediaSource {
        if mode == .gifs { return .klipy }
        if chip?.noto == true { return .noto }
        return MediaClient.shared.config?.klipy != nil ? .klipy : .noto
    }

    /// KLIPY asks for its name in the search field.
    private var placeholder: String {
        let klipy = MediaClient.shared.config?.klipy != nil
        switch mode {
        case .gifs where klipy, .stickers where klipy: return "Search KLIPY"
        default: return mode.placeholder
        }
    }

    private static let emoticonChips: [Chip] = [recentsChip] +
        EmoticonData.categories.map { Chip(id: $0.id, title: $0.title, query: $0.id, label: $0.title) }

    private func chips(for mode: Mode) -> [Chip] {
        switch mode {
        case .gifs: return Self.gifChips
        case .stickers: return stickerChips
        case .emoticons: return Self.emoticonChips
        case .emoji: return []
        }
    }

    static let recentsKey = "emoji-recents.json"

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        searchEditor.onChange = { [weak self] q in self?.queryChanged(q) }
        // Apple's emoji search field is a rounded rectangle a shade lighter
        // than the sheet (#eff0f4 on #e2e4e8, measured on iOS 26), not a pill.
        searchEditor.layer.cornerRadius = 12
        searchEditor.backgroundColor = Glass.chromeDark
            ? UIColor.white.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.48)
        let tap = UITapGestureRecognizer(target: self, action: #selector(searchTapped))
        searchEditor.addGestureRecognizer(tap)
        searchEditor.isAccessibilityElement = true
        searchEditor.accessibilityIdentifier = "emoji:search"
        searchEditor.accessibilityLabel = "Search emoji"
        addSubview(searchEditor)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "emoji:close"
        closeButton.accessibilityLabel = "Close search"
        closeButton.addAction(UIAction { [weak self] _ in self?.exitSearch() },
                              for: .touchUpInside)
        addSubview(closeButton)

        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        abcButton.setTitleColor(Glass.textPrimary, for: .normal)
        abcButton.accessibilityIdentifier = "emoji:abc"
        abcButton.isHidden = true
        abcButton.addAction(UIAction { [weak self] _ in self?.exitSearch() },
                            for: .touchUpInside)
        addSubview(abcButton)

        // Apple's grid, measured on iOS 26: columns about 47pt apart, rows
        // 39pt, five rows, filled top to bottom and paging sideways.
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 47, height: 39)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 14)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = Glass.touchableGrid
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        collection.showsHorizontalScrollIndicator = false
        collection.alwaysBounceHorizontal = true

        // Apple's section names are small capitals in a quiet grey.
        sectionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sectionLabel.textColor = Self.sectionGrey
        sectionLabel.accessibilityIdentifier = "emoji:section"
        addSubview(sectionLabel)
        attributionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        attributionLabel.textColor = Self.sectionGrey
        attributionLabel.textAlignment = .right
        attributionLabel.accessibilityIdentifier = "emoji:attribution"
        addSubview(attributionLabel)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(cellLong(_:)))
        long.minimumPressDuration = 0.35
        collection.addGestureRecognizer(long)
        addSubview(collection)

        masonry.aspect = { [weak self] ip in
            guard let self, self.feed.items.indices.contains(ip.item) else { return 1 }
            return self.mode == .stickers ? 1 : self.feed.items[ip.item].aspect
        }
        mediaGrid = UICollectionView(frame: .zero, collectionViewLayout: masonry)
        mediaGrid.backgroundColor = Glass.touchableGrid
        mediaGrid.dataSource = self
        mediaGrid.delegate = self
        mediaGrid.register(MediaCell.self, forCellWithReuseIdentifier: "m")
        mediaGrid.showsVerticalScrollIndicator = false
        mediaGrid.alwaysBounceVertical = true
        mediaGrid.accessibilityIdentifier = "emoji:media"
        addSubview(mediaGrid)

        let emoticonLayout = UICollectionViewFlowLayout()
        emoticonLayout.minimumInteritemSpacing = 0
        emoticonLayout.minimumLineSpacing = 2
        emoticonLayout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 10, right: 8)
        emoticonGrid = UICollectionView(frame: .zero, collectionViewLayout: emoticonLayout)
        emoticonGrid.backgroundColor = Glass.touchableGrid
        emoticonGrid.dataSource = self
        emoticonGrid.delegate = self
        emoticonGrid.register(EmoticonCell.self, forCellWithReuseIdentifier: "t")
        emoticonGrid.showsVerticalScrollIndicator = false
        emoticonGrid.alwaysBounceVertical = true
        emoticonGrid.accessibilityIdentifier = "emoji:emoticons"
        addSubview(emoticonGrid)

        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = Glass.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "emoji:status"
        addSubview(statusLabel)
        spinner.color = Glass.textSecondary
        spinner.hidesWhenStopped = true
        addSubview(spinner)

        lettersButton.setTitle("ABC", for: .normal)
        lettersButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        lettersButton.setTitleColor(Glass.textPrimary, for: .normal)
        lettersButton.accessibilityIdentifier = "emoji:letters"
        lettersButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.emojiBackToLetters()
        }, for: .touchUpInside)
        addSubview(lettersButton)

        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.setPreferredSymbolConfiguration(.init(pointSize: 18, weight: .regular),
                                                     forImageIn: .normal)
        deleteButton.tintColor = Glass.textPrimary
        deleteButton.accessibilityIdentifier = "emoji:delete"
        deleteButton.accessibilityLabel = "Delete"
        deleteButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.emojiDeleteBackward()
        }, for: .touchUpInside)
        addSubview(deleteButton)

        tabThumb.backgroundColor = Self.thumbColor
        addSubview(tabThumb)
        tabs.axis = .horizontal
        tabs.distribution = .fillEqually
        addSubview(tabs)
        buildTabs()

        chipThumb.backgroundColor = Self.thumbColor
        chipBar.addSubview(chipThumb)
        chipBar.showsHorizontalScrollIndicator = false
        chipBar.accessibilityIdentifier = "emoji:chips"
        chipFade.addSubview(chipBar)
        chipFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        chipFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        chipFadeMask.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        chipFade.layer.mask = chipFadeMask
        addSubview(chipFade)
        suggestionBar.showsHorizontalScrollIndicator = false
        suggestionBar.accessibilityIdentifier = "emoji:suggestions"
        addSubview(suggestionBar)

        modeThumb.backgroundColor = Self.thumbColor
        modeBar.addSubview(modeThumb)
        buildModeBar()
        addSubview(modeBar)

        reload()
        highlightTab(0)
        setMode(.emoji, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Light and dark flipped while the board was up (the phone went dark
    /// at sunset, say): every colour it took from the palette is taken
    /// again, and the grids redraw with the new ink.
    func applyPalette() {
        backgroundColor = Glass.touchableGrid
        searchEditor.backgroundColor = Glass.chromeDark
            ? UIColor.white.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.48)
        searchEditor.placeholder = placeholder   // re-renders its text in the new ink
        closeButton.tintColor = Glass.textSecondary
        abcButton.setTitleColor(Glass.textPrimary, for: .normal)
        lettersButton.setTitleColor(Glass.textPrimary, for: .normal)
        deleteButton.tintColor = Glass.textPrimary
        for grid in [collection, mediaGrid, emoticonGrid] as [UICollectionView] {
            grid.backgroundColor = Glass.touchableGrid
        }
        sectionLabel.textColor = Self.sectionGrey
        attributionLabel.textColor = Self.sectionGrey
        statusLabel.textColor = Glass.textSecondary
        spinner.color = Glass.textSecondary
        for thumb in [tabThumb, modeThumb, chipThumb] { thumb.backgroundColor = Self.thumbColor }
        for (i, b) in modeButtons.enumerated() {
            b.tintColor = i == mode.rawValue ? Glass.textPrimary : Glass.textSecondary
        }
        highlightTab(currentCategory)
        placeChipThumb()
        collection.reloadData()
        emoticonGrid.reloadData()
        mediaGrid.reloadData()
        if !suggestionBar.isHidden { queryChanged(searchEditor.text) }
    }

    /// Apple's section names: small capitals, lighter than body text.
    private static var sectionGrey: UIColor {
        // Apple's grey is made for Apple's sheet. On a painted board (Dusk,
        // Ocean…) it all but vanishes, and KLIPY's "Powered by" line has to
        // be readable, so there the board's own ink is softened instead.
        if Glass.themedBgActive { return Glass.textPrimary.withAlphaComponent(0.72) }
        return Glass.chromeDark ? UIColor(white: 0.60, alpha: 1) : UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1)
    }
    /// The soft circle Apple puts behind the chosen category.
    private static var thumbColor: UIColor {
        Glass.textPrimary.withAlphaComponent(Glass.chromeDark ? 0.18 : 0.10)
    }

    private static let sectionTitles = [
        "smileys": "SMILEYS & PEOPLE", "animals": "ANIMALS & NATURE",
        "food": "FOOD & DRINK", "activity": "ACTIVITY", "travel": "TRAVEL & PLACES",
        "objects": "OBJECTS", "symbols": "SYMBOLS", "flags": "FLAGS",
    ]

    // MARK: Mode switch

    private func buildModeBar() {
        let glyphs: [(Mode, UIImage?, String)] = [
            (.emoji, UIImage(systemName: "face.smiling"), "Emoji"),
            (.stickers, BoardGlyphs.sticker(), "Stickers"),
            (.gifs, BoardGlyphs.text("GIF", size: 10.5, weight: .heavy, boxed: true), "GIFs"),
            (.emoticons, BoardGlyphs.text(":-)", size: 14, weight: .semibold), "Emoticons"),
        ]
        for (mode, image, label) in glyphs {
            let b = UIButton(type: .system)
            b.setImage(image, for: .normal)
            if mode == .emoji {
                b.setPreferredSymbolConfiguration(.init(pointSize: 17, weight: .regular), forImageIn: .normal)
            }
            b.tintColor = Glass.textSecondary
            b.accessibilityLabel = label
            b.accessibilityIdentifier = "emoji:mode:\(mode.name)"
            b.addAction(UIAction { [weak self] _ in self?.setMode(mode, animated: true) },
                        for: .touchUpInside)
            modeBar.addSubview(b)
            modeButtons.append(b)
        }
    }

    /// Switches what the board holds. Search starts over in the new mode.
    func setMode(_ new: Mode, animated: Bool) {
        dismissTonePopup()
        let changed = new != mode
        mode = new
        searchEditor.placeholder = placeholder
        searchEditor.accessibilityLabel = placeholder
        for (i, b) in modeButtons.enumerated() {
            b.tintColor = i == new.rawValue ? Glass.textPrimary : Glass.textSecondary
            b.accessibilityTraits = i == new.rawValue ? [.button, .selected] : .button
        }
        buildChips()
        switch new {
        case .emoji:
            feedTask?.cancel()
            statusText = nil
            spinner.stopAnimating()
            attributionLabel.text = nil
            highlightTab(currentCategory)
        case .stickers, .gifs:
            // What is set up decides the chips and the field's words, so
            // ask the server first (once an hour at most).
            feedTask?.cancel()
            feed = Feed(key: "", title: "")
            reloadMedia()
            statusText = nil
            attributionLabel.text = nil
            spinner.startAnimating()
            MediaClient.shared.loadConfig { [weak self] _ in
                guard let self, self.mode == new else { return }
                self.spinner.stopAnimating()
                self.searchEditor.placeholder = self.placeholder
                self.searchEditor.accessibilityLabel = self.placeholder
                self.buildChips()
                self.selectChip(self.selectedChip[new] ?? "trending")
            }
        case .emoticons:
            feedTask?.cancel()
            spinner.stopAnimating()
            attributionLabel.text = nil
            selectChip(selectedChip[new] ?? (EmoticonRecents.load().isEmpty ? "classic" : "recents"))
        }
        if changed { MemoryLogger.logSurface("emoji:\(new.name)") }
        setNeedsLayout()
        if animated { UIView.animate(withDuration: Glass.motion) { self.layoutIfNeeded() } }
    }

    // MARK: Emoji tabs

    private func buildTabs() {
        let symbols = ["clock"] + EmojiData.categories.map(\.symbol)
        for (i, symbol) in symbols.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.setPreferredSymbolConfiguration(.init(pointSize: 16, weight: .light), forImageIn: .normal)
            b.tintColor = Glass.textSecondary
            b.accessibilityIdentifier = "emoji:tab:\(i)"
            b.addAction(UIAction { [weak self] _ in self?.jump(to: i) }, for: .touchUpInside)
            tabs.addArrangedSubview(b)
        }
    }

    /// A category button: straight to the start of its section.
    private func jump(to section: Int) {
        dismissTonePopup()
        guard section < sections.count, collection.numberOfItems(inSection: section) > 0 else { return }
        collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: false)
        highlightTab(section)
    }

    /// Apple rings the category you are in with a soft circle.
    private func highlightTab(_ section: Int) {
        currentCategory = section
        guard mode == .emoji else { return }
        let views = tabs.arrangedSubviews
        guard views.indices.contains(section) else { return }
        for (i, v) in views.enumerated() {
            (v as? UIButton)?.tintColor = i == section ? Glass.textPrimary : Glass.textSecondary
        }
        let frame = tabs.convert(views[section].frame, to: self)
        let d = min(frame.height, 30)
        tabThumb.frame = CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
        tabThumb.layer.cornerRadius = d / 2
        if !searchActive {
            sectionLabel.text = sections.indices.contains(section) ? sections[section].title : nil
        }
    }

    // MARK: Media and emoticon chips

    private func buildChips() {
        chipButtons.forEach { $0.removeFromSuperview() }
        chipButtons = []
        for chip in chips(for: mode) {
            let b = UIButton(type: .system)
            if let symbol = chip.symbol {
                b.setImage(UIImage(systemName: symbol), for: .normal)
                b.setPreferredSymbolConfiguration(.init(pointSize: 16, weight: .light), forImageIn: .normal)
            } else if let glyph = chip.glyph {
                b.setTitle(glyph, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 21)
            } else {
                b.setTitle(chip.title, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 15)
            }
            b.tintColor = Glass.textSecondary
            b.setTitleColor(Glass.textSecondary, for: .normal)
            b.accessibilityLabel = chip.label
            b.accessibilityIdentifier = "emoji:chip:\(chip.id)"
            b.addAction(UIAction { [weak self] _ in self?.selectChip(chip.id) }, for: .touchUpInside)
            chipBar.addSubview(b)
            chipButtons.append(b)
        }
        layoutChips()
    }

    private func layoutChips() {
        let h = chipBar.bounds.height
        var x: CGFloat = 0
        for (b, chip) in zip(chipButtons, chips(for: mode)) {
            let w: CGFloat
            if chip.title != nil {
                w = ceil(b.intrinsicContentSize.width) + 20
            } else {
                w = 34
            }
            b.frame = CGRect(x: x, y: 0, width: w, height: h)
            x += w + (chip.title != nil ? 2 : 1)
        }
        chipBar.contentSize = CGSize(width: x, height: h)
        placeChipThumb()
    }

    private func placeChipThumb() {
        let list = chips(for: mode)
        let chosen = selectedChip[mode].flatMap { id in list.firstIndex { $0.id == id } }
        for (j, b) in chipButtons.enumerated() {
            let on = j == chosen
            b.tintColor = on ? Glass.textPrimary : Glass.textSecondary
            b.setTitleColor(on ? Glass.textPrimary : Glass.textSecondary, for: .normal)
            b.accessibilityTraits = on ? [.button, .selected] : .button
        }
        guard let i = chosen, chipButtons.indices.contains(i) else {
            chipThumb.isHidden = true
            return
        }
        chipThumb.isHidden = false
        let frame = chipButtons[i].frame
        let d = min(frame.height, 30)
        chipThumb.frame = list[i].title != nil
            ? CGRect(x: frame.minX, y: frame.midY - d / 2, width: frame.width, height: d)
            : CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
        chipThumb.layer.cornerRadius = d / 2
        chipBar.scrollRectToVisible(frame.insetBy(dx: -40, dy: 0), animated: false)
    }

    /// A chip on the bottom bar: the recents, trending, or a feeling.
    private func selectChip(_ id: String) {
        guard let chip = chips(for: mode).first(where: { $0.id == id }) else { return }
        selectedChip[mode] = id
        placeChipThumb()
        switch mode {
        case .emoticons:
            emoticonItems = id == "recents" ? EmoticonRecents.load() : EmoticonData.items(of: id)
            sectionLabel.text = chip.label.uppercased()
            statusText = emoticonItems.isEmpty ? "Emoticons you send show up here" : nil
            emoticonGrid.reloadData()
            emoticonGrid.setContentOffset(.zero, animated: false)
        case .gifs, .stickers:
            load(chip: chip)
        case .emoji:
            break
        }
        setNeedsLayout()
    }

    // MARK: Media feeds

    /// A chip's feed: its recents, trending, or the feeling it searches.
    private func load(chip: Chip) {
        let source = source(for: chip)
        let title: String
        if chip.query == nil {
            title = "RECENTLY USED"
        } else if chip.query?.isEmpty == true {
            title = chip.noto ? "ANIMATED EMOJI" : (source == .klipy ? "TRENDING" : "POPULAR")
        } else {
            title = chip.label.uppercased()
        }
        load(title: title, key: chip.id, query: chip.query, source: source)
    }

    /// Recents (nil query), trending ("") or a search, from one source.
    private func load(title: String, key: String, query: String?, source: MediaSource) {
        guard let kind = mode.kind else { return }
        feedTask?.cancel()
        feed = Feed(key: key, title: title, source: source, query: query, loading: true)
        sectionLabel.text = title
        attributionLabel.text = nil
        reloadMedia()
        // Noto's recents live on this phone: no network, no Full Access.
        if query == nil, source == .noto {
            feed.loading = false
            feed.items = MediaRecents.load(kind)
            statusText = feed.items.isEmpty ? "Stickers you send show up here" : nil
            spinner.stopAnimating()
            reloadMedia()
            return
        }
        guard delegate?.emojiBoardHasFullAccess ?? false else {
            feed.loading = false
            statusText = kind == .gifs
                ? "Turn on Full Access to send GIFs\nSettings › Apps › Glyf › Keyboards"
                : "Turn on Full Access to send stickers\nSettings › Apps › Glyf › Keyboards"
            return
        }
        if source == .klipy, MediaClient.shared.config?.klipy == nil {
            feed.loading = false
            spinner.stopAnimating()
            statusText = "GIFs aren't set up yet"
            return
        }
        statusText = nil
        spinner.startAnimating()
        let done: (Result<MediaPage, MediaClient.Failure>) -> Void = { [weak self] result in
            guard let self, self.feed.key == key, self.mode.kind == kind else { return }
            self.spinner.stopAnimating()
            self.feed.loading = false
            switch result {
            case .success(let page):
                self.feed.items = page.items
                self.feed.next = page.next
                self.attributionLabel.text = page.attribution
                let noun = kind == .gifs ? "GIFs" : "stickers"
                if page.items.isEmpty {
                    switch query {
                    case nil: self.statusText = "\(noun.prefix(1).uppercased() + noun.dropFirst()) you send show up here"
                    case let q? where q.isEmpty: self.statusText = "Nothing here right now"
                    case let q?: self.statusText = "No \(noun) for “\(q)”"
                    }
                } else {
                    self.statusText = nil
                }
            case .failure(.unavailable):
                self.statusText = "GIFs aren't set up yet"
            case .failure(.offline):
                self.statusText = "Couldn't load. Check the connection and tap to try again"
            }
            self.reloadMedia()
        }
        if query == nil {
            feedTask = MediaClient.shared.recent(kind, completion: done)
        } else {
            feedTask = MediaClient.shared.page(kind, source: source, query: query ?? "", completion: done)
        }
    }

    private func loadMore() {
        guard let kind = mode.kind, !feed.loading, let next = feed.next else { return }
        feed.loading = true
        let key = feed.key
        let apply: (Result<MediaPage, MediaClient.Failure>) -> Void = { [weak self] result in
            guard let self, self.feed.key == key, self.mode.kind == kind else { return }
            self.feed.loading = false
            guard case .success(let page) = result else { return }
            let known = Set(self.feed.items.map(\.id))
            let fresh = page.items.filter { !known.contains($0.id) }
            self.feed.next = fresh.isEmpty ? nil : page.next
            guard !fresh.isEmpty else { return }
            let start = self.feed.items.count
            self.feed.items += fresh
            let paths = (start..<self.feed.items.count).map { IndexPath(item: $0, section: 0) }
            self.mediaGrid.insertItems(at: paths)
        }
        if let query = feed.query {
            feedTask = MediaClient.shared.page(kind, source: feed.source, query: query,
                                               page: next, completion: apply)
        } else if feed.source == .klipy {
            feedTask = MediaClient.shared.recent(kind, page: next, completion: apply)
        } else {
            feed.loading = false
        }
    }

    private func reloadMedia() {
        masonry.columns = mode == .stickers ? 4 : 2
        masonry.spacing = mode == .stickers ? 0 : 6
        sendingIndex = nil
        mediaGrid.reloadData()
        mediaGrid.setContentOffset(.zero, animated: false)
    }

    /// A tap on the message line under an error tries again.
    @objc private func statusTapped() {
        guard mode.kind != nil, !feed.loading, !feed.key.isEmpty else { return }
        load(title: feed.title, key: feed.key, query: feed.query, source: feed.source)
    }

    // MARK: Search

    private func queryChanged(_ q: String) {
        switch mode {
        case .emoji:
            if q.isEmpty {
                // In strip mode an empty query falls back to recents so the
                // row is never blank; in grid mode it clears the filter.
                searchResults = searchActive ? Self.loadRecents() : nil
            } else {
                searchResults = EmojiData.search(q)
            }
            reload()
        case .gifs, .stickers:
            suggestWork?.cancel()
            suggestTask?.cancel()
            let typed = q.trimmingCharacters(in: .whitespaces)
            showSuggestions(typed.isEmpty ? [] : [typed])
            // KLIPY completes a search; Noto's fixed set has nothing to add.
            guard !typed.isEmpty, source(for: nil) == .klipy,
                  delegate?.emojiBoardHasFullAccess ?? false else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.suggestTask = MediaClient.shared.suggest(query: typed) { [weak self] terms in
                    guard let self, self.searchEditor.text.trimmingCharacters(in: .whitespaces) == typed
                    else { return }
                    var seen = Set<String>()
                    let list = ([typed] + terms).filter { seen.insert($0.lowercased()).inserted }
                    self.showSuggestions(Array(list.prefix(8)))
                }
            }
            suggestWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        case .emoticons:
            let typed = q.trimmingCharacters(in: .whitespaces).lowercased()
            let hits = typed.isEmpty ? EmoticonRecents.load()
                : EmoticonData.categories.filter { $0.title.lowercased().hasPrefix(typed) }
                    .flatMap(\.items)
            showSuggestions(Array(hits.prefix(24)), emoticons: true)
        }
    }

    /// The strip's second row outside emoji: terms to search, or emoticons.
    private func showSuggestions(_ items: [String], emoticons: Bool = false) {
        suggestionBar.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 8
        let h: CGFloat = 36
        for (i, text) in items.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(text, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: i == 0 && !emoticons ? .semibold : .regular)
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.backgroundColor = Glass.surfaceCard
            b.layer.cornerRadius = h / 2
            b.layer.cornerCurve = .continuous
            b.accessibilityIdentifier = "emoji:suggestion:\(i)"
            b.addAction(UIAction { [weak self] _ in
                if emoticons { self?.typeEmoticon(text) } else { self?.runSearch(text) }
            }, for: .touchUpInside)
            let w = ceil(b.intrinsicContentSize.width) + 26
            b.frame = CGRect(x: x, y: 0, width: w, height: h)
            suggestionBar.addSubview(b)
            x += w + 6
        }
        suggestionBar.contentSize = CGSize(width: x + 2, height: h)
        suggestionBar.setContentOffset(.zero, animated: false)
    }

    /// Return, or a suggestion: search and show the results as the board.
    private func runSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, mode.kind != nil else { exitSearch(); return }
        leaveStrip()
        selectedChip[mode] = nil
        placeChipThumb()
        load(title: "“\(q)”".uppercased(), key: "q:\(q.lowercased())", query: q,
             source: source(for: nil))
    }

    /// The return key while the strip is up.
    func returnPressed() {
        switch mode {
        case .gifs, .stickers: runSearch(searchEditor.text)
        default: exitSearch()
        }
    }

    @objc private func searchTapped() {
        searchEditor.isActive = true
        if !searchActive {
            searchActive = true
            switch mode {
            case .emoji:
                // Empty query shows recents in the strip right away.
                if searchResults == nil { searchResults = Self.loadRecents() }
                reload()
            case .emoticons:
                queryChanged(searchEditor.text)
            case .gifs, .stickers:
                showSuggestions([])
            }
            abcButton.isHidden = false
            tabs.isHidden = true
            setNeedsLayout()
            delegate?.emojiLayoutChanged()
        }
        delegate?.emojiSearchActivated(searchEditor)
    }

    /// Back to the full board with the field cleared; the grid keeps what
    /// it was showing.
    private func leaveStrip() {
        guard searchActive else { return }
        searchActive = false
        searchEditor.isActive = false
        searchEditor.clear()
        suggestWork?.cancel()
        suggestTask?.cancel()
        abcButton.isHidden = true
        setNeedsLayout()
        delegate?.emojiSearchDismissed()
        delegate?.emojiLayoutChanged()
    }

    /// ABC / return: back to the full grid (search cleared, like Apple's).
    func exitSearch() {
        guard searchActive else { return }
        searchResults = nil
        leaveStrip()
        if mode == .emoji { reload() }
    }

    func deactivateSearch() { searchEditor.isActive = false }

    // MARK: Recents

    static func loadRecents() -> [String] {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(recentsKey)),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return ["😂", "❤️", "👍", "🙏", "😊", "🔥", "🎉", "😍"] }
        return list
    }

    static func pushRecent(_ e: String) {
        var list = loadRecents().filter { $0 != e }
        list.insert(e, at: 0)
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONEncoder().encode(Array(list.prefix(32))) else { return }
        try? data.write(to: dir.appendingPathComponent(recentsKey), options: .atomic)
    }

    private func reload() {
        sections = [("FREQUENTLY USED", Self.loadRecents())] + EmojiData.categories.map {
            (Self.sectionTitles[$0.id] ?? $0.id.uppercased(), $0.emoji)
        }
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    // MARK: Collections

    func numberOfSections(in cv: UICollectionView) -> Int {
        if cv === mediaGrid || cv === emoticonGrid { return 1 }
        return searchResults != nil ? 1 : sections.count
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int {
        if cv === mediaGrid { return feed.items.count }
        if cv === emoticonGrid { return emoticonItems.count }
        if let results = searchResults { return results.count }
        return sections.indices.contains(s) ? sections[s].emoji.count : 0
    }

    private func emoji(at ip: IndexPath) -> String {
        if let results = searchResults { return results[ip.item] }
        return sections[ip.section].emoji[ip.item]
    }

    func collectionView(_ cv: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if cv === mediaGrid {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "m", for: indexPath) as! MediaCell
            cell.configure(feed.items[indexPath.item], sticker: mode == .stickers)
            cell.accessibilityIdentifier = "emoji:media:\(indexPath.item)"
            cell.setSending(sendingIndex == indexPath.item)
            return cell
        }
        if cv === emoticonGrid {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "t", for: indexPath) as! EmoticonCell
            let text = emoticonItems[indexPath.item]
            cell.label.text = text
            cell.label.textColor = Glass.textPrimary
            cell.accessibilityLabel = text
            cell.accessibilityIdentifier = "emoji:emoticon:\(indexPath.item)"
            return cell
        }
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.label.text = emoji(at: indexPath)
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dismissTonePopup()
        if cv === mediaGrid { send(at: indexPath); return }
        if cv === emoticonGrid { typeEmoticon(emoticonItems[indexPath.item]); return }
        pick(emoji(at: indexPath))
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // The emoji grid keeps the size its layout was given; emoticons go
        // three to a row, a thumb's height.
        guard cv === emoticonGrid else {
            return (layout as? UICollectionViewFlowLayout)?.itemSize ?? .zero
        }
        let width = cv.bounds.width - 16
        return CGSize(width: floor(width / 3), height: 46)
    }

    private func send(at ip: IndexPath) {
        guard let kind = mode.kind, feed.items.indices.contains(ip.item), sendingIndex == nil else { return }
        let item = feed.items[ip.item]
        sendingIndex = ip.item
        (mediaGrid.cellForItem(at: ip) as? MediaCell)?.setSending(true)
        let query = feed.query
        delegate?.emojiBoardSend(item, kind: kind) { [weak self] sent in
            guard let self else { return }
            self.sendingIndex = nil
            for cell in self.mediaGrid.visibleCells { (cell as? MediaCell)?.setSending(false) }
            // KLIPY counts a send toward trending and this install's recents.
            if sent, item.slug != nil {
                MediaClient.shared.reportShare(item, kind: kind, query: query)
            }
        }
    }

    private func typeEmoticon(_ text: String) {
        EmoticonRecents.push(text)
        delegate?.emojiBoardType(text)
    }

    /// The tone popup only means something over the emoji it came from: a
    /// tap anywhere else, a category jump or a scroll puts it away.
    private func dismissTonePopup() {
        tonePopup?.removeFromSuperview()
        tonePopup = nil
    }

    private func pick(_ e: String) {
        Self.pushRecent(e)
        delegate?.emojiPicked(e)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === mediaGrid {
            let remaining = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
            if remaining < 240 { loadMore() }
            return
        }
        if scrollView === collection, tonePopup != nil { dismissTonePopup() }
        guard !searchActive, scrollView === collection, mode == .emoji else { return }
        // The section under the left edge names the grid, as Apple's does.
        let probe = CGPoint(x: scrollView.contentOffset.x + 24, y: 20)
        if let ip = collection.indexPathForItem(at: probe), ip.section != currentCategory {
            highlightTab(ip.section)
        }
    }

    // MARK: Skin tones (long-press)

    @objc private func cellLong(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            let p = g.location(in: collection)
            guard let ip = collection.indexPathForItem(at: p) else { return }
            let base = emoji(at: ip)
            let variants = EmojiData.variants(of: base)
            guard variants.count > 1, let cell = collection.cellForItem(at: ip) else { return }
            showTonePopup(variants, over: collection.convert(cell.frame, to: self))
        case .ended, .cancelled:
            break
        default:
            break
        }
    }

    private func showTonePopup(_ variants: [String], over rect: CGRect) {
        tonePopup?.removeFromSuperview()
        let pop = UIView()
        pop.backgroundColor = Glass.surfaceCard
        pop.layer.cornerRadius = 12
        pop.layer.cornerCurve = .continuous
        pop.layer.shadowOpacity = 0.25
        pop.layer.shadowRadius = 8
        pop.layer.shadowOffset = CGSize(width: 0, height: 3)
        let w = CGFloat(variants.count) * 40 + 8
        var x = rect.midX - w / 2
        x = max(4, min(x, bounds.width - w - 4))
        pop.frame = CGRect(x: x, y: max(2, rect.minY - 50), width: w, height: 44)
        for (i, v) in variants.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(v, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 26)
            b.frame = CGRect(x: 4 + CGFloat(i) * 40, y: 2, width: 40, height: 40)
            b.addAction(UIAction { [weak self] _ in
                self?.tonePopup?.removeFromSuperview()
                self?.tonePopup = nil
                self?.pick(v)
            }, for: .touchUpInside)
            pop.addSubview(b)
        }
        addSubview(pop)
        tonePopup = pop
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout
        let isEmoji = mode == .emoji
        if searchActive {
            // Strip mode: [ABC][field][x] + one row (emoji, search terms or
            // emoticons); the letter keys live below this view.
            abcButton.frame = CGRect(x: 6, y: 6, width: 44, height: 32)
            searchEditor.frame = CGRect(x: 54, y: 6, width: bounds.width - 96, height: 32)
            closeButton.isHidden = false
            closeButton.frame = CGRect(x: bounds.width - 40, y: 6, width: 32, height: 32)
            collection.isHidden = !isEmoji
            collection.frame = CGRect(x: 8, y: 46, width: bounds.width - 16, height: 44)
            suggestionBar.isHidden = isEmoji
            suggestionBar.frame = CGRect(x: 0, y: 50, width: bounds.width, height: 36)
            for v in [sectionLabel, attributionLabel, lettersButton, deleteButton, tabThumb, tabs,
                      chipFade, modeBar, statusLabel] as [UIView] { v.isHidden = true }
            mediaGrid.isHidden = true
            emoticonGrid.isHidden = true
            spinner.isHidden = true
            if isEmoji, flow?.itemSize != CGSize(width: 44, height: 44) {
                flow?.itemSize = CGSize(width: 44, height: 44); flow?.invalidateLayout()
            }
            return
        }

        // Apple's: the search field across the top (here with the mode
        // glyphs at its end), no close button (ABC is the way back), the
        // section name, the grid, the bottom bar.
        closeButton.isHidden = true
        suggestionBar.isHidden = true
        modeBar.isHidden = false
        let modeW: CGFloat = 4 * 32 + 3 * 2
        // The field ends where it always has, so the section name and the
        // five rows stay on Apple's lines (measured: within 1pt of iOS 26).
        let fieldY: CGFloat = 4, fieldH: CGFloat = 36
        searchEditor.frame = CGRect(x: 8, y: fieldY, width: bounds.width - 16 - modeW - 8, height: fieldH)
        modeBar.frame = CGRect(x: bounds.width - 8 - modeW, y: fieldY + (fieldH - 32) / 2,
                               width: modeW, height: 32)
        for (i, b) in modeButtons.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * 34, y: 0, width: 32, height: 32)
        }
        if modeButtons.indices.contains(mode.rawValue) {
            modeThumb.frame = modeButtons[mode.rawValue].frame
            modeThumb.layer.cornerRadius = 16
        }

        sectionLabel.isHidden = false
        attributionLabel.isHidden = mode.kind == nil
        let labelY = fieldY + fieldH + 4
        attributionLabel.frame = CGRect(x: bounds.width / 2, y: labelY, width: bounds.width / 2 - 14, height: 16)
        sectionLabel.frame = CGRect(x: 14, y: labelY,
                                    width: bounds.width - 28 - (attributionLabel.isHidden ? 0 : bounds.width / 2 - 14),
                                    height: 16)
        let barY = bounds.height - 36
        lettersButton.isHidden = false
        deleteButton.isHidden = false
        lettersButton.frame = CGRect(x: 4, y: barY, width: 46, height: 34)
        deleteButton.frame = CGRect(x: bounds.width - 48, y: barY, width: 44, height: 34)
        let barRect = CGRect(x: 54, y: barY, width: bounds.width - 108, height: 34)
        let gridTop = labelY + 20
        let gridRect = CGRect(x: 0, y: gridTop, width: bounds.width, height: max(0, barY - gridTop - 2))

        tabs.isHidden = !isEmoji
        tabThumb.isHidden = !isEmoji
        collection.isHidden = !isEmoji
        chipFade.isHidden = isEmoji
        mediaGrid.isHidden = mode.kind == nil
        emoticonGrid.isHidden = mode != .emoticons
        statusLabel.isHidden = isEmoji || statusText == nil
        // Only ever a running spinner: un-hiding a stopped one draws its
        // spokes, frozen, in the middle of the grid.
        spinner.isHidden = !spinner.isAnimating

        if isEmoji {
            tabs.frame = barRect
            collection.frame = gridRect.insetBy(dx: 4, dy: 0)
            let rowH = floor(collection.bounds.height / 5)
            let size = CGSize(width: 47, height: rowH)
            if flow?.itemSize != size { flow?.itemSize = size; flow?.invalidateLayout() }
            highlightTab(currentCategory)
        } else {
            if chipFade.frame != barRect {
                chipFade.frame = barRect
                chipBar.frame = chipFade.bounds
                chipFadeMask.frame = chipFade.bounds
                let edge = NSNumber(value: Double(10 / max(barRect.width, 1)))
                chipFadeMask.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
                layoutChips()
            }
            mediaGrid.frame = gridRect
            emoticonGrid.frame = gridRect
            statusLabel.frame = gridRect.insetBy(dx: 28, dy: 10)
            spinner.center = CGPoint(x: gridRect.midX, y: gridRect.midY)
            if statusLabel.gestureRecognizers?.isEmpty ?? true {
                statusLabel.isUserInteractionEnabled = true
                statusLabel.addGestureRecognizer(
                    UITapGestureRecognizer(target: self, action: #selector(statusTapped)))
            }
        }
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}
