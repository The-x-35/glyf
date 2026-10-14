import XCTest

/// The three lookups moved from the server to the phone on 2026-10-14
/// (docs/SERVER-INVENTORY.md), held to the server's own cases:
/// Noto stickers (server/test/media.test.ts and shared/stickers/noto-cases.json,
/// recorded from the server's search), cashtag and token prices
/// (server/test/rates.test.ts) and Cal.com booking links
/// (server/test/scheduling.test.ts). The Android keyboard runs the same.
final class PhoneLookupsTests: XCTestCase {

    // MARK: Noto stickers

    private static let sharedDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // RunnerTests
        .deletingLastPathComponent()          // ios
        .deletingLastPathComponent()          // app
        .deletingLastPathComponent()          // repo
        .appendingPathComponent("shared/stickers")

    func testNotoSearchAnswersEveryRecordedSearchLikeTheServer() throws {
        let data = try Data(contentsOf: Self.sharedDir.appendingPathComponent("noto-cases.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 10)
        for c in cases {
            let q = c["q"] as! String
            let hits = NotoStickers.search(q).map(NotoStickers.item)
            XCTAssertEqual(hits.count, c["count"] as? Int, "count for '\(q)'")
            XCTAssertEqual(hits.map(\.id), c["ids"] as? [String], "order for '\(q)'")
            XCTAssertEqual(Array(hits.prefix(5).map(\.title)), c["titles"] as? [String], "titles for '\(q)'")
        }
    }

    func testNotoBundlesTheCatalogueBaseEmojiOnlyMostPopularFirst() {
        let all = NotoStickers.catalogue
        XCTAssertGreaterThan(all.count, 500)
        XCTAssertEqual(all.first?.c, "1f600")
        XCTAssertFalse(all.contains { $0.c.range(of: "_1f3f[b-f]", options: .regularExpression) != nil })
    }

    func testNotoFindsAFeelingThroughTheEmojiThatShowIt() {
        XCTAssertTrue(NotoStickers.search("laughing").prefix(3).contains { $0.c == "1f602" })
        XCTAssertTrue(NotoStickers.search("thank you").contains { $0.c == "1f64f" })
        XCTAssertTrue(NotoStickers.search("hello").contains { $0.c == "1f44b" })
        XCTAssertGreaterThan(NotoStickers.search("wow").count, 2)
        XCTAssertEqual(NotoStickers.search("zzzqqq"), [])
    }

    func testNotoPreviewsTheStillAndSendsTheAnimatedGif() {
        let item = NotoStickers.item(.init(c: "1f602", t: ["joy"], g: "smileys"))
        XCTAssertEqual(item.preview, "https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/128.png")
        XCTAssertEqual(item.url, "https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/512.gif")
        XCTAssertEqual(item.title, "joy")
        XCTAssertEqual(item.id, "noto:1f602")
        XCTAssertEqual(NotoStickers.item(.init(c: "1f62d", t: ["loudly-crying"], g: "smileys")).title, "loudly crying")
    }

    func testNotoPagesThroughASearchAndCreditsGoogle() {
        let first = NotoStickers.page(query: "", page: nil)
        XCTAssertEqual(first.items.count, 30)
        XCTAssertEqual(first.next, "2")
        XCTAssertTrue(first.attribution.contains("CC BY 4.0"))
        let second = NotoStickers.page(query: "", page: "2")
        XCTAssertNotEqual(second.items[0].id, first.items[0].id)
        XCTAssertEqual(second.items[0].id, "noto:\(NotoStickers.search("")[30].c)")
        XCTAssertGreaterThan(NotoStickers.page(query: "love", page: nil).items.count, 3)
        let last = NotoStickers.page(query: "", page: "21")
        XCTAssertEqual(last.items.count, NotoStickers.catalogue.count - 600)
        XCTAssertNil(last.next)
        XCTAssertEqual(NotoStickers.page(query: "", page: "22").items.count, 0)
        XCTAssertEqual(NotoStickers.page(query: "", page: "nonsense"), first)
    }

    // MARK: Cashtag and token prices

    private let jupiter: [[String: Any]] = [
        ["id": "jupSoLaHXQiZZTSfEWMTRRgpnyFm8f6sZdosWBjx93v", "symbol": "JupSOL", "name": "Jupiter Staked SOL",
         "isVerified": true, "usdPrice": 135.17, "tags": ["strict", "verified", "lst"]],
        ["id": "So11111111111111111111111111111111111111112", "symbol": "SOL", "name": "Wrapped SOL",
         "isVerified": true, "usdPrice": 111.77, "tags": ["major", "strict", "verified"], "liquidity": 8e8],
        ["id": "FakeSoL1111111111111111111111111111111111111", "symbol": "SOL", "name": "Not Solana",
         "isVerified": false, "usdPrice": 0.5],
    ]

    private func share(_ id: String, _ symbol: String, _ name: String, _ usd: Double) -> [String: Any] {
        ["id": id, "symbol": symbol, "name": name, "isVerified": true, "usdPrice": usd,
         "tags": ["stocks", "xstocks", "verified"], "liquidity": 6e5, "stats24h": ["priceChange": 1.5]]
    }

    private lazy var apple: [[String: Any]] = [
        share("XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp", "AAPLx", "Apple xStock", 340.3),
        ["id": "123mYEnRLM2LLYsJW3K6oyYh8uP1fngj732iG638ondo", "symbol": "AAPLon", "name": "Apple (Ondo Tokenized)",
         "isVerified": true, "usdPrice": 340.22, "tags": ["equities", "verified"], "liquidity": 9e5],
        ["id": "9B2sGQFakeAaplx1111111111111111111111111111", "symbol": "AAPLX", "name": "AAPL Stock with Dividends",
         "isVerified": false, "usdPrice": 0.01, "tags": ["unknown"]],
        ["id": "BWMwxBAppleCoin111111111111111111111111111", "symbol": "AAPL", "name": "Applecoin",
         "isVerified": false, "usdPrice": 0.02],
    ]

    /// A stand-in for Jupiter's search that answers by query and counts calls;
    /// nil is Jupiter down.
    private final class Fake {
        var calls: [String] = []
        let answer: (String) -> [[String: Any]]?
        init(_ answer: @escaping (String) -> [[String: Any]]?) { self.answer = answer }
        func search(_ q: String) throws -> [[String: Any]] {
            calls.append(q)
            guard let list = answer(q) else { throw TokenLookup.Unavailable() }
            return list
        }
    }

    func testTokenPicksTheTokenThatIsTheTicker() {
        let sol = TokenLookup.pickToken("SOL", jupiter)
        XCTAssertEqual(sol?.mint, "So11111111111111111111111111111111111111112")
        XCTAssertEqual(sol?.usd, 111.77)
        XCTAssertNil(TokenLookup.pickToken("SOL", [jupiter[2]]))
        XCTAssertNil(TokenLookup.pickToken("BONK", jupiter))
        XCTAssertEqual(TokenLookup.tickerOf("$sol"), "SOL")
        XCTAssertNil(TokenLookup.tickerOf("13"))
        XCTAssertNil(TokenLookup.tickerOf("$"))
    }

    func testTokenRemembersAMissForAMinute() throws {
        let jupiter = self.jupiter
        let fake = Fake { $0 == "SOL" ? jupiter : [] }
        var clock = Date(timeIntervalSince1970: 0)
        let rates = TokenLookup(search: fake.search, now: { clock })
        XCTAssertEqual(try rates.quote("$sol")?.usd, 111.77)
        XCTAssertNil(try rates.quote("lol"))
        _ = try rates.quote("LOL")
        _ = try rates.quote("sol")
        // A miss asks twice (the ticker, then its tokenized share), then rests.
        XCTAssertEqual(fake.calls.count, 3)
        clock = Date(timeIntervalSince1970: 61)
        _ = try rates.quote("SOL")
        XCTAssertEqual(fake.calls.count, 4)
    }

    func testTokenPricesAStockByItsVerifiedShareXStockFirst() {
        let q = TokenLookup.pickStock("AAPL", apple)
        XCTAssertEqual(q?.symbol, "AAPL")
        XCTAssertEqual(q?.name, "Apple xStock")
        XCTAssertEqual(q?.usd, 340.3)
        XCTAssertEqual(q?.stock, true)
        XCTAssertEqual(q?.change24h, 1.5)
        XCTAssertEqual(TokenLookup.pickStock("AAPL", Array(apple.dropFirst()))?.name, "Apple (Ondo Tokenized)")
        XCTAssertNil(TokenLookup.pickStock("AAPL", Array(apple.dropFirst(2))))
        var solx = jupiter[1]
        solx["symbol"] = "SOLx"
        XCTAssertNil(TokenLookup.pickStock("SOL", [solx]))
    }

    func testTokenAnswersAaplAskingForTheShareWhenTheTickerSearchMisses() throws {
        let apple = self.apple
        let fake = Fake { $0 == "AAPLx" ? Array(apple.prefix(1)) : $0 == "AAPL" ? apple : [] }
        let q = try TokenLookup(search: fake.search).quote("$aapl")
        XCTAssertEqual(q?.symbol, "AAPL")
        XCTAssertEqual(q?.usd, 340.3)
        XCTAssertEqual(q?.stock, true)
        XCTAssertEqual(fake.calls.count, 1)
        let tsla = share("XsDoVfTsla111111111111111111111111111111111", "TSLAx", "Tesla xStock", 371.43)
        let second = Fake { $0 == "TSLAx" ? [tsla] : [] }
        XCTAssertEqual(try TokenLookup(search: second.search).quote("TSLA")?.usd, 371.43)
        XCTAssertEqual(second.calls, ["TSLA", "TSLAx"])
    }

    func testTokenPricesACompanyTypedByName() throws {
        let appleCoin: [String: Any] = ["id": "AppLeCoin11111111111111111111111111111111111", "symbol": "APPLE",
                                        "name": "Apple Coin", "isVerified": true, "usdPrice": 0.003, "tags": ["verified"]]
        let pfizer = [share("PFExPfizer1111111111111111111111111111111111", "PFEx", "Pfizer xStock", 26.48)]
        let apple = self.apple
        let fake = Fake { q in q == "AAPL" ? apple : q == "APPLE" ? [appleCoin] : q == "PFIZER" ? pfizer : [] }
        let rates = TokenLookup(search: fake.search)
        let a = try rates.quote("$apple")
        XCTAssertEqual(a?.symbol, "APPLE")
        XCTAssertEqual(a?.usd, 340.3)
        XCTAssertEqual(a?.stock, true)
        XCTAssertEqual(fake.calls, ["AAPL"])
        let p = try rates.quote("$pfizer")
        XCTAssertEqual(p?.symbol, "PFIZER")
        XCTAssertEqual(p?.usd, 26.48)
        XCTAssertEqual(p?.name, "Pfizer xStock")
        XCTAssertNil(try rates.quote("$banana"))
    }

    func testTokenBitcoinReadsAsBtc() throws {
        let wbtc: [String: Any] = ["id": "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh", "symbol": "WBTC",
                                   "name": "Wrapped BTC", "isVerified": true, "usdPrice": 61000, "tags": ["strict", "verified"]]
        let rates = TokenLookup(search: Fake { $0 == "WBTC" ? [wbtc] : [] }.search)
        let q = try rates.quote("$bitcoin")
        XCTAssertEqual(q?.symbol, "BITCOIN")
        XCTAssertEqual(q?.ticker, "BTC")
        XCTAssertEqual(q?.usd, 61000)
        XCTAssertEqual(try rates.quote("$btc")?.ticker, "BTC")
    }

    func testTokenFindsTheCompanyForASlipOrHalfAName() throws {
        let applovin = share("XsPdAVBi8Zc1xvv53k4JcMrQaEDTgkGqKYeh7AYgPHV", "APPx", "AppLovin xStock", 649.83)
        let apple = self.apple
        let fake = Fake { $0 == "APPL" ? [apple[0], apple[1], applovin] : $0 == "AAPL" ? apple : [] }
        let rates = TokenLookup(search: fake.search)
        let q = try rates.quote("$appl")
        XCTAssertEqual(q?.symbol, "APPL")
        XCTAssertEqual(q?.ticker, "AAPL")
        XCTAssertEqual(q?.usd, 340.3)
        XCTAssertEqual(try rates.quote("$apple")?.ticker, "AAPL")
        XCTAssertEqual(TokenLookup.pickStockByPrefix("APP", [applovin])?.ticker, "APP")
        XCTAssertNil(try TokenLookup(search: Fake { _ in [applovin] }.search).quote("$tes"))
        var coin = apple[3]
        coin["name"] = "Applecoin"
        XCTAssertNil(TokenLookup.pickStockByPrefix("APPL", [coin]))
    }

    func testTokenPricesNvidiaNotAMemeCoinSolStaysSol() throws {
        let meme: [String: Any] = ["id": "9dwPiStDBwJJqC3QzMnjpJP7xohZbMVmHELFx3uy3KRq", "symbol": "NVDA", "name": "NVIDIA",
                                   "isVerified": true, "usdPrice": 0.00017, "tags": ["verified"]]
        let nvdax = share("Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh", "NVDAx", "NVIDIA xStock", 224.52)
        let jupiter = self.jupiter
        let rates = TokenLookup(search: Fake { $0 == "NVDA" ? [meme] : $0 == "NVDAx" ? [nvdax] : $0 == "SOL" ? jupiter : [] }.search)
        let n = try rates.quote("$nvda")
        XCTAssertEqual(n?.usd, 224.52)
        XCTAssertEqual(n?.stock, true)
        XCTAssertEqual(try rates.quote("$sol")?.usd, 111.77)
    }

    func testTokenThrowsWhenJupiterCannotBeAskedSoTheServerIsAsked() {
        let rates = TokenLookup(search: Fake { _ in nil }.search)
        XCTAssertThrowsError(try rates.quote("$sol"))
        XCTAssertThrowsError(try rates.token(at: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"))
    }

    func testTokenTellsATokensAddressFromAWallets() throws {
        let bonk: [String: Any] = ["id": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", "symbol": "Bonk", "name": "Bonk",
                                   "decimals": 5, "usdPrice": 0.0000036, "isVerified": true]
        let fresh: [String: Any] = ["id": "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr", "symbol": "POPCAT", "name": "Popcat",
                                    "decimals": 9, "isVerified": false]
        let fake = Fake { q in q == bonk["id"] as? String ? [bonk] : q == fresh["id"] as? String ? [fresh] : [] }
        let rates = TokenLookup(search: fake.search)
        XCTAssertEqual(try rates.token(at: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"),
                       TokenLookup.MintQuote(mint: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", symbol: "Bonk", name: "Bonk",
                             decimals: 5, usd: 0.0000036, verified: true))
        // Too new for a price, and not verified: still a token, said plainly.
        XCTAssertEqual(try rates.token(at: "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr"),
                       TokenLookup.MintQuote(mint: "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr", symbol: "POPCAT", name: "Popcat",
                             decimals: 9, usd: nil, verified: false))
        let wallet = "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"
        XCTAssertNil(try rates.token(at: wallet))
        _ = try rates.token(at: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263")
        XCTAssertEqual(fake.calls.count, 3)
        XCTAssertNil(try rates.token(at: "not an address"))
        XCTAssertTrue(TokenLookup.isAddress(wallet))
        XCTAssertFalse(TokenLookup.isAddress("0OIl"))
    }

    // MARK: Cal.com booking

    private struct Asked { let method: String; let url: String; let headers: [String: String]; let body: Data? }

    /// Answers from a table of URL prefixes, and records what it was asked.
    private final class FakeCal {
        var asked: [Asked] = []
        let table: [(String, Int, String)]
        let fail: Error?
        init(_ table: [(String, Int, String)], fail: Error? = nil) { self.table = table; self.fail = fail }
        var http: CalBooking.HTTP {
            { [unowned self] method, url, headers, body in
                self.asked.append(Asked(method: method, url: url, headers: headers, body: body))
                if let fail = self.fail { throw fail }
                guard let hit = self.table.first(where: { url.hasPrefix($0.0) }) else {
                    return .init(status: 404, body: Data("{}".utf8))
                }
                return .init(status: hit.1, body: Data(hit.2.utf8))
            }
        }
    }

    private func query(_ url: String) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(string: url)?.queryItems ?? [] { out[item.name] = item.value }
        return out
    }

    func testCalReadsCalComAndCalendlyLinksHoweverTyped() {
        XCTAssertEqual(CalBooking.parse("cal.com/jane/30min"),
                       CalBooking.Link(provider: "calcom", base: "https://cal.com/jane/30min", username: "jane", slug: "30min", org: nil))
        XCTAssertEqual(CalBooking.parse("https://app.cal.com/jane")?.base, "https://cal.com/jane")
        let org = CalBooking.parse("physics.cal.com/rick/15min")
        XCTAssertEqual(org?.org, "physics")
        XCTAssertEqual(org?.username, "rick")
        XCTAssertEqual(org?.slug, "15min")
        XCTAssertEqual(CalBooking.parse("https://calendly.com/jane/intro?month=2026-09"),
                       CalBooking.Link(provider: "calendly", base: "https://calendly.com/jane/intro", username: "jane", slug: "intro", org: nil))
        XCTAssertNil(CalBooking.parse("cal.com"))
        XCTAssertNil(CalBooking.parse("example.com/jane"))
        XCTAssertNil(CalBooking.parse("cal.com/jane/<script>"))
        XCTAssertEqual(CalBooking.parse("  www.Cal.com/jane/ ")?.base, "https://cal.com/jane")
    }

    func testCalOpensThePageOnADayAndCalComOnTheTimeItself() throws {
        let cal = try XCTUnwrap(CalBooking.parse("cal.com/jane/30min"))
        XCTAssertEqual(CalBooking.bookingUrl(cal, date: "2026-10-06", slotUtc: "2026-10-06T08:40:00.000Z"),
                       "https://cal.com/jane/30min?month=2026-10&date=2026-10-06&slot=2026-10-06T08%3A40%3A00.000Z")
        let calendly = try XCTUnwrap(CalBooking.parse("calendly.com/jane/intro"))
        XCTAssertEqual(CalBooking.bookingUrl(calendly, date: "2026-09-25", slotUtc: "2026-09-25T10:00:00.000Z"),
                       "https://calendly.com/jane/intro?month=2026-09&date=2026-09-25")
    }

    func testCalGivesCalendlysLinkOnTheDayWithoutAsking() {
        let fake = FakeCal([])
        guard case .ok(let s) = CalBooking.slots(link: "calendly.com/jane/intro", date: "2026-09-25", tz: "Asia/Kolkata",
                                                 http: fake.http) else { return XCTFail("no answer") }
        XCTAssertEqual(s.provider, "calendly")
        XCTAssertEqual(s.link, "https://calendly.com/jane/intro")
        XCTAssertEqual(s.bookingUrl, "https://calendly.com/jane/intro?month=2026-09&date=2026-09-25")
        XCTAssertTrue(s.days.isEmpty)
        XCTAssertEqual(fake.asked.count, 0)
    }

    func testCalGivesCalComsOpenTimesEachOpeningOnTheSlot() {
        let fake = FakeCal([("https://api.cal.com/v2/slots", 200, """
            {"status":"success","data":{
              "2026-09-27":[{"start":"2026-09-27T23:30:00.000+05:30"}],
              "2026-09-28":[{"start":"2026-09-28T19:00:00.000+05:30"},{"start":"2026-09-28T19:30:00.000+05:30"}],
              "2026-09-29":[{"start":"2026-09-29T10:00:00.000+05:30"}]}}
            """)])
        guard case .ok(let s) = CalBooking.slots(link: "cal.com/slot-test/30min", date: "2026-09-28", days: 1,
                                                 tz: "Asia/Kolkata", http: fake.http) else { return XCTFail("no answer") }
        XCTAssertEqual(s.provider, "calcom")
        XCTAssertEqual(s.days.count, 1)
        XCTAssertEqual(s.days.first?.date, "2026-09-28")
        XCTAssertEqual(s.days.first?.slots.map(\.start), ["2026-09-28T19:00:00.000+05:30", "2026-09-28T19:30:00.000+05:30"])
        XCTAssertEqual(s.days.first?.slots.map(\.url), [
            "https://cal.com/slot-test/30min?month=2026-09&date=2026-09-28&slot=2026-09-28T13%3A30%3A00.000Z",
            "https://cal.com/slot-test/30min?month=2026-09&date=2026-09-28&slot=2026-09-28T14%3A00%3A00.000Z",
        ])
        let q = query(fake.asked[0].url)
        XCTAssertEqual(q["eventTypeSlug"], "30min")
        XCTAssertEqual(q["username"], "slot-test")
        XCTAssertEqual(q["start"], "2026-09-27")
        XCTAssertEqual(q["end"], "2026-09-29")
        XCTAssertEqual(q["timeZone"], "Asia/Kolkata")
        XCTAssertEqual(fake.asked[0].headers["cal-api-version"], "2024-09-04")
    }

    func testCalPicksTheShortestShownEventWhenTheLinkNamesNone() {
        let fake = FakeCal([
            ("https://api.cal.com/v2/event-types", 200, """
             {"status":"success","data":[{"slug":"60min","title":"Hour","lengthInMinutes":60},
             {"slug":"secret","title":"Hidden","lengthInMinutes":5,"hidden":true},
             {"slug":"15min","title":"Quick chat","lengthInMinutes":15}]}
             """),
            ("https://api.cal.com/v2/slots", 200, #"{"status":"success","data":{}}"#),
        ])
        guard case .ok(let s) = CalBooking.slots(link: "cal.com/pick-test", date: "2026-09-28", tz: "UTC", http: fake.http)
        else { return XCTFail("no answer") }
        XCTAssertEqual(s.link, "https://cal.com/pick-test/15min")
        XCTAssertEqual(s.title, "Quick chat")
        XCTAssertEqual(s.length, 15)
        XCTAssertTrue(s.days.isEmpty)
        XCTAssertEqual(query(fake.asked[1].url)["eventTypeSlug"], "15min")
        XCTAssertEqual(fake.asked[0].headers["cal-api-version"], "2026-06-12")
    }

    private func refused<T>(_ o: CalBooking.Outcome<T>) -> String? {
        if case .refused(let words) = o { return words }
        return nil
    }

    private func unreachable<T>(_ o: CalBooking.Outcome<T>) -> Bool {
        if case .unreachable = o { return true }
        return false
    }

    func testCalSaysWhatWentWrongInWordsAndHandsTheRestToTheServer() {
        XCTAssertEqual(refused(CalBooking.slots(link: "example.com/jane", date: "2026-09-28", tz: "UTC", http: FakeCal([]).http)),
                       "That isn't a Cal.com or Calendly link")
        let gone = FakeCal([("https://api.cal.com/v2/slots", 404, #"{"status":"error"}"#)])
        XCTAssertEqual(refused(CalBooking.slots(link: "cal.com/nobody-here/30min", date: "2026-09-28", tz: "UTC", http: gone.http)),
                       "Cal.com doesn't know that link")
        let down = FakeCal([("https://api.cal.com/v2/slots", 503, "{}")])
        XCTAssertTrue(unreachable(CalBooking.slots(link: "cal.com/jane/30min", date: "2026-09-28", tz: "UTC", http: down.http)))
        let offline = FakeCal([], fail: CalBooking.NotSent())
        XCTAssertTrue(unreachable(CalBooking.slots(link: "cal.com/jane", date: "2026-09-28", tz: "UTC", http: offline.http)))
        let none = FakeCal([("https://api.cal.com/v2/event-types", 200, #"{"data":[{"slug":"x","hidden":true}]}"#)])
        XCTAssertEqual(refused(CalBooking.slots(link: "cal.com/jane", date: "2026-09-28", tz: "UTC", http: none.http)),
                       "No bookable event on that Cal.com link")
    }

    private let start = Date(timeIntervalSince1970: 1_790_602_200)   // 2026-09-28T13:30:00Z

    func testCalBooksOnCalComWithTheAttendeeAndGuests() throws {
        XCTAssertEqual(CalBooking.isoUTC(start), "2026-09-28T13:30:00.000Z")
        let fake = FakeCal([("https://api.cal.com/v2/bookings", 200, """
            {"status":"success","data":{"uid":"bk_1","start":"2026-09-28T13:30:00.000Z","end":"2026-09-28T14:00:00.000Z",
            "title":"30 min between Jane and Sam Lee","meetingUrl":"https://app.cal.com/video/bk_1"}}
            """)])
        guard case .ok(let b) = CalBooking.book(link: "cal.com/book-test/30min", start: start, name: "Sam Lee",
                                                email: "sam@example.com", guests: ["ria@example.com", "SAM@example.com"],
                                                tz: "Asia/Kolkata", http: fake.http) else { return XCTFail("not booked") }
        XCTAssertEqual(b.uid, "bk_1")
        XCTAssertEqual(b.meetingUrl, "https://app.cal.com/video/bk_1")
        XCTAssertEqual(b.invited, ["sam@example.com", "ria@example.com", "SAM@example.com"])
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(fake.asked[0].body)) as? NSDictionary)
        XCTAssertEqual(sent, [
            "start": "2026-09-28T13:30:00.000Z", "eventTypeSlug": "30min", "username": "book-test",
            "attendee": ["name": "Sam Lee", "email": "sam@example.com", "timeZone": "Asia/Kolkata"],
            "guests": ["ria@example.com"],
        ] as NSDictionary)
        XCTAssertEqual(fake.asked[0].headers["cal-api-version"], "2026-02-25")
        XCTAssertEqual(fake.asked[0].method, "POST")
    }

    func testCalSaysATakenTimePlainlyAndKeepsCalendlyToItsOwnPage() {
        let taken = FakeCal([("https://api.cal.com/v2/bookings", 400,
                              #"{"status":"error","error":{"message":"User either already has booking at this time or is not available"}}"#)])
        XCTAssertEqual(refused(CalBooking.book(link: "cal.com/book-test/30min", start: start, name: "Sam Lee",
                                               email: "sam@example.com", guests: [], tz: "Asia/Kolkata", http: taken.http)),
                       "That time was just taken. Pick another")
        XCTAssertEqual(refused(CalBooking.book(link: "calendly.com/jane/intro", start: start, name: "Sam Lee",
                                               email: "sam@example.com", guests: [], tz: "UTC", http: taken.http)),
                       "Calendly books only on its own page. Send the link instead")
        XCTAssertEqual(refused(CalBooking.book(link: "cal.com/book-test/30min", start: start, name: "Sam Lee",
                                               email: "not-an-email", guests: [], tz: "UTC", http: taken.http)),
                       "Check the email addresses")
        let owner = FakeCal([("https://api.cal.com/v2/bookings", 401, #"{"error":{"message":"Needs authentication"}}"#)])
        XCTAssertEqual(refused(CalBooking.book(link: "cal.com/b/30min", start: start, name: "Sam", email: "sam@example.com",
                                               guests: [], tz: "UTC", http: owner.http)),
                       "This page only takes bookings on Cal.com itself. Send the link instead")
        let other = FakeCal([("https://api.cal.com/v2/bookings", 400, #"{"message":["Name too short","Bad thing"]}"#)])
        XCTAssertEqual(refused(CalBooking.book(link: "cal.com/b/30min", start: start, name: "Sam", email: "sam@example.com",
                                               guests: [], tz: "UTC", http: other.http)),
                       "Cal.com said: Name too short, Bad thing")
    }

    func testCalHandsABookingToTheServerOnlyWhenNothingWasSent() {
        let offline = FakeCal([], fail: CalBooking.NotSent())
        XCTAssertTrue(unreachable(CalBooking.book(link: "cal.com/b/30min", start: start, name: "Sam", email: "sam@example.com",
                                                  guests: [], tz: "UTC", http: offline.http)))
        let busy = FakeCal([("https://api.cal.com/v2/bookings", 429, "{}")])
        XCTAssertTrue(unreachable(CalBooking.book(link: "cal.com/b/30min", start: start, name: "Sam", email: "sam@example.com",
                                                  guests: [], tz: "UTC", http: busy.http)))
        // Lost on the way: it may have booked, so never a second try.
        let lost = FakeCal([], fail: URLError(.timedOut))
        XCTAssertEqual(refused(CalBooking.book(link: "cal.com/b/30min", start: start, name: "Sam", email: "sam@example.com",
                                               guests: [], tz: "UTC", http: lost.http)),
                       "Cal.com didn't answer. Try again")
    }

    // MARK: Glyf's swap fee (docs/SWAP-FEE.md)

    func testSwapFeeShipsOffSoTheBuyQuoteIsAskedAsBefore() throws {
        XCTAssertEqual(SwapFee.referralAccount, "")
        let url = try XCTUnwrap(SwapFee.orderURL(inputMint: "So11111111111111111111111111111111111111112",
                                                 outputMint: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
                                                 units: 100_000_000))
        XCTAssertEqual(url.absoluteString, "https://api.jup.ag/swap/v2/order?inputMint=So11111111111111111111111111111111111111112"
                       + "&outputMint=DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263&amount=100000000")
    }

    func testSwapFeeAddsTheReferralAccountAndFiftyBps() throws {
        let url = try XCTUnwrap(SwapFee.orderURL(inputMint: "A", outputMint: "B", units: 5,
                                                 referral: "18LeLp3B8yGctKtWKAXXqdB6Lf1GxmEa2fRL5xxa1ta"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "referralAccount" }?.value, "18LeLp3B8yGctKtWKAXXqdB6Lf1GxmEa2fRL5xxa1ta")
        XCTAssertEqual(items.first { $0.name == "referralFee" }?.value, "50")
        XCTAssert((50...255).contains(SwapFee.bps))
    }

    func testSwapFeeShowsOnlyWhenJupiterAppliedIt() {
        // Recorded from /swap/v2/order, 2026-10-14.
        XCTAssertNil(SwapFee.applied(["feeBps": 10, "feeMint": "So11111111111111111111111111111111111111112"]))
        XCTAssertEqual(SwapFee.applied(["feeBps": 50, "referralAccount": "18LeLp3B8yGctKtWKAXXqdB6Lf1GxmEa2fRL5xxa1ta"]), 50)
        XCTAssertEqual(SwapFee.label(50), "Fee 0.5%")
        XCTAssertEqual(SwapFee.label(100), "Fee 1%")
        XCTAssertEqual(SwapFee.label(255), "Fee 2.55%")
    }
}
