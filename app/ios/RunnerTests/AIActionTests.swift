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
        XCTAssertEqual(i.amount, "140")
        XCTAssertEqual(i.title, "Buy $20 of ETH every day for 7 days")
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
        // Sends to a name aren't one of this phone's tools.
        XCTAssertNil(action("send", ["to": "arpit.eth", "amount": 5, "token": "USDC"]))
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

    /// The live AI's answer for "grab 10 dollars of tesla whenever it slips
    /// under 300" opens as $10 of Tesla at $300 on Base.
    func testAnAIFlashOrderKeepsTheTypedValues() throws {
        let action = AIAction(tool: "trade.flash", label: "Buy TSLA at $300 · Flash", params: ["type": "limit", "asset": "TSLA", "amount": "10", "usd": "true", "price": "300"])
        let t = try XCTUnwrap(action.trade)
        XCTAssertEqual(t.kind, .limit)
        XCTAssertEqual(t.amount, "10")
        XCTAssertTrue(t.amountIsUSD)
        XCTAssertEqual(t.price, "300")
        XCTAssertEqual(t.buy, "TSLA")
        XCTAssertEqual(t.chainName, "base")
    }

    // MARK: NEAR Intents' tools (server lib/actions.ts, near: true)

    func testNEARSwapAndSendOpenTheNEARPanelThroughTheWords() throws {
        let swap = try XCTUnwrap(action("near.swap", ["sell": "USDC", "buy": "SOL", "amount": "20", "sellChain": "base"],
                                        label: "Swap 20 USDC → SOL · NEAR Intents"))
        guard case .trade(let t)? = swap.chip else { return XCTFail("no trade chip") }
        XCTAssertTrue(t.isNear)
        XCTAssertEqual(t.amount, "20")
        XCTAssertEqual(t.chainName, "base")
        XCTAssertEqual(t.buyChain, "solana")
        XCTAssertEqual(t, TradeIntent.parse("swap 20 usdc on base to sol"))
        // A coin with no chain sits at home, else on Base, as the server reads it.
        let btc = try XCTUnwrap(action("near.swap", ["sell": "USDC", "buy": "BTC", "amount": 50])?.trade)
        XCTAssertEqual(btc.buyChain, "bitcoin")
        XCTAssertEqual(btc.buy, "BTC")
        XCTAssertEqual(btc.chainName, "base")
        // No amount heard: the panel opens without one (and never says "all").
        let bare = try XCTUnwrap(action("near.swap", ["sell": "SOL", "buy": "USDC", "buyChain": "base"])?.trade)
        XCTAssertNil(bare.amount)
        XCTAssertEqual(bare.title, "Swap SOL → USDC")
        // The same coin across chains is a move.
        let move = try XCTUnwrap(action("near.swap", ["sell": "USDC", "buy": "USDC", "amount": 50, "buyChain": "solana"])?.trade)
        XCTAssertEqual(move.title, "Move 50 USDC to Solana")
        // A swap Uniswap does isn't NEAR's to open.
        XCTAssertNil(action("near.swap", ["sell": "USDC", "buy": "ETH", "amount": 5, "sellChain": "base", "buyChain": "arbitrum"]))

        let send = try XCTUnwrap(action("near.send", ["to": "alice.near", "amount": "5", "coin": "USDC"])?.trade)
        XCTAssertEqual(send.kind, .send)
        XCTAssertEqual(send.to, "alice.near")
        XCTAssertEqual(send.buyChain, "near")
        XCTAssertEqual(send.query["exact"], "out")
        let withSol = try XCTUnwrap(action("near.send", ["to": "bob.near", "amount": 10, "coin": "USDC", "with": "SOL"])?.trade)
        XCTAssertEqual(withSol.sell, "SOL")
        XCTAssertEqual(withSol.chainName, "solana")
        let arb = try XCTUnwrap(action("near.send", ["to": "bob.near", "amount": 10, "coin": "USDC", "with": "USDC",
                                                    "withChain": "arbitrum"])?.trade)
        XCTAssertEqual(arb.chainName, "arbitrum")
        let fromSol = try XCTUnwrap(action("near.send", ["to": "bob.near", "amount": 10, "withChain": "solana"])?.trade)
        XCTAssertEqual(fromSol.chainName, "solana")
        XCTAssertEqual(fromSol.sell, "USDC")
    }

    func testNEAREarnOpensEarnMode() throws {
        let fifty = try XCTUnwrap(action("near.earn", ["amount": "50", "coin": "USDC"])?.trade)
        XCTAssertEqual(fifty.kind, .earn)
        XCTAssertEqual(fifty, TradeIntent.parse("put $50 to work"))
        let sol = try XCTUnwrap(action("near.earn", ["amount": 0.5, "coin": "SOL"])?.trade)
        XCTAssertEqual(sol.chainName, "solana")
        let out = try XCTUnwrap(action("near.earn", ["coin": "USDC", "out": true])?.trade)
        XCTAssertTrue(out.earnOut)
        XCTAssertNil(out.amount)
        XCTAssertEqual(out.query["all"], "1")
        let twenty = try XCTUnwrap(action("near.earn", ["coin": "USDC", "amount": 20, "out": true, "chain": "solana"])?.trade)
        XCTAssertEqual(twenty.amount, "20")
        XCTAssertEqual(twenty.chainName, "solana")
        // No amount going in: the panel asks for it.
        let bare = try XCTUnwrap(action("near.earn", ["coin": "USDC"])?.trade)
        XCTAssertNil(bare.amount)
        XCTAssertFalse(bare.earnOut)
        XCTAssertEqual(bare.title, "Put USDC to work")
    }

    func testNEARRequestAndThePotAreChipsWithTheirParams() throws {
        let req = try XCTUnwrap(action("near.request", ["amount": "90", "count": 4, "us": true, "note": "dinner"],
                                       label: "Request $22.50 each · NEAR Intents"))
        guard case .action(let label, let query, let intent)? = req.chip else { return XCTFail("no request chip") }
        XCTAssertEqual(label, "Request $22.50 each · NEAR Intents")
        XCTAssertEqual(intent, "near:request")
        XCTAssertEqual(req.chip?.verb, "Request")
        let ask = try XCTUnwrap(PayAsk(params: [String: String](chipQuery: query)))
        XCTAssertEqual(ask, PayAsk(amount: "90", count: 4, us: true, note: "dinner"))
        XCTAssertNil(action("near.request", ["note": "dinner"]))

        let pot = try XCTUnwrap(action("near.pot", ["pot": "trip"], label: "See the trip pot · Sputnik DAO"))
        guard case .action(_, let pq, "near:pot")? = pot.chip else { return XCTFail("no pot chip") }
        XCTAssertEqual(PotAsk(params: [String: String](chipQuery: pq), pay: false)?.pot, "trip")
        XCTAssertEqual(pot.chip?.verb, "See")
        let pay = try XCTUnwrap(action("near.pot.pay", ["to": "the caterer", "amount": "120", "coin": "USDC"],
                                       label: "Propose $120 to caterer from the pot · Sputnik DAO"))
        guard case .action(_, let payQuery, "near:pot.pay")? = pay.chip else { return XCTFail("no payout chip") }
        let payAsk = try XCTUnwrap(PotAsk(params: [String: String](chipQuery: payQuery), pay: true))
        XCTAssertEqual(payAsk.to, "the caterer")
        XCTAssertEqual(payAsk.amount, "120")
        XCTAssertEqual(pay.chip?.verb, "Propose")
        XCTAssertNil(action("near.pot.pay", ["amount": "120"]))
    }

    // MARK: pay links (NearPay.swift)

    /// Where the requester is paid: the wallet on the chain asked, else
    /// MetaMask on Base, else the NEAR account; none, nothing is posted.
    func testTheRequesterIsPaidInTheirOwnWallet() throws {
        let r = { (chain: String?, evm: String?, sol: String?, near: String?) in
            PayAsk.receiver(chain: chain, evm: evm, solana: sol, near: near).map { "\($0.to)@\($0.chain)" } }
        XCTAssertEqual(r("solana", "0xab", "7xKX", "me.near"), "7xKX@solana")
        XCTAssertEqual(r("arbitrum", "0xab", "7xKX", nil), "0xab@arbitrum")
        XCTAssertEqual(r("near", "0xab", nil, "me.near"), "me.near@near")
        XCTAssertEqual(r(nil, "0xab", "7xKX", "me.near"), "0xab@base")
        XCTAssertEqual(r(nil, nil, "7xKX", "trip.sputnik-dao.near"), "trip.sputnik-dao.near@near")
        XCTAssertNil(r("solana", "0xab", nil, nil))
        XCTAssertNil(r(nil, nil, "7xKX", nil))
        XCTAssertEqual(PayAsk.noWallet, "Add a wallet in Glyf to get paid")
        let body = PayAsk(amount: "90", count: 4, us: true, note: "dinner").body(to: "0xab", chain: "base")
        XCTAssertEqual(body["amount"] as? String, "90")
        XCTAssertEqual(body["count"] as? Int, 4)
        XCTAssertEqual(body["us"] as? Bool, true)
        XCTAssertEqual(body["note"] as? String, "dinner")
        XCTAssertEqual(body["to"] as? String, "0xab")
        XCTAssertEqual(body["chain"] as? String, "base")
        XCTAssertNil(body["each"])
        let each = PayAsk(params: ["amount": "22.5", "each": "true", "count": "4", "chain": "solana"])
        XCTAssertEqual(each?.body(to: "7xKX", chain: "solana")["each"] as? Bool, true)
    }

    /// The bill split's chip asks for the money: one card, Insert and Request.
    func testABillSplitInDollarsCanBeRequested() throws {
        let c = try XCTUnwrap(Smart.billMath(in: "dinner was $90 for 4 of us"))
        XCTAssertEqual(c.results, ["$22.50 each"])
        XCTAssertEqual(c.request, PayAsk(amount: "90", count: 4, us: true, note: "dinner"))
        let chip = Smart.Chip.convert(c)
        XCTAssertNil(chip.choices)
        XCTAssertEqual(chip.verb, "Insert")
        XCTAssertEqual(chip.extra, "Request")
        XCTAssertEqual(Smart.billMath(in: "the cabin is $1,200 for 6 people")?.request,
                       PayAsk(amount: "1200", count: 6, note: "cabin"))
        XCTAssertEqual(Smart.billMath(in: "split the cab $60 3 ways")?.request?.note, "cab")
        XCTAssertNil(Smart.billMath(in: "split the bill $60 3 ways")?.request?.note)
        XCTAssertEqual(Smart.billMath(in: "split $90 between 4 people")?.request?.us, false)
        // Rupees aren't asked for: a pay link is paid in dollars.
        let rupees = try XCTUnwrap(Smart.billMath(in: "split ₹900 between 4 people"))
        XCTAssertNil(rupees.request)
        XCTAssertNotNil(Smart.Chip.convert(rupees).choices)
    }

    // MARK: the group pot

    func testPotPhrasesAreReadOnThePhone() throws {
        XCTAssertEqual(PotAsk.parse("how much is in the trip pot"), PotAsk(pay: false, pot: "trip"))
        XCTAssertEqual(PotAsk.parse("what's in the pot?"), PotAsk(pay: false))
        XCTAssertEqual(PotAsk.parse("check the trip pot"), PotAsk(pay: false, pot: "trip"))
        XCTAssertEqual(PotAsk.parse("pot balance"), PotAsk(pay: false))
        XCTAssertEqual(PotAsk.parse("how much is in build.sputnik-dao.near"), PotAsk(pay: false, dao: "build.sputnik-dao.near"))
        XCTAssertEqual(PotAsk.parse("pay the caterer $120 from the pot"),
                       PotAsk(pay: true, to: "the caterer", amount: "120", coin: "USDC"))
        XCTAssertEqual(PotAsk.parse("pay caterer.near 120 usdc from the trip pot for catering"),
                       PotAsk(pay: true, pot: "trip", to: "caterer.near", amount: "120", coin: "USDC", note: "catering"))
        XCTAssertEqual(PotAsk.parse("send bob.near 5 near out of the pot"),
                       PotAsk(pay: true, to: "bob.near", amount: "5", coin: "NEAR"))
        for t in ["pay the caterer $120", "the pot is on the stove", "take it out"] { XCTAssertNil(PotAsk.parse(t), t) }
        guard case .action(let label, _, "near:pot")? = Smart.chip(for: "how much is in the trip pot", fields: []) else {
            return XCTFail("no pot chip")
        }
        XCTAssertEqual(label, "See the trip pot · Sputnik DAO")
        guard case .action(let payLabel, _, "near:pot.pay")? = Smart.chip(for: "pay the caterer $120 from the pot", fields: []) else {
            return XCTFail("no payout chip")
        }
        XCTAssertEqual(payLabel, "Propose $120 to caterer from the pot · Sputnik DAO")
        XCTAssertEqual(PotAsk(pay: true, to: "bob.near", amount: "5", coin: "NEAR", note: nil).label,
                       "Propose 5 NEAR to bob.near from the pot · Sputnik DAO")
    }

    /// Which pot a chip means: the typed DAO, the saved pot, a Sputnik DAO
    /// saved as the NEAR account, then the word's.
    func testWhichPot() {
        let trip = PotAsk(pay: false, pot: "trip")
        XCTAssertEqual(trip.daoAccount(saved: "lisbon.sputnik-dao.near", account: nil), "lisbon.sputnik-dao.near")
        XCTAssertEqual(trip.daoAccount(saved: nil, account: "club.sputnik-dao.near"), "club.sputnik-dao.near")
        XCTAssertEqual(trip.daoAccount(saved: nil, account: "me.near"), "trip.sputnik-dao.near")
        XCTAssertEqual(PotAsk(pay: false, dao: "build.sputnik-dao.near").daoAccount(saved: "x.sputnik-dao.near", account: nil),
                       "build.sputnik-dao.near")
        XCTAssertNil(PotAsk(pay: false).daoAccount(saved: nil, account: "me.near"))
        XCTAssertEqual(PotAsk.noPot, "Add your pot in Glyf")
        XCTAssertTrue(PotAsk.isNEARAccount("caterer.near"))
        XCTAssertFalse(PotAsk.isNEARAccount("the caterer"))
    }

    /// GET /near/pot (shaped like build.sputnik-dao.near's) and
    /// GET /near/pot/propose-link, as the pot card says them.
    func testThePotCardReads() throws {
        let pot: [String: Any] = ["ok": true, "dao": "trip.sputnik-dao.near",
            "text": "The trip pot holds 42.5 NEAR · 140.5 USDC. 4 members, payouts need 2 of 3. 2 proposals open",
            "links": ["trezu": "https://trezu.app/trip.sputnik-dao.near/dashboard"],
            "proposals": [
                ["id": 5, "kind": "Transfer", "description": "Caterer", "amount": "12.5", "coin": "NEAR",
                 "receiver": "caterer.near", "status": "InProgress", "approvalsNeeded": 1,
                 "url": "https://trezu.app/trip.sputnik-dao.near/requests/5"],
                ["id": 4, "kind": "AddMemberToRole", "description": "Add dee\nPlease", "status": "InProgress",
                 "approvalsNeeded": 2, "url": "https://trezu.app/trip.sputnik-dao.near/requests/4"],
                ["id": 3, "kind": "Transfer", "amount": "1", "coin": "USDC", "receiver": "x.near", "status": "Approved"]]]
        let v = PotView(ok: true, pot)
        XCTAssertEqual(v.text, "The trip pot holds 42.5 NEAR · 140.5 USDC. 4 members, payouts need 2 of 3. 2 proposals open")
        XCTAssertEqual(v.open.map(\.line), ["#5 12.5 NEAR to caterer.near · 1 more approval", "#4 Add dee · 2 more approvals"])
        XCTAssertEqual(v.open.first?.url, "https://trezu.app/trip.sputnik-dao.near/requests/5")
        XCTAssertEqual(PotView(ok: false, ["ok": false, "error": "No Sputnik DAO nope.sputnik-dao.near"]).error,
                       "No Sputnik DAO nope.sputnik-dao.near")

        let link: [String: Any] = ["ok": true, "url": "https://trezu.app/trip.sputnik-dao.near/payments?address=caterer.near&token=usdc",
            "fill": ["amount": "120", "coin": "USDC", "note": "catering"],
            "text": "Proposing 120 USDC to caterer.near from the trip pot for catering. Vote: https://trezu.app/trip.sputnik-dao.near/requests",
            "bond": "0.1", "proposers": "everyone", "threshold": ["words": "2 of 3"]]
        let p = PotProposal(ok: true, link, to: "caterer.near", account: nil)
        XCTAssertEqual(p.headline, "Propose $120 to caterer.near")
        XCTAssertEqual(p.terms, "Needs 2 of 3 · bond 0.1 NEAR")
        var noRule = link
        noRule["threshold"] = NSNull()
        noRule["bond"] = nil
        XCTAssertNil(PotProposal(ok: true, noRule, to: "caterer.near", account: nil).terms)
        XCTAssertEqual(p.fill, "Type 120 USDC, note: catering")
        XCTAssertFalse(p.notMember)
        var members = link
        members["proposers"] = ["ana.near", "ben.near"]
        XCTAssertTrue(PotProposal(ok: true, members, to: "caterer.near", account: "me.near").notMember)
        XCTAssertFalse(PotProposal(ok: true, members, to: "caterer.near", account: "Ben.near").notMember)
        XCTAssertEqual(PotProposal.membersOnly, "Only members can propose from this pot")
    }

    /// A chip's words are never cut mid-word (D108): roomy, one line at 15 pt;
    /// tighter, the venue part goes whole; the pot's payout, too long alone
    /// even at 11 pt in the strip's 188 pt, wraps onto two lines.
    func testChipWordsFitWithoutCutting() {
        let roomy = ChipFit.fit(value: "See the build pot · Sputnik DAO", label: nil, width: 400, height: 30)
        XCTAssertEqual(roomy, ChipFit.Fit(parts: ["See the build pot", "Sputnik DAO"], label: nil, size: 15, lines: 1))
        let pay = "Propose $120 to caterer from the build pot · Sputnik DAO"
        let tight = ChipFit.fit(value: pay, label: nil, width: 188, height: 30)
        XCTAssertEqual(tight.parts, ["Propose $120 to caterer from the build pot"])
        XCTAssertEqual(tight.lines, 2)
        XCTAssertGreaterThanOrEqual(tight.size, 11)
        let box = ChipFit.string(tight.parts, label: nil, size: tight.size)
            .boundingRect(with: CGSize(width: 188, height: 1000), options: [.usesLineFragmentOrigin], context: nil)
        XCTAssertLessThanOrEqual(ceil(box.height), 30)
        // A bill split keeps its answer: the question goes before the answer is cut.
        let split = ChipFit.fit(value: "$90 for the four of us = $22.50 each", label: nil, width: 188, height: 30,
                                shorter: "$22.50 each")
        XCTAssertEqual(split, ChipFit.Fit(parts: ["$22.50 each"], label: nil, size: 15, lines: 1))
        // A payout drops its pot ("Propose $120 to caterer"), on one line.
        let payChip = Smart.Chip.action(label: pay, query: "{}", intent: "near:pot.pay")
        XCTAssertEqual(ChipFit.shorter(payChip), "Propose $120 to caterer · Sputnik DAO")
        let short = ChipFit.fit(value: pay, label: nil, width: 188, height: 30, shorter: ChipFit.shorter(payChip))
        XCTAssertEqual(short.parts, ["Propose $120 to caterer"])
        XCTAssertEqual(short.lines, 1)
        XCTAssertNil(ChipFit.shorter(.action(label: "See the build pot · Sputnik DAO", query: "{}", intent: "near:pot")))
        // One line still wins when a smaller size or a dropped part does it.
        let earn = ChipFit.fit(value: "Put 50 USDC to work · Morpho", label: "NEAR Intents", width: 188, height: 30)
        XCTAssertEqual(earn.lines, 1)
        XCTAssertLessThanOrEqual(ceil(ChipFit.string(earn.parts, label: earn.label, size: earn.size).size().width), 188)
    }

}
