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
}

/// §6.1 emoji keyboard, laid out like Apple's: Search Emoji on top, then one
/// grid five rows tall that pages left and right through every section, the
/// section's name above it, and ABC · categories · delete along the bottom.
/// One UICollectionView with cell reuse; text-only cells (no images — memory).
final class EmojiBoard: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    weak var delegate: EmojiBoardDelegate?

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
    private var collection: UICollectionView!
    private let tabs = UIStackView()
    private let tabThumb = UIView()
    private let sectionLabel = UILabel()
    /// Frequently used, then every category, as one horizontal run.
    private var sections: [(title: String, emoji: [String])] = []
    private var currentCategory = 0
    private var searchResults: [String]?
    private var tonePopup: UIView?

    static let recentsKey = "emoji-recents.json"

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        searchEditor.onChange = { [weak self] q in
            guard let self else { return }
            if q.isEmpty {
                // In strip mode an empty query falls back to recents so the
                // row is never blank; in grid mode it clears the filter.
                self.searchResults = self.searchActive ? Self.loadRecents() : nil
            } else {
                self.searchResults = EmojiData.search(q)
            }
            self.reload()
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(searchTapped))
        searchEditor.addGestureRecognizer(tap)
        searchEditor.isAccessibilityElement = true
        searchEditor.accessibilityIdentifier = "emoji:search"
        searchEditor.accessibilityLabel = "Search emoji"
        addSubview(searchEditor)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "emoji:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.emojiBoardClosed() },
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

        sectionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sectionLabel.textColor = Glass.textSecondary
        addSubview(sectionLabel)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(cellLong(_:)))
        long.minimumPressDuration = 0.35
        collection.addGestureRecognizer(long)
        addSubview(collection)

        lettersButton.setTitle("ABC", for: .normal)
        lettersButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        lettersButton.setTitleColor(Glass.textPrimary, for: .normal)
        lettersButton.accessibilityIdentifier = "emoji:letters"
        lettersButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.emojiBackToLetters()
        }, for: .touchUpInside)
        addSubview(lettersButton)

        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.tintColor = Glass.textPrimary
        deleteButton.accessibilityIdentifier = "emoji:delete"
        deleteButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.emojiDeleteBackward()
        }, for: .touchUpInside)
        addSubview(deleteButton)

        tabThumb.backgroundColor = Glass.textPrimary.withAlphaComponent(Glass.isDark ? 0.18 : 0.10)
        addSubview(tabThumb)
        tabs.axis = .horizontal
        tabs.distribution = .fillEqually
        addSubview(tabs)
        buildTabs()
        reload()
        highlightTab(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let sectionTitles = [
        "smileys": "SMILEYS & PEOPLE", "people": "PEOPLE", "animals": "ANIMALS & NATURE",
        "food": "FOOD & DRINK", "activity": "ACTIVITY", "travel": "TRAVEL & PLACES",
        "objects": "OBJECTS", "symbols": "SYMBOLS", "flags": "FLAGS",
    ]

    private func buildTabs() {
        let symbols = ["clock"] + EmojiData.categories.map(\.symbol)
        for (i, symbol) in symbols.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.setPreferredSymbolConfiguration(.init(pointSize: 15, weight: .regular), forImageIn: .normal)
            b.tintColor = Glass.textSecondary
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
        let views = tabs.arrangedSubviews
        guard views.indices.contains(section) else { return }
        for (i, v) in views.enumerated() {
            (v as? UIButton)?.tintColor = i == section ? Glass.textPrimary : Glass.textSecondary
        }
        let frame = tabs.convert(views[section].frame, to: self)
        let d = min(frame.height, 30)
        tabThumb.frame = CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
        tabThumb.layer.cornerRadius = d / 2
        sectionLabel.text = sections.indices.contains(section) ? sections[section].title : nil
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === collection, tonePopup != nil { dismissTonePopup() }
        guard !searchActive, scrollView === collection else { return }
        // The section under the left edge names the grid, as Apple's does.
        let probe = CGPoint(x: scrollView.contentOffset.x + 24, y: 20)
        if let ip = collection.indexPathForItem(at: probe), ip.section != currentCategory {
            highlightTab(ip.section)
        }
    }

    private func reload() {
        sections = [("FREQUENTLY USED", Self.loadRecents())] + EmojiData.categories.map {
            (Self.sectionTitles[$0.id] ?? $0.id.uppercased(), $0.emoji)
        }
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    @objc private func searchTapped() {
        searchEditor.isActive = true
        if !searchActive {
            searchActive = true
            // Empty query shows recents in the strip right away.
            if searchResults == nil { searchResults = Self.loadRecents() }
            abcButton.isHidden = false
            tabs.isHidden = true
            reload()
            setNeedsLayout()
            delegate?.emojiLayoutChanged()
        }
        delegate?.emojiSearchActivated(searchEditor)
    }

    /// ABC / return: back to the full grid (search cleared, like Apple's).
    func exitSearch() {
        guard searchActive else { return }
        searchActive = false
        searchEditor.isActive = false
        searchEditor.clear()
        searchResults = nil
        abcButton.isHidden = true
        tabs.isHidden = false
        reload()
        setNeedsLayout()
        delegate?.emojiSearchDismissed()
        delegate?.emojiLayoutChanged()
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

    // MARK: Collection

    func numberOfSections(in cv: UICollectionView) -> Int {
        searchResults != nil ? 1 : sections.count
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int {
        if let results = searchResults { return results.count }
        return sections.indices.contains(s) ? sections[s].emoji.count : 0
    }

    private func emoji(at ip: IndexPath) -> String {
        if let results = searchResults { return results[ip.item] }
        return sections[ip.section].emoji[ip.item]
    }

    func collectionView(_ cv: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.label.text = emoji(at: indexPath)
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dismissTonePopup()
        pick(emoji(at: indexPath))
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout
        if searchActive {
            // Strip mode: [ABC][field][x] + one horizontal result row; the
            // letter keys live below this view.
            abcButton.frame = CGRect(x: 6, y: 6, width: 44, height: 32)
            searchEditor.frame = CGRect(x: 54, y: 6, width: bounds.width - 96, height: 32)
            closeButton.isHidden = false
            closeButton.frame = CGRect(x: bounds.width - 40, y: 6, width: 32, height: 32)
            collection.frame = CGRect(x: 8, y: 46, width: bounds.width - 16, height: 44)
            sectionLabel.isHidden = true
            lettersButton.isHidden = true
            deleteButton.isHidden = true
            tabThumb.isHidden = true
            if flow?.itemSize != CGSize(width: 44, height: 44) {
                flow?.itemSize = CGSize(width: 44, height: 44); flow?.invalidateLayout()
            }
        } else {
            // Apple's: the search field across the top, no close button (ABC
            // is the way back), the section name, five rows, the bottom bar.
            closeButton.isHidden = true
            searchEditor.frame = CGRect(x: 8, y: 6, width: bounds.width - 16, height: 34)
            sectionLabel.isHidden = false
            sectionLabel.frame = CGRect(x: 14, y: 44, width: bounds.width - 28, height: 16)
            let barY = bounds.height - 36
            lettersButton.isHidden = false
            deleteButton.isHidden = false
            tabThumb.isHidden = false
            lettersButton.frame = CGRect(x: 4, y: barY, width: 46, height: 34)
            deleteButton.frame = CGRect(x: bounds.width - 48, y: barY, width: 44, height: 34)
            tabs.frame = CGRect(x: 54, y: barY, width: bounds.width - 108, height: 34)
            let gridTop: CGFloat = 64
            collection.frame = CGRect(x: 4, y: gridTop, width: bounds.width - 8,
                                      height: max(0, barY - gridTop - 2))
            let rowH = floor(collection.bounds.height / 5)
            let size = CGSize(width: 47, height: rowH)
            if flow?.itemSize != size { flow?.itemSize = size; flow?.invalidateLayout() }
            highlightTab(currentCategory)
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
