import ActivityKit
import Foundation

/// A trade in flight, on the Lock Screen and in the Dynamic Island: placing,
/// waiting on the wallet that signs it, placed or sent, confirmed or failed.
/// The app starts and updates it from each step of the trade screen
/// (TradeActivityHost, lib/evm/trade_activity.dart); no server push. Compiled
/// into the app and the GlyfVoiceWidget extension, which draws it.
struct GlyfTradeAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable, CaseIterable {
        case placing, waiting, placed, submitted, confirmed, failed

        /// Still moving: the Island shows a spinner and no Done.
        var inFlight: Bool { self == .placing || self == .waiting }
        var finished: Bool { self == .confirmed || self == .failed }
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// The trade screen's own words: "Sign the stop-loss in Phantom".
        var title: String
        var detail: String?
        /// Who signs: "Phantom", "MetaMask", "Glyf wallet".
        var wallet: String?
        /// The explorer (Solscan, Basescan) or Definitive's order page.
        var link: String?
        var orderId: String?
        var updated: Date
    }

    /// One trade screen's run.
    var tradeId: String
    /// TradeIntent's kind: swap, stop-loss, take-profit, limit, bracket…
    var kind: String
    /// "SOL → USDC".
    var pair: String
    /// "0.5 SOL" or "$20".
    var amount: String?
    /// "at $140", "trail 5%".
    var trigger: String?
    /// "Solana", "Base".
    var chain: String
    /// A Flash order on an Ethereum chain: Flash's cancel message is signed
    /// there (lib/evm/flash_orders.dart); Solana's has no cancel yet.
    var cancellable: Bool
}

/// The pure half of the trade activity: what the trade screen hands over
/// (its query and each TradeOutcome) turned into the activity's data.
enum GlyfTradeActivity {
    static let flashKinds: Set<String> = ["limit", "stop", "stop-loss", "take-profit", "bracket", "trailing-stop", "twap"]

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "swap": return "Swap"
        case "send": return "Send"
        case "request": return "Request"
        case "limit": return "Limit"
        case "stop": return "Stop buy"
        case "stop-loss": return "Stop-loss"
        case "take-profit": return "Take profit"
        case "bracket": return "Bracket"
        case "trailing-stop": return "Trailing stop"
        case "twap": return "TWAP"
        case "bridge": return "Bridge"
        default: return "Trade"
        }
    }

    static func chainLabel(_ chain: String?) -> String {
        switch (chain ?? "base").lowercased() {
        case "solana": return "Solana"
        case "ethereum", "mainnet": return "Ethereum"
        case "arbitrum": return "Arbitrum"
        case "optimism": return "Optimism"
        case "polygon": return "Polygon"
        case "whitechain": return "Whitechain"
        case "sepolia", "base-sepolia": return "Testnet"
        default: return "Base"
        }
    }

    /// The trade's fixed facts, read from TradeIntent's query.
    static func attributes(id: String, query q: [String: String]) -> GlyfTradeAttributes {
        let kind = q["kind"] ?? "swap"
        let sell = (q["sell"] ?? "").uppercased()
        let buy = (q["buy"] ?? "").uppercased()
        let pair: String
        switch kind {
        case "send": pair = q["to"].map { "\(sell) → \($0)" } ?? sell
        case "request": pair = sell.isEmpty ? buy : sell
        default: pair = [sell, buy].filter { !$0.isEmpty }.joined(separator: " → ")
        }
        var amount: String?
        if let a = q["amount"], !a.isEmpty {
            amount = q["usd"] == "1" ? "$\(a)" : "\(a) \(sell)".trimmingCharacters(in: .whitespaces)
        } else if let b = q["buyAmount"], !b.isEmpty {
            amount = "\(b) \(buy)".trimmingCharacters(in: .whitespaces)
        }
        var trigger: String?
        if let t = q["trail"], !t.isEmpty {
            trigger = "trail \(t)%"
        } else if let p = q["price"], !p.isEmpty {
            trigger = q["stopPrice"].map { "$\(p) / $\($0)" } ?? "at $\(p)"
        } else if let s = q["stopPrice"], !s.isEmpty {
            trigger = "stop $\(s)"
        } else if let d = q["duration"].flatMap(Int.init), d > 0 {
            trigger = d % 86400 == 0 ? "over \(d / 86400)d" : "over \(max(1, d / 3600))h"
        }
        let chain = q["chain"]
        return GlyfTradeAttributes(
            tradeId: id, kind: kind, pair: pair.isEmpty ? kindLabel(kind) : pair,
            amount: amount, trigger: trigger, chain: chainLabel(chain),
            cancellable: flashKinds.contains(kind) && chain?.lowercased() != "solana")
    }

    /// One TradeOutcome as the activity shows it. `state` is TradeState's
    /// name (working, done, submitted, failed); a working step that waits on
    /// the wallet (it can reopen it, or names it) is `waiting`.
    static func content(kind: String, state: String, title: String, detail: String?,
                        wallet: String?, link: String?, orderId: String?, reopen: Bool,
                        now: Date = Date()) -> GlyfTradeAttributes.ContentState {
        let phase: GlyfTradeAttributes.Phase
        switch state {
        case "done": phase = flashKinds.contains(kind) || kind == "bridge" ? .placed : .confirmed
        case "submitted": phase = .submitted
        case "failed": phase = .failed
        default:
            let t = title.lowercased()
            let waits = reopen || t.hasPrefix("sign ") || t.hasPrefix("approve ") || t.hasPrefix("let flash")
                || (wallet.map { t.contains($0.lowercased()) } ?? false)
            phase = waits ? .waiting : .placing
        }
        return .init(phase: phase, title: title, detail: detail, wallet: wallet,
                     link: link.flatMap { $0.hasPrefix("https://") ? $0 : nil },
                     orderId: orderId, updated: now)
    }

    /// Which wallet a step names ("Sign the order in Phantom", "…: confirm
    /// in MetaMask"); Solana's orders are always Phantom's.
    static func wallet(in title: String, chain: String) -> String? {
        let t = title.lowercased()
        if t.contains("phantom") { return "Phantom" }
        if t.contains("metamask") { return "MetaMask" }
        return chain == "Solana" ? "Phantom" : nil
    }

    /// The word on the compact Island's right.
    static func status(_ s: GlyfTradeAttributes.ContentState) -> String {
        switch s.phase {
        case .placing: return "Placing"
        case .waiting: return s.wallet ?? "Sign"
        case .placed: return "Placed"
        case .submitted: return "Sent"
        case .confirmed: return "Done"
        case .failed: return "Failed"
        }
    }

    /// The line under the pair: "Waiting for Phantom", "Placed on Solana".
    static func headline(_ s: GlyfTradeAttributes.ContentState, chain: String) -> String {
        switch s.phase {
        case .placing: return "Placing…"
        case .waiting: return "Waiting for \(s.wallet ?? "your wallet")"
        case .placed: return "Placed on \(chain)"
        case .submitted: return "Submitted, confirming"
        case .confirmed: return "Confirmed on \(chain)"
        case .failed: return s.title
        }
    }

    /// How long a finished trade stays on the Lock Screen. A placed Flash
    /// order isn't ended at all: its Cancel stays until the order is gone
    /// or iOS's eight hours run out.
    static func dismissal(_ phase: GlyfTradeAttributes.Phase) -> TimeInterval? {
        switch phase {
        case .confirmed: return 15 * 60
        case .failed: return 5 * 60
        case .submitted: return 30 * 60
        case .placing, .waiting, .placed: return nil
        }
    }

    /// The link's name on the expanded Island.
    static func linkLabel(_ link: String?) -> String {
        guard let link else { return "View" }
        if link.contains("definitive.fi") { return "Definitive" }
        if link.contains("solscan") { return "Solscan" }
        if link.contains("basescan") { return "Basescan" }
        if link.contains("etherscan") { return "Etherscan" }
        if link.contains("arbiscan") { return "Arbiscan" }
        return "Explorer"
    }

    /// Where Open lands: the order list for Flash, the wallet otherwise.
    static func openURL(kind: String, chain: String) -> URL {
        if chain == "Solana" { return URL(string: "glyf://open?path=wallet")! }
        return URL(string: "glyf://open?path=evm-wallet")!
    }

    /// Cancel from the Island: the app opens on Flash's cancel for the order.
    static func cancelURL(orderId: String) -> URL? {
        var c = URLComponents(string: "glyf://open")
        c?.queryItems = [.init(name: "path", value: "flash-cancel"), .init(name: "id", value: orderId)]
        return c?.url
    }
}
