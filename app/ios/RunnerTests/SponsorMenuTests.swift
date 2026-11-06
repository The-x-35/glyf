import XCTest
@testable import Runner

/// The g menu's sponsor row (ETHGlobal Mumbai): which apps show, what each
/// one's panel lists, and what every option on it puts up. A tap on a card
/// only opens its panel (Arpit, 2026-11-06: "should not trigger a thing by
/// default. It should show all the options").
final class SponsorMenuTests: XCTestCase {

    private func options(_ entries: [SponsorMenu.Entry]) -> [SponsorMenu.Option] {
        entries.compactMap { if case .option(let o, _, _, _) = $0 { return o }; return nil }
    }

    private func trade(_ option: SponsorMenu.Option, typed: String = "", chain: String = "base",
                       file: StaticString = #filePath, line: UInt = #line) -> TradeIntent? {
        guard case .trade(let t)? = SponsorMenu.action(for: option, typed: typed, flashChain: chain) else {
            XCTFail("\(option) should open the trade panel", file: file, line: line)
            return nil
        }
        return t
    }

    func testUniswapAndDefinitiveAlwaysShowAndZeroGOnlyWhereTheAppWroteIt() {
        XCTAssertEqual(SponsorMenu.sponsors(privateAI: nil), [.uniswap, .definitive])
        XCTAssertEqual(SponsorMenu.sponsors(privateAI: true), [.uniswap, .definitive, .zeroG])
        // Turned off is still the hackathon build: the icon stays, to turn it on.
        XCTAssertEqual(SponsorMenu.sponsors(privateAI: false), [.uniswap, .definitive, .zeroG])
        XCTAssertEqual(SponsorMenu.Sponsor.allCases.map(\.title), ["Uniswap", "Definitive", "0G"])
    }

    func testEachSponsorIsAShellScreen() {
        for sponsor in SponsorMenu.Sponsor.allCases {
            XCTAssertEqual(SponsorMenu.Sponsor(screenId: sponsor.screenId), sponsor)
        }
        XCTAssertEqual(SponsorMenu.Sponsor.zeroG.screenId, "sponsor:0g")
        XCTAssertNil(SponsorMenu.Sponsor(screenId: "vault"))
        XCTAssertNil(SponsorMenu.Sponsor(screenId: "sponsor:world"))
    }

    func testOptionIdsRoundTrip() {
        var all: [SponsorMenu.Option] = [.swap, .jupiter, .typed, .openOrders, .receipts]
        all += SponsorMenu.swapChains.map { .swapOn($0) }
        all += SponsorMenu.orderKinds.map { .order($0) }
        for option in all { XCTAssertEqual(SponsorMenu.Option(id: option.id), option, option.id) }
        XCTAssertNil(SponsorMenu.Option(id: "swap:polygon"))
        XCTAssertNil(SponsorMenu.Option(id: "order:send"))
        XCTAssertNil(SponsorMenu.Option(id: "nope"))
    }

    // MARK: Uniswap

    func testUniswapListsSwapAndEveryChain() {
        let entries = SponsorMenu.entries(for: .uniswap, typed: "", privateAI: nil)
        XCTAssertEqual(options(entries), [.swap] + ["base", "ethereum", "arbitrum", "optimism", "unichain"].map { .swapOn($0) } + [.jupiter])
        XCTAssertEqual(entries[0], .option(.swap, title: "Swap", detail: "10 USDC → ETH", icon: "arrow.left.arrow.right"))
        XCTAssertEqual(entries[1], .header("Chains"))
        guard case .option(_, let title, _, _) = entries[3] else { return XCTFail() }
        XCTAssertEqual(title, "Ethereum")
    }

    func testUniswapSwapIsTheStarterOnBase() throws {
        let t = try XCTUnwrap(trade(.swap))
        XCTAssertEqual(t.kind, .swap)
        XCTAssertEqual(t.venue, "Uniswap")
        XCTAssertEqual(t.amount, "10")
        XCTAssertEqual(t.sell, "USDC")
        XCTAssertEqual(t.buy, "ETH")
        XCTAssertEqual(t.chainName, "base")
    }

    func testUniswapSwapTakesTheSwapAlreadyTypedAndSaysSo() {
        let typed = "sure. swap 0.05 eth to usdc on arbitrum"
        XCTAssertEqual(trade(.swap, typed: typed), TradeIntent.parse(typed))
        let entries = SponsorMenu.entries(for: .uniswap, typed: typed, privateAI: nil)
        XCTAssertEqual(entries[0], .option(.swap, title: "Swap", detail: "0.05 ETH → USDC", icon: "arrow.left.arrow.right"))
        // A Flash order typed is not Uniswap's: the starter swap instead.
        XCTAssertEqual(trade(.swap, typed: "stop-loss eth at 2800"), SponsorMenu.starterSwap(on: "base"))
    }

    func testEachChainStartsASwapThere() {
        for chain in SponsorMenu.swapChains {
            let t = trade(.swapOn(chain))
            XCTAssertEqual(t?.kind, .swap)
            XCTAssertEqual(t?.chainName, chain)
            XCTAssertEqual(t?.sell, "USDC")
            XCTAssertEqual(t?.buy, "ETH")
        }
    }

    // MARK: Definitive

    func testDefinitiveListsTheChainEveryOrderTypeAndOpenOrders() {
        let entries = SponsorMenu.entries(for: .definitive, typed: "hello", privateAI: nil)
        XCTAssertEqual(entries.first, .chainPicker)
        XCTAssertEqual(entries[1], .header("Orders"))
        XCTAssertEqual(options(entries),
                       [.limit, .stop, .stopLoss, .takeProfit, .bracket, .trailingStop, .twap, .bridge].map { .order($0) }
                       + [.openOrders])
        let titles = entries.compactMap { e -> String? in if case .option(_, let t, _, _) = e { return t }; return nil }
        XCTAssertEqual(titles, ["Limit buy", "Stop buy", "Stop-loss", "Take profit", "Bracket", "Trailing stop",
                                "TWAP", "Bridge", "Open orders"])
        XCTAssertEqual(SponsorMenu.orderDetail(.bridge, chain: "base"), "→ Arbitrum")
        XCTAssertEqual(SponsorMenu.orderDetail(.bridge, chain: "solana"), "→ Base")
    }

    func testDefinitiveOffersTheFlashOrderTypedFirst() {
        let typed = "stop-loss eth at 2800"
        let entries = SponsorMenu.entries(for: .definitive, typed: typed, privateAI: nil)
        XCTAssertEqual(entries[2], .option(.typed, title: "Stop-loss ETH at $2,800", detail: nil, icon: "text.cursor"))
        XCTAssertEqual(trade(.typed, typed: typed), TradeIntent.parse(typed))
        // A swap typed is Uniswap's, not an order: no typed row.
        XCTAssertFalse(options(SponsorMenu.entries(for: .definitive, typed: "swap 1 eth to usdc", privateAI: nil))
            .contains(.typed))
        XCTAssertNil(SponsorMenu.action(for: .typed, typed: "hello"))
    }

    func testEveryOrderTypeStartsOnBaseWithETH() throws {
        for kind in SponsorMenu.orderKinds {
            let t = try XCTUnwrap(trade(.order(kind)), "\(kind)")
            XCTAssertEqual(t.kind, kind)
            XCTAssertEqual(t.venue, "Flash")
            XCTAssertEqual(t.chainName, "base", "\(kind)")
        }
        let limit = try XCTUnwrap(trade(.order(.limit)))
        XCTAssertEqual(limit.buy, "ETH")
        XCTAssertEqual(limit.sell, "USDC")
        XCTAssertEqual(limit.amount, "20")
        XCTAssertTrue(limit.amountIsUSD)
        let stopLoss = try XCTUnwrap(trade(.order(.stopLoss)))
        XCTAssertEqual(stopLoss.sell, "ETH")
        XCTAssertNil(stopLoss.amount, "guards everything held")
        let trail = try XCTUnwrap(trade(.order(.trailingStop)))
        XCTAssertEqual(trail.trailPercent, "10")
        XCTAssertNil(trail.price)
        XCTAssertFalse(trail.awaitingPrice)
        let twap = try XCTUnwrap(trade(.order(.twap)))
        XCTAssertEqual(twap.amount, "20")
        XCTAssertEqual(twap.durationSeconds, 86_400)
        let bridge = try XCTUnwrap(trade(.order(.bridge)))
        XCTAssertEqual(bridge.sell, "USDC")
        XCTAssertEqual(bridge.toChain, "arbitrum")
    }

    func testPricedOrdersWaitForTheMarketAndSitTheRightSideOfIt() throws {
        let cases: [(TradeIntent.Kind, Double, Double?)] = [
            (.limit, -5, nil), (.stop, 5, nil), (.stopLoss, -10, nil), (.takeProfit, 10, nil), (.bracket, 10, -10),
        ]
        for (kind, pct, stopPct) in cases {
            let t = try XCTUnwrap(trade(.order(kind)), "\(kind)")
            XCTAssertNil(t.price, "\(kind): no made-up price")
            XCTAssertEqual(t.pricePercent, pct, "\(kind)")
            XCTAssertEqual(t.stopPercent, stopPct, "\(kind)")
            XCTAssertTrue(t.awaitingPrice)
        }
        let stopLoss = SponsorMenu.priced(try XCTUnwrap(trade(.order(.stopLoss))), market: 3_183.42)
        XCTAssertEqual(stopLoss.price, "2870")
        XCTAssertFalse(stopLoss.awaitingPrice)
        XCTAssertEqual(stopLoss.title, "Stop-loss ETH at $2,870")
        XCTAssertEqual(stopLoss.query["price"], "2870")
        let bracket = SponsorMenu.priced(try XCTUnwrap(trade(.order(.bracket))), market: 3_000)
        XCTAssertEqual(bracket.price, "3300")
        XCTAssertEqual(bracket.stopPrice, "2700")
        let limit = SponsorMenu.priced(try XCTUnwrap(trade(.order(.limit))), market: 3_000)
        XCTAssertEqual(limit.price, "2850")
        let stop = SponsorMenu.priced(try XCTUnwrap(trade(.order(.stop))), market: 3_000)
        XCTAssertEqual(stop.price, "3150")
        // No price, no change: the panel keeps waiting rather than guess.
        let waiting = try XCTUnwrap(trade(.order(.takeProfit)))
        XCTAssertEqual(SponsorMenu.priced(waiting, market: 0), waiting)
    }

    func testPricesRoundTheWayPeopleSayThem() {
        XCTAssertEqual(SponsorMenu.roundPrice(2_865.07), "2870")
        XCTAssertEqual(SponsorMenu.roundPrice(142.37), "142")
        XCTAssertEqual(SponsorMenu.roundPrice(21.456), "21.46")
        XCTAssertEqual(SponsorMenu.roundPrice(0.123456), "0.1235")
    }

    func testOnSolanaTheOrdersAreSOLs() throws {
        for kind in SponsorMenu.orderKinds {
            let t = try XCTUnwrap(trade(.order(kind), chain: "solana"), "\(kind)")
            XCTAssertEqual(t.kind, kind)
            XCTAssertEqual(t.chainName, "solana", "\(kind)")
        }
        XCTAssertEqual(trade(.order(.stopLoss), chain: "solana")?.sell, "SOL")
        XCTAssertEqual(trade(.order(.limit), chain: "solana")?.buy, "SOL")
        XCTAssertEqual(trade(.order(.trailingStop), chain: "solana")?.sell, "SOL")
        let bridge = try XCTUnwrap(trade(.order(.bridge), chain: "solana"))
        XCTAssertEqual(bridge.toChain, "base")
    }

    /// Solana sits under Uniswap's chains as Jupiter (Uniswap's own app
    /// routes Solana through Jupiter), and opens the keyboard's Buy panel.
    func testSolanaSwapsGoThroughJupiter() {
        let entries = SponsorMenu.entries(for: .uniswap, typed: "", privateAI: nil)
        XCTAssertEqual(entries.last, .option(.jupiter, title: "Solana", detail: "Jupiter", icon: "chain:solana"))
        XCTAssertEqual(SponsorMenu.action(for: .jupiter, typed: ""), .solanaSwap)
        XCTAssertEqual(TradeIntent.parse("swap 10 usdc to usdt on solana")?.venue, "Jupiter")
        XCTAssertEqual(TradeIntent.parse("swap 10 usdc to eth on base")?.venue, "Uniswap")
    }

    func testOpenOrdersAndReceiptsOpenTheApp() {
        XCTAssertEqual(SponsorMenu.action(for: .openOrders, typed: ""), .openApp(path: "evm-wallet"))
        XCTAssertEqual(SponsorMenu.action(for: .receipts, typed: ""), .openApp(path: "settings"))
    }

    // MARK: 0G

    func testZeroGShowsTheSwitchTheLastAnswerAndReceipts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let at = (now.timeIntervalSince1970 - 180) * 1000
        let on = SponsorMenu.entries(for: .zeroG, typed: "", privateAI: true,
                                     receipts: [["at": at, "teeVerified": true, "model": "0gm"]],
                                     receiptsLoaded: true, now: now)
        XCTAssertEqual(on, [
            .privateAISwitch,
            .header("Last answer"),
            .status(title: "When", value: "3 min ago", icon: "clock"),
            .status(title: "TEE", value: "Verified", icon: "lock.shield"),
            .option(.receipts, title: "Receipts", detail: nil, icon: "checkmark.seal"),
        ])
        // Off: nothing to say about answers, just the switch and the receipts.
        XCTAssertEqual(SponsorMenu.entries(for: .zeroG, typed: "", privateAI: false),
                       [.privateAISwitch, .option(.receipts, title: "Receipts", detail: nil, icon: "checkmark.seal")])
    }

    func testTheLastAnswerStatus() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let at = (now.timeIntervalSince1970 - 7_200) * 1000
        XCTAssertEqual(SponsorMenu.status(receipts: [["at": at, "teeVerified": NSNull()]], loaded: true, now: now).last, "2 h ago")
        XCTAssertEqual(SponsorMenu.status(receipts: [["at": at, "teeVerified": NSNull()]], loaded: true, now: now).tee, "Not verified")
        XCTAssertEqual(SponsorMenu.status(receipts: [], loaded: true, now: now).last, "None yet")
        // Still asking, and the server could not be reached.
        XCTAssertEqual(SponsorMenu.status(receipts: nil, loaded: false, now: now).last, "…")
        XCTAssertEqual(SponsorMenu.status(receipts: nil, loaded: true, now: now).tee, "—")
        XCTAssertEqual(SponsorMenu.ago(now.addingTimeInterval(-30), now: now), "Just now")
        XCTAssertEqual(SponsorMenu.ago(now.addingTimeInterval(-3 * 86_400), now: now), "3 d ago")
    }
}
