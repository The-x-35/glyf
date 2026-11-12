package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The trade panel's numbers (TradeQuote): what it asks /uniswap and
 *  /flash, how their answers read, and what the one button says. */
class TradeQuoteTest {

    private fun read(text: String) = TradeIntent.parse(text) ?: throw AssertionError(text)

    @Test fun aSwapAsksUniswapForWhatTheAmountGets() {
        val b = TradeQuote.body(read("swap 0.05 eth to usdc on arbitrum"))!!
        assertEquals("arbitrum", b.getString("chain"))
        assertEquals("ETH", b.getString("sell"))
        assertEquals("USDC", b.getString("buy"))
        assertEquals("0.05", b.getString("amount"))
        assertFalse(b.has("buyChain"))
    }

    @Test fun buyingAnAmountAsksWhatItCostsTheOtherWayRound() {
        val b = TradeQuote.body(read("buy 0.1 eth with usdc"))!!
        assertEquals("ETH", b.getString("sell"))
        assertEquals("USDC", b.getString("buy"))
        assertEquals("0.1", b.getString("amount"))
        val q = TradeQuote.read(true, JSONObject().put("amountOut", "312.5").put("sellUsd", "300").put("buyUsd", "312"), reversed = true)
        assertEquals(312.5, q.out!!, 0.0)
        assertEquals("the sides put back", 312.0, q.inUsd!!, 0.0)
        assertEquals(300.0, q.outUsd!!, 0.0)
    }

    @Test fun aPickedTokenGoesByItsAddressAndACrossChainSwapNamesBothChains() {
        val pepe = TradeEdit.pick(TokenPick("PEPE", "Pepe", "0xB4fDe59a779991bfB6a52253B51947828b982be3"),
            TradeEdit.Side.BUY, read("swap 10 usdc to eth on base"))
        assertEquals("0xB4fDe59a779991bfB6a52253B51947828b982be3", TradeQuote.body(pepe)!!.getString("buy"))
        val cross = TradeQuote.body(read("swap 50 usdc on base to eth on arbitrum"))!!
        assertEquals("base", cross.getString("chain"))
        assertEquals("arbitrum", cross.getString("buyChain"))
        // A share is asked by its Base address.
        assertEquals(TradeIntent.baseStocks["AAPL"], TradeQuote.body(read("buy $10 of apple"))!!.getString("buy"))
    }

    @Test fun nothingIsAskedWithoutAnAmountOrOnSolana() {
        assertNull(TradeQuote.body(read("sell my eth")))
        assertNull(TradeQuote.body(read("swap 10 usdc to usdt on solana")))
        assertNull(TradeQuote.body(read("stop loss my eth at 3000")))
    }

    @Test fun anAnswerReadsItsDollarsEitherWay() {
        val flat = TradeQuote.read(true, JSONObject().put("amountOut", "0.0031").put("sellUsd", "10").put("buyUsd", "9.97"), false)
        assertEquals(0.0031, flat.out!!, 1e-12)
        assertEquals(10.0, flat.inUsd!!, 0.0)
        val nested = TradeQuote.read(true, JSONObject().put("amountOut", "2")
            .put("sell", JSONObject().put("usd", "5")).put("buy", JSONObject().put("usd", "4.9")), false)
        assertEquals(5.0, nested.inUsd!!, 0.0)
        assertEquals(4.9, nested.outUsd!!, 0.0)
        assertNull(nested.error)
    }

    @Test fun aRefusalSpeaksOnTheButtonInOneLine() {
        val q = TradeQuote.read(false, JSONObject().put("ok", false).put("error", "No Uniswap pool for PEPE and USDC on Unichain"), false)
        assertEquals("No Uniswap pool for PEPE and USDC on Unichain", q.error)
        assertEquals("No quote right now", TradeQuote.read(false, null, false).error)
        assertEquals(58, TradeQuote.shortError("x".repeat(90)).length)
        val go = TradeQuote.go(read("swap 10 usdc to eth"), "0xabc", false, q, null)
        assertEquals(q.error, go.title)
        assertTrue(go.blocked)
    }

    @Test fun jupiterPricesBothSidesOnSolana() {
        val prices = mapOf("SOL" to 100.0)
        // Words keep a swap with SOL off Solana's stablecoins; the panel's picker allows it.
        val toSol = TradeEdit.pick(TokenPick("SOL", "Solana", native = true), TradeEdit.Side.BUY,
            read("swap 10 usdc to usdt on solana"))
        val q = TradeQuote.jupiter(toSol) { prices[it] }!!
        assertEquals(0.1, q.out!!, 1e-12)
        assertEquals(10.0, q.inUsd!!, 0.0)
        assertNull(TradeQuote.jupiter(toSol) { null })
    }

    @Test fun aShareIsPricedFromFlashsListing() {
        val json = JSONObject().put("results", JSONArray()
            .put(JSONObject().put("address", "0xOTHER").put("price", 1))
            .put(JSONObject().put("address", TradeIntent.baseStocks["TSLA"]!!.lowercase()).put("price", "342.5")))
        assertEquals(342.5, TradeQuote.sharePrice(json, TradeIntent.baseStocks["TSLA"]!!)!!, 0.0)
        assertNull(TradeQuote.sharePrice(JSONObject(), "0x1"))
        val body = TradeQuote.priceBody("base", "eth", null)
        assertEquals("eth", body.getString("sell"))
        assertEquals("USDC", body.getString("buy"))
        assertEquals("1", body.getString("amount"))
    }

    @Test fun balancesReadTheGasCoinAsETH() {
        val held = TradeQuote.balances(JSONObject().put("balances", JSONArray()
            .put(JSONObject().put("symbol", "native").put("amount", "0.5"))
            .put(JSONObject().put("symbol", "USDC").put("amount", "12.25"))))!!
        assertEquals(0.5, held["ETH"]!!, 0.0)
        assertEquals(12.25, held["USDC"]!!, 0.0)
        assertNull(TradeQuote.balances(JSONObject()))
    }

    @Test fun theButtonAsksForTheWalletFirstThenWhatsMissing() {
        val swap = read("swap 10 usdc to eth on base")
        assertEquals(TradeQuote.Go("Connect MetaMask", blocked = false, connect = true), TradeQuote.go(swap, null, false, null, null))
        assertEquals("Connect Phantom", TradeQuote.go(read("sell 0.1 sol if it drops below 100"), "", false, null, null).title)
        // Waiting on the quote: greyed.
        assertTrue(TradeQuote.go(swap, "0xabc", true, null, null).blocked)
        assertEquals("Swap ≈ $10.00", TradeQuote.go(swap, "0xabc", false, TradeQuote.Quote(0.003, 10.0, 9.98), 50.0).title)
        assertEquals("Not enough USDC", TradeQuote.go(swap, "0xabc", false, TradeQuote.Quote(0.003, 10.0, 9.98), 5.0).title)
        val starter = SponsorMenu.starter(TradeIntent.Kind.STOP_LOSS, "base")!!
        assertEquals("Getting the price", TradeQuote.go(starter, "0xabc", true, null, null).title)
        assertEquals("No price yet", TradeQuote.go(starter, "0xabc", false, null, null).title)
        assertEquals("Place stop-loss", TradeQuote.go(read("stop loss my eth at 3000"), "0xabc", false, null, 1.0).title)
        assertEquals("Set both prices", TradeQuote.go(TradeEdit.apply(TradeField.PRICE, "", read("my eth tp 4500 sl 3000")), "0xabc", false, null, null).title)
        assertEquals("Move to Arbitrum", TradeQuote.go(read("move 50 usdc from base to arbitrum"), "0xabc", false, null, null).title)
        assertEquals("Start TWAP", TradeQuote.go(read("dca $20 in eth each month"), "0xabc", false, null, null).title)
    }

    @Test fun theAppIsHandedTheTradesWordsAndItsTitle() {
        val q = TradeQuote.handOff(read("buy $10 of tesla if it dips below 300"))
        assertEquals("limit", q["kind"])
        assertEquals("TSLA", q["buy"])
        assertEquals("1", q["usd"])
        assertEquals("300", q["price"])
        assertEquals("Buy $10 of TSLA at $300", q["title"])
    }

    @Test fun namesAndFigures() {
        assertEquals("Stop-loss", TradeQuote.headerTitle(TradeIntent.Kind.STOP_LOSS))
        assertEquals("You pay", TradeQuote.topKey(read("swap 10 usdc to eth")))
        assertEquals("Sell", TradeQuote.topKey(read("stop loss my eth at 3000")))
        assertEquals("Buy", TradeQuote.topKey(read("buy $20 of eth at 2800")))
        assertEquals("Spend", TradeQuote.topKey(read("buy $100 of eth over a day")))
        assertEquals("4,426,585.96", TradeQuote.amount(4_426_585.957))
        assertEquals("0.011253", TradeQuote.amount(0.0112534))
        assertEquals("< $0.01", TradeQuote.approx(0.004))
        assertEquals("≈ $1,234", TradeQuote.approx(1234.4))
        assertEquals("cbBTC", TradeQuote.display("CBBTC"))
    }
}
