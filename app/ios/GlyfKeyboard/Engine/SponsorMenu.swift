import Foundation

/// The g menu's top row: the apps Glyf trades and thinks through (ETHGlobal
/// Mumbai): Uniswap swaps, Definitive's Flash orders, 0G's Private AI. A tap
/// on one opens its own panel listing everything it does; nothing runs on
/// the tap itself (Arpit, 2026-11-06: "any icon, should not trigger a thing
/// by default. It should show all the options"). Pure, so RunnerTests pins
/// which icons show, what each panel lists and what each option puts up.
enum SponsorMenu {

    enum Sponsor: String, CaseIterable {
        case uniswap, definitive
        case zeroG = "0g"

        var title: String {
            switch self {
            case .uniswap: return "Uniswap"
            case .definitive: return "Definitive"
            case .zeroG: return "0G"
            }
        }

        /// The shell screen that is its panel.
        var screenId: String { "sponsor:\(rawValue)" }

        init?(screenId: String) {
            guard screenId.hasPrefix("sponsor:") else { return nil }
            self.init(rawValue: String(screenId.dropFirst("sponsor:".count)))
        }
    }

    /// One thing a panel can do.
    enum Option: Equatable {
        /// Uniswap: the swap typed, or the starter on Base.
        case swap
        /// Uniswap: the starter swap on this chain.
        case swapOn(String)
        /// Definitive: the Flash order already typed.
        case typed
        /// Definitive: a starter of this kind on the chain picked.
        case order(TradeIntent.Kind)
        /// Definitive: the app's Ethereum wallet, where Flash orders wait.
        case openOrders
        /// 0G: Keyboard settings in the app, with the 0G receipts.
        case receipts

        /// The shell row's target ("!sponsor:<id>").
        var id: String {
            switch self {
            case .swap: return "swap"
            case .swapOn(let chain): return "swap:\(chain)"
            case .typed: return "typed"
            case .order(let kind): return "order:\(kind.rawValue)"
            case .openOrders: return "orders"
            case .receipts: return "receipts"
            }
        }

        init?(id: String) {
            switch id {
            case "swap": self = .swap
            case "typed": self = .typed
            case "orders": self = .openOrders
            case "receipts": self = .receipts
            default:
                if id.hasPrefix("swap:") {
                    let chain = String(id.dropFirst("swap:".count))
                    guard SponsorMenu.swapChains.contains(chain) else { return nil }
                    self = .swapOn(chain)
                } else if id.hasPrefix("order:"),
                          let kind = TradeIntent.Kind(rawValue: String(id.dropFirst("order:".count))),
                          SponsorMenu.orderKinds.contains(kind) {
                    self = .order(kind)
                } else {
                    return nil
                }
            }
        }
    }

    /// A row of a sponsor's panel.
    enum Entry: Equatable {
        case header(String)
        case option(Option, title: String, detail: String?, icon: String)
        /// Definitive: Base or Solana.
        case chainPicker
        /// 0G: Private AI on or off.
        case privateAISwitch
        /// 0G: a fact about the last answer.
        case status(title: String, value: String, icon: String)
    }

    /// What a tap on an option does.
    enum Action: Equatable {
        /// The trade panel, with this trade on it, as if it had been typed.
        case trade(TradeIntent)
        /// One hop to the app.
        case openApp(path: String)
    }

    /// Every chain Glyf swaps on through Uniswap (the server's EVM chains).
    static let swapChains = ["base", "ethereum", "arbitrum", "optimism", "unichain"]
    /// Flash's chains the keyboard offers.
    static let flashChains = ["base", "solana"]
    /// Flash's order types, in the panel's order.
    static let orderKinds: [TradeIntent.Kind] = [
        .limit, .stop, .stopLoss, .takeProfit, .bracket, .trailingStop, .twap, .bridge,
    ]

    /// The chain the Definitive panel trades on; Base until Solana is picked.
    /// Kept while the keyboard process lives.
    static var flashChain = "base"

    /// Uniswap and Definitive always; 0G only where the app wrote the
    /// `privateAI` setting (the hackathon build; other builds leave it unset).
    static func sponsors(privateAI: Bool?) -> [Sponsor] {
        privateAI == nil ? [.uniswap, .definitive] : Sponsor.allCases
    }

    // MARK: panels

    /// A sponsor's panel. `typed` is the text before the cursor; `receipts`
    /// GET /ai/receipts's list (nil when it failed), `receiptsLoaded`
    /// whether the answer is in.
    static func entries(for sponsor: Sponsor, typed: String, flashChain: String = "base",
                        privateAI: Bool?, receipts: [[String: Any]]? = nil,
                        receiptsLoaded: Bool = false, now: Date = Date()) -> [Entry] {
        switch sponsor {
        case .uniswap:
            let swap = typedSwap(typed) ?? starterSwap(on: "base")
            var rows: [Entry] = [
                .option(.swap, title: "Swap", detail: swapDetail(swap), icon: "arrow.left.arrow.right"),
                .header("Chains"),
            ]
            rows += swapChains.map {
                .option(.swapOn($0), title: TradeIntent.chainLabels[$0] ?? $0.capitalized, detail: nil,
                        icon: "square.stack.3d.up")
            }
            return rows
        case .definitive:
            var rows: [Entry] = [.chainPicker, .header("Orders")]
            if let t = typedOrder(typed) {
                rows.append(.option(.typed, title: t.title, detail: nil, icon: "text.cursor"))
            }
            rows += orderKinds.map {
                .option(.order($0), title: orderTitle($0), detail: orderDetail($0, chain: flashChain),
                        icon: orderIcon($0))
            }
            rows.append(.option(.openOrders, title: "Open orders", detail: nil, icon: "list.bullet.rectangle"))
            return rows
        case .zeroG:
            var rows: [Entry] = [.privateAISwitch]
            if privateAI == true {
                let s = status(receipts: receipts, loaded: receiptsLoaded, now: now)
                rows.append(.header("Last answer"))
                rows.append(.status(title: "When", value: s.last, icon: "clock"))
                rows.append(.status(title: "TEE", value: s.tee, icon: "lock.shield"))
            }
            rows.append(.option(.receipts, title: "Receipts", detail: nil, icon: "checkmark.seal"))
            return rows
        }
    }

    /// "USDC → ETH", "0.05 ETH → USDC", "Buy $20 of ETH".
    static func swapDetail(_ t: TradeIntent) -> String {
        t.title.hasPrefix("Swap ") ? String(t.title.dropFirst("Swap ".count)) : t.title
    }

    static func orderTitle(_ kind: TradeIntent.Kind) -> String {
        switch kind {
        case .limit: return "Limit buy"
        case .stop: return "Stop buy"
        case .stopLoss: return "Stop-loss"
        case .takeProfit: return "Take profit"
        case .bracket: return "Bracket"
        case .trailingStop: return "Trailing stop"
        case .twap: return "TWAP"
        case .bridge: return "Bridge"
        default: return kind.rawValue.capitalized
        }
    }

    /// How far from the price each starter sits, as the row says it.
    static func orderDetail(_ kind: TradeIntent.Kind, chain: String) -> String? {
        switch kind {
        case .limit: return "−5%"
        case .stop: return "+5%"
        case .stopLoss: return "−10%"
        case .takeProfit: return "+10%"
        case .bracket: return "±10%"
        case .trailingStop: return "10%"
        case .twap: return "$20 · 1 day"
        case .bridge:
            let to = bridgeTarget(from: chain)
            return "→ \(TradeIntent.chainLabels[to] ?? to.capitalized)"
        default: return nil
        }
    }

    static func orderIcon(_ kind: TradeIntent.Kind) -> String {
        switch kind {
        case .limit: return "scope"
        case .stop: return "arrow.up.right"
        case .stopLoss: return "arrow.down.right"
        case .takeProfit: return "flag"
        case .bracket: return "arrow.up.and.down"
        case .trailingStop: return "chart.line.downtrend.xyaxis"
        case .twap: return "clock.arrow.circlepath"
        case .bridge: return "arrow.triangle.swap"
        default: return "circle"
        }
    }

    // MARK: options

    static func action(for option: Option, typed: String, flashChain: String = "base") -> Action? {
        switch option {
        case .swap: return .trade(typedSwap(typed) ?? starterSwap(on: "base"))
        case .swapOn(let chain): return .trade(starterSwap(on: chain))
        case .typed: return typedOrder(typed).map { .trade($0) }
        case .order(let kind): return starter(kind, chain: flashChain).map { .trade($0) }
        case .openOrders: return .openApp(path: "evm-wallet")
        case .receipts: return .openApp(path: "settings")
        }
    }

    /// A swap typed at the end of the message.
    static func typedSwap(_ typed: String) -> TradeIntent? {
        guard let t = TradeIntent.parse(typed), t.kind == .swap else { return nil }
        return t
    }

    /// A Flash order typed at the end of the message.
    static func typedOrder(_ typed: String) -> TradeIntent? {
        guard let t = TradeIntent.parse(typed), t.venue == "Flash" else { return nil }
        return t
    }

    /// A small swap, 10 USDC to ETH, on `chain`.
    static func starterSwap(on chain: String) -> TradeIntent {
        TradeIntent.parse("swap 10 usdc to eth on \(chain)")!
    }

    static func bridgeTarget(from chain: String) -> String { chain == "solana" ? "base" : "arbitrum" }

    /// A Flash starter of `kind`: ETH on Base, SOL on Solana. A buy spends
    /// $20 of USDC; a stop-loss, take-profit, bracket or trail guards what
    /// is held. Read from the words a person would type, so it is the trade
    /// the chip would show. Orders that wait on a price carry it as a
    /// distance from the market (`pricePercent`), set once the trade panel
    /// has the price, so a starter never sits on the wrong side of it.
    static func starter(_ kind: TradeIntent.Kind, chain: String) -> TradeIntent? {
        let solana = chain == "solana"
        let a = solana ? "sol" : "eth"
        let on = solana ? " on solana" : ""
        let words: String
        var pct: Double?
        var stopPct: Double?
        switch kind {
        case .limit: words = "buy $20 of \(a) at 1\(on)"; pct = -5
        case .stop: words = "buy $20 of \(a) if it breaks 1\(on)"; pct = 5
        case .stopLoss: words = "stop-loss my \(a) at 1\(on)"; pct = -10
        case .takeProfit: words = "take profit my \(a) at 1\(on)"; pct = 10
        case .bracket: words = "my \(a) tp 2 sl 1\(on)"; pct = 10; stopPct = -10
        case .trailingStop: words = "trail my \(a) by 10%\(on)"
        case .twap: words = "buy $20 of \(a) over a day\(on)"
        case .bridge: words = "move 10 usdc from \(chain) to \(bridgeTarget(from: chain))"
        default: return nil
        }
        guard var t = TradeIntent.parse(words), t.kind == kind else { return nil }
        if let pct {
            t.price = nil
            t.pricePercent = pct
        }
        if let stopPct {
            t.stopPrice = nil
            t.stopPercent = stopPct
        }
        return t
    }

    /// A starter's prices set from the market's: `pricePercent` and
    /// `stopPercent` away from it, rounded the way people say prices.
    static func priced(_ intent: TradeIntent, market: Double) -> TradeIntent {
        guard market > 0 else { return intent }
        var t = intent
        if let p = t.pricePercent {
            t.price = roundPrice(market * (1 + p / 100))
            t.pricePercent = nil
        }
        if let p = t.stopPercent {
            t.stopPrice = roundPrice(market * (1 + p / 100))
            t.stopPercent = nil
        }
        return t
    }

    /// $3,180 not $3,183.42; $142 not $142.37; cents under $100.
    static func roundPrice(_ v: Double) -> String {
        let step: Double = v >= 1000 ? 10 : v >= 100 ? 1 : v >= 1 ? 0.01 : 0.0001
        let r = (v / step).rounded() * step
        // Two decimals at most below $100, so 0.1 steps don't print 141.70000001.
        return step < 1 ? TradeIntent.trimmed((r * 10_000).rounded() / 10_000) : TradeIntent.trimmed(r)
    }

    // MARK: 0G

    /// The last 0G answer from GET /ai/receipts (newest first; `at` in
    /// milliseconds): how long ago, and whether it ran in a verified TEE.
    static func status(receipts: [[String: Any]]?, loaded: Bool, now: Date = Date()) -> (last: String, tee: String) {
        guard loaded else { return ("…", "…") }
        guard let receipts else { return ("—", "—") }
        guard let last = receipts.first else { return ("None yet", "—") }
        var when = "—"
        if let at = (last["at"] as? NSNumber)?.doubleValue {
            when = ago(Date(timeIntervalSince1970: at / 1000), now: now)
        }
        let tee = (last["teeVerified"] as? Bool) == true ? "Verified" : "Not verified"
        return (when, tee)
    }

    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86_400 { return "\(s / 3600) h ago" }
        return "\(s / 86_400) d ago"
    }
}
