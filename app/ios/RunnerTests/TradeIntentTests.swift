import XCTest
@testable import Runner

/// The trades the keyboard reads from plain words (ETHGlobal Mumbai).
final class TradeIntentTests: XCTestCase {

    private func read(_ text: String) -> TradeIntent? { TradeIntent.parse(text) }

    func testASwapNamesBothTokensAndTheChain() throws {
        let i = try XCTUnwrap(read("swap 0.05 eth to usdc on base"))
        XCTAssertEqual(i.kind, .swap)
        XCTAssertEqual(i.amount, "0.05")
        XCTAssertEqual(i.sell, "ETH")
        XCTAssertEqual(i.buy, "USDC")
        XCTAssertEqual(i.chainName, "base")
        XCTAssertEqual(i.title, "Swap 0.05 ETH → USDC")
        XCTAssertEqual(i.detail, "Base · Uniswap")
    }

    func testASwapWithNoChainIsOnBase() throws {
        let i = try XCTUnwrap(read("convert 100 usdc into eth"))
        XCTAssertEqual(i.chainName, "base")
        XCTAssertEqual(i.sell, "USDC")
        XCTAssertEqual(i.buy, "ETH")
    }

    func testDollarsOfATokenAreSpentInUSDC() throws {
        let i = try XCTUnwrap(read("buy $50 of eth"))
        XCTAssertEqual(i.kind, .swap)
        XCTAssertTrue(i.amountIsUSD)
        XCTAssertEqual(i.amount, "50")
        XCTAssertEqual(i.sell, "USDC")
        XCTAssertEqual(i.title, "Buy $50 of ETH")
    }

    func testBuyingAnAmountKeepsTheAmountWanted() throws {
        let i = try XCTUnwrap(read("buy 0.1 eth with usdt on arbitrum"))
        XCTAssertNil(i.amount)
        XCTAssertEqual(i.buyAmount, "0.1")
        XCTAssertEqual(i.sell, "USDT")
        XCTAssertEqual(i.chainName, "arbitrum")
        XCTAssertEqual(i.title, "Buy 0.1 ETH with USDT")
    }

    func testSellingEverythingHasNoAmount() throws {
        let i = try XCTUnwrap(read("sell my eth"))
        XCTAssertEqual(i.kind, .swap)
        XCTAssertNil(i.amount)
        XCTAssertEqual(i.buy, "USDC")
        XCTAssertEqual(i.title, "Swap all ETH → USDC")
    }

    func testAFallToAPriceIsAStopLoss() throws {
        let i = try XCTUnwrap(read("sell my eth if it drops below 3000"))
        XCTAssertEqual(i.kind, .stopLoss)
        XCTAssertEqual(i.price, "3000")
        XCTAssertNil(i.amount)
        XCTAssertEqual(i.title, "Stop-loss ETH at $3,000")
        XCTAssertEqual(i.detail, "Base · Flash")
        XCTAssertEqual(read("stop loss 0.5 eth at $3,000")?.kind, .stopLoss)
        XCTAssertEqual(read("stop loss 0.5 eth at $3,000")?.price, "3000")
    }

    func testARiseToAPriceIsATakeProfit() throws {
        let i = try XCTUnwrap(read("sell 0.2 eth when it hits 4500"))
        XCTAssertEqual(i.kind, .takeProfit)
        XCTAssertEqual(i.amount, "0.2")
        XCTAssertEqual(i.price, "4500")
        XCTAssertEqual(read("take profit eth at 4.5k")?.price, "4500")
    }

    func testABuyBelowThePriceIsALimit() throws {
        let i = try XCTUnwrap(read("buy $100 of eth if it dips below 2800"))
        XCTAssertEqual(i.kind, .limit)
        XCTAssertTrue(i.amountIsUSD)
        XCTAssertEqual(i.price, "2800")
        XCTAssertEqual(i.title, "Buy ETH at $2,800")
        XCTAssertEqual(read("buy 0.1 eth at 2800")?.kind, .limit)
    }

    func testABuyAboveThePriceIsAStop() throws {
        XCTAssertEqual(read("buy eth when it breaks 4000")?.kind, .stop)
    }

    func testTakeProfitAndStopTogetherAreABracket() throws {
        let held = try XCTUnwrap(read("my eth: tp 4500, sl 3000"))
        XCTAssertEqual(held.kind, .bracket)
        XCTAssertEqual(held.sell, "ETH")
        XCTAssertEqual(held.price, "4500")
        XCTAssertEqual(held.stopPrice, "3000")
        let buy = try XCTUnwrap(read("buy 0.1 eth take profit 4500 stop loss 3000"))
        XCTAssertEqual(buy.kind, .bracket)
        XCTAssertEqual(buy.buy, "ETH")
        XCTAssertEqual(buy.buyAmount, "0.1")
        // A take-profit under its stop is a typo, not an order.
        XCTAssertNil(read("my eth tp 3000 sl 4500"))
    }

    func testATrailFollowsThePrice() throws {
        let i = try XCTUnwrap(read("protect my eth with a 5% trail"))
        XCTAssertEqual(i.kind, .trailingStop)
        XCTAssertEqual(i.trailPercent, "5")
        XCTAssertEqual(read("trailing stop on eth 7.5%")?.trailPercent, "7.5")
        XCTAssertNil(read("trail my eth by 90%"))
    }

    func testARepeatedBuyIsOneTWAP() throws {
        let i = try XCTUnwrap(read("buy $20 of eth every day for a week"))
        XCTAssertEqual(i.kind, .twap)
        XCTAssertEqual(i.amount, "140")
        XCTAssertEqual(i.durationSeconds, 7 * 86_400)
        XCTAssertEqual(i.title, "Buy $140 of ETH over a week")
        let over = try XCTUnwrap(read("dca $300 into eth over 3 days"))
        XCTAssertEqual(over.amount, "300")
        XCTAssertEqual(over.durationSeconds, 3 * 86_400)
    }

    func testMovingBetweenChainsIsABridge() throws {
        let i = try XCTUnwrap(read("move 50 usdc from base to arbitrum"))
        XCTAssertEqual(i.kind, .bridge)
        XCTAssertEqual(i.chainName, "base")
        XCTAssertEqual(i.toChain, "arbitrum")
        XCTAssertEqual(i.title, "Move 50 USDC to Arbitrum")
        XCTAssertNil(read("move 50 usdc from base to base"))
    }

    func testASendToANameKeepsTheName() throws {
        let eth = try XCTUnwrap(read("send 20 usdc to arpit.eth"))
        XCTAssertEqual(eth.kind, .send)
        XCTAssertEqual(eth.to, "arpit.eth")
        XCTAssertEqual(eth.chainName, "base")
        let sol = try XCTUnwrap(read("pay arpit.sol 5 usdc"))
        XCTAssertEqual(sol.to, "arpit.sol")
        XCTAssertEqual(sol.chainName, "solana")
        let hex = try XCTUnwrap(read("send 0.01 eth to 0x52908400098527886E0F7030069857D2E4169EE7"))
        XCTAssertEqual(hex.to, "0x52908400098527886E0F7030069857D2E4169EE7")
    }

    func testARequestIsWhitechainUSDT() throws {
        let i = try XCTUnwrap(read("request 20 usdt"))
        XCTAssertEqual(i.kind, .request)
        XCTAssertEqual(i.amount, "20")
        XCTAssertEqual(i.chainName, "whitechain-sepolia")
        XCTAssertEqual(i.title, "Request 20 USDT")
        XCTAssertEqual(read("can you send it, I'll request 15 usdt for dinner")?.amount, nil)
    }

    func testOrdinaryWordsAreNoTrade() {
        for text in ["swap shifts with sam", "I'll buy dinner tonight", "sell the old bike",
                     "send me the doc", "stop it", "I want to take profit from this lesson"] {
            XCTAssertNil(read(text), text)
        }
    }

    func testTheCommandMayFollowASentence() throws {
        let i = try XCTUnwrap(read("ok done. swap 1 usdc to eth"))
        XCTAssertEqual(i.amount, "1")
    }

    func testTheQueryCarriesEverythingTheAppNeeds() throws {
        let q = try XCTUnwrap(read("buy 0.1 eth take profit 4500 stop loss 3000 on arbitrum")).query
        XCTAssertEqual(q["kind"], "bracket")
        XCTAssertEqual(q["chain"], "arbitrum")
        XCTAssertEqual(q["price"], "4500")
        XCTAssertEqual(q["stopPrice"], "3000")
        XCTAssertEqual(q["buyAmount"], "0.1")
    }
}
