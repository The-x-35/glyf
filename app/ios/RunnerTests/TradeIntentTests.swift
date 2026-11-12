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

    // MARK: NEAR Intents (docs/NEAR-SPEC.md)

    private let bech32 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
    private let tAddress = "t1Rv4exT7bqhZqi2j7xz8bUHDMxwosrjADU"
    private let implicit = "98793cd91a3f870fb126f66285808c7e094afcfc4eda8a970f6648cdf0dbd6de"

    /// The spec's first row: USDC on Base to SOL on Solana.
    func testASwapFromBaseToSolanaGoesThroughNEARIntents() throws {
        let i = try XCTUnwrap(read("swap 20 usdc on base to sol"))
        XCTAssertEqual(i.kind, .swap)
        XCTAssertTrue(i.isNear)
        XCTAssertEqual(i.amount, "20")
        XCTAssertEqual(i.sell, "USDC")
        XCTAssertEqual(i.buy, "SOL")
        XCTAssertEqual(i.chainName, "base")
        XCTAssertEqual(i.buyChain, "solana")
        XCTAssertEqual(i.venue, "NEAR Intents")
        XCTAssertEqual(i.title, "Swap 20 USDC → SOL")
        XCTAssertEqual(i.detail, "Base → Solana · NEAR Intents")
        XCTAssertEqual(i.query["venue"], "near")
        XCTAssertEqual(i.query["kind"], "swap")
        XCTAssertEqual(i.query["chain"], "base")
        XCTAssertEqual(i.query["buyChain"], "solana")
        XCTAssertEqual(i.query["amount"], "20")
        XCTAssertNil(i.query["exact"])
        // The same said other ways.
        XCTAssertEqual(read("swap 20 usdc on base to sol on solana"), i)
        XCTAssertEqual(read("Swap 20 USDC from Base to SOL"), i)
        XCTAssertEqual(read("pls swap 20 usdc on base to solana")?.buy, "SOL")
    }

    func testASwapFromSolanaToBase() throws {
        let i = try XCTUnwrap(read("swap 0.2 sol to usdc on base"))
        XCTAssertTrue(i.isNear)
        XCTAssertEqual(i.sell, "SOL")
        XCTAssertEqual(i.chainName, "solana")
        XCTAssertEqual(i.buy, "USDC")
        XCTAssertEqual(i.buyChain, "base")
        XCTAssertEqual(i.title, "Swap 0.2 SOL → USDC")
        XCTAssertEqual(i.detail, "Solana → Base · NEAR Intents")
        XCTAssertEqual(read("swap 0.2 sol on solana to usdc on arbitrum")?.buyChain, "arbitrum")
        XCTAssertEqual(read("swap 0.2 sol to eth on base")?.buy, "ETH")
    }

    /// Bitcoin, NEAR and Zcash need someone to pay: an address typed after,
    /// or (NEAR) the account saved in the app.
    func testSwapsToChainsOfTheirOwn() throws {
        let btc = try XCTUnwrap(read("swap 50 usdc on arbitrum to btc to \(bech32)"))
        XCTAssertEqual(btc.sell, "USDC")
        XCTAssertEqual(btc.chainName, "arbitrum")
        XCTAssertEqual(btc.buy, "BTC")
        XCTAssertEqual(btc.buyChain, "bitcoin")
        XCTAssertEqual(btc.to, bech32)
        XCTAssertEqual(btc.detail, "Arbitrum → Bitcoin · NEAR Intents")
        XCTAssertEqual(btc.query["to"], bech32)
        XCTAssertEqual(btc.query["buyChain"], "bitcoin")

        let near = try XCTUnwrap(read("swap 20 usdc on base to near"))
        XCTAssertEqual(near.buy, "NEAR")
        XCTAssertEqual(near.buyChain, "near")
        XCTAssertNil(near.to)
        XCTAssertEqual(near.title, "Swap 20 USDC → NEAR")
        XCTAssertEqual(near.detail, "Base → NEAR · NEAR Intents")
        XCTAssertEqual(read("swap 20 usdc on base to near to alice.near")?.to, "alice.near")

        let zec = try XCTUnwrap(read("swap 20 usdc on base to zec"))
        XCTAssertEqual(zec.buy, "ZEC")
        XCTAssertEqual(zec.buyChain, "zcash")
        XCTAssertEqual(read("swap 20 usdc on base to zec to \(tAddress)")?.to, tAddress)
        // Base pays when no chain is said and the other side has its own.
        XCTAssertEqual(read("swap 20 usdc to zec")?.chainName, "base")
        // Native BTC said by its chain, or beside Solana.
        XCTAssertEqual(read("swap 20 usdc on base to btc on bitcoin")?.buy, "BTC")
        XCTAssertEqual(read("swap 1 sol to btc")?.buyChain, "bitcoin")
        let fromBTC = try XCTUnwrap(read("swap 0.01 btc on bitcoin to usdc on base"))
        XCTAssertEqual(fromBTC.chainName, "bitcoin")
        XCTAssertEqual(fromBTC.sell, "BTC")
        XCTAssertEqual(fromBTC.buyChain, "base")
        // Every chain only NEAR Intents reaches.
        for (word, coin, chain) in [("ton", "TON", "ton"), ("tron", "TRX", "tron"), ("xrp", "XRP", "xrp"),
                                    ("doge", "DOGE", "dogecoin"), ("ltc", "LTC", "litecoin"), ("sui", "SUI", "sui"),
                                    ("aptos", "APT", "aptos"), ("xlm", "XLM", "stellar"), ("cardano", "ADA", "cardano")] {
            let t = try XCTUnwrap(read("swap 20 usdc on base to \(word)"), word)
            XCTAssertEqual(t.buy, coin, word)
            XCTAssertEqual(t.buyChain, chain, word)
            XCTAssertEqual(t.venue, "NEAR Intents", word)
        }
    }

    func testMovingTheSameCoinAcrossChainsNEARIntentsJoins() throws {
        let i = try XCTUnwrap(read("move 50 usdc from base to solana"))
        XCTAssertEqual(i.kind, .swap)
        XCTAssertTrue(i.isNear)
        XCTAssertEqual(i.sell, "USDC")
        XCTAssertEqual(i.buy, "USDC")
        XCTAssertEqual(i.chainName, "base")
        XCTAssertEqual(i.buyChain, "solana")
        XCTAssertEqual(i.title, "Move 50 USDC to Solana")
        XCTAssertEqual(i.detail, "Base → Solana · NEAR Intents")
        XCTAssertEqual(i.query["venue"], "near")
        XCTAssertEqual(read("bridge 10 usdc from solana to arbitrum")?.buyChain, "arbitrum")
        // Between EVM chains it's Flash's, as before.
        let flash = try XCTUnwrap(read("move 50 usdc from base to arbitrum"))
        XCTAssertEqual(flash.kind, .bridge)
        XCTAssertEqual(flash.venue, "Flash")
        // A coin Solana doesn't have stays a Flash move, as it was.
        XCTAssertEqual(read("move 0.1 eth from base to solana")?.kind, .bridge)
        // Flash's own words (the Definitive panel) read as they did.
        XCTAssertEqual(TradeIntent.parse("move 10 usdc from solana to base", near: false)?.kind, .bridge)
    }

    /// Sends pay the recipient exactly (EXACT_OUTPUT), from USDC on Base
    /// unless the words say what pays.
    func testSendsToANEARAccount() throws {
        let i = try XCTUnwrap(read("send 5 usdc to alice.near"))
        XCTAssertEqual(i.kind, .send)
        XCTAssertTrue(i.isNear)
        XCTAssertEqual(i.amount, "5")
        XCTAssertEqual(i.buy, "USDC")
        XCTAssertEqual(i.buyChain, "near")
        XCTAssertEqual(i.sell, "USDC")
        XCTAssertEqual(i.chainName, "base")
        XCTAssertEqual(i.to, "alice.near")
        XCTAssertEqual(i.venue, "NEAR Intents")
        XCTAssertEqual(i.title, "Send 5 USDC to alice.near")
        XCTAssertEqual(i.detail, "Base → NEAR · NEAR Intents")
        XCTAssertEqual(i.query["venue"], "near")
        XCTAssertEqual(i.query["exact"], "out")
        XCTAssertEqual(i.query["kind"], "send")
        XCTAssertEqual(i.query["to"], "alice.near")
        XCTAssertEqual(i.query["buy"], "USDC")
        XCTAssertEqual(i.query["buyChain"], "near")
        XCTAssertEqual(i.query["sell"], "USDC")
        XCTAssertEqual(i.query["chain"], "base")
        XCTAssertTrue(TradeIntent.isName(i.to))

        let sol = try XCTUnwrap(read("pay bob.near 10 usdc with sol"))
        XCTAssertEqual(sol.to, "bob.near")
        XCTAssertEqual(sol.amount, "10")
        XCTAssertEqual(sol.buy, "USDC")
        XCTAssertEqual(sol.sell, "SOL")
        XCTAssertEqual(sol.chainName, "solana")
        XCTAssertEqual(sol.detail, "Solana → NEAR · NEAR Intents")
        let arb = try XCTUnwrap(read("send 5 usdc to alice.near with usdc on arbitrum"))
        XCTAssertEqual(arb.sell, "USDC")
        XCTAssertEqual(arb.chainName, "arbitrum")
        let fromSol = try XCTUnwrap(read("send 5 usdc to Alice.NEAR from solana"))
        XCTAssertEqual(fromSol.chainName, "solana")
        XCTAssertEqual(fromSol.sell, "USDC")
        XCTAssertEqual(fromSol.to, "alice.near")
        XCTAssertEqual(read("send 2 near to sub.alice.near with eth")?.sell, "ETH")
        XCTAssertEqual(read("send 2 near to sub.alice.near with eth")?.buy, "NEAR")
        let hex = try XCTUnwrap(read("send 3 usdt to \(implicit)"))
        XCTAssertEqual(hex.buyChain, "near")
        XCTAssertEqual(hex.to, implicit)
        XCTAssertEqual(hex.title, "Send 3 USDT to 98793c…d6de")
        XCTAssertFalse(TradeIntent.isName(hex.to))
    }

    func testSendsToBitcoinAndZcashAddresses() throws {
        let btc = try XCTUnwrap(read("send 0.001 btc to \(bech32)"))
        XCTAssertEqual(btc.buy, "BTC")
        XCTAssertEqual(btc.buyChain, "bitcoin")
        XCTAssertEqual(btc.sell, "USDC")
        XCTAssertEqual(btc.chainName, "base")
        XCTAssertEqual(btc.amount, "0.001")
        XCTAssertEqual(btc.title, "Send 0.001 BTC to bc1qar…5mdq")
        XCTAssertEqual(btc.query["exact"], "out")
        XCTAssertEqual(btc.query["to"], bech32)
        for legacy in ["1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"] {
            let t = try XCTUnwrap(read("send 0.01 bitcoin to \(legacy)"), legacy)
            XCTAssertEqual(t.buyChain, "bitcoin", legacy)
            XCTAssertEqual(t.to, legacy, legacy)    // base58 keeps its case
        }
        let zec = try XCTUnwrap(read("send 1.5 zec to \(tAddress) with sol"))
        XCTAssertEqual(zec.buy, "ZEC")
        XCTAssertEqual(zec.buyChain, "zcash")
        XCTAssertEqual(zec.sell, "SOL")
        XCTAssertEqual(zec.detail, "Solana → Zcash · NEAR Intents")
        XCTAssertNil(TradeIntent.phantomSend(zec.query.merging(["address": tAddress]) { $1 }))
    }

    func testNEARTradesThatCantBeAreNotRead() {
        for text in ["send 5 usdc to \(bech32)",          // Bitcoin carries only BTC
                     "send 1 btc to alice.near",            // NEAR takes NEAR, USDC, USDT here
                     "send 5 zec to \(bech32)",
                     "send 2 near to alice.near with near", // that's a plain NEAR transfer
                     "send usdc to alice.near",             // no amount
                     "send 5 usdc to alice.nearby",
                     "send 5 usdc to bc1qshort",
                     "swap 50 usdc on arbitrum to btc to alice.near", // the address doesn't fit
                     "swap 20 usdc to sol",                 // which USDC? not guessed beside Solana
                     "swap 0.2 sol to usdc",
                     "swap 1 near on base to usdc on solana",
                     "swap 10 tsla on base to sol"] {
            XCTAssertNil(read(text), text)
        }
        XCTAssertNil(TradeIntent.nearRecipientChain("alice.eth"))
        XCTAssertNil(TradeIntent.nearRecipientChain("0x52908400098527886E0F7030069857D2E4169EE7"))
    }

    /// Everything Uniswap, Jupiter and Flash read stays theirs.
    func testOldTradesStayWhereTheyWere() throws {
        let uni = try XCTUnwrap(read("swap 50 usdc on base to eth on arbitrum"))
        XCTAssertFalse(uni.isNear)
        XCTAssertEqual(uni.venue, "Uniswap")
        XCTAssertEqual(uni.detail, "Base → Arbitrum · Uniswap")
        XCTAssertNil(uni.query["venue"])
        XCTAssertEqual(read("swap 50 usdc on base to eth on polygon")?.venue, "Uniswap")
        for (text, venue) in [("swap 0.05 eth to usdc on base", "Uniswap"), ("swap 10 usdc to usdt on solana", "Jupiter"),
                              ("swap 0.01 btc to usdc", "Uniswap"), ("swap 20 usdc to btc", "Uniswap"),
                              ("buy $50 of eth", "Uniswap"), ("sell 0.1 sol if it drops below 100", "Flash"),
                              ("move 50 usdc from base to arbitrum", "Flash"),
                              ("send 20 usdc to vitalik.eth", "MetaMask"), ("pay arpit.sol 5 usdc", "Phantom")] {
            let t = try XCTUnwrap(read(text), text)
            XCTAssertFalse(t.isNear, text)
            XCTAssertEqual(t.venue, venue, text)
            XCTAssertNil(t.query["venue"], text)
            XCTAssertNil(t.query["exact"], text)
        }
        XCTAssertEqual(read("swap 0.01 btc to usdc")?.sell, "WBTC")
        XCTAssertEqual(read("swap 20 usdc to btc")?.buy, "WBTC")
        // Words that were never a trade still aren't.
        for text in ["I'm near the station", "send it near noon", "swap 1 sol to usdc on solana",
                     "buy a ton of snacks", "send 5 usdc to arpit.eth on solana"] {
            XCTAssertNil(read(text), text)
        }
    }

    func testTheStripOffersNEARTrades() {
        guard case .trade(let t)? = Smart.chip(for: "swap 20 usdc on base to sol", fields: []) else {
            return XCTFail("no NEAR swap chip")
        }
        let chip = Smart.Chip.trade(t)
        XCTAssertEqual(chip.key, "NEAR Intents")
        XCTAssertEqual(chip.value, "Swap 20 USDC → SOL · Base → Solana")
        XCTAssertEqual(chip.verb, "Swap")
        guard case .trade(let send)? = Smart.chip(for: "send 5 usdc to alice.near", fields: []) else {
            return XCTFail("no NEAR send chip")
        }
        XCTAssertEqual(Smart.Chip.trade(send).value, "Send 5 USDC to alice.near · Base → NEAR")
        XCTAssertEqual(Smart.Chip.trade(send).verb, "Send")
        guard case .trade(let move)? = Smart.chip(for: "move 50 usdc from base to solana", fields: []) else {
            return XCTFail("no NEAR move chip")
        }
        XCTAssertEqual(Smart.Chip.trade(move).verb, "Move")
        // A legacy Bitcoin address looks like a Solana one; the words say which.
        guard case .trade(let legacy)? = Smart.chip(for: "send 0.01 btc to 1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", fields: []) else {
            return XCTFail("no Bitcoin send chip")
        }
        XCTAssertEqual(legacy.buyChain, "bitcoin")
        // Old chips read as they did.
        guard case .trade(let uni)? = Smart.chip(for: "swap 0.05 eth to usdc on base", fields: []) else { return XCTFail() }
        XCTAssertEqual(Smart.Chip.trade(uni).value, "Swap 0.05 ETH → USDC · Base")
    }

    /// GET /names/resolve for a .near name: the account, or "No NEAR account".
    func testANEARNameIsCheckedOnNEAR() {
        let found: [String: Any] = ["ok": true, "found": true, "chain": "near", "address": "alice.near", "exists": true]
        XCTAssertEqual(TradeIntent.recipient(for: "alice.near", chain: "near", ok: true, answer: found).0, "alice.near")
        let missing: [String: Any] = ["ok": true, "chain": "near", "address": "nobody.near", "exists": false]
        let none = TradeIntent.recipient(for: "nobody.near", chain: "near", ok: true, answer: missing)
        XCTAssertNil(none.0)
        XCTAssertEqual(none.1, "No NEAR account nobody.near")
        XCTAssertEqual(TradeIntent.recipient(for: "nobody.near", chain: "near", ok: false,
                                             answer: ["ok": false, "exists": false]).1, "No NEAR account nobody.near")
        XCTAssertEqual(TradeIntent.recipient(for: "a.near", chain: "near", ok: false, answer: nil).1, "Couldn’t look up a.near")
    }

    /// What POST /near/quote's answer shows on the panel.
    func testANEARQuoteReads() {
        let answer: [String: Any] = [
            "ok": true, "dry": true, "venue": "NEAR Intents", "amountIn": "20", "amountInUsd": "19.99",
            "amountOut": "0.2438", "amountOutUsd": "19.88", "timeSeconds": 32,
            "guard": ["level": "warn", "checks": [["id": "new-recipient", "level": "warn", "text": "First time paying this address"],
                                                  ["id": "lookalike", "level": "block", "text": "Looks like 0xAb12…9fE0 you paid before, but it isn't"]]],
        ]
        let q = NearQuote(ok: true, answer)
        XCTAssertEqual(q.amountIn, 20)
        XCTAssertEqual(q.amountOut, 0.2438)
        XCTAssertEqual(q.inUSD, 19.99)
        XCTAssertEqual(q.outUSD, 19.88)
        XCTAssertEqual(q.time, "~32 s")
        XCTAssertEqual(q.guardLevel, "block")
        XCTAssertEqual(q.guardText, "Looks like 0xAb12…9fE0 you paid before, but it isn't")
        XCTAssertNil(q.error)
        let quiet = NearQuote(ok: true, ["ok": true, "amountOut": 5, "timeSeconds": 150, "guard": ["level": "ok", "checks": []]])
        XCTAssertNil(quiet.guardLevel)
        XCTAssertEqual(quiet.time, "~3 min")
        let small = NearQuote(ok: false, ["ok": false, "error": "Too small for NEAR Intents: at least $1"])
        XCTAssertNil(small.amountOut)
        XCTAssertEqual(small.error, "Too small for NEAR Intents: at least $1")
        XCTAssertEqual(NearQuote(ok: false, nil).error, "No quote right now")
    }

    /// The panel's chain pickers for a NEAR trade, and what a pick does.
    func testANEARTradeIsEditedInThePanel() throws {
        let swap = try XCTUnwrap(read("swap 20 usdc on base to sol"))
        XCTAssertTrue(TradeEdit.chains(for: swap).contains("bitcoin"))
        XCTAssertTrue(TradeEdit.chains(for: swap).contains("solana"))
        // To Bitcoin: what's bought becomes BTC.
        let toBTC = TradeEdit.pickChain("bitcoin", side: .buy, in: swap)
        XCTAssertEqual(toBTC.buy, "BTC")
        XCTAssertEqual(toBTC.buyChain, "bitcoin")
        XCTAssertTrue(toBTC.isNear)
        // Both sides on Base: Uniswap's swap there, no longer NEAR's.
        let same = TradeEdit.pickChain("base", side: .buy, in: swap)
        XCTAssertNil(same.buyChain)
        XCTAssertEqual(same.buy, "ETH")
        XCTAssertFalse(same.isNear)
        XCTAssertEqual(same.venue, "Uniswap")
        // Paying from Arbitrum keeps USDC.
        XCTAssertEqual(TradeEdit.pickChain("arbitrum", side: .sell, in: swap).sell, "USDC")
        XCTAssertEqual(TradeEdit.pickChain("arbitrum", side: .sell, in: swap).chainName, "arbitrum")
        // Flipped: SOL on Solana to USDC on Base.
        let back = TradeEdit.flip(swap)
        XCTAssertEqual(back.sell, "SOL")
        XCTAssertEqual(back.chainName, "solana")
        XCTAssertEqual(back.buyChain, "base")
        XCTAssertTrue(back.isNear)

        let send = try XCTUnwrap(read("send 0.001 btc to \(bech32)"))
        XCTAssertEqual(TradeEdit.asset(send), "BTC")
        XCTAssertEqual(TradeEdit.label(.amount, send), "Amount in BTC")
        XCTAssertEqual(TradeEdit.chains(for: send), TradeEdit.nearPayChains)
        let paid = TradeEdit.pickChain("solana", side: .sell, in: send)
        XCTAssertEqual(paid.chainName, "solana")
        XCTAssertEqual(paid.sell, "USDC")
        XCTAssertEqual(paid.buy, "BTC")
        XCTAssertEqual(paid.buyChain, "bitcoin")
        XCTAssertEqual(TradeEdit.apply(.amount, "0.002", to: send).amount, "0.002")
        XCTAssertNil(TradeEdit.problem(send))
        XCTAssertEqual(TradeEdit.builtIn(chain: "bitcoin").map(\.symbol), ["BTC"])
        XCTAssertEqual(TradeEdit.builtIn(chain: "near").map(\.symbol), ["NEAR", "USDC", "USDT"])
    }

    /// The shared settings with `privateAI` (and `nearRecent`) set as given.
    private func settings(_ edit: (inout [String: Any]) -> Void) throws -> GlyfSettings {
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(GlyfSettings())) as? [String: Any])
        edit(&dict)
        return try JSONDecoder().decode(GlyfSettings.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    /// Private AI on NEAR AI Cloud: the app writes "near" or removes the
    /// key; the ETHGlobal build's Bool reads as off without losing the file.
    func testPrivateAIOnNEARIsReadFromTheSharedSettings() throws {
        let on = try settings { $0["privateAI"] = "near"; $0["nearRecent"] = ["alice.near", "0xab"] }
        XCTAssertEqual(on.privateAI?.value, "near")
        XCTAssertEqual(on.privateAIHeader, "near")
        XCTAssertEqual(on.nearRecent, ["alice.near", "0xab"])
        let missing = try settings { $0["privateAI"] = nil }
        XCTAssertNil(missing.privateAI)
        XCTAssertNil(missing.privateAIHeader)
        for legacy in [true, false] {
            let old = try settings { $0["privateAI"] = legacy; $0["haptics"] = false }
            XCTAssertNil(old.privateAIHeader, "\(legacy)")
            XCTAssertFalse(old.haptics, "the rest of the file still reads")
        }
        XCTAssertNil((try settings { $0["privateAI"] = "0g" }).privateAIHeader)
        XCTAssertNil((try settings { $0["privateAI"] = NSNull() }).privateAIHeader)
    }
}
