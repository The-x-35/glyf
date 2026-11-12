import XCTest
@testable import Runner

/// The trades the keyboard reads from plain words: Uniswap, Jupiter and Definitive Flash.
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
        XCTAssertEqual(i.title, "Buy $100 of ETH at $2,800")
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
        XCTAssertEqual(i.title, "Buy $20 of ETH every day for 7 days")
        // Autocorrect's "everyday", and "daily" for every day.
        XCTAssertEqual(read("buy $20 of eth everyday for a week")?.amount, "140")
        XCTAssertEqual(read("dca $10 into eth daily for 5 days")?.durationSeconds, 5 * 86_400)
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

    /// Sends to an ENS or SNS name (Arpit, 2026-11-12: "I feel you can add
    /// sending to .eth and .sol"): MetaMask on Ethereum chains, Phantom on
    /// Solana. Whitechain pay requests stay out.
    func testASendToANameIsRead() throws {
        let eth = try XCTUnwrap(read("send 20 usdc to Vitalik.ETH"))
        XCTAssertEqual(eth.kind, .send)
        XCTAssertEqual(eth.to, "vitalik.eth")
        XCTAssertEqual(eth.amount, "20")
        XCTAssertEqual(eth.sell, "USDC")
        XCTAssertEqual(eth.chainName, "base")
        XCTAssertEqual(eth.title, "Send 20 USDC to vitalik.eth")
        XCTAssertEqual(eth.detail, "Base · MetaMask")
        XCTAssertEqual(eth.query["to"], "vitalik.eth")
        XCTAssertEqual(eth.query["kind"], "send")

        let arb = try XCTUnwrap(read("pls send 0.01 eth to pay.arpit.eth on arbitrum"))
        XCTAssertEqual(arb.chainName, "arbitrum")
        XCTAssertEqual(arb.to, "pay.arpit.eth")

        let sol = try XCTUnwrap(read("pay arpit.sol 5 usdc"))
        XCTAssertEqual(sol.to, "arpit.sol")
        XCTAssertEqual(sol.chainName, "solana")
        XCTAssertEqual(sol.detail, "Solana · Phantom")
        // SOL lives on Solana, even to an ENS name (its Solana record).
        XCTAssertEqual(read("send 1 sol to vitalik.eth")?.chainName, "solana")

        let hex = try XCTUnwrap(read("send 0.01 eth to 0x52908400098527886E0F7030069857D2E4169EE7"))
        XCTAssertEqual(hex.to, "0x52908400098527886E0F7030069857D2E4169EE7")
        XCTAssertEqual(hex.title, "Send 0.01 ETH to 0x5290…9EE7")
        XCTAssertFalse(TradeIntent.isName(hex.to))
        XCTAssertTrue(TradeIntent.isName(eth.to))
        guard case .trade(let chip)? = Smart.chip(for: "send 5 usdc to vitalik.eth", fields: []) else {
            return XCTFail("no send chip")
        }
        XCTAssertEqual(chip.to, "vitalik.eth")
    }

    func testSendsGlyfCantCarryAreNotRead() {
        for text in ["send usdc to arpit.eth",                // no amount
                     "send 5 usdt to arpit.sol",              // Phantom's send here: SOL or USDC
                     "send 1 sol to 0x52908400098527886E0F7030069857D2E4169EE7",
                     "send 5 usdc to arpit.eth on solana",    // an ENS name's EVM send isn't on Solana
                     "send 1 tsla to arpit.eth",              // shares stay trades
                     "send 5 usdc to arpit.com",
                     "request 20 usdt", "request 15 usdt on whitechain"] {
            XCTAssertNil(read(text), text)
        }
        // Whitechain isn't a trading chain.
        XCTAssertNil(read("swap 1 usdc to eth on whitechain"))
    }

    /// The panel shows the address a name points at before anything is
    /// signed, and a name that points nowhere stops the send.
    func testANameResolvesForTheSendsChain() {
        let answer: [String: Any] = ["ok": true, "found": true, "name": "vitalik.eth",
                                     "addresses": ["ethereum": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                                                   "base": "0x1111111111111111111111111111111111111111",
                                                   "solana": "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"]]
        XCTAssertEqual(TradeIntent.recipient(for: "vitalik.eth", chain: "base", ok: true, answer: answer).0,
                       "0x1111111111111111111111111111111111111111")
        // No Unichain record: the Ethereum one is the same account.
        XCTAssertEqual(TradeIntent.recipient(for: "vitalik.eth", chain: "unichain", ok: true, answer: answer).0,
                       "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        XCTAssertEqual(TradeIntent.recipient(for: "vitalik.eth", chain: "solana", ok: true, answer: answer).0,
                       "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU")
        // A Solana send never falls back to an Ethereum address.
        let evmOnly: [String: Any] = ["addresses": ["ethereum": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"]]
        let noSol = TradeIntent.recipient(for: "vitalik.eth", chain: "solana", ok: true, answer: evmOnly)
        XCTAssertNil(noSol.0)
        XCTAssertEqual(noSol.1, "vitalik.eth has no Solana address")
        let missing = TradeIntent.recipient(for: "nobody.sol", chain: "solana", ok: false, answer: ["ok": false, "found": false])
        XCTAssertNil(missing.0)
        XCTAssertEqual(missing.1, "nobody.sol isn’t registered")
        XCTAssertEqual(TradeIntent.recipient(for: "a.eth", chain: "base", ok: false, answer: nil).1, "Couldn’t look up a.eth")
        // Junk in a record is no address.
        XCTAssertNil(TradeIntent.recipient(for: "a.eth", chain: "base", ok: true, answer: ["addresses": ["base": "0x12"]]).0)
    }

    /// A Solana send goes to the app's existing Phantom send, with the
    /// address the name resolved to; an Ethereum one to the Trade screen.
    func testASolanaSendGoesThroughPhantom() throws {
        var q = try XCTUnwrap(read("send 1.5 sol to arpit.sol")).query
        q["address"] = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
        let pay = try XCTUnwrap(TradeIntent.phantomSend(q))
        XCTAssertEqual(pay["kind"], "send")
        XCTAssertEqual(pay["to"], "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU")
        XCTAssertEqual(pay["amount"], "1.5")
        XCTAssertEqual(pay["mint"], "So11111111111111111111111111111111111111112")
        XCTAssertEqual(pay["decimals"], "9")
        var usdc = try XCTUnwrap(read("pay arpit.sol 5 usdc")).query
        usdc["address"] = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
        XCTAssertEqual(TradeIntent.phantomSend(usdc)?["mint"], "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        // Not resolved yet: nothing goes anywhere.
        XCTAssertNil(TradeIntent.phantomSend(try XCTUnwrap(read("pay arpit.sol 5 usdc")).query))
        var evm = try XCTUnwrap(read("send 5 usdc to vitalik.eth")).query
        evm["address"] = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        XCTAssertNil(TradeIntent.phantomSend(evm))
    }

    /// The panel edits a send like a move: the token is both sides, the
    /// amount stays, and the chains are where the name can be paid.
    func testASendIsEditedInThePanel() throws {
        let i = try XCTUnwrap(read("send 5 usdc to vitalik.eth"))
        XCTAssertTrue(TradeEdit.sells(i))
        XCTAssertEqual(TradeEdit.fields(i), [.amount])
        XCTAssertEqual(TradeEdit.chains(for: i), SponsorMenu.swapChains)
        XCTAssertEqual(TradeEdit.chains(for: try XCTUnwrap(read("pay arpit.sol 5 usdc"))), ["solana"])
        XCTAssertNil(TradeEdit.problem(i))
        var none = i
        none.amount = nil
        XCTAssertEqual(TradeEdit.problem(none), "Enter an amount")
        let dai = TradeEdit.pick(TokenPick(symbol: "DAI", name: "Dai"), side: .sell, in: i)
        XCTAssertEqual(dai.sell, "DAI")
        XCTAssertEqual(dai.buy, "DAI")
        XCTAssertEqual(dai.amount, "5")
        XCTAssertEqual(dai.to, "vitalik.eth")
    }

    func testSolanaOrdersGoToTheAppOnSolana() throws {
        // Phantom signs these (lib/wallet/flash_solana.dart): the app reads chain=solana.
        let stop = try XCTUnwrap(read("sell 0.1 sol if it drops below 100"))
        XCTAssertEqual(stop.kind, .stopLoss)
        XCTAssertEqual(stop.query["chain"], "solana")
        XCTAssertEqual(stop.query["sell"], "SOL")
        let bracket = try XCTUnwrap(read("buy 0.1 sol, tp 200, sl 100"))
        XCTAssertEqual(bracket.kind, .bracket)
        XCTAssertEqual(bracket.query["chain"], "solana")
        XCTAssertEqual(bracket.query["buyAmount"], "0.1")
        XCTAssertEqual(read("buy $10 of sol at 80")?.query["chain"], "solana")
    }

    func testTheStripOffersEachTradeAsItsChip() {
        for text in ["Buy $20 of eth every day for a week ", "Buy $20 of eth every day for a week",
                     "Sell my eth if it drops below 3000", "Swap 0.05 eth to usdc on base"] {
            let chip = Smart.chip(for: text, fields: [])
            guard case .trade? = chip else { return XCTFail("\(text): \(String(describing: chip))") }
        }
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

    /// Always the person's own wallet app: there is no Glyf wallet.
    func testTheWalletPerChainIsAlwaysAnOutsideWallet() {
        XCTAssertEqual(TradeIntent.walletName(chain: "solana"), "Phantom")
        XCTAssertEqual(TradeIntent.walletName(chain: "base"), "MetaMask")
        XCTAssertEqual(TradeIntent.walletName(chain: "arbitrum"), "MetaMask")
        XCTAssertEqual(TradeIntent.walletName(chain: nil), "MetaMask")
    }

    /// Shares trade on Base, by their address there: a buy is a Uniswap
    /// swap from USDC, a buy below a price is a Flash limit.
    func testSharesTradeOnBase() throws {
        let buy = try XCTUnwrap(read("buy $10 of apple"))
        XCTAssertEqual(buy.kind, .swap)
        XCTAssertEqual(buy.sell, "USDC")
        XCTAssertEqual(buy.buy, "AAPL")
        XCTAssertEqual(buy.chainName, "base")
        XCTAssertEqual(buy.buyAddress, "0xb200000000000000000000C2e324d24d7eEcd1fb")
        XCTAssertEqual(buy.venue, "Uniswap")
        XCTAssertEqual(read("buy $10 of $aapl")?.buy, "AAPL")
        let limit = try XCTUnwrap(read("buy $10 of tesla if it dips below 300"))
        XCTAssertEqual(limit.kind, .limit)
        XCTAssertEqual(limit.chainName, "base")
        XCTAssertEqual(limit.query["buyAddress"] ?? limit.query["sellAddress"], TradeIntent.baseStocks["TSLA"])
        XCTAssertEqual(read("swap 20 usdc to nvda on solana")?.chainName, "base")
        XCTAssertEqual(TradeIntent.baseStock("AAPLx"), "AAPL")
        XCTAssertEqual(TradeIntent.baseStock("AAPLon"), "AAPL")
        XCTAssertNil(TradeIntent.baseStock("SOL"))
        XCTAssertNil(read("I ate an apple"))
    }

    /// "every time", "whenever" and "it's below" read as a price to wait
    /// for; a DCA says what was typed, not its total.
    func testHowPeopleSayAPriceAndADCA() throws {
        for text in ["buy $10 of tesla every time it dips below 300", "buy $10 of tesla whenever it drops below 300",
                     "buy $10 of tesla when it's below 300", "buy $10 of tesla when it’s below 300",
                     "buy $10 of tesla if the price is under 300"] {
            let i = try XCTUnwrap(read(text), text)
            XCTAssertEqual(i.kind, .limit, text)
            XCTAssertEqual(i.price, "300", text)
            XCTAssertEqual(i.buy, "TSLA", text)
            XCTAssertEqual(i.amount, "10", text)
            XCTAssertTrue(i.amountIsUSD, text)
            XCTAssertEqual(TradeEdit.shown(.amount, i), "$10", text)
        }
        // As the phone types it: capitals, autocorrect's curly apostrophe.
        let typed = try XCTUnwrap(read("Buy $10 of Tesla every time it dips below 300"))
        XCTAssertEqual(TradeEdit.shown(.amount, typed), "$10")
        XCTAssertEqual(TradeEdit.shown(.price, typed), "$300")
        XCTAssertEqual(typed.title, "Buy $10 of TSLA at $300")
        XCTAssertEqual(read("sell my eth whenever it falls below 1800")?.kind, .stopLoss)
        let dca = try XCTUnwrap(read("buy $5 of eth every hour for 2 hours"))
        XCTAssertEqual(dca.kind, .twap)
        XCTAssertEqual(dca.amount, "10")
        XCTAssertEqual(dca.title, "Buy $5 of ETH every hour for 2 hours")
    }
}

