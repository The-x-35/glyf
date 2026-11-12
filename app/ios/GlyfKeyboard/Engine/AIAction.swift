import Foundation

/// The strip's recommended action from POST /suggest (server lib/actions.ts):
/// the suggestion model read the pause as a job for one of Glyf's tools and
/// named it with its values, checked on the server. A tap opens that tool
/// with the values filled in, for the person to check and change; nothing
/// runs from the strip.
///
/// Trades go through the same reader as typed words (TradeIntent.parse), so
/// the AI's "stop-loss ETH at 3000" opens the very panel the words would.
struct AIAction: Equatable {
    var tool: String
    var label: String
    var params: [String: String]

    /// The server's `action` object; nil for anything this phone can't open.
    static func from(json: [String: Any]) -> AIAction? {
        guard let tool = json["tool"] as? String, let label = json["label"] as? String,
              label.count <= 80 else { return nil }
        var params: [String: String] = [:]
        for (k, v) in json["params"] as? [String: Any] ?? [:] {
            switch v {
            case let s as String: params[k] = s
            case let b as Bool: params[k] = b ? "true" : "false"
            case let n as NSNumber: params[k] = TradeIntent.trimmed(n.doubleValue)
            default: break
            }
        }
        let a = AIAction(tool: tool, label: label, params: params)
        return a.chip == nil ? nil : a
    }

    /// The words a person would type for a trade, read by TradeIntent.
    var tradeWords: String? {
        let p = params
        let on = p["chain"].map { " on \($0)" } ?? ""
        switch tool {
        case "trade.swap":
            guard let sell = p["sell"], let buy = p["buy"] else { return nil }
            if p["usd"] == "true", let a = p["amount"] { return "buy $\(a) of \(buy) with \(sell)\(on)" }
            return "swap \(p["amount"].map { "\($0) " } ?? "")\(sell) to \(buy)\(on)"
        case "trade.flash":
            guard let type = p["type"], let asset = p["asset"] else { return nil }
            let held = p["amount"].map { "\($0) " } ?? ""
            let price = p["price"] ?? ""
            switch type {
            case "limit":
                if p["side"] == "sell" { return "sell \(held)\(asset) at \(price)\(on)" }
                if p["usd"] == "true", let a = p["amount"] { return "buy $\(a) of \(asset) at \(price)\(on)" }
                return "buy \(held)\(asset) at \(price)\(on)"
            case "stop": return "buy \(asset) if it breaks \(price)\(on)"
            case "stop-loss": return "stop loss \(held)\(asset) at \(price)\(on)"
            case "take-profit": return "take profit \(held)\(asset) at \(price)\(on)"
            case "bracket":
                guard let stop = p["stopPrice"] else { return nil }
                return "\(held)\(asset) tp \(price) sl \(stop)\(on)"
            case "trailing-stop":
                guard let trail = p["trailPercent"] else { return nil }
                return "trail \(held)\(asset) by \(trail)%\(on)"
            case "twap":
                guard let a = p["amount"], let h = p["hours"].flatMap(Double.init), h >= 1 else { return nil }
                let span = h.truncatingRemainder(dividingBy: 24) == 0 ? "\(Int(h / 24)) days" : "\(Int(h.rounded())) hours"
                return "buy $\(a) of \(asset) over \(span)\(on)"
            default: return nil
            }
        case "trade.bridge":
            guard let a = p["amount"], let asset = p["asset"], let from = p["from"], let to = p["to"] else { return nil }
            return "move \(a) \(asset) from \(from) to \(to)"
        case "near.swap":
            // Each side on its chain, as the server read it (a coin with no
            // chain said sits at home, else on Base): the words then read
            // the same however they were typed. No amount: the panel asks.
            guard let sell = p["sell"], let buy = p["buy"] else { return nil }
            let from = p["sellChain"] ?? TradeIntent.nativeChain[sell.uppercased()] ?? "base"
            let into = p["buyChain"] ?? TradeIntent.nativeChain[buy.uppercased()] ?? "base"
            return "swap \(p["amount"] ?? "1") \(sell) on \(from) to \(buy) on \(into)"
        case "near.send":
            guard let a = p["amount"], let to = p["to"] else { return nil }
            var words = "send \(a) \(p["coin"] ?? "USDC") to \(to)"
            if let with = p["with"] { words += " with \(with)" + (p["withChain"].map { " on \($0)" } ?? "") }
            else if let from = p["withChain"] { words += " from \(from)" }
            return words
        case "near.earn":
            let coin = p["coin"] ?? "USDC"
            if p["out"] == "true" {
                let what = p["amount"].map { "\($0) \(coin)" } ?? "my \(coin)"
                return "take \(what) out of earn" + (p["chain"].map { " to \($0)" } ?? "")
            }
            guard let a = p["amount"] else { return nil }
            return "put \(a) \(coin)" + (p["chain"].map { " on \($0)" } ?? "") + " to work"
        default:
            return nil
        }
    }

    /// The trade the action opens, filled in.
    var trade: TradeIntent? {
        if tool == "trade.dca" {
            guard let every = params["every"].flatMap(Double.init),
                  let asset = TradeIntent.symbol(params["asset"]),
                  let period = params["period"].flatMap(RecurringPlan.Period.init(rawValue:)) else { return nil }
            return TradeIntent.recurringBuy(every: every, of: asset, with: TradeIntent.symbol(params["spend"]),
                                            period: period, periods: params["periods"].flatMap { Int($0) },
                                            chain: params["chain"])
        }
        if tool == "near.earn", tradeWords == nil {
            // "put usdc to work": no amount said, so the panel asks for it.
            return TradeIntent.earn(coin: params["coin"] ?? "USDC", amount: nil, out: false, chain: params["chain"])
        }
        guard var t = tradeWords.flatMap({ TradeIntent.parse($0) }) else { return nil }
        // A NEAR Intents tool opens NEAR Intents' panel, never Uniswap's.
        if tool.hasPrefix("near."), !t.isNear { return nil }
        if tool == "near.swap", params["amount"] == nil { t.amount = nil }
        return t
    }

    /// The chip it shows as; nil when this phone can't open it.
    var chip: Smart.Chip? {
        if tool.hasPrefix("trade.") || ["near.swap", "near.send", "near.earn"].contains(tool) { return trade.map { .trade($0) } }
        switch tool {
        case "calendar.event":
            guard let title = params["title"], let when = params["when"] else { return nil }
            let plan = EventParse.parse("\(title) \(when)")
            return plan.hasDay || plan.hasTime ? .event(plan: plan) : nil
        case "meet.link": return .action(label: "Add a Meet link", query: "", intent: "meet")
        case "search", "youtube", "shorts", "maps":
            guard let q = params["query"], !q.isEmpty else { return nil }
            return .action(label: label, query: q, intent: "open:\(tool)")
        case "translate":
            guard let to = params["to"], !to.isEmpty else { return nil }
            return .action(label: label, query: to.prefix(1).uppercased() + to.dropFirst().lowercased(),
                           intent: "open:translate")
        case "rewrite": return .action(label: label, query: "", intent: "rewrite")
        case "convert": return .action(label: label, query: params["query"] ?? "", intent: "answer")
        // A pay link to ask for, and the group pot: their panels read the
        // params back from the query (NearPay.swift).
        case "near.request":
            guard PayAsk(params: params) != nil else { return nil }
            return .action(label: label, query: params.chipQuery, intent: "near:request")
        case "near.pot", "near.pot.pay":
            guard PotAsk(params: params, pay: tool == "near.pot.pay") != nil else { return nil }
            return .action(label: label, query: params.chipQuery, intent: tool == "near.pot" ? "near:pot" : "near:pot.pay")
        default: return nil
        }
    }
}
