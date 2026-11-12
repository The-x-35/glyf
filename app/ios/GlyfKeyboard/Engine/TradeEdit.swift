import Foundation

/// What the trade panel lets a person change, and how each change lands on
/// the trade (TradeSurface). Pure, so the mapping is tested
/// (RunnerTests/TradeEditTests): the panel only shows and asks.
enum TradeField: String, CaseIterable {
    /// What's spent or bought, in the unit `amountUnit` says.
    case amount
    /// A limit, a trigger, or a bracket's take-profit, in dollars.
    case price
    /// A bracket's stop-loss, in dollars.
    case stopPrice
    /// A trailing stop's distance, in percent.
    case trail
    /// A TWAP's length, in days (0.5 = 12 hours).
    case duration

    var isNumber: Bool { true }
}

/// A token the picker offers: from GET /uniswap/tokens, or the built-in
/// few when that can't be had.
struct TokenPick: Equatable {
    var symbol: String
    var name: String
    var address: String?
    var decimals: Int?
    var logo: String?
    var native = false

    init(symbol: String, name: String, address: String? = nil, decimals: Int? = nil, logo: String? = nil,
         native: Bool = false) {
        self.symbol = symbol
        self.name = name
        self.address = address
        self.decimals = decimals
        self.logo = logo
        self.native = native
    }

    init?(json: [String: Any]) {
        guard let symbol = json["symbol"] as? String, !symbol.isEmpty else { return nil }
        self.init(symbol: symbol, name: json["name"] as? String ?? symbol, address: json["address"] as? String,
                  decimals: json["decimals"] as? Int, logo: json["logoURI"] as? String,
                  native: json["native"] as? Bool ?? false)
    }
}

enum TradeEdit {

    enum Side { case sell, buy }

    /// The unit the amount is typed in.
    enum AmountUnit: Equatable {
        /// Dollars of what's bought ("$20 of ETH").
        case dollars
        /// Whole tokens of what's spent.
        case spend(String)
        /// Whole tokens of what comes back ("buy 0.1 ETH").
        case receive(String)
    }

    static let stables: Set<String> = ["USDC", "USDT", "DAI"]

    // MARK: what's on the panel

    /// A Flash order on what's held sells it; one paid in dollars buys.
    static func sells(_ i: TradeIntent) -> Bool {
        switch i.kind {
        case .swap, .bridge, .send, .stopLoss, .takeProfit, .trailingStop: return true
        case .bracket: return i.buyAmount == nil && !i.amountIsUSD
        case .limit: return !stables.contains(i.sell)
        default: return false
        }
    }

    /// The asset an order is about (the side that isn't dollars).
    static func asset(_ i: TradeIntent) -> String {
        if i.kind == .swap || i.kind == .bridge { return i.sell }
        // What's sent: the coin the recipient gets (a NEAR Intents send
        // may pay for it in another).
        if i.kind == .send { return i.buy }
        return sells(i) ? i.sell : i.buy
    }

    static func amountUnit(_ i: TradeIntent) -> AmountUnit {
        if i.amountIsUSD { return .dollars }
        if i.buyAmount != nil { return .receive(i.buy) }
        if i.kind == .twap { return .dollars }
        if !sells(i), [.limit, .stop, .bracket].contains(i.kind) { return .dollars }
        // A send's amount is what arrives.
        if i.kind == .send { return .spend(i.buy) }
        return .spend(i.sell)
    }

    /// The fields the panel shows, top to bottom after the amount.
    static func fields(_ i: TradeIntent) -> [TradeField] {
        switch i.kind {
        case .limit, .stop, .stopLoss, .takeProfit: return [.amount, .price]
        case .bracket: return [.amount, .price, .stopPrice]
        case .trailingStop: return [.amount, .trail]
        case .twap: return [.amount, .duration]
        case .swap, .bridge, .send: return [.amount]
        }
    }

    /// The row's name for a field.
    static func label(_ field: TradeField, _ i: TradeIntent) -> String {
        switch field {
        case .amount:
            switch amountUnit(i) {
            case .dollars: return "Amount in $"
            case .spend(let s): return "Amount in \(s)"
            case .receive(let s): return "\(s) to get"
            }
        case .price:
            switch i.kind {
            case .limit: return sells(i) ? "Sell at" : "Buy at"
            case .stop: return "Buy above"
            case .stopLoss: return "Sell below"
            case .takeProfit: return "Sell above"
            case .bracket: return "Take profit"
            default: return "Price"
            }
        case .stopPrice: return "Stop-loss"
        case .trail: return "Trail"
        case .duration: return "Over"
        }
    }

    /// The text the editor opens with.
    static func value(_ field: TradeField, _ i: TradeIntent) -> String {
        switch field {
        case .amount: return i.buyAmount ?? i.amount ?? ""
        case .price: return i.price ?? ""
        case .stopPrice: return i.stopPrice ?? ""
        case .trail: return i.trailPercent ?? ""
        case .duration:
            guard let s = i.durationSeconds else { return "" }
            return TradeIntent.trimmed((Double(s) / 86_400 * 1000).rounded() / 1000)
        }
    }

    /// How a field reads on the panel.
    static func shown(_ field: TradeField, _ i: TradeIntent) -> String {
        switch field {
        case .amount:
            let v = value(.amount, i)
            if v.isEmpty { return sells(i) ? "All" : "0" }
            return amountUnit(i) == .dollars ? "$\(v)" : v
        case .price: return i.price.map { TradeIntent.dollars($0) } ?? "—"
        case .stopPrice: return i.stopPrice.map { TradeIntent.dollars($0) } ?? "—"
        case .trail: return i.trailPercent.map { "\($0)%" } ?? "—"
        case .duration: return duration(i.durationSeconds)
        }
    }

    /// "1 day", "12 hours", "2 weeks".
    static func duration(_ seconds: Int?) -> String {
        guard let s = seconds, s > 0 else { return "—" }
        if s % (7 * 86_400) == 0 { let w = s / (7 * 86_400); return w == 1 ? "1 week" : "\(w) weeks" }
        if s % 86_400 == 0 { let d = s / 86_400; return d == 1 ? "1 day" : "\(d) days" }
        let h = max(1, Int((Double(s) / 3600).rounded())); return h == 1 ? "1 hour" : "\(h) hours"
    }

    // MARK: changes

    /// Digits and one point, as an amount field takes them ("1,5" → "1.5").
    static func cleanNumber(_ text: String) -> String {
        var out = ""
        var point = false
        for ch in text.replacingOccurrences(of: ",", with: ".") {
            if ch.isASCII, ch.isNumber { out.append(ch) } else if ch == ".", !point { point = true; out.append(ch) }
        }
        if out.hasPrefix(".") { out = "0" + out }
        // "007" is 7; "0.5" stays.
        while out.count > 1, out.hasPrefix("0"), !out.hasPrefix("0.") { out.removeFirst() }
        return String(out.prefix(18))
    }

    /// The typed text set on the trade. An empty amount on a sell means
    /// everything held; an empty price stays unset.
    static func apply(_ field: TradeField, _ text: String, to intent: TradeIntent) -> TradeIntent {
        var i = intent
        let clean = cleanNumber(text)
        let number = Double(clean).flatMap { $0 > 0 ? clean : nil }
        switch field {
        case .amount:
            switch amountUnit(i) {
            case .receive:
                i.buyAmount = number
                i.amount = nil
            case .dollars, .spend:
                i.amount = number
            }
        case .price:
            i.price = number
            i.pricePercent = nil
        case .stopPrice:
            i.stopPrice = number
            i.stopPercent = nil
        case .trail:
            i.trailPercent = number
        case .duration:
            i.durationSeconds = number.flatMap(Double.init).map { max(3600, Int(($0 * 86_400).rounded())) }
        }
        return i
    }

    /// Why the trade can't go as set, in one short line; nil when it can.
    static func problem(_ i: TradeIntent) -> String? {
        if i.kind == .swap {
            if (i.buyChain ?? i.chainName) == i.chainName, i.sell == i.buy,
               (i.sellAddress ?? i.sell) == (i.buyAddress ?? i.buy) { return "Pick two different tokens" }
            return nil
        }
        let positive = { (s: String?) in s.flatMap(Double.init).map { $0 > 0 } ?? false }
        switch i.kind {
        case .limit, .stop, .stopLoss, .takeProfit:
            if !positive(i.price) && i.pricePercent == nil { return "Set a price" }
        case .bracket:
            if (!positive(i.price) && i.pricePercent == nil) || (!positive(i.stopPrice) && i.stopPercent == nil) {
                return "Set both prices"
            }
            if let tp = i.price.flatMap(Double.init), let sl = i.stopPrice.flatMap(Double.init), tp <= sl {
                return "Take profit must be above the stop-loss"
            }
        case .trailingStop:
            guard let p = i.trailPercent.flatMap(Double.init), p >= 0.5, p <= 50 else { return "Trail between 0.5% and 50%" }
        case .twap:
            if !positive(i.amount) { return "Enter an amount" }
            if (i.durationSeconds ?? 0) < 3600 { return "At least an hour" }
        case .bridge:
            if !positive(i.amount) { return "Enter an amount" }
            if i.toChain == nil || i.toChain == i.chainName { return "Pick another chain" }
        case .send:
            if !positive(i.amount) { return "Enter an amount" }
        default:
            break
        }
        return nil
    }

    /// A token picked for `side`. A Flash order changes its asset (both
    /// sides of a bridge), keeping the dollar side.
    static func pick(_ token: TokenPick, side: Side, in intent: TradeIntent) -> TradeIntent {
        var i = intent
        let symbol = token.symbol.uppercased() == "CBBTC" ? "CBBTC" : token.symbol
        let address = token.native ? nil : token.address
        if i.kind == .bridge || i.kind == .send {
            i.sell = symbol; i.buy = symbol
            i.sellAddress = address; i.buyAddress = address
            return i
        }
        if i.kind != .swap {
            // The asset side changes; a dollar coin picked as the asset
            // flips nothing, it just can't be the asset.
            if sells(i) {
                i.sell = symbol; i.sellAddress = address
                if stables.contains(symbol), stables.contains(i.buy) { i.buy = TradeIntent.stableFor(symbol); i.buyAddress = nil }
            } else {
                i.buy = symbol; i.buyAddress = address
                if stables.contains(symbol), stables.contains(i.sell) { i.sell = TradeIntent.stableFor(symbol); i.sellAddress = nil }
            }
            return i
        }
        switch side {
        case .sell:
            // Picking what's on the other side swaps the two, as Uniswap's app does.
            if symbol == i.buy, (i.buyChain ?? i.chainName) == i.chainName { return flip(i) }
            i.sell = symbol; i.sellAddress = address
        case .buy:
            if symbol == i.sell, (i.buyChain ?? i.chainName) == i.chainName { return flip(i) }
            i.buy = symbol; i.buyAddress = address
        }
        // A picked token is spent or bought by count, not dollars.
        if i.amountIsUSD { i.amountIsUSD = false }
        return i
    }

    /// An order whose asset changed (another token, or a chain that trades
    /// another coin): its prices were the old asset's, so they go back to
    /// the starters' distances from the new market (SponsorMenu.starter),
    /// filled once the panel has the new price.
    static func repriced(_ intent: TradeIntent, was: TradeIntent) -> TradeIntent {
        guard intent.kind != .swap, asset(intent) != asset(was) else { return intent }
        var i = intent
        switch i.kind {
        case .limit: i.price = nil; i.pricePercent = sells(i) ? 5 : -5
        case .stop: i.price = nil; i.pricePercent = 5
        case .stopLoss: i.price = nil; i.pricePercent = -10
        case .takeProfit: i.price = nil; i.pricePercent = 10
        case .bracket:
            i.price = nil; i.pricePercent = 10
            i.stopPrice = nil; i.stopPercent = -10
        default: break
        }
        // An amount of the old coin isn't an amount of the new one.
        if sells(i), i.kind != .bridge, i.kind != .send { i.amount = nil }
        return i
    }

    /// You pay and You get trade places; the amount stays what's typed.
    static func flip(_ intent: TradeIntent) -> TradeIntent {
        var i = intent
        swap(&i.sell, &i.buy)
        swap(&i.sellAddress, &i.buyAddress)
        if let to = i.buyChain, to != i.chainName {
            let from = i.chainName
            i.chain = to
            i.buyChain = from
        }
        if let buyAmount = i.buyAmount { i.amount = buyAmount; i.buyAmount = nil }
        i.amountIsUSD = false
        return i
    }

    /// The chains a trade of this kind can be on.
    static func chains(for i: TradeIntent) -> [String] {
        switch i.kind {
        case .swap: return i.isNear ? nearChains : SponsorMenu.swapChains
        // NEAR Intents' send pays from any chain a wallet here signs on.
        case .send where i.isNear: return nearPayChains
        // A send stays where its name points: Solana for a .sol name or
        // SOL, any of MetaMask's chains otherwise.
        case .send: return i.chainName == "solana" ? ["solana"] : SponsorMenu.swapChains
        default: return flashChains
        }
    }

    /// The chains a NEAR Intents swap picks from: where MetaMask and
    /// Phantom sign, then the chains of their own (paid from any wallet).
    static let nearChains = ["base", "ethereum", "arbitrum", "optimism", "polygon", "bsc", "avalanche", "solana",
                             "near", "bitcoin", "zcash", "ton", "tron", "xrp", "dogecoin", "litecoin", "sui"]
    /// Where a NEAR Intents send is paid from: chains Glyf can sign on.
    static let nearPayChains = ["base", "ethereum", "arbitrum", "optimism", "polygon", "solana"]

    /// Flash's chains that this server also has an EVM node for, Solana too.
    static let flashChains = ["base", "solana", "ethereum", "arbitrum", "optimism"]

    /// The chain picked for `side` (a swap's You get side makes it
    /// cross-chain; a bridge's buy side is where it lands). Tokens that
    /// don't exist on the new chain fall back to its gas coin.
    static func pickChain(_ chain: String, side: Side, in intent: TradeIntent) -> TradeIntent {
        if intent.isNear { return pickNearChain(chain, side: side, in: intent) }
        var i = intent
        if i.kind == .bridge, side == .buy {
            i.toChain = chain == i.chainName ? nil : chain
            return i
        }
        if i.kind == .swap, side == .buy {
            i.buyChain = chain == i.chainName ? nil : chain
            i.buyAddress = nil
            return i
        }
        let was = i.chainName
        i.chain = chain
        if i.kind == .swap, i.buyChain == chain { i.buyChain = nil }
        if i.kind == .bridge, i.toChain == chain { i.toChain = SponsorMenu.bridgeTarget(from: chain) }
        // Addresses belong to the chain they were picked on.
        i.sellAddress = nil
        if i.kind != .swap || i.buyChain == nil { i.buyAddress = nil }
        let toSolana = chain == "solana", fromSolana = was == "solana"
        if toSolana != fromSolana {
            let gas = toSolana ? "SOL" : "ETH"
            let allowed: Set<String> = toSolana ? ["SOL", "USDC", "USDT"] : []
            if toSolana {
                if !allowed.contains(i.sell) { i.sell = gas }
                if !allowed.contains(i.buy) { i.buy = gas }
            } else {
                if i.sell == "SOL" { i.sell = gas }
                if i.buy == "SOL" { i.buy = gas }
            }
            if i.sell == i.buy { i.buy = TradeIntent.stableFor(i.sell) }
            if i.kind == .bridge { i.buy = i.sell }
        }
        return i
    }

    /// A chain picked on a NEAR Intents trade: a coin that isn't on the new
    /// chain becomes that chain's own. One chain on both sides is a swap
    /// there (Uniswap's, or Jupiter's), no longer across.
    private static func pickNearChain(_ chain: String, side: Side, in intent: TradeIntent) -> TradeIntent {
        var i = intent
        if side == .buy, i.kind == .swap {
            i.buy = TradeIntent.nearFit(i.buy, on: chain)
            i.buyAddress = nil
            i.buyChain = chain == i.chainName ? nil : chain
            if i.buyChain == nil, i.sell == i.buy { i.buy = TradeIntent.stableFor(i.sell) }
            return i
        }
        i.chain = chain
        i.sell = TradeIntent.nearFit(i.sell, on: chain)
        i.sellAddress = nil
        if i.kind == .swap, i.buyChain == chain {
            i.buyChain = nil
            if i.sell == i.buy { i.buy = TradeIntent.stableFor(i.sell) }
        }
        return i
    }

    // MARK: picker rows

    /// The picker's rows before the server answers (or when it can't):
    /// the coins every chain here has.
    static func builtIn(chain: String) -> [TokenPick] {
        // A chain of its own: its coin, and the dollars 1Click has there.
        if TradeIntent.otherChains.contains(chain) {
            let own = TradeIntent.nativeChain.first { $0.value == chain }?.key ?? chain.uppercased()
            var rows = [TokenPick(symbol: own, name: TradeIntent.label(chain), native: true)]
            if TradeIntent.nearHas("USDC", on: chain) { rows.append(TokenPick(symbol: "USDC", name: "USD Coin")) }
            if TradeIntent.nearHas("USDT", on: chain) { rows.append(TokenPick(symbol: "USDT", name: "Tether USD")) }
            return rows
        }
        if chain == "solana" {
            return [TokenPick(symbol: "SOL", name: "Solana", native: true), TokenPick(symbol: "USDC", name: "USD Coin"),
                    TokenPick(symbol: "USDT", name: "Tether USD")]
        }
        var rows = [TokenPick(symbol: "ETH", name: "Ether", native: true), TokenPick(symbol: "USDC", name: "USD Coin")]
        if chain != "base", chain != "unichain" { rows.append(TokenPick(symbol: "USDT", name: "Tether USD")) }
        rows.append(TokenPick(symbol: "WETH", name: "Wrapped Ether"))
        if chain != "unichain" { rows.append(TokenPick(symbol: "DAI", name: "Dai Stablecoin")) }
        rows.append(chain == "base" ? TokenPick(symbol: "cbBTC", name: "Coinbase Wrapped BTC")
                                    : TokenPick(symbol: "WBTC", name: "Wrapped BTC"))
        return rows
    }

    /// The rows matching what's typed: an exact symbol, then symbols that
    /// start with it, then names that do, then anything containing it; a
    /// pasted address matches its own row.
    static func filter(_ rows: [TokenPick], query: String) -> [TokenPick] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "$", with: "")
        guard !q.isEmpty else { return rows }
        if q.hasPrefix("0x") { return rows.filter { $0.address?.lowercased() == q } }
        func score(_ t: TokenPick) -> Int? {
            let s = t.symbol.lowercased(), n = t.name.lowercased()
            if s == q { return 0 }
            if s.hasPrefix(q) { return 1 }
            if n.hasPrefix(q) { return 2 }
            if s.contains(q) || n.contains(q) { return 3 }
            return nil
        }
        return rows.enumerated().compactMap { idx, t in score(t).map { ($0, idx, t) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map { $0.2 }
    }

    /// Server rows after the built-in ones, without repeating a symbol
    /// the built-in list already has unless the address differs.
    static func merge(_ first: [TokenPick], _ more: [TokenPick]) -> [TokenPick] {
        var out = first
        for t in more where !out.contains(where: {
            $0.symbol.uppercased() == t.symbol.uppercased() && ($0.address == nil || $0.address?.lowercased() == t.address?.lowercased())
        }) { out.append(t) }
        // Server rows carry logos and addresses: they fill in the built-in ones.
        for (k, t) in out.enumerated() where t.logo == nil || t.address == nil {
            if let better = more.first(where: { $0.symbol.uppercased() == t.symbol.uppercased() }) {
                out[k].logo = out[k].logo ?? better.logo
                if !t.native { out[k].address = out[k].address ?? better.address }
            }
        }
        return out
    }
}
