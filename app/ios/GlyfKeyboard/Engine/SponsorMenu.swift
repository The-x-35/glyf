import Foundation

/// The g menu's top row: the apps Glyf trades and thinks through (ETHGlobal
/// Mumbai): Uniswap swaps, Definitive's Flash orders, 0G's Private AI. Pure,
/// so RunnerTests pins which icons show and what each tap does.
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
    }

    /// What a tap does.
    enum Action: Equatable {
        /// The trade panel, with this trade on it, as if it had been typed.
        case trade(TradeIntent)
        /// Says Private AI on 0G is on, with the last answer's receipt.
        case privateAIStatus
        /// One hop to the app (Keyboard settings, where Private AI is turned on).
        case openApp(path: String)
    }

    /// Uniswap's starter: a small swap on Base, ready to sign in the app.
    static let swapStarter = "swap 10 usdc to eth on base"
    /// Definitive's starter: a stop that follows ETH up and sells on a 10% fall.
    /// It needs no price, so it never sits on the wrong side of the market.
    static let flashStarter = "trail my eth by 10%"

    /// Uniswap and Definitive always; 0G only where the app wrote the
    /// `privateAI` setting (the hackathon build; other builds leave it unset).
    static func sponsors(privateAI: Bool?) -> [Sponsor] {
        privateAI == nil ? [.uniswap, .definitive] : Sponsor.allCases
    }

    /// A trade already typed for that venue is the one shown; otherwise the
    /// starter. `typed` is the text before the cursor.
    static func action(for sponsor: Sponsor, typed: String, privateAI: Bool?) -> Action {
        switch sponsor {
        case .uniswap:
            if let t = TradeIntent.parse(typed), t.kind == .swap { return .trade(t) }
            return .trade(TradeIntent.parse(swapStarter)!)
        case .definitive:
            if let t = TradeIntent.parse(typed), t.venue == "Flash" { return .trade(t) }
            return .trade(TradeIntent.parse(flashStarter)!)
        case .zeroG:
            return privateAI == true ? .privateAIStatus : .openApp(path: "settings")
        }
    }

    /// The toast for an on switch: the last 0G answer from GET /ai/receipts
    /// (newest first; `at` in milliseconds), or that there is none yet.
    static func statusLine(receipts: [[String: Any]]?, now: Date = Date()) -> String {
        let head = "Private AI on 0G is on"
        guard let receipts else { return head }
        guard let last = receipts.first else { return "\(head) · no answers yet" }
        var parts = [head]
        if let at = (last["at"] as? NSNumber)?.doubleValue {
            parts.append("last " + ago(Date(timeIntervalSince1970: at / 1000), now: now))
        }
        if (last["teeVerified"] as? Bool) == true { parts.append("TEE verified") }
        return parts.joined(separator: " · ")
    }

    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86_400 { return "\(s / 3600) h ago" }
        return "\(s / 86_400) d ago"
    }
}
