package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** NEAR Intents trades read from plain words (docs/NEAR-SPEC.md): the twin
 *  of RunnerTests/TradeIntentTests.swift's NEAR Intents section, case for
 *  case. Uniswap, Jupiter and Flash read as they did. */
class NearIntentTest {

    private fun read(text: String): TradeIntent? = TradeIntent.parse(text)
    private fun must(text: String): TradeIntent = read(text) ?: throw AssertionError("no trade read from: $text")

    private val bech32 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
    private val tAddress = "t1Rv4exT7bqhZqi2j7xz8bUHDMxwosrjADU"
    private val implicit = "98793cd91a3f870fb126f66285808c7e094afcfc4eda8a970f6648cdf0dbd6de"

    /** The spec's first row: USDC on Base to SOL on Solana. */
    @Test fun aSwapFromBaseToSolanaGoesThroughNEARIntents() {
        val i = must("swap 20 usdc on base to sol")
        assertEquals(TradeIntent.Kind.SWAP, i.kind)
        assertTrue(i.isNear)
        assertEquals("20", i.amount)
        assertEquals("USDC", i.sell)
        assertEquals("SOL", i.buy)
        assertEquals("base", i.chainName)
        assertEquals("solana", i.buyChain)
        assertEquals("NEAR Intents", i.venue)
        assertEquals("Swap 20 USDC → SOL", i.title)
        assertEquals("Base → Solana · NEAR Intents", i.detail)
        assertEquals("near", i.query["venue"])
        assertEquals("swap", i.query["kind"])
        assertEquals("base", i.query["chain"])
        assertEquals("solana", i.query["buyChain"])
        assertEquals("20", i.query["amount"])
        assertNull(i.query["exact"])
        // The same said other ways.
        assertEquals(i, read("swap 20 usdc on base to sol on solana"))
        assertEquals(i, read("Swap 20 USDC from Base to SOL"))
        assertEquals("SOL", read("pls swap 20 usdc on base to solana")?.buy)
    }

    @Test fun aSwapFromSolanaToBase() {
        val i = must("swap 0.2 sol to usdc on base")
        assertTrue(i.isNear)
        assertEquals("SOL", i.sell)
        assertEquals("solana", i.chainName)
        assertEquals("USDC", i.buy)
        assertEquals("base", i.buyChain)
        assertEquals("Swap 0.2 SOL → USDC", i.title)
        assertEquals("Solana → Base · NEAR Intents", i.detail)
        assertEquals("arbitrum", read("swap 0.2 sol on solana to usdc on arbitrum")?.buyChain)
        assertEquals("ETH", read("swap 0.2 sol to eth on base")?.buy)
    }

    /** Bitcoin, NEAR and Zcash need someone to pay: an address typed after,
     *  or (NEAR) the account saved in the app. */
    @Test fun swapsToChainsOfTheirOwn() {
        val btc = must("swap 50 usdc on arbitrum to btc to $bech32")
        assertEquals("USDC", btc.sell)
        assertEquals("arbitrum", btc.chainName)
        assertEquals("BTC", btc.buy)
        assertEquals("bitcoin", btc.buyChain)
        assertEquals(bech32, btc.to)
        assertEquals("Arbitrum → Bitcoin · NEAR Intents", btc.detail)
        assertEquals(bech32, btc.query["to"])
        assertEquals("bitcoin", btc.query["buyChain"])

        val near = must("swap 20 usdc on base to near")
        assertEquals("NEAR", near.buy)
        assertEquals("near", near.buyChain)
        assertNull(near.to)
        assertEquals("Swap 20 USDC → NEAR", near.title)
        assertEquals("Base → NEAR · NEAR Intents", near.detail)
        assertEquals("alice.near", read("swap 20 usdc on base to near to alice.near")?.to)

        val zec = must("swap 20 usdc on base to zec")
        assertEquals("ZEC", zec.buy)
        assertEquals("zcash", zec.buyChain)
        assertEquals(tAddress, read("swap 20 usdc on base to zec to $tAddress")?.to)
        // Base pays when no chain is said and the other side has its own.
        assertEquals("base", read("swap 20 usdc to zec")?.chainName)
        // Native BTC said by its chain, or beside Solana.
        assertEquals("BTC", read("swap 20 usdc on base to btc on bitcoin")?.buy)
        assertEquals("bitcoin", read("swap 1 sol to btc")?.buyChain)
        val fromBTC = must("swap 0.01 btc on bitcoin to usdc on base")
        assertEquals("bitcoin", fromBTC.chainName)
        assertEquals("BTC", fromBTC.sell)
        assertEquals("base", fromBTC.buyChain)
        // Every chain only NEAR Intents reaches.
        for ((word, coin, chain) in listOf(Triple("ton", "TON", "ton"), Triple("tron", "TRX", "tron"), Triple("xrp", "XRP", "xrp"),
                Triple("doge", "DOGE", "dogecoin"), Triple("ltc", "LTC", "litecoin"), Triple("sui", "SUI", "sui"),
                Triple("aptos", "APT", "aptos"), Triple("xlm", "XLM", "stellar"), Triple("cardano", "ADA", "cardano"))) {
            val t = read("swap 20 usdc on base to $word")
            assertNotNull(word, t)
            assertEquals(word, coin, t!!.buy)
            assertEquals(word, chain, t.buyChain)
            assertEquals(word, "NEAR Intents", t.venue)
        }
    }

    @Test fun movingTheSameCoinAcrossChainsNEARIntentsJoins() {
        val i = must("move 50 usdc from base to solana")
        assertEquals(TradeIntent.Kind.SWAP, i.kind)
        assertTrue(i.isNear)
        assertEquals("USDC", i.sell)
        assertEquals("USDC", i.buy)
        assertEquals("base", i.chainName)
        assertEquals("solana", i.buyChain)
        assertEquals("Move 50 USDC to Solana", i.title)
        assertEquals("Base → Solana · NEAR Intents", i.detail)
        assertEquals("near", i.query["venue"])
        assertEquals("arbitrum", read("bridge 10 usdc from solana to arbitrum")?.buyChain)
        // Between EVM chains it's Flash's, as before.
        val flash = must("move 50 usdc from base to arbitrum")
        assertEquals(TradeIntent.Kind.BRIDGE, flash.kind)
        assertEquals("Flash", flash.venue)
        // A coin Solana doesn't have stays a Flash move, as it was.
        assertEquals(TradeIntent.Kind.BRIDGE, read("move 0.1 eth from base to solana")?.kind)
        // Flash's own words (the Definitive panel) read as they did.
        assertEquals(TradeIntent.Kind.BRIDGE, TradeIntent.parse("move 10 usdc from solana to base", near = false)?.kind)
    }

    /** Sends pay the recipient exactly (EXACT_OUTPUT), from USDC on Base
     *  unless the words say what pays. */
    @Test fun sendsToANEARAccount() {
        val i = must("send 5 usdc to alice.near")
        assertEquals(TradeIntent.Kind.SEND, i.kind)
        assertTrue(i.isNear)
        assertEquals("5", i.amount)
        assertEquals("USDC", i.buy)
        assertEquals("near", i.buyChain)
        assertEquals("USDC", i.sell)
        assertEquals("base", i.chainName)
        assertEquals("alice.near", i.to)
        assertEquals("NEAR Intents", i.venue)
        assertEquals("Send 5 USDC to alice.near", i.title)
        assertEquals("Base → NEAR · NEAR Intents", i.detail)
        assertEquals("near", i.query["venue"])
        assertEquals("out", i.query["exact"])
        assertEquals("send", i.query["kind"])
        assertEquals("alice.near", i.query["to"])
        assertEquals("USDC", i.query["buy"])
        assertEquals("near", i.query["buyChain"])
        assertEquals("USDC", i.query["sell"])
        assertEquals("base", i.query["chain"])
        assertTrue(TradeIntent.isName(i.to))

        val sol = must("pay bob.near 10 usdc with sol")
        assertEquals("bob.near", sol.to)
        assertEquals("10", sol.amount)
        assertEquals("USDC", sol.buy)
        assertEquals("SOL", sol.sell)
        assertEquals("solana", sol.chainName)
        assertEquals("Solana → NEAR · NEAR Intents", sol.detail)
        val arb = must("send 5 usdc to alice.near with usdc on arbitrum")
        assertEquals("USDC", arb.sell)
        assertEquals("arbitrum", arb.chainName)
        val fromSol = must("send 5 usdc to Alice.NEAR from solana")
        assertEquals("solana", fromSol.chainName)
        assertEquals("USDC", fromSol.sell)
        assertEquals("alice.near", fromSol.to)
        assertEquals("ETH", read("send 2 near to sub.alice.near with eth")?.sell)
        assertEquals("NEAR", read("send 2 near to sub.alice.near with eth")?.buy)
        val hex = must("send 3 usdt to $implicit")
        assertEquals("near", hex.buyChain)
        assertEquals(implicit, hex.to)
        assertEquals("Send 3 USDT to 98793c…d6de", hex.title)
        assertFalse(TradeIntent.isName(hex.to))
    }

    @Test fun sendsToBitcoinAndZcashAddresses() {
        val btc = must("send 0.001 btc to $bech32")
        assertEquals("BTC", btc.buy)
        assertEquals("bitcoin", btc.buyChain)
        assertEquals("USDC", btc.sell)
        assertEquals("base", btc.chainName)
        assertEquals("0.001", btc.amount)
        assertEquals("Send 0.001 BTC to bc1qar…5mdq", btc.title)
        assertEquals("out", btc.query["exact"])
        assertEquals(bech32, btc.query["to"])
        for (legacy in listOf("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy")) {
            val t = read("send 0.01 bitcoin to $legacy")
            assertNotNull(legacy, t)
            assertEquals(legacy, "bitcoin", t!!.buyChain)
            assertEquals(legacy, legacy, t.to)    // base58 keeps its case
        }
        val zec = must("send 1.5 zec to $tAddress with sol")
        assertEquals("ZEC", zec.buy)
        assertEquals("zcash", zec.buyChain)
        assertEquals("SOL", zec.sell)
        assertEquals("Solana → Zcash · NEAR Intents", zec.detail)
        assertNull(TradeIntent.phantomSend(zec.query + ("address" to tAddress)))
    }

    @Test fun nearTradesThatCantBeAreNotRead() {
        for (text in listOf("send 5 usdc to $bech32",          // Bitcoin carries only BTC
                "send 1 btc to alice.near",            // NEAR takes NEAR, USDC, USDT here
                "send 5 zec to $bech32",
                "send 2 near to alice.near with near", // that's a plain NEAR transfer
                "send usdc to alice.near",             // no amount
                "send 5 usdc to alice.nearby",
                "send 5 usdc to bc1qshort",
                "swap 50 usdc on arbitrum to btc to alice.near", // the address doesn't fit
                "swap 20 usdc to sol",                 // which USDC? not guessed beside Solana
                "swap 0.2 sol to usdc",
                "swap 1 near on base to usdc on solana",
                "swap 10 tsla on base to sol")) {
            assertNull(text, read(text))
        }
        assertNull(TradeIntent.nearRecipientChain("alice.eth"))
        assertNull(TradeIntent.nearRecipientChain("0x52908400098527886E0F7030069857D2E4169EE7"))
    }

    /** Everything Uniswap, Jupiter and Flash read stays theirs. */
    @Test fun oldTradesStayWhereTheyWere() {
        val uni = must("swap 50 usdc on base to eth on arbitrum")
        assertFalse(uni.isNear)
        assertEquals("Uniswap", uni.venue)
        assertEquals("Base → Arbitrum · Uniswap", uni.detail)
        assertNull(uni.query["venue"])
        assertEquals("Uniswap", read("swap 50 usdc on base to eth on polygon")?.venue)
        for ((text, venue) in listOf("swap 0.05 eth to usdc on base" to "Uniswap", "swap 10 usdc to usdt on solana" to "Jupiter",
                "swap 0.01 btc to usdc" to "Uniswap", "swap 20 usdc to btc" to "Uniswap",
                "buy \$50 of eth" to "Uniswap", "sell 0.1 sol if it drops below 100" to "Flash",
                "move 50 usdc from base to arbitrum" to "Flash",
                "send 20 usdc to vitalik.eth" to "MetaMask", "pay arpit.sol 5 usdc" to "Phantom")) {
            val t = read(text)
            assertNotNull(text, t)
            assertFalse(text, t!!.isNear)
            assertEquals(text, venue, t.venue)
            assertNull(text, t.query["venue"])
            assertNull(text, t.query["exact"])
        }
        assertEquals("WBTC", read("swap 0.01 btc to usdc")?.sell)
        assertEquals("WBTC", read("swap 20 usdc to btc")?.buy)
        // Words that were never a trade still aren't.
        for (text in listOf("I'm near the station", "send it near noon", "swap 1 sol to usdc on solana",
                "buy a ton of snacks", "send 5 usdc to arpit.eth on solana")) {
            assertNull(text, read(text))
        }
    }

    @Test fun theStripOffersNEARTrades() {
        val t = (Smart.chip("swap 20 usdc on base to sol", emptyList()) as? Smart.Chip.Trade)?.intent
            ?: throw AssertionError("no NEAR swap chip")
        val chip = Smart.Chip.Trade(t)
        assertEquals("NEAR Intents", Smart.key(chip))
        assertEquals("Swap 20 USDC → SOL · Base → Solana", Smart.display(chip))
        assertEquals("Swap", Smart.verb(chip))
        val send = (Smart.chip("send 5 usdc to alice.near", emptyList()) as? Smart.Chip.Trade)?.intent
            ?: throw AssertionError("no NEAR send chip")
        assertEquals("Send 5 USDC to alice.near · Base → NEAR", Smart.display(Smart.Chip.Trade(send)))
        assertEquals("Send", Smart.verb(Smart.Chip.Trade(send)))
        val move = (Smart.chip("move 50 usdc from base to solana", emptyList()) as? Smart.Chip.Trade)?.intent
            ?: throw AssertionError("no NEAR move chip")
        assertEquals("Move", Smart.verb(Smart.Chip.Trade(move)))
        // A legacy Bitcoin address looks like a Solana one; the words say which.
        val legacy = (Smart.chip("send 0.01 btc to 1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", emptyList()) as? Smart.Chip.Trade)?.intent
            ?: throw AssertionError("no Bitcoin send chip")
        assertEquals("bitcoin", legacy.buyChain)
        // Old chips read as they did.
        val uni = (Smart.chip("swap 0.05 eth to usdc on base", emptyList()) as? Smart.Chip.Trade)?.intent
            ?: throw AssertionError("no Uniswap chip")
        assertEquals("Swap 0.05 ETH → USDC · Base", Smart.display(Smart.Chip.Trade(uni)))
    }

    /** The strip's chip fits a NEAR route the same way (D108): never "…",
     *  and when it can't fit, the route goes whole. */
    @Test fun aNEARChipLosesItsRouteWholeNeverCut() {
        val value = Smart.display(Smart.Chip.Trade(must("swap 20 usdc on base to sol")))
        // One unit a character, at any size: room for the title only.
        val fit = ChipFit.fit(value, 15.0, "Swap 20 USDC → SOL".length.toDouble()) { t, _ -> t.length.toDouble() }
        assertEquals("Swap 20 USDC → SOL", fit.text)
        assertTrue(fit.fits)
        assertFalse(fit.text.contains("…"))
    }

    /** GET /names/resolve for a .near name: the account, or "No NEAR account". */
    @Test fun aNEARNameIsCheckedOnNEAR() {
        val found = JSONObject().put("ok", true).put("found", true).put("chain", "near").put("address", "alice.near").put("exists", true)
        assertEquals("alice.near", TradeIntent.recipient("alice.near", "near", true, found).first)
        val missing = JSONObject().put("ok", true).put("chain", "near").put("address", "nobody.near").put("exists", false)
        val none = TradeIntent.recipient("nobody.near", "near", true, missing)
        assertNull(none.first)
        assertEquals("No NEAR account named nobody.near", none.second)
        assertEquals("No NEAR account named nobody.near", TradeIntent.recipient("nobody.near", "near", false,
            JSONObject().put("ok", false).put("exists", false)).second)
        assertEquals("Couldn’t look up a.near", TradeIntent.recipient("a.near", "near", false, null).second)
    }

    /** The panel's chain pickers for a NEAR trade, and what a pick does. */
    @Test fun aNEARTradeIsEditedInThePanel() {
        val swap = must("swap 20 usdc on base to sol")
        assertTrue(TradeEdit.chains(swap).contains("bitcoin"))
        assertTrue(TradeEdit.chains(swap).contains("solana"))
        // To Bitcoin: what's bought becomes BTC.
        val toBTC = TradeEdit.pickChain("bitcoin", TradeEdit.Side.BUY, swap)
        assertEquals("BTC", toBTC.buy)
        assertEquals("bitcoin", toBTC.buyChain)
        assertTrue(toBTC.isNear)
        // Both sides on Base: Uniswap's swap there, no longer NEAR's.
        val same = TradeEdit.pickChain("base", TradeEdit.Side.BUY, swap)
        assertNull(same.buyChain)
        assertEquals("ETH", same.buy)
        assertFalse(same.isNear)
        assertEquals("Uniswap", same.venue)
        // Paying from Arbitrum keeps USDC.
        assertEquals("USDC", TradeEdit.pickChain("arbitrum", TradeEdit.Side.SELL, swap).sell)
        assertEquals("arbitrum", TradeEdit.pickChain("arbitrum", TradeEdit.Side.SELL, swap).chainName)
        // Flipped: SOL on Solana to USDC on Base.
        val back = TradeEdit.flip(swap)
        assertEquals("SOL", back.sell)
        assertEquals("solana", back.chainName)
        assertEquals("base", back.buyChain)
        assertTrue(back.isNear)
        // The trade passed in is never changed.
        assertEquals("solana", swap.buyChain)

        val send = must("send 0.001 btc to $bech32")
        assertEquals("BTC", TradeEdit.asset(send))
        assertEquals("Amount in BTC", TradeEdit.label(TradeField.AMOUNT, send))
        assertEquals(TradeEdit.NEAR_PAY_CHAINS, TradeEdit.chains(send))
        val paid = TradeEdit.pickChain("solana", TradeEdit.Side.SELL, send)
        assertEquals("solana", paid.chainName)
        assertEquals("USDC", paid.sell)
        assertEquals("BTC", paid.buy)
        assertEquals("bitcoin", paid.buyChain)
        assertEquals("0.002", TradeEdit.apply(TradeField.AMOUNT, "0.002", send).amount)
        assertNull(TradeEdit.problem(send))
        assertEquals(listOf("BTC"), TradeEdit.builtIn("bitcoin").map { it.symbol })
        assertEquals(listOf("NEAR", "USDC", "USDT"), TradeEdit.builtIn("near").map { it.symbol })
    }

    /** Private AI on NEAR AI Cloud: the app writes "near" or removes the
     *  key; the ETHGlobal build's Bool reads as off without losing the file. */
    @Test fun privateAIOnNEARIsReadFromTheSharedSettings() {
        val store = com.arpit.glyf.store.SettingsStore
        val on = JSONObject().put("privateAI", "near").put("nearRecent", org.json.JSONArray(listOf("alice.near", "0xab")))
        assertEquals("near", store.privateAIHeader(on))
        assertEquals(listOf("alice.near", "0xab"), store.nearRecent(on))
        assertNull(store.privateAIHeader(JSONObject()))
        assertEquals(emptyList<String>(), store.nearRecent(JSONObject()))
        for (legacy in listOf(true, false)) {
            val old = JSONObject().put("privateAI", legacy).put("haptics", false)
            assertNull("$legacy", store.privateAIHeader(old))
            assertFalse("the rest of the file still reads", old.optBoolean("haptics", true))
        }
        assertNull(store.privateAIHeader(JSONObject().put("privateAI", "0g")))
        assertNull(store.privateAIHeader(JSONObject().put("privateAI", JSONObject.NULL)))
        // Junk in the list is skipped; twenty at most go to Guard.
        val many = JSONObject().put("nearRecent", org.json.JSONArray((1..25).map { "a$it.near" } + listOf(7)))
        assertEquals(20, store.nearRecent(many).size)
        assertEquals(listOf("x.near"), store.nearRecent(JSONObject().put("nearRecent", org.json.JSONArray(listOf(1, "x.near", true)))))
    }

    /** Every call to Glyf's server carries the header while the switch is on. */
    @Test fun everyCallCarriesTheNEARHeaderWhileItIsOn() {
        fun conn() = java.net.URL("http://127.0.0.1:9/ai").openConnection() as java.net.HttpURLConnection
        val was = BackendClient.privateAI
        try {
            BackendClient.privateAI = "near"
            val on = conn().also { BackendClient.session(it) }
            assertEquals("near", on.getRequestProperty("X-Glyf-AI"))
            BackendClient.privateAI = null
            val off = conn().also { BackendClient.session(it) }
            assertNull(off.getRequestProperty("X-Glyf-AI"))
        } finally {
            BackendClient.privateAI = was
        }
    }
}
