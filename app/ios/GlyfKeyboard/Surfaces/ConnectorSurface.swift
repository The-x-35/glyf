import UIKit

protocol ConnectorSurfaceDelegate: AnyObject {
    func connectorInsert(_ text: String)
    func connectorClosed()
    func connectorSearchActivated(_ editor: InlineEditor)
    func connectorOpenApp(path: String)
    /// Search focus collapses the surface so letter keys can show below.
    func connectorLayoutChanged()
    func connectorSearchDismissed()
    /// A word for the person after the surface has closed (the toast
    /// otherwise leaves with it).
    func connectorToast(_ text: String)
}

/// §6.12 — the ConnectorSurface: search field (36pt) · result list (44pt
/// rows) · action bar (36pt). Opens with a DEFAULT QUERY ALREADY RUN — never
/// an empty state. Built once, reused per connector; today it speaks to the
/// demo calendar; Google/Notion/Slack plug into the same fetcher when OAuth
/// credentials land (M6). Memory: one plain table, cell reuse, ≤16pt symbols.
final class ConnectorSurface: UIView, UITableViewDataSource, UITableViewDelegate {

    weak var delegate: ConnectorSurfaceDelegate?

    struct Item {
        var title: String
        var detail: String
        var insertLink: String
        var insertFull: String
    }

    private let connectorId: String
    private let titleLabel = UILabel()
    private let searchEditor = InlineEditor(placeholder: "Search")
    private let closeButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .plain)
    private let monthGrid = UIView()
    private let actionBar = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var items: [Item] = []
    private var debounce: DispatchWorkItem?
    private var showingMonth = false
    private var monthLoaded = false
    /// §6.12: cache the last successful result set for 5 minutes.
    private static var cache: [String: (items: [Item], at: Date)] = [:]

    init(connectorId: String) {
        self.connectorId = connectorId
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        MemoryLogger.logSurface("connector:\(connectorId)")

        titleLabel.text = connectorId == "mockcal" ? "Calendar · today" : connectorId
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Glass.textPrimary
        addSubview(titleLabel)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "connector:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.connectorClosed() },
                              for: .touchUpInside)
        addSubview(closeButton)

        modeButton.setTitle("Month", for: .normal)
        modeButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        modeButton.setTitleColor(Glass.accentPrimary, for: .normal)
        modeButton.accessibilityIdentifier = "connector:mode"
        modeButton.addAction(UIAction { [weak self] _ in self?.toggleMonth() },
                             for: .touchUpInside)
        addSubview(modeButton)

        monthGrid.isHidden = true
        addSubview(monthGrid)

        searchEditor.onChange = { [weak self] q in self?.search(q) }
        let tap = UITapGestureRecognizer(target: self, action: #selector(searchTapped))
        searchEditor.addGestureRecognizer(tap)
        addSubview(searchEditor)

        table.backgroundColor = Glass.touchableGrid
        table.separatorColor = Glass.strokeHairline
        table.rowHeight = 44
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        addSubview(table)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Glass.textSecondary
        statusLabel.textAlignment = .center
        addSubview(statusLabel)

        actionBar.setTitle("New event from my text", for: .normal)
        actionBar.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        actionBar.setTitleColor(Glass.accentPrimary, for: .normal)
        actionBar.accessibilityIdentifier = "connector:action"
        actionBar.addAction(UIAction { [weak self] _ in
            self?.delegate?.connectorOpenApp(path: "connectors")
        }, for: .touchUpInside)
        addSubview(actionBar)

        // §6.12: default query already run; cached results paint instantly.
        if let cached = Self.cache[connectorId],
           Date().timeIntervalSince(cached.at) < 300 {
            items = cached.items
            table.reloadData()
        }
        search("")
    }

    required init?(coder: NSCoder) { fatalError() }

    /// While true the surface is a strip (title + field + short list) with
    /// the letter keys visible underneath — same fix as the emoji board.
    private(set) var searchActive = false
    static let searchStripHeight: CGFloat = 184

    @objc private func searchTapped() {
        searchEditor.isActive = true
        if !searchActive, !showingMonth {
            searchActive = true
            setNeedsLayout()
            delegate?.connectorLayoutChanged()
        }
        delegate?.connectorSearchActivated(searchEditor)
    }

    /// Return key / done: full surface comes back, filter kept.
    func exitSearch() {
        guard searchActive else { return }
        searchActive = false
        searchEditor.isActive = false
        setNeedsLayout()
        delegate?.connectorSearchDismissed()
        delegate?.connectorLayoutChanged()
    }

    func deactivateSearch() { searchEditor.isActive = false }

    private func search(_ query: String) {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fetch(query) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work) // §6.12: 250ms
    }

    private func fetch(_ query: String) {
        let s = SettingsStore.current
        var comps = URLComponents(string: "\(s.backendURL)/connector/\(connectorId)/events")
        if !query.isEmpty {
            comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        guard let url = comps?.url else { return }
        statusLabel.text = "…"
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = obj["events"] as? [[String: Any]] else {
                    self.statusLabel.text = "Couldn't load. Try again in a moment"
                    return
                }
                self.items = events.map { e in
                    let title = e["title"] as? String ?? ""
                    let start = e["start"] as? String ?? ""
                    let end = e["end"] as? String ?? ""
                    let link = e["link"] as? String ?? ""
                    return Item(
                        title: title,
                        detail: "\(start)–\(end)",
                        insertLink: link.isEmpty ? title : link,
                        insertFull: link.isEmpty ? "\(title) (\(start)–\(end))"
                                                 : "\(title) (\(start)–\(end)): \(link)")
                }
                self.statusLabel.text = self.items.isEmpty ? "No matches" : " "
                Self.cache[self.connectorId] = (self.items, Date())
                self.table.reloadData()
            }
        }.resume()
    }

    // MARK: month view (list = today's tasks · grid = the month at a glance)

    private func toggleMonth() {
        showingMonth.toggle()
        modeButton.setTitle(showingMonth ? "Today" : "Month", for: .normal)
        table.isHidden = showingMonth
        searchEditor.isHidden = showingMonth
        monthGrid.isHidden = !showingMonth
        if showingMonth, !monthLoaded { fetchMonth() }
        setNeedsLayout()
    }

    private func fetchMonth() {
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/connector/\(connectorId)/month")
        else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self, let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let days = obj["days"] as? [[String: Any]] else { return }
                self.monthLoaded = true
                self.buildMonthGrid(
                    firstWeekday: obj["firstWeekday"] as? Int ?? 0,
                    today: obj["today"] as? Int ?? 0,
                    month: obj["month"] as? Int ?? 1,
                    year: obj["year"] as? Int ?? 2026,
                    days: days.map { ($0["day"] as? Int ?? 0, $0["events"] as? Int ?? 0) })
            }
        }.resume()
    }

    private func buildMonthGrid(firstWeekday: Int, today: Int, month: Int,
                                year: Int, days: [(Int, Int)]) {
        monthGrid.subviews.forEach { $0.removeFromSuperview() }
        let monthName = DateFormatter().monthSymbols[max(0, month - 1)]
        let header = UILabel()
        header.text = "\(monthName) \(year)"
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = Glass.textPrimary
        header.textAlignment = .center
        header.tag = 100
        monthGrid.addSubview(header)
        for (i, wd) in ["S", "M", "T", "W", "T", "F", "S"].enumerated() {
            let l = UILabel()
            l.text = wd
            l.font = .systemFont(ofSize: 10, weight: .semibold)
            l.textColor = Glass.textSecondary
            l.textAlignment = .center
            l.tag = 200 + i
            monthGrid.addSubview(l)
        }
        for (day, events) in days {
            let cell = UIButton(type: .system)
            cell.setTitle("\(day)", for: .normal)
            cell.titleLabel?.font = .systemFont(ofSize: 12,
                                                weight: day == today ? .bold : .regular)
            cell.setTitleColor(day == today ? Glass.surfaceCard : Glass.textPrimary, for: .normal)
            cell.backgroundColor = day == today ? Glass.textPrimary : .clear
            cell.layer.cornerRadius = 7
            cell.tag = 1000 + ((firstWeekday + day - 1)) // grid slot
            cell.accessibilityIdentifier = "connector:day:\(day)"
            cell.addAction(UIAction { [weak self] _ in
                // Tap a day → drop the date into the field.
                self?.delegate?.connectorInsert("\(monthName) \(day)")
            }, for: .touchUpInside)
            if events > 0 {
                let dot = UIView()
                dot.backgroundColor = day == today
                    ? .white : Glass.accentPrimary
                dot.layer.cornerRadius = 1.75
                dot.tag = 99
                cell.addSubview(dot)
            }
            monthGrid.addSubview(cell)
        }
        setNeedsLayout()
    }

    private func layoutMonthGrid() {
        let w = monthGrid.bounds.width
        let h = monthGrid.bounds.height
        guard w > 100 else { return }
        let cellW = (w - 12) / 7
        // Rows stretch to FILL the surface — no dead space under the month.
        var maxSlot = 0
        for v in monthGrid.subviews where v.tag >= 1000 {
            maxSlot = max(maxSlot, v.tag - 1000)
        }
        let rows = CGFloat(maxSlot / 7 + 1)
        let cellH = max(26, min(62, (h - 46) / rows))
        for v in monthGrid.subviews {
            switch v.tag {
            case 100:
                v.frame = CGRect(x: 0, y: 0, width: w, height: 18)
            case 200...206:
                v.frame = CGRect(x: 6 + CGFloat(v.tag - 200) * cellW, y: 22,
                                 width: cellW, height: 14)
            case 1000...:
                let slot = v.tag - 1000
                v.frame = CGRect(x: 6 + CGFloat(slot % 7) * cellW,
                                 y: 42 + CGFloat(slot / 7) * cellH,
                                 width: cellW - 3, height: cellH - 4)
                if let dot = v.viewWithTag(99) {
                    dot.frame = CGRect(x: (cellW - 3) / 2 - 1.75,
                                       y: cellH - 11, width: 3.5, height: 3.5)
                }
            default: break
            }
        }
    }

    // MARK: table

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { items.count }

    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip)
        let item = items[ip.row]
        cell.backgroundColor = Glass.touchableGrid
        cell.textLabel?.text = "\(item.detail)   \(item.title)"
        cell.textLabel?.font = .systemFont(ofSize: 14)
        cell.textLabel?.textColor = Glass.textPrimary
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "connector:row:\(item.title)"
        return cell
    }

    func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        showInsertMenu(for: items[ip.row])
    }

    /// §6.12 insert menu: Link · Title+time · Full details. Inline overlay —
    /// UIAlertController would clip inside the keyboard's short window.
    private var menuOverlay: UIView?

    private func showInsertMenu(for item: Item) {
        menuOverlay?.removeFromSuperview()
        let overlay = UIView()
        overlay.backgroundColor = Glass.surfaceCard.withAlphaComponent(0.97)
        overlay.layer.borderWidth = Glass.hairlineWidth
        overlay.layer.borderColor = Glass.strokeHairline.cgColor
        overlay.accessibilityIdentifier = "connector:menu"

        func pill(_ title: String, id: String, _ insert: @escaping () -> String?) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            b.setTitleColor(id == "cancel" ? Glass.textSecondary : Glass.surfaceCard, for: .normal)
            b.backgroundColor = id == "cancel" ? Glass.fillField : Glass.textPrimary
            b.layer.cornerRadius = 15
            b.accessibilityIdentifier = "connector:menu:\(id)"
            b.addAction(UIAction { [weak self] _ in
                if let text = insert() { self?.delegate?.connectorInsert(text) }
                self?.menuOverlay?.removeFromSuperview()
                self?.menuOverlay = nil
            }, for: .touchUpInside)
            return b
        }
        let buttons = [
            pill("Link", id: "link") { item.insertLink },
            pill("Time + title", id: "brief") { "\(item.title) (\(item.detail))" },
            pill("Details", id: "full") { item.insertFull },
            pill("✕", id: "cancel") { nil },
        ]
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillProportionally
        overlay.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            stack.heightAnchor.constraint(equalToConstant: 30),
        ])
        overlay.frame = table.frame
        addSubview(overlay)
        menuOverlay = overlay
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.frame = CGRect(x: 12, y: 6, width: bounds.width - 150, height: 20)
        closeButton.frame = CGRect(x: bounds.width - 40, y: 2, width: 34, height: 28)
        modeButton.frame = CGRect(x: bounds.width - 104, y: 2, width: 60, height: 28)
        searchEditor.frame = CGRect(x: 10, y: 30, width: bounds.width - 20, height: 36)
        statusLabel.frame = CGRect(x: 0, y: 68, width: bounds.width, height: 16)
        actionBar.isHidden = searchActive
        actionBar.frame = CGRect(x: 0, y: bounds.height - 36, width: bounds.width, height: 36)
        let tableBottomInset: CGFloat = searchActive ? 0 : 36
        table.frame = CGRect(x: 0, y: 84, width: bounds.width,
                             height: max(0, bounds.height - 84 - tableBottomInset))
        monthGrid.frame = CGRect(x: 10, y: 30, width: bounds.width - 20,
                                 height: max(0, bounds.height - 30 - 40))
        layoutMonthGrid()
    }
}
