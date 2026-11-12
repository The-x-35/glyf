import Foundation

/// A buy repeated on a schedule ("dca $20 in eth each month", "invest 100
/// usdc in sol monthly", "buy $50 of btc every week for 3 months"), read on
/// the phone and placed as one Definitive Flash TWAP.
///
/// Flash runs a TWAP for 10 minutes to 30 days (flash.definitive.fi/docs,
/// order types; the quote API's floor is 300 s). A plan longer than that is
/// placed as its first 30 days: the order spends what those periods would,
/// and the panel says how much of the plan it covers ("1 of 12 months").
struct RecurringPlan: Equatable {
    enum Period: String {
        case hour, day, week, month

        var seconds: Int {
            switch self {
            case .hour: return 3600
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            }
        }

        /// "monthly", "weekly": how the chip says it.
        var adverb: String {
            switch self {
            case .hour: return "hourly"
            case .day: return "daily"
            case .week: return "weekly"
            case .month: return "monthly"
            }
        }

        /// Periods in a plan nobody gave a length for: a year of months, a
        /// month of weeks, a week of days, a day of hours.
        var defaultCount: Int {
            switch self {
            case .hour: return 24
            case .day: return 7
            case .week: return 4
            case .month: return 12
            }
        }
    }

    /// Dollars spent each period.
    var every: String
    var period: Period
    /// Periods between buys ("every 2 weeks" = 2).
    var interval: Int = 1
    /// How many buys the plan has.
    var periods: Int
    /// How many of them this one Flash order covers (all, unless the plan
    /// runs past Flash's 30 days).
    var placed: Int

    /// Flash's longest TWAP.
    static let flashMaxSeconds = 30 * 86_400
    /// Flash's shortest (the quote API's floor).
    static let flashMinSeconds = 300

    var capped: Bool { placed < periods }

    /// "$20 monthly", "$50 every 2 weeks".
    var cadence: String {
        interval == 1 ? "$\(every) \(period.adverb)" : "$\(every) every \(interval) \(period.rawValue)s"
    }

    /// "12 months", "1 week".
    static func count(_ n: Int, _ unit: String) -> String { n == 1 ? "1 \(unit)" : "\(n) \(unit)s" }

    /// What the panel shows under the amount: "$20 monthly · 12 months".
    var summary: String { "\(cadence) · \(Self.count(periods * interval, period.rawValue))" }

    /// Said only when Flash can't hold the whole plan: "Flash runs 30 days
    /// at most · 1 of 12 months".
    var capNote: String? {
        capped ? "Flash runs 30 days at most · \(placed) of \(periods) \(period.rawValue)s" : nil
    }
}

extension TradeIntent {

    /// Builds the Flash TWAP for a plan of `periods` buys of `every` dollars.
    static func recurringBuy(every: Double, of asset: String, with spend: String? = nil,
                             period: RecurringPlan.Period, interval: Int = 1,
                             periods: Int?, chain: String?) -> TradeIntent? {
        guard every > 0, every <= 1_000_000, interval >= 1, interval <= 12,
              symbols.values.contains(asset), !["USDC", "USDT", "DAI"].contains(asset) else { return nil }
        let step = period.seconds * interval
        let total = max(1, min(periods ?? period.defaultCount, 520))
        let fits = max(1, RecurringPlan.flashMaxSeconds / step)
        let placed = min(total, fits)
        let duration = min(RecurringPlan.flashMaxSeconds, max(RecurringPlan.flashMinSeconds, placed * step))
        let sell = spend.flatMap { ["USDC", "USDT", "DAI"].contains($0) ? $0 : nil } ?? stableFor(asset)
        var i = TradeIntent(kind: .twap, amount: trimmed(every * Double(placed)), sell: sell, buy: asset,
                            chain: chain.flatMap { chains[$0.lowercased()] ?? (chainLabels[$0] != nil ? $0 : nil) }
                                ?? (asset == "SOL" ? "solana" : nil))
        i.amountIsUSD = true
        i.durationSeconds = duration
        i.plan = RecurringPlan(every: trimmed(every), period: period, interval: interval, periods: total, placed: placed)
        return i
    }

    /// The trade panel's Over row for a plan, while the order is still the
    /// one the plan made (an amount or length changed in the panel ends it):
    /// "Over · Flash max" "30 days · month 1 of 12", or "Over" "4 weeks ·
    /// $20 weekly". One row: the panel has no room for more.
    var planOverRow: (label: String, value: String)? {
        guard kind == .twap, let plan, let every = Double(plan.every),
              amount == TradeIntent.trimmed(every * Double(plan.placed)),
              durationSeconds == min(RecurringPlan.flashMaxSeconds,
                                     max(RecurringPlan.flashMinSeconds, plan.placed * plan.period.seconds * plan.interval))
        else { return nil }
        let span = TradeIntent.span(durationSeconds).replacingOccurrences(of: "over ", with: "")
        guard plan.capped else { return ("Over", "\(span) · \(plan.cadence)") }
        let unit = plan.period.rawValue
        let part = plan.placed == 1 ? "\(unit) 1 of \(plan.periods)" : "\(unit)s 1–\(plan.placed) of \(plan.periods)"
        return ("Over · Flash max", "\(span) · \(part)")
    }

    /// The chip's words for a plan: "DCA $20 of ETH monthly".
    var planTitle: String? {
        guard let plan else { return nil }
        let cadence = plan.interval == 1 ? plan.period.adverb : "every \(plan.interval) \(plan.period.rawValue)s"
        return "DCA $\(plan.every) of \(buy) \(cadence)"
    }

    // "dca $20 in eth each month", "dca 20$ eth weekly", "invest 100 usdc in
    // sol monthly", "buy $50 of btc every week for 3 months".
    static func recurring(_ text: String) -> TradeIntent? {
        var t = String(text.suffix(200))
        let lower = t.lowercased()
        guard ["dca", "invest", "buy", "stack", "put", "auto"].contains(where: lower.contains) else { return nil }
        // Two-week words first: "bi-weekly" holds "weekly".
        for (said, meant) in [("bi-?weekly", "every 2 weeks"), ("fortnightly", "every 2 weeks"),
                              ("every other (day|week|month)", "every 2 $1s"),
                              ("everyday", "every day"), ("daily", "every day"), ("weekly", "every week"),
                              ("hourly", "every hour"), ("monthly", "every month")] {
            t = t.replacingOccurrences(of: #"\b\#(said)\b"#, with: meant, options: [.regularExpression, .caseInsensitive])
        }
        let n = #"(\d+(?:[.,]\d+)?k?)"#
        let sym = #"(eth|ether|weth|wbtc|btc|bitcoin|cbbtc|uni|link|aave|op|arb|pol|matic|aero|degen|sol|solana|pepe|ldo)"#
        let words = #"(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+)"#
        let unit = #"(hour|day|week|month|year)s?"#
        let pattern = #"(?:^|[.!?\n]\s*|\b(?:pls|please|glyf|hey glyf)[,:]?\s+)"#
            + #"(?:(?:set\s+up\s+(?:a\s+)?)?(?:dca|auto[- ]?buy|recurring\s+buy|invest|stack|put|buy))\s+"#
            + #"(?:\$\s?"# + n + "|" + n + #"\s?(?:\$|usd\b|dollars?\b|bucks\b|(usdc|usdt|dai)\b))"#
            + #"(?:\s+(?:of|worth\s+of|into|in|on))?\s+"# + sym
            + #"\s+(?:every|each|a|per)\s+(?:"# + words + #"\s+)?(hour|day|week|month)s?"#
            + #"(?:\s+for\s+(?:the\s+next\s+)?"# + words + #"\s+"# + unit + ")?"
            + #"(?:\s+on\s+(base|ethereum|mainnet|arbitrum|optimism|polygon|unichain|solana))?"#
            + #"\s*[.!]?\s*$"#
        guard let m = groups(pattern, t),
              let each = Double(amount(m[1] ?? m[2]) ?? ""),
              let asset = symbol(m[4]),
              let period = RecurringPlan.Period(rawValue: (m[6] ?? "").lowercased())
        else { return nil }
        let interval = m[5].map(number) ?? 1
        var periods: Int?
        if let howMany = m[7], let span = m[8]?.lowercased() {
            let spanSeconds = number(howMany) * (span == "year" ? 365 * 86_400 : RecurringPlan.Period(rawValue: span)?.seconds ?? 86_400)
            // "every week for 3 months": 13 weeks; "monthly for a year": 12.
            let step = period.seconds * interval
            periods = span == "year" && period == .month ? number(howMany) * 12 / interval
                : max(1, Int((Double(spanSeconds) / Double(step)).rounded()))
        }
        return recurringBuy(every: each, of: asset, with: symbol(m[3]), period: period, interval: interval,
                            periods: periods, chain: m[9])
    }

    private static func number(_ word: String) -> Int {
        ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
         "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12][word.lowercased()] ?? Int(word) ?? 1
    }

    private static func groups(_ pattern: String, _ text: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}
