import UIKit

protocol SearchSurfaceDelegate: AnyObject {
    func searchActivated(_ editor: InlineEditor)
    func searchInsert(_ text: String)
    func searchOpenTranslate()
    func searchClosed()
    func searchLayoutChanged()
}

/// Gboard-style search suite (§6.12): chip tabs (Search / YouTube / Shorts /
/// Maps / Contacts / Translate), an inline query the keyboard types into, and rich
/// result cards that paste into the field. Typing: the search row and one
/// row of suggestion chips above the keys; once results land they take the
/// chips' and the keys' place (ABC returns). The keyboard is the same height
/// in every state, so nothing jumps while you search.
///
/// The card designs are the ones on tryglyf.com — an answer card with the sun
/// arc, video cards with thumbnail + duration badge, place cards with rating
/// and open-now. `SearchCard.kind` picks the cell. Shorts land on a sideways
/// shelf of tall 9:16 cards instead of the list.
final class SearchSurface: UIView, UITableViewDataSource, UITableViewDelegate {

    weak var delegate: SearchSurfaceDelegate?

    typealias Card = BackendClient.SearchCard

    enum Tab: String, CaseIterable {
        case web = "Search"
        case youtube = "YouTube"
        case shorts = "Shorts"
        case maps = "Maps"
        case contacts = "Contacts"
        case translate = "Translate"

        var icon: String {
            switch self {
            case .web: return "magnifyingglass"
            case .youtube: return "play.rectangle"
            case .shorts: return "play.rectangle"   // drawn upright: BrandMark.shortsTab
            case .maps: return "map"
            case .contacts: return "person.crop.circle"
            case .translate: return "character.bubble"
            }
        }

        /// The `/search` vertical; nil for tabs answered locally.
        var vertical: String? {
            switch self {
            case .web: return "web"
            case .youtube: return "yt"
            case .shorts: return "shorts"
            case .maps: return "maps"
            case .contacts, .translate: return nil
            }
        }
    }

    private(set) var tab: Tab = .web
    private(set) var expandedForResults = false
    /// Suggestions are showing and the KEYS STAY VISIBLE — you must be able
    /// to start typing over a suggestion, which is why this is a separate
    /// mode from `expandedForResults` (results do replace the keys).
    private(set) var landingActive = false
    /// The search row: close, tabs, query, go.
    static let rowHeight: CGFloat = 44
    /// One row of suggestions under it (recent and trending searches, or the
    /// contacts a name matches), side by side, so the keyboard never grows
    /// to fit them.
    static let chipsHeight: CGFloat = 40
    /// The strip over the keys while a query is typed.
    static var stripHeight: CGFloat { rowHeight + chipsHeight }
    /// What searching adds to the keyboard: the same in every state.
    static var extraHeight: CGFloat { max(0, stripHeight - Glass.toolbarHeight) }
    private var cards: [Card] = []
    /// The line under the query ("Searching…", "Nothing found", "Type a
    /// name"). It was laid out but never given its words (found 2026-09-30
    /// while capturing the Android parity reference).
    private var status = "" {
        didSet {
            statusLabel.text = status
            setNeedsLayout()
        }
    }
    /// Read and decoded once per search, not on every letter of a name.
    private lazy var contacts = AppGroupStore.readContacts()

    /// What the tour's coach needs to know about this surface.
    var coachView: TourCoach.SearchView {
        if expandedForResults { return .results(cards.count) }
        if status == "Searching…" { return .loading }
        return landingActive ? .landing(rows: cards.count) : .typing
    }

    private let closeButton = UIButton(type: .system)
    private let chipsRow = ControlScrollView()
    /// The website's tab track: a soft pill holding icon-only tabs with a
    /// key-coloured thumb that slides to the active one.
    private let tabTrack = UIView()
    private let tabThumb = UIView()
    private var chipButtons: [UIButton] = []
    let queryEditor = InlineEditor(placeholder: "Search…")
    private let goButton = UIButton(type: .system)
    private let abcButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let chipsRowView = ControlScrollView()
    private var suggestionChips: [UIButton] = []
    private let table = UITableView(frame: .zero, style: .plain)
    /// The Shorts tab's results: tall cards side by side, swiped through.
    private let shelf: UICollectionView = {
        let flow = UICollectionViewFlowLayout()
        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = 8
        flow.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        return UICollectionView(frame: .zero, collectionViewLayout: flow)
    }()
    private var showsShelf: Bool {
        expandedForResults && tab == .shorts && cards.contains { $0.kind == "short" }
    }
    private var task: URLSessionDataTask?
    private let hasFullAccess: Bool

    init(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.setPreferredSymbolConfiguration(.init(pointSize: 13, weight: .semibold),
                                                    forImageIn: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "search:close"
        closeButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.searchClosed()
        }, for: .touchUpInside)
        addSubview(closeButton)

        chipsRow.showsHorizontalScrollIndicator = false
        addSubview(chipsRow)
        tabTrack.backgroundColor = Glass.fillSoft
        tabTrack.layer.cornerCurve = .continuous
        chipsRow.addSubview(tabTrack)
        tabThumb.backgroundColor = Glass.surfaceCard
        tabThumb.layer.cornerCurve = .continuous
        tabThumb.layer.shadowColor = Glass.keyShadowColor.cgColor
        tabThumb.layer.shadowOpacity = Glass.keyShadowOpacity
        tabThumb.layer.shadowOffset = Glass.keyShadowOffset
        tabThumb.layer.shadowRadius = 0
        tabTrack.addSubview(tabThumb)
        for t in Tab.allCases {
            let b = UIButton(type: .system)
            var cfg = UIButton.Configuration.plain()
            // Neutral stroke marks, like the website: the vendors' own marks
            // belong on the result cards, not the tabs.
            cfg.image = t == .shorts ? BrandMark.shortsTab() : UIImage(systemName: t.icon)?
                .applyingSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10,
                                                        bottom: 6, trailing: 10)
            b.configuration = cfg
            b.accessibilityLabel = t.rawValue
            b.accessibilityIdentifier = "search:tab:\(t.rawValue.lowercased())"
            b.addAction(UIAction { [weak self] _ in self?.select(t) }, for: .touchUpInside)
            tabTrack.addSubview(b)
            chipButtons.append(b)
        }

        queryEditor.accessibilityIdentifier = "search:query"
        queryEditor.showsEnd = true
        queryEditor.onChange = { [weak self] t in self?.queryChanged(t) }
        addSubview(queryEditor)
        let tap = UITapGestureRecognizer(target: self, action: #selector(activateQuery))
        queryEditor.addGestureRecognizer(tap)

        goButton.setImage(UIImage(systemName: "arrow.forward.circle.fill"), for: .normal)
        goButton.tintColor = Glass.brandInk
        goButton.accessibilityIdentifier = "search:go"
        goButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        addSubview(goButton)

        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        abcButton.setTitleColor(Glass.textPrimary, for: .normal)
        abcButton.accessibilityIdentifier = "search:abc"
        abcButton.isHidden = true
        abcButton.addAction(UIAction { [weak self] _ in self?.collapse() }, for: .touchUpInside)
        addSubview(abcButton)

        statusLabel.font = .systemFont(ofSize: 12.5)
        statusLabel.textColor = Glass.textSecondary
        addSubview(statusLabel)

        chipsRowView.showsHorizontalScrollIndicator = false
        chipsRowView.alwaysBounceHorizontal = true
        addSubview(chipsRowView)

        table.backgroundColor = Glass.touchableGrid
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.showsVerticalScrollIndicator = false
        table.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 10, right: 0)
        table.register(AnswerCell.self, forCellReuseIdentifier: "answer")
        table.register(LinkCell.self, forCellReuseIdentifier: "link")
        table.register(VideoCell.self, forCellReuseIdentifier: "video")
        table.register(PlaceCell.self, forCellReuseIdentifier: "place")
        table.isHidden = true
        addSubview(table)
        table.noEdgeEffects()

        shelf.backgroundColor = Glass.touchableGrid
        shelf.showsHorizontalScrollIndicator = false
        shelf.alwaysBounceHorizontal = true
        shelf.dataSource = self
        shelf.delegate = self
        shelf.register(ShortCell.self, forCellWithReuseIdentifier: "short")
        shelf.accessibilityIdentifier = "search:shelf"
        shelf.isHidden = true
        addSubview(shelf)
        shelf.noEdgeEffects()

        styleChips()
        MemoryLogger.logSurface("search")
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Google/YouTube/Maps marks where we have them, SF Symbols elsewhere —
    /// the chip row is the one place the suite borrows brand colour.
    private func brandIcon(for t: Tab) -> UIImage? {
        let symbol = UIImage(systemName: t.icon)?
            .applyingSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        switch t {
        case .web:
            return BrandMark.google(size: 15)?.withRenderingMode(.alwaysOriginal)
        case .youtube, .shorts:
            return BrandMark.youtube(size: 15)?.withRenderingMode(.alwaysOriginal)
        case .maps:
            return BrandMark.pin(size: 15)?.withRenderingMode(.alwaysOriginal)
        default:
            return symbol
        }
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let rowH = Self.rowHeight
        closeButton.frame = CGRect(x: 2, y: (rowH - 30) / 2, width: 32, height: 30)
        // Tab track: 3pt padding, 2pt gaps, icon-only tabs up to 35pt wide,
        // narrower when they would leave the query (beside ABC) under ~70pt:
        // 30pt each on a 402pt phone, 35 on 440.
        let pad: CGFloat = 3, gap: CGFloat = 2, pillH: CGFloat = 30
        let n = CGFloat(chipButtons.count)
        let pillW = min(35, max(28, floor((bounds.width - 218) / n)))
        let trackW = pillW * n + gap * (n - 1) + pad * 2
        let trackH = pillH + pad * 2
        chipsRow.frame = CGRect(x: 34, y: (rowH - trackH) / 2, width: trackW, height: trackH)
        chipsRow.contentSize = CGSize(width: trackW, height: trackH)
        tabTrack.frame = CGRect(x: 0, y: 0, width: trackW, height: trackH)
        tabTrack.layer.cornerRadius = trackH / 2
        for (i, b) in chipButtons.enumerated() {
            b.frame = CGRect(x: pad + CGFloat(i) * (pillW + gap), y: pad,
                             width: pillW, height: pillH)
        }
        moveThumb(animated: false)

        let hasABC = expandedForResults
        let abcW: CGFloat = hasABC ? 46 : 0
        abcButton.isHidden = !hasABC
        let queryX = chipsRow.frame.maxX + 6 + abcW
        abcButton.frame = CGRect(x: chipsRow.frame.maxX + 6, y: (rowH - 34) / 2,
                                 width: abcW, height: 34)
        goButton.frame = CGRect(x: bounds.width - 40, y: (rowH - 34) / 2,
                                width: 34, height: 34)
        queryEditor.frame = CGRect(x: queryX, y: (rowH - 34) / 2,
                                   width: max(60, goButton.frame.minX - queryX - 6), height: 34)
        // Typing: suggestions sit in one row under the query, and a status
        // ("Searching…") takes that row's place. Results: the status heads
        // the list.
        let chipsOn = !expandedForResults
        chipsRowView.isHidden = !chipsOn
        chipsRowView.frame = CGRect(x: 0, y: rowH, width: bounds.width, height: Self.chipsHeight)
        var x: CGFloat = 12
        let chipH: CGFloat = 30
        for chip in suggestionChips {
            let w = min(230, ceil(chip.intrinsicContentSize.width))
            chip.frame = CGRect(x: x, y: (Self.chipsHeight - chipH) / 2, width: w, height: chipH)
            chip.layer.cornerRadius = chipH / 2
            x += w + 8
        }
        chipsRowView.contentSize = CGSize(width: x + 4, height: Self.chipsHeight)
        if chipsOn {
            statusLabel.frame = CGRect(x: 16, y: rowH + (Self.chipsHeight - 15) / 2,
                                       width: bounds.width - 32, height: 15)
            statusLabel.isHidden = status.isEmpty || !suggestionChips.isEmpty
        } else {
            statusLabel.frame = CGRect(x: 14, y: rowH + 2, width: bounds.width - 28, height: 15)
            statusLabel.isHidden = status.isEmpty
        }
        table.isHidden = !expandedForResults || showsShelf
        shelf.isHidden = !showsShelf
        let tableY = rowH + (status.isEmpty ? 4 : 18)
        table.frame = CGRect(x: 0, y: tableY, width: bounds.width,
                             height: max(0, bounds.height - tableY - 4))
        let shelfFrame = CGRect(x: 0, y: tableY + 2, width: bounds.width,
                                height: max(0, bounds.height - tableY - 10))
        if shelf.frame != shelfFrame {
            shelf.frame = shelfFrame
            shelf.collectionViewLayout.invalidateLayout()
        }
    }

    /// The suggestion row: a recent or trending search runs when tapped, a
    /// contact goes into the message.
    private func rebuildChips() {
        suggestionChips.forEach { $0.removeFromSuperview() }
        suggestionChips = []
        guard !expandedForResults else { return }
        for card in cards.prefix(12) {
            let b = UIButton(type: .system)
            var cfg = UIButton.Configuration.plain()
            let symbol: String
            switch card.kind {
            case "contact": symbol = card.domain ?? "person"
            default: symbol = card.source == "recent" ? "clock" : "arrow.up.right"
            }
            cfg.image = UIImage(systemName: symbol)?
                .applyingSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            cfg.imagePadding = 5
            var title = AttributedString(card.kind == "contact" ? "\(card.title) · \(card.url)" : card.title)
            title.font = .systemFont(ofSize: 13.5, weight: .medium)
            cfg.attributedTitle = title
            cfg.titleLineBreakMode = .byTruncatingTail
            cfg.baseForegroundColor = Glass.textPrimary
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 12)
            b.configuration = cfg
            b.tintColor = Glass.textSecondary
            b.backgroundColor = Glass.surfaceCard
            b.layer.cornerCurve = .continuous
            b.accessibilityIdentifier = "search:card:\(card.kind)"
            b.accessibilityLabel = card.kind == "contact" ? "\(card.title), \(card.url)" : card.title
            b.addAction(UIAction { [weak self] _ in self?.choose(card) }, for: .touchUpInside)
            chipsRowView.addSubview(b)
            suggestionChips.append(b)
        }
        chipsRowView.setContentOffset(.zero, animated: false)
    }

    /// The active tab's pill: the thumb slides, the way the website does it.
    private func moveThumb(animated: Bool) {
        guard let i = Tab.allCases.firstIndex(of: tab), chipButtons.indices.contains(i)
        else { return }
        let frame = chipButtons[i].frame
        let apply = { [weak self] in
            self?.tabThumb.frame = frame
            self?.tabThumb.layer.cornerRadius = frame.height / 2
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0,
                           usingSpringWithDamping: 0.86, initialSpringVelocity: 0.4,
                           options: [.allowUserInteraction], animations: apply)
        } else {
            apply()
        }
    }

    private func styleChips() {
        for (i, t) in Tab.allCases.enumerated() {
            let b = chipButtons[i]
            let active = t == tab
            b.configuration?.baseForegroundColor =
                active ? Glass.textPrimary : Glass.textSecondary
            b.tintColor = active ? Glass.textPrimary : Glass.textSecondary
        }
        moveThumb(animated: true)
    }

    // MARK: behavior

    private func select(_ t: Tab) {
        if t == .translate {
            delegate?.searchOpenTranslate()
            return
        }
        tab = t
        styleChips()
        if queryEditor.text.isEmpty { showLanding() } else { submit() }
    }

    /// What a tab shows BEFORE anything is typed: the user's own recent
    /// searches first (local, never uploaded), then what is trending /
    /// popular / nearby from the server. Gboard never opens on a blank box.
    func showLanding() {
        task?.cancel()
        let vertical = tab.vertical
        // Results from the tab just left must not sit under this one's rows.
        expandedForResults = false
        // Three rows, like the website's landing: any more would slide under
        // the keys, which stay live here. Contacts keeps no recents: a name
        // is not a search, and the web tab's history has no place there.
        let recents: [Card] = tab == .contacts ? [] :
            SearchRecents.list(vertical ?? "web").prefix(3).map { q -> Card in
                var c = Card(kind: "query", id: "recent-\(q)", title: q, url: "")
                c.source = "recent"
                return c
            }
        cards = recents
        status = ""
        landingActive = true
        if tab == .contacts {
            status = contacts.isEmpty
                ? "Turn on Contacts search in the Glyf app"
                : "Type a name"
            showRows(); return
        }
        showRows()   // even empty: the table forgets the last tab's rows
        guard let vertical, hasFullAccess else { return }
        task = BackendClient.shared.runSuggest(vertical: vertical,
            onResult: { [weak self] out in
                guard let self, out.vertical == self.tab.vertical else { return }
                // Recents stay on top; suggestions fill in underneath.
                let seen = Set(self.cards.map { $0.title.lowercased() })
                self.cards = recents + out.cards.filter {
                    !seen.contains($0.title.lowercased())
                }
                if !self.cards.isEmpty { self.showRows() }
            },
            onError: { _ in })
    }

    @objc private func activateQuery() {
        queryEditor.isActive = true
        delegate?.searchActivated(queryEditor)
    }

    func submit() {
        let q = queryEditor.text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        task?.cancel()
        if tab == .contacts {
            showContactMatches(q)
            return
        }
        guard hasFullAccess else {
            status = "Search needs Full Access"
            setNeedsLayout(); return
        }
        guard let vertical = tab.vertical else { return }
        SearchRecents.record(q, vertical: vertical)
        landingActive = false
        // The suggestions give way to "Searching…" until the results come.
        cards = []
        rebuildChips()
        status = "Searching…"
        setNeedsLayout()
        task = BackendClient.shared.runSearch(vertical: vertical, query: q, dark: Glass.chromeDark,
            onResult: { [weak self] out in
                guard let self else { return }
                // A late response from a tab the user already left must not
                // overwrite what they are looking at now.
                guard out.vertical == self.tab.vertical else { return }
                self.cards = out.cards
                // Places near you need to know where you are: the app asks.
                let nowhere = self.tab == .maps && SettingsStore.current.lastLat == nil
                self.status = self.cards.isEmpty
                    ? (nowhere ? "Turn on Nearby search in the Glyf app" : "Nothing found") : ""
                self.expand()
            },
            onError: { [weak self] message in
                self?.status = message
                self?.setNeedsLayout()
            })
    }

    /// Local contacts synced by the app (Profile → Search → Contacts). Never
    /// leaves the device — no vertical, no request.
    private func showContactMatches(_ q: String, live: Bool = false) {
        let lower = q.lowercased()
        let contacts = self.contacts
        guard !contacts.isEmpty else {
            status = "Turn on Contacts search in the Glyf app"
            setNeedsLayout(); return
        }
        func row(_ name: String, _ value: String, _ symbol: String) -> Card {
            var c = Card(kind: "contact", id: "\(name)-\(value)", title: name, url: value)
            c.snippet = value
            c.domain = symbol
            return c
        }
        cards = contacts
            .filter { $0.name.lowercased().contains(lower) }
            .prefix(12)
            .flatMap { c -> [Card] in
                var rows: [Card] = []
                for phone in c.phones { rows.append(row(c.name, phone, "phone")) }
                for email in c.emails { rows.append(row(c.name, email, "envelope")) }
                if rows.isEmpty { rows.append(row(c.name, c.name, "person")) }
                return rows
            }
        status = cards.isEmpty ? "No contacts named “\(q)”" : ""
        if live {
            // Typing a name: the matches show above keys that stay live, the
            // way the landing rows do, so the next letter narrows them.
            expandedForResults = false
            landingActive = true
            showRows()
        } else {
            expand()
        }
    }

    /// The query changed under the keys: contacts filter as you type.
    func queryChanged(_ text: String) {
        guard tab == .contacts else { return }
        let q = text.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { showLanding() } else { showContactMatches(q, live: true) }
    }

    private func reloadResults() {
        table.reloadData()
        shelf.reloadData()
        shelf.setContentOffset(.zero, animated: false)
    }

    /// Re-lays out the suggestion row while the keyboard stays put.
    private func showRows() {
        rebuildChips()
        reloadResults()
        table.setContentOffset(.zero, animated: false)
        setNeedsLayout()
        delegate?.searchLayoutChanged()
    }

    private func expand() {
        landingActive = false
        expandedForResults = true
        rebuildChips()
        // Maps drawn from OpenStreetMap carry its credit, once, under the list.
        if cards.contains(where: { $0.thumb?.hasPrefix("/search/staticmap") == true }) {
            let credit = UILabel(frame: CGRect(x: 0, y: 0, width: bounds.width, height: 26))
            credit.text = "Maps © OpenStreetMap contributors · Geoapify"
            credit.font = .systemFont(ofSize: 11)
            credit.textColor = Glass.textSecondary
            credit.textAlignment = .center
            table.tableFooterView = credit
        } else {
            table.tableFooterView = nil
        }
        reloadResults()
        table.setContentOffset(.zero, animated: false)
        setNeedsLayout()
        delegate?.searchLayoutChanged()
    }

    private func collapse() {
        expandedForResults = false
        cards = []
        status = ""
        reloadResults()
        setNeedsLayout()
        delegate?.searchLayoutChanged()
        activateQuery()
        // ABC returns you to suggestions, never to an empty panel.
        showLanding()
    }

    /// An empty query and the suggestions again, results or not.
    func startOver() {
        task?.cancel()
        queryEditor.setText("")
        if expandedForResults {
            expandedForResults = false
            cards = []
            status = ""
            reloadResults()
            setNeedsLayout()
            delegate?.searchLayoutChanged()
        }
        activateQuery()
        showLanding()
    }

    /// Called by the VC once the surface is on screen.
    func presentLanding() {
        showLanding()
    }

    func cancelWork() { task?.cancel() }

    // MARK: table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cards.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch cards[indexPath.row].kind {
        case "query": return 58
        case "answer": return 104
        case "video": return 82
        case "place": return 78
        default: return 66
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let card = cards[indexPath.row]
        switch card.kind {
        case "answer":
            let cell = tableView.dequeueReusableCell(withIdentifier: "answer", for: indexPath) as! AnswerCell
            cell.fill(card); return cell
        case "video":
            let cell = tableView.dequeueReusableCell(withIdentifier: "video", for: indexPath) as! VideoCell
            cell.fill(card); return cell
        case "place":
            let cell = tableView.dequeueReusableCell(withIdentifier: "place", for: indexPath) as! PlaceCell
            cell.fill(card); return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "link", for: indexPath) as! LinkCell
            cell.fill(card); return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        choose(cards[indexPath.row])
    }

    private func choose(_ card: Card) {
        // A suggestion is not something to paste — it RUNS the search.
        if card.kind == "query" {
            queryEditor.setText(card.title)
            submit()
            return
        }
        // A contact row is a phone number or an address, not a link — the
        // paste style does not apply to it.
        let text = card.kind == "contact"
            ? card.url
            : card.insertText(style: SettingsStore.current.pasteStyle ?? "titleAndLink")
        UIPasteboard.general.string = text
        delegate?.searchInsert(text)
    }
}

// MARK: - Shorts shelf

extension SearchSurface: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        showsShelf ? cards.count : 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "short",
                                                      for: indexPath) as! ShortCell
        cell.fill(cards[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        ShortsThumb.cardSize(height: max(40, collectionView.bounds.height))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        choose(cards[indexPath.item])
    }
}

/// A Short on the shelf: YouTube's 9:16 frame edge to edge, the YouTube mark
/// and the length on top, the title and channel over a shade at the foot —
/// the way YouTube's own Shorts shelf reads. The last tile is the link to
/// more Shorts on YouTube.
final class ShortCell: UICollectionViewCell {
    private let thumb = UIImageView()
    private let shade = CAGradientLayer()
    private let ytMark = UIImageView()
    private let badge = UILabel()
    private let title = UILabel()
    private let channel = UILabel()
    private let moreMark = UIImageView()
    private let moreTitle = UILabel()
    private var thumbURL = ""
    private var isMore = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        contentView.backgroundColor = UIColor.gray.withAlphaComponent(0.18)
        contentView.layer.cornerRadius = 15
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = Glass.strokeHairline.cgColor
        contentView.clipsToBounds = true

        thumb.clipsToBounds = true
        contentView.addSubview(thumb)
        shade.colors = [UIColor.black.withAlphaComponent(0).cgColor,
                        UIColor.black.withAlphaComponent(0.72).cgColor]
        shade.locations = [0, 1]
        contentView.layer.addSublayer(shade)

        // YouTube requires its mark on every card that shows its content.
        ytMark.image = BrandMark.youtube(size: 16)?.withRenderingMode(.alwaysOriginal)
        ytMark.contentMode = .scaleAspectFit
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 4
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.numberOfLines = 3
        channel.font = .systemFont(ofSize: 11)
        channel.textColor = UIColor.white.withAlphaComponent(0.78)
        moreMark.image = BrandMark.youtube(size: 30)?.withRenderingMode(.alwaysOriginal)
        moreMark.contentMode = .scaleAspectFit
        moreTitle.font = .systemFont(ofSize: 13, weight: .medium)
        moreTitle.textColor = Glass.textPrimary
        moreTitle.textAlignment = .center
        moreTitle.numberOfLines = 3
        for v in [ytMark, badge, title, channel, moreMark, moreTitle] { contentView.addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func fill(_ c: BackendClient.SearchCard) {
        isMore = c.kind != "short"
        for v in [thumb, ytMark, badge, title, channel] as [UIView] { v.isHidden = isMore }
        shade.isHidden = isMore
        moreMark.isHidden = !isMore
        moreTitle.isHidden = !isMore
        contentView.backgroundColor = isMore
            ? Glass.surfaceCard : UIColor.gray.withAlphaComponent(0.18)
        accessibilityIdentifier = isMore ? "search:card:link" : "search:card:short"
        accessibilityLabel = isMore ? c.title : "\(c.title). \(c.channel ?? "")"
        if isMore {
            moreTitle.text = c.title
            thumbURL = ""
            thumb.image = nil
            setNeedsLayout()
            return
        }
        title.text = c.title
        channel.text = c.channel
        badge.text = c.duration.map { " \($0) " }
        badge.isHidden = (c.duration ?? "").isEmpty
        // A vertical video's frame fills the card; anything else is fitted
        // whole, never cropped (YouTube's policies).
        let portrait = c.portrait == true
        thumb.contentMode = portrait ? .scaleAspectFill : .scaleAspectFit
        thumbURL = c.thumb ?? ""
        let variant = portrait ? "#9x16" : ""
        thumb.image = ThumbLoader.cached(thumbURL, variant: variant)
        if thumb.image == nil, !thumbURL.isEmpty {
            let wanted = thumbURL
            ThumbLoader.load(wanted, maxPixel: 320, variant: variant,
                             crop: { ShortsThumb.frame(imageSize: $0, portrait: portrait) }) { [weak self] image in
                guard let self, self.thumbURL == wanted else { return }
                self.thumb.image = image
            }
        }
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbURL = ""
        thumb.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        thumb.frame = b
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = CGRect(x: 0, y: b.height * 0.5, width: b.width, height: b.height * 0.5)
        CATransaction.commit()
        ytMark.frame = CGRect(x: 8, y: 8, width: 16, height: 16)
        let bw = badge.intrinsicContentSize.width + 4
        badge.frame = CGRect(x: b.width - bw - 7, y: 9, width: bw, height: 14)
        let inset: CGFloat = 8
        channel.frame = CGRect(x: inset, y: b.height - inset - 14, width: b.width - inset * 2, height: 14)
        let titleH = min(48, title.sizeThatFits(CGSize(width: b.width - inset * 2,
                                                       height: .greatestFiniteMagnitude)).height)
        title.frame = CGRect(x: inset, y: channel.frame.minY - titleH - 2,
                             width: b.width - inset * 2, height: titleH)
        moreMark.frame = CGRect(x: (b.width - 30) / 2, y: b.height / 2 - 34, width: 30, height: 30)
        moreTitle.frame = CGRect(x: 10, y: b.height / 2 + 4, width: b.width - 20, height: 52)
        moreTitle.sizeToFit()
        moreTitle.frame = CGRect(x: 10, y: b.height / 2 + 4, width: b.width - 20,
                                 height: moreTitle.frame.height)
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.contentView.alpha = self.isHighlighted ? 0.88 : 1
            }
        }
    }
}

// MARK: - Brand marks

/// The Google / YouTube / Maps marks, drawn rather than shipped as assets so
/// the extension stays small and the glyphs scale with the chip.
enum BrandMark {
    static func google(size: CGFloat) -> UIImage? {
        render(size: size) { ctx, r in
            let parts: [(UIColor, [CGFloat])] = [
                (UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1), [-0.30, 0.55]),
                (UIColor(red: 0.20, green: 0.66, blue: 0.32, alpha: 1), [0.55, 1.35]),
                (UIColor(red: 0.98, green: 0.74, blue: 0.02, alpha: 1), [1.35, 2.15]),
                (UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1), [2.15, 2.95]),
            ]
            let c = CGPoint(x: r.midX, y: r.midY)
            let radius = r.width * 0.38
            ctx.setLineWidth(r.width * 0.24)
            ctx.setLineCap(.butt)
            for (colour, arc) in parts {
                ctx.setStrokeColor(colour.cgColor)
                ctx.addArc(center: c, radius: radius,
                           startAngle: arc[0], endAngle: arc[1], clockwise: false)
                ctx.strokePath()
            }
            // The bar that turns the ring into a G.
            ctx.setFillColor(UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1).cgColor)
            ctx.fill(CGRect(x: c.x, y: c.y - r.width * 0.10,
                            width: r.width * 0.46, height: r.width * 0.20))
        }
    }

    static func youtube(size: CGFloat) -> UIImage? {
        render(size: size) { ctx, r in
            let box = CGRect(x: r.minX, y: r.midY - r.height * 0.34,
                             width: r.width, height: r.height * 0.68)
            ctx.setFillColor(UIColor(red: 1, green: 0, blue: 0.2, alpha: 1).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: box, cornerRadius: r.width * 0.22).cgPath)
            ctx.fillPath()
            ctx.setFillColor(UIColor.white.cgColor)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: box.minX + box.width * 0.38, y: box.minY + box.height * 0.26))
            p.addLine(to: CGPoint(x: box.minX + box.width * 0.38, y: box.maxY - box.height * 0.26))
            p.addLine(to: CGPoint(x: box.minX + box.width * 0.66, y: box.midY))
            p.close()
            ctx.addPath(p.cgPath)
            ctx.fillPath()
        }
    }

    /// The Shorts tab: the YouTube tab's play.rectangle stood upright, as a
    /// template so it tints like the SF Symbols beside it.
    static func shortsTab() -> UIImage? {
        render(width: 16, height: 19) { ctx, _ in
            ctx.setStrokeColor(UIColor.black.cgColor)
            ctx.setLineWidth(1.7)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: 2.35, y: 1.35, width: 11.3, height: 16.3),
                                     cornerRadius: 3).cgPath)
            ctx.strokePath()
            ctx.setFillColor(UIColor.black.cgColor)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 6.4, y: 6.6))
            p.addLine(to: CGPoint(x: 6.4, y: 12.4))
            p.addLine(to: CGPoint(x: 10.9, y: 9.5))
            p.close()
            ctx.addPath(p.cgPath)
            ctx.fillPath()
        }?.withRenderingMode(.alwaysTemplate)
    }

    static func pin(size: CGFloat) -> UIImage? {
        render(size: size) { ctx, r in
            ctx.setFillColor(UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1).cgColor)
            let p = UIBezierPath()
            let top = CGPoint(x: r.midX, y: r.minY + r.height * 0.04)
            p.addArc(withCenter: CGPoint(x: r.midX, y: r.minY + r.height * 0.38),
                     radius: r.width * 0.34, startAngle: .pi, endAngle: 0, clockwise: true)
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.04))
            p.close()
            _ = top
            ctx.addPath(p.cgPath)
            ctx.fillPath()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: r.midX - r.width * 0.12,
                                       y: r.minY + r.height * 0.26,
                                       width: r.width * 0.24, height: r.width * 0.24))
        }
    }

    private static func render(size: CGFloat,
                               _ draw: (CGContext, CGRect) -> Void) -> UIImage? {
        render(width: size, height: size, draw)
    }

    private static func render(width: CGFloat, height: CGFloat,
                               _ draw: (CGContext, CGRect) -> Void) -> UIImage? {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { context in draw(context.cgContext, rect) }
    }
}

// MARK: - Cells

/// Shared rounded container. Matches the site's `.ss-card`: 15pt radius,
/// card fill, hairline border, 10pt side inset.
class SearchCardCell: UITableViewCell {
    let card = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Glass.touchableGrid
        selectionStyle = .none
        // One result = one element. VoiceOver reads the whole card in a
        // single swipe instead of five fragments, and it is what exposes the
        // card's identifier to the UI tests.
        isAccessibilityElement = true
        accessibilityTraits = .button
        card.backgroundColor = Glass.surfaceCard
        card.layer.cornerRadius = 15
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = Glass.strokeHairline.cgColor
        card.clipsToBounds = true
        contentView.addSubview(card)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = contentView.bounds.insetBy(dx: 10, dy: 4)
    }

    /// The press state the site gets from `whileTap` — cards are the primary
    /// action here, so they must feel like buttons.
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: 0.12) {
            self.card.transform = highlighted
                ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            self.card.alpha = highlighted ? 0.88 : 1
        }
    }
}

/// The big answer at the top of the web tab. Sun and weather answers get the
/// site's dusk gradient; calculations and definitions stay on the card fill
/// so they read as text, not as a banner.
final class AnswerCell: SearchCardCell {
    private let gradient = CAGradientLayer()
    private let value = UILabel()
    private let sub = UILabel()
    private let art = SunArcView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.colors = [
            UIColor(red: 0.184, green: 0.188, blue: 0.278, alpha: 1).cgColor,
            UIColor(red: 0.420, green: 0.290, blue: 0.486, alpha: 1).cgColor,
            UIColor(red: 0.788, green: 0.435, blue: 0.416, alpha: 1).cgColor,
        ]
        gradient.locations = [0, 0.55, 1]
        card.layer.insertSublayer(gradient, at: 0)

        value.font = .systemFont(ofSize: 34, weight: .bold)
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.5
        sub.font = .systemFont(ofSize: 12.5)
        sub.numberOfLines = 2
        card.addSubview(value)
        card.addSubview(sub)
        card.addSubview(art)
    }

    required init?(coder: NSCoder) { fatalError() }

    func fill(_ c: BackendClient.SearchCard) {
        let painted = c.art == "sun" || c.art == "weather"
        gradient.isHidden = !painted
        art.isHidden = c.art != "sun"
        value.textColor = painted ? .white : Glass.textPrimary
        sub.textColor = painted ? UIColor.white.withAlphaComponent(0.78) : Glass.textSecondary
        // A definition's headline is the word; its body carries the meaning,
        // so it needs room that a time or a temperature does not.
        let long = (c.value ?? "").count > 12
        value.font = .systemFont(ofSize: long ? 22 : 34, weight: .bold)
        value.text = c.value ?? c.title
        sub.numberOfLines = c.art == "define" ? 3 : 2
        sub.text = c.sub ?? c.source
        accessibilityLabel = "\(c.value ?? c.title). \(c.sub ?? "")"
        accessibilityIdentifier = "search:card:answer"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = card.bounds
        let artW: CGFloat = art.isHidden ? 0 : 130
        art.frame = CGRect(x: card.bounds.width - artW - 14,
                           y: card.bounds.midY - 24, width: artW, height: 48)
        let textW = card.bounds.width - 30 - artW
        value.frame = CGRect(x: 15, y: 18, width: textW, height: 40)
        sub.frame = CGRect(x: 15, y: 60, width: textW, height: 32)
    }
}

/// The dashed arc with the sun sitting on it — straight from the site's
/// `.ss-sun-arc` SVG.
final class SunArcView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Glass.touchableGrid
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), rect.width > 20 else { return }
        let path = UIBezierPath()
        let inset: CGFloat = 4
        path.move(to: CGPoint(x: inset, y: rect.maxY - 4))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - 4),
                          controlPoint: CGPoint(x: rect.midX, y: rect.minY - 18))
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [3, 5])
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setFillColor(UIColor(red: 1, green: 0.827, blue: 0.431, alpha: 1).cgColor)
        let sun = CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.28)
        ctx.fillEllipse(in: CGRect(x: sun.x - 6, y: sun.y - 6, width: 12, height: 12))
    }
}

/// A web result: square icon chip (or page thumbnail), title, domain.
final class LinkCell: SearchCardCell {
    private let chip = UIView()
    private let symbol = UIImageView()
    private let thumb = UIImageView()
    private let title = UILabel()
    private let detail = UILabel()
    private var thumbURL = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        chip.backgroundColor = UIColor.gray.withAlphaComponent(0.14)
        chip.layer.cornerRadius = 10
        chip.layer.cornerCurve = .continuous
        chip.clipsToBounds = true
        symbol.contentMode = .scaleAspectFit
        symbol.tintColor = Glass.textSecondary
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        chip.addSubview(thumb)
        chip.addSubview(symbol)
        title.font = .systemFont(ofSize: 14.5, weight: .medium)
        title.textColor = Glass.textPrimary
        title.numberOfLines = 1
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = Glass.textSecondary
        detail.numberOfLines = 1
        card.addSubview(chip)
        card.addSubview(title)
        card.addSubview(detail)
    }

    required init?(coder: NSCoder) { fatalError() }

    func fill(_ c: BackendClient.SearchCard) {
        title.text = c.title
        detail.text = switch c.kind {
        case "contact": c.snippet
        case "query": nil                     // a suggestion is one line
        default: c.domain ?? c.snippet
        }
        let symbolName: String = switch c.kind {
        case "contact": c.domain ?? "person"
        // A clock for the user's own history, a trend arrow for what's hot —
        // the same two icons Gboard uses.
        case "query": c.source == "recent" ? "clock" : "arrow.up.right"
        default: "magnifyingglass"
        }
        symbol.image = UIImage(systemName: symbolName)?
            .applyingSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        thumbURL = c.thumb ?? ""
        thumb.image = nil
        thumb.isHidden = thumbURL.isEmpty
        symbol.isHidden = !thumbURL.isEmpty
        if !thumbURL.isEmpty {
            let wanted = thumbURL
            ThumbLoader.load(wanted, maxPixel: 72) { [weak self] image in
                guard let self, self.thumbURL == wanted else { return }
                self.thumb.image = image
                self.symbol.isHidden = image != nil
                self.thumb.isHidden = image == nil
            }
        }
        accessibilityLabel = c.title
        accessibilityIdentifier = "search:card:\(["contact", "query"].contains(c.kind) ? c.kind : "link")"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        chip.frame = CGRect(x: 12, y: (card.bounds.height - 36) / 2, width: 36, height: 36)
        thumb.frame = chip.bounds
        symbol.frame = chip.bounds.insetBy(dx: 9, dy: 9)
        let x: CGFloat = 60
        let w = card.bounds.width - x - 14
        let twoLine = (detail.text ?? "").isEmpty == false
        title.frame = CGRect(x: x, y: twoLine ? 13 : 22, width: w, height: 19)
        detail.frame = CGRect(x: x, y: 34, width: w, height: 16)
        detail.isHidden = !twoLine
    }
}

/// A YouTube result: 16:9 thumbnail with a play badge and a duration chip,
/// then title over channel.
final class VideoCell: SearchCardCell {
    private let thumb = UIImageView()
    private let play = UIImageView()
    private let badge = UILabel()
    private let title = UILabel()
    private let channel = UILabel()
    private let ytMark = UIImageView()
    private var thumbURL = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        // YouTube's policies forbid altering a thumbnail, so it is fitted
        // inside the frame rather than cropped to fill it.
        thumb.contentMode = .scaleAspectFit
        thumb.clipsToBounds = true
        thumb.backgroundColor = UIColor.gray.withAlphaComponent(0.18)
        thumb.layer.cornerRadius = 9
        thumb.layer.cornerCurve = .continuous
        play.image = UIImage(systemName: "play.circle.fill")?
            .applyingSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        play.tintColor = UIColor.white.withAlphaComponent(0.92)
        play.contentMode = .center
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 4
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = Glass.textPrimary
        title.numberOfLines = 2
        channel.font = .systemFont(ofSize: 12.5)
        channel.textColor = Glass.textSecondary
        // YouTube requires its mark on EVERY card that shows its content —
        // a single header attribution is explicitly not sufficient when
        // results from several sources share a surface.
        ytMark.image = BrandMark.youtube(size: 13)?.withRenderingMode(.alwaysOriginal)
        ytMark.contentMode = .scaleAspectFit
        card.addSubview(thumb)
        card.addSubview(play)
        card.addSubview(badge)
        card.addSubview(title)
        card.addSubview(ytMark)
        card.addSubview(channel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func fill(_ c: BackendClient.SearchCard) {
        title.text = c.title
        channel.text = c.channel
        let live = c.live == true
        badge.text = live ? " LIVE " : (c.duration.map { " \($0) " } ?? "")
        badge.isHidden = (badge.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        badge.backgroundColor = live
            ? UIColor(red: 1, green: 0, blue: 0.2, alpha: 0.95)
            : UIColor.black.withAlphaComponent(0.72)
        thumbURL = c.thumb ?? ""
        thumb.image = ThumbLoader.cached(thumbURL)
        play.isHidden = thumb.image == nil
        if thumb.image == nil, !thumbURL.isEmpty {
            let wanted = thumbURL
            ThumbLoader.load(wanted, maxPixel: 200) { [weak self] image in
                guard let self, self.thumbURL == wanted else { return }
                self.thumb.image = image
                self.play.isHidden = image == nil
            }
        }
        accessibilityLabel = "\(c.title). \(c.channel ?? "")"
        accessibilityIdentifier = "search:card:video"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let tw: CGFloat = 94, th: CGFloat = 54
        thumb.frame = CGRect(x: 10, y: (card.bounds.height - th) / 2, width: tw, height: th)
        play.frame = thumb.frame
        let bw = badge.intrinsicContentSize.width + 4
        badge.frame = CGRect(x: thumb.frame.maxX - bw - 5,
                             y: thumb.frame.maxY - 18, width: bw, height: 14)
        let x = thumb.frame.maxX + 12
        let w = card.bounds.width - x - 12
        title.frame = CGRect(x: x, y: 12, width: w, height: 36)
        ytMark.frame = CGRect(x: x, y: 52, width: 13, height: 13)
        channel.frame = CGRect(x: x + 18, y: 50, width: w - 18, height: 16)
    }
}

/// A Maps result: photo (or a drawn map tile), name, then the meta line
/// Gboard shows — distance, open now, rating.
final class PlaceCell: SearchCardCell {
    private let art = UIView()
    private let photo = UIImageView()
    private let pin = UIImageView()
    private let title = UILabel()
    private let meta = UILabel()
    private var thumbURL = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        art.backgroundColor = UIColor(red: 0.91, green: 0.94, blue: 0.91, alpha: 1)
        art.layer.cornerRadius = 9
        art.layer.cornerCurve = .continuous
        art.clipsToBounds = true
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        pin.image = BrandMark.pin(size: 22)?.withRenderingMode(.alwaysOriginal)
        pin.contentMode = .center
        art.addSubview(photo)
        art.addSubview(pin)
        title.font = .systemFont(ofSize: 14.5, weight: .medium)
        title.textColor = Glass.textPrimary
        title.numberOfLines = 1
        meta.font = .systemFont(ofSize: 12.5)
        meta.textColor = Glass.textSecondary
        meta.numberOfLines = 1
        card.addSubview(art)
        card.addSubview(title)
        card.addSubview(meta)
    }

    required init?(coder: NSCoder) { fatalError() }

    func fill(_ c: BackendClient.SearchCard) {
        title.text = c.title
        var bits: [String] = []
        if let d = c.distance { bits.append(d) }
        if let open = c.openNow { bits.append(open ? "Open" : "Closed") }
        if let r = c.rating {
            bits.append(c.ratingCount.map { "\(String(format: "%.1f", r)) ★ (\($0))" }
                        ?? "\(String(format: "%.1f", r)) ★")
        }
        if bits.isEmpty, let a = c.address { bits.append(a) }
        meta.text = bits.joined(separator: " · ")

        thumbURL = resolved(c.thumb)
        photo.image = nil
        photo.isHidden = true
        // The pin holds the corner until the picture comes (or if it never does).
        pin.isHidden = false
        // A map (no photo of the place): its middle, where the pin is, above
        // the credit Geoapify prints along the bottom (credited under the list).
        photo.layer.contentsRect = c.thumb?.hasPrefix("/search/staticmap") == true
            ? CGRect(x: 0, y: 0.14, width: 1, height: 0.70) : CGRect(x: 0, y: 0, width: 1, height: 1)
        if !thumbURL.isEmpty {
            let wanted = thumbURL
            ThumbLoader.load(wanted, maxPixel: 300) { [weak self] image in
                guard let self, self.thumbURL == wanted else { return }
                self.photo.image = image
                self.photo.isHidden = image == nil
                self.pin.isHidden = image != nil
            }
        }
        accessibilityLabel = "\(c.title). \(meta.text ?? "")"
        accessibilityIdentifier = "search:card:place"
    }

    /// Place photos come back as a server-relative path so the API key stays
    /// on the server.
    private func resolved(_ thumb: String?) -> String {
        guard let thumb, !thumb.isEmpty else { return "" }
        if thumb.hasPrefix("http") { return thumb }
        // A place with no photo shows its map, drawn dark on a dark board.
        let dark = Glass.chromeDark && thumb.hasPrefix("/search/staticmap") ? "&dark=1" : ""
        return SettingsStore.current.backendURL + thumb + dark
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let aw: CGFloat = 74, ah: CGFloat = 52
        art.frame = CGRect(x: 10, y: (card.bounds.height - ah) / 2, width: aw, height: ah)
        photo.frame = art.bounds
        pin.frame = art.bounds
        let x = art.frame.maxX + 12
        let w = card.bounds.width - x - 12
        title.frame = CGRect(x: x, y: 18, width: w, height: 19)
        meta.frame = CGRect(x: x, y: 39, width: w, height: 17)
    }
}

// MARK: - Contacts read model

extension AppGroupStore {
    struct SharedContact: Decodable {
        var name: String
        var phones: [String]
        var emails: [String]
    }

    /// contacts.json is written by the app when the user enables Contacts
    /// search (Profile). Missing file = feature off.
    static func readContacts() -> [SharedContact] {
        guard let url = bridgeDir?.appendingPathComponent("contacts.json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([SharedContact].self, from: data)
        else { return [] }
        return rows
    }
}
