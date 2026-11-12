package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The trade panel's edits (TradeEdit): what a typed value, a picked token
 *  or a picked chain does to the trade, the picker's filtering, and the
 *  cross-chain swaps read from words. The twin of TradeEditTests.swift. */
class TradeEditTest {

    private fun read(text: String): TradeIntent = TradeIntent.parse(text) ?: throw AssertionError(text)

    // MARK: typed values

    @Test fun theAmountOfASwapIsWhatsSpent() {
        val i = TradeEdit.apply(TradeField.AMOUNT, "25.5", read("swap 10 usdc to eth on base"))
        assertEquals("25.5", i.amount)
        assertEquals("25.5", i.query["amount"])
        assertEquals("Amount in USDC", TradeEdit.label(TradeField.AMOUNT, i))
    }

    @Test fun anEmptyAmountOnASellIsEverythingHeld() {
        val i = TradeEdit.apply(TradeField.AMOUNT, "", read("swap 10 usdc to eth on base"))
        assertNull(i.amount)
        assertEquals("All", TradeEdit.shown(TradeField.AMOUNT, i))
        assertNull(i.query["amount"])
    }

    @Test fun buyingAnAmountEditsWhatComesBack() {
        val i = TradeEdit.apply(TradeField.AMOUNT, "0.2", read("buy 0.1 eth with usdc"))
        assertEquals("0.2", i.buyAmount)
        assertNull(i.amount)
        assertEquals("ETH to get", TradeEdit.label(TradeField.AMOUNT, i))
    }

    @Test fun aBuyOrderIsTypedInDollars() {
        val i = read("buy $20 of eth at 2800")
        assertEquals(TradeEdit.AmountUnit.Dollars, TradeEdit.amountUnit(i))
        val j = TradeEdit.apply(TradeField.AMOUNT, "75", i)
        assertEquals("75", j.amount)
        assertEquals("$75", TradeEdit.shown(TradeField.AMOUNT, j))
    }

    @Test fun aPriceEditReplacesAStartersDistance() {
        var i = SponsorMenu.starter(TradeIntent.Kind.LIMIT, "base")!!
        assertTrue(i.awaitingPrice)
        i = TradeEdit.apply(TradeField.PRICE, "2,500", i)
        assertEquals("a comma is a decimal point while typing", "2.500", i.price)
        i = TradeEdit.apply(TradeField.PRICE, "2500", i)
        assertEquals("2500", i.price)
        assertNull(i.pricePercent)
        assertFalse(i.awaitingPrice)
        assertEquals("2500", i.query["price"])
    }

    @Test fun bracketPricesAreEditedApartAndCheckedTogether() {
        var i = read("my eth tp 4500 sl 3000")
        assertEquals(listOf(TradeField.AMOUNT, TradeField.PRICE, TradeField.STOP_PRICE), TradeEdit.fields(i))
        assertNull(TradeEdit.problem(i))
        i = TradeEdit.apply(TradeField.STOP_PRICE, "4600", i)
        assertEquals("4600", i.stopPrice)
        assertEquals("Take profit must be above the stop-loss", TradeEdit.problem(i))
        i = TradeEdit.apply(TradeField.PRICE, "5000", i)
        assertNull(TradeEdit.problem(i))
        assertEquals("4600", i.query["stopPrice"])
    }

    @Test fun trailAndDuration() {
        var t = read("trail my eth by 5%")
        t = TradeEdit.apply(TradeField.TRAIL, "7.5", t)
        assertEquals("7.5", t.trailPercent)
        assertEquals("7.5%", TradeEdit.shown(TradeField.TRAIL, t))
        assertEquals("Trail between 0.5% and 50%", TradeEdit.problem(TradeEdit.apply(TradeField.TRAIL, "80", t)))

        var w = read("buy $100 of eth over a day")
        assertEquals("1", TradeEdit.value(TradeField.DURATION, w))
        w = TradeEdit.apply(TradeField.DURATION, "0.5", w)
        assertEquals(43_200, w.durationSeconds)
        assertEquals("12 hours", TradeEdit.shown(TradeField.DURATION, w))
        w = TradeEdit.apply(TradeField.DURATION, "7", w)
        assertEquals("1 week", TradeEdit.shown(TradeField.DURATION, w))
        assertEquals("604800", w.query["duration"])
    }

    @Test fun cleanNumbers() {
        assertEquals("1.23", TradeEdit.cleanNumber("1.2.3"))
        assertEquals("0.5", TradeEdit.cleanNumber(".5"))
        assertEquals("7", TradeEdit.cleanNumber("007"))
        assertEquals("12", TradeEdit.cleanNumber("12a"))
    }

    /** Android's own: an edit hands back a new trade and leaves the one it
     *  was given as it was (Swift's structs copy; Kotlin's data classes don't). */
    @Test fun anEditNeverChangesTheTradeItWasGiven() {
        val i = read("swap 10 usdc to eth on base")
        TradeEdit.apply(TradeField.AMOUNT, "99", i)
        TradeEdit.pick(TokenPick("PEPE", "Pepe"), TradeEdit.Side.BUY, i)
        TradeEdit.pickChain("arbitrum", TradeEdit.Side.SELL, i)
        TradeEdit.flip(i)
        assertEquals(read("swap 10 usdc to eth on base"), i)
    }

    // MARK: tokens and chains

    @Test fun pickingASwapTokenSetsItsAddress() {
        val pepe = TokenPick("PEPE", "Pepe", "0xB4fDe59a779991bfB6a52253B51947828b982be3")
        val i = TradeEdit.pick(pepe, TradeEdit.Side.BUY, read("swap 10 usdc to eth on base"))
        assertEquals("PEPE", i.buy)
        assertEquals("0xB4fDe59a779991bfB6a52253B51947828b982be3", i.query["buyAddress"])
        assertNull(i.sellAddress)
    }

    @Test fun pickingTheOtherSidesTokenFlips() {
        val i = TradeEdit.pick(TokenPick("ETH", "Ether", native = true), TradeEdit.Side.SELL,
            read("swap 10 usdc to eth on base"))
        assertEquals("ETH", i.sell)
        assertEquals("USDC", i.buy)
        assertEquals("10", i.amount)
    }

    @Test fun flipMovesTheChainsOfACrossChainSwap() {
        val i = TradeEdit.flip(read("swap 50 usdc on base to eth on arbitrum"))
        assertEquals("ETH", i.sell)
        assertEquals("USDC", i.buy)
        assertEquals("arbitrum", i.chainName)
        assertEquals("base", i.buyChain)
    }

    @Test fun aFlashOrderPickChangesItsAssetNotTheDollarSide() {
        val link = TokenPick("LINK", "Chainlink")
        val buy = TradeEdit.pick(link, TradeEdit.Side.SELL, read("buy $20 of eth at 2800"))
        assertEquals("LINK", buy.buy)
        assertEquals("USDC", buy.sell)
        val sell = TradeEdit.pick(link, TradeEdit.Side.BUY, read("stop loss my eth at 3000"))
        assertEquals("LINK", sell.sell)
        assertEquals("USDC", sell.buy)
        val bridge = TradeEdit.pick(TokenPick("USDC", "USD Coin"), TradeEdit.Side.SELL,
            read("move 50 usdc from base to arbitrum"))
        assertEquals("USDC", bridge.sell)
        assertEquals("USDC", bridge.buy)
    }

    @Test fun chainsPerKind() {
        assertEquals(listOf("base", "ethereum", "arbitrum", "optimism", "unichain"), TradeEdit.chains(read("swap 10 usdc to eth")))
        assertTrue(TradeEdit.chains(read("stop loss my eth at 3000")).contains("solana"))
        assertFalse(TradeEdit.chains(read("swap 10 usdc to eth")).contains("solana"))
    }

    @Test fun aFlashOrderMovedToSolanaTradesSol() {
        val i = TradeEdit.pickChain("solana", TradeEdit.Side.SELL, read("stop loss my eth at 3000"))
        assertEquals("solana", i.chainName)
        assertEquals("SOL", i.sell)
        assertEquals("USDC", i.buy)
        val back = TradeEdit.pickChain("base", TradeEdit.Side.SELL, i)
        assertEquals("ETH", back.sell)
    }

    @Test fun anOrdersPricesFollowANewAsset() {
        val eth = read("my eth tp 4500 sl 3000")
        val sol = TradeEdit.repriced(TradeEdit.pickChain("solana", TradeEdit.Side.SELL, eth), eth)
        assertEquals("SOL", sol.sell)
        assertNull(sol.price)
        assertNull(sol.stopPrice)
        assertTrue(sol.awaitingPrice)
        val filled = SponsorMenu.priced(sol, 100.0)
        assertEquals("110", filled.price)
        assertEquals("90", filled.stopPrice)
        // Same asset, another value: nothing reset.
        val same = TradeEdit.apply(TradeField.PRICE, "5000", eth)
        assertEquals("5000", TradeEdit.repriced(same, eth).price)
        // A buy's limit goes back under the new market.
        val buy = read("buy $20 of eth at 2800")
        val link = TradeEdit.repriced(TradeEdit.pick(TokenPick("LINK", "Chainlink"), TradeEdit.Side.BUY, buy), buy)
        assertEquals(-5.0, link.pricePercent!!, 0.0)
        assertEquals("dollars spent stay", "20", link.amount)
    }

    @Test fun youGetOnAnotherChainIsCrossChain() {
        val i = TradeEdit.pickChain("arbitrum", TradeEdit.Side.BUY, read("swap 10 usdc to eth on base"))
        assertEquals("arbitrum", i.buyChain)
        assertEquals("arbitrum", i.query["buyChain"])
        assertEquals("Base → Arbitrum · Uniswap", i.detail)
        // Back on the same chain: an ordinary swap.
        assertNull(TradeEdit.pickChain("base", TradeEdit.Side.BUY, i).buyChain)
        // A bridge's buy side is where it lands.
        val move = TradeEdit.pickChain("optimism", TradeEdit.Side.BUY, read("move 50 usdc from base to arbitrum"))
        assertEquals("optimism", move.toChain)
    }

    @Test fun sameTokenOnBothSidesIsAProblemOnlyOnOneChain() {
        val i = read("swap 10 usdc to eth on base")
        i.buy = "USDC"
        assertEquals("Pick two different tokens", TradeEdit.problem(i))
        i.buyChain = "arbitrum"
        assertNull(TradeEdit.problem(i))
    }

    // MARK: picker rows

    @Test fun filterRanksSymbolThenPrefixThenName() {
        val rows = listOf(TokenPick("XPEPE", "x"), TokenPick("PEPE", "Pepe"),
            TokenPick("PEPECOIN", "p"), TokenPick("FROG", "Pepe's friend"))
        assertEquals(listOf("PEPE", "PEPECOIN", "FROG", "XPEPE"), TradeEdit.filter(rows, "pepe").map { it.symbol })
        assertEquals("PEPE", TradeEdit.filter(rows, "\$PEPE").first().symbol)
        assertEquals(4, TradeEdit.filter(rows, "").size)
        assertTrue(TradeEdit.filter(rows, "zzz").isEmpty())
        val addressed = listOf(TokenPick("PEPE", "Pepe", "0xAbC0000000000000000000000000000000000001"))
        assertEquals(1, TradeEdit.filter(addressed, "0xabc0000000000000000000000000000000000001").size)
    }

    @Test fun builtInRowsPerChainAndMergeKeepsThemFirst() {
        assertEquals(listOf("SOL", "USDC", "USDT"), TradeEdit.builtIn("solana").map { it.symbol })
        assertEquals(listOf("ETH", "USDC", "WETH", "DAI", "cbBTC"), TradeEdit.builtIn("base").map { it.symbol })
        val server = listOf(TokenPick("USDC", "USD Coin", "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", logo = "https://x/usdc.png"),
            TokenPick("PEPE", "Pepe", "0xB4fDe59a779991bfB6a52253B51947828b982be3"))
        val merged = TradeEdit.merge(TradeEdit.builtIn("base"), server)
        assertEquals("ETH", merged.first().symbol)
        assertEquals(1, merged.count { it.symbol == "USDC" })
        assertEquals("https://x/usdc.png", merged.first { it.symbol == "USDC" }.logo)
        assertEquals("PEPE", merged.last().symbol)
    }

    @Test fun tokenRowsReadTheServersJSON() {
        val t = TokenPick.fromJson(JSONObject().put("symbol", "ETH").put("name", "Ether")
            .put("address", "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE")
            .put("decimals", 18).put("native", true).put("logoURI", "https://x/eth.png"))
        assertEquals(true, t?.native)
        assertEquals("https://x/eth.png", t?.logo)
        assertEquals(18, t?.decimals)
        assertNull(TokenPick.fromJson(JSONObject().put("name", "no symbol")))
    }

    // MARK: words

    @Test fun aCrossChainSwapReadsBothChains() {
        val i = read("swap 50 usdc on base to eth on arbitrum")
        assertEquals(TradeIntent.Kind.SWAP, i.kind)
        assertEquals("50", i.amount)
        assertEquals("USDC", i.sell)
        assertEquals("ETH", i.buy)
        assertEquals("base", i.chainName)
        assertEquals("arbitrum", i.buyChain)
        assertEquals("Swap 50 USDC → ETH on Arbitrum", i.title)
        assertEquals("arbitrum", i.query["buyChain"])
        // The same token moved is a swap across chains too.
        assertEquals("optimism", read("swap 20 usdc on base to usdc on optimism").buyChain)
        assertNull(TradeIntent.parse("swap 20 usdc on base to usdc on base"))
    }

    @Test fun aMemeCoinSwapLandsInTheSamePanel() {
        val i = read("swap 0.1 eth to pepe on base")
        assertEquals(TradeIntent.Kind.SWAP, i.kind)
        assertEquals("PEPE", i.buy)
        assertEquals("base", i.chainName)
        assertNull(i.buyChain)
    }
}
