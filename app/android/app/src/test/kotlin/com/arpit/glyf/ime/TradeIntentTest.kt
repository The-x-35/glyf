package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The trades the keyboard reads from plain words: Uniswap, Jupiter and
 *  Definitive Flash. The twin of RunnerTests/TradeIntentTests.swift, case
 *  for case. */
class TradeIntentTest {

    private fun read(text: String): TradeIntent? = TradeIntent.parse(text)
    private fun must(text: String): TradeIntent = read(text) ?: throw AssertionError("no trade read from: $text")

    @Test fun aSwapNamesBothTokensAndTheChain() {
        val i = must("swap 0.05 eth to usdc on base")
        assertEquals(TradeIntent.Kind.SWAP, i.kind)
        assertEquals("0.05", i.amount)
        assertEquals("ETH", i.sell)
        assertEquals("USDC", i.buy)
        assertEquals("base", i.chainName)
        assertEquals("Swap 0.05 ETH → USDC", i.title)
        assertEquals("Base · Uniswap", i.detail)
    }

    @Test fun aSwapWithNoChainIsOnBase() {
        val i = must("convert 100 usdc into eth")
        assertEquals("base", i.chainName)
        assertEquals("USDC", i.sell)
        assertEquals("ETH", i.buy)
    }

    @Test fun dollarsOfATokenAreSpentInUSDC() {
        val i = must("buy $50 of eth")
        assertEquals(TradeIntent.Kind.SWAP, i.kind)
        assertTrue(i.amountIsUSD)
        assertEquals("50", i.amount)
        assertEquals("USDC", i.sell)
        assertEquals("Buy $50 of ETH", i.title)
    }

    @Test fun buyingAnAmountKeepsTheAmountWanted() {
        val i = must("buy 0.1 eth with usdt on arbitrum")
        assertNull(i.amount)
        assertEquals("0.1", i.buyAmount)
        assertEquals("USDT", i.sell)
        assertEquals("arbitrum", i.chainName)
        assertEquals("Buy 0.1 ETH with USDT", i.title)
    }

    @Test fun sellingEverythingHasNoAmount() {
        val i = must("sell my eth")
        assertEquals(TradeIntent.Kind.SWAP, i.kind)
        assertNull(i.amount)
        assertEquals("USDC", i.buy)
        assertEquals("Swap all ETH → USDC", i.title)
    }

    @Test fun aFallToAPriceIsAStopLoss() {
        val i = must("sell my eth if it drops below 3000")
        assertEquals(TradeIntent.Kind.STOP_LOSS, i.kind)
        assertEquals("3000", i.price)
        assertNull(i.amount)
        assertEquals("Stop-loss ETH at $3,000", i.title)
        assertEquals("Base · Flash", i.detail)
        assertEquals(TradeIntent.Kind.STOP_LOSS, read("stop loss 0.5 eth at $3,000")?.kind)
        assertEquals("3000", read("stop loss 0.5 eth at $3,000")?.price)
    }

    @Test fun aRiseToAPriceIsATakeProfit() {
        val i = must("sell 0.2 eth when it hits 4500")
        assertEquals(TradeIntent.Kind.TAKE_PROFIT, i.kind)
        assertEquals("0.2", i.amount)
        assertEquals("4500", i.price)
        assertEquals("4500", read("take profit eth at 4.5k")?.price)
    }

    @Test fun aBuyBelowThePriceIsALimit() {
        val i = must("buy $100 of eth if it dips below 2800")
        assertEquals(TradeIntent.Kind.LIMIT, i.kind)
        assertTrue(i.amountIsUSD)
        assertEquals("2800", i.price)
        assertEquals("Buy $100 of ETH at $2,800", i.title)
        assertEquals(TradeIntent.Kind.LIMIT, read("buy 0.1 eth at 2800")?.kind)
    }

    @Test fun aBuyAboveThePriceIsAStop() {
        assertEquals(TradeIntent.Kind.STOP, read("buy eth when it breaks 4000")?.kind)
    }

    @Test fun takeProfitAndStopTogetherAreABracket() {
        val held = must("my eth: tp 4500, sl 3000")
        assertEquals(TradeIntent.Kind.BRACKET, held.kind)
        assertEquals("ETH", held.sell)
        assertEquals("4500", held.price)
        assertEquals("3000", held.stopPrice)
        val buy = must("buy 0.1 eth take profit 4500 stop loss 3000")
        assertEquals(TradeIntent.Kind.BRACKET, buy.kind)
        assertEquals("ETH", buy.buy)
        assertEquals("0.1", buy.buyAmount)
        // A take-profit under its stop is a typo, not an order.
        assertNull(read("my eth tp 3000 sl 4500"))
    }

    @Test fun aTrailFollowsThePrice() {
        val i = must("protect my eth with a 5% trail")
        assertEquals(TradeIntent.Kind.TRAILING_STOP, i.kind)
        assertEquals("5", i.trailPercent)
        assertEquals("7.5", read("trailing stop on eth 7.5%")?.trailPercent)
        assertNull(read("trail my eth by 90%"))
    }

    @Test fun aRepeatedBuyIsOneTWAP() {
        val i = must("buy $20 of eth every day for a week")
        assertEquals(TradeIntent.Kind.TWAP, i.kind)
        assertEquals("140", i.amount)
        assertEquals(7 * 86_400, i.durationSeconds)
        assertEquals("Buy $20 of ETH every day for 7 days", i.title)
        // Autocorrect's "everyday", and "daily" for every day.
        assertEquals("140", read("buy $20 of eth everyday for a week")?.amount)
        assertEquals(5 * 86_400, read("dca $10 into eth daily for 5 days")?.durationSeconds)
        val over = must("dca $300 into eth over 3 days")
        assertEquals("300", over.amount)
        assertEquals(3 * 86_400, over.durationSeconds)
    }

    @Test fun movingBetweenChainsIsABridge() {
        val i = must("move 50 usdc from base to arbitrum")
        assertEquals(TradeIntent.Kind.BRIDGE, i.kind)
        assertEquals("base", i.chainName)
        assertEquals("arbitrum", i.toChain)
        assertEquals("Move 50 USDC to Arbitrum", i.title)
        assertNull(read("move 50 usdc from base to base"))
    }

    /** Sends to an ENS or SNS name (Arpit, 2026-11-12: "I feel you can add
     *  sending to .eth and .sol"): MetaMask on Ethereum chains, Phantom on
     *  Solana. Whitechain pay requests stay out. */
    @Test fun aSendToANameIsRead() {
        val eth = must("send 20 usdc to Vitalik.ETH")
        assertEquals(TradeIntent.Kind.SEND, eth.kind)
        assertEquals("vitalik.eth", eth.to)
        assertEquals("20", eth.amount)
        assertEquals("USDC", eth.sell)
        assertEquals("base", eth.chainName)
        assertEquals("Send 20 USDC to vitalik.eth", eth.title)
        assertEquals("Base · MetaMask", eth.detail)
        assertEquals("vitalik.eth", eth.query["to"])
        assertEquals("send", eth.query["kind"])

        val arb = must("pls send 0.01 eth to pay.arpit.eth on arbitrum")
        assertEquals("arbitrum", arb.chainName)
        assertEquals("pay.arpit.eth", arb.to)

        val sol = must("pay arpit.sol 5 usdc")
        assertEquals("arpit.sol", sol.to)
        assertEquals("solana", sol.chainName)
        assertEquals("Solana · Phantom", sol.detail)
        // SOL lives on Solana, even to an ENS name (its Solana record).
        assertEquals("solana", read("send 1 sol to vitalik.eth")?.chainName)

        val hex = must("send 0.01 eth to 0x52908400098527886E0F7030069857D2E4169EE7")
        assertEquals("0x52908400098527886E0F7030069857D2E4169EE7", hex.to)
        assertEquals("Send 0.01 ETH to 0x5290…9EE7", hex.title)
        assertFalse(TradeIntent.isName(hex.to))
        assertTrue(TradeIntent.isName(eth.to))
        val chip = Smart.chip("send 5 usdc to vitalik.eth", emptyList())
        assertTrue("$chip", chip is Smart.Chip.Trade)
        assertEquals("vitalik.eth", (chip as Smart.Chip.Trade).intent.to)
        assertEquals("MetaMask", Smart.key(chip))
        assertEquals("Send", Smart.verb(chip))
        assertEquals("Send 5 USDC to vitalik.eth · Base", Smart.display(chip))
    }

    @Test fun sendsGlyfCantCarryAreNotRead() {
        for (text in listOf("send usdc to arpit.eth",                // no amount
                "send 5 usdt to arpit.sol",              // Phantom's send here: SOL or USDC
                "send 1 sol to 0x52908400098527886E0F7030069857D2E4169EE7",
                "send 5 usdc to arpit.eth on solana",    // an ENS name's EVM send isn't on Solana
                "send 1 tsla to arpit.eth",              // shares stay trades
                "send 5 usdc to arpit.com",
                "request 20 usdt", "request 15 usdt on whitechain")) {
            assertNull(text, read(text))
        }
        // Whitechain isn't a trading chain.
        assertNull(read("swap 1 usdc to eth on whitechain"))
    }

    /** The panel shows the address a name points at before anything is
     *  signed, and a name that points nowhere stops the send. */
    @Test fun aNameResolvesForTheSendsChain() {
        val answer = JSONObject().put("ok", true).put("found", true).put("name", "vitalik.eth")
            .put("addresses", JSONObject().put("ethereum", "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
                .put("base", "0x1111111111111111111111111111111111111111")
                .put("solana", "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"))
        assertEquals("0x1111111111111111111111111111111111111111",
            TradeIntent.recipient("vitalik.eth", "base", true, answer).first)
        // No Unichain record: the Ethereum one is the same account.
        assertEquals("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
            TradeIntent.recipient("vitalik.eth", "unichain", true, answer).first)
        assertEquals("7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU",
            TradeIntent.recipient("vitalik.eth", "solana", true, answer).first)
        // A Solana send never falls back to an Ethereum address.
        val evmOnly = JSONObject().put("addresses", JSONObject().put("ethereum", "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"))
        val noSol = TradeIntent.recipient("vitalik.eth", "solana", true, evmOnly)
        assertNull(noSol.first)
        assertEquals("vitalik.eth has no Solana address", noSol.second)
        val missing = TradeIntent.recipient("nobody.sol", "solana", false, JSONObject().put("ok", false).put("found", false))
        assertNull(missing.first)
        assertEquals("nobody.sol isn’t registered", missing.second)
        assertEquals("Couldn’t look up a.eth", TradeIntent.recipient("a.eth", "base", false, null).second)
        // Junk in a record is no address.
        assertNull(TradeIntent.recipient("a.eth", "base", true,
            JSONObject().put("addresses", JSONObject().put("base", "0x12"))).first)
    }

    /** A Solana send goes to the app's existing Phantom send, with the
     *  address the name resolved to; an Ethereum one to the Trade screen. */
    @Test fun aSolanaSendGoesThroughPhantom() {
        val owner = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
        val q = must("send 1.5 sol to arpit.sol").query + ("address" to owner)
        val pay = TradeIntent.phantomSend(q)!!
        assertEquals("send", pay["kind"])
        assertEquals(owner, pay["to"])
        assertEquals("1.5", pay["amount"])
        assertEquals("So11111111111111111111111111111111111111112", pay["mint"])
        assertEquals("9", pay["decimals"])
        val usdc = must("pay arpit.sol 5 usdc").query + ("address" to owner)
        assertEquals("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", TradeIntent.phantomSend(usdc)?.get("mint"))
        // Not resolved yet: nothing goes anywhere.
        assertNull(TradeIntent.phantomSend(must("pay arpit.sol 5 usdc").query))
        val evm = must("send 5 usdc to vitalik.eth").query + ("address" to "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        assertNull(TradeIntent.phantomSend(evm))
        // Android's own: where the panel's hand-off goes in the app.
        assertEquals("pay", TradeQuote.destination(usdc).first)
        assertEquals("trade", TradeQuote.destination(evm).first)
        assertEquals(evm, TradeQuote.destination(evm).second)
    }

    /** The panel edits a send like a move: the token is both sides, the
     *  amount stays, and the chains are where the name can be paid. */
    @Test fun aSendIsEditedInThePanel() {
        val i = must("send 5 usdc to vitalik.eth")
        assertTrue(TradeEdit.sells(i))
        assertEquals(listOf(TradeField.AMOUNT), TradeEdit.fields(i))
        assertEquals(SponsorMenu.SWAP_CHAINS, TradeEdit.chains(i))
        assertEquals(listOf("solana"), TradeEdit.chains(must("pay arpit.sol 5 usdc")))
        assertNull(TradeEdit.problem(i))
        assertEquals("Enter an amount", TradeEdit.problem(i.copy(amount = null)))
        val dai = TradeEdit.pick(TokenPick("DAI", "Dai"), TradeEdit.Side.SELL, i)
        assertEquals("DAI", dai.sell)
        assertEquals("DAI", dai.buy)
        assertEquals("5", dai.amount)
        assertEquals("vitalik.eth", dai.to)
    }

    @Test fun solanaOrdersGoToTheAppOnSolana() {
        // Phantom signs these (lib/wallet/flash_solana.dart): the app reads chain=solana.
        val stop = must("sell 0.1 sol if it drops below 100")
        assertEquals(TradeIntent.Kind.STOP_LOSS, stop.kind)
        assertEquals("solana", stop.query["chain"])
        assertEquals("SOL", stop.query["sell"])
        val bracket = must("buy 0.1 sol, tp 200, sl 100")
        assertEquals(TradeIntent.Kind.BRACKET, bracket.kind)
        assertEquals("solana", bracket.query["chain"])
        assertEquals("0.1", bracket.query["buyAmount"])
        assertEquals("solana", read("buy $10 of sol at 80")?.query?.get("chain"))
    }

    @Test fun theStripOffersEachTradeAsItsChip() {
        for (text in listOf("Buy \$20 of eth every day for a week ", "Buy \$20 of eth every day for a week",
                "Sell my eth if it drops below 3000", "Swap 0.05 eth to usdc on base")) {
            val chip = Smart.chip(text, emptyList())
            assertTrue("$text: $chip", chip is Smart.Chip.Trade)
        }
    }

    @Test fun ordinaryWordsAreNoTrade() {
        for (text in listOf("swap shifts with sam", "I'll buy dinner tonight", "sell the old bike",
                "send me the doc", "stop it", "I want to take profit from this lesson")) {
            assertNull(text, read(text))
        }
    }

    @Test fun theCommandMayFollowASentence() {
        assertEquals("1", must("ok done. swap 1 usdc to eth").amount)
    }

    @Test fun theQueryCarriesEverythingTheAppNeeds() {
        val q = must("buy 0.1 eth take profit 4500 stop loss 3000 on arbitrum").query
        assertEquals("bracket", q["kind"])
        assertEquals("arbitrum", q["chain"])
        assertEquals("4500", q["price"])
        assertEquals("3000", q["stopPrice"])
        assertEquals("0.1", q["buyAmount"])
    }

    /** Always the person's own wallet app: there is no Glyf wallet. */
    @Test fun theWalletPerChainIsAlwaysAnOutsideWallet() {
        assertEquals("Phantom", TradeIntent.walletName("solana"))
        assertEquals("MetaMask", TradeIntent.walletName("base"))
        assertEquals("MetaMask", TradeIntent.walletName("arbitrum"))
        assertEquals("MetaMask", TradeIntent.walletName(null))
    }

    /** Shares trade on Base, by their address there. */
    @Test fun sharesTradeOnBase() {
        val buy = must("buy $10 of apple")
        assertEquals(TradeIntent.Kind.SWAP, buy.kind)
        assertEquals("USDC", buy.sell)
        assertEquals("AAPL", buy.buy)
        assertEquals("base", buy.chainName)
        assertEquals("0xb200000000000000000000C2e324d24d7eEcd1fb", buy.buyAddress)
        assertEquals("Uniswap", buy.venue)
        assertEquals("AAPL", read("buy \$10 of \$aapl")?.buy)
        val limit = must("buy $10 of tesla if it dips below 300")
        assertEquals(TradeIntent.Kind.LIMIT, limit.kind)
        assertEquals("base", limit.chainName)
        assertEquals(TradeIntent.baseStocks["TSLA"], limit.query["buyAddress"] ?: limit.query["sellAddress"])
        assertEquals("base", read("swap 20 usdc to nvda on solana")?.chainName)
        assertEquals("AAPL", TradeIntent.baseStock("AAPLx"))
        assertEquals("AAPL", TradeIntent.baseStock("AAPLon"))
        assertNull(TradeIntent.baseStock("SOL"))
        assertNull(read("I ate an apple"))
    }

    /** "every time", "whenever" and "it's below" read as a price to wait
     *  for; a DCA says what was typed, not its total. */
    @Test fun howPeopleSayAPriceAndADCA() {
        for (text in listOf("buy $10 of tesla every time it dips below 300", "buy $10 of tesla whenever it drops below 300",
                "buy $10 of tesla when it's below 300", "buy $10 of tesla when it’s below 300",
                "buy $10 of tesla if the price is under 300")) {
            val i = must(text)
            assertEquals(text, TradeIntent.Kind.LIMIT, i.kind)
            assertEquals(text, "300", i.price)
            assertEquals(text, "TSLA", i.buy)
            assertEquals(text, "10", i.amount)
            assertTrue(text, i.amountIsUSD)
            assertEquals(text, "$10", TradeEdit.shown(TradeField.AMOUNT, i))
        }
        // As the phone types it: capitals, autocorrect's curly apostrophe.
        val typed = must("Buy $10 of Tesla every time it dips below 300")
        assertEquals("$10", TradeEdit.shown(TradeField.AMOUNT, typed))
        assertEquals("$300", TradeEdit.shown(TradeField.PRICE, typed))
        assertEquals("Buy $10 of TSLA at $300", typed.title)
        assertEquals(TradeIntent.Kind.STOP_LOSS, read("sell my eth whenever it falls below 1800")?.kind)
        val dca = must("buy $5 of eth every hour for 2 hours")
        assertEquals(TradeIntent.Kind.TWAP, dca.kind)
        assertEquals("10", dca.amount)
        assertEquals("Buy $5 of ETH every hour for 2 hours", dca.title)
        assertFalse(dca.awaitingPrice)
    }

    /** Android's own: the strip names the venue and says what a tap does,
     *  as iOS's chip does (Smart.swift's `.trade` cases). */
    @Test fun theChipSaysTheVenueAndTheVerb() {
        val swap = Smart.Chip.Trade(must("swap 0.05 eth to usdc on base"))
        assertEquals("Uniswap", Smart.key(swap))
        assertEquals("Swap", Smart.verb(swap))
        assertEquals("Swap 0.05 ETH → USDC · Base", Smart.display(swap))
        assertEquals("", Smart.insert(swap))
        assertEquals("Buy", Smart.verb(Smart.Chip.Trade(must("buy $50 of eth"))))
        assertEquals("Move", Smart.verb(Smart.Chip.Trade(must("move 50 usdc from base to arbitrum"))))
        assertEquals("Set", Smart.verb(Smart.Chip.Trade(must("sell my eth if it drops below 3000"))))
        assertEquals("Jupiter", Smart.key(Smart.Chip.Trade(must("swap 10 usdc to usdt on solana"))))
    }
}
