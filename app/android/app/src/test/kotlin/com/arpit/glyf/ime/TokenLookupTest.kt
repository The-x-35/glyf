package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The cashtag lookup ported from server/src/lib/rates.ts, with the
 *  server's own cases (server/test/rates.test.ts): the token that IS the
 *  ticker, a stock before a meme coin that took its ticker, names like
 *  $apple and $bitcoin, made-up tickers remembered as misses. */
class TokenLookupTest {

    private fun j(vararg pairs: Pair<String, Any?>) = JSONObject().apply { pairs.forEach { put(it.first, it.second) } }
    private fun tags(vararg t: String) = org.json.JSONArray(t.toList())

    private val jupiter = listOf(
        j("id" to "jupSoLaHXQiZZTSfEWMTRRgpnyFm8f6sZdosWBjx93v", "symbol" to "JupSOL", "name" to "Jupiter Staked SOL",
            "isVerified" to true, "usdPrice" to 135.17, "tags" to tags("strict", "verified", "lst")),
        j("id" to "So11111111111111111111111111111111111111112", "symbol" to "SOL", "name" to "Wrapped SOL",
            "isVerified" to true, "usdPrice" to 111.77, "tags" to tags("major", "strict", "verified"), "liquidity" to 8e8),
        j("id" to "FakeSoL1111111111111111111111111111111111111", "symbol" to "SOL", "name" to "Not Solana",
            "isVerified" to false, "usdPrice" to 0.5),
    )

    private fun share(id: String, symbol: String, name: String, usd: Double) =
        j("id" to id, "symbol" to symbol, "name" to name, "isVerified" to true, "usdPrice" to usd,
            "tags" to tags("stocks", "xstocks", "verified"), "liquidity" to 6e5, "stats24h" to j("priceChange" to 1.5))

    private val apple = listOf(
        share("XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp", "AAPLx", "Apple xStock", 340.3),
        j("id" to "123mYEnRLM2LLYsJW3K6oyYh8uP1fngj732iG638ondo", "symbol" to "AAPLon", "name" to "Apple (Ondo Tokenized)",
            "isVerified" to true, "usdPrice" to 340.22, "tags" to tags("equities", "verified"), "liquidity" to 9e5),
        j("id" to "9B2sGQFakeAaplx1111111111111111111111111111", "symbol" to "AAPLX", "name" to "AAPL Stock with Dividends",
            "isVerified" to false, "usdPrice" to 0.01, "tags" to tags("unknown")),
        j("id" to "BWMwxBAppleCoin111111111111111111111111111", "symbol" to "AAPL", "name" to "Applecoin",
            "isVerified" to false, "usdPrice" to 0.02),
    )

    /** A stand-in for Jupiter's search that answers by query and counts calls. */
    private class Fake(val answer: (String) -> List<JSONObject>?) {
        val calls = mutableListOf<String>()
        fun search(q: String): List<JSONObject> {
            calls += q
            return answer(q) ?: throw TokenLookup.Unavailable("down")
        }
    }

    @Test fun picksTheTokenThatIsTheTicker() {
        val sol = TokenLookup.pickToken("SOL", jupiter)
        assertEquals("So11111111111111111111111111111111111111112", sol?.mint)
        assertEquals(111.77, sol!!.usd, 0.0)
        assertNull(TokenLookup.pickToken("SOL", listOf(jupiter[2])))
        assertNull(TokenLookup.pickToken("BONK", jupiter))
        assertEquals("SOL", TokenLookup.tickerOf("\$sol"))
        assertNull(TokenLookup.tickerOf("13"))
        assertNull(TokenLookup.tickerOf("\$"))
    }

    @Test fun remembersAMissForAMinute() {
        val fake = Fake { if (it == "SOL") jupiter else emptyList() }
        var clock = 0L
        val rates = TokenLookup(fake::search) { clock }
        assertEquals(111.77, rates.quote("\$sol")!!.usd, 0.0)
        assertNull(rates.quote("lol"))
        rates.quote("LOL")
        rates.quote("sol")
        // A miss asks twice (the ticker, then its tokenized share), then rests.
        assertEquals(3, fake.calls.size)
        clock = 61 * 1000L
        rates.quote("SOL")
        assertEquals(4, fake.calls.size)
    }

    @Test fun pricesAStockByItsVerifiedShareXStockFirst() {
        val q = TokenLookup.pickStock("AAPL", apple)!!
        assertEquals("AAPL", q.symbol); assertEquals("Apple xStock", q.name)
        assertEquals(340.3, q.usd, 0.0); assertTrue(q.stock); assertEquals(1.5, q.change24h!!, 0.0)
        assertEquals("Apple (Ondo Tokenized)", TokenLookup.pickStock("AAPL", apple.drop(1))?.name)
        assertNull(TokenLookup.pickStock("AAPL", apple.drop(2)))
        assertNull(TokenLookup.pickStock("SOL", listOf(JSONObject(jupiter[1].toString()).put("symbol", "SOLx"))))
    }

    @Test fun answersAaplAskingForTheShareWhenTheTickerSearchMisses() {
        val fake = Fake { when (it) { "AAPLx" -> apple.take(1); "AAPL" -> apple; else -> emptyList() } }
        val q = TokenLookup(fake::search) { 0L }.quote("\$aapl")!!
        assertEquals("AAPL", q.symbol); assertEquals(340.3, q.usd, 0.0); assertTrue(q.stock)
        assertEquals(1, fake.calls.size)
        val second = Fake { if (it == "TSLAx") listOf(share("XsDoVfTsla111111111111111111111111111111111", "TSLAx", "Tesla xStock", 371.43)) else emptyList() }
        assertEquals(371.43, TokenLookup(second::search) { 0L }.quote("TSLA")!!.usd, 0.0)
        assertEquals(listOf("TSLA", "TSLAx"), second.calls)
    }

    @Test fun pricesACompanyTypedByName() {
        val appleCoin = j("id" to "AppLeCoin11111111111111111111111111111111111", "symbol" to "APPLE", "name" to "Apple Coin",
            "isVerified" to true, "usdPrice" to 0.003, "tags" to tags("verified"))
        val pfizer = listOf(share("PFExPfizer1111111111111111111111111111111111", "PFEx", "Pfizer xStock", 26.48))
        val fake = Fake { when (it) { "AAPL" -> apple; "APPLE" -> listOf(appleCoin); "PFIZER" -> pfizer; else -> emptyList() } }
        val rates = TokenLookup(fake::search) { 0L }
        val a = rates.quote("\$apple")!!
        assertEquals("APPLE", a.symbol); assertEquals(340.3, a.usd, 0.0); assertTrue(a.stock)
        assertEquals(listOf("AAPL"), fake.calls)
        val p = rates.quote("\$pfizer")!!
        assertEquals("PFIZER", p.symbol); assertEquals(26.48, p.usd, 0.0); assertEquals("Pfizer xStock", p.name)
        assertNull(rates.quote("\$banana"))
    }

    @Test fun bitcoinReadsAsBtc() {
        val wbtc = j("id" to "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh", "symbol" to "WBTC", "name" to "Wrapped BTC",
            "isVerified" to true, "usdPrice" to 61000.0, "tags" to tags("strict", "verified"))
        val fake = Fake { if (it == "WBTC") listOf(wbtc) else emptyList() }
        val rates = TokenLookup(fake::search) { 0L }
        val q = rates.quote("\$bitcoin")!!
        assertEquals("BITCOIN", q.symbol); assertEquals("BTC", q.ticker); assertEquals(61000.0, q.usd, 0.0)
        assertEquals("BTC", rates.quote("\$btc")!!.ticker)
    }

    @Test fun findsTheCompanyForASlipOrHalfAName() {
        val applovin = share("XsPdAVBi8Zc1xvv53k4JcMrQaEDTgkGqKYeh7AYgPHV", "APPx", "AppLovin xStock", 649.83)
        val fake = Fake { when (it) { "APPL" -> listOf(apple[0], apple[1], applovin); "AAPL" -> apple; else -> emptyList() } }
        val rates = TokenLookup(fake::search) { 0L }
        val q = rates.quote("\$appl")!!
        assertEquals("APPL", q.symbol); assertEquals("AAPL", q.ticker); assertEquals(340.3, q.usd, 0.0); assertTrue(q.stock)
        val a = rates.quote("\$apple")!!
        assertEquals("APPLE", a.symbol); assertEquals("AAPL", a.ticker)
        assertEquals("APP", TokenLookup.pickStockByPrefix("APP", listOf(applovin))?.ticker)
        assertNull(TokenLookup(Fake { listOf(applovin) }::search) { 0L }.quote("\$tes"))
        assertNull(TokenLookup.pickStockByPrefix("APPL", listOf(JSONObject(apple[3].toString()).put("name", "Applecoin"))))
    }

    @Test fun pricesNvidiaNotAMemeCoinSolStaysSol() {
        val meme = j("id" to "9dwPiStDBwJJqC3QzMnjpJP7xohZbMVmHELFx3uy3KRq", "symbol" to "NVDA", "name" to "NVIDIA",
            "isVerified" to true, "usdPrice" to 0.00017, "tags" to tags("verified"))
        val nvdax = share("Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh", "NVDAx", "NVIDIA xStock", 224.52)
        val fake = Fake { when (it) { "NVDA" -> listOf(meme); "NVDAx" -> listOf(nvdax); "SOL" -> jupiter; else -> emptyList() } }
        val rates = TokenLookup(fake::search) { 0L }
        val n = rates.quote("\$nvda")!!
        assertEquals(224.52, n.usd, 0.0); assertTrue(n.stock)
        assertEquals(111.77, rates.quote("\$sol")!!.usd, 0.0)
    }

    @Test fun throwsWhenJupiterCannotBeAskedSoTheServerIsAsked() {
        val rates = TokenLookup(Fake { null }::search) { 0L }
        assertTrue(runCatching { rates.quote("\$sol") }.isFailure)
        assertTrue(runCatching { rates.tokenAt("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263") }.isFailure)
    }

    @Test fun tellsATokensAddressFromAWallets() {
        val bonk = j("id" to "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", "symbol" to "Bonk", "name" to "Bonk",
            "decimals" to 5, "usdPrice" to 0.0000036, "isVerified" to true)
        val fresh = j("id" to "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr", "symbol" to "POPCAT", "name" to "Popcat",
            "decimals" to 9, "isVerified" to false)
        val fake = Fake { q -> when { q.contains(bonk.getString("id")) -> listOf(bonk); q.contains(fresh.getString("id")) -> listOf(fresh); else -> emptyList() } }
        val rates = TokenLookup(fake::search) { 0L }
        assertEquals(TokenLookup.MintQuote(bonk.getString("id"), "Bonk", "Bonk", 5, 0.0000036, true), rates.tokenAt(bonk.getString("id")))
        // Too new for a price, and not verified: still a token, said plainly.
        assertEquals(TokenLookup.MintQuote(fresh.getString("id"), "POPCAT", "Popcat", 9, null, false), rates.tokenAt(fresh.getString("id")))
        val wallet = "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"
        assertNull(rates.tokenAt(wallet))
        rates.tokenAt(bonk.getString("id"))
        assertEquals(3, fake.calls.size)
        assertNull(rates.tokenAt("not an address"))
        assertTrue(TokenLookup.isAddress(wallet))
        assertTrue(!TokenLookup.isAddress("0OIl"))
    }
}
