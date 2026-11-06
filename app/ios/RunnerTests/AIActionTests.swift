import XCTest
@testable import Runner

/// Recurring buys read on the phone (TradeRecurring.swift) and the strip's
/// recommended actions from POST /suggest (AIAction.swift).
final class AIActionTests: XCTestCase {

    private let month = 30 * 86_400

    func testADCAEachMonthIsOneFlashTWAPOfItsFirstMonth() throws {
        let i = try XCTUnwrap(TradeIntent.parse("dca $20 in eth each month"))
        XCTAssertEqual(i.kind, .twap)
        XCTAssertEqual(i.venue, "Flash")
        XCTAssertEqual(i.buy, "ETH")
        XCTAssertEqual(i.sell, "USDC")
        XCTAssertTrue(i.amountIsUSD)
        // Flash runs a TWAP 30 days at most: the order is the first month.
        XCTAssertEqual(i.amount, "20")
        XCTAssertEqual(i.durationSeconds, month)
        let plan = try XCTUnwrap(i.plan)
        XCTAssertEqual(plan, RecurringPlan(every: "20", period: .month, periods: 12, placed: 1))
        XCTAssertEqual(i.title, "DCA $20 of ETH monthly")
        XCTAssertEqual(plan.summary, "$20 monthly · 12 months")
        XCTAssertEqual(plan.capNote, "Flash runs 30 days at most · 1 of 12 months")
    }

    func testTheWaysPeopleSayIt() throws {
        let weekly = try XCTUnwrap(TradeIntent.parse("dca 20$ eth weekly"))
        XCTAssertEqual(weekly.plan?.period, .week)
        XCTAssertEqual(weekly.plan?.every, "20")
        XCTAssertEqual(weekly.plan?.periods, 4)
        XCTAssertEqual(weekly.amount, "80")
        XCTAssertEqual(weekly.durationSeconds, 28 * 86_400)
        XCTAssertNil(weekly.plan?.capNote)

        let btc = try XCTUnwrap(TradeIntent.parse("buy $50 of btc every week for 3 months"))
        XCTAssertEqual(btc.buy, "WBTC")
        XCTAssertEqual(btc.plan?.periods, 13)
        XCTAssertEqual(btc.plan?.placed, 4)
        XCTAssertEqual(btc.amount, "200")
        XCTAssertEqual(btc.plan?.capNote, "Flash runs 30 days at most · 4 of 13 weeks")

        let sol = try XCTUnwrap(TradeIntent.parse("invest 100 usdc in sol monthly"))
        XCTAssertEqual(sol.buy, "SOL")
        XCTAssertEqual(sol.sell, "USDC")
        XCTAssertEqual(sol.chainName, "solana")
        XCTAssertEqual(sol.amount, "100")
        XCTAssertEqual(sol.title, "DCA $100 of SOL monthly")

        XCTAssertEqual(TradeIntent.parse("dca $10 into eth every 2 weeks")?.plan?.interval, 2)
        XCTAssertEqual(TradeIntent.parse("dca $10 into eth biweekly")?.plan?.periods, 4)
        XCTAssertEqual(TradeIntent.parse("invest $25 in eth monthly for a year")?.plan?.periods, 12)
        XCTAssertEqual(TradeIntent.parse("Buy $30 of ETH every month on arbitrum.")?.chainName, "arbitrum")
    }

    func testAShortScheduleStaysTheTWAPItWas() throws {
        // Inside Flash's 30 days: one order spread over the whole span, as before.
        let i = try XCTUnwrap(TradeIntent.parse("buy $20 of eth every day for a week"))
        XCTAssertNil(i.plan)
        XCTAssertEqual(i.title, "Buy $140 of ETH over a week")
        // Past 30 days ("weekly" read as 7 weeks): now the recurring plan.
        let long = try XCTUnwrap(TradeIntent.parse("dca $50 into eth weekly"))
        XCTAssertEqual(long.plan?.period, .week)
        XCTAssertLessThanOrEqual(long.durationSeconds ?? 0, RecurringPlan.flashMaxSeconds)
    }

    func testNotEveryRepeatIsATrade() {
        XCTAssertNil(TradeIntent.parse("i put $20 in the jar every month"))
        XCTAssertNil(TradeIntent.parse("dca $20 in usdc each month"))
        XCTAssertNil(TradeIntent.parse("we should invest more time in this every week"))
    }

    // MARK: actions from the server

    private func action(_ tool: String, _ params: [String: Any], label: String = "x") -> AIAction? {
        AIAction.from(json: ["tool": tool, "label": label, "params": params])
    }

    func testADCAActionOpensTheTradePanelFilledIn() throws {
        let a = try XCTUnwrap(action("trade.dca", ["asset": "ETH", "every": 20, "period": "month"],
                                     label: "DCA $20 of ETH monthly · Flash"))
        guard case .trade(let t)? = a.chip else { return XCTFail("not a trade chip") }
        XCTAssertEqual(t, TradeIntent.parse("dca $20 in eth each month"))
        XCTAssertEqual(t.plan?.periods, 12)
        let weeks = try XCTUnwrap(action("trade.dca", ["asset": "WBTC", "every": "50", "period": "week", "periods": 13]))
        XCTAssertEqual(weeks.trade?.plan?.placed, 4)
    }

    func testTradeActionsReadAsTheWordsWould() throws {
        let cases: [([String: Any], String, String)] = [
            (["type": "stop-loss", "asset": "ETH", "price": "3000"], "trade.flash", "stop loss eth at 3000"),
            (["type": "take-profit", "asset": "ETH", "price": 4500, "amount": 0.1], "trade.flash", "take profit 0.1 eth at 4500"),
            (["type": "limit", "asset": "ETH", "side": "buy", "usd": true, "amount": 100, "price": 2800], "trade.flash", "buy $100 of eth at 2800"),
            (["type": "bracket", "asset": "ETH", "price": 4500, "stopPrice": 3000], "trade.flash", "my eth tp 4500 sl 3000"),
            (["type": "trailing-stop", "asset": "ETH", "trailPercent": 5], "trade.flash", "trail my eth by 5%"),
            (["type": "twap", "asset": "ETH", "amount": 100, "hours": 48], "trade.flash", "buy $100 of eth over 2 days"),
            (["sell": "ETH", "buy": "USDC", "amount": 0.05, "chain": "base"], "trade.swap", "swap 0.05 eth to usdc on base"),
            (["sell": "USDC", "buy": "ETH", "amount": 20, "usd": true], "trade.swap", "buy $20 of eth"),
            (["asset": "USDC", "amount": 50, "from": "base", "to": "arbitrum"], "trade.bridge", "move 50 usdc from base to arbitrum"),
            (["to": "arpit.eth", "amount": 5, "token": "USDC"], "send", "send 5 usdc to arpit.eth"),
        ]
        for (params, tool, words) in cases {
            let a = try XCTUnwrap(action(tool, params), words)
            XCTAssertEqual(a.trade, TradeIntent.parse(words), words)
        }
    }

    func testOtherToolsOpenTheirPanels() throws {
        guard case .event(let plan)? = action("calendar.event", ["title": "Dinner with Sam", "when": "friday 8pm"])?.chip
        else { return XCTFail("no event") }
        XCTAssertTrue(plan.hasDay)
        XCTAssertTrue(plan.hasTime)
        XCTAssertEqual(action("meet.link", [:])?.chip, .action(label: "Add a Meet link", query: "", intent: "meet"))
        XCTAssertEqual(action("youtube", ["query": "dune 2 trailer"], label: "YouTube: dune 2 trailer")?.chip,
                       .action(label: "YouTube: dune 2 trailer", query: "dune 2 trailer", intent: "open:youtube"))
        XCTAssertEqual(action("maps", ["query": "ramen near me"])?.chip,
                       .action(label: "x", query: "ramen near me", intent: "open:maps"))
        XCTAssertEqual(action("translate", ["to": "spanish"])?.chip,
                       .action(label: "x", query: "Spanish", intent: "open:translate"))
        XCTAssertEqual(action("rewrite", [:])?.chip, .action(label: "x", query: "", intent: "rewrite"))
    }

    func testWhatThisPhoneCantOpenIsDropped() {
        XCTAssertNil(action("trade.yolo", [:]))
        XCTAssertNil(action("trade.flash", ["type": "stop-loss", "asset": "DOGE", "price": 1]))
        XCTAssertNil(action("calendar.event", ["title": "stuff", "when": "sometime"]))
        XCTAssertNil(action("search", ["query": ""]))
        XCTAssertNil(action("booking.link", [:]))
        XCTAssertNil(AIAction.from(json: ["tool": "meet.link"]))
    }
}

extension AIActionTests {
    func testThePanelShowsThePlanUntilItIsChanged() throws {
        var i = try XCTUnwrap(TradeIntent.parse("dca $20 in eth each month"))
        XCTAssertEqual(i.planOverRow?.label, "Over · Flash max")
        XCTAssertEqual(i.planOverRow?.value, "30 days · month 1 of 12")
        XCTAssertEqual(TradeIntent.parse("buy $50 of btc every week for 3 months")?.planOverRow?.value, "4 weeks · weeks 1–4 of 13")
        XCTAssertEqual(TradeIntent.parse("dca 20$ eth weekly")?.planOverRow?.value, "4 weeks · $20 weekly")
        i.amount = "35"
        XCTAssertNil(i.planOverRow)
        XCTAssertNil(TradeIntent.parse("buy $20 of eth every day for a week")?.planOverRow)
    }
}
