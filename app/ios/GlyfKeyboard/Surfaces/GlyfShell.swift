import UIKit

protocol GlyfShellDelegate: AnyObject {
    func shellClosed()
    func shellInsertText(_ text: String)
    func shellOpenApp(path: String)
    func shellStateChanged()
    func shellOpenSearch()
    /// A g menu tile was tapped: the same tool ids the strip uses.
    func shellOpenTool(_ id: String)
    /// Run one of the person's own glyfs on what they are typing.
    func shellRunGlyf(_ id: String)
    /// A tile held and dragged: it can be dropped on the strip to live there.
    func shellTileDragBegan(_ id: String, icon: String, at windowPoint: CGPoint)
    func shellTileDragMoved(to windowPoint: CGPoint)
    func shellTileDragEnded(at windowPoint: CGPoint)
    /// Opens the note editor strip (nil id = new note).
    func shellEditNote(id: String?, text: String)
    /// Puts a vault image back on the clipboard, ready to paste into a field.
    func shellCopyImage(id: String)
}

/// §6.3 — the in-keyboard navigation shell. HARD memory rules:
/// screens are DATA (`ShellScreen` structs) rendered by ONE reusable
/// UITableView; pop = discard data, never a VC tree; icons ≤20pt SF Symbols.
final class GlyfShell: UIView, UITableViewDataSource, UITableViewDelegate {

    weak var delegate: GlyfShellDelegate?

    enum ActionStyle { case plain, accent, danger }

    enum Row {
        case nav(icon: String, title: String, detail: String?, target: String)
        /// `moveUp` adds a ↑ beside the switch for rows whose order matters
        /// (the toolbar's items); nil draws the switch alone.
        case toggle(title: String, value: () -> Bool, set: (Bool) -> Void,
                    moveUp: (() -> Void)? = nil)
        case segmented(title: String, options: [String], value: () -> String, set: (String) -> Void)
        case action(title: String, style: ActionStyle, handler: () -> Void)
        case info(title: String, detail: String?)
        /// A section's title, in small capitals above the group it opens.
        case header(title: String)
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
        /// A picture kept in the vault: tap puts it back on the clipboard,
        /// which is as close to "insert" as any keyboard can get.
        case vaultImage(VaultImage)
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
    /// deeper screen stays the reusable table. It scrolls: every tool the
    /// keyboard has is here, nothing hides behind a More.
    private let grid = ControlScrollView()
    /// The vault draws as the website's 3-column card grid, not a list.
    private let vaultGrid = ControlScrollView()
    /// A tile in the vault grid. Text tiles insert; an image tile can only
    /// go back on the clipboard, since no keyboard can type a picture into a
    /// host field. Adding anything happens in the APP — the keyboard reads
    /// the vault and puts things into the field, it never edits it.
    enum VaultCard {
        case text(label: String, value: String, insert: String)
        case image(VaultImage)
        /// A note inserts on tap and opens for editing on a hold.
        case note(GlyfNote)
        /// The one card that adds something: a note written right here.
        case newNote
    }

    private var vaultCards: [VaultCard] = []
    /// Every tool, in the website's order first. The ids are the strip's, so
    /// any tile can be dragged up to live there. People reorder them by
    /// holding one and moving it (saved as `menuOrder`).
    static let tools: [(id: String, title: String)] = [
        ("search", "Search"), ("rewrite", "Rewrite"), ("translate", "Translate"),
        ("vault", "Vault"), ("calendar", "Calendar"), ("clipboard", "Clipboard"), ("emoji", "Emoji"),
        ("ask", "Ask Glyf"), ("dictation", "Voice"), ("glyfs", "My glyfs"),
        ("shorthand", "Shorthand"), ("keys", "Keys"), ("pay", "Pay"),
        ("settings", "Settings"),
    ]

    /// The saved order, with tools added since it was saved at the end.
    static var menuOrder: [String] {
        let known = tools.map(\.id)
        let saved = (SettingsStore.current.menuOrder ?? []).filter(known.contains)
        return saved + known.filter { !saved.contains($0) }
    }

    private var order: [String] = []
    private var tileViews: [String: UIControl] = [:]
    private var draggingTile: String?

    private static let stateFile = "shell-state.json"

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

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

        table.backgroundColor = Glass.touchableGrid
        table.separatorStyle = .none   // the cells draw the group's own hairlines
        table.contentInset.bottom = 8
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
        if isRoot, draggingTile == nil { layoutGrid() }
        if isVault { layoutVaultGrid() }
        footerButton.frame = CGRect(x: 0, y: bounds.height - footerH,
                                    width: bounds.width, height: footerH)
        footerButton.isHidden = footerH == 0
    }

    // MARK: Root launcher grid

    private func buildGrid() {
        grid.alwaysBounceVertical = true
        grid.showsVerticalScrollIndicator = false
        order = Self.menuOrder
        for (id, title) in Self.tools {
            let cell = UIControl()
            cell.accessibilityLabel = title
            cell.accessibilityIdentifier = "shell:tile:\(id)"
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = .button

            let card = UIView()
            card.tag = 1
            card.backgroundColor = Glass.surfaceCard
            card.layer.cornerRadius = 14
            card.layer.cornerCurve = .continuous
            if !Glass.solidLook {
                card.layer.borderWidth = 1
                card.layer.borderColor = Glass.strokeHairline.cgColor
            }
            card.isUserInteractionEnabled = false
            cell.addSubview(card)

            let icon = UIImageView(image: UIImage(systemName: GlyfToolbar.icons[id] ?? "square"))
            icon.tag = 2
            icon.tintColor = Glass.textPrimary
            icon.contentMode = .center
            icon.preferredSymbolConfiguration = .init(pointSize: 22, weight: .regular)
            icon.isUserInteractionEnabled = false
            cell.addSubview(icon)

            let label = UILabel()
            label.tag = 3
            label.text = title
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = Glass.textPrimary
            label.textAlignment = .center
            label.isUserInteractionEnabled = false
            cell.addSubview(label)

            cell.addAction(UIAction { [weak self] _ in
                self?.delegate?.shellOpenTool(id)
            }, for: .touchUpInside)
            // Hold a tile to pick it up: move it around the grid to reorder,
            // or up onto the strip to keep it there.
            let drag = UILongPressGestureRecognizer(target: self, action: #selector(tileDrag(_:)))
            drag.minimumPressDuration = 0.3
            drag.allowableMovement = 10   // moving first is a scroll, not a pick-up
            cell.addGestureRecognizer(drag)
            grid.addSubview(cell)
            tileViews[id] = cell
        }
    }

    @objc private func tileDrag(_ g: UILongPressGestureRecognizer) {
        guard let cell = g.view as? UIControl,
              let id = tileViews.first(where: { $0.value === cell })?.key else { return }
        let point = cell.convert(g.location(in: cell), to: window)
        switch g.state {
        case .began:
            draggingTile = id
            grid.isScrollEnabled = false
            UIView.animate(withDuration: 0.15) { cell.alpha = 0.3 }
            delegate?.shellTileDragBegan(id, icon: GlyfToolbar.icons[id] ?? "square", at: point)
        case .changed:
            delegate?.shellTileDragMoved(to: point)
            let inGrid = g.location(in: grid)
            guard grid.bounds.contains(inGrid), let to = tileIndex(at: inGrid),
                  let from = order.firstIndex(of: id), to != from else { break }
            order.remove(at: from)
            order.insert(id, at: to)
            // The picked-up tile slides into its new slot as a faint
            // placeholder; the ghost under the finger shows what is moving.
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                self.layoutGrid()
            }
        case .ended, .cancelled, .failed:
            draggingTile = nil
            grid.isScrollEnabled = true
            UIView.animate(withDuration: 0.15) {
                cell.alpha = 1
                self.layoutGrid()
            }
            if order != Self.menuOrder {
                let saved = order
                SettingsStore.update { $0.menuOrder = saved }
            }
            delegate?.shellTileDragEnded(at: point)
        default:
            break
        }
    }

    private static let gridCols = 4
    private static let gridGap: CGFloat = 8
    private static let gridSide: CGFloat = 6
    /// Two rows fill the panel with the third peeking in, so the grid shows
    /// at a glance that it scrolls.
    private var tileHeight: CGFloat { max(64, (grid.bounds.height - 40 - Self.gridGap) / 2) }

    private func tileIndex(at p: CGPoint) -> Int? {
        let cols = Self.gridCols
        let cellW = (grid.bounds.width - Self.gridSide * 2 - Self.gridGap * CGFloat(cols - 1))
            / CGFloat(cols)
        let c = Int((p.x - Self.gridSide) / (cellW + Self.gridGap))
        let r = Int(p.y / (tileHeight + Self.gridGap))
        guard c >= 0, c < cols, r >= 0 else { return nil }
        return min(order.count - 1, r * cols + c)
    }

    /// Tiles in `order`, four to a row.
    private func layoutGrid() {
        let cols = Self.gridCols, gap = Self.gridGap, side = Self.gridSide
        let cellW = (grid.bounds.width - side * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = tileHeight
        for (i, id) in order.enumerated() {
            guard let cell = tileViews[id] else { continue }
            let r = i / cols, c = i % cols
            let frame = CGRect(x: side + CGFloat(c) * (cellW + gap),
                               y: CGFloat(r) * (cellH + gap),
                               width: cellW, height: cellH)
            cell.frame = frame
            cell.viewWithTag(1)?.frame = CGRect(origin: .zero, size: frame.size)
            // Icon over caption, centred as a column with an 8pt gap.
            let iconH: CGFloat = 26, capH: CGFloat = 15
            let top = (cellH - iconH - 8 - capH) / 2
            cell.viewWithTag(2)?.frame = CGRect(x: 0, y: top, width: cellW, height: iconH)
            cell.viewWithTag(3)?.frame = CGRect(x: 2, y: top + iconH + 8,
                                                width: cellW - 4, height: capH)
        }
        let rows = Int(ceil(Double(order.count) / Double(cols)))
        grid.contentSize = CGSize(width: grid.bounds.width,
                                  height: CGFloat(rows) * (cellH + gap) - gap + side)
    }

    // MARK: Vault grid (website 6.3)

    /// Nine cards, three to a row: label above value, tap inserts.
    private func buildVaultGrid() {
        vaultGrid.subviews.forEach { $0.removeFromSuperview() }
        let vault = VaultStore.shared.load()
        vaultCards = vault.fields.map {
            .text(label: $0.label.uppercased(), value: $0.value, insert: $0.value)
        }
        for note in NotesStore.shared.load() {
            vaultCards.append(.note(note))
        }
        for image in vault.images {
            vaultCards.append(.image(image))
        }
        vaultCards.append(.newNote)
        for (i, item) in vaultCards.enumerated() {
            let labelText: String
            let valueText: String
            switch item {
            case .text(let l, let v, _): labelText = l; valueText = v
            case .note(let n): labelText = "NOTE"; valueText = n.text
            case .newNote: labelText = ""; valueText = "＋ New note"
            case .image(let img): labelText = "IMAGE"; valueText = ShellCell.age(img.addedAt)
            }
            let cell = UIControl()
            cell.tag = 2000 + i
            cell.accessibilityLabel = "\(labelText), \(valueText)"
            cell.accessibilityIdentifier = "vault:card:\(i)"
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = .button

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

            // An image tile is the picture itself, filling the card.
            if case .image(let img) = item,
               let data = VaultStore.shared.imageData(id: img.id),
               let thumb = UIImage(data: data) {
                let view = UIImageView(image: thumb)
                view.tag = 4
                view.contentMode = .scaleAspectFill
                view.clipsToBounds = true
                view.layer.cornerRadius = 12
                view.layer.cornerCurve = .continuous
                view.isUserInteractionEnabled = false
                cell.addSubview(view)
            }

            let label = UILabel()
            label.tag = 2
            label.attributedText = NSAttributedString(
                string: labelText,
                attributes: [.kern: 0.44,
                             .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                             .foregroundColor: Glass.textSecondary])
            label.isUserInteractionEnabled = false
            label.isHidden = {
                switch item { case .image, .newNote: return true; default: return false }
            }()
            cell.addSubview(label)

            let value = UILabel()
            value.tag = 3
            value.text = valueText
            value.font = .systemFont(ofSize: 13, weight: .medium)
            value.textColor = { if case .newNote = item { return Glass.accentPrimary }; return Glass.textPrimary }()
            value.lineBreakMode = .byTruncatingTail
            value.isUserInteractionEnabled = false
            value.isHidden = { if case .image = item { return true }; return false }()
            if case .newNote = item {
                value.textAlignment = .center
                value.numberOfLines = 1
            }
            cell.addSubview(value)

            cell.addAction(UIAction { [weak self] _ in
                switch item {
                case .text(_, _, let insert):
                    self?.delegate?.shellInsertText(insert)
                case .note(let n):
                    self?.delegate?.shellInsertText(n.text)
                case .newNote:
                    self?.delegate?.shellEditNote(id: nil, text: "")
                case .image(let img):
                    self?.delegate?.shellCopyImage(id: img.id)
                }
            }, for: .touchUpInside)
            if case .note = item {
                let hold = UILongPressGestureRecognizer(target: self, action: #selector(noteCardHeld(_:)))
                hold.minimumPressDuration = 0.4
                cell.addGestureRecognizer(hold)
                cell.accessibilityHint = "Hold to edit"
            }
            vaultGrid.addSubview(cell)
        }
    }

    /// Holding a note card opens it in the editor strip, the way the list's
    /// ✎ does; a tap keeps inserting.
    @objc private func noteCardHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let cell = g.view,
              vaultCards.indices.contains(cell.tag - 2000),
              case .note(let n) = vaultCards[cell.tag - 2000] else { return }
        delegate?.shellEditNote(id: n.id, text: n.text)
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
            cell.viewWithTag(4)?.frame = cell.bounds          // image fills it
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

    /// The screen on top: "root", "vault", …
    var screenId: String { screen?.id ?? "root" }

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

    /// Always the menu. The shell used to reopen whatever screen was up in
    /// the last minute, so g could land on Vault instead of the grid.
    private func restoreOrRoot() {
        stack = ["root"]
        render()
    }

    // MARK: Screens as data (§6.3 table)

    static func build(id: String) -> Screen {
        switch id {
        case "root":
            // Drawn as the tool grid, not as rows.
            return Screen(id: id, title: "Glyf", rows: [], showOpenInApp: false)

        case "settings":
            // The same sections and words as the app's Keyboard screen, so
            // a setting reads the same wherever it is found.
            return Screen(id: id, title: "Settings", rows: [
                .segmented(title: "Appearance",
                           options: ["auto", "light", "dark"],
                           value: { SettingsStore.current.appearance ?? "auto" },
                           set: { v in SettingsStore.update { $0.appearance = v } }),
                .header(title: "Typing"),
                .toggle(title: "Autocorrect",
                        value: { SettingsStore.current.autocorrect },
                        set: { v in SettingsStore.update { $0.autocorrect = v } }),
                .toggle(title: "Correct automatically",
                        value: { SettingsStore.current.autocorrectApply ?? true },
                        set: { v in SettingsStore.update { $0.autocorrectApply = v } }),
                .toggle(title: "Suggestions",
                        value: { SettingsStore.current.candidates },
                        set: { v in SettingsStore.update { $0.candidates = v } }),
                .toggle(title: "Auto-capitalize",
                        value: { SettingsStore.current.autocapitalize },
                        set: { v in SettingsStore.update { $0.autocapitalize = v } }),
                .toggle(title: "Double-space for period",
                        value: { SettingsStore.current.periodShortcut },
                        set: { v in SettingsStore.update { $0.periodShortcut = v } }),
                .toggle(title: "Number row",
                        value: { SettingsStore.current.numberRow },
                        set: { v in SettingsStore.update { $0.numberRow = v } }),
                .segmented(title: "One-handed",
                           options: ["off", "left", "right"],
                           value: { SettingsStore.current.oneHanded },
                           set: { v in SettingsStore.update { $0.oneHanded = v } }),
                .header(title: "Feel"),
                .toggle(title: "Sound on keypress",
                        value: { SettingsStore.current.keyClicks },
                        set: { v in SettingsStore.update { $0.keyClicks = v } }),
                .toggle(title: "Haptic feedback on keypress",
                        value: { SettingsStore.current.haptics },
                        set: { v in SettingsStore.update { $0.haptics = v } }),
                .header(title: "More"),
                .toggle(title: "Paste title with link",
                        value: { (SettingsStore.current.pasteStyle ?? "titleAndLink") == "titleAndLink" },
                        set: { on in
                            SettingsStore.update { $0.pasteStyle = on ? "titleAndLink" : "linkOnly" }
                        }),
                .nav(icon: "slider.horizontal.3", title: "Toolbar items", detail: nil,
                     target: "toolbar"),
            ], showOpenInApp: false)

        case "toolbar":
            // One row per item: its switch, and a ↑ that moves it a place
            // up the strip (the first item has nowhere to go).
            var rows: [Row] = []
            for (position, itemId) in SettingsStore.current.toolbarOrder.enumerated() {
                let moveUp: (() -> Void)? = position == 0 ? nil : {
                    SettingsStore.update { s in
                        if let i = s.toolbarOrder.firstIndex(of: itemId), i > 0 {
                            s.toolbarOrder.swapAt(i, i - 1)
                        }
                    }
                }
                rows.append(.toggle(
                    title: itemId.capitalized,
                    value: { !SettingsStore.current.toolbarHidden.contains(itemId) },
                    set: { visible in
                        SettingsStore.update { s in
                            s.toolbarHidden.removeAll { $0 == itemId }
                            if !visible { s.toolbarHidden.append(itemId) }
                        }
                    },
                    moveUp: moveUp))
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
            return Screen(id: id, title: "Keys", rows: rows, appPath: "keys")

        case "glyfs":
            // The glyfs this person built in the app. Tap one to run it on
            // what is being typed; the key it sits on shows alongside.
            let s = SettingsStore.current
            var rows: [Row] = (s.customTitles ?? [:])
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
                .map { glyfId, title in
                    let key = s.bindings.first { $0.value == glyfId }?.key
                    return .nav(icon: "sparkles", title: title,
                                detail: key.map { "Hold \($0.uppercased())" },
                                target: "!run:\(glyfId)")
                }
            rows.append(.nav(icon: "plus", title: "Build your own", detail: nil,
                             target: "!app:build"))
            return Screen(id: id, title: "My glyfs", rows: rows, showOpenInApp: false)

        case "connectors":
            return Screen(id: id, title: "Connectors", rows: [
                .nav(icon: "calendar", title: "Calendar", detail: nil, target: "!connector:calendar"),
            ], appPath: "connectors")

        case "vault":
            let vault = VaultStore.shared.load()
            NotesStore.shared.invalidate() // the app may have edited them
            var rows: [Row] = []
            for field in vault.fields {
                rows.append(.vaultField(field))
            }
            for note in NotesStore.shared.load() {
                rows.append(.note(note))
            }
            for image in vault.images {
                rows.append(.vaultImage(image))
            }
            rows.append(.action(title: "＋ New note", style: .accent, handler: {}))
            return Screen(id: id, title: "Vault", rows: rows, appPath: "vault")

        default:
            return Screen(id: id, title: id, rows: [.info(title: "…", detail: nil)])
        }
    }

    // MARK: Table plumbing (ONE table, reused cells)

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { screen.rows.count }

    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip) as! ShellCell
        cell.configure(row: screen.rows[ip.row], shell: self, place: place(of: ip.row))
        return cell
    }

    func tableView(_ t: UITableView, heightForRowAt ip: IndexPath) -> CGFloat {
        switch screen.rows[ip.row] {
        case .header: return ShellCell.headerHeight
        case .info: return ShellCell.footerHeight
        default:
            return (Glass.solidLook ? ShellCell.rowHeight : ShellCell.twoLineHeight)
                + place(of: ip.row).gap
        }
    }

    /// Rows join the group of their neighbours unless a title, a footer or
    /// a standalone action (an accent or danger button, in its own card the
    /// way Settings sets "Sign Out" apart) comes between. The first row of
    /// a group with no title above it keeps some air instead.
    private func place(of i: Int) -> ShellCell.Place {
        let rows = screen.rows
        func carded(_ r: Row) -> Bool {
            switch r {
            case .header, .info: return false
            default: return true
            }
        }
        func solo(_ r: Row) -> Bool {
            if case .action(_, let style, _) = r { return style != .plain }
            return false
        }
        let me = rows[i]
        let prev = i > 0 ? rows[i - 1] : nil
        let next = i + 1 < rows.count ? rows[i + 1] : nil
        let first = prev.map { !carded($0) || solo($0) || solo(me) } ?? true
        let last = next.map { !carded($0) || solo($0) || solo(me) } ?? true
        var gap: CGFloat = 0
        if first {
            if let prev {
                if case .header = prev { gap = 0 } else { gap = ShellCell.groupGap }
            } else {
                gap = 6
            }
        }
        return ShellCell.Place(first: first, last: last, gap: gap)
    }

    func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        switch screen.rows[ip.row] {
        case .nav(_, _, _, let target):
            if target == "!none" { break }
            if target.hasPrefix("!run:") {
                delegate?.shellRunGlyf(String(target.dropFirst("!run:".count)))
            } else if target.hasPrefix("!app:") {
                delegate?.shellOpenApp(path: String(target.dropFirst("!app:".count)))
            } else if target.hasPrefix("!connector:") {
                delegate?.shellOpenTool(String(target.dropFirst("!connector:".count)))
            } else {
                push(target)
            }
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
        case .vaultImage(let image):
            // No keyboard can type a picture into a host text box, so the
            // most a tap can do is put it back on the clipboard, ready for
            // one hold-and-paste in the field.
            delegate?.shellCopyImage(id: image.id)
        case .binding:
            break // unbinding is the ✕ button, never a whole-row surprise
        case .toggle(_, let valueFn, let set, _):
            // The switch sits at the row's edge, where a thumb's tap often
            // lands just past it; the whole row flips it, and the switch
            // animates as if the thumb had landed on it.
            let on = !valueFn()
            (t.cellForRow(at: ip) as? ShellCell)?.toggle?.setOn(on, animated: true)
            set(on)
            rowChanged(reload: false)
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

    /// A control on a row changed a setting. The keyboard applies it first
    /// (appearance re-skins the keys, the number row changes the height),
    /// then the rows are rebuilt so the next dequeue reads the new value.
    /// The list is only reloaded when asked: a reload cuts a switch's own
    /// animation short, and a toggle never changes another row's look.
    fileprivate func rowChanged(reload: Bool) {
        delegate?.shellStateChanged()
        screen = Self.build(id: stack.last ?? "root")
        saveState()
        if reload { table.reloadData() }
    }
}

// MARK: - Cell

/// One row of an inset-grouped list, the way Settings draws one: the rows
/// of a group share a single rounded card, a hairline runs between them from
/// where the text starts, a section's title sits above its group in small
/// capitals, and the whole row answers a tap. Titles and footers are the
/// only rows without a card.
private final class ShellCell: UITableViewCell {
    private weak var shell: GlyfShell?

    /// Where a row sits in its group: which corners it rounds, whether a
    /// hairline runs under it, and the air above a group with no title.
    struct Place {
        var first = true
        var last = true
        var gap: CGFloat = 0
    }

    static let rowHeight: CGFloat = 44
    static let twoLineHeight: CGFloat = 52
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 32
    /// Between two groups when no title separates them.
    static let groupGap: CGFloat = 10
    /// The card's inset from the panel's edge, and the text's from the card.
    static let sideInset: CGFloat = 12
    static let textInset: CGFloat = 16
    static let radius: CGFloat = 12

    private enum Kind { case cell, header, footer }
    private var kind = Kind.cell
    private var place = Place()
    /// A nav row's detail sits at the right in grey, beside the chevron.
    private var detailRight = false

    // Row anatomy: [chip][title  value][trailing]
    private let card = UIView()
    private let separator = UIView()
    private let chip = UIView()
    private let chipIcon = UIImageView()
    private let chipLetter = UILabel()
    private let chipDot = UIView()
    private let title = UILabel()
    private let value = UILabel()
    private var trailing: UIView?
    /// A toggle row's switch, so a tap anywhere on the row flips it with
    /// the same animation a thumb on the switch gets.
    private(set) var toggle: UISwitch?

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
        backgroundColor = Glass.touchableGrid
        selectionStyle = .none

        card.layer.cornerRadius = Self.radius
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)
        card.addSubview(separator)

        chip.layer.cornerRadius = 7
        chip.layer.cornerCurve = .continuous
        card.addSubview(chip)
        chipIcon.contentMode = .center
        chipIcon.preferredSymbolConfiguration = .init(pointSize: 14, weight: .medium)
        chip.addSubview(chipIcon)
        chipLetter.font = .systemFont(ofSize: 14, weight: .bold)
        chipLetter.textAlignment = .center
        chip.addSubview(chipLetter)
        chipDot.layer.cornerRadius = 2
        chip.addSubview(chipDot)

        title.font = .systemFont(ofSize: 15)
        card.addSubview(title)
        value.font = .systemFont(ofSize: 15)
        value.lineBreakMode = .byTruncatingTail
        card.addSubview(value)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        let textX = Self.sideInset + Self.textInset
        switch kind {
        case .header:
            // The title hangs just above its group, on the text's own line.
            card.frame = b
            title.frame = CGRect(x: textX, y: b.height - 24, width: b.width - textX * 2, height: 18)
            return
        case .footer:
            card.frame = b
            title.frame = b.insetBy(dx: textX, dy: 0)
            return
        case .cell:
            break
        }

        card.frame = CGRect(x: Self.sideInset, y: place.gap,
                            width: b.width - Self.sideInset * 2, height: b.height - place.gap)
        var corners: CACornerMask = []
        if place.first { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if place.last { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        card.layer.maskedCorners = corners

        let cb = card.bounds
        let hasChip = !chip.isHidden
        chip.frame = CGRect(x: Self.textInset, y: (cb.height - 28) / 2, width: 28, height: 28)
        chipIcon.frame = chip.bounds
        chipLetter.frame = chip.bounds
        chipDot.frame = CGRect(x: 20, y: 4, width: 4, height: 4)
        let x = hasChip ? Self.textInset + 28 + 12 : Self.textInset
        var right = cb.width - Self.textInset
        if let tv = trailing {
            tv.frame = CGRect(x: right - tv.frame.width, y: (cb.height - tv.frame.height) / 2,
                              width: tv.frame.width, height: tv.frame.height)
            right = tv.frame.minX - 8
        }
        separator.isHidden = place.last
        separator.frame = CGRect(x: x, y: cb.height - Glass.hairlineWidth,
                                 width: cb.width - x, height: Glass.hairlineWidth)

        let w = max(0, right - x)
        if value.isHidden {
            title.frame = CGRect(x: x, y: 0, width: w, height: cb.height)
        } else if detailRight {
            // Settings' own arrangement: the title left, the detail in grey
            // at the right, beside the chevron.
            let dw = min(ceil(value.intrinsicContentSize.width), w * 0.55)
            value.frame = CGRect(x: x + w - dw, y: 0, width: dw, height: cb.height)
            title.frame = CGRect(x: x, y: 0, width: max(0, w - dw - 10), height: cb.height)
        } else if Glass.solidLook {
            // One line: a fixed key column, then the value (website rows).
            let keyW: CGFloat = min(92, w * 0.42)
            title.frame = CGRect(x: x, y: 0, width: keyW, height: cb.height)
            value.frame = CGRect(x: x + keyW + 10, y: 0,
                                 width: max(0, w - keyW - 10), height: cb.height)
        } else {
            title.frame = CGRect(x: x, y: 8, width: w, height: 19)
            value.frame = CGRect(x: x, y: 28, width: w, height: 16)
        }
    }

    /// A finger on a row darkens its card a touch, as Settings does.
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        guard kind == .cell else { return }
        let base = Glass.surfaceCard
        card.backgroundColor = highlighted ? base.blend(Glass.textPrimary, 0.08) : base
    }

    private func reset() {
        kind = .cell
        place = Place()
        detailRight = false
        card.backgroundColor = Glass.surfaceCard
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        separator.backgroundColor = Glass.strokeSeparator
        separator.isHidden = false
        chip.isHidden = true
        chipIcon.image = nil
        chipLetter.text = nil
        chipDot.isHidden = true
        chip.backgroundColor = Glass.fillField
        chipIcon.tintColor = Glass.textPrimary
        chipLetter.textColor = Glass.textPrimary
        chipDot.backgroundColor = Glass.accentPrimary
        title.text = nil
        title.attributedText = nil
        title.font = .systemFont(ofSize: 15)
        title.textColor = Glass.textPrimary
        title.textAlignment = .natural
        value.text = nil
        value.isHidden = true
        value.font = .systemFont(ofSize: 15)
        value.textColor = Glass.textSecondary
        value.textAlignment = .natural
        trailing?.removeFromSuperview()
        trailing = nil
        toggle = nil
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
        iv.tintColor = Glass.textSecondary.withAlphaComponent(0.55)
        iv.preferredSymbolConfiguration = .init(pointSize: 14, weight: .semibold)
        iv.contentMode = .center
        iv.frame = CGRect(x: 0, y: 0, width: 14, height: 20)
        return iv
    }

    private func iconButton(_ name: String, tint: UIColor,
                            action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: name), for: .normal)
        b.setPreferredSymbolConfiguration(.init(pointSize: 14, weight: .semibold),
                                          forImageIn: .normal)
        b.tintColor = tint
        b.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    func configure(row: GlyfShell.Row, shell: GlyfShell, place: Place) {
        self.shell = shell
        reset()
        self.place = place

        switch row {
        case .header(let t):
            kind = .header
            card.backgroundColor = .clear
            separator.isHidden = true
            title.attributedText = NSAttributedString(
                string: t.uppercased(),
                attributes: [.font: UIFont.systemFont(ofSize: 13),
                             .foregroundColor: Glass.textSecondary,
                             .kern: 0.4])
        case .info(let t, _):
            kind = .footer
            card.backgroundColor = .clear
            separator.isHidden = true
            title.text = t
            title.font = .systemFont(ofSize: 13)
            title.textColor = Glass.textSecondary
            title.textAlignment = .center
        case .nav(let icon, let t, let detail, let target):
            setIcon(icon)
            title.text = t
            if let detail, !detail.isEmpty {
                value.isHidden = false
                value.text = detail
                value.textAlignment = .right
                detailRight = true
            }
            if target != "!none" { setTrailing(chevron()) }
        case .insert(let icon, let t, _):
            setIcon(icon)
            title.text = preview(t)
            accessibilityIdentifier = "note:\(preview(t))"
        case .toggle(let t, let valueFn, let set, let moveUp):
            title.text = t
            let sw = UISwitch()
            sw.isOn = valueFn()
            sw.onTintColor = Glass.accentPrimary
            sw.sizeToFit()
            sw.addAction(UIAction { [weak self] a in
                guard let s = a.sender as? UISwitch else { return }
                set(s.isOn)
                self?.shell?.rowChanged(reload: false)
            }, for: .valueChanged)
            toggle = sw
            if let moveUp {
                // [↑][switch], the arrow a full tap target of its own.
                let up = iconButton("arrow.up", tint: Glass.textSecondary) { [weak self] in
                    moveUp()
                    self?.shell?.rowChanged(reload: true)
                }
                up.accessibilityIdentifier = "toggle:\(t):up"
                let pair = UIView(frame: CGRect(x: 0, y: 0,
                                                width: up.frame.width + 6 + sw.frame.width,
                                                height: max(up.frame.height, sw.frame.height)))
                up.frame.origin = CGPoint(x: 0, y: (pair.bounds.height - up.frame.height) / 2)
                sw.frame.origin = CGPoint(x: pair.bounds.width - sw.frame.width,
                                          y: (pair.bounds.height - sw.frame.height) / 2)
                pair.addSubview(up)
                pair.addSubview(sw)
                setTrailing(pair)
            } else {
                setTrailing(sw)
            }
            accessibilityIdentifier = "toggle:\(t)"
        case .segmented(let t, let options, let valueFn, let set):
            title.text = t
            let seg = UISegmentedControl(items: options.map(\.capitalized))
            seg.selectedSegmentIndex = options.firstIndex(of: valueFn()) ?? 0
            seg.selectedSegmentTintColor = Glass.accentPrimary
            seg.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 13, weight: .medium),
                                        .foregroundColor: Glass.textPrimary], for: .normal)
            seg.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                                        .foregroundColor: UIColor.white], for: .selected)
            seg.addAction(UIAction { [weak self] a in
                guard let s = a.sender as? UISegmentedControl,
                      s.selectedSegmentIndex >= 0 else { return }
                set(options[s.selectedSegmentIndex])
                // Appearance re-skins everything, this list included.
                self?.shell?.rowChanged(reload: true)
            }, for: .valueChanged)
            seg.sizeToFit()
            seg.frame = CGRect(x: 0, y: 0, width: max(seg.frame.width, 168), height: 30)
            setTrailing(seg)
        case .action(let t, let style, _):
            title.text = t
            switch style {
            case .accent:
                title.textAlignment = .center
                title.textColor = Glass.accentPrimary
            case .danger:
                title.textAlignment = .center
                title.textColor = Glass.accentDanger
            case .plain:
                title.textColor = Glass.textSecondary
            }
        case .clip(let item):
            // Website row: how long ago on the left, the text beside it.
            if Glass.solidLook {
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
                self?.shell?.rowChanged(reload: true)
            })
        case .binding(let key, let glyfId):
            chip.isHidden = false
            chip.backgroundColor = Glass.fillField
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
            chip.backgroundColor = Glass.fillField
            chipLetter.text = ";"
            chipLetter.textColor = Glass.accentPrimary
            title.text = trigger
            value.isHidden = false
            value.text = preview(text)
            accessibilityIdentifier = "snippet:\(trigger)"
        case .vaultImage(let image):
            setIcon("photo")
            title.text = image.label
            value.isHidden = false
            value.text = Self.age(image.addedAt)
            accessibilityIdentifier = "vault:image:\(image.id)"
            // The thumbnail is decrypted here, for this row only — the vault
            // file itself never carries the pixels.
            if let data = VaultStore.shared.imageData(id: image.id),
               let thumb = UIImage(data: data) {
                let view = UIImageView(image: thumb)
                view.contentMode = .scaleAspectFill
                view.clipsToBounds = true
                view.layer.cornerRadius = 6
                view.layer.cornerCurve = .continuous
                view.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
                setTrailing(view)
            }
        }
    }
}
