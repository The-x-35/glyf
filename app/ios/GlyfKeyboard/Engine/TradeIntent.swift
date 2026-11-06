import Foundation

/// A trade said in plain words at the end of a message, read on the phone
/// with no model (ETHGlobal Mumbai, docs/ETHGLOBAL-MUMBAI.md): a swap goes
/// to Uniswap, an order that waits for a price to Definitive's Flash, a
/// payment to a name, a request for USDT to Whitechain. The keyboard only
/// shows what it read; the app quotes it again and the wallet signs.
struct TradeIntent: Equatable {

    enum Kind: String {
        /// Uniswap, now: "swap 0.05 eth to usdc on base", "buy $20 of eth".
        case swap
        /// Flash: a buy or sell at a price ("buy eth at 2800").
        case limit
        /// Flash: buy when the price breaks up through a level.
        case stop
        /// Flash: sell when the price falls to a level.
        case stopLoss = "stop-loss"
        /// Flash: sell when the price rises to a level.
        case takeProfit = "take-profit"
        /// Flash: a take-profit and a stop-loss together, on what's held,
        /// or attached to a market buy.
        case bracket
        /// Flash: a stop that follows the price up by a percentage.
        case trailingStop = "trailing-stop"
        /// Flash: one order spread over time ("buy $20 of eth every day for a week").
        case twap
        /// Flash: the same token moved to another chain.
        case bridge
        /// The wallet: to an ENS or SNS name, or an address.
        case send
        /// Whitechain: ask someone for USDT; they pay a GlyfPayRequest.
        case request
    }

    var kind: Kind
    /// The number typed; nil means everything held ("sell my eth").
    var amount: String?
    /// The amount is dollars of what's bought ("$50 of eth").
    var amountIsUSD = false
    /// What is spent (a swap's sell side, the asset an order sells).
    var sell: String
    /// What comes back.
    var buy: String
    var chain: String?
    var toChain: String?
    /// The trigger or limit, in dollars (a bracket's take-profit).
    var price: String?
    /// A bracket's stop-loss.
    var stopPrice: String?
    var trailPercent: String?
    var durationSeconds: Int?
    /// A send's recipient: arpit.eth, arpit.sol, 0x…
    var to: String?
    /// "buy 0.1 eth": the amount wanted back, not the amount spent.
    var buyAmount: String?
    /// A g menu starter (SponsorMenu.starter): the trigger is this many
    /// percent from the market (-10 = 10% under), set as `price` once the
    /// trade panel has the price. Never read from words.
    var pricePercent: Double?
    /// The same for a bracket's stop-loss.
    var stopPercent: Double?
    /// A token picked in the panel by its contract (GET /uniswap/tokens),
    /// sent beside the symbol so a lookalike symbol can't stand in.
    var sellAddress: String?
    var buyAddress: String?
    /// A swap whose You get side is on another chain ("swap 50 usdc on base
    /// to eth on arbitrum"): Uniswap's cross-chain route. Nil = same chain.
    var buyChain: String?
    /// A buy repeated on a schedule ("dca $20 in eth each month"), placed
    /// as this one Flash TWAP (TradeRecurring.swift).
    var plan: RecurringPlan?

    /// A starter whose price waits on the market's.
    var awaitingPrice: Bool {
        (pricePercent != nil && price == nil) || (stopPercent != nil && stopPrice == nil)
    }

    /// Who carries it out, as the strip says it.
    var venue: String {
        switch kind {
        // Solana has no Uniswap pools here: Jupiter swaps there.
        case .swap: return chainName == "solana" ? "Jupiter" : "Uniswap"
        case .send: return "Glyf wallet"
        case .request: return "Whitechain"
        default: return "Flash"
        }
    }

    /// The chain it lands on: Base unless the words named one (cheap, and
    /// both Uniswap and Flash trade there). A request is Whitechain's.
    var chainName: String {
        if kind == .request { return "whitechain-sepolia" }
        return chain ?? "base"
    }

    static let chainLabels = [
        "base": "Base", "ethereum": "Ethereum", "arbitrum": "Arbitrum", "optimism": "Optimism",
        "polygon": "Polygon", "unichain": "Unichain", "solana": "Solana", "whitechain-sepolia": "Whitechain",
    ]

    var chainLabel: String { Self.chainLabels[chainName] ?? chainName.capitalized }

    private var amountText: String {
        if amount == nil, let buyAmount { return "\(buyAmount) \(buy)" }
        guard let amount else { return "all \(sell)" }
        return amountIsUSD ? "$\(amount) of \(buy)" : "\(amount) \(sell)"
    }

    /// The chip's words: "Swap 0.05 ETH → USDC", "Stop-loss ETH at $3,000".
    var title: String {
        switch kind {
        case .swap:
            if amountIsUSD { return "Buy \(amountText)" }
            if buyAmount != nil { return "Buy \(amountText) with \(sell)" }
            if let buyChain, buyChain != chainName {
                return "Swap \(amountText) → \(buy) on \(Self.chainLabels[buyChain] ?? buyChain.capitalized)"
            }
            return "Swap \(amountText) → \(buy)"
        case .limit:
            return sell == "USDC" || sell == "USDT"
                ? "Buy \(buy) at \(Self.dollars(price))" : "Sell \(sell) at \(Self.dollars(price))"
        case .stop: return "Buy \(buy) above \(Self.dollars(price))"
        case .stopLoss: return "Stop-loss \(sell) at \(Self.dollars(price))"
        case .takeProfit: return "Take profit \(sell) at \(Self.dollars(price))"
        case .bracket:
            return "\(sell) TP \(Self.dollars(price)) · SL \(Self.dollars(stopPrice))"
        case .trailingStop: return "Trail \(sell) by \(trailPercent ?? "")%"
        case .twap:
            if let planTitle { return planTitle }
            return "Buy \(amountIsUSD ? "$\(amount ?? "")" : amountText) of \(buy) \(Self.span(durationSeconds))"
        case .bridge:
            return "Move \(amountText) to \(Self.chainLabels[toChain ?? ""] ?? (toChain ?? "").capitalized)"
        case .send: return "Send \(amountText) to \(to ?? "")"
        case .request: return "Request \(amount ?? "") \(sell)"
        }
    }

    /// Under the title: where and through whom.
    var detail: String {
        switch kind {
        case .bridge: return "\(chainLabel) → \(Self.chainLabels[toChain ?? ""] ?? "") · Flash"
        case .swap where buyChain != nil && buyChain != chainName:
            return "\(chainLabel) → \(Self.chainLabels[buyChain!] ?? buyChain!.capitalized) · Uniswap"
        default: return "\(chainLabel) · \(venue)"
        }
    }

    /// The app's words for it (glyf://open?path=trade?…).
    var query: [String: String] {
        var q = ["kind": kind.rawValue, "sell": sell, "buy": buy, "chain": chainName]
        if let amount { q["amount"] = amount }
        if amountIsUSD { q["usd"] = "1" }
        if let toChain { q["toChain"] = toChain }
        if let price { q["price"] = price }
        if let stopPrice { q["stopPrice"] = stopPrice }
        if let trailPercent { q["trail"] = trailPercent }
        if let durationSeconds { q["duration"] = String(durationSeconds) }
        if let to { q["to"] = to }
        if let buyAmount { q["buyAmount"] = buyAmount }
        if let sellAddress { q["sellAddress"] = sellAddress }
        if let buyAddress { q["buyAddress"] = buyAddress }
        if let buyChain, buyChain != chainName { q["buyChain"] = buyChain }
        return q
    }

    static func dollars(_ price: String?) -> String {
        guard let price, let v = Double(price) else { return "$\(price ?? "")" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v < 10 ? 4 : 2
        return "$" + (f.string(from: NSNumber(value: v)) ?? price)
    }

    static func span(_ seconds: Int?) -> String {
        guard let s = seconds else { return "" }
        if s % (7 * 86_400) == 0 { let w = s / (7 * 86_400); return w == 1 ? "over a week" : "over \(w) weeks" }
        if s % 86_400 == 0 { let d = s / 86_400; return d == 1 ? "over a day" : "over \(d) days" }
        let h = max(1, s / 3600); return h == 1 ? "over an hour" : "over \(h) hours"
    }

    // MARK: reading

    /// Tokens the words may name. Only these: "swap shifts with sam" is not
    /// a trade.
    static let symbols: [String: String] = [
        "eth": "ETH", "ether": "ETH", "weth": "WETH", "usdc": "USDC", "usdt": "USDT", "dai": "DAI",
        "wbtc": "WBTC", "btc": "WBTC", "bitcoin": "WBTC", "cbbtc": "CBBTC", "uni": "UNI", "link": "LINK",
        "aave": "AAVE", "op": "OP", "arb": "ARB", "pol": "POL", "matic": "POL", "aero": "AERO",
        "degen": "DEGEN", "sol": "SOL", "solana": "SOL", "pepe": "PEPE", "ldo": "LDO",
    ]

    static let chains: [String: String] = [
        "base": "base", "ethereum": "ethereum", "eth mainnet": "ethereum", "mainnet": "ethereum",
        "arbitrum": "arbitrum", "arb": "arbitrum", "optimism": "optimism", "op": "optimism",
        "polygon": "polygon", "unichain": "unichain", "solana": "solana", "whitechain": "whitechain-sepolia",
    ]

    private static let sym = #"(eth|ether|weth|usdc|usdt|dai|wbtc|btc|bitcoin|cbbtc|uni|link|aave|op|arb|pol|matic|aero|degen|sol|solana|pepe|ldo)"#
    private static let num = #"(\d+(?:[.,]\d+)?(?:k)?)"#
    private static let chainPart = #"(?:\s+on\s+(base|ethereum|eth mainnet|mainnet|arbitrum|arb|optimism|op|polygon|unichain|solana|whitechain))?"#
    private static let chainWord = #"(base|ethereum|eth mainnet|mainnet|arbitrum|arb|optimism|op|unichain|polygon|solana|whitechain)"#
    private static let end = #"\s*[.!]?\s*$"#
    /// Where a command may begin: the start, or after a sentence ends.
    private static let start = #"(?:^|[.!?\n]\s*|\b(?:pls|please|glyf|hey glyf)[,:]?\s+)"#

    static func parse(_ text: String) -> TradeIntent? {
        let t = String(text.suffix(200))
        if t.count < 8 { return nil }
        // Cheap test first: every pattern has one of these words.
        let lower = t.lowercased()
        let words = ["swap", "convert", "trade", "buy", "sell", "stop", "take profit", "tp ", "trail",
                     "dca", "move", "bridge", "send", "pay", "request", "protect", "limit", "invest", "stack", "put"]
        guard words.contains(where: lower.contains) else { return nil }
        // A schedule longer than Flash's 30-day TWAP is a recurring plan.
        let spread = twap(t).flatMap { ($0.durationSeconds ?? 0) <= RecurringPlan.flashMaxSeconds ? $0 : nil }
        return bracket(t) ?? orders(t) ?? spread ?? recurring(t) ?? bridgeMove(t) ?? send(t) ?? request(t) ?? swap(t)
    }

    // "swap 0.05 eth to usdc on base", "sell 0.1 eth", "buy 20 usdc of eth"
    private static func swap(_ t: String) -> TradeIntent? {
        // "swap 50 usdc on base to eth on arbitrum": each side on its chain.
        if let m = match(start + #"(?:swap|convert|trade|exchange|bridge)\s+"# + num + #"\s+"# + sym + #"\s+(?:on|from)\s+"# + chainWord + #"\s+(?:to|for|into)\s+"# + sym + #"\s+on\s+"# + chainWord + end, t),
           let sell = symbol(m[2]), let from = chains[m[3]!.lowercased()], let buy = symbol(m[4]),
           let to = chains[m[5]!.lowercased()], from != "solana", to != "solana", from != "whitechain-sepolia",
           to != "whitechain-sepolia" {
            var i = TradeIntent(kind: .swap, amount: amount(m[1]), sell: sell, buy: buy, chain: from)
            if to != from { i.buyChain = to } else if sell == buy { return nil }
            return i
        }
        if let m = match(start + #"(?:swap|convert|trade|exchange)\s+(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|"# + num + #"\s+)?"# + sym + #"\s+(?:to|for|into)\s+"# + sym + chainPart + end, t) {
            return swapOf(amount: m[1], sell: m[2]!, buy: m[3]!, chain: m[4])
        }
        // "buy $50 of eth", "buy $50 worth of eth with usdt"
        if let m = match(start + #"buy\s+\$"# + num + #"\s+(?:of|worth\s+of|in)\s+"# + sym + #"(?:\s+(?:with|using)\s+"# + sym + ")?" + chainPart + end, t) {
            let buy = symbol(m[2])!
            var i = TradeIntent(kind: .swap, amount: amount(m[1]), sell: symbol(m[3]) ?? stableFor(buy), buy: buy,
                                chain: chain(m[4], token: buy))
            i.amountIsUSD = true
            return i.sell == i.buy ? nil : i
        }
        // "buy 0.1 eth (with usdc)"
        if let m = match(start + #"buy\s+"# + num + #"\s+"# + sym + #"(?:\s+(?:with|using)\s+"# + sym + ")?" + chainPart + end, t) {
            let buy = symbol(m[2])!
            let sell = symbol(m[3]) ?? stableFor(buy)
            // The amount is what comes back: the app works out what it costs.
            var i = TradeIntent(kind: .swap, sell: sell, buy: buy, chain: chain(m[4], token: buy))
            i.buyAmount = amount(m[1])
            return i.sell == i.buy ? nil : i
        }
        // "sell 0.1 eth (for usdc)", "sell my eth"
        if let m = match(start + #"sell\s+(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|"# + num + #"\s+)?"# + sym + #"(?:\s+(?:for|to|into)\s+"# + sym + ")?" + chainPart + end, t) {
            let sell = symbol(m[2])!
            return swapOf(amount: m[1], sell: m[2]!, buy: m[3] ?? stableFor(sell).lowercased(), chain: m[4])
        }
        return nil
    }

    private static func swapOf(amount a: String?, sell s: String, buy b: String, chain c: String?) -> TradeIntent? {
        guard let sell = symbol(s), let buy = symbol(b), sell != buy else { return nil }
        if (sell == "SOL") != (buy == "SOL") { return nil }   // a swap stays on one chain
        return TradeIntent(kind: .swap, amount: amount(a), sell: sell, buy: buy, chain: chain(c, token: sell))
    }

    // Orders that wait for a price, all Flash.
    private static func orders(_ t: String) -> TradeIntent? {
        let held = #"(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|"# + num + #"\s+)?"#
        let price = #"\$?"# + num
        // "sell my eth if it drops below 3000", "sell 0.1 eth when it falls to $3,000"
        if let m = match(start + #"sell\s+"# + held + sym + #"\s+(?:if|when|once)\s+(?:it|the\s+price|price|"# + sym + #")\s+(?:drops?|falls?|goes|dips?|gets|is)\s+(?:below|under|to|beneath)\s+"# + price + chainPart + end, t) {
            return order(.stopLoss, amount: m[1], asset: m[2]!, price: m[4], chain: m[5])
        }
        // "stop loss my eth at 3000", "stop-loss eth 3000", "sl eth at 3000"
        if let m = match(start + #"(?:set\s+(?:a\s+)?)?(?:stop[- ]?loss|sl)\s+(?:on\s+|for\s+)?"# + held + sym + #"\s+(?:at\s+|@\s*|to\s+)?"# + price + chainPart + end, t) {
            return order(.stopLoss, amount: m[1], asset: m[2]!, price: m[3], chain: m[4])
        }
        // "sell my eth if it hits 4500", "sell eth when it reaches $4,500"
        if let m = match(start + #"sell\s+"# + held + sym + #"\s+(?:if|when|once)\s+(?:it|the\s+price|price|"# + sym + #")\s+(?:hits|reaches|goes\s+(?:above|over|to)|rises\s+(?:above|over|to)|gets\s+to|crosses|is\s+(?:above|over)|touches)\s+"# + price + chainPart + end, t) {
            return order(.takeProfit, amount: m[1], asset: m[2]!, price: m[4], chain: m[5])
        }
        // "take profit eth at 4500", "tp my eth 4500"
        if let m = match(start + #"(?:set\s+(?:a\s+)?)?(?:take[- ]?profit|tp)\s+(?:on\s+|for\s+)?"# + held + sym + #"\s+(?:at\s+|@\s*|to\s+)?"# + price + chainPart + end, t) {
            return order(.takeProfit, amount: m[1], asset: m[2]!, price: m[3], chain: m[4])
        }
        // "sell 0.1 eth at 4000" (a limit sell)
        if let m = match(start + #"(?:limit\s+)?sell\s+"# + held + sym + #"\s+(?:at|@)\s*"# + price + chainPart + end, t) {
            return order(.limit, amount: m[1], asset: m[2]!, price: m[3], chain: m[4])
        }
        // "buy eth if it drops to 2800", "buy $100 of eth if it dips below 2800"
        if let m = match(start + #"buy\s+(?:\$"# + num + #"\s+(?:of|worth\s+of)\s+|"# + num + #"\s+)?"# + sym + #"\s+(?:if|when|once)\s+(?:it|the\s+price|price)\s+(?:drops?|falls?|dips?|goes|gets|is)\s+(?:below|under|to)\s+"# + price + chainPart + end, t) {
            return buyOrder(.limit, usd: m[1], qty: m[2], asset: m[3]!, price: m[4], chain: m[5])
        }
        // "buy $100 of eth at 2800", "limit buy eth at 2800"
        if let m = match(start + #"(?:limit\s+)?buy\s+(?:\$"# + num + #"\s+(?:of|worth\s+of)\s+|"# + num + #"\s+)?"# + sym + #"\s+(?:at|@)\s*"# + price + chainPart + end, t) {
            return buyOrder(.limit, usd: m[1], qty: m[2], asset: m[3]!, price: m[4], chain: m[5])
        }
        // "buy eth if it breaks 4000", "buy eth when it goes above 4000"
        if let m = match(start + #"buy\s+(?:\$"# + num + #"\s+(?:of|worth\s+of)\s+|"# + num + #"\s+)?"# + sym + #"\s+(?:if|when|once)\s+(?:it|the\s+price|price)\s+(?:breaks(?:\s+above)?|goes\s+(?:above|over)|crosses|rises\s+(?:above|over)|is\s+above)\s+"# + price + chainPart + end, t) {
            return buyOrder(.stop, usd: m[1], qty: m[2], asset: m[3]!, price: m[4], chain: m[5])
        }
        // "trail my eth by 5%", "trailing stop eth 5%", "protect my eth with a 5% trail"
        if let m = match(start + #"(?:set\s+(?:a\s+)?)?(?:trail(?:ing\s+stop)?|trailing)\s+(?:on\s+|for\s+)?"# + held + sym + #"\s+(?:by\s+|at\s+|with\s+)?"# + num + #"\s?%"# + chainPart + end, t) {
            return trailing(amount: m[1], asset: m[2]!, percent: m[3], chain: m[4])
        }
        if let m = match(start + #"protect\s+"# + held + sym + #"\s+with\s+(?:a\s+)?"# + num + #"\s?%\s+trail(?:ing\s+stop)?"# + chainPart + end, t) {
            return trailing(amount: m[1], asset: m[2]!, percent: m[3], chain: m[4])
        }
        return nil
    }

    // "buy 0.1 eth tp 4500 sl 3000", "my eth: take profit 4500, stop loss 3000"
    private static func bracket(_ t: String) -> TradeIntent? {
        let tp = #"(?:tp|take[- ]?profit)(?:\s+at)?\s+\$?"# + num
        let sl = #"(?:sl|stop[- ]?loss|stop)(?:\s+at)?\s+\$?"# + num
        let joiner = #"\s*(?:,|and|&|\+)?\s*"#
        if let m = match(start + #"buy\s+(?:\$"# + num + #"\s+(?:of|worth\s+of)\s+|"# + num + #"\s+)?"# + sym + #"[,:]?\s+"# + tp + joiner + sl + chainPart + end, t) {
            guard let asset = symbol(m[3]) else { return nil }
            var i = TradeIntent(kind: .bracket, amount: amount(m[1] ?? m[2]), sell: stableFor(asset), buy: asset,
                                chain: chain(m[6], token: asset), price: amount(m[4]), stopPrice: amount(m[5]))
            i.amountIsUSD = m[1] != nil
            if !i.amountIsUSD, m[2] != nil { i.buyAmount = amount(m[2]); i.amount = nil }
            return sane(i)
        }
        if let m = match(start + #"(?:(?:set\s+)?(?:a\s+)?bracket\s+(?:on\s+)?)?(?:all\s+(?:of\s+)?(?:my\s+)?|my\s+|"# + num + #"\s+)?"# + sym + #"[,:]?\s+"# + tp + joiner + sl + chainPart + end, t) {
            guard let asset = symbol(m[2]) else { return nil }
            return sane(TradeIntent(kind: .bracket, amount: amount(m[1]), sell: asset, buy: stableFor(asset),
                                    chain: chain(m[5], token: asset), price: amount(m[3]), stopPrice: amount(m[4])))
        }
        return nil
    }

    // "buy $20 of eth every day for a week", "dca $50 into eth weekly for 4 weeks",
    // "buy $100 of eth over a day"
    private static func twap(_ text: String) -> TradeIntent? {
        // Autocorrect makes "every day" "everyday"; people say "daily" too.
        var t = text
        for (said, meant) in [("everyday", "every day"), ("daily", "every day"), ("weekly", "every week"),
                              ("hourly", "every hour")] {
            t = t.replacingOccurrences(of: #"\b\#(said)\b"#, with: meant, options: [.regularExpression, .caseInsensitive])
        }
        let units = #"(hour|day|week)s?"#
        if let m = match(start + #"(?:buy|dca)\s+\$"# + num + #"\s+(?:of|worth\s+of|into|in)\s+"# + sym + #"\s+(?:every|each|a|per)\s+"# + units + #"(?:\s+for\s+(a|an|one|two|three|four|five|six|seven|\d+)\s+"# + units + ")?" + chainPart + end, t) {
            guard let each = Double(amount(m[1]) ?? ""), let asset = symbol(m[2]) else { return nil }
            let unit = seconds(m[3]!)
            let span = m[4].map { count($0) * seconds(m[5] ?? m[3]!) } ?? 7 * unit
            let slices = max(1, span / unit)
            var i = TradeIntent(kind: .twap, amount: trimmed(each * Double(slices)), sell: stableFor(asset), buy: asset,
                                chain: chain(m[6], token: asset))
            i.amountIsUSD = true
            i.durationSeconds = span
            return i
        }
        if let m = match(start + #"(?:buy|dca)\s+\$"# + num + #"\s+(?:of|worth\s+of|into|in)\s+"# + sym + #"\s+over\s+(a|an|one|two|three|four|five|six|seven|\d+)\s+"# + units + chainPart + end, t) {
            guard let asset = symbol(m[2]) else { return nil }
            var i = TradeIntent(kind: .twap, amount: amount(m[1]), sell: stableFor(asset), buy: asset,
                                chain: chain(m[5], token: asset))
            i.amountIsUSD = true
            i.durationSeconds = count(m[3]!) * seconds(m[4]!)
            return i
        }
        return nil
    }

    // "move 50 usdc from base to arbitrum", "bridge 0.1 eth from ethereum to base"
    private static func bridgeMove(_ t: String) -> TradeIntent? {
        let c = #"(base|ethereum|mainnet|arbitrum|arb|optimism|op|polygon|unichain|solana)"#
        guard let m = match(start + #"(?:move|bridge|send)\s+"# + num + #"\s+"# + sym + #"\s+from\s+"# + c + #"\s+to\s+"# + c + end, t),
              let asset = symbol(m[2]), let from = chains[m[3]!.lowercased()], let to = chains[m[4]!.lowercased()], from != to
        else { return nil }
        var i = TradeIntent(kind: .bridge, amount: amount(m[1]), sell: asset, buy: asset, chain: from)
        i.toChain = to
        return i
    }

    // "send 20 usdc to arpit.eth", "pay arpit.sol 5 usdc", "send 0.01 eth to 0x12…"
    private static func send(_ t: String) -> TradeIntent? {
        let who = #"([a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:eth|sol)|0x[0-9a-fA-F]{40})"#
        var m = match(start + #"(?:send|pay|transfer)\s+"# + num + #"\s+"# + sym + #"\s+to\s+"# + who + chainPart + end, t)
        if m == nil, let n = match(start + #"(?:send|pay)\s+"# + who + #"\s+"# + num + #"\s+"# + sym + chainPart + end, t) {
            m = [n[0], n[2], n[3], n[1], n[4]]
        }
        guard let m, let asset = symbol(m[2]), let to = m[3] else { return nil }
        let name = to.lowercased()
        // A .sol name is Solana's: the existing Phantom send takes it.
        let onSolana = name.hasSuffix(".sol") || asset == "SOL"
        var i = TradeIntent(kind: .send, amount: amount(m[1]), sell: asset, buy: asset,
                            chain: onSolana ? "solana" : chain(m[4], token: asset))
        i.to = to.hasPrefix("0x") ? to : name
        return i
    }

    // "request 20 usdt", "request 15 usdt on whitechain"
    private static func request(_ t: String) -> TradeIntent? {
        guard let m = match(start + #"(?:request|invoice|bill)\s+(?:me\s+)?\$?"# + num + #"\s*(usdt|usdc|\$)?(?:\s+on\s+whitechain)?(?:\s+for\s+[^.!?\n]{1,40})?"# + end, t)
        else { return nil }
        return TradeIntent(kind: .request, amount: amount(m[1]), sell: "USDT", buy: "USDT", chain: "whitechain-sepolia")
    }

    // MARK: helpers

    private static func order(_ kind: Kind, amount a: String?, asset s: String, price p: String?, chain c: String?) -> TradeIntent? {
        guard let asset = symbol(s), !["USDC", "USDT", "DAI"].contains(asset) else { return nil }
        return sane(TradeIntent(kind: kind, amount: amount(a), sell: asset, buy: stableFor(asset),
                                chain: chain(c, token: asset), price: amount(p)))
    }

    private static func buyOrder(_ kind: Kind, usd: String?, qty: String?, asset s: String, price p: String?, chain c: String?) -> TradeIntent? {
        guard let asset = symbol(s), !["USDC", "USDT", "DAI"].contains(asset) else { return nil }
        var i = TradeIntent(kind: kind, amount: amount(usd), sell: stableFor(asset), buy: asset,
                            chain: chain(c, token: asset), price: amount(p))
        i.amountIsUSD = usd != nil
        if usd == nil, let qty { i.buyAmount = amount(qty) }
        return sane(i)
    }

    private static func trailing(amount a: String?, asset s: String, percent: String?, chain c: String?) -> TradeIntent? {
        guard let asset = symbol(s), let p = Double(amount(percent) ?? ""), p >= 0.5, p <= 50 else { return nil }
        var i = TradeIntent(kind: .trailingStop, amount: amount(a), sell: asset, buy: stableFor(asset),
                            chain: chain(c, token: asset))
        i.trailPercent = trimmed(p)
        return i
    }

    /// A take-profit has to sit above the stop.
    private static func sane(_ i: TradeIntent) -> TradeIntent? {
        if let p = i.price.flatMap(Double.init), p <= 0 { return nil }
        if i.kind == .bracket, let tp = i.price.flatMap(Double.init), let sl = i.stopPrice.flatMap(Double.init), tp <= sl { return nil }
        return i
    }

    static func symbol(_ word: String?) -> String? { word.flatMap { symbols[$0.lowercased()] } }

    /// What a token is priced against: USDC, or ETH for a stablecoin.
    static func stableFor(_ symbol: String) -> String { ["USDC", "USDT", "DAI"].contains(symbol) ? "ETH" : "USDC" }

    private static func chain(_ word: String?, token: String) -> String? {
        if let word, let c = chains[word.lowercased()] { return c }
        return token == "SOL" ? "solana" : nil
    }

    /// "1,000" and "1.5k" as plain numbers; "3,000" with a comma is thousands.
    static func amount(_ raw: String?) -> String? {
        guard var s = raw?.lowercased(), !s.isEmpty else { return nil }
        var scale = 1.0
        if s.hasSuffix("k") { scale = 1000; s.removeLast() }
        if s.contains(","), s.split(separator: ",").last?.count == 3 { s = s.replacingOccurrences(of: ",", with: "") }
        s = s.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(s), v > 0 else { return nil }
        return trimmed(v * scale)
    }

    static func trimmed(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        var s = String(format: "%.8f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    private static func seconds(_ unit: String) -> Int {
        switch unit.lowercased() {
        case "hour": return 3600
        case "week": return 7 * 86_400
        default: return 86_400
        }
    }

    private static func count(_ word: String) -> Int {
        ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7][word.lowercased()]
            ?? Int(word) ?? 1
    }

    /// Capture groups of the last match, nil where a group didn't take part.
    private static func match(_ pattern: String, _ text: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}

extension TradeIntent {
    /// Who signs a trade on [chain], as the app names it: the app's switch
    /// (shared settings `walletMode`, lib/wallet/wallet_mode.dart) picks the
    /// Glyf wallet on every chain, or Phantom on Solana and MetaMask elsewhere.
    static func walletName(chain: String?, mode: String?) -> String {
        guard mode == "external" else { return "Glyf wallet" }
        return chain == "solana" ? "Phantom" : "MetaMask"
    }
}
