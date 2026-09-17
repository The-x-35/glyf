import UIKit

protocol GlyfShellDelegate: AnyObject {
    func shellClosed()
    func shellInsertText(_ text: String)
    func shellOpenApp(path: String)
    func shellStateChanged()
    func shellOpenSearch()
    /// A tile that opens one of the keyboard's own surfaces (the website's
    /// g menu): "search" | "emoji" | "translate" | "tones" | "ask".
    func shellOpenSurface(_ id: String)
    /// A tile held and dragged: it can be dropped on the strip to live there.
    func shellTileDragBegan(_ id: String, icon: String, at windowPoint: CGPoint)
    func shellTileDragMoved(to windowPoint: CGPoint)
    func shellTileDragEnded(at windowPoint: CGPoint)
    /// Opens the note editor strip (nil id = new note).
    func shellEditNote(id: String?, text: String)
}

/// §6.3 — the in-keyboard navigation shell. HARD memory rules:
/// screens are DATA (`ShellScreen` structs) rendered by ONE reusable
/// UITableView; pop = discard data, never a VC tree; icons ≤20pt SF Symbols.
/// Nav state survives keyboard dismissal for 60s via the App Group.
final class GlyfShell: UIView, UITableViewDataSource, UITableViewDelegate {

    weak var delegate: GlyfShellDelegate?

    enum ActionStyle { case plain, accent, danger }

    enum Row {
        case nav(icon: String, title: String, detail: String?, target: String)
        case toggle(title: String, value: () -> Bool, set: (Bool) -> Void)
        case segmented(title: String, options: [String], value: () -> String, set: (String) -> Void)
        case action(title: String, style: ActionStyle, handler: () -> Void)
        case info(title: String, detail: String?)
        /// Generic tap-to-insert row (notes, snippets…).
        case insert(icon: String, title: String, text: String)
        case clip(ClipItem)
        case binding(key: String, glyfId: String?)
        case vaultField(VaultField)
        case vaultCombo(VaultCombo)
        /// A note: tap inserts, ✎ edits right here in the keyboard.
        case note(GlyfNote)
        /// A ;shorthand: tap inserts its expansion.
        case snippet(trigger: String, text: String)
    }

    struct Screen {
        var id: String
        var title: String
        var rows: [Row]
        var showOpenInApp = true
        var appPath = ""
    }

    // MARK: State

    private var stack: [String] = ["root"]
    /// True when a deeper screen is open: the strip shows the way back.
    var canGoBack: Bool { stack.count > 1 }
    private var screen: Screen!
    private let header = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .plain)
    private let footerButton = UIButton(type: .system)

    /// Root renders as a launcher grid (Gboard/Launchpad pattern) — every
    /// deeper screen stays the reusable table.
    private let grid = UIView()
    /// The vault draws as the website's 3-column card grid, not a list.
    private let vaultGrid = UIScrollView()
    private var vaultCards: [(label: String, value: String, insert: String)] = []
    private struct Tile { var icon: String; var title: String; var target: String }
    /// The website's g menu: 4 x 2, in its order. "More" stands where the
    /// site puts Wallet and holds everything the keyboard has beyond it.
    private static let rootTiles: [Tile] = [
        Tile(icon: "magnifyingglass", title: "Search", target: "!search"),
        Tile(icon: "wand.and.stars", title: "Rewrite", target: "!tones"),
        Tile(icon: "character.bubble", title: "Translate", target: "!translate"),
        Tile(icon: "person.text.rectangle", title: "Vault", target: "vault"),
        Tile(icon: "doc.on.clipboard", title: "Clipboard", target: "!clipboard"),
        Tile(icon: "face.smiling", title: "Emoji", target: "!emoji"),
        Tile(icon: "sparkles", title: "Ask Glyf", target: "!ask"),
        Tile(icon: "ellipsis.circle", title: "More", target: "more"),
    ]

    private static let stateFile = "shell-state.json"

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = Glass.textPrimary
        backButton.accessibilityIdentifier = "shell:back"
        backButton.addAction(UIAction { [weak self] _ in self?.back() }, for: .touchUpInside)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = Glass.textPrimary
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "shell:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        header.addSubview(backButton)
        header.addSubview(titleLabel)
        header.addSubview(closeButton)
        addSubview(header)

        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = Glass.siteLook ? 48 : 52   // website: key height x 1.1
        table.dataSource = self
        table.delegate = self
        table.register(ShellCell.self, forCellReuseIdentifier: "c")
        addSubview(table)

        buildGrid()
        addSubview(grid)
        vaultGrid.alwaysBounceVertical = true
        vaultGrid.showsVerticalScrollIndicator = false
        addSubview(vaultGrid)

        footerButton.setTitle("Open in Glyf app ↗", for: .normal)
        footerButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        footerButton.setTitleColor(Glass.accentPrimary, for: .normal)
        footerButton.accessibilityIdentifier = "shell:openapp"
        footerButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.shellOpenApp(path: self.screen.appPath)
        }, for: .touchUpInside)
        addSubview(footerButton)

        restoreOrRoot()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let isRoot = screen.id == "root"
        // In the website look the strip carries the title, the close button
        // AND the way back, so the panel spends none of its 206pt on chrome.
        let headerH: CGFloat = Glass.solidLook ? 0 : 36
        titleLabel.isHidden = Glass.solidLook
        closeButton.isHidden = Glass.solidLook
        backButton.isHidden = Glass.solidLook || screen.id == "root"
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerH)
        backButton.frame = CGRect(x: 4, y: 0, width: 44, height: headerH)
        closeButton.frame = CGRect(x: bounds.width - 48, y: 0, width: 44, height: headerH)
        titleLabel.frame = CGRect(x: 52, y: 0, width: bounds.width - 104, height: headerH)
        let isVault = screen.id == "vault" && Glass.solidLook
        // Grids fill the panel the way the website does; only list screens
        // keep the "open in the app" line.
        let footerH: CGFloat = screen.showOpenInApp && !isRoot && !isVault ? 30 : 0
        table.isHidden = isRoot || isVault
        grid.isHidden = !isRoot
        vaultGrid.isHidden = !isVault
        table.frame = CGRect(x: 0, y: headerH, width: bounds.width,
                             height: bounds.height - headerH - footerH)
        grid.frame = table.frame
        vaultGrid.frame = table.frame
        if isRoot { layoutGrid() }
        if isVault { layoutVaultGrid() }
        footerButton.frame = CGRect(x: 0, y: bounds.height - footerH,
                                    width: bounds.width, height: footerH)
        footerButton.isHidden = footerH == 0
    }

    // MARK: Root launcher grid

    private func buildGrid() {
        for (i, tile) in Self.rootTiles.enumerated() {
            let cell = UIControl()
            cell.tag = 1000 + i
            cell.accessibilityLabel = tile.title
            cell.accessibilityIdentifier = "shell:tile:\(tile.target)"

            let card = UIView()
            card.tag = 1
            card.backgroundColor = Glass.surfaceCard
            card.layer.cornerRadius = 14
            card.layer.cornerCurve = .continuous
            if Glass.solidLook {
                card.layer.shadowColor = Glass.keyShadowColor.cgColor
                card.layer.shadowOpacity = Glass.keyShadowOpacity
                card.layer.shadowOffset = Glass.keyShadowOffset
                card.layer.shadowRadius = 0
            } else {
                card.layer.borderWidth = 1
                card.layer.borderColor = Glass.strokeHairline.cgColor
            }
            card.isUserInteractionEnabled = false
            cell.addSubview(card)

            let icon = UIImageView(image: UIImage(systemName: tile.icon))
            icon.tag = 2
            icon.tintColor = Glass.textPrimary
            icon.contentMode = .center
            icon.preferredSymbolConfiguration = .init(pointSize: 22, weight: .regular)
            icon.isUserInteractionEnabled = false
            cell.addSubview(icon)

            let label = UILabel()
            label.tag = 3
            label.text = tile.title
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = Glass.textPrimary
            label.textAlignment = .center
            label.isUserInteractionEnabled = false
            cell.addSubview(label)

            cell.addAction(UIAction { [weak self] _ in
                if tile.target.hasPrefix("!") {
                    self?.delegate?.shellOpenSurface(String(tile.target.dropFirst()))
                } else {
                    self?.push(tile.target)
                }
            }, for: .touchUpInside)
            // Hold a tile and drag it onto the strip to keep it there — the
            // way you rearrange a launcher.
            let drag = UILongPressGestureRecognizer(target: self, action: #selector(tileDrag(_:)))
            drag.minimumPressDuration = 0.3
            drag.allowableMovement = .greatestFiniteMagnitude
            cell.addGestureRecognizer(drag)
            grid.addSubview(cell)
        }
    }

    /// The strip id a tile stands for, or nil when it cannot live there.
    private static func stripId(for target: String) -> String? {
        switch target {
        case "!search": return "search"
        case "!emoji": return "emoji"
        case "!translate": return "translate"
        case "!tones": return "rewrite"
        case "!ask": return "ask"
        case "vault": return "vault"
        case "clipboard": return "clipboard"
        case "settings": return "settings"
        default: return nil
        }
    }

    @objc private func tileDrag(_ g: UILongPressGestureRecognizer) {
        guard let cell = g.view as? UIControl else { return }
        let i = cell.tag - 1000
        guard i >= 0, i < Self.rootTiles.count else { return }
        let tile = Self.rootTiles[i]
        let point = cell.convert(g.location(in: cell), to: window)
        switch g.state {
        case .began:
            guard let id = Self.stripId(for: tile.target) else { return }
            cell.alpha = 0.3
            delegate?.shellTileDragBegan(id, icon: tile.icon, at: point)
        case .changed:
            delegate?.shellTileDragMoved(to: point)
        case .ended, .cancelled, .failed:
            cell.alpha = 1
            delegate?.shellTileDragEnded(at: point)
        default:
            break
        }
    }

    /// The website's grid: 4 x 2 with an 8pt gap, tiles filling the panel.
    private func layoutGrid() {
        let cols = 4, gap: CGFloat = 8, side: CGFloat = 6
        let rows = Int(ceil(Double(Self.rootTiles.count) / Double(cols)))
        let cellW = (grid.bounds.width - side * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = (grid.bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        for case let cell as UIControl in grid.subviews {
            let i = cell.tag - 1000
            guard i >= 0, i < Self.rootTiles.count else { continue }
            let r = i / cols, c = i % cols
            cell.frame = CGRect(x: side + CGFloat(c) * (cellW + gap),
                                y: CGFloat(r) * (cellH + gap),
                                width: cellW, height: cellH)
            cell.viewWithTag(1)?.frame = cell.bounds
            // Icon over caption, centred as a column with an 8pt gap.
            let iconH: CGFloat = 26, capH: CGFloat = 15
            let top = (cellH - iconH - 8 - capH) / 2
            cell.viewWithTag(2)?.frame = CGRect(x: 0, y: top, width: cellW, height: iconH)
            cell.viewWithTag(3)?.frame = CGRect(x: 2, y: top + iconH + 8,
                                                width: cellW - 4, height: capH)
        }
    }

    // MARK: Vault grid (website 6.3)

    /// Nine cards, three to a row: label above value, tap inserts.
    private func buildVaultGrid() {
        vaultGrid.subviews.forEach { $0.removeFromSuperview() }
        let vault = VaultStore.shared.load()
        vaultCards = vault.fields.map {
            (label: $0.label.uppercased(), value: $0.value, insert: $0.value)
        }
        for note in NotesStore.shared.load() {
            vaultCards.append((label: "NOTE", value: note.text, insert: note.text))
        }
        for (i, item) in vaultCards.enumerated() {
            let cell = UIControl()
            cell.tag = 2000 + i
            cell.accessibilityLabel = item.label
            cell.accessibilityIdentifier = "vault:card:\(i)"

            let card = UIView()
            card.tag = 1
            card.backgroundColor = Glass.surfaceCard
            card.layer.cornerRadius = 12
            card.layer.cornerCurve = .continuous
            card.layer.shadowColor = Glass.keyShadowColor.cgColor
            card.layer.shadowOpacity = Glass.keyShadowOpacity
            card.layer.shadowOffset = Glass.keyShadowOffset
            card.layer.shadowRadius = 0
            card.isUserInteractionEnabled = false
            cell.addSubview(card)

            let label = UILabel()
            label.tag = 2
            label.attributedText = NSAttributedString(
                string: item.label,
                attributes: [.kern: 0.44,
                             .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                             .foregroundColor: Glass.textSecondary])
            label.isUserInteractionEnabled = false
            cell.addSubview(label)

            let value = UILabel()
            value.tag = 3
            value.text = item.value
            value.font = .systemFont(ofSize: 13, weight: .medium)
            value.textColor = Glass.textPrimary
            value.lineBreakMode = .byTruncatingTail
            value.isUserInteractionEnabled = false
            cell.addSubview(value)

            cell.addAction(UIAction { [weak self] _ in
                self?.delegate?.shellInsertText(item.insert)
            }, for: .touchUpInside)
            vaultGrid.addSubview(cell)
        }
    }

    private func layoutVaultGrid() {
        let cols = 3, gap: CGFloat = 6, side: CGFloat = 6
        let w = (vaultGrid.bounds.width - side * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let rows = max(1, Int(ceil(Double(vaultCards.count) / Double(cols))))
        // Three rows fill the panel exactly; more than nine cards scroll.
        let h = (vaultGrid.bounds.height - gap * 2) / 3
        for case let cell as UIControl in vaultGrid.subviews {
            let i = cell.tag - 2000
            guard i >= 0, i < vaultCards.count else { continue }
            let r = i / cols, c = i % cols
            cell.frame = CGRect(x: side + CGFloat(c) * (w + gap),
                                y: CGFloat(r) * (h + gap), width: w, height: h)
            cell.viewWithTag(1)?.frame = cell.bounds
            let top = (h - 15 - 2 - 17) / 2
            cell.viewWithTag(2)?.frame = CGRect(x: 8, y: top, width: w - 16, height: 15)
            cell.viewWithTag(3)?.frame = CGRect(x: 8, y: top + 17, width: w - 16, height: 17)
        }
        vaultGrid.contentSize = CGSize(width: vaultGrid.bounds.width,
                                       height: CGFloat(rows) * (h + gap) - gap)
    }

    // MARK: Navigation

    func push(_ id: String) {
        stack.append(id)
        render()
    }

    func back() {
        if stack.count > 1 {
            stack.removeLast()
            render()
        } else {
            close()
        }
    }

    private func close() {
        Self.clearSavedState()
        delegate?.shellClosed()
    }

    /// What the strip above should call this panel (website parity).
    var headerTitle: String { screen.id == "root" ? "Glyf" : screen.title }

    func render() {
        screen = Self.build(id: stack.last ?? "root")
        titleLabel.text = screen.title
        backButton.isHidden = screen.id == "root"
        if screen.id == "vault", Glass.solidLook { buildVaultGrid() }
        table.reloadData()
        saveState()
        setNeedsLayout()
        delegate?.shellStateChanged()
        MemoryLogger.logSurface("shell:\(screen.id)")
    }

    // MARK: 60s state survival (§6.3)

    private func saveState() {
        AppGroupStore.writeJSON(["stack": stack, "ts": Date().timeIntervalSince1970],
                                name: Self.stateFile)
    }

    static func clearSavedState() {
        AppGroupStore.writeJSON(["stack": ["root"], "ts": 0], name: stateFile)
    }

    private func restoreOrRoot() {
        if let saved = AppGroupStore.readJSON(name: Self.stateFile),
           let ts = saved["ts"] as? TimeInterval,
           let savedStack = saved["stack"] as? [String],
           Date().timeIntervalSince1970 - ts < 60, !savedStack.isEmpty {
            stack = savedStack
        } else {
            stack = ["root"]
        }
        render()
    }

    // MARK: Screens as data (§6.3 table)

    static func build(id: String) -> Screen {
        switch id {
        case "root":
            return Screen(id: id, title: "Glyf", rows: [
                .nav(icon: "square.grid.2x2", title: "Glyfs", detail: nil, target: "glyfs"),
                .nav(icon: "keyboard", title: "Glyf Keys", detail: nil, target: "keys"),
                .nav(icon: "link", title: "Connectors", detail: nil, target: "connectors"),
                .nav(icon: "person.text.rectangle", title: "Vault", detail: nil, target: "vault"),
                .nav(icon: "note.text", title: "Notes", detail: nil, target: "notes"),
                .nav(icon: "doc.on.clipboard", title: "Clipboard", detail: nil, target: "clipboard"),
                .nav(icon: "rectangle.stack", title: "Packs", detail: nil, target: "packs"),
                .nav(icon: "gearshape", title: "Settings", detail: nil, target: "settings"),
                .nav(icon: "person.crop.circle", title: "Account", detail: nil, target: "account"),
            ], showOpenInApp: true)

        case "more":
            return Screen(id: id, title: "More", rows: [
                .nav(icon: "square.grid.2x2", title: "Glyfs", detail: nil, target: "glyfs"),
                .nav(icon: "keyboard", title: "Glyf Keys", detail: nil, target: "keys"),
                .nav(icon: "bolt", title: "Shorthand", detail: nil, target: "shorthand"),
                .nav(icon: "note.text", title: "Notes", detail: nil, target: "notes"),
                .nav(icon: "link", title: "Connectors", detail: nil, target: "connectors"),
                .nav(icon: "rectangle.stack", title: "Packs", detail: nil, target: "packs"),
                .nav(icon: "gearshape", title: "Settings", detail: nil, target: "settings"),
                .nav(icon: "person.crop.circle", title: "Account", detail: nil, target: "account"),
            ], showOpenInApp: false)

        case "settings":
            return Screen(id: id, title: "Settings", rows: [
                .segmented(title: "Appearance",
                           options: ["auto", "light", "dark"],
                           value: { SettingsStore.current.appearance ?? "auto" },
                           set: { v in SettingsStore.update { $0.appearance = v } }),
                .segmented(title: "Key style",
                           options: ["glass", "classic", "glow"],
                           value: { SettingsStore.current.keyTheme ?? "glass" },
                           set: { v in SettingsStore.update { $0.keyTheme = v } }),
                .toggle(title: "Haptics",
                        value: { SettingsStore.current.haptics },
                        set: { v in SettingsStore.update { $0.haptics = v } }),
                .toggle(title: "Key sounds",
                        value: { SettingsStore.current.keyClicks },
                        set: { v in SettingsStore.update { $0.keyClicks = v } }),
                .toggle(title: "Number row",
                        value: { SettingsStore.current.numberRow },
                        set: { v in SettingsStore.update { $0.numberRow = v } }),
                .toggle(title: "Autocorrect",
                        value: { SettingsStore.current.autocorrect },
                        set: { v in SettingsStore.update { $0.autocorrect = v } }),
                .toggle(title: "Auto-capitalize",
                        value: { SettingsStore.current.autocapitalize },
                        set: { v in SettingsStore.update { $0.autocapitalize = v } }),
                .toggle(title: "\".\" shortcut",
                        value: { SettingsStore.current.periodShortcut },
                        set: { v in SettingsStore.update { $0.periodShortcut = v } }),
                .segmented(title: "One-handed",
                           options: ["off", "left", "right"],
                           value: { SettingsStore.current.oneHanded },
                           set: { v in SettingsStore.update { $0.oneHanded = v } }),
                .toggle(title: "Paste title with link",
                        value: { (SettingsStore.current.pasteStyle ?? "titleAndLink") == "titleAndLink" },
                        set: { on in
                            SettingsStore.update { $0.pasteStyle = on ? "titleAndLink" : "linkOnly" }
                        }),
                .nav(icon: "slider.horizontal.3", title: "Toolbar items", detail: nil,
                     target: "toolbar"),
            ], showOpenInApp: false)

        case "toolbar":
            var rows: [Row] = []
            for itemId in SettingsStore.current.toolbarOrder {
                rows.append(.toggle(
                    title: itemId.capitalized,
                    value: { !SettingsStore.current.toolbarHidden.contains(itemId) },
                    set: { visible in
                        SettingsStore.update { s in
                            s.toolbarHidden.removeAll { $0 == itemId }
                            if !visible { s.toolbarHidden.append(itemId) }
                        }
                    }))
                rows.append(.action(title: "    ↑ move \(itemId) up", style: .plain, handler: {
                    SettingsStore.update { s in
                        if let i = s.toolbarOrder.firstIndex(of: itemId), i > 0 {
                            s.toolbarOrder.swapAt(i, i - 1)
                        }
                    }
                }))
            }
            return Screen(id: id, title: "Toolbar", rows: rows, showOpenInApp: false)

        case "notes":
            // Notes live inside Vault now; keep the target as an alias so
            // old saved nav stacks and bindings still land somewhere real.
            return build(id: "vault")

        case "shorthand":
            let snippets = VaultStore.shared.load().snippets
            var rows: [Row] = snippets.map { .snippet(trigger: $0.trigger, text: $0.text) }
            if rows.isEmpty {
                rows.append(.info(title: "No shorthand yet", detail: nil))
            }
            return Screen(id: id, title: "Shorthand", rows: rows, appPath: "vault")

        case "clipboard":
            ClipboardStore.captureNow() // opening the screen is user intent
            var rows: [Row] = ClipboardStore.load().map { .clip($0) }
            if rows.isEmpty {
                rows.append(.info(title: ClipboardStore.fullAccessHint
                                  ? "Nothing copied yet"
                                  : "Turn on Full Access to keep what you copy", detail: nil))
            } else {
                rows.append(.action(title: "Clear unpinned", style: .danger, handler: {
                    ClipboardStore.clearUnpinned()
                }))
            }
            return Screen(id: id, title: "Clipboard", rows: rows, showOpenInApp: false)

        case "keys":
            let bindings = SettingsStore.current.bindings
            var rows: [Row] = []
            for letter in "qwertyuiopasdfghjklzxcvbnm".map(String.init) {
                if let glyfId = bindings[letter] {
                    rows.append(.binding(key: letter, glyfId: glyfId))
                }
            }
            if rows.isEmpty {
                rows.append(.info(title: "No keys bound", detail: nil))
            }
            return Screen(id: id, title: "Glyf Keys", rows: rows, appPath: "keys")

        case "glyfs":
            let rows: [Row] = GlyfCatalog.all.map {
                .nav(icon: $0.icon, title: $0.title, detail: nil, target: "!none")
            }
            return Screen(id: id, title: "Glyfs", rows: rows, appPath: "glyfs")

        case "connectors":
            return Screen(id: id, title: "Connectors", rows: [
                .nav(icon: "calendar", title: "Calendar", detail: nil, target: "!connector:mockcal"),
                .info(title: "Google · Notion · Slack soon", detail: nil),
            ], appPath: "connectors")

        case "vault":
            let vault = VaultStore.shared.load()
            NotesStore.shared.invalidate() // the app may have edited them
            var rows: [Row] = []
            for combo in vault.combos {
                rows.append(.vaultCombo(combo))
            }
            for field in vault.fields {
                rows.append(.vaultField(field))
            }
            for note in NotesStore.shared.load() {
                rows.append(.note(note))
            }
            rows.append(.action(title: "＋ New note", style: .accent, handler: {}))
            return Screen(id: id, title: "Vault", rows: rows, appPath: "vault")

        case "packs":
            return Screen(id: id, title: "Packs", rows: [
                .nav(icon: "pencil.and.outline", title: "Writer", detail: nil, target: "!none"),
                .nav(icon: "bolt.fill", title: "Operator", detail: nil, target: "!none"),
                .nav(icon: "bubble.left.and.bubble.right", title: "Social", detail: nil, target: "!none"),
            ], appPath: "packs")

        case "account":
            return Screen(id: id, title: "Account", rows: [
                .info(title: "Free · \(GlyfCatalog.runsRemainingText())", detail: nil),
            ], appPath: "account")

        default:
            return Screen(id: id, title: id, rows: [.info(title: "…", detail: nil)])
        }
    }

    // MARK: Table plumbing (ONE table, reused cells)

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { screen.rows.count }

    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip) as! ShellCell
        cell.configure(row: screen.rows[ip.row], shell: self)
        return cell
    }

    func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        switch screen.rows[ip.row] {
        case .nav(_, _, _, let target):
            if target == "!none" { break }
            push(target)
        case .action(let title, _, let handler):
            if title.contains("New note") {
                delegate?.shellEditNote(id: nil, text: "")
                break
            }
            handler()
            render()
        case .insert(_, _, let text):
            delegate?.shellInsertText(text)
        case .clip(let item):
            delegate?.shellInsertText(item.text)
        case .vaultField(let field):
            delegate?.shellInsertText(field.value)
        case .vaultCombo(let combo):
            delegate?.shellInsertText(VaultStore.shared.comboText(combo))
        case .note(let note):
            delegate?.shellInsertText(note.text)
        case .snippet(_, let text):
            delegate?.shellInsertText(text)
        case .binding:
            break // unbinding is the ✕ button, never a whole-row surprise
        default:
            break
        }
    }

    fileprivate func unbind(_ key: String) {
        SettingsStore.update { $0.bindings.removeValue(forKey: key) }
        render()
    }

    fileprivate func editNote(_ note: GlyfNote) {
        delegate?.shellEditNote(id: note.id, text: note.text)
    }

    fileprivate func rowChanged() { render() }
}

// MARK: - Cell

private final class ShellCell: UITableViewCell {
    private weak var shell: GlyfShell?

    // Card anatomy: [chip][title  value][trailing]
    private let card = UIView()
    private let chip = UIView()
    private let chipIcon = UIImageView()
    private let chipLetter = UILabel()
    private let chipDot = UIView()
    private let title = UILabel()
    private let value = UILabel()
    private var trailing: UIView?

    /// Display name for a binding — NEVER a raw id like "glyf.summarize".
    static func displayTitle(_ glyfId: String) -> String {
        let t = GlyfCatalog.title(for: glyfId)
        guard t == glyfId else { return t }
        let last = glyfId.split(separator: ".").last.map(String.init) ?? glyfId
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// "Just now", "2 min", "1 hr", "Yesterday" — the website's clipboard ages.
    static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Just now"
        case ..<3600: return "\(Int(seconds / 60)) min"
        case ..<86_400: return "\(Int(seconds / 3600)) hr"
        case ..<172_800: return "Yesterday"
        default: return "\(Int(seconds / 86_400)) days"
        }
    }

    private func preview(_ v: String) -> String {
        let flat = v.replacingOccurrences(of: "\n", with: " · ")
        return flat.count > 40 ? String(flat.prefix(40)) + "…" : flat
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        // Website row: radius 12 card with a hard bottom edge, no outline.
        card.layer.cornerRadius = Glass.siteLook ? 12 : 13
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = Glass.siteLook ? 0 : Glass.hairlineWidth
        if Glass.siteLook {
            card.layer.shadowColor = Glass.keyShadowColor.cgColor
            card.layer.shadowOpacity = 1
            card.layer.shadowRadius = 0
            card.layer.shadowOffset = CGSize(width: 0, height: 1)
        }
        contentView.addSubview(card)

        chip.layer.cornerRadius = 8
        chip.layer.cornerCurve = .continuous
        card.addSubview(chip)
        chipIcon.contentMode = .center
        chipIcon.preferredSymbolConfiguration = .init(pointSize: 13.5, weight: .medium)
        chip.addSubview(chipIcon)
        chipLetter.font = .systemFont(ofSize: 14, weight: .bold)
        chipLetter.textAlignment = .center
        chip.addSubview(chipLetter)
        chipDot.layer.cornerRadius = 2
        chip.addSubview(chipDot)

        title.font = .systemFont(ofSize: Glass.siteLook ? 14 : 14.5, weight: .semibold)
        card.addSubview(title)
        value.font = .systemFont(ofSize: Glass.siteLook ? 14 : 12.5)
        card.addSubview(value)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = contentView.bounds.insetBy(dx: 10, dy: 3)
        let hasChip = !chip.isHidden
        chip.frame = CGRect(x: 10, y: (card.bounds.height - 28) / 2, width: 28, height: 28)
        chipIcon.frame = chip.bounds
        chipLetter.frame = chip.bounds
        chipDot.frame = CGRect(x: 20, y: 4, width: 4, height: 4)
        let x: CGFloat = hasChip ? 48 : 14
        let trailW: CGFloat = trailing.map { $0.frame.width + 12 } ?? 10
        let w = card.bounds.width - x - trailW
        if value.isHidden {
            title.frame = CGRect(x: x, y: 0, width: w, height: card.bounds.height)
        } else if Glass.siteLook {
            // One line: a fixed key column, then the value (website rows).
            let keyW: CGFloat = min(92, w * 0.42)
            title.frame = CGRect(x: x, y: 0, width: keyW, height: card.bounds.height)
            value.frame = CGRect(x: x + keyW + 10, y: 0,
                                 width: max(0, w - keyW - 10), height: card.bounds.height)
        } else {
            title.frame = CGRect(x: x, y: 7, width: w, height: 18)
            value.frame = CGRect(x: x, y: 25, width: w, height: 15)
        }
        if let tv = trailing {
            tv.center = CGPoint(x: card.bounds.width - trailW / 2 - 2,
                                y: card.bounds.height / 2)
        }
    }

    private func reset() {
        card.backgroundColor = Glass.surfaceCard
        card.layer.borderColor = Glass.strokeHairline.cgColor
        chip.isHidden = true
        chipIcon.image = nil
        chipLetter.text = nil
        chipDot.isHidden = true
        chip.backgroundColor = Glass.fillField
        chipIcon.tintColor = Glass.textPrimary
        chipLetter.textColor = Glass.textPrimary
        chipDot.backgroundColor = Glass.accentPrimary
        title.text = nil
        title.textColor = Glass.textPrimary
        title.textAlignment = .natural
        value.text = nil
        value.isHidden = true
        value.textColor = Glass.textSecondary
        trailing?.removeFromSuperview()
        trailing = nil
        accessibilityIdentifier = nil
    }

    private func setIcon(_ name: String) {
        chip.isHidden = false
        chipIcon.image = UIImage(systemName: name)
    }

    private func setTrailing(_ v: UIView) {
        trailing = v
        card.addSubview(v)
        setNeedsLayout()
    }

    private func chevron() -> UIView {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right"))
        iv.tintColor = Glass.textSecondary.withAlphaComponent(0.6)
        iv.preferredSymbolConfiguration = .init(pointSize: 11, weight: .semibold)
        iv.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        return iv
    }

    private func iconButton(_ name: String, tint: UIColor,
                            action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: name), for: .normal)
        b.setPreferredSymbolConfiguration(.init(pointSize: 13, weight: .semibold),
                                          forImageIn: .normal)
        b.tintColor = tint
        b.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    func configure(row: GlyfShell.Row, shell: GlyfShell) {
        self.shell = shell
        reset()

        switch row {
        case .nav(let icon, let t, _, let target):
            setIcon(icon)
            title.text = t
            if target != "!none" { setTrailing(chevron()) }
        case .insert(let icon, let t, _):
            setIcon(icon)
            title.text = preview(t)
            accessibilityIdentifier = "note:\(preview(t))"
        case .toggle(let t, let valueFn, let set):
            title.text = t
            let sw = UISwitch()
            sw.isOn = valueFn()
            sw.onTintColor = Glass.accentPrimary
            sw.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            sw.addAction(UIAction { [weak self] a in
                guard let s = a.sender as? UISwitch else { return }
                set(s.isOn)
                self?.shell?.rowChanged()
            }, for: .valueChanged)
            sw.frame = CGRect(x: 0, y: 0, width: 42, height: 26)
            setTrailing(sw)
        case .segmented(let t, let options, let valueFn, let set):
            title.text = t
            let seg = UISegmentedControl(items: options)
            seg.selectedSegmentIndex = options.firstIndex(of: valueFn()) ?? 0
            seg.selectedSegmentTintColor = Glass.accentPrimary
            seg.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11.5)], for: .normal)
            seg.addAction(UIAction { [weak self] a in
                guard let s = a.sender as? UISegmentedControl,
                      s.selectedSegmentIndex >= 0 else { return }
                set(options[s.selectedSegmentIndex])
                self?.shell?.rowChanged()
            }, for: .valueChanged)
            seg.frame = CGRect(x: 0, y: 0, width: 150, height: 28)
            setTrailing(seg)
        case .action(let t, let style, _):
            title.text = t
            title.textAlignment = .center
            card.backgroundColor = .clear
            card.layer.borderColor = UIColor.clear.cgColor
            switch style {
            case .accent: title.textColor = Glass.accentPrimary
            case .danger: title.textColor = Glass.accentDanger
            case .plain: title.textColor = Glass.textSecondary
            }
        case .info(let t, _):
            title.text = t
            title.textColor = Glass.textSecondary
            title.textAlignment = .center
            card.backgroundColor = .clear
            card.layer.borderColor = UIColor.clear.cgColor
        case .clip(let item):
            // Website row: how long ago on the left, the text beside it.
            if Glass.siteLook {
                title.text = Self.age(item.ts)
                value.text = preview(item.text)
                value.isHidden = false
            } else {
                setIcon("doc.on.clipboard")
                title.text = preview(item.text)
            }
            setTrailing(iconButton(item.pinned ? "pin.fill" : "pin",
                                   tint: item.pinned ? Glass.accentPrimary
                                                     : Glass.textSecondary) { [weak self] in
                ClipboardStore.togglePin(item.text)
                self?.shell?.rowChanged()
            })
        case .binding(let key, let glyfId):
            chip.isHidden = false
            chip.backgroundColor = Glass.fillKeySolid
            chipLetter.text = key.uppercased()
            chipDot.isHidden = false
            title.text = Self.displayTitle(glyfId ?? "")
            setTrailing(iconButton("xmark.circle.fill",
                                   tint: Glass.textSecondary.withAlphaComponent(0.55)) { [weak shell] in
                shell?.unbind(key)
            })
            accessibilityIdentifier = "key:\(key)"
        case .vaultField(let field):
            setIcon("person.text.rectangle")
            title.text = field.label
            value.isHidden = false
            value.text = preview(field.value)
            accessibilityIdentifier = "vault:\(field.label)"
        case .vaultCombo(let combo):
            setIcon("square.stack")
            title.text = combo.label
            value.isHidden = false
            value.text = "\(combo.fieldIds.count) fields"
            accessibilityIdentifier = "vault:\(combo.label)"
        case .note(let note):
            setIcon("note.text")
            let first = String(note.text.split(separator: "\n").first ?? "")
            title.text = preview(first)
            accessibilityIdentifier = "note:\(preview(first))"
            setTrailing(iconButton("square.and.pencil",
                                   tint: Glass.accentPrimary) { [weak shell] in
                shell?.editNote(note)
            })
        case .snippet(let trigger, let text):
            chip.isHidden = false
            chip.backgroundColor = Glass.fillKeySolid
            chipLetter.text = ";"
            chipLetter.textColor = Glass.accentPrimary
            title.text = trigger
            value.isHidden = false
            value.text = preview(text)
            accessibilityIdentifier = "snippet:\(trigger)"
        }
    }
}
