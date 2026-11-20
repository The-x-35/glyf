import Foundation
import UIKit

/// A pay link to ask for (POST /near/requests; docs/NEAR-SPEC.md, Hand-off:
/// the keyboard's Request button): from the bill split's chip ("$22.50
/// each") or the strip AI's near.request. The keyboard adds where the
/// person is paid and posts it; the answer's `text` goes in the chat as is.
struct PayAsk: Equatable {
    /// The total when `each` is false and `count` is set; each payer's
    /// share when `each` is true. As typed ("22.5", "1200").
    var amount: String
    var coin: String? = nil
    /// Where the requester wants to be paid, when the words said.
    var chain: String? = nil
    var each = false
    var count: Int? = nil
    /// The writer is one of `count` ("$90 for 4 of us").
    var us = false
    var note: String? = nil

    /// The near.request action's params, as they came (checked on the server).
    init?(params p: [String: String]) {
        guard let amount = p["amount"], Double(amount) != nil else { return nil }
        self.amount = amount
        coin = p["coin"]
        chain = p["chain"]
        each = p["each"] == "true"
        count = p["count"].flatMap { Int($0) ?? Double($0).map { Int($0) } }
        us = p["us"] == "true"
        note = p["note"]
    }

    init(amount: String, coin: String? = nil, chain: String? = nil, each: Bool = false, count: Int? = nil,
         us: Bool = false, note: String? = nil) {
        self.amount = amount
        self.coin = coin
        self.chain = chain
        self.each = each
        self.count = count
        self.us = us
        self.note = note
    }

    /// The bill split's ask: the total and the headcount, "of us" or "we"
    /// making the writer one of them, and what it was for when the words
    /// lead with it ("dinner was $90 for 4 of us"). Dollars only: a pay
    /// link is paid in USDC.
    static func split(text: String, total: Double, count: Int) -> PayAsk {
        let lower = text.lowercased()
        let us = lower.range(of: #"\b(of us|we)\b"#, options: .regularExpression) != nil
        return PayAsk(amount: TradeIntent.trimmed((total * 100).rounded() / 100), count: count, us: us,
                      note: billNote(lower))
    }

    /// What a bill was for: "dinner was $90…", "the cabin is $1,200…",
    /// "split the cab $60…". Words that only say it's a bill don't count.
    static func billNote(_ lower: String) -> String? {
        let patterns = [
            #"(?:^|[.!?]\s*)(?:the\s+|our\s+)?([a-z]{3,20})\s+(?:was|is|came to|cost|costs)\s+\$"#,
            #"\bsplit\s+(?:the\s+|our\s+)?([a-z]{3,20})\s+(?:of\s+)?\$"#,
        ]
        let plain: Set<String> = ["bill", "check", "total", "tab", "cost", "amount", "it", "that", "this", "price"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let r = Range(m.range(at: 1), in: lower) else { continue }
            let word = String(lower[r])
            if !plain.contains(word) { return word }
        }
        return nil
    }

    /// The requester's own receiving address: on the chain asked, the
    /// wallet there (Phantom on Solana, MetaMask on EVM chains, the saved
    /// NEAR account on NEAR); with none asked, MetaMask on Base, else the
    /// NEAR account. Nil: no wallet to be paid in ("Add a wallet in Glyf to
    /// get paid"), and nothing is posted.
    static func receiver(chain: String?, evm: String?, solana: String?, near: String?) -> (to: String, chain: String)? {
        func has(_ s: String?) -> String? { (s ?? "").isEmpty ? nil : s }
        if let chain {
            if chain == "solana" { return has(solana).map { ($0, chain) } }
            if chain == "near" { return has(near).map { ($0, chain) } }
            if TradeIntent.evmChains.contains(chain) { return has(evm).map { ($0, chain) } }
            return nil
        }
        if let e = has(evm) { return (e, "base") }
        if let n = has(near) { return (n, "near") }
        return nil
    }

    /// POST /near/requests' body.
    func body(to: String, chain: String) -> [String: Any] {
        var b: [String: Any] = ["amount": amount, "to": to, "chain": chain]
        if let coin { b["coin"] = coin }
        if each { b["each"] = true }
        if let count { b["count"] = count }
        if us { b["us"] = true }
        if let note, !note.isEmpty { b["note"] = note }
        return b
    }

    static let noWallet = "Add a wallet in Glyf to get paid"
}

/// A look at the group pot, or a payout from it to propose (docs/NEAR-SPEC.md,
/// The group pot on Sputnik DAO): read from the words on the phone ("how
/// much is in the trip pot", "pay the caterer $120 from the pot") or named
/// by the strip's AI (near.pot, near.pot.pay).
struct PotAsk: Equatable {
    var pay: Bool
    /// The word before "pot" ("trip"), which the saved pot stands for.
    var pot: String? = nil
    /// A typed *.sputnik-dao.near.
    var dao: String? = nil
    /// Who's paid: a NEAR account, or the words for them ("the caterer").
    var to: String? = nil
    var amount: String? = nil
    var coin = "USDC"
    var note: String? = nil

    init(pay: Bool, pot: String? = nil, dao: String? = nil, to: String? = nil, amount: String? = nil,
         coin: String = "USDC", note: String? = nil) {
        self.pay = pay
        self.pot = pot
        self.dao = dao
        self.to = to
        self.amount = amount
        self.coin = coin
        self.note = note
    }

    /// The action's params (near.pot, near.pot.pay).
    init?(params p: [String: String], pay: Bool) {
        self.pay = pay
        pot = p["pot"]
        dao = p["dao"]
        to = p["to"]
        amount = p["amount"]
        coin = (p["coin"] ?? "USDC").uppercased()
        note = p["note"]
        if pay, to == nil || amount == nil { return nil }
    }

    var params: [String: String] {
        var p: [String: String] = [:]
        if let pot { p["pot"] = pot }
        if let dao { p["dao"] = dao }
        if let to { p["to"] = to }
        if let amount { p["amount"] = amount }
        if pay { p["coin"] = coin }
        if let note { p["note"] = note }
        return p
    }

    /// "trip pot", or "pot".
    var potName: String {
        if let dao { return dao.replacingOccurrences(of: ".sputnik-dao.near", with: "") + " pot" }
        return pot.map { "\($0) pot" } ?? "pot"
    }

    /// "$120", "5 NEAR".
    static func money(_ amount: String, _ coin: String) -> String {
        coin == "USDC" ? TradeIntent.dollars(amount) : "\(amount) \(coin)"
    }

    /// The chip's words, the server's (lib/actions.ts actionLabel).
    var label: String {
        guard pay, let to, let amount else { return "See the \(potName) · Sputnik DAO" }
        let who = to.replacingOccurrences(of: #"^the\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        return "Propose \(Self.money(amount, coin)) to \(who) from the \(potName) · Sputnik DAO"
    }

    /// The pot meant: the typed DAO, else the saved pot (or a Sputnik DAO
    /// saved as the NEAR account), else the word's ("trip" →
    /// trip.sputnik-dao.near). Nil: "Add your pot in Glyf".
    func daoAccount(saved: String?, account: String?) -> String? {
        if let dao { return dao }
        if let s = saved?.lowercased(), Self.isDAO(s) { return s }
        if let a = account?.lowercased(), Self.isDAO(a) { return a }
        return pot.map { "\($0).sputnik-dao.near" }
    }

    static func isDAO(_ s: String) -> Bool {
        s.range(of: #"^[a-z0-9][a-z0-9_-]*\.sputnik-dao\.near$"#, options: .regularExpression) != nil
    }

    /// A NEAR account as Trezu pays it: a name.near or 64 hex.
    static func isNEARAccount(_ s: String) -> Bool {
        TradeIntent.nearRecipientChain(s.lowercased()) == "near"
    }

    static let noPot = "Add your pot in Glyf"

    // MARK: reading (server lib/nearphrase.ts parsePotPhrase, the same phrases)

    private static let potPattern = #"(?:(?:(?:the|our|my)\s+)?(?:([a-z][a-z0-9-]{1,20})\s+)?(?:pot|treasury|kitty)|([a-z0-9][a-z0-9_-]*\.sputnik-dao\.near))"#
    private static let notPotWord: Set<String> = ["the", "our", "my", "a", "shared", "group"]

    static func parse(_ text: String) -> PotAsk? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[.!?]$"#, with: "", options: .regularExpression)
        let lower = t.lowercased()
        guard lower.contains("pot") || lower.contains("treasury") || lower.contains("kitty") || lower.contains("sputnik")
        else { return nil }
        let balances = [
            #"^(?:how much|what)(?:'s| is| do we have)?\s+(?:left\s+)?in\s+"# + potPattern + #"(?:\s+left)?$"#,
            #"^(?:check|show(?:\s+me)?|open)\s+"# + potPattern + #"(?:\s+balance)?$"#,
            "^" + potPattern + #"\s+balance$"#,
        ]
        for p in balances {
            if let m = groups(p, lower) { return PotAsk(pay: false).named(word: m[1], dao: m[2]) }
        }
        let money = #"(?:\$\s?(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(usdc|usdt|near|dollars|bucks))"#
        let pay = #"^(?:pay|send|give)\s+((?:the\s+)?[a-z][a-z0-9._-]{0,63}(?:\s+[a-z][a-z0-9._-]{0,30})?)\s+"# + money
            + #"\s+(?:from|out of)\s+"# + potPattern + #"(?:\s+for\s+([a-z][a-z0-9 '&-]{1,40}))?$"#
        guard let m = groups(pay, lower), let payee = m[1] else { return nil }
        let dollars = m[2] != nil || ["dollars", "bucks"].contains(m[4] ?? "")
        var ask = PotAsk(pay: true, to: payee.trimmingCharacters(in: .whitespaces), amount: m[2] ?? m[3],
                         coin: dollars ? "USDC" : (m[4] ?? "usdc").uppercased(),
                         note: m[7]?.trimmingCharacters(in: .whitespaces))
        ask = ask.named(word: m[5], dao: m[6])
        return ask
    }

    private func named(word: String?, dao: String?) -> PotAsk {
        var a = self
        if let dao { a.dao = dao } else if let word, !Self.notPotWord.contains(word) { a.pot = word }
        return a
    }

    private static func groups(_ pattern: String, _ text: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } }
    }
}

/// GET /near/pot's answer, as the pot card shows it.
struct PotView: Equatable {
    var text: String?
    var dao: String?
    var trezu: String?
    struct Proposal: Equatable { var id: Int; var line: String; var url: String? }
    /// Open proposals (still taking votes), newest first.
    var open: [Proposal] = []
    var error: String?

    init(ok: Bool, _ obj: [String: Any]?) {
        guard ok, let obj, obj["ok"] as? Bool != false else {
            let words = obj?["error"] as? String
            error = (words?.isEmpty ?? true) ? "NEAR didn't answer. Try again in a moment" : words
            return
        }
        text = obj["text"] as? String
        dao = obj["dao"] as? String
        trezu = (obj["links"] as? [String: Any])?["trezu"] as? String
        for p in obj["proposals"] as? [[String: Any]] ?? [] where p["status"] as? String == "InProgress" {
            guard let id = TradeSurfaceNumbers.number(p["id"]).map({ Int($0) }) else { continue }
            open.append(Proposal(id: id, line: Self.line(p, id: id), url: p["url"] as? String))
        }
    }

    /// "#5 12.5 NEAR to caterer.near · 1 more approval"; a proposal that
    /// isn't a payout reads by its description.
    static func line(_ p: [String: Any], id: Int) -> String {
        var what: String
        if let amount = p["amount"] as? String, let coin = p["coin"] as? String, let to = p["receiver"] as? String {
            what = "\(amount) \(coin) to \(to)"
        } else {
            let d = ((p["description"] as? String) ?? "").split(separator: "\n").first.map(String.init) ?? ""
            what = d.isEmpty ? ((p["kind"] as? String) ?? "Proposal") : d
        }
        var line = "#\(id) \(what)"
        if let n = TradeSurfaceNumbers.number(p["approvalsNeeded"]).map({ Int($0) }), n > 0 {
            line += " · \(n) more approval\(n == 1 ? "" : "s")"
        }
        return line
    }
}

/// GET /near/pot/propose-link's answer, as the payout panel shows it.
struct PotProposal: Equatable {
    var url: String?
    var text: String?
    /// "Propose $120 to caterer.near": the card's bold line.
    var headline: String?
    /// "Needs 2 of 3 · bond 0.1 NEAR": the vote and its cost, under it.
    var terms: String?
    /// "Type 120 USDC, note: catering": what Trezu doesn't prefill.
    var fill: String?
    /// The person can't file it: "Only members can propose from this pot".
    var notMember = false
    var error: String?

    init(ok: Bool, _ obj: [String: Any]?, to: String, account: String?) {
        guard ok, let obj, obj["ok"] as? Bool != false else {
            let words = obj?["error"] as? String
            error = (words?.isEmpty ?? true) ? "NEAR didn't answer. Try again in a moment" : words
            return
        }
        url = obj["url"] as? String
        text = obj["text"] as? String
        let fill = obj["fill"] as? [String: Any]
        let amount = (fill?["amount"] as? String) ?? ""
        let coin = (fill?["coin"] as? String) ?? "USDC"
        headline = "Propose \(PotAsk.money(amount, coin)) to \(to)"
        var terms: [String] = []
        if let words = (obj["threshold"] as? [String: Any])?["words"] as? String { terms.append("Needs \(words)") }
        if let bond = obj["bond"] as? String { terms.append("bond \(bond) NEAR") }
        self.terms = terms.isEmpty ? nil : terms.joined(separator: " · ")
        let note = (fill?["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.fill = "Type \(amount) \(coin)" + (note.map { ", note: \($0)" } ?? "")
        if let list = obj["proposers"] as? [String] {
            notMember = !list.contains((account ?? "").lowercased())
        }
    }

    static let membersOnly = "Only members can propose from this pot"
}

extension Dictionary where Key == String, Value == String {
    /// The params a chip carries in its query, as JSON.
    var chipQuery: String {
        (try? JSONSerialization.data(withJSONObject: self, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    init(chipQuery: String) {
        let obj = chipQuery.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: String]
        self = obj ?? [:]
    }
}

/// How a whole chip's words fit the strip without "…" (D108): 15 pt down to
/// 11 pt in half points on one line; then the last " · " part goes whole (the
/// venue word, "Sputnik DAO"), then the grey label, fitted again; then the
/// chip's shorter words when it has them (a bill split's answer alone,
/// "$22.50 each", rather than "$90 for the four of us =" with the answer cut
/// off); and when even that is too wide at 11 pt ("Propose $120 to caterer
/// from the build pot"), it wraps onto two lines, 13 pt down to 11 pt, rather
/// than being cut mid-word.
enum ChipFit {
    struct Fit: Equatable {
        var parts: [String]
        var label: String?
        var size: CGFloat
        var lines: Int
        var text: String { parts.joined(separator: " · ") }
    }

    /// What a whole chip says when its words don't fit: a sum's answer
    /// without its question ("$22.50 each"), a payout without its pot
    /// ("Propose $120 to caterer"; the panel names the pot).
    static func shorter(_ chip: Smart.Chip) -> String? {
        switch chip {
        case .convert(let c) where !c.source.isEmpty:
            return c.results.joined(separator: " · ")
        case .action(_, _, let intent) where intent == "near:pot.pay":
            let short = chip.value.replacingOccurrences(of: #" from the [^·]*?(?= · |$)"#, with: "", options: .regularExpression)
            return short == chip.value ? nil : short
        default:
            return nil
        }
    }

    static func valueFont(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size) }
    static func labelFont(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size - 2, weight: .medium) }

    static func string(_ parts: [String], label: String?, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if let label { out.append(NSAttributedString(string: label + "  ", attributes: [.font: labelFont(size)])) }
        out.append(NSAttributedString(string: parts.joined(separator: " · "), attributes: [.font: valueFont(size)]))
        return out
    }

    static func fit(value: String, label: String?, width: CGFloat, height: CGFloat, shorter: String? = nil) -> Fit {
        func oneLine(_ value: String, _ label: String?) -> Fit? {
            var parts = value.components(separatedBy: " · ")
            var label = label
            while true {
                for size in stride(from: 15.0, through: 11.0, by: -0.5) {
                    let l = string(parts, label: label, size: CGFloat(size))
                    if ceil(l.size().width) <= width { return Fit(parts: parts, label: label, size: CGFloat(size), lines: 1) }
                }
                if parts.count > 1 { parts.removeLast(); continue }
                if label != nil { label = nil; continue }
                return nil
            }
        }
        if let fit = oneLine(value, label) { return fit }
        if let shorter, let fit = oneLine(shorter, nil) { return fit }
        let parts = [value.components(separatedBy: " · ")[0]]
        for size in stride(from: 13.0, through: 11.0, by: -0.5) {
            let font = valueFont(CGFloat(size))
            let box = string(parts, label: nil, size: CGFloat(size))
                .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin], context: nil)
            if ceil(box.height) <= min(height, ceil(font.lineHeight * 2) + 1) {
                return Fit(parts: parts, label: nil, size: CGFloat(size), lines: 2)
            }
        }
        return Fit(parts: parts, label: nil, size: 11, lines: 2)
    }
}
