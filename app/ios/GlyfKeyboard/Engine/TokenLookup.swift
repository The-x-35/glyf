import Foundation

/// A cashtag's price and a copied address's token, asked of Jupiter's
/// keyless lite API from the phone: the server's lookup
/// (server/src/lib/rates.ts, `tokenQuote`, `tokenAt`, `pickToken`,
/// `pickStock`, the name list) ported as it is, so `$sol`, `$aapl` and a
/// copied mint work without our server (docs/SERVER-INVENTORY.md,
/// 2026-10-14). GET /rates/crypto and /rates/token stay as the fallback.
///
/// Synchronous: `search` blocks, so RatesStore runs this on a queue of its
/// own and tests hand in a stand-in. Not thread-safe; one queue only.
final class TokenLookup {

    struct Quote: Equatable {
        var symbol: String
        var name: String
        var mint: String
        var usd: Double
        /// Priced through a tokenized share (xStocks, Ondo) rather than a token.
        var stock = false
        /// Percent over the last day, when Jupiter has it.
        var change24h: Double?
        /// A coin the ecosystem tags major (SOL): it keeps its ticker even
        /// where a stock shares it.
        var major = false
        /// The market's own ticker, whatever was typed.
        var ticker: String?
    }

    /// A token found by its address.
    struct MintQuote: Equatable {
        let mint: String
        let symbol: String
        let name: String
        let decimals: Int
        /// Nil for a token too new to have a price.
        let usd: Double?
        let verified: Bool
    }

    struct Unavailable: Error {}

    typealias Search = (String) throws -> [[String: Any]]

    static let jupiterSearch = "https://lite-api.jup.ag/tokens/v2/search?query="
    static let ttl: TimeInterval = 60

    private let search: Search
    private let now: () -> Date
    private var tokens: [String: (quote: Quote?, at: Date)] = [:]
    private var mints: [String: (token: MintQuote?, at: Date)] = [:]

    init(search: @escaping Search = TokenLookup.liveSearch, now: @escaping () -> Date = Date.init) {
        self.search = search
        self.now = now
    }

    /// Jupiter's token search, blocking; throws when Jupiter can't be asked.
    static func liveSearch(_ query: String) throws -> [[String: Any]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        guard let url = URL(string: jupiterSearch + encoded) else { throw Unavailable() }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let done = DispatchSemaphore(value: 0)
        var body: Data?
        var status = 0
        URLSession.shared.dataTask(with: req) { data, response, _ in
            body = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            done.signal()
        }.resume()
        if done.wait(timeout: .now() + 7) == .timedOut { throw Unavailable() }
        guard (200..<300).contains(status), let body,
              let list = try? JSONSerialization.jsonObject(with: body) else { throw Unavailable() }
        return (list as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    // MARK: Lookups

    /// "$sol" / "SOL" → "SOL", "$apple" → "APPLE"; anything that is not a
    /// ticker or a name → nil.
    static func tickerOf(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("$") { t.removeFirst() }
        t = t.uppercased()
        // Letters with maybe digits ("SOL", "W3D"); a bare number is an amount.
        guard (2...14).contains(t.unicodeScalars.count),
              t.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) || ("0"..."9").contains($0) }),
              t.unicodeScalars.contains(where: { ("A"..."Z").contains($0) }) else { return nil }
        return t
    }

    /// Base58, 32 to 44 characters: the shape of every Solana address.
    static func isAddress(_ s: String) -> Bool {
        let base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return (32...44).contains(s.unicodeScalars.count) && s.allSatisfy { base58.contains($0) }
    }

    /// The dollar price of the verified token behind a ticker. A miss is
    /// remembered for a minute too, so "$lol" typed letter by letter is one
    /// lookup, not five. Throws when Jupiter can't be asked (the server is
    /// asked then), where the server would keep what it had.
    func quote(_ raw: String) throws -> Quote? {
        guard let symbol = Self.tickerOf(raw) else { return nil }
        // "$apple" is Apple: a known name goes straight to its ticker, so a
        // coin that took the name never answers for the company.
        if let known = Self.names[symbol], known != symbol {
            guard var found = try quote(known) else { return nil }
            // Bitcoin trades here as WBTC, but people read BTC.
            found.ticker = known == "WBTC" ? "BTC" : found.ticker ?? known
            found.symbol = symbol
            return found
        }
        if let hit = tokens[symbol], now().timeIntervalSince(hit.at) < Self.ttl { return hit.quote }
        let list = try search(symbol)
        let token = Self.pickToken(symbol, list)
        // A stock beats a coin that merely shares its ticker (a verified meme
        // coin called NVDA is not Nvidia); only a major coin keeps its name.
        var stock = Self.pickStock(symbol, list)
        if stock == nil, token?.major != true, !symbol.hasSuffix("X") {
            stock = Self.pickStock(symbol, try search("\(symbol)x"))
        }
        var found = token?.major == true ? token : stock ?? token
        // Any other company typed by name ("$pfizer"): its tokenized share.
        if found == nil, symbol.utf16.count >= 3 { found = Self.pickStockByName(symbol, list) }
        // Half a name, or the usual slip ("$appl" on the way to "$apple").
        if found == nil, symbol.utf16.count >= 4 { found = Self.pickStockByPrefix(symbol, list) }
        tokens[symbol] = (found, now())
        return found
    }

    /// The token at a Solana address, or nil when Jupiter has none there (a
    /// wallet, in a chat). Throws when Jupiter can't be asked: "not a token"
    /// is never said on a guess.
    func token(at address: String) throws -> MintQuote? {
        guard Self.isAddress(address) else { return nil }
        if let hit = mints[address], now().timeIntervalSince(hit.at) < Self.ttl { return hit.token }
        let t = try search(address).first { $0["id"] as? String == address }
        var token: MintQuote?
        if let t, let symbol = t["symbol"] as? String, let decimals = Self.number(t["decimals"]) {
            let usd = Self.number(t["usdPrice"]).flatMap { $0 > 0 ? $0 : nil }
            token = MintQuote(mint: address, symbol: symbol, name: t["name"] as? String ?? symbol,
                              decimals: Int(decimals), usd: usd, verified: Self.isTrue(t["isVerified"]))
        }
        mints[address] = (token, now())
        return token
    }

    // MARK: Picking (pure, as the server's)

    /// Names people type instead of tickers.
    static let names: [String: String] = [
        "APPLE": "AAPL", "TESLA": "TSLA", "NVIDIA": "NVDA", "MICROSOFT": "MSFT", "GOOGLE": "GOOGL",
        "ALPHABET": "GOOGL", "AMAZON": "AMZN", "FACEBOOK": "META", "NETFLIX": "NFLX", "COINBASE": "COIN",
        "MICROSTRATEGY": "MSTR", "PALANTIR": "PLTR", "ROBINHOOD": "HOOD", "GAMESTOP": "GME", "INTEL": "INTC",
        "BROADCOM": "AVGO", "ORACLE": "ORCL", "SALESFORCE": "CRM", "ADOBE": "ADBE", "DISNEY": "DIS",
        "NIKE": "NKE", "WALMART": "WMT", "COSTCO": "COST", "MCDONALDS": "MCD", "COCACOLA": "KO",
        "PEPSI": "PEP", "JPMORGAN": "JPM", "SP500": "SPY", "NASDAQ": "QQQ",
        "BITCOIN": "WBTC", "BTC": "WBTC", "ETHEREUM": "ETH", "ETHER": "ETH", "SOLANA": "SOL", "JUPITER": "JUP",
    ]

    /// A JSON number (never a boolean), as the server's `typeof x === "number"`.
    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    /// `x === true`: a JSON true, never the number 1.
    private static func isTrue(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    private static func tags(_ t: [String: Any]) -> [String] { t["tags"] as? [String] ?? [] }
    private static func liquidity(_ t: [String: Any]) -> Double { number(t["liquidity"]) ?? 0 }

    /// Verified, priced above zero, with an id: the server's common gate.
    private static func priced(_ t: [String: Any]) -> Bool {
        isTrue(t["isVerified"]) && (number(t["usdPrice"]).map { $0 > 0 } ?? false) && t["id"] is String
    }

    private static func isStockTagged(_ t: [String: Any]) -> Bool {
        tags(t).contains { $0 == "stocks" || $0 == "equities" || $0 == "xstocks" }
    }

    /// The server's sort (JavaScript's is stable): higher rank, then deeper
    /// liquidity, then Jupiter's own order.
    private static func ranked(_ list: [[String: Any]], _ rank: ([String: Any]) -> Int) -> [[String: Any]] {
        list.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            if ra != rb { return ra > rb }
            let la = liquidity(a.element), lb = liquidity(b.element)
            if la != lb { return la > lb }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func change(_ t: [String: Any]) -> Double? {
        number((t["stats24h"] as? [String: Any])?["priceChange"])
    }

    /// The verified token that IS the ticker, never a staked or wrapped
    /// cousin whose symbol merely contains it (SOL must not become JupSOL).
    static func pickToken(_ symbol: String, _ list: [[String: Any]]) -> Quote? {
        let exact = list.filter { priced($0) && ($0["symbol"] as? String ?? "").uppercased() == symbol }
        guard let t = ranked(exact, { (tags($0).contains("major") ? 2 : 0) + (tags($0).contains("strict") ? 1 : 0) }).first
        else { return nil }
        return Quote(symbol: symbol, name: t["name"] as? String ?? symbol, mint: t["id"] as! String,
                     usd: number(t["usdPrice"])!, change24h: change(t), major: tags(t).contains("major"), ticker: symbol)
    }

    /// A share's own ticker: AAPLx and AAPLon are both AAPL.
    static func shareTicker(_ symbol: String?, _ fallback: String) -> String {
        var s = symbol ?? ""
        if s.hasSuffix("x") { s.removeLast() } else if s.hasSuffix("on") { s.removeLast(2) }
        let ok = (1...10).contains(s.unicodeScalars.count) && s.unicodeScalars.allSatisfy {
            ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "."
        }
        return ok ? s.uppercased() : fallback
    }

    /// A company half typed or misspelt: the first verified share, in
    /// Jupiter's order, whose company name starts with what was typed.
    static func pickStockByPrefix(_ prefix: String, _ list: [[String: Any]]) -> Quote? {
        let want = prefix.lowercased()
        guard let t = list.first(where: {
            priced($0) && isStockTagged($0) && ($0["name"] as? String ?? "").lowercased().hasPrefix(want)
        }) else { return nil }
        return Quote(symbol: prefix, name: t["name"] as? String ?? prefix, mint: t["id"] as! String,
                     usd: number(t["usdPrice"])!, stock: true, change24h: change(t),
                     ticker: shareTicker(t["symbol"] as? String, prefix))
    }

    /// A stock by its tokenized share: the verified xStock ("AAPLx") first,
    /// then Ondo's ("AAPLon"), then the deepest. Only tokens Jupiter tags as
    /// stocks count, so a meme coin called AAPLX never prices Apple.
    static func pickStock(_ symbol: String, _ list: [[String: Any]]) -> Quote? {
        let shares = list.filter {
            let sym = ($0["symbol"] as? String ?? "").uppercased()
            return priced($0) && (sym == "\(symbol)X" || sym == "\(symbol)ON") && isStockTagged($0)
        }
        guard let t = ranked(shares, { ($0["symbol"] as? String ?? "").uppercased() == "\(symbol)X" ? 1 : 0 }).first
        else { return nil }
        return Quote(symbol: symbol, name: t["name"] as? String ?? symbol, mint: t["id"] as! String,
                     usd: number(t["usdPrice"])!, stock: true, change24h: change(t), ticker: symbol)
    }

    private static let companySuffix = try! NSRegularExpression(pattern: "\\s*(xstock|\\(ondo tokenized\\)|-.*)$")

    /// A company typed by name ("PFIZER"): the verified tokenized share whose
    /// name is that company ("Pfizer xStock"), xStock first.
    static func pickStockByName(_ name: String, _ list: [[String: Any]]) -> Quote? {
        let want = name.lowercased()
        let shares = list.filter { t in
            guard priced(t), isStockTagged(t) else { return false }
            let full = (t["name"] as? String ?? "").lowercased()
            let ns = full as NSString
            var company = full
            if let m = companySuffix.firstMatch(in: full, range: NSRange(location: 0, length: ns.length)) {
                company = ns.replacingCharacters(in: m.range, with: "")
            }
            company = company.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = String(company.prefix { !($0.isWhitespace || $0 == "," || $0 == ".") })
            return company == want || first == want
        }
        guard let t = ranked(shares, { ($0["symbol"] as? String ?? "").hasSuffix("x") ? 1 : 0 }).first
        else { return nil }
        return Quote(symbol: name, name: t["name"] as? String ?? name, mint: t["id"] as! String,
                     usd: number(t["usdPrice"])!, stock: true, change24h: change(t),
                     ticker: shareTicker(t["symbol"] as? String, name))
    }
}

/// Glyf's fee on a buy: Jupiter's referral fee on Swap V2 /order
/// (docs/SWAP-FEE.md). Off while `referralAccount` is empty, and then the
/// Buy quote is asked exactly as before. Twins: SwapFee in
/// lib/wallet/wallet_api.dart (which builds the real order) and
/// ime/SwapFee.kt. The keyboard only prices; the fee must match the app's.
enum SwapFee {
    /// The referral account made at referral.jup.ag under Jupiter's Ultra
    /// referral project. Public, not a secret.
    static let referralAccount = ""

    /// 0.5%. Jupiter takes 50 to 255 and keeps a fifth of it.
    static let bps = 50

    /// The /order quote link for the Buy panel: keyless, no taker.
    static func orderURL(inputMint: String, outputMint: String, units: Int,
                         referral: String = referralAccount) -> URL? {
        var comps = URLComponents(string: "https://api.jup.ag/swap/v2/order")
        var items: [URLQueryItem] = [.init(name: "inputMint", value: inputMint),
                                     .init(name: "outputMint", value: outputMint),
                                     .init(name: "amount", value: String(units))]
        if !referral.isEmpty {
            items.append(.init(name: "referralAccount", value: referral))
            items.append(.init(name: "referralFee", value: String(bps)))
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// The fee Jupiter says it applied for Glyf, from an /order answer.
    static func applied(_ json: [String: Any]) -> Int? {
        guard let account = json["referralAccount"] as? String, !account.isEmpty else { return nil }
        return (json["feeBps"] as? NSNumber)?.intValue ?? bps
    }

    /// "Fee 0.5%".
    static func label(_ bps: Int) -> String {
        var pct = String(format: "%.2f", Double(bps) / 100)
        while pct.hasSuffix("0") { pct.removeLast() }
        if pct.hasSuffix(".") { pct.removeLast() }
        return "Fee \(pct)%"
    }
}
