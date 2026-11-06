import UIKit

protocol TradeSurfaceDelegate: AnyObject {
    /// The trade as set and quoted, handed to the app, which signs it with
    /// the chosen wallet and says how it went when the keyboard is next up.
    func tradeHandOff(query: [String: String])
    /// No Glyf wallet on this phone yet: the app makes one.
    func tradeSetUpWallet()
    func tradeToast(_ text: String)
    /// A value started or stopped being typed: the keys come and go.
    func tradeLayoutChanged()
}

/// A trade, set in the keyboard before it's signed: Uniswap swaps and
/// Definitive's Flash orders on one panel. Every value is tapped to change:
/// the amount and prices on the keyboard's own digits (the panel folds to a
/// strip over them, as the Buy panel does), tokens from a picker with
/// search, chains from a list. One card per side, at most one detail line
/// each, one button. The quote here is Uniswap's (or the price an order
/// waits on); the app asks again at signing, so nothing shown is signed.
final class TradeSurface: UIView {

    weak var delegate: TradeSurfaceDelegate?

    private(set) var intent: TradeIntent

    /// What the panel shows: the trade, a value being typed, or a picker.
    enum Mode: Equatable {
        case panel
        case number(TradeField)
        case tokens(TradeEdit.Side)
        case search(TradeEdit.Side)
        case chains(TradeEdit.Side)
    }
    private(set) var mode = Mode.panel

    /// The strip over the keys while a value or a search is typed.
    static let numberStripHeight: CGFloat = 64
    static let searchStripHeight: CGFloat = 104

    var editStripHeight: CGFloat? {
        switch mode {
        case .number: return Self.numberStripHeight
        case .search: return Self.searchStripHeight
        default: return nil
        }
    }

    /// The editor the keys type into, while one is up.
    var activeEditor: InlineEditor? {
        switch mode {
        case .number: return numberEditor
        case .search: return searchEditor
        default: return nil
        }
    }

    /// Digits for values, letters for a token search.
    var wantsDecimalPad: Bool { if case .number = mode { return true } else { return false } }

    private var searching: Bool { if case .search = mode { return true } else { return false } }

    // MARK: views

    private let payCard = TradeCard()
    private let getCard = TradeCard()
    private let rowsCard = UIView()
    private var rows: [FieldRow] = []
    private let flipButton = UIButton(type: .custom)
    private let goButton = UIButton(type: .system)

    // Strip
    private let stripKey = UILabel()
    let numberEditor = InlineEditor(placeholder: "0")
    let searchEditor = InlineEditor(placeholder: "Search or paste address", searchStyle: true)
    private let doneButton = UIButton(type: .system)
    private let resultsRow = UIStackView()

    // Pickers
    private let backButton = UIButton(type: .system)
    private let pickerTitle = UILabel()
    private let pickerScroll = UIScrollView()
    private let pickerHint = UILabel()

    // MARK: live numbers

    private var quoteOut: Double?
    private var quoteInUSD: Double?
    private var quoteOutUSD: Double?
    private var quoteError: String?
    private var marketPrice: Double?
    /// Whole tokens held by symbol, per chain, once /evm/balances answers.
    private var held: [String: [String: Double]] = [:]
    private var resolved: String?
    private var resolveFailed = false
    private var asking = true
    private var quoteTask: URLSessionDataTask?
    private var quoteWork: DispatchWorkItem?
    private var quoteSerial = 0

    /// Picker rows per chain (server answer merged over the built-in few).
    private var tokenRows: [String: [TokenPick]] = [:]
    /// Logos and addresses of tokens on the panel, by "chain|SYMBOL".
    private var known: [String: TokenPick] = [:]
    private var searchWork: DispatchWorkItem?
    private var searchResults: [TokenPick] = []
    private var searchLoading = false

    private var wallet: String? {
        intent.chainName == "solana" ? SettingsStore.current.walletAddress : SettingsStore.current.evmAddress
    }

    private var walletName: String {
        TradeIntent.walletName(chain: intent.chainName, mode: SettingsStore.current.walletMode)
    }

    private var isSwap: Bool { intent.kind == .swap }
    private var buyChain: String { intent.buyChain ?? intent.chainName }

    init(intent: TradeIntent) {
        self.intent = intent
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        build()
        render()
        loadBalances(intent.chainName)
        loadLive()
        prefetchTokens(intent.chainName)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The strip's header while the panel is up.
    var headerTitle: String {
        switch intent.kind {
        case .swap: return "Swap"
        case .limit: return "Limit order"
        case .stop: return "Stop buy"
        case .stopLoss: return "Stop-loss"
        case .takeProfit: return "Take profit"
        case .bracket: return "Bracket"
        case .trailingStop: return "Trailing stop"
        case .twap: return "TWAP"
        case .bridge: return "Bridge"
        case .send: return "Send"
        case .request: return "Request USDT"
        }
    }

    // MARK: build

    private func build() {
        addSubview(payCard)
        addSubview(getCard)
        payCard.accessibilityIdentifier = "trade:top"
        getCard.accessibilityIdentifier = "trade:bottom"
        payCard.amount.accessibilityIdentifier = "trade:amount"
        getCard.amount.accessibilityIdentifier = "trade:value"
        getCard.sub.accessibilityIdentifier = "trade:sub"
        payCard.token.accessibilityIdentifier = "trade:token:sell"
        getCard.token.accessibilityIdentifier = "trade:token:buy"
        payCard.chain.accessibilityIdentifier = "trade:chain:sell"
        getCard.chain.accessibilityIdentifier = "trade:chain:buy"
        payCard.onAmount = { [weak self] in self?.begin(.amount) }
        payCard.token.addAction(UIAction { [weak self] _ in self?.openTokens(.sell) }, for: .touchUpInside)
        getCard.token.addAction(UIAction { [weak self] _ in self?.openTokens(.buy) }, for: .touchUpInside)
        payCard.chain.addAction(UIAction { [weak self] _ in self?.openChains(.sell) }, for: .touchUpInside)
        getCard.chain.addAction(UIAction { [weak self] _ in self?.openChains(.buy) }, for: .touchUpInside)

        rowsCard.backgroundColor = Glass.surfaceCard
        rowsCard.layer.cornerRadius = 16
        rowsCard.layer.cornerCurve = .continuous
        rowsCard.accessibilityIdentifier = "trade:rows"
        addSubview(rowsCard)

        flipButton.backgroundColor = Self.flipFill
        flipButton.layer.cornerRadius = 16
        flipButton.layer.borderWidth = 3
        flipButton.layer.borderColor = Glass.touchableGrid.cgColor
        flipButton.setImage(UIImage(systemName: "arrow.down", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        flipButton.tintColor = Glass.textPrimary
        flipButton.accessibilityIdentifier = "trade:flip"
        flipButton.accessibilityLabel = "Flip"
        flipButton.addAction(UIAction { [weak self] _ in self?.flip() }, for: .touchUpInside)
        addSubview(flipButton)

        goButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        goButton.titleLabel?.adjustsFontSizeToFitWidth = true
        goButton.titleLabel?.minimumScaleFactor = 0.8
        goButton.setTitleColor(.white, for: .normal)
        goButton.backgroundColor = Glass.imBlue
        goButton.layer.cornerRadius = 14
        goButton.layer.cornerCurve = .continuous
        goButton.accessibilityIdentifier = "trade:go"
        goButton.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
        addSubview(goButton)

        // Strip
        stripKey.font = .systemFont(ofSize: 12, weight: .semibold)
        stripKey.textColor = Glass.textSecondary
        addSubview(stripKey)
        numberEditor.accessibilityIdentifier = "trade:editor"
        numberEditor.onChange = { [weak self] text in self?.numberChanged(text) }
        addSubview(numberEditor)
        searchEditor.accessibilityIdentifier = "trade:search"
        searchEditor.onChange = { [weak self] text in self?.searchChanged(text) }
        searchEditor.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(searchTapped)))
        addSubview(searchEditor)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = Glass.imBlue
        doneButton.layer.cornerRadius = 16
        doneButton.layer.cornerCurve = .continuous
        doneButton.accessibilityIdentifier = "trade:done"
        doneButton.addAction(UIAction { [weak self] _ in self?.endEditing() }, for: .touchUpInside)
        addSubview(doneButton)
        resultsRow.axis = .horizontal
        resultsRow.spacing = 6
        resultsRow.distribution = .fillEqually
        addSubview(resultsRow)

        // Pickers
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        backButton.tintColor = Glass.textPrimary
        backButton.backgroundColor = Glass.surfaceCard
        backButton.layer.cornerRadius = 17
        backButton.accessibilityIdentifier = "trade:back"
        backButton.accessibilityLabel = "Back"
        backButton.addAction(UIAction { [weak self] _ in self?.closePicker() }, for: .touchUpInside)
        addSubview(backButton)
        pickerTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        pickerTitle.textColor = Glass.textPrimary
        addSubview(pickerTitle)
        pickerScroll.showsVerticalScrollIndicator = false
        pickerScroll.alwaysBounceVertical = true
        pickerScroll.backgroundColor = Glass.touchableGrid
        pickerScroll.accessibilityIdentifier = "trade:picker"
        addSubview(pickerScroll)
        pickerHint.font = .systemFont(ofSize: 13)
        pickerHint.textColor = Glass.textSecondary
        pickerHint.textAlignment = .center
        addSubview(pickerHint)
    }

    private static let flipFill = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.24, alpha: 1) : UIColor(white: 0.90, alpha: 1) }

    // MARK: modes

    private func setMode(_ m: Mode) {
        let wasStrip = editStripHeight
        let wasEditor = activeEditor
        mode = m
        render()
        if wasStrip != editStripHeight || wasEditor !== activeEditor { delegate?.tradeLayoutChanged() }
    }

    private func begin(_ field: TradeField) {
        if intent.kind == .request, field != .amount { return }
        numberEditor.setText(TradeEdit.value(field, intent))
        setMode(.number(field))
    }

    /// Return or Done: a value is set, a search goes back to its list.
    func endEditing() {
        switch mode {
        case .number: setMode(.panel); requote()
        case .search(let side): setMode(.tokens(side))
        default: break
        }
    }

    private func numberChanged(_ text: String) {
        guard case .number(let field) = mode else { return }
        let clean = TradeEdit.cleanNumber(text)
        if clean != text { numberEditor.setText(clean); return }
        intent = TradeEdit.apply(field, clean, to: intent)
    }

    private func openTokens(_ side: TradeEdit.Side) {
        if intent.kind == .request { return }
        searchEditor.setText("")
        searchResults = []
        setMode(.tokens(side))
        prefetchTokens(chain(of: side))
        loadBalances(chain(of: side))
    }

    private func openChains(_ side: TradeEdit.Side) {
        if TradeEdit.chains(for: intent).count < 2 { return }
        setMode(.chains(side))
    }

    private func closePicker() { setMode(.panel) }

    @objc private func searchTapped() {
        if case .tokens(let side) = mode { setMode(.search(side)) }
    }

    private func chain(of side: TradeEdit.Side) -> String {
        side == .buy && isSwap ? buyChain : intent.chainName
    }

    /// The side a Flash order's token pill changes (its asset).
    private var assetSide: TradeEdit.Side { TradeEdit.sells(intent) ? .sell : .buy }

    private func flip() {
        intent = TradeEdit.flip(intent)
        clearQuote()
        render()
        loadBalances(intent.chainName)
        requote()
    }

    private func clearQuote() { quoteOut = nil; quoteInUSD = nil; quoteOutUSD = nil; quoteError = nil }

    private func picked(_ token: TokenPick, side: TradeEdit.Side) {
        known["\(chain(of: side))|\(token.symbol.uppercased())"] = token
        intent = TradeEdit.repriced(TradeEdit.pick(token, side: isSwap ? side : assetSide, in: intent), was: intent)
        clearQuote()
        if !isSwap { marketPrice = nil; asking = true }
        setMode(.panel)
        loadLive()
    }

    private func pickedChain(_ chain: String, side: TradeEdit.Side) {
        intent = TradeEdit.repriced(TradeEdit.pickChain(chain, side: side, in: intent), was: intent)
        clearQuote()
        if !isSwap, side == .sell { marketPrice = nil; asking = true }
        setMode(.panel)
        loadBalances(intent.chainName)
        prefetchTokens(chain)
        loadLive()
    }

    // MARK: live numbers

    private func loadLive() {
        let i = intent
        switch i.kind {
        case .swap:
            requote()
        case .send:
            if let to = i.to, !to.hasPrefix("0x") {
                BackendClient.shared.evmJSON(path: "/names/resolve?name=\(to)") { [weak self] obj in
                    guard let self else { return }
                    let addresses = obj?["addresses"] as? [String: Any]
                    let key = i.chainName == "solana" ? "solana" : i.chainName
                    self.resolved = (addresses?[key] as? String) ?? (addresses?["ethereum"] as? String)
                    self.resolveFailed = self.resolved == nil
                    self.asking = false
                    self.render()
                }
            } else {
                resolved = i.to
                asking = false
            }
            price(of: i.sell)
        case .request:
            asking = false
        default:
            price(of: TradeEdit.asset(i))
        }
        render()
    }

    private func loadBalances(_ chain: String) {
        guard chain != "solana", intent.kind != .request, held[chain] == nil,
              let address = SettingsStore.current.evmAddress, !address.isEmpty else { return }
        BackendClient.shared.evmJSON(path: "/evm/balances?chain=\(chain)&address=\(address)") { [weak self] obj in
            guard let self, let list = obj?["balances"] as? [[String: Any]] else { return }
            var map: [String: Double] = [:]
            for row in list {
                let symbol = ((row["symbol"] as? String) ?? "").uppercased()
                map[symbol == "NATIVE" ? "ETH" : symbol] = Self.number(row["amount"]) ?? Self.number(row["balance"]) ?? 0
            }
            self.held[chain] = map
            self.render()
        }
    }

    /// Whole tokens of `symbol` held on `chain`; nil until known.
    private func balance(_ symbol: String, on chain: String) -> Double? {
        guard let map = held[chain] else { return nil }
        return map[symbol.uppercased()] ?? 0
    }

    /// A quote shortly after the last change (typing doesn't ask per key).
    private func requote() {
        guard isSwap else {
            if intent.awaitingPrice { price(of: TradeEdit.asset(intent)) }
            render()
            return
        }
        quoteWork?.cancel()
        quoteTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.quote() }
        quoteWork = work
        asking = true
        quoteError = nil
        render()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func quote() {
        let i = intent
        quoteSerial += 1
        let serial = quoteSerial
        if TradeEdit.problem(i) != nil { asking = false; render(); return }
        // "buy 0.1 eth": what 0.1 ETH costs, asked the other way round.
        let reversed = i.buyAmount != nil
        let sellRef = i.sellAddress ?? i.sell
        let buyRef = i.buyAddress ?? i.buy
        guard let amount = reversed ? i.buyAmount : i.amount else {
            asking = false; clearQuote(); render(); return
        }
        if i.chainName == "solana" { jupiterQuote(i, amount: amount, reversed: reversed, serial: serial); return }
        var body: [String: Any] = ["chain": reversed ? buyChain : i.chainName,
                                   "sell": reversed ? buyRef : sellRef, "buy": reversed ? sellRef : buyRef,
                                   "amount": amount]
        if buyChain != i.chainName { body["buyChain"] = reversed ? i.chainName : buyChain }
        quoteTask = BackendClient.shared.evmJSONResult(path: "/uniswap/quote", body: body) { [weak self] ok, obj in
            guard let self, serial == self.quoteSerial else { return }
            self.asking = false
            if ok, let obj, obj["amountOut"] != nil {
                self.quoteError = nil
                self.quoteOut = Self.number(obj["amountOut"])
                let inUSD = Self.number(obj["sellUsd"]) ?? Self.number((obj["sell"] as? [String: Any])?["usd"])
                let outUSD = Self.number(obj["buyUsd"]) ?? Self.number((obj["buy"] as? [String: Any])?["usd"])
                self.quoteInUSD = reversed ? outUSD : inUSD
                self.quoteOutUSD = reversed ? inUSD : outUSD
            } else {
                self.quoteOut = nil; self.quoteInUSD = nil; self.quoteOutUSD = nil
                self.quoteError = Self.shortError(obj?["error"] as? String)
            }
            self.render()
        }
    }

    /// One short line from the server's words.
    static func shortError(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "No quote right now" }
        if raw.count <= 60 { return raw }
        return String(raw.prefix(57)) + "…"
    }

    private func price(of symbol: String) {
        if TradeEdit.stables.contains(symbol) { marketPrice = 1; asking = false; render(); return }
        if symbol == "SOL" || intent.chainName == "solana" { jupiterPrice(symbol); return }
        let ref = known["\(intent.chainName)|\(symbol.uppercased())"]?.address ?? symbol
        BackendClient.shared.evmJSON(path: "/uniswap/quote",
                                     body: ["chain": intent.chainName, "sell": ref, "buy": "USDC", "amount": "1"]) { [weak self] obj in
            guard let self else { return }
            let price = Self.number(obj?["amountOut"])
            if price == nil, self.intent.awaitingPrice { self.jupiterPrice(symbol); return }
            self.asking = false
            self.marketPrice = price
            self.fillPrice()
            self.render()
        }
    }

    /// A Solana swap's quote: Jupiter's prices for both sides (the app asks
    /// Jupiter for the real order before anything is signed).
    private func jupiterQuote(_ i: TradeIntent, amount: String, reversed: Bool, serial: Int) {
        let rates = RatesStore.shared
        let usd = { (symbol: String) -> Double? in TradeEdit.stables.contains(symbol) ? 1 : rates.crypto[symbol] }
        let take = { [weak self] in
            guard let self, serial == self.quoteSerial, self.asking else { return }
            guard let sell = usd(i.sell), let buy = usd(i.buy), sell > 0, buy > 0,
                  let n = Double(amount.replacingOccurrences(of: ",", with: "")) else { return }
            self.asking = false
            self.quoteError = nil
            // Forward: what `n` of the sell side gets. Reversed: what `n` of
            // the buy side costs, in the sell side.
            self.quoteOut = reversed ? n * buy / sell : n * sell / buy
            self.quoteInUSD = n * (reversed ? buy : sell)
            self.quoteOutUSD = self.quoteInUSD
            self.render()
        }
        for symbol in [i.sell, i.buy] where usd(symbol) == nil { rates.ensureToken(symbol, then: take) }
        take()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, serial == self.quoteSerial, self.asking else { return }
            self.asking = false
            self.quoteError = "Jupiter has no price right now"
            self.render()
        }
    }

    private func jupiterPrice(_ symbol: String) {
        let rates = RatesStore.shared
        let take = { [weak self] in
            guard let self, self.asking else { return }
            self.asking = false
            self.marketPrice = rates.crypto[symbol]
            self.fillPrice()
            self.render()
        }
        if rates.crypto[symbol] != nil { take(); return }
        rates.ensureToken(symbol, then: take)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: take)
    }

    private func fillPrice() {
        guard intent.awaitingPrice, let marketPrice else { return }
        intent = SponsorMenu.priced(intent, market: marketPrice)
    }

    // MARK: tokens

    private func prefetchTokens(_ chain: String, query: String = "") {
        if tokenRows[chain] == nil { tokenRows[chain] = TradeEdit.builtIn(chain: chain) }
        guard chain != "solana", intent.kind != .request else { return }
        if query.isEmpty, (tokenRows[chain]?.count ?? 0) > 8 { return }
        let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if !query.isEmpty { searchLoading = true }
        _ = BackendClient.shared.evmJSONResult(path: "/uniswap/tokens?chain=\(chain)&q=\(q)&limit=40") { [weak self] _, obj in
            guard let self else { return }
            let rows = ((obj?["tokens"] as? [[String: Any]]) ?? []).compactMap(TokenPick.init(json:))
            if query.isEmpty {
                self.tokenRows[chain] = TradeEdit.merge(TradeEdit.builtIn(chain: chain), rows)
            } else {
                self.searchLoading = false
                self.tokenRows[chain] = TradeEdit.merge(self.tokenRows[chain] ?? [], rows)
                guard self.searchEditor.text == query else { return }
                self.searchResults = TradeEdit.merge(TradeEdit.filter(self.tokenRows[chain] ?? [], query: query), rows)
            }
            for t in rows where self.known["\(chain)|\(t.symbol.uppercased())"] == nil {
                self.known["\(chain)|\(t.symbol.uppercased())"] = t
            }
            self.render()
        }
    }

    private func searchChanged(_ text: String) {
        guard case .search(let side) = mode else { return }
        let chain = chain(of: side)
        searchResults = TradeEdit.filter(tokenRows[chain] ?? [], query: text)
        searchWork?.cancel()
        if !text.isEmpty, chain != "solana" {
            let work = DispatchWorkItem { [weak self] in self?.prefetchTokens(chain, query: text) }
            searchWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        render()
    }

    /// The rows the picker lists now.
    private func pickerTokens(_ side: TradeEdit.Side) -> [TokenPick] {
        let chain = chain(of: side)
        let all = tokenRows[chain] ?? TradeEdit.builtIn(chain: chain)
        let q = searchEditor.text
        if q.isEmpty { return all }
        return searchResults.isEmpty ? TradeEdit.filter(all, query: q) : searchResults
    }

    private func logo(_ symbol: String, chain: String) -> String? {
        known["\(chain)|\(symbol.uppercased())"]?.logo
            ?? tokenRows[chain]?.first(where: { $0.symbol.uppercased() == symbol.uppercased() })?.logo
    }

    // MARK: render

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// "4,426,585.96", "0.011253": grouped, with as many places as matter.
    static func amount(_ v: Double, _ symbol: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = v >= 1000 ? 2 : v >= 1 ? 4 : 6
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// What the balances answer says is held of `symbol`, in whole tokens.
    static func balance(of symbol: String, in obj: [String: Any]?) -> Double? {
        guard let rows = obj?["balances"] as? [[String: Any]] else { return nil }
        let wanted = symbol == "ETH" ? ["ETH", "NATIVE"] : [symbol]
        for row in rows where wanted.contains(((row["symbol"] as? String) ?? "").uppercased()) {
            return number(row["amount"]) ?? number(row["balance"])
        }
        return 0
    }

    /// Dollars as the panel says them; a dust amount isn't "$0.00".
    static func approx(_ v: Double) -> String {
        v > 0 && v < 0.01 ? "< $0.01" : "≈ " + PaySurface.dollars(v)
    }

    private func label(_ chain: String) -> String { TradeIntent.chainLabels[chain] ?? chain.capitalized }
    private static func display(_ symbol: String) -> String { symbol == "CBBTC" ? "cbBTC" : symbol }

    private func render() {
        let panel = mode == .panel
        let picker: Bool = { switch mode { case .tokens, .chains: return true; default: return false } }()
        let tokensList: Bool = { if case .tokens = mode { return true } else { return false } }()
        let chainsList: Bool = { if case .chains = mode { return true } else { return false } }()

        payCard.isHidden = !panel
        getCard.isHidden = !panel || !isSwap
        rowsCard.isHidden = !panel || isSwap
        flipButton.isHidden = !panel || !isSwap
        goButton.isHidden = !panel
        stripKey.isHidden = !wantsDecimalPad
        numberEditor.isHidden = !wantsDecimalPad
        searchEditor.isHidden = !(tokensList || searching)
        doneButton.isHidden = editStripHeight == nil
        resultsRow.isHidden = !searching
        backButton.isHidden = !picker
        pickerTitle.isHidden = !chainsList
        pickerScroll.isHidden = !picker
        pickerHint.isHidden = true

        switch mode {
        case .panel: renderPanel()
        case .number(let field):
            stripKey.text = TradeEdit.label(field, intent)
            numberEditor.placeholder = field == .amount && TradeEdit.sells(intent) && intent.kind != .bridge ? "All" : "0"
        case .tokens(let side): renderTokenList(side)
        case .search(let side): renderResults(side)
        case .chains(let side): renderChainList(side)
        }
        setNeedsLayout()
    }

    private func renderPanel() {
        defer { payCard.setNeedsLayout(); getCard.setNeedsLayout() }
        let i = intent
        let tappable = i.kind != .request
        // Top card: what's spent, or an order's asset.
        let top = isSwap ? i.sell : TradeEdit.asset(i)
        payCard.key.text = topKey
        payCard.setChain(label(i.chainName), key: i.chainName, enabled: TradeEdit.chains(for: i).count > 1)
        payCard.token.set(symbol: Self.display(top), logo: logo(top, chain: i.chainName), enabled: tappable)
        let typed = TradeEdit.value(.amount, i)
        payCard.setAmount(TradeEdit.shown(.amount, i), placeholder: typed.isEmpty)

        if isSwap {
            if i.buyAmount != nil {
                payCard.setAmount(quoteOut.map { "≈ " + Self.amount($0, i.sell) } ?? (asking ? "…" : "0"), placeholder: quoteOut == nil)
            }
            var detail: [String] = []
            if let usd = quoteInUSD { detail.append(Self.approx(usd)) }
            if let have = balance(i.sell, on: i.chainName), have > 0 { detail.append("Balance \(PaySurface.compact(have))") }
            payCard.sub.text = detail.joined(separator: " · ")
            getCard.key.text = "You get"
            getCard.setChain(label(buyChain), key: buyChain, enabled: true)
            getCard.token.set(symbol: Self.display(i.buy), logo: logo(i.buy, chain: buyChain), enabled: true)
            if let buyAmount = i.buyAmount {
                getCard.setAmount(buyAmount, placeholder: false)
            } else if let quoteOut {
                getCard.setAmount(Self.amount(quoteOut, i.buy), placeholder: false)
            } else {
                getCard.setAmount(asking && i.amount != nil ? "…" : "0", placeholder: true)
            }
            getCard.amount.isUserInteractionEnabled = false
            // An error speaks on the button, in one line.
            getCard.sub.text = quoteError == nil ? (quoteOutUSD.map { Self.approx($0) } ?? "") : ""
        } else {
            // Orders: what's held of the asset, and the price now.
            var detail: [String] = []
            if i.kind == .request { detail.append("Test USDT on Whitechain") }
            else if let p = marketPrice { detail.append("\(Self.display(top)) \(PaySurface.dollars(p))") }
            else if asking { detail.append("…") }
            if TradeEdit.sells(i), let have = balance(top, on: i.chainName), have > 0 { detail.append("Balance \(PaySurface.compact(have))") }
            payCard.sub.text = detail.joined(separator: " · ")
            renderRows()
        }
        renderGo()
    }

    private var topKey: String {
        switch intent.kind {
        case .swap: return "You pay"
        case .send: return "Send"
        case .request: return "Ask for"
        case .bridge: return "Move"
        case .twap: return "Spend"
        default: return TradeEdit.sells(intent) ? "Sell" : "Buy"
        }
    }

    /// An order's values under the asset: one row each, tap to change.
    private func renderRows() {
        let i = intent
        var specs: [(id: String, label: String, value: String, tap: Bool, action: () -> Void)] = []
        for field in TradeEdit.fields(i) where field != .amount {
            specs.append((field.rawValue, TradeEdit.label(field, i), TradeEdit.shown(field, i), true,
                          { [weak self] in self?.begin(field) }))
        }
        switch i.kind {
        case .bridge:
            specs.append(("toChain", "To", label(i.toChain ?? ""), true, { [weak self] in self?.openChains(.buy) }))
        case .send:
            let name = i.to.map { $0.hasPrefix("0x") ? Smart.shortAddress($0) : $0 } ?? ""
            specs.append(("to", "To", name, false, {}))
            if i.to?.hasPrefix("0x") == false {
                let to = resolved.map(Smart.shortAddress) ?? (resolveFailed ? "Not found" : (asking ? "…" : ""))
                specs.append(("address", "Address", to, false, {}))
            }
        case .request:
            specs.append(("paidTo", "Paid to", wallet.map(Smart.shortAddress) ?? "Your \(walletName)", false, {}))
        default:
            break
        }
        // A recurring buy: the Over row says how much of the plan this Flash
        // order holds (Flash runs 30 days at most).
        if let over = i.planOverRow, let k = specs.firstIndex(where: { $0.id == TradeField.duration.rawValue }) {
            specs[k].label = over.label
            specs[k].value = over.value
        }
        while rows.count < specs.count {
            let r = FieldRow()
            rowsCard.addSubview(r)
            rows.append(r)
        }
        for (k, r) in rows.enumerated() {
            r.isHidden = k >= specs.count
            guard k < specs.count else { continue }
            let s = specs[k]
            r.accessibilityIdentifier = "trade:row:\(s.id)"
            r.set(label: s.label, value: s.value, tappable: s.tap, separator: k > 0)
            r.onTap = s.action
        }
    }

    /// The wallet knows what's held and it's short of what's spent.
    private var short: Bool {
        let i = intent
        guard i.kind != .request, i.chainName != "solana", let held = balance(i.sell, on: i.chainName) else { return false }
        guard TradeEdit.sells(i) || i.amountIsUSD || i.buyAmount != nil || i.kind == .twap else { return false }
        if i.amount == nil, i.buyAmount == nil { return held <= 0 }
        let spend = i.buyAmount != nil ? quoteOut : Double(i.amount ?? "")
        guard let spend else { return false }
        return spend > held + 1e-12
    }

    private var needsGlyfWallet: Bool { wallet == nil && intent.chainName != "solana" }


    private var goTitle: String {
        if needsGlyfWallet { return "Set up your Glyf wallet" }
        if let p = TradeEdit.problem(intent) { return p }
        if intent.awaitingPrice { return asking ? "Getting the price" : "No price yet" }
        if isSwap, let quoteError { return quoteError }
        if short { return "Not enough \(Self.display(intent.sell))" }
        switch intent.kind {
        case .swap:
            if let usd = quoteInUSD { return "Swap ≈ \(PaySurface.dollars(usd))" }
            return "Swap"
        case .limit: return "Place limit order"
        case .stop: return "Place stop buy"
        case .stopLoss: return "Place stop-loss"
        case .takeProfit: return "Place take profit"
        case .bracket: return "Set bracket"
        case .trailingStop: return "Set trailing stop"
        case .twap: return "Start TWAP"
        case .bridge: return "Move to \(label(intent.toChain ?? ""))"
        case .send: return resolveFailed ? "Name not found" : "Send \(intent.amount ?? "") \(intent.sell)"
        case .request: return "Create request"
        }
    }

    private var blocked: Bool {
        if needsGlyfWallet { return false }
        if TradeEdit.problem(intent) != nil || short || intent.awaitingPrice { return true }
        if intent.kind == .send && resolveFailed { return true }
        if isSwap, quoteError != nil || asking { return true }
        return false
    }

    private func renderGo() {
        goButton.setTitle(goTitle, for: .normal)
        let off = blocked
        goButton.backgroundColor = off ? Self.offFill : Glass.imBlue
        goButton.setTitleColor(off ? Glass.textSecondary : .white, for: .normal)
    }

    private static let offFill = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.06) }

    private func go() {
        guard !needsGlyfWallet else { delegate?.tradeSetUpWallet(); return }
        guard !blocked else { return }
        var q = intent.query
        if let resolved { q["address"] = resolved }
        delegate?.tradeHandOff(query: q)
    }

    // MARK: pickers

    private func clearPicker() {
        pickerScroll.subviews.forEach { $0.removeFromSuperview() }
    }

    private func renderTokenList(_ side: TradeEdit.Side) {
        clearPicker()
        let chain = chain(of: side)
        let current = side == .sell || !isSwap ? (isSwap ? intent.sell : TradeEdit.asset(intent)) : intent.buy
        let list = pickerTokens(side)
        var y: CGFloat = 0
        for t in list.prefix(60) {
            let row = TokenRow()
            row.set(t, logo: t.logo ?? logo(t.symbol, chain: chain), held: balance(t.symbol, on: chain),
                    selected: t.symbol.uppercased() == current.uppercased())
            row.accessibilityIdentifier = "trade:tokenrow:\(t.symbol)"
            row.onTap = { [weak self] in self?.picked(t, side: side) }
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: TokenRow.height)
            pickerScroll.addSubview(row)
            y += TokenRow.height
        }
        pickerScroll.contentSize = CGSize(width: bounds.width, height: y + 8)
        if list.isEmpty {
            pickerHint.isHidden = false
            pickerHint.text = searchLoading ? "Searching…" : "No tokens match"
        }
    }

    private func renderResults(_ side: TradeEdit.Side) {
        resultsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let chain = chain(of: side)
        let list = Array(pickerTokens(side).prefix(4))
        if list.isEmpty, !searchEditor.text.isEmpty {
            let l = UILabel()
            l.text = searchLoading ? "Searching…" : "No tokens match"
            l.font = .systemFont(ofSize: 13)
            l.textColor = Glass.textSecondary
            resultsRow.addArrangedSubview(l)
            return
        }
        for t in list {
            let b = TokenPill()
            b.compact = true
            b.set(symbol: t.symbol, logo: t.logo ?? logo(t.symbol, chain: chain), enabled: true, chevron: false)
            b.accessibilityIdentifier = "trade:result:\(t.symbol)"
            b.addAction(UIAction { [weak self] _ in self?.picked(t, side: side) }, for: .touchUpInside)
            resultsRow.addArrangedSubview(b)
        }
        // Keep the grid even: blanks fill a short row.
        for _ in list.count..<4 { resultsRow.addArrangedSubview(UIView()) }
    }

    private func renderChainList(_ side: TradeEdit.Side) {
        clearPicker()
        pickerTitle.text = intent.kind == .bridge && side == .buy ? "Move to" : (side == .buy ? "Get it on" : "Chain")
        var chains = TradeEdit.chains(for: intent)
        if intent.kind == .bridge, side == .buy { chains = chains.filter { $0 != intent.chainName } }
        let current = side == .buy ? (intent.kind == .bridge ? (intent.toChain ?? "") : buyChain) : intent.chainName
        var y: CGFloat = 0
        for c in chains {
            let row = TokenRow()
            row.setChain(label(c), chain: c, selected: c == current)
            row.accessibilityIdentifier = "trade:chainrow:\(c)"
            row.onTap = { [weak self] in self?.pickedChain(c, side: side) }
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: TokenRow.chainHeight)
            pickerScroll.addSubview(row)
            y += TokenRow.chainHeight
        }
        pickerScroll.contentSize = CGSize(width: bounds.width, height: y + 8)
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let x: CGFloat = 12
        let cw = w - 24
        switch mode {
        case .number:
            let doneW: CGFloat = 72
            doneButton.frame = CGRect(x: w - 12 - doneW, y: 16, width: doneW, height: 32)
            stripKey.frame = CGRect(x: 16, y: 4, width: doneButton.frame.minX - 24, height: 15)
            numberEditor.frame = CGRect(x: 12, y: 21, width: doneButton.frame.minX - 22, height: 36)
            return
        case .search:
            let doneW: CGFloat = 72
            doneButton.frame = CGRect(x: w - 12 - doneW, y: 10, width: doneW, height: 34)
            searchEditor.frame = CGRect(x: 12, y: 8, width: doneButton.frame.minX - 20, height: 38)
            resultsRow.frame = CGRect(x: 12, y: 56, width: w - 24, height: 38)
            return
        case .tokens:
            backButton.frame = CGRect(x: x, y: 8, width: 34, height: 34)
            searchEditor.frame = CGRect(x: backButton.frame.maxX + 8, y: 6, width: w - backButton.frame.maxX - 20, height: 38)
            pickerScroll.frame = CGRect(x: 0, y: 50, width: w, height: max(0, bounds.height - 50))
            pickerHint.frame = CGRect(x: 0, y: 80, width: w, height: 20)
            for row in pickerScroll.subviews { row.frame.size.width = w }
            return
        case .chains:
            backButton.frame = CGRect(x: x, y: 8, width: 34, height: 34)
            pickerTitle.frame = CGRect(x: backButton.frame.maxX + 12, y: 8, width: w - 120, height: 34)
            pickerScroll.frame = CGRect(x: 0, y: 50, width: w, height: max(0, bounds.height - 50))
            for row in pickerScroll.subviews { row.frame.size.width = w }
            return
        case .panel:
            break
        }
        let goH: CGFloat = 44
        goButton.frame = CGRect(x: x, y: bounds.height - 8 - goH, width: cw, height: goH)
        let top: CGFloat = 8
        let room = goButton.frame.minY - 8 - top
        if isSwap {
            let gap: CGFloat = 4
            let ch = min(84, floor((room - gap) / 2))
            payCard.frame = CGRect(x: x, y: top, width: cw, height: ch)
            getCard.frame = CGRect(x: x, y: payCard.frame.maxY + gap, width: cw, height: ch)
            flipButton.frame = CGRect(x: (w - 32) / 2, y: payCard.frame.maxY + gap / 2 - 16, width: 32, height: 32)
        } else {
            let count = CGFloat(max(1, rows.filter { !$0.isHidden }.count))
            let ch: CGFloat = min(84, max(62, room - 6 - count * 44))
            let rowH = min(44, floor((room - ch - 6) / count))
            payCard.frame = CGRect(x: x, y: top, width: cw, height: ch)
            rowsCard.frame = CGRect(x: x, y: payCard.frame.maxY + 6, width: cw, height: rowH * count)
            var y: CGFloat = 0
            for r in rows where !r.isHidden {
                r.frame = CGRect(x: 0, y: y, width: cw, height: rowH)
                y += rowH
            }
        }
    }
}

// MARK: - pieces

/// One side of a trade: key and chain on top, the amount and the token
/// pill, one detail line.
private final class TradeCard: UIView {
    let key = UILabel()
    let chain = UIButton(type: .system)
    let amount = UILabel()
    let token = TokenPill()
    let sub = UILabel()
    let right = UILabel()
    var onAmount: (() -> Void)?

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceCard
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        key.font = .systemFont(ofSize: 13, weight: .medium)
        key.textColor = Glass.textSecondary
        addSubview(key)
        chain.contentHorizontalAlignment = .right
        chain.contentVerticalAlignment = .top
        addSubview(chain)
        amount.font = .monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        amount.textColor = Glass.textPrimary
        amount.adjustsFontSizeToFitWidth = true
        amount.minimumScaleFactor = 0.5
        amount.isUserInteractionEnabled = true
        amount.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(amountTapped)))
        addSubview(amount)
        addSubview(token)
        for l in [sub, right] {
            l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            l.textColor = Glass.textSecondary
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.8
            addSubview(l)
        }
        right.textAlignment = .right
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func amountTapped() { onAmount?() }

    func setAmount(_ text: String, placeholder: Bool) {
        amount.text = text
        amount.textColor = placeholder ? Glass.textSecondary : Glass.textPrimary
    }

    func setChain(_ name: String, key: String, enabled: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12.5, weight: .medium),
                                                    .foregroundColor: Glass.textSecondary]
        let text = NSMutableAttributedString()
        if let mark = ChainLogo.image(key, side: 13) {
            let a = NSTextAttachment()
            a.image = mark
            a.bounds = CGRect(x: 0, y: -2, width: 13, height: 13)
            text.append(NSAttributedString(attachment: a))
            text.append(NSAttributedString(string: " ", attributes: attrs))
        }
        text.append(NSAttributedString(string: name, attributes: attrs))
        if enabled { text.append(NSAttributedString(string: " ▾", attributes: attrs)) }
        chain.setAttributedTitle(text, for: .normal)
        chain.isUserInteractionEnabled = enabled
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let pad: CGFloat = 14
        // Right: the token pill, the chain under it.
        let pillW = token.fitWidth
        token.frame = CGRect(x: w - 10 - pillW, y: 8, width: pillW, height: 32)
        chain.frame = CGRect(x: w * 0.45, y: token.frame.maxY + 1, width: w * 0.55 - pad + 2, height: max(16, h - token.frame.maxY - 5))
        // Left: "You pay · ≈ $25.00", then the amount.
        let keyW = ceil((key.text as NSString? ?? "").size(withAttributes: [.font: key.font!]).width)
        key.frame = CGRect(x: pad, y: 9, width: keyW, height: 16)
        sub.frame = CGRect(x: key.frame.maxX + 6, y: 9, width: max(0, token.frame.minX - key.frame.maxX - 14), height: 16)
        right.frame = .zero
        amount.frame = CGRect(x: pad, y: 26, width: token.frame.minX - pad - 8, height: max(28, h - 30))
    }
}

/// A token: its logo and symbol on a soft pill, with ▾ when it can change.
private final class TokenPill: UIControl {
    let logoView = UIImageView()
    let symbol = UILabel()
    let chevron = UIImageView(image: UIImage(systemName: "chevron.down", withConfiguration:
        UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)))
    var compact = false
    private var logoURL: String?

    static let fill = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.06) }

    init() {
        super.init(frame: .zero)
        backgroundColor = Self.fill
        layer.cornerCurve = .continuous
        logoView.clipsToBounds = true
        logoView.contentMode = .scaleAspectFill
        symbol.font = .systemFont(ofSize: 16, weight: .semibold)
        symbol.textColor = Glass.textPrimary
        chevron.tintColor = Glass.textSecondary
        for v in [logoView, symbol, chevron] { v.isUserInteractionEnabled = false; addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(symbol s: String, logo: String?, enabled: Bool, chevron showChevron: Bool = true) {
        symbol.text = s
        isAccessibilityElement = true
        accessibilityLabel = s
        accessibilityTraits = .button
        symbol.font = .systemFont(ofSize: compact ? 14 : 16, weight: .semibold)
        chevron.isHidden = !enabled || !showChevron
        isUserInteractionEnabled = enabled
        if logoURL != logo || logoView.image == nil {
            logoURL = logo
            logoView.image = TokenLogo.placeholder(s)
            TokenLogo.load(logo) { [weak self] image in
                guard let self, self.logoURL == logo, let image else { return }
                self.logoView.image = image
            }
        }
        setNeedsLayout()
    }

    var fitWidth: CGFloat {
        let tw = (symbol.text as NSString?)?.size(withAttributes: [.font: symbol.font!]).width ?? 0
        return min(150, 6 + 22 + 7 + ceil(tw) + (chevron.isHidden ? 12 : 7 + 11 + 11))
    }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let d: CGFloat = compact ? 20 : 22
        layer.cornerRadius = h / 2
        logoView.layer.cornerRadius = d / 2
        logoView.frame = CGRect(x: 6, y: (h - d) / 2, width: d, height: d)
        let chevronW: CGFloat = chevron.isHidden ? 0 : 11
        let textX = logoView.frame.maxX + 7
        symbol.frame = CGRect(x: textX, y: 0, width: max(0, bounds.width - textX - (chevron.isHidden ? 8 : chevronW + 17)), height: h)
        chevron.frame = CGRect(x: bounds.width - 11 - chevronW, y: (h - 11) / 2, width: chevronW, height: 11)
    }
}

/// A value on an order: name left, value right, tap to change.
private final class FieldRow: UIControl {
    private let name = UILabel()
    private let value = UILabel()
    private let line = UIView()
    var onTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        name.font = .systemFont(ofSize: 15)
        name.textColor = Glass.textSecondary
        value.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        value.textColor = Glass.textPrimary
        value.textAlignment = .right
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7
        line.backgroundColor = Glass.strokeSeparator
        for v in [name, value, line] { v.isUserInteractionEnabled = false; addSubview(v) }
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(label: String, value v: String, tappable: Bool, separator: Bool) {
        name.text = label
        value.text = v
        isAccessibilityElement = true
        accessibilityLabel = "\(label) \(v)"
        accessibilityTraits = tappable ? .button : .staticText
        value.textColor = tappable ? Glass.textPrimary : Glass.textSecondary
        isUserInteractionEnabled = tappable
        line.isHidden = !separator
    }

    override var isHighlighted: Bool { didSet { value.alpha = isHighlighted ? 0.5 : 1 } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        name.frame = CGRect(x: 14, y: 0, width: w * 0.45, height: h)
        value.frame = CGRect(x: w * 0.4, y: 0, width: w * 0.6 - 14, height: h)
        line.frame = CGRect(x: 14, y: 0, width: w - 28, height: Glass.hairlineWidth)
    }
}

/// A picker row: a token (logo, symbol, name, balance) or a chain.
private final class TokenRow: UIControl {
    static let height: CGFloat = 54
    static let chainHeight: CGFloat = 48
    private let logoView = UIImageView()
    private let symbol = UILabel()
    private let name = UILabel()
    private let right = UILabel()
    private let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration:
        UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
    private var logoURL: String?
    private var chainRow = false
    var onTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        logoView.clipsToBounds = true
        logoView.contentMode = .scaleAspectFill
        symbol.font = .systemFont(ofSize: 16, weight: .semibold)
        symbol.textColor = Glass.textPrimary
        name.font = .systemFont(ofSize: 12.5)
        name.textColor = Glass.textSecondary
        right.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        right.textColor = Glass.textPrimary
        right.textAlignment = .right
        check.tintColor = Glass.imBlue
        for v in [logoView, symbol, name, right, check] { v.isUserInteractionEnabled = false; addSubview(v) }
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ t: TokenPick, logo: String?, held: Double?, selected: Bool) {
        chainRow = false
        isAccessibilityElement = true
        accessibilityLabel = "\(t.symbol) \(t.name)"
        accessibilityTraits = .button
        symbol.text = t.symbol
        name.text = t.name
        right.text = held.flatMap { $0 > 0 ? PaySurface.compact($0) : nil } ?? ""
        check.isHidden = !selected || !(right.text ?? "").isEmpty
        logoURL = logo
        logoView.image = TokenLogo.placeholder(t.symbol)
        TokenLogo.load(logo) { [weak self] image in
            guard let self, self.logoURL == logo, let image else { return }
            self.logoView.image = image
        }
        setNeedsLayout()
    }

    func setChain(_ label: String, chain: String, selected: Bool) {
        chainRow = true
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = selected ? [.button, .selected] : .button
        symbol.text = label
        name.text = nil
        right.text = nil
        check.isHidden = !selected
        logoView.image = ChainLogo.image(chain, side: 28) ?? TokenLogo.placeholder(label)
        setNeedsLayout()
    }

    override var isHighlighted: Bool { didSet { backgroundColor = isHighlighted ? Glass.surfaceCard : Glass.touchableGrid } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let d: CGFloat = chainRow ? 28 : 32
        // A chain's mark keeps its own shape (Base's square, Arbitrum's hexagon).
        logoView.layer.cornerRadius = chainRow ? 0 : d / 2
        logoView.frame = CGRect(x: 16, y: (h - d) / 2, width: d, height: d)
        let tx = logoView.frame.maxX + 12
        check.frame = CGRect(x: w - 32, y: (h - 16) / 2, width: 16, height: 16)
        right.frame = CGRect(x: w * 0.55, y: 0, width: w * 0.45 - 16, height: h)
        if chainRow || (name.text ?? "").isEmpty {
            symbol.frame = CGRect(x: tx, y: 0, width: w - tx - 50, height: h)
        } else {
            symbol.frame = CGRect(x: tx, y: h / 2 - 19, width: w * 0.55 - tx, height: 20)
            name.frame = CGRect(x: tx, y: h / 2 + 1, width: w * 0.55 - tx, height: 17)
        }
    }
}

/// Token logos from the list's URLs, kept small and cached for the
/// keyboard's life; a lettered disc until (or unless) one arrives.
enum TokenLogo {
    private static let cache = NSCache<NSString, UIImage>()
    private static var placeholders: [String: UIImage] = [:]
    private static var waiting: [String: [(UIImage?) -> Void]] = [:]

    static func load(_ url: String?, done: @escaping (UIImage?) -> Void) {
        guard let url, url.hasPrefix("https://"), let u = URL(string: url) else { done(nil); return }
        if let hit = cache.object(forKey: url as NSString) { done(hit); return }
        if waiting[url] != nil { waiting[url]!.append(done); return }
        waiting[url] = [done]
        var req = URLRequest(url: u)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }.map(shrink)
            DispatchQueue.main.async {
                if let image { cache.setObject(image, forKey: url as NSString) }
                let calls = waiting.removeValue(forKey: url) ?? []
                calls.forEach { $0(image) }
            }
        }.resume()
    }

    /// 64 px is plenty for a 32 pt disc; big list images would cost memory.
    private static func shrink(_ image: UIImage) -> UIImage {
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// The first letter on a colour picked from the name, the same each time.
    static func placeholder(_ symbol: String) -> UIImage {
        if let hit = placeholders[symbol] { return hit }
        let palette: [UIColor] = [
            UIColor(red: 0.38, green: 0.49, blue: 0.98, alpha: 1), UIColor(red: 0.16, green: 0.62, blue: 0.56, alpha: 1),
            UIColor(red: 0.93, green: 0.45, blue: 0.20, alpha: 1), UIColor(red: 0.62, green: 0.36, blue: 0.86, alpha: 1),
            UIColor(red: 0.85, green: 0.30, blue: 0.47, alpha: 1), UIColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1),
        ]
        let sum = symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let color = palette[sum % palette.count]
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            let letter = String(symbol.prefix(1)).uppercased() as NSString
            let font = UIFont.systemFont(ofSize: 30, weight: .bold)
            let size = letter.size(withAttributes: [.font: font])
            letter.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2),
                        withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
        placeholders[symbol] = img
        return img
    }
}
