import UIKit

protocol TradeSurfaceDelegate: AnyObject {
    /// The trade as read and quoted, handed to the app, which signs it with
    /// the chosen wallet and says how it went when the keyboard is next up.
    func tradeHandOff(query: [String: String])
    /// No Glyf wallet on this phone yet: the app makes one.
    func tradeSetUpWallet()
    func tradeToast(_ text: String)
}

/// A trade said in words, shown before it's signed: what leaves, what comes
/// back or when it fires, where, and one blue button. The Buy panel's two
/// cards (PaySurface), so a swap on Base looks like a buy on Solana. The
/// quote here is Uniswap's (or the price an order waits on); the app asks
/// again at signing, so nothing on this panel is ever what's signed.
final class TradeSurface: UIView {

    weak var delegate: TradeSurfaceDelegate?

    let intent: TradeIntent
    private let wallet = SettingsStore.current.evmAddress
    /// The wallet that signs, as the app names it. Solana's is Phantom
    /// (its deeplinks sign only Solana; lib/wallet/flash_solana.dart).
    private var walletName: String {
        if intent.chainName == "solana" { return "Phantom" }
        switch SettingsStore.current.evmSigner {
        case "metamask": return "MetaMask"
        case "phantom": return "Phantom"
        default: return "Glyf wallet"
        }
    }

    // Top card: what leaves (or what's asked for).
    private let topCard = UIView()
    private let topKey = UILabel()
    private let topHeld = UILabel()
    private let topAmount = UILabel()
    private let topUSD = UILabel()
    private let topToken = UILabel()
    // Bottom card: what comes back, or when the order fires.
    private let bottomCard = UIView()
    private let bottomKey = UILabel()
    private let bottomValue = UILabel()
    private let bottomSub = UILabel()
    private let bottomToken = UILabel()
    private let metaLabel = UILabel()
    private let goButton = UIButton(type: .system)

    /// The live numbers, once the server answers.
    private var quoteOut: Double?
    private var quoteInUSD: Double?
    private var quoteOutUSD: Double?
    private var marketPrice: Double?
    private var held: Double?
    private var resolved: String?
    private var resolveFailed = false
    private var asking = true

    private static let pillFill = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.06) }

    init(intent: TradeIntent) {
        self.intent = intent
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid
        build()
        render()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The strip's header while the panel is up.
    var headerTitle: String {
        switch intent.kind {
        case .swap: return intent.amountIsUSD || intent.buyAmount != nil ? "Buy \(intent.buy)" : "Swap"
        case .limit: return "Limit order"
        case .stop: return "Stop buy"
        case .stopLoss: return "Stop-loss"
        case .takeProfit: return "Take profit"
        case .bracket: return "Bracket"
        case .trailingStop: return "Trailing stop"
        case .twap: return "TWAP"
        case .bridge: return "Move"
        case .send: return "Send"
        case .request: return "Request USDT"
        }
    }

    // MARK: build

    private func build() {
        for card in [topCard, bottomCard] {
            card.backgroundColor = Glass.surfaceCard
            card.layer.cornerRadius = 14
            card.layer.cornerCurve = .continuous
            addSubview(card)
        }
        topCard.accessibilityIdentifier = "trade:top"
        bottomCard.accessibilityIdentifier = "trade:bottom"
        for label in [topKey, bottomKey] {
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = Glass.textSecondary
        }
        topCard.addSubview(topKey)
        bottomCard.addSubview(bottomKey)
        topHeld.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        topHeld.textColor = Glass.textSecondary
        topHeld.textAlignment = .right
        topCard.addSubview(topHeld)
        for label in [topAmount, bottomValue] {
            label.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
            label.textColor = Glass.textPrimary
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
        }
        topAmount.accessibilityIdentifier = "trade:amount"
        bottomValue.accessibilityIdentifier = "trade:value"
        topCard.addSubview(topAmount)
        bottomCard.addSubview(bottomValue)
        for label in [topUSD, bottomSub] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = Glass.textSecondary
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
        }
        bottomSub.accessibilityIdentifier = "trade:sub"
        topCard.addSubview(topUSD)
        bottomCard.addSubview(bottomSub)
        for pill in [topToken, bottomToken] {
            pill.font = .systemFont(ofSize: 14, weight: .semibold)
            pill.textColor = Glass.textPrimary
            pill.backgroundColor = Self.pillFill
            pill.textAlignment = .center
            pill.layer.cornerRadius = 15
            pill.layer.cornerCurve = .continuous
            pill.clipsToBounds = true
        }
        topCard.addSubview(topToken)
        bottomCard.addSubview(bottomToken)

        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = Glass.textSecondary
        metaLabel.textAlignment = .center
        metaLabel.accessibilityIdentifier = "trade:meta"
        addSubview(metaLabel)

        goButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        goButton.setTitleColor(.white, for: .normal)
        goButton.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .disabled)
        goButton.backgroundColor = Glass.imBlue
        goButton.layer.cornerRadius = 12
        goButton.layer.cornerCurve = .continuous
        goButton.accessibilityIdentifier = "trade:go"
        goButton.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
        addSubview(goButton)
    }

    // MARK: live numbers

    private func load() {
        let i = intent
        if let wallet, i.chainName != "solana", i.kind != .request {
            BackendClient.shared.evmJSON(path: "/evm/balances?chain=\(i.chainName)&address=\(wallet)") { [weak self] obj in
                guard let self else { return }
                self.held = Self.balance(of: i.sell, in: obj)
                self.render()
            }
        }
        switch i.kind {
        case .swap:
            quote(sell: i.sell, buy: i.buy, amount: i.amount, usd: i.amountIsUSD, buyAmount: i.buyAmount)
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
            // An order waits on the price of what it buys or sells.
            price(of: i.sell == "USDC" || i.sell == "USDT" ? i.buy : i.sell)
        }
    }

    private func quote(sell: String, buy: String, amount: String?, usd: Bool, buyAmount: String?) {
        // "buy 0.1 eth": what 0.1 ETH costs, asked the other way round.
        let reversed = buyAmount != nil
        let body: [String: Any] = ["chain": intent.chainName,
                                   "sell": reversed ? buy : sell, "buy": reversed ? sell : buy,
                                   "amount": buyAmount ?? amount ?? "1"]
        BackendClient.shared.evmJSON(path: "/uniswap/quote", body: body) { [weak self] obj in
            guard let self else { return }
            self.asking = false
            if let obj, obj["amountOut"] != nil {
                self.quoteOut = Self.number(obj["amountOut"])
                let inUSD = Self.number(obj["sellUsd"]) ?? Self.number((obj["sell"] as? [String: Any])?["usd"])
                let outUSD = Self.number(obj["buyUsd"]) ?? Self.number((obj["buy"] as? [String: Any])?["usd"])
                self.quoteInUSD = reversed ? outUSD : inUSD
                self.quoteOutUSD = reversed ? inUSD : outUSD
                // "All": the app knows how much once it reads the balance.
                if amount == nil, !reversed, !usd { self.quoteOut = nil; self.quoteInUSD = nil }
            }
            self.render()
        }
    }

    private func price(of symbol: String) {
        if ["USDC", "USDT", "DAI"].contains(symbol) { marketPrice = 1; asking = false; render(); return }
        BackendClient.shared.evmJSON(path: "/uniswap/quote",
                                     body: ["chain": intent.chainName == "solana" ? "base" : intent.chainName,
                                            "sell": symbol == "SOL" ? "ETH" : symbol, "buy": "USDC",
                                            "amount": "1"]) { [weak self] obj in
            guard let self else { return }
            self.asking = false
            if symbol != "SOL" { self.marketPrice = Self.number(obj?["amountOut"]) }
            self.render()
        }
    }

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
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

    // MARK: render

    static func amount(_ v: Double, _ symbol: String) -> String {
        let digits = v >= 1000 ? 2 : v >= 1 ? 4 : 6
        var s = String(format: "%.\(digits)f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private func render() {
        let i = intent
        topToken.text = i.kind == .request ? "USDT" : (i.amountIsUSD ? i.sell : i.sell)
        topHeld.text = held.map { "\(PaySurface.compact($0)) \(i.sell)" } ?? ""
        switch i.kind {
        case .swap:
            topKey.text = "You pay"
            bottomKey.text = "You get"
            bottomToken.text = i.buy
            if let buyAmount = i.buyAmount {
                topAmount.text = quoteOut == nil ? "…" : "≈ " + Self.amount(quoteOut!, i.sell)
                bottomValue.text = buyAmount
            } else {
                let some = held.map { $0 > 0 } ?? true
                topAmount.text = i.amount ?? (some ? (held.map { Self.amount($0, i.sell) } ?? "All") : "All")
                bottomValue.text = quoteOut.map { Self.amount($0, i.buy) } ?? (asking ? "…" : "—")
            }
            topUSD.text = i.amountIsUSD ? "$\(i.amount ?? "")" : (quoteInUSD.map(PaySurface.dollars) ?? "")
            if i.amount == nil, i.buyAmount == nil, !i.amountIsUSD, held == 0 { topUSD.text = "No \(i.sell) on \(i.chainLabel) yet" }
            bottomSub.text = quoteOutUSD.map(PaySurface.dollars) ?? (asking ? "Asking Uniswap" : "")
        case .limit, .stop, .stopLoss, .takeProfit, .bracket, .trailingStop:
            let selling = i.kind == .stopLoss || i.kind == .takeProfit || i.kind == .trailingStop
                || (i.kind == .bracket && i.buyAmount == nil && !i.amountIsUSD)
                || (i.kind == .limit && i.sell != "USDC" && i.sell != "USDT")
            topKey.text = selling ? "Sell" : "Buy"
            let asset = selling ? i.sell : i.buy
            topToken.text = asset
            if selling {
                // "All" of nothing is said as nothing held, not as 0.
                let some = held.map { $0 > 0 } ?? true
                topAmount.text = i.amount ?? (some ? (held.map { Self.amount($0, asset) } ?? "All") : "All")
                topUSD.text = i.amount != nil ? "" : (some ? "Everything held" : "No \(asset) on \(i.chainLabel) yet")
            } else if i.amountIsUSD {
                topAmount.text = "$\(i.amount ?? "")"
                topUSD.text = "of \(asset), paid in \(i.sell)"
            } else {
                topAmount.text = i.buyAmount ?? i.amount ?? "—"
                topUSD.text = "paid in \(i.sell)"
            }
            bottomKey.text = "When"
            bottomToken.text = asset
            switch i.kind {
            case .stopLoss: bottomValue.text = "≤ \(TradeIntent.dollars(i.price))"
            case .takeProfit: bottomValue.text = "≥ \(TradeIntent.dollars(i.price))"
            case .stop: bottomValue.text = "≥ \(TradeIntent.dollars(i.price))"
            case .limit: bottomValue.text = (selling ? "≥ " : "≤ ") + TradeIntent.dollars(i.price)
            case .bracket:
                bottomKey.text = "Take profit · Stop"
                bottomValue.text = "\(TradeIntent.dollars(i.price)) · \(TradeIntent.dollars(i.stopPrice))"
            default:
                bottomKey.text = "Trail"
                bottomValue.text = "\(i.trailPercent ?? "")% below the high"
            }
            bottomSub.text = marketPrice.map { "Now \(PaySurface.dollars($0))" } ?? (asking ? "Asking the price" : "")
        case .twap:
            topKey.text = "Spend"
            topAmount.text = "$\(i.amount ?? "")"
            topToken.text = i.sell
            topUSD.text = "on \(i.buy), a slice at a time"
            bottomKey.text = "Over"
            bottomValue.text = TradeIntent.span(i.durationSeconds).replacingOccurrences(of: "over ", with: "").capitalizedFirst
            bottomToken.text = i.buy
            bottomSub.text = marketPrice.map { "\(i.buy) now \(PaySurface.dollars($0))" } ?? ""
        case .bridge:
            topKey.text = "Move"
            topAmount.text = i.amount ?? ""
            topUSD.text = "from \(i.chainLabel)"
            bottomKey.text = "To"
            bottomValue.text = TradeIntent.chainLabels[i.toChain ?? ""] ?? ""
            bottomToken.text = i.buy
            bottomSub.text = "Same token, one signature"
        case .send:
            topKey.text = "Send"
            topAmount.text = i.amount ?? ""
            topUSD.text = marketPrice.flatMap { p in Double(i.amount ?? "").map { PaySurface.dollars($0 * p) } } ?? ""
            bottomKey.text = "To"
            bottomValue.text = i.to ?? ""
            bottomToken.text = i.chainLabel
            bottomSub.text = resolved.map(Smart.shortAddress)
                ?? (resolveFailed ? "No address for this name" : (asking ? "Looking up the name" : ""))
        case .request:
            topKey.text = "Ask for"
            topAmount.text = i.amount ?? ""
            topUSD.text = "Test USDT on Whitechain"
            bottomKey.text = "Paid to"
            bottomValue.text = wallet.map(Smart.shortAddress) ?? "Your \(walletName)"
            bottomToken.text = "Whitechain"
            bottomSub.text = "A link goes in the chat; they pay it"
        }
        // "Solana · Flash · Phantom": who signs, when it isn't the EVM wallet.
        metaLabel.text = i.chainName == "solana" && i.kind != .send ? "\(i.detail) · \(walletName)" : i.detail
        renderGo()
        setNeedsLayout()
    }

    /// What the wallet holds is known and falls short of what's spent
    /// (the Buy panel's "Not enough SOL"): the button says so.
    private var short: Bool {
        guard let held, intent.kind != .request, intent.chainName != "solana" else { return false }
        if intent.amount == nil, intent.buyAmount == nil { return held <= 0 && Self.sells(intent) }
        let spend = intent.buyAmount != nil ? quoteOut : Double(intent.amount ?? "")
        guard let spend, Self.sells(intent) || intent.amountIsUSD || intent.buyAmount != nil else { return false }
        return spend > held
    }

    /// The panel spends what `sell` names (a swap, a send, an order that sells).
    private static func sells(_ i: TradeIntent) -> Bool {
        switch i.kind {
        case .swap, .send, .bridge, .stopLoss, .takeProfit, .trailingStop: return true
        case .bracket: return i.buyAmount == nil && !i.amountIsUSD
        case .limit: return i.sell != "USDC" && i.sell != "USDT"
        default: return false
        }
    }

    /// Solana sends are Phantom's, not the Glyf wallet's.
    private var needsGlyfWallet: Bool { wallet == nil && intent.chainName != "solana" }

    private var goTitle: String {
        if needsGlyfWallet { return "Set up your Glyf wallet" }
        if short { return "Not enough \(intent.sell)" }
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
        case .bridge: return "Move to \(TradeIntent.chainLabels[intent.toChain ?? ""] ?? "")"
        case .send: return resolveFailed ? "Name not found" : "Send \(intent.amount ?? "") \(intent.sell)"
        case .request: return "Create request"
        }
    }

    private func renderGo() {
        goButton.setTitle(goTitle, for: .normal)
        let blocked = !needsGlyfWallet && ((intent.kind == .send && resolveFailed) || short)
        goButton.isEnabled = !blocked
        goButton.alpha = blocked ? 0.5 : 1
    }

    private func go() {
        guard !needsGlyfWallet else { delegate?.tradeSetUpWallet(); return }
        var q = intent.query
        if let resolved { q["address"] = resolved }
        delegate?.tradeHandOff(query: q)
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // The Buy panel's numbers (PaySurface.layoutBuy), so the two read as
        // one design: 10pt margins, a 42pt button, the meta line under it
        // when there's room, the two cards sharing what's left.
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
        let topH = min(84, max(66, (room * 0.53).rounded()))
        let bottomH = max(56, room - topH)
        topCard.frame = CGRect(x: x, y: top, width: cw, height: topH)
        bottomCard.frame = CGRect(x: x, y: topCard.frame.maxY + gap, width: cw, height: bottomH)
        layoutCard(topCard, key: topKey, right: topHeld, value: topAmount, sub: topUSD, pill: topToken, pillH: 32)
        layoutCard(bottomCard, key: bottomKey, right: nil, value: bottomValue, sub: bottomSub, pill: bottomToken, pillH: 28)
    }

    private func layoutCard(_ card: UIView, key: UILabel, right: UILabel?, value: UILabel, sub: UILabel,
                            pill: UILabel, pillH: CGFloat) {
        let cw = card.bounds.width
        let h = card.bounds.height
        key.frame = CGRect(x: 12, y: 8, width: cw * 0.6, height: 16)
        right?.frame = CGRect(x: cw * 0.4, y: 7, width: cw * 0.6 - 10, height: 18)
        let textW = (pill.text as NSString?)?.size(withAttributes: [.font: pill.font!]).width ?? 0
        let pw = min(140, max(56, textW + 24))
        pill.frame = CGRect(x: cw - 10 - pw, y: 8 + 16 + (h - 24 - pillH) / 2, width: pw, height: pillH)
        let valueH: CGFloat = pillH == 32 ? 30 : 28
        value.frame = CGRect(x: 12, y: pillH == 32 ? 26 : 24, width: pill.frame.minX - 20, height: valueH)
        sub.frame = CGRect(x: 12, y: value.frame.maxY, width: cw - 24, height: 15)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
