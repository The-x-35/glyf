import UIKit

protocol PaySurfaceDelegate: AnyObject {
    /// The finished payment, handed to the app — which opens Phantom at
    /// once and gets out of the way.
    func payHandOff(query: [String: String])
    /// Phantom isn't connected yet: the app's Wallet screen does that once.
    func payConnect()
    /// The amount editor opened or closed: the keys come and go with it.
    func payLayoutChanged()
    func payToast(_ text: String)
}

/// Paying without leaving the chat — the website's wallet panel on the real
/// keyboard, jup.ag-simple: balance up top, the amount in whichever asset
/// the wallet holds, Private by MagicBlock for USDC, one blue button. iOS
/// lets a keyboard open only its own app, never Phantom, so the button is a
/// flash of Glyf on the way into Phantom; the keyboard says how it went
/// when it next comes up.
final class PaySurface: UIView {

    /// What the chip knew: who to pay, or what to buy.
    enum Intent: Equatable {
        /// `token` "USDC" or "SOL"; a nil recipient asks for a paste.
        case send(to: String?, amount: String?, token: String?)
        /// Buying `mint`, sold from any asset the wallet holds.
        case buy(mint: String, symbol: String, price: String?)
    }

    /// Something the wallet holds, spendable from the keyboard.
    struct Asset: Equatable {
        var mint: String
        var symbol: String
        var decimals: Int
        /// Whole tokens held (0 until the relay answers).
        var amount: Double
    }

    static let wsol = "So11111111111111111111111111111111111111112"
    static let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    static let sol = Asset(mint: wsol, symbol: "SOL", decimals: 9, amount: 0)
    static let usdc = Asset(mint: usdcMint, symbol: "USDC", decimals: 6, amount: 0)

    /// The strip over the keys while the amount is typed.
    static let editStripHeight: CGFloat = 64

    weak var delegate: PaySurfaceDelegate?
    let amountEditor = InlineEditor(placeholder: "0")

    private let intent: Intent
    private var to: String?
    /// Send: what leaves. Buy: what pays for it. USDC first for a send
    /// (that is what people owe each other), SOL first for a buy.
    private var paying: Asset
    /// Everything the wallet holds, SOL first, once the relay answers.
    private var assets: [Asset] = [PaySurface.usdc, PaySurface.sol]
    /// What the wallet holds is known (the relay answered), not yet asked,
    /// or couldn't be had: zeros are shown only when they are true.
    private enum Balance { case loading, known, unavailable }
    private var balance = Balance.loading
    private var isPrivate = false
    private(set) var editingAmount = false
    private let connected = !(SettingsStore.current.walletAddress ?? "").isEmpty

    /// Buying: what the typed amount gets, from Jupiter (no key, no taker).
    private var quote: String?
    private var quoteWork: DispatchWorkItem?
    private var targetDecimals: Int?

    // Panel
    private let balanceKey = UILabel()
    private let balanceValue = UILabel()
    private let balanceTokens = UILabel()
    private let amountRow = UIControl()
    private let amountLabel = UILabel()
    private let unitLabel = UILabel()
    private let arrowLabel = UILabel()
    private let toZone = UIControl()
    private let toName = UILabel()
    private let toAddress = UILabel()
    private let assetsRow = ControlScrollView()
    private var assetButtons: [UIButton] = []
    private let privateRow = UIControl()
    private let privateIcon = UIImageView()
    private let privateTitle = UILabel()
    private let privateBy = UILabel()
    private let privateSwitch = UISwitch()
    private let metaLabel = UILabel()
    private let goButton = UIButton(type: .system)
    // Connect / paste states
    private let leadLabel = UILabel()
    private let ctaButton = UIButton(type: .system)
    // Edit strip
    private let editKey = UILabel()
    private var percentButtons: [UIButton] = []
    private let doneButton = UIButton(type: .system)
    // Buy, laid out the way jup.ag does it (Arpit, 2026-10-06: "we need to
    // improve the buy ui a lot ... check jupiter jup.ag and make a proper ui
    // for this"): what you pay (the amount, its dollars, the token, the
    // balance with Half and Max), what you get (Jupiter's quote, its dollars,
    // the rate), and one button that says what's next.
    private let payCard = UIControl()
    private let payKey = UILabel()
    private let payHeld = UILabel()
    private let halfButton = UIButton(type: .system)
    private let maxButton = UIButton(type: .system)
    private let payAmount = UILabel()
    private let payUSD = UILabel()
    private let payToken = UIButton(type: .system)
    private let getCard = UIView()
    private let getKey = UILabel()
    private let getAmount = UILabel()
    private let getUSD = UILabel()
    private let getToken = UILabel()
    /// The pay token dropdown is open (Arpit, 2026-10-06: "the asset list
    /// needs to be dropdown"): a card under the token pill, one row per held
    /// token, over a dim that closes it.
    private var picking = false
    private let tokenScrim = UIControl()
    private let tokenMenu = UIView()
    private let tokenList = ControlScrollView()
    private var tokenRows: [UIControl] = []
    private static let tokenRowHeight: CGFloat = 44
    /// Jupiter's answer for the typed amount, in whole tokens of what's
    /// bought; asking says so while it's on its way.
    private var quoteOut: Double?
    private var quoting = false
    /// Token pills and the Half/Max chips: a grey that reads on the card in
    /// either appearance.
    private static let pillFill = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.06) }

    init(intent: Intent) {
        self.intent = intent
        switch intent {
        case .send(let address, let amount, let token):
            to = address
            paying = token?.uppercased() == "SOL" ? Self.sol : Self.usdc
            super.init(frame: .zero)
            if let amount { amountEditor.setText(amount) }
        case .buy:
            paying = Self.sol
            super.init(frame: .zero)
        }
        backgroundColor = Glass.touchableGrid
        build()
        render()
        loadAssets()
        RatesStore.shared.ensureToken("SOL") { [weak self] in self?.renderBalance() }
        if case .buy(let mint, _, _) = intent {
            tokenMeta(mint) { [weak self] _, decimals in
                self?.targetDecimals = decimals
                self?.requote()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isBuy: Bool { if case .buy = intent { return true }; return false }

    /// The strip's header while the panel is up.
    var headerTitle: String {
        if case .buy(_, let symbol, _) = intent { return "Buy \(symbol)" }
        return "Send"
    }

    // MARK: build

    private func build() {
        balanceKey.text = "Balance"
        balanceKey.font = .systemFont(ofSize: 12, weight: .semibold)
        balanceKey.textColor = Glass.textSecondary
        addSubview(balanceKey)
        balanceValue.font = .systemFont(ofSize: 20, weight: .bold)
        balanceValue.textColor = Glass.textPrimary
        addSubview(balanceValue)
        balanceTokens.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        balanceTokens.textColor = Glass.textSecondary
        balanceTokens.textAlignment = .right
        addSubview(balanceTokens)

        amountRow.backgroundColor = Glass.surfaceCard
        amountRow.layer.cornerRadius = 12
        amountRow.layer.cornerCurve = .continuous
        amountRow.accessibilityIdentifier = "pay:amountrow"
        amountRow.addAction(UIAction { [weak self] _ in self?.beginAmount() }, for: .touchUpInside)
        addSubview(amountRow)
        amountLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        amountLabel.textColor = Glass.textPrimary
        amountRow.addSubview(amountLabel)
        unitLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        unitLabel.textColor = Glass.textSecondary
        amountRow.addSubview(unitLabel)
        arrowLabel.text = "→"
        arrowLabel.font = .systemFont(ofSize: 15)
        arrowLabel.textColor = Glass.textSecondary
        amountRow.addSubview(arrowLabel)
        // The recipient is its own tap: paste (or re-paste) the address
        // there without leaving the form. On a buy it opens the amount.
        toZone.accessibilityIdentifier = "pay:to"
        toZone.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.isBuy { self.beginAmount() } else { self.pasteAddress() }
        }, for: .touchUpInside)
        amountRow.addSubview(toZone)
        toName.font = .systemFont(ofSize: 13.5, weight: .semibold)
        toName.textColor = Glass.textPrimary
        toName.textAlignment = .right
        toName.isUserInteractionEnabled = false
        toZone.addSubview(toName)
        toAddress.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        toAddress.textColor = Glass.textSecondary
        toAddress.textAlignment = .right
        toAddress.isUserInteractionEnabled = false
        toZone.addSubview(toAddress)

        assetsRow.showsHorizontalScrollIndicator = false
        addSubview(assetsRow)

        privateRow.backgroundColor = Glass.surfaceCard
        privateRow.layer.cornerRadius = 12
        privateRow.layer.cornerCurve = .continuous
        privateRow.addAction(UIAction { [weak self] _ in self?.togglePrivate() }, for: .touchUpInside)
        addSubview(privateRow)
        privateIcon.image = UIImage(systemName: "lock.shield",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        privateIcon.tintColor = Glass.textSecondary
        privateIcon.contentMode = .center
        privateRow.addSubview(privateIcon)
        privateTitle.text = "Private"
        privateTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        privateTitle.textColor = Glass.textPrimary
        privateRow.addSubview(privateTitle)
        privateBy.text = "by MagicBlock"
        privateBy.font = .systemFont(ofSize: 12)
        privateBy.textColor = Glass.textSecondary
        privateRow.addSubview(privateBy)
        privateSwitch.onTintColor = UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
        privateSwitch.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)
        privateSwitch.accessibilityIdentifier = "pay:private"
        privateSwitch.addAction(UIAction { [weak self] _ in self?.togglePrivate(fromSwitch: true) }, for: .valueChanged)
        privateRow.addSubview(privateSwitch)

        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = Glass.textSecondary
        metaLabel.textAlignment = .center
        addSubview(metaLabel)

        goButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        goButton.setTitleColor(.white, for: .normal)
        goButton.backgroundColor = Glass.imBlue
        goButton.layer.cornerRadius = 12
        goButton.layer.cornerCurve = .continuous
        goButton.accessibilityIdentifier = "pay:go"
        goButton.addAction(UIAction { [weak self] _ in self?.goIfReady() }, for: .touchUpInside)
        addSubview(goButton)

        leadLabel.font = .systemFont(ofSize: 14)
        leadLabel.textColor = Glass.textSecondary
        leadLabel.numberOfLines = 2
        leadLabel.textAlignment = .center
        addSubview(leadLabel)
        ctaButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = Glass.imBlue
        ctaButton.layer.cornerRadius = 12
        ctaButton.layer.cornerCurve = .continuous
        addSubview(ctaButton)

        // The strip while typing: Amount · the editor · 25% 50% Max · Done.
        editKey.text = "Amount"
        editKey.font = .systemFont(ofSize: 13, weight: .semibold)
        editKey.textColor = Glass.textSecondary
        addSubview(editKey)
        amountEditor.accessibilityIdentifier = "pay:amount"
        amountEditor.onChange = { [weak self] text in
            guard let self else { return }
            let clean = Self.cleanAmount(text)
            if clean != text { self.amountEditor.setText(clean); return }
            self.amountLabel.text = self.amountText
            self.requote()
            self.renderGo()
        }
        addSubview(amountEditor)
        for (i, title) in ["25%", "50%", "Max"].enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.backgroundColor = Glass.surfaceCard
            b.layer.cornerRadius = 13
            b.layer.cornerCurve = .continuous
            b.accessibilityIdentifier = "pay:pct:\(title)"
            b.addAction(UIAction { [weak self] _ in self?.takePercent([0.25, 0.5, 1][i]) }, for: .touchUpInside)
            percentButtons.append(b)
            addSubview(b)
        }
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        doneButton.setTitleColor(Glass.controlOnText, for: .normal)
        doneButton.backgroundColor = Glass.controlOn
        doneButton.layer.cornerRadius = 15
        doneButton.layer.cornerCurve = .continuous
        doneButton.accessibilityIdentifier = "pay:done"
        doneButton.addAction(UIAction { [weak self] _ in self?.endAmount() }, for: .touchUpInside)
        addSubview(doneButton)
        if isBuy { buildBuy() }
    }

    private func buildBuy() {
        for card in [payCard, getCard] as [UIView] {
            card.backgroundColor = Glass.surfaceCard
            card.layer.cornerRadius = 14
            card.layer.cornerCurve = .continuous
            insertSubview(card, belowSubview: assetsRow)
        }
        payCard.accessibilityIdentifier = "pay:paycard"
        payCard.addAction(UIAction { [weak self] _ in self?.beginAmount() }, for: .touchUpInside)
        for (label, text) in [(payKey, "You pay"), (getKey, "You get")] {
            label.text = text
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = Glass.textSecondary
            label.isUserInteractionEnabled = false
        }
        payCard.addSubview(payKey)
        getCard.addSubview(getKey)
        payHeld.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        payHeld.textColor = Glass.textSecondary
        payHeld.textAlignment = .right
        payHeld.isUserInteractionEnabled = false
        payCard.addSubview(payHeld)
        for (button, title, share, id) in [(halfButton, "HALF", 0.5, "pay:half"), (maxButton, "MAX", 1.0, "pay:max")] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 10.5, weight: .bold)
            button.setTitleColor(Glass.textSecondary, for: .normal)
            button.backgroundColor = Self.pillFill
            button.layer.cornerRadius = 9
            button.layer.cornerCurve = .continuous
            button.accessibilityIdentifier = id
            button.addAction(UIAction { [weak self] _ in self?.takePercent(share) }, for: .touchUpInside)
            payCard.addSubview(button)
        }
        for label in [payAmount, getAmount] {
            label.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.55
            label.isUserInteractionEnabled = false
        }
        payCard.addSubview(payAmount)
        getCard.addSubview(getAmount)
        for label in [payUSD, getUSD] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = Glass.textSecondary
            label.isUserInteractionEnabled = false
        }
        payCard.addSubview(payUSD)
        getCard.addSubview(getUSD)
        payToken.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        payToken.setTitleColor(Glass.textPrimary, for: .normal)
        payToken.backgroundColor = Self.pillFill
        payToken.layer.cornerRadius = 16
        payToken.layer.cornerCurve = .continuous
        payToken.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
        payToken.accessibilityIdentifier = "pay:token"
        payToken.addAction(UIAction { [weak self] _ in self?.openTokens() }, for: .touchUpInside)
        payCard.addSubview(payToken)
        getToken.font = .systemFont(ofSize: 14, weight: .semibold)
        getToken.textColor = Glass.textPrimary
        getToken.backgroundColor = Self.pillFill
        getToken.textAlignment = .center
        getToken.layer.cornerRadius = 14
        getToken.layer.cornerCurve = .continuous
        getToken.clipsToBounds = true
        getCard.addSubview(getToken)

        // Not clear: a keyboard drops touches on clear pixels, and a tap
        // anywhere off the menu has to close it.
        tokenScrim.backgroundColor = Glass.scrim
        tokenScrim.isHidden = true
        tokenScrim.accessibilityIdentifier = "pay:tokenscrim"
        tokenScrim.addAction(UIAction { [weak self] _ in self?.closeTokens() }, for: .touchUpInside)
        addSubview(tokenScrim)
        tokenMenu.isHidden = true
        tokenMenu.layer.shadowColor = UIColor.black.cgColor
        tokenMenu.layer.shadowOpacity = 0.22
        tokenMenu.layer.shadowRadius = 16
        tokenMenu.layer.shadowOffset = CGSize(width: 0, height: 6)
        addSubview(tokenMenu)
        tokenList.backgroundColor = Glass.surfaceCard
        tokenList.layer.cornerRadius = 14
        tokenList.layer.cornerCurve = .continuous
        tokenList.clipsToBounds = true
        tokenList.alwaysBounceVertical = false
        tokenList.accessibilityIdentifier = "pay:tokens"
        tokenMenu.addSubview(tokenList)
        renderTokenRows()
    }

    /// One row per held token: the token, what's held, a tick on the one
    /// paying.
    private func renderTokenRows() {
        for r in tokenRows { r.removeFromSuperview() }
        tokenRows = assets.enumerated().map { i, asset in
            let row = UIControl()
            row.accessibilityIdentifier = "pay:asset:\(asset.symbol)"
            row.addAction(UIAction { [weak self] _ in self?.pick(asset) }, for: .touchUpInside)
            let name = UILabel()
            name.text = "\(Self.glyph(asset))\(asset.symbol)"
            name.font = .systemFont(ofSize: 15, weight: .semibold)
            name.textColor = Glass.textPrimary
            name.tag = 1
            let held = UILabel()
            held.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            held.textColor = Glass.textSecondary
            held.textAlignment = .right
            held.tag = 2
            let tick = UIImageView(image: UIImage(systemName: "checkmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
            tick.tintColor = Glass.imBlue
            tick.contentMode = .center
            tick.tag = 3
            let line = UIView()
            line.backgroundColor = Glass.strokeSeparator
            line.isHidden = i == assets.count - 1
            line.tag = 4
            for v in [name, held, tick, line] {
                v.isUserInteractionEnabled = false
                row.addSubview(v)
            }
            tokenList.addSubview(row)
            return row
        }
        styleTokenRows()
        setNeedsLayout()
    }

    private func styleTokenRows() {
        for (row, asset) in zip(tokenRows, assets) {
            (row.viewWithTag(2) as? UILabel)?.text = balance == .known ? Self.compact(asset.amount) : ""
            row.viewWithTag(3)?.isHidden = asset.mint != paying.mint
        }
    }

    private func openTokens() {
        guard !picking, !assets.isEmpty else { return }
        picking = true
        styleTokenRows()
        render()
        layoutIfNeeded()
        tokenMenu.alpha = 0
        tokenMenu.transform = CGAffineTransform(translationX: 0, y: -6)
        tokenScrim.alpha = 0
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
            self.tokenMenu.alpha = 1
            self.tokenMenu.transform = .identity
            self.tokenScrim.alpha = 1
        }
    }

    private func closeTokens() {
        guard picking else { return }
        picking = false
        render()
    }

    // MARK: state

    /// "12,5" typed on a phone in Europe is still a decimal; one dot, and
    /// digits only, at most nine characters.
    static func cleanAmount(_ text: String) -> String {
        var out = ""
        var dot = false
        for ch in text.replacingOccurrences(of: ",", with: ".") {
            if ch.isNumber { out.append(ch) }
            else if ch == ".", !dot { dot = true; out.append(ch) }
        }
        return String(out.prefix(9))
    }

    private var amountValue: Double? {
        Double(amountEditor.text).flatMap { $0 > 0 ? $0 : nil }
    }

    /// What can be spent of the paying asset: SOL keeps a sliver for fees.
    private var spendable: Double {
        paying.mint == Self.wsol ? max(0, paying.amount - 0.005) : paying.amount
    }

    /// ◎ for SOL, $ for USDC, nothing for the rest.
    static func glyph(_ asset: Asset) -> String {
        asset.mint == wsol ? "◎ " : asset.mint == usdcMint ? "$ " : ""
    }

    /// "$5.98", "$1,240": a dollar figure.
    static func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = value >= 100 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    /// The chip's price ("$332.57") as a number.
    static func price(_ text: String?) -> Double? {
        text.flatMap { Double($0.filter { "0123456789.".contains($0) }) }
    }

    /// What an amount of an asset is worth in dollars, when that is known.
    private func dollarsOf(_ asset: Asset, _ amount: Double?) -> Double? {
        guard let amount else { return nil }
        if asset.mint == Self.usdcMint { return amount }
        if asset.mint == Self.wsol, let sol = RatesStore.shared.crypto["SOL"] { return amount * sol }
        return nil
    }

    /// The big figure: dollars read with a $, everything else as itself.
    private var amountText: String {
        let raw = amountEditor.text.isEmpty ? "0" : amountEditor.text
        return paying.mint == Self.usdcMint ? "$\(raw)" : raw
    }

    private var needsConnect: Bool { !connected }
    private var formReady: Bool { connected }

    var activeEditor: InlineEditor? { editingAmount ? amountEditor : nil }

    private func beginAmount() {
        guard formReady, !editingAmount else { return }
        editingAmount = true
        render()
        delegate?.payLayoutChanged()
    }

    func endAmount() {
        guard editingAmount else { return }
        editingAmount = false
        render()
        delegate?.payLayoutChanged()
    }

    /// 25%, 50% or everything the wallet holds of the paying asset (SOL
    /// keeps a sliver back for fees).
    private func takePercent(_ share: Double) {
        var held = paying.amount
        if paying.mint == Self.wsol { held = max(0, held - 0.005) }
        guard balance == .known else {
            delegate?.payToast(balance == .loading ? "Checking the wallet…" : "Balance unavailable")
            return
        }
        guard held > 0 else {
            delegate?.payToast("Nothing to take a share of yet")
            return
        }
        let value = held * share
        let places = paying.mint == Self.usdcMint ? 2 : min(6, paying.decimals)
        var text = String(format: "%.\(places)f", floor(value * pow(10, Double(places))) / pow(10, Double(places)))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        amountEditor.setText(text)
        requote()
        render()
    }

    private func pick(_ asset: Asset) {
        paying = asset
        picking = false
        if asset.mint != Self.usdcMint { isPrivate = false; privateSwitch.setOn(false, animated: false) }
        requote()
        render()
    }

    private func togglePrivate(fromSwitch: Bool = false) {
        isPrivate = fromSwitch ? privateSwitch.isOn : !isPrivate
        if !fromSwitch { privateSwitch.setOn(isPrivate, animated: true) }
        render()
    }

    private func pasteAddress() {
        // The tap is the permission moment for reading the copy (off the
        // main thread, so the keyboard keeps working while iOS asks).
        ClipboardStore.readCopy { [weak self] text in self?.useCopied(text ?? "") }
    }

    private func useCopied(_ copied: String) {
        guard let p = Smart.payment(in: copied) else {
            delegate?.payToast("Copy a Solana wallet address first")
            return
        }
        if p.address == SettingsStore.current.walletAddress {
            delegate?.payToast("That’s your own wallet")
            return
        }
        to = p.address
        if let asked = p.amount ?? Smart.amountAsked(in: copied) {
            amountEditor.setText(asked.value)
            paying = asked.token == "SOL" ? currentAsset(Self.wsol) : currentAsset(Self.usdcMint)
        }
        render()
        delegate?.payLayoutChanged()
    }

    private func currentAsset(_ mint: String) -> Asset {
        assets.first { $0.mint == mint } ?? (mint == Self.wsol ? Self.sol : Self.usdc)
    }

    func goIfReady() {
        if editingAmount { endAmount() }
        if !isBuy, to == nil {
            // Send with nowhere to send: try the clipboard right here.
            pasteAddress()
            guard to != nil else { return }
        }
        guard let amount = amountValue else { beginAmount(); return }
        if isBuy, balance == .known, amount > spendable + 1e-9 {
            delegate?.payToast("Not enough \(paying.symbol)")
            return
        }
        var query: [String: String]
        switch intent {
        case .send:
            guard let to else { return }
            query = ["kind": "send", "to": to, "amount": amountEditor.text,
                     "mint": paying.mint, "symbol": paying.symbol, "decimals": String(paying.decimals)]
            if isPrivate && paying.mint == Self.usdcMint { query["private"] = "1" }
        case .buy(let mint, let symbol, _):
            query = ["kind": "buy", "mint": mint, "symbol": symbol, "amount": amountEditor.text,
                     "sellMint": paying.mint, "sellSymbol": paying.symbol,
                     "sellDecimals": String(paying.decimals)]
        }
        delegate?.payHandOff(query: query)
    }

    // MARK: what the wallet holds (through the app's relay; the node's key
    // stays server-side)

    private func loadAssets() {
        guard connected, let address = SettingsStore.current.walletAddress else { return }
        rpc(method: "getBalance", params: [address, ["commitment": "confirmed"]]) { [weak self] result in
            guard let self else { return }
            guard let lamports = (result as? [String: Any])?["value"] as? NSNumber else {
                if self.balance == .loading { self.balance = .unavailable; self.renderBalance() }
                return
            }
            self.balance = .known
            self.upsert(Asset(mint: Self.wsol, symbol: "SOL", decimals: 9,
                              amount: lamports.doubleValue / 1e9))
        }
        rpc(method: "getTokenAccountsByOwner",
            params: [address, ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"],
                     ["encoding": "jsonParsed", "commitment": "confirmed"]]) { [weak self] result in
            guard let self, let accounts = (result as? [String: Any])?["value"] as? [[String: Any]] else { return }
            var held: [(String, Int, Double)] = []
            for account in accounts {
                guard let info = (((account["account"] as? [String: Any])?["data"] as? [String: Any])?["parsed"]
                    as? [String: Any])?["info"] as? [String: Any],
                    let mint = info["mint"] as? String,
                    let tokenAmount = info["tokenAmount"] as? [String: Any],
                    let ui = (tokenAmount["uiAmount"] as? NSNumber)?.doubleValue, ui > 0,
                    let decimals = (tokenAmount["decimals"] as? NSNumber)?.intValue else { continue }
                held.append((mint, decimals, ui))
            }
            // The biggest holdings first, a keyboard-sized handful of them.
            for (mint, decimals, ui) in held.sorted(by: { $0.2 > $1.2 }).prefix(8) {
                if mint == Self.usdcMint {
                    self.upsert(Asset(mint: mint, symbol: "USDC", decimals: decimals, amount: ui))
                    continue
                }
                self.upsert(Asset(mint: mint, symbol: Smart.shortAddress(mint), decimals: decimals, amount: ui))
                self.tokenMeta(mint) { [weak self] symbol, _ in
                    guard let self, let symbol else { return }
                    if var a = self.assets.first(where: { $0.mint == mint }) {
                        a.symbol = symbol
                        self.upsert(a)
                    }
                }
            }
        }
    }

    private func upsert(_ asset: Asset) {
        if let i = assets.firstIndex(where: { $0.mint == asset.mint }) {
            assets[i] = asset
        } else {
            assets.append(asset)
        }
        // SOL, then USDC (raw counts across tokens mean nothing), then the
        // rest by count.
        func rank(_ x: Asset) -> Int { x.mint == Self.wsol ? 0 : x.mint == Self.usdcMint ? 1 : 2 }
        assets.sort { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.amount > b.amount
        }
        if let mine = assets.first(where: { $0.mint == paying.mint }) { paying = mine }
        renderBalance()
        renderAssets()
        renderGo()
    }

    /// A token's symbol and decimals, from the server's Jupiter lookup.
    private func tokenMeta(_ mint: String, done: @escaping (String?, Int?) -> Void) {
        guard let url = URL(string: "\(SettingsStore.current.backendURL)/rates/token?mint=\(mint)") else { return }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      obj["ok"] as? Bool == true,
                      let token = obj["token"] as? [String: Any] else { return done(nil, nil) }
                done(token["symbol"] as? String, (token["decimals"] as? NSNumber)?.intValue)
            }
        }.resume()
    }

    private func rpc(method: String, params: [Any], done: @escaping (Any?) -> Void) {
        guard let url = URL(string: "\(SettingsStore.current.backendURL)/wallet/rpc") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.glyfSession()
        req.timeoutInterval = 8
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["method": method, "params": params])
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      obj["ok"] as? Bool == true else { return done(nil) }
                done(obj["result"])
            }
        }.resume()
    }

    // MARK: the buy quote (Jupiter, keyless, no taker: a price, not an order)

    /// Which quote the panel is waiting for: an answer to an older amount or
    /// asset arriving late must not replace the one for what is on screen.
    private var quoteAsked = 0

    private func requote() {
        guard case .buy(let mint, let symbol, _) = intent else { return }
        quoteWork?.cancel()
        quoteAsked += 1
        let asked = quoteAsked
        guard let amount = amountValue, amount > 0 else {
            quote = nil
            quoteOut = nil
            quoting = false
            renderQuote()
            return
        }
        quoting = true
        renderQuote()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let units = Int(amount * pow(10, Double(self.paying.decimals)))
            guard units > 0,
                  var comps = URLComponents(string: "https://api.jup.ag/swap/v2/order") else { return }
            comps.queryItems = [.init(name: "inputMint", value: self.paying.mint),
                                .init(name: "outputMint", value: mint),
                                .init(name: "amount", value: String(units))]
            guard let url = comps.url else { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                DispatchQueue.main.async {
                    guard let self, asked == self.quoteAsked else { return }
                    self.quoting = false
                    guard let data,
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let out = obj["outAmount"] as? String, let raw = Double(out),
                          let decimals = self.targetDecimals else {
                        self.quote = nil
                        self.quoteOut = nil
                        self.renderQuote()
                        return
                    }
                    let whole = raw / pow(10, Double(decimals))
                    self.quote = "≈ \(Self.compact(whole)) \(symbol)"
                    self.quoteOut = whole
                    self.renderQuote()
                }
            }.resume()
        }
        quoteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// "2,741,737", "13.5T", "0.0821": a figure a strip can hold.
    static func compact(_ v: Double) -> String {
        func short(_ x: Double, _ suffix: String) -> String {
            var t = String(format: x >= 100 ? "%.0f" : "%.1f", x)
            if t.hasSuffix(".0") { t.removeLast(2) }
            return t + suffix
        }
        if v >= 1e12 { return short(v / 1e12, "T") }
        if v >= 1e9 { return short(v / 1e9, "B") }
        if v >= 1e6 { return short(v / 1e6, "M") }
        if v >= 1e5 { return short(v / 1e3, "K") }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = v >= 1000 ? 0 : v >= 1 ? 2 : 6
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    // MARK: render

    private func renderBalance() {
        guard connected else {
            balanceTokens.text = ""
            balanceValue.text = ""
            return
        }
        // Not a $0.00 wallet before (or without) an answer: a zero is a fact.
        guard balance == .known else {
            balanceTokens.text = balance == .loading ? "…" : "Balance unavailable"
            balanceValue.text = balance == .loading ? "…" : ""
            return
        }
        var parts: [String] = []
        let usdcHeld = assets.first { $0.mint == Self.usdcMint }?.amount ?? 0
        let solHeld = assets.first { $0.mint == Self.wsol }?.amount ?? 0
        parts.append("$\(Self.compact(usdcHeld)) USDC")
        parts.append("◎ \(Self.compact(solHeld))")
        balanceTokens.text = parts.joined(separator: "  ")
        if let price = RatesStore.shared.crypto["SOL"] {
            let total = usdcHeld + solHeld * price
            balanceValue.text = total >= 100_000 ? "$\(Self.compact(total))"
                : "$\(String(format: "%.2f", total))"
        } else {
            balanceValue.text = ""
        }
    }

    private func renderAssets() {
        for b in assetButtons { b.removeFromSuperview() }
        assetButtons = []
        for asset in assets {
            let b = UIButton(type: .system)
            let held = asset.amount > 0 ? " \(Self.compact(asset.amount))" : ""
            b.setTitle("\(asset.symbol)\(held)", for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            b.layer.cornerRadius = 13
            b.layer.cornerCurve = .continuous
            b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            b.accessibilityIdentifier = "pay:asset:\(asset.symbol)"
            b.addAction(UIAction { [weak self] _ in self?.pick(asset) }, for: .touchUpInside)
            assetButtons.append(b)
            assetsRow.addSubview(b)
        }
        styleAssets()
        if isBuy { renderTokenRows() }
        setNeedsLayout()
    }

    private func styleAssets() {
        for (i, b) in assetButtons.enumerated() {
            let on = assets.indices.contains(i) && assets[i].mint == paying.mint
            b.backgroundColor = on ? Glass.controlOn : Glass.surfaceCard
            b.setTitleColor(on ? Glass.controlOnText : Glass.textPrimary, for: .normal)
        }
    }

    private func renderQuote() {
        guard case .buy(_, let symbol, let price) = intent else { return }
        renderBuy()
        if let quote {
            toName.text = quote
            toAddress.text = price.map { "1 \(symbol) = \($0)" } ?? ""
        } else {
            toName.text = symbol
            toAddress.text = price ?? ""
        }
    }

    private func render() {
        let editing = editingAmount
        let form = formReady && !editing

        for v in [balanceKey, balanceValue, balanceTokens] { v.isHidden = !form || isBuy }
        amountRow.isHidden = !form || isBuy
        // A buy picks what pays from its dropdown, not this row.
        assetsRow.isHidden = !form || isBuy
        tokenScrim.isHidden = !(form && isBuy && picking)
        tokenMenu.isHidden = tokenScrim.isHidden
        payCard.isHidden = !(form && isBuy)
        getCard.isHidden = payCard.isHidden
        privateRow.isHidden = !(form && !isBuy && paying.mint == Self.usdcMint)
        // The panel is one row too small for both: when Private shows, the
        // fee note rides on it and the meta line stays out.
        metaLabel.isHidden = !form || !privateRow.isHidden
        goButton.isHidden = !form
        leadLabel.isHidden = !needsConnect || editing
        ctaButton.isHidden = leadLabel.isHidden
        for v in [editKey, amountEditor, doneButton] { v.isHidden = !editing }
        editKey.text = isBuy ? "Amount in \(paying.symbol)" : "Amount"
        for b in percentButtons { b.isHidden = !editing }

        if needsConnect {
            leadLabel.text = "Connect Phantom once in the app; after that you pay right here."
            ctaButton.setTitle("Connect Phantom", for: .normal)
            ctaButton.removeTarget(nil, action: nil, for: .allEvents)
            ctaButton.addAction(UIAction { [weak self] _ in self?.delegate?.payConnect() }, for: .touchUpInside)
        }

        amountLabel.text = amountText
        unitLabel.text = isBuy ? "of \(paying.symbol)" : paying.symbol
        switch intent {
        case .send:
            if let to {
                toName.text = "Wallet"
                toName.textColor = Glass.textPrimary
                toAddress.text = Smart.shortAddress(to)
            } else {
                // The slot itself asks, the way the website's panel does.
                toName.text = "Paste address"
                toName.textColor = Glass.imBlue
                toAddress.text = "from the chat"
            }
            metaLabel.text = isPrivate
                ? "Nobody onchain sees who paid · about 0.002 SOL + 0.1%"
                : "Phantom signs · nothing moves without you"
            goButton.setTitle(isPrivate && paying.mint == Self.usdcMint ? "Send privately" : "Send", for: .normal)
        case .buy:
            toName.textColor = Glass.textPrimary
            metaLabel.text = "Best route via Jupiter · Phantom signs"
            renderQuote()
        }
        privateIcon.tintColor = isPrivate ? Glass.textPrimary : Glass.textSecondary
        privateBy.text = isPrivate ? "≈0.002 SOL + 0.1% · off-chain" : "by MagicBlock"
        styleAssets()
        renderGo()
        setNeedsLayout()
    }

    private func renderGo() {
        if isBuy { renderBuy(); return }
        let ready = amountValue != nil && formReady && (isBuy || to != nil)
        goButton.alpha = ready ? 1 : 0.45
    }

    /// The two cards and the button, from the amount, the balance and the
    /// quote: the button says what's missing before it says Buy.
    private func renderBuy() {
        guard case .buy(_, let symbol, let price) = intent else { return }
        let amount = amountValue
        payAmount.text = amountEditor.text.isEmpty ? "0" : amountEditor.text
        payAmount.textColor = amount == nil ? Glass.textSecondary : Glass.textPrimary
        // No dollar price for what's paid (SOL's is only fetched for a
        // $sol): the quote's worth stands in, which is the same money.
        let unit = Self.price(price)
        let paid = dollarsOf(paying, amount) ?? quoteOut.flatMap { out in unit.map { out * $0 } }
        payUSD.text = paid.map { "≈ \(Self.dollars($0))" } ?? (amount == nil && !editingAmount ? "Tap to type an amount" : "")
        payToken.setTitle("\(Self.glyph(paying))\(paying.symbol) \(picking ? "▴" : "▾")", for: .normal)
        switch balance {
        case .known: payHeld.text = "\(Self.glyph(paying))\(Self.compact(paying.amount))"
        case .loading: payHeld.text = "…"
        case .unavailable: payHeld.text = ""
        }
        styleTokenRows()
        getToken.text = symbol
        if let out = quoteOut {
            getAmount.text = Self.compact(out)
            getAmount.textColor = Glass.textPrimary
        } else {
            getAmount.text = amount != nil && quoting ? "…" : "0"
            getAmount.textColor = Glass.textSecondary
        }
        var line: [String] = []
        if let out = quoteOut, let unit { line.append("≈ \(Self.dollars(out * unit))") }
        if let price { line.append("1 \(symbol) = \(price)") }
        if amount != nil, quoteOut == nil, !quoting { line.insert("No price right now", at: 0) }
        getUSD.text = line.joined(separator: " · ")

        let short = amount != nil && balance == .known && (amount ?? 0) > spendable + 1e-9
        if amount == nil {
            goButton.setTitle("Enter an amount", for: .normal)
        } else if short {
            goButton.setTitle("Not enough \(paying.symbol)", for: .normal)
        } else {
            goButton.setTitle("Buy \(paid.map { "≈ \(Self.dollars($0)) of " } ?? "")\(symbol)", for: .normal)
        }
        goButton.alpha = amount == nil || short ? 0.45 : 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        if editingAmount {
            let doneW: CGFloat = 70
            doneButton.frame = CGRect(x: w - 12 - doneW, y: 16, width: doneW, height: 32)
            var px = doneButton.frame.minX - 8
            for b in percentButtons.reversed() {
                let bw = b.intrinsicContentSize.width + 14
                b.frame = CGRect(x: px - bw, y: 19, width: bw, height: 26)
                px -= bw + 5
            }
            amountEditor.frame = CGRect(x: 12, y: 24, width: max(60, px - 20), height: 34)
            editKey.frame = CGRect(x: 16, y: 6, width: max(60, px - 24), height: 16)
            return
        }
        if !ctaButton.isHidden {
            leadLabel.frame = CGRect(x: 24, y: 46, width: w - 48, height: 40)
            ctaButton.frame = CGRect(x: 60, y: 100, width: w - 120, height: 42)
            return
        }
        if isBuy, !payCard.isHidden {
            layoutBuy()
            return
        }
        let x: CGFloat = 10
        let cw = w - 20
        balanceKey.frame = CGRect(x: x + 4, y: 12, width: 54, height: 16)
        let bv = min(balanceValue.intrinsicContentSize.width, w * 0.35)
        balanceValue.frame = CGRect(x: balanceKey.frame.maxX + 6, y: 5, width: bv, height: 26)
        let toksX = balanceValue.frame.maxX + 8
        balanceTokens.frame = CGRect(x: toksX, y: 11, width: max(0, w - x - 4 - toksX), height: 18)

        amountRow.frame = CGRect(x: x, y: 36, width: cw, height: 46)
        let al = min(amountLabel.intrinsicContentSize.width, 120)
        amountLabel.frame = CGRect(x: 12, y: 0, width: al, height: 46)
        unitLabel.frame = CGRect(x: amountLabel.frame.maxX + 6, y: 0,
                                 width: unitLabel.intrinsicContentSize.width, height: 46)
        toZone.frame = CGRect(x: cw - 168, y: 0, width: 156, height: 46)
        toName.frame = CGRect(x: 0, y: 8, width: 156, height: 16)
        toAddress.frame = CGRect(x: 0, y: 24, width: 156, height: 14)
        arrowLabel.isHidden = isBuy
        arrowLabel.frame = CGRect(x: toZone.frame.minX - 16, y: 0, width: 14, height: 46)

        assetsRow.frame = CGRect(x: x, y: 88, width: cw, height: 28)
        var ax: CGFloat = 0
        for b in assetButtons {
            let bw = b.intrinsicContentSize.width + 8
            b.frame = CGRect(x: ax, y: 1, width: bw, height: 26)
            ax += bw + 6
        }
        assetsRow.contentSize = CGSize(width: max(0, ax - 6), height: 28)

        var y: CGFloat = 122
        if !privateRow.isHidden {
            privateRow.frame = CGRect(x: x, y: y, width: cw, height: 36)
            privateIcon.frame = CGRect(x: 10, y: 8, width: 20, height: 20)
            privateTitle.frame = CGRect(x: 38, y: 0, width: 60, height: 36)
            privateBy.frame = CGRect(x: 96, y: 0, width: 170, height: 36)
            privateSwitch.frame = CGRect(x: cw - 54, y: 6, width: 51, height: 31)
            y = privateRow.frame.maxY + 5
        }
        if !metaLabel.isHidden {
            metaLabel.frame = CGRect(x: x, y: y, width: cw, height: 15)
            y = metaLabel.frame.maxY + 5
        }
        let goH: CGFloat = 42
        let goY = min(max(y, bounds.height - goH - 10), bounds.height - goH - 6)
        goButton.frame = CGRect(x: x, y: goY, width: cw, height: goH)
    }

    /// You pay over You get over the button, filling the panel; the route
    /// line under the button only when there's room for it.
    private func layoutBuy() {
        let x: CGFloat = 10
        let cw = bounds.width - 20
        let goH: CGFloat = 42
        let showMeta = bounds.height >= 236
        metaLabel.isHidden = !showMeta
        let bottom = bounds.height - 8 - (showMeta ? 19 : 0)
        goButton.frame = CGRect(x: x, y: bottom - goH, width: cw, height: goH)
        if showMeta { metaLabel.frame = CGRect(x: x, y: goButton.frame.maxY + 4, width: cw, height: 15) }
        let top: CGFloat = 6
        let gap: CGFloat = 6
        let room = goButton.frame.minY - 8 - top - gap
        let payH = min(84, max(66, (room * 0.53).rounded()))
        let getH = max(56, room - payH)
        payCard.frame = CGRect(x: x, y: top, width: cw, height: payH)
        getCard.frame = CGRect(x: x, y: payCard.frame.maxY + gap, width: cw, height: getH)

        // You pay: the key and balance chips on top, the amount and its
        // dollars down the left, the token pill on the right.
        payKey.frame = CGRect(x: 12, y: 8, width: 70, height: 16)
        maxButton.frame = CGRect(x: cw - 10 - 38, y: 7, width: 38, height: 18)
        halfButton.frame = CGRect(x: maxButton.frame.minX - 5 - 40, y: 7, width: 40, height: 18)
        payHeld.frame = CGRect(x: 80, y: 7, width: max(0, halfButton.frame.minX - 86), height: 18)
        let pw = min(140, payToken.intrinsicContentSize.width + 2)
        let tokenY = 8 + 16 + (payH - 24 - 32) / 2
        payToken.frame = CGRect(x: cw - 10 - pw, y: tokenY, width: pw, height: 32)
        payAmount.frame = CGRect(x: 12, y: 26, width: payToken.frame.minX - 20, height: 30)
        payUSD.frame = CGRect(x: 12, y: payAmount.frame.maxY, width: payToken.frame.minX - 20, height: 15)

        // You get: the quote, its dollars and the rate; the bought token's
        // pill on the right. Or, while choosing, the wallet's tokens.
        getKey.frame = CGRect(x: 12, y: 8, width: 120, height: 16)
        let gw = getToken.intrinsicContentSize.width + 24
        getToken.frame = CGRect(x: cw - 10 - gw, y: 8 + 16 + (getH - 24 - 28) / 2, width: gw, height: 28)
        getAmount.frame = CGRect(x: 12, y: 24, width: getToken.frame.minX - 20, height: 28)
        getUSD.frame = CGRect(x: 12, y: getAmount.frame.maxY, width: cw - 24, height: 15)

        // The dropdown hangs from the pill, right edges lined up, and
        // scrolls when the wallet holds more than the panel can show.
        tokenScrim.frame = bounds
        let pill = payCard.convert(payToken.frame, to: self)
        let menuW = min(250, cw)
        let menuX = max(x, min(bounds.width - x - menuW, pill.maxX - menuW))
        let menuY = pill.maxY + 6
        let rowH = Self.tokenRowHeight
        let contentH = CGFloat(tokenRows.count) * rowH
        let menuH = max(rowH, min(contentH, bounds.height - menuY - 8))
        tokenMenu.bounds = CGRect(x: 0, y: 0, width: menuW, height: menuH)
        tokenMenu.center = CGPoint(x: menuX + menuW / 2, y: menuY + menuH / 2)
        tokenMenu.layer.shadowPath = UIBezierPath(roundedRect: tokenMenu.bounds, cornerRadius: 14).cgPath
        tokenList.frame = tokenMenu.bounds
        tokenList.contentSize = CGSize(width: menuW, height: contentH)
        for (i, row) in tokenRows.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(i) * rowH, width: menuW, height: rowH)
            let tickX = menuW - 14 - 16
            row.viewWithTag(3)?.frame = CGRect(x: tickX, y: 0, width: 16, height: rowH)
            let nameW = min(menuW * 0.5, (row.viewWithTag(1) as? UILabel)?.intrinsicContentSize.width ?? 80)
            row.viewWithTag(1)?.frame = CGRect(x: 14, y: 0, width: nameW, height: rowH)
            row.viewWithTag(2)?.frame = CGRect(x: 14 + nameW + 8, y: 0, width: max(0, tickX - 8 - (14 + nameW + 8)), height: rowH)
            row.viewWithTag(4)?.frame = CGRect(x: 14, y: rowH - 0.5, width: menuW - 14, height: 0.5)
        }
    }
}
