import UIKit

protocol EmojiBoardDelegate: AnyObject {
    func emojiPicked(_ emoji: String)
    func emojiBoardClosed()
    func emojiSearchActivated(_ editor: InlineEditor)
    /// Search opened/closed — the board collapses to a strip so the LETTER
    /// KEYS can show underneath (Apple/Gboard behavior).
    func emojiLayoutChanged()
    func emojiSearchDismissed()
}

/// §6.1 emoji keyboard: recents, search, categories, long-press skin tones.
/// One UICollectionView with cell reuse; text-only cells (no images — memory).
final class EmojiBoard: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    weak var delegate: EmojiBoardDelegate?

    private let searchEditor = InlineEditor(placeholder: "Search emoji")
    private let closeButton = UIButton(type: .system)
    private let abcButton = UIButton(type: .system)
    /// While true the board is a strip (field + one result row) and the
    /// keyboard's letter keys are visible below it.
    private(set) var searchActive = false
    /// Strip height in search mode (field row + results row).
    static let searchStripHeight: CGFloat = 96
    private var collection: UICollectionView!
    private let tabs = UIStackView()
    private var currentEmoji: [String] = []
    private var currentCategory = 0
    private var searchResults: [String]?
    private var tonePopup: UIView?

    static let recentsKey = "emoji-recents.json"

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear

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

        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 38, height: 38)
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 4
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        let long = UILongPressGestureRecognizer(target: self, action: #selector(cellLong(_:)))
        long.minimumPressDuration = 0.35
        collection.addGestureRecognizer(long)
        addSubview(collection)

        tabs.axis = .horizontal
        tabs.distribution = .fillEqually
        addSubview(tabs)
        buildTabs()
        selectCategory(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildTabs() {
        let recents = UIButton(type: .system)
        recents.setImage(UIImage(systemName: "clock"), for: .normal)
        recents.tintColor = Glass.textSecondary
        recents.addAction(UIAction { [weak self] _ in self?.selectCategory(-1) }, for: .touchUpInside)
        tabs.addArrangedSubview(recents)
        for (i, cat) in EmojiData.categories.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: cat.symbol), for: .normal)
            b.tintColor = Glass.textSecondary
            b.addAction(UIAction { [weak self] _ in self?.selectCategory(i) }, for: .touchUpInside)
            tabs.addArrangedSubview(b)
        }
    }

    private func selectCategory(_ idx: Int) {
        currentCategory = idx
        searchResults = nil
        searchEditor.clear()
        for (i, v) in tabs.arrangedSubviews.enumerated() {
            (v as? UIButton)?.tintColor = (i == idx + 1) ? Glass.accentPrimary : Glass.textSecondary
        }
        reload()
    }

    private func reload() {
        if let results = searchResults {
            currentEmoji = results
        } else if currentCategory == -1 {
            currentEmoji = Self.loadRecents()
        } else {
            currentEmoji = EmojiData.categories[currentCategory].emoji
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
            (collection.collectionViewLayout as? UICollectionViewFlowLayout)?
                .scrollDirection = .horizontal
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
        (collection.collectionViewLayout as? UICollectionViewFlowLayout)?
            .scrollDirection = .vertical
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

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int {
        currentEmoji.count
    }

    func collectionView(_ cv: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.label.text = currentEmoji[indexPath.item]
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        pick(currentEmoji[indexPath.item])
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
            let base = currentEmoji[ip.item]
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
        pop.backgroundColor = Glass.reduceTransparency ? Glass.solidKey : Glass.fillKeyPressed
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
        if searchActive {
            // Strip mode: [ABC][field][x] + one horizontal result row; the
            // letter keys live below this view.
            abcButton.frame = CGRect(x: 6, y: 6, width: 44, height: 32)
            searchEditor.frame = CGRect(x: 54, y: 6, width: bounds.width - 96, height: 32)
            closeButton.frame = CGRect(x: bounds.width - 40, y: 6, width: 32, height: 32)
            collection.frame = CGRect(x: 8, y: 46, width: bounds.width - 16, height: 44)
        } else {
            searchEditor.frame = CGRect(x: 8, y: 6, width: bounds.width - 52, height: 32)
            closeButton.frame = CGRect(x: bounds.width - 40, y: 6, width: 32, height: 32)
            tabs.frame = CGRect(x: 4, y: bounds.height - 38, width: bounds.width - 8, height: 34)
            collection.frame = CGRect(x: 8, y: 44, width: bounds.width - 16,
                                      height: bounds.height - 44 - 40)
        }
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 28)
        label.textAlignment = .center
        contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}
