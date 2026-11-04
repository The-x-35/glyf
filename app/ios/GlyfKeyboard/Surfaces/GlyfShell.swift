import UIKit

protocol GlyfShellDelegate: AnyObject {
    func shellClosed()
    func shellInsertText(_ text: String)
    /// A shorthand typed out, its blanks ({date}, {cursor}…) filled.
    func shellInsertShorthand(_ text: String)
    /// Typed into the message with the panel left open (temp mail's
    /// Insert: its inbox is still being watched).
    func shellInsertTextStaying(_ text: String)
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
    /// Opens the editor strip for a new detail of this kind.
    func shellAddDetail(_ kind: DetailKind)
    /// Opens the editor strip for a new shorthand.
    func shellAddShorthand()
    /// My glyfs: does what holding this letter does.
    func shellRunKey(_ letter: String)
    /// Puts a vault image back on the clipboard, ready to paste into a field.
    func shellCopyImage(id: String)
    /// Puts text on the clipboard (a temp address, a code) and says so.
    func shellCopyText(_ text: String)
    /// Opens a web page in the browser (temp mail's credit to mail.tm).
    func shellOpenLink(_ url: URL)
    /// Style: the words picked out, or the message so far, in a style.
    func shellApplyStyle(_ id: String)
}

/// §6.3 — the in-keyboard navigation shell. HARD memory rules:
/// screens are DATA (`ShellScreen` structs) rendered by ONE reusable
/// UITableView; pop = discard data, never a VC tree; icons ≤20pt SF Symbols.
final class GlyfShell: UIView, UITableViewDataSource, UITableViewDelegate {

    weak var delegate: GlyfShellDelegate?

    enum ActionStyle { case plain, accent, danger }

    /// What the vault adds without leaving the keyboard. Only a picture
    /// cannot be: no keyboard can take one in.
    enum Adding: String, CaseIterable {
        case note, detail, shorthand

        var title: String {
            switch self {
            case .note: return "New note"
            case .detail: return "New detail"
            case .shorthand: return "New shorthand"
            }
        }

        /// The app's Vault marks each the same way: a note, a detail card,
        /// and shorthand's bolt.
        var symbol: String {
            switch self {
            case .note: return "note.text"
            case .detail: return "person.text.rectangle"
            case .shorthand: return "bolt"
            }
        }
    }

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
    /// The vault draws as the website's 3-column card grid, not a list, and
    /// so does its New detail screen.
    private let vaultGrid = ControlScrollView()
    /// A tile in the vault grid. Text tiles insert; an image tile can only
    /// go back on the clipboard, since no keyboard can type a picture into a
    /// host field. Editing and deleting happen in the APP; a note, a detail
    /// or a shorthand can be added right here, from the + in the corner.
    enum VaultCard {
        case text(label: String, value: String, insert: String)
        case image(VaultImage)
        /// A note inserts on tap and opens for editing on a hold.
        case note(GlyfNote)
        /// A shorthand types what it expands to, as its shortcut would.
        case snippet(VaultSnippet)
        /// New detail: one kind it can be.
        case kind(DetailKind)
    }

    private var vaultCards: [VaultCard] = []

    /// The vault's one way to add (user, 2026-09-29: "a single plus icon
    /// floating button in bottom right corner, which expands to show this as
    /// options"). It floats over the cards, so it stays put while they
    /// scroll and shows on an empty vault too; a tap stacks the three
    /// options above it and turns the + into a ×.
    private let addButton = UIButton(type: .custom)
    private let addIcon = UIImageView(image: UIImage(systemName: "plus"))
    private var addOptions: [UIControl] = []
    /// Dims the panel behind the options; a tap on it closes them.
    private let addScrim = UIControl()
    private var addOpen = false
    private static let addSize: CGFloat = 46
    private static let addMargin: CGFloat = 12
    /// What the lists keep clear below their last card, so it can scroll out
    /// from under the +.
    private static var addClearance: CGFloat { addSize + addMargin + 6 }
    /// Every tool, in the website's order first. The ids are the strip's, so
    /// any tile can be dragged up to live there. People reorder them by
    /// holding one and moving it (saved as `menuOrder`).
    static let tools: [(id: String, title: String)] = [
        ("search", "Search"), ("rewrite", "Rewrite"), ("style", "Style"), ("translate", "Translate"),
        ("vault", "Vault"), ("calendar", "Calendar"), ("tempmail", "Temp mail"),
        ("clipboard", "Clipboard"), ("gifs", "GIFs"),
        ("ask", "Ask Glyf"), ("dictation", "Voice"), ("glyfs", "My glyfs"),
        ("pay", "Pay"), ("games", "Games"), ("settings", "Settings"),
    ]

    /// The saved order, with tools added since it was saved at the end. An
    /// order saved with Emoji, Keys or Shorthand in it places the tools that
    /// took them over.
    static var menuOrder: [String] {
        let known = tools.map(\.id)
        var saved: [String] = []
        for id in (SettingsStore.current.menuOrder ?? []).map(GlyfSettings.Toolbar.canonical)
        where known.contains(id) && !saved.contains(id) {
            saved.append(id)
        }
        return saved + known.filter { !saved.contains($0) }
    }

    /// What the menu shows: every tool that is not on the strip right now.
    /// A tool lives in one place, so taking it off the strip is what brings
    /// it back here.
    static var menuTools: [String] {
        let strip = Set(GlyfToolbar.shownTools)
        return menuOrder.filter { !strip.contains($0) && ($0 != "pay" || GlyfToolbar.walletOn) }
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
        table.noEdgeEffects()

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

        buildAddButton()
        buildTempMail()
        restoreOrRoot()
    }

    /// Temp mail's two screens: the inbox, and one mail open.
    private let tempMailView = TempMailView()

    private func buildTempMail() {
        tempMailView.isHidden = true
        // Insert types and stays (Arpit, 2026-10-01: "when i click insert in
        // temp mail i should not redirect back to keyboard, should stay here").
        tempMailView.onInsert = { [weak self] text in self?.delegate?.shellInsertTextStaying(text) }
        tempMailView.onCopy = { [weak self] text in self?.delegate?.shellCopyText(text) }
        tempMailView.onOpenLink = { [weak self] url in self?.delegate?.shellOpenLink(url) }
        tempMailView.onOpenMail = { [weak self] id in
            TempMailWatcher.shared.openedId = id
            self?.push("tempmail:mail")
        }
        addSubview(tempMailView)
    }

    private var showsTempMail: Bool { screen?.id.hasPrefix("tempmail") == true }

    /// The +, its three options and the scrim behind them, over everything
    /// the panel scrolls.
    private func buildAddButton() {
        // No wash over the cards (Arpit: "why white layover when menu open,
        // that looks bad"): the layer only catches the tap that closes the
        // options. Not .clear: an extension drops touches on clear pixels.
        addScrim.backgroundColor = Glass.touchableGrid
        addScrim.alpha = 0
        addScrim.isHidden = true
        addScrim.addAction(UIAction { [weak self] _ in self?.setAddOpen(false) }, for: .touchUpInside)
        addSubview(addScrim)

        for adding in Adding.allCases {
            // The cards' own look, as a pill: an accent mark, then the words.
            let option = UIControl()
            option.backgroundColor = Glass.surfaceCard
            option.layer.cornerCurve = .continuous
            option.layer.shadowColor = UIColor.black.cgColor
            option.layer.shadowOpacity = 0.12
            option.layer.shadowRadius = 8
            option.layer.shadowOffset = CGSize(width: 0, height: 2)
            option.accessibilityIdentifier = "vault:new:\(adding.rawValue)"
            option.accessibilityLabel = adding.title
            option.isAccessibilityElement = true
            option.accessibilityTraits = .button
            option.isHidden = true
            let mark = UIImageView(image: UIImage(systemName: adding.symbol))
            mark.tag = 1
            mark.tintColor = Glass.accentPrimary
            mark.contentMode = .center
            mark.preferredSymbolConfiguration = .init(pointSize: 14, weight: .semibold)
            mark.isUserInteractionEnabled = false
            option.addSubview(mark)
            let title = UILabel()
            title.tag = 2
            title.text = adding.title
            title.font = .systemFont(ofSize: 15, weight: .medium)
            title.textColor = Glass.textPrimary
            title.isUserInteractionEnabled = false
            option.addSubview(title)
            option.addAction(UIAction { [weak self] _ in
                self?.setAddOpen(false, animated: false)
                self?.add(adding)
            }, for: .touchUpInside)
            addSubview(option)
            addOptions.append(option)
        }

        // Filled accent, a white +, and only the hairline shadow the cards
        // and keys stand on.
        addButton.backgroundColor = Glass.accentPrimary
        addButton.layer.cornerRadius = Self.addSize / 2
        addButton.layer.shadowColor = Glass.keyShadowColor.cgColor
        addButton.layer.shadowOpacity = Glass.keyShadowOpacity
        addButton.layer.shadowOffset = Glass.keyShadowOffset
        addButton.layer.shadowRadius = 0
        addButton.accessibilityIdentifier = "vault:add"
        addButton.accessibilityLabel = "Add"
        addButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setAddOpen(!self.addOpen)
        }, for: .touchUpInside)
        addIcon.tintColor = .white
        addIcon.contentMode = .center
        addIcon.preferredSymbolConfiguration = .init(pointSize: 20, weight: .semibold)
        addIcon.isUserInteractionEnabled = false
        addButton.addSubview(addIcon)
        addSubview(addButton)
    }

    /// Opens or closes the three options; the + turns an eighth of a turn
    /// into a ×, and back.
    private func setAddOpen(_ open: Bool, animated: Bool = true) {
        guard open != addOpen else { return }
        addOpen = open
        addButton.accessibilityLabel = open ? "Close" : "Add"
        let rest = CGAffineTransform(translationX: 0, y: 8)
        if open {
            addScrim.isHidden = false
            for option in addOptions {
                option.isHidden = false
                option.alpha = 0
                option.transform = rest
            }
        }
        let change = {
            self.addIcon.transform = open ? CGAffineTransform(rotationAngle: .pi / 4) : .identity
            self.addScrim.alpha = open ? 1 : 0
            for option in self.addOptions {
                option.alpha = open ? 1 : 0
                option.transform = open ? .identity : rest
            }
        }
        let finish = { (_: Bool) in
            // Hidden once closed, so nothing under them takes a touch.
            guard !self.addOpen else { return }
            self.addScrim.isHidden = true
            for option in self.addOptions {
                option.isHidden = true
                option.transform = .identity
            }
        }
        if animated, !Glass.reduceMotion {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState],
                           animations: change, completion: finish)
        } else {
            change()
            finish(true)
        }
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
        let isVault = usesCardGrid
        let isTempMail = showsTempMail
        // Grids fill the panel the way the website does; only list screens
        // keep the "open in the app" line.
        let footerH: CGFloat = screen.showOpenInApp && !isRoot && !isVault ? 30 : 0
        table.isHidden = isRoot || isVault || isTempMail
        tempMailView.isHidden = !isTempMail
        grid.isHidden = !isRoot
        vaultGrid.isHidden = !isVault
        table.frame = CGRect(x: 0, y: headerH, width: bounds.width,
                             height: bounds.height - headerH - footerH)
        grid.frame = table.frame
        vaultGrid.frame = table.frame
        tempMailView.frame = table.frame
        if isRoot, draggingTile == nil { layoutGrid() }
        if isVault { layoutVaultGrid() }
        footerButton.frame = CGRect(x: 0, y: bounds.height - footerH,
                                    width: bounds.width, height: footerH)
        footerButton.isHidden = footerH == 0
        layoutAddButton(in: table.frame)
    }

    /// The + in the corner of what scrolls (above the "open in the app"
    /// line in the list look), its options stacked over it, flush right.
    private func layoutAddButton(in area: CGRect) {
        addButton.isHidden = screen.id != "vault"
        guard !addButton.isHidden else { return }
        let s = Self.addSize, m = Self.addMargin
        addButton.frame = CGRect(x: area.maxX - m - s, y: area.maxY - m - s, width: s, height: s)
        // Bounds and centre, not frame: the icon may be turned into a ×.
        addIcon.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        addIcon.center = CGPoint(x: s / 2, y: s / 2)
        addScrim.frame = CGRect(x: 0, y: area.minY, width: bounds.width, height: bounds.height - area.minY)

        // Three pills of one width, as tall as the room allows: an iPhone on
        // its side has little over half a portrait panel.
        let gap: CGFloat = 6
        let room = addButton.frame.minY - 10 - (area.minY + 6)
        let h = max(28, min(36, floor((room - gap * 2) / 3)))
        let textW = addOptions.compactMap { ($0.viewWithTag(2) as? UILabel)?.intrinsicContentSize.width }.max() ?? 90
        let w = ceil(14 + 18 + 8 + textW + 18)
        var y = addButton.frame.minY - 10 - h * 3 - gap * 2
        for option in addOptions {
            // Bounds and centre again: an option may be mid-slide.
            option.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            option.center = CGPoint(x: addButton.frame.maxX - w / 2, y: y + h / 2)
            option.layer.cornerRadius = h / 2
            option.viewWithTag(1)?.frame = CGRect(x: 14, y: 0, width: 18, height: h)
            option.viewWithTag(2)?.frame = CGRect(x: 14 + 18 + 8, y: 0, width: ceil(textW), height: h)
            y += h + gap
        }
    }

    // MARK: Root launcher grid

    /// The vault and its New detail screen are cards in the website's look.
    private var usesCardGrid: Bool {
        Glass.solidLook && (screen.id == "vault" || screen.id == "vault:detail")
    }

    private func buildGrid() {
        grid.alwaysBounceVertical = true
        grid.showsVerticalScrollIndicator = false
        order = Self.menuTools
        for (id, title) in Self.tools {
            let cell = UIControl()
            cell.accessibilityLabel = title
            cell.accessibilityIdentifier = "shell:tile:\(id)"
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = .button

            let card = UIView()
            card.tag = 1
            card.backgroundColor = Glass.surfaceTile
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
            // Android's name for the tool's glyph. The tile is the one element
            // VoiceOver and the tests see here, as shell:tile:<id>.
            icon.accessibilityIdentifier = "menu:\(id)"
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
            cell.isHidden = !order.contains(id)
            grid.addSubview(cell)
            tileViews[id] = cell
        }
    }

    /// The tiles for what is off the strip right now. The strip can change
    /// while the menu is up (Toolbar items), and what joined it leaves here.
    private func refreshGrid() {
        guard draggingTile == nil else { return }
        order = Self.menuTools
        for (id, cell) in tileViews { cell.isHidden = !order.contains(id) }
        setNeedsLayout()
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
            if order != Self.menuTools {
                // The strip's tools keep their places in the saved order, so
                // one that leaves the strip comes back where it was.
                let strip = Set(GlyfToolbar.shownTools)
                var moved = order.makeIterator()
                let saved = Self.menuOrder.map { strip.contains($0) ? $0 : (moved.next() ?? $0) }
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

    /// The slot a point is over, up to one past the last of `count` tiles.
    private func slotIndex(at p: CGPoint, count: Int) -> Int {
        let cols = Self.gridCols
        let cellW = (grid.bounds.width - Self.gridSide * 2 - Self.gridGap * CGFloat(cols - 1))
            / CGFloat(cols)
        let c = min(cols - 1, max(0, Int((p.x - Self.gridSide) / (cellW + Self.gridGap))))
        let r = max(0, Int(p.y / (tileHeight + Self.gridGap)))
        return min(count, r * cols + c)
    }

    /// Tiles in `order`, four to a row.
    private func layoutGrid() {
        let cols = Self.gridCols, gap = Self.gridGap, side = Self.gridSide
        for (i, id) in order.enumerated() {
            if let cell = tileViews[id] { layoutTile(cell, at: i) }
        }
        let rows = Int(ceil(Double(order.count) / Double(cols)))
        grid.contentSize = CGSize(width: grid.bounds.width,
                                  height: CGFloat(rows) * (tileHeight + gap) - gap + side)
    }

    private func layoutTile(_ cell: UIView, at i: Int) {
        let cols = Self.gridCols, gap = Self.gridGap, side = Self.gridSide
        let cellW = (grid.bounds.width - side * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = tileHeight
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

    // MARK: A tool dragged down from the strip

    /// A tool held on the strip, over the grid (window coordinates; nil once
    /// it left): its tile opens a slot where it would land, faint as a tile
    /// being moved is, and the tiles around it slide to make room. Away from
    /// the grid the slot closes again.
    func stripToolHovered(_ id: String, at windowPoint: CGPoint?) {
        guard screen.id == "root", draggingTile == nil, let cell = tileViews[id] else { return }
        var next = order.filter { $0 != id }
        if let windowPoint {
            let p = grid.convert(windowPoint, from: nil)
            if grid.bounds.contains(p) { next.insert(id, at: slotIndex(at: p, count: next.count)) }
        }
        guard next != order else { return }
        let arriving = !order.contains(id)
        order = next
        if let i = order.firstIndex(of: id) {
            if arriving {
                // Straight into its slot: only the tiles around it move.
                UIView.performWithoutAnimation {
                    cell.isHidden = false
                    cell.alpha = 0.3
                    layoutTile(cell, at: i)
                }
            }
        } else {
            cell.isHidden = true
            cell.alpha = 1
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.layoutGrid()
        }
    }

    /// The held strip tool let go over the grid: it keeps the slot it opened,
    /// saved in `menuOrder` with the strip's tools holding their places
    /// there. Where its tile is, in window coordinates; nil when it was not
    /// over the grid.
    func landStripTool(_ id: String, at windowPoint: CGPoint) -> CGRect? {
        stripToolHovered(id, at: windowPoint)
        guard order.contains(id), let cell = tileViews[id] else { return nil }
        var strip = Set(GlyfToolbar.shownTools)
        strip.remove(id)
        var moved = order.makeIterator()
        let saved = Self.menuOrder.map { strip.contains($0) ? $0 : (moved.next() ?? $0) }
        SettingsStore.update { $0.menuOrder = saved }
        return grid.convert(cell.frame, to: nil)
    }

    /// The landed tile at full strength, as the ghost settles into it.
    func revealTile(_ id: String) {
        guard let cell = tileViews[id] else { return }
        UIView.animate(withDuration: 0.24) { cell.alpha = 1 }
    }

    // MARK: Vault grid (website 6.3)

    /// Nine cards, three to a row: label above value, tap inserts. The
    /// details come first, then shorthand, notes and pictures. New detail is
    /// the same grid, one card per kind.
    private func buildVaultGrid() {
        vaultGrid.subviews.forEach { $0.removeFromSuperview() }
        if screen.id == "vault:detail" {
            vaultCards = DetailKind.addable(region: SettingsStore.current.region).map { .kind($0) }
        } else {
            let vault = VaultStore.shared.load()
            vaultCards = vault.fields.map {
                .text(label: $0.title.uppercased(), value: $0.masked, insert: $0.value)
            }
            vaultCards += vault.snippets.map { .snippet($0) }
            vaultCards += NotesStore.shared.load().map { .note($0) }
            vaultCards += vault.images.map { .image($0) }
        }
        for (i, item) in vaultCards.enumerated() {
            let labelText: String
            let valueText: String
            switch item {
            case .text(let l, let v, _): labelText = l; valueText = v
            // The shortcut as it is typed: its case is part of it.
            case .snippet(let s): labelText = s.trigger; valueText = s.text
            case .note(let n): labelText = "NOTE"; valueText = n.text
            case .kind(let k): labelText = ""; valueText = k.title
            case .image(let img): labelText = "IMAGE"; valueText = ShellCell.age(img.addedAt)
            }
            let cell = UIControl()
            cell.tag = 2000 + i
            cell.accessibilityLabel = labelText.isEmpty ? valueText : "\(labelText), \(valueText)"
            if case .kind(let k) = item {
                cell.accessibilityIdentifier = "vault:kind:\(k.kind)"
            } else {
                cell.accessibilityIdentifier = "vault:card:\(i)"
            }
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = .button

            let card = UIView()
            card.tag = 1
            card.backgroundColor = Glass.surfaceTile
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

            // A kind reads like a menu tile: its symbol over its name.
            if case .kind(let k) = item {
                let icon = UIImageView(image: UIImage(systemName: k.symbol))
                icon.tag = 5
                icon.tintColor = Glass.textPrimary
                icon.contentMode = .center
                icon.preferredSymbolConfiguration = .init(pointSize: 18, weight: .regular)
                icon.isUserInteractionEnabled = false
                cell.addSubview(icon)
            }

            let label = UILabel()
            label.tag = 2
            label.attributedText = NSAttributedString(
                string: labelText,
                attributes: [.kern: 0.44,
                             .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                             .foregroundColor: Glass.textSecondary])
            label.lineBreakMode = .byTruncatingTail
            label.isUserInteractionEnabled = false
            label.isHidden = labelText.isEmpty || { if case .image = item { return true }; return false }()
            cell.addSubview(label)

            let value = UILabel()
            value.tag = 3
            value.text = valueText
            value.font = .systemFont(ofSize: 13, weight: .medium)
            value.textColor = Glass.textPrimary
            value.lineBreakMode = .byTruncatingTail
            value.isUserInteractionEnabled = false
            value.isHidden = { if case .image = item { return true }; return false }()
            if case .kind = item {
                value.textAlignment = .center
                value.numberOfLines = 1
                // "Wallet address" is a card's whole width on a small phone:
                // a touch smaller beats cut short.
                value.adjustsFontSizeToFitWidth = true
                value.minimumScaleFactor = 0.8
            }
            cell.addSubview(value)

            cell.addAction(UIAction { [weak self] _ in
                switch item {
                case .text(_, _, let insert):
                    self?.delegate?.shellInsertText(insert)
                case .snippet(let s):
                    self?.delegate?.shellInsertShorthand(s.text)
                case .note(let n):
                    self?.delegate?.shellInsertText(n.text)
                case .kind(let k):
                    self?.delegate?.shellAddDetail(k)
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

    /// A note, straight to the editor strip; a detail, by way of its kinds;
    /// a shorthand, to its two fields.
    private func add(_ adding: Adding) {
        switch adding {
        case .note: delegate?.shellEditNote(id: nil, text: "")
        case .detail: push("vault:detail")
        case .shorthand: delegate?.shellAddShorthand()
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
            cell.viewWithTag(4)?.frame = cell.bounds          // image fills it
            if let icon = cell.viewWithTag(5) {
                // Symbol over name, centred as a column.
                let top = (h - 22 - 5 - 17) / 2
                icon.frame = CGRect(x: 0, y: top, width: w, height: 22)
                cell.viewWithTag(3)?.frame = CGRect(x: 6, y: top + 27, width: w - 12, height: 17)
            } else {
                let top = (h - 15 - 2 - 17) / 2
                cell.viewWithTag(2)?.frame = CGRect(x: 8, y: top, width: w - 16, height: 15)
                cell.viewWithTag(3)?.frame = CGRect(x: 8, y: top + 17, width: w - 16, height: 17)
            }
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
        // Going back, or on to New detail, closes the +'s options.
        setAddOpen(false, animated: false)
        let wasTempMail = showsTempMail
        screen = Self.build(id: stack.last ?? "root")
        // Temp mail open: it shows new mail itself, watches at its quickest,
        // and opening it starts a fresh 15 minutes.
        let watcher = TempMailWatcher.shared
        watcher.panelOpen = showsTempMail
        if showsTempMail {
            if !wasTempMail { watcher.restartWatch() }
            tempMailView.show(detail: screen.id == "tempmail:mail")
        } else {
            tempMailView.stop()
        }
        titleLabel.text = screen.title
        backButton.isHidden = screen.id == "root"
        if screen.id == "root" { refreshGrid() }
        // The vault's last card can always scroll out from under the +.
        let clearance = screen.id == "vault" ? Self.addClearance : 0
        vaultGrid.contentInset.bottom = clearance
        table.contentInset.bottom = 8 + clearance
        if usesCardGrid {
            buildVaultGrid()
            vaultGrid.setContentOffset(.zero, animated: false)
        }
        table.reloadData()
        // One table serves every screen: a new one starts at its top, not
        // where the last was scrolled to (New detail opened on Link). The
        // reload is lazy and carries the old offset through, so it is done
        // first; not animated, which also stops a scroll still gliding.
        table.layoutIfNeeded()
        table.setContentOffset(CGPoint(x: 0, y: -table.adjustedContentInset.top), animated: false)
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
            // No Appearance row: on the iPhone the keyboard follows the app
            // it types into, like Apple's. A forced light or dark board sat
            // between the band and bar iOS draws in the app's own colour.
            return Screen(id: id, title: "Settings", rows: [
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
                .toggle(title: "Glide typing",
                        value: { SettingsStore.current.glideTyping ?? true },
                        set: { v in SettingsStore.update { $0.glideTyping = v } }),
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
                // The menu's own name for it ("Voice", "GIFs"), so a tool
                // reads the same wherever it is found.
                rows.append(.toggle(
                    title: tools.first { $0.id == itemId }?.title ?? itemId.capitalized,
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

        case "notes", "shorthand":
            // Notes and shorthand live inside Vault now; keep the targets as
            // aliases so old saved nav stacks and bindings still land
            // somewhere real.
            return build(id: "vault")

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
            // Keys and My glyfs said the same thing twice: one screen now.
            return build(id: "glyfs")

        case "glyfs":
            // What each held key does, in the keys' own order, then the
            // glyfs this person built that are on no key. A row does what
            // holding its key does: it runs the glyf, or opens what the key
            // opens.
            let s = SettingsStore.current
            var rows: [Row] = []
            for letter in "qwertyuiopasdfghjklzxcvbnm".map(String.init) {
                guard let target = s.bindings[letter] else { continue }
                rows.append(.nav(icon: glyfIcon(target), title: ShellCell.displayTitle(target),
                                 detail: "Hold \(letter.uppercased())", target: "!key:\(letter)"))
            }
            let bound = Set(s.bindings.values)
            for (glyfId, title) in (s.customTitles ?? [:]).filter({ !bound.contains($0.key) })
                .sorted(by: { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }) {
                rows.append(.nav(icon: "sparkles", title: title, detail: nil, target: "!run:\(glyfId)"))
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
            // Shorthand after the details: a tap types what it expands to.
            for snippet in vault.snippets {
                rows.append(.snippet(trigger: snippet.trigger, text: snippet.text))
            }
            for note in NotesStore.shared.load() {
                rows.append(.note(note))
            }
            for image in vault.images {
                rows.append(.vaultImage(image))
            }
            // Adding is the + floating over the list (layoutAddButton).
            return Screen(id: id, title: "Vault", rows: rows, appPath: "vault")

        case "tempmail", "tempmail:mail":
            // Drawn by TempMailView: the address and its inbox, or one mail.
            return Screen(id: id, title: "Temp mail", rows: [], showOpenInApp: false)

        case "style":
            // Each style shows what it makes of the words picked out, or of
            // the message so far, or of its own name when nothing is typed.
            let sample = styleSample.trimmingCharacters(in: .whitespacesAndNewlines)
            // How long it is, for a post or a bio with a limit.
            var rows: [Row] = [.info(title: sample.isEmpty ? "Type something, then pick a style"
                                         : "\(Smart.textCount(sample)) · tap a style", detail: nil)]
            for style in Smart.TextStyle.allCases {
                let text = sample.isEmpty ? style.title : String(sample.prefix(40))
                rows.append(.nav(icon: styleIcon(style), title: Smart.styled(text, style),
                                 detail: style.title, target: "!style:\(style.rawValue)"))
            }
            return Screen(id: id, title: "Style", rows: rows, showOpenInApp: false)

        case "vault:detail":
            // The kinds, as the app's Vault names them; one tap and the
            // strip over the keys takes its value.
            let rows: [Row] = DetailKind.addable(region: SettingsStore.current.region).map {
                .nav(icon: $0.symbol, title: $0.title, detail: nil, target: "!detail:\($0.kind)")
            }
            return Screen(id: id, title: "New detail", rows: rows, showOpenInApp: false)

        default:
            return Screen(id: id, title: id, rows: [.info(title: "…", detail: nil)])
        }
    }

    /// What the Style screen shows its styles on (the keyboard sets it as
    /// the screen opens): the words picked out, or the message so far.
    static var styleSample = ""

    private static func styleIcon(_ style: Smart.TextStyle) -> String {
        switch style {
        case .bold, .serifBold: return "bold"
        case .italic: return "italic"
        case .boldItalic: return "bold.italic.underline"
        case .underline: return "underline"
        case .strike: return "strikethrough"
        case .script: return "signature"
        case .doubleStruck: return "textformat.size"
        case .monospace: return "chevron.left.forwardslash.chevron.right"
        case .bubble: return "circle.circle"
        case .smallCaps: return "textformat.size.smaller"
        case .wide: return "arrow.left.and.right"
        case .upsideDown: return "arrow.up.arrow.down"
        case .plain: return "textformat"
        case .upper: return "textformat.size.larger"
        case .lower: return "textformat.size.smaller"
        case .titleCase: return "textformat.alt"
        case .sentenceCase: return "text.alignleft"
        }
    }

    /// A held key's icon in My glyfs: the tool it opens, a catalog glyf's
    /// own, or the spark every glyf a person built wears.
    private static func glyfIcon(_ target: String) -> String {
        switch target {
        case "surface:vault", "surface:notes": return GlyfToolbar.icons["vault"] ?? "sparkles"
        case "surface:translate-hud": return GlyfToolbar.icons["translate"] ?? "sparkles"
        case "surface:tones": return GlyfToolbar.icons["rewrite"] ?? "sparkles"
        case "connector:calendar", "connector:mockcal": return "calendar"
        case "connector:meet": return "video"
        default: return GlyfCatalog.all.first { $0.id == target }?.icon ?? "sparkles"
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
            } else if target.hasPrefix("!key:") {
                delegate?.shellRunKey(String(target.dropFirst("!key:".count)))
            } else if target.hasPrefix("!detail:") {
                let kind = String(target.dropFirst("!detail:".count))
                if let k = DetailKind.addable(region: SettingsStore.current.region)
                    .first(where: { $0.kind == kind }) {
                    delegate?.shellAddDetail(k)
                }
            } else if target.hasPrefix("!app:") {
                delegate?.shellOpenApp(path: String(target.dropFirst("!app:".count)))
            } else if target.hasPrefix("!connector:") {
                delegate?.shellOpenTool(String(target.dropFirst("!connector:".count)))
            } else if target.hasPrefix("!style:") {
                delegate?.shellApplyStyle(String(target.dropFirst("!style:".count)))
            } else {
                push(target)
            }
        case .action(_, _, let handler):
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
            delegate?.shellInsertShorthand(text)
        case .vaultImage(let image):
            // No keyboard can type a picture into a host text box, so the
            // most a tap can do is put it back on the clipboard, ready for
            // one hold-and-paste in the field.
            delegate?.shellCopyImage(id: image.id)
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
        let base = Glass.surfaceTile
        card.backgroundColor = highlighted ? base.blend(Glass.textPrimary, 0.08) : base
    }

    private func reset() {
        kind = .cell
        place = Place()
        detailRight = false
        card.backgroundColor = Glass.surfaceTile
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        separator.backgroundColor = Glass.strokeSeparator
        separator.isHidden = false
        chip.isHidden = true
        chipIcon.image = nil
        chipLetter.text = nil
        chip.backgroundColor = Glass.fillField
        chipIcon.tintColor = Glass.textPrimary
        chipLetter.textColor = Glass.textPrimary
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
        isAccessibilityElement = Self.cellIsElement
        accessibilityLabel = nil
        accessibilityTraits = .none
    }

    /// What UIKit gives a cell, so a row that made itself one element (a
    /// nav row) hands the next row its switches and buttons back.
    private static let cellIsElement = UITableViewCell().isAccessibilityElement

    /// One element, read as it is seen: "Vault, Hold V".
    private func readAsOne(_ parts: [String?], id: String) {
        isAccessibilityElement = true
        accessibilityLabel = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityTraits = .button
        accessibilityIdentifier = id
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
            // "shell:key:v", "shell:detail:email", "shell:toolbar".
            readAsOne([t, detail], id: "shell:" + target.replacingOccurrences(of: "!", with: ""))
        case .insert(let icon, let t, _):
            setIcon(icon)
            title.text = preview(t)
            accessibilityIdentifier = "note:\(preview(t))"
        case .toggle(let t, let valueFn, let set, let moveUp):
            title.text = t
            let sw = UISwitch()
            sw.isOn = valueFn()
            sw.onTintColor = Glass.controlOn
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
            seg.selectedSegmentTintColor = Glass.controlOn
            seg.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 13, weight: .medium),
                                        .foregroundColor: Glass.textPrimary], for: .normal)
            seg.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                                        .foregroundColor: Glass.controlOnText], for: .selected)
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
        case .vaultField(let field):
            setIcon("person.text.rectangle")
            title.text = field.title
            value.isHidden = false
            value.text = preview(field.masked)
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
