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

    /** What POST /near/quote's answer shows on the panel. */
    @Test fun aNEARQuoteReads() {
        val answer = JSONObject("""{"ok": true, "dry": true, "venue": "NEAR Intents", "amountIn": "20", "amountInUsd": "19.99",
            "amountOut": "0.2438", "amountOutUsd": "19.88", "timeSeconds": 32,
            "guard": {"level": "warn", "checks": [{"id": "new-recipient", "level": "warn", "text": "First time paying this address"},
                {"id": "lookalike", "level": "block", "text": "Looks like 0xAb12…9fE0 you paid before, but it isn't"}]}}""")
        val q = NearQuote.read(true, answer)
        assertEquals(20.0, q.amountIn!!, 0.0)
        assertEquals(0.2438, q.amountOut!!, 0.0)
        assertEquals(19.99, q.inUsd!!, 0.0)
        assertEquals(19.88, q.outUsd!!, 0.0)
        assertEquals("~32 s", q.time)
        assertEquals("block", q.guardLevel)
        assertEquals("Looks like 0xAb12…9fE0 you paid before, but it isn't", q.guardText)
        assertEquals("lookalike", q.guardId)
        assertNull(q.error)
        val quiet = NearQuote.read(true, JSONObject("""{"ok": true, "amountOut": 5, "timeSeconds": 150, "guard": {"level": "ok", "checks": []}}"""))
        assertNull(quiet.guardLevel)
        assertEquals("~3 min", quiet.time)
        val small = NearQuote.read(false, JSONObject("""{"ok": false, "error": "Too small for NEAR Intents: at least $1"}"""))
        assertNull(small.amountOut)
        assertEquals("Too small for NEAR Intents: at least $1", small.error)
        assertEquals("No quote right now", NearQuote.read(false, null).error)
    }

    /** What the panel asks POST /near/quote: a dry preview, exact-out for a
     *  send, the recipient and the ones paid before for Guard. */
    @Test fun thePanelAsksForADryNEARQuote() {
        val swap = TradeQuote.nearBody(must("swap 20 usdc on base to sol"))!!
        assertEquals("USDC", swap.getString("sell"))
        assertEquals("base", swap.getString("sellChain"))
        assertEquals("SOL", swap.getString("buy"))
        assertEquals("solana", swap.getString("buyChain"))
        assertEquals("20", swap.getString("amount"))
        assertEquals("in", swap.getString("exact"))
        assertEquals(1, swap.getInt("slippage"))
        // Dry: never a refund address from the keyboard.
        assertFalse(swap.has("refundTo"))
        assertFalse(swap.has("recipient"))
        val recent = (1..25).map { "r$it.near" }
        val send = TradeQuote.nearBody(must("send 5 usdc to alice.near"), recent)!!
        assertEquals("out", send.getString("exact"))
        assertEquals("5", send.getString("amount"))
        assertEquals("USDC", send.getString("buy"))
        assertEquals("near", send.getString("buyChain"))
        assertEquals("alice.near", send.getString("recipient"))
        assertEquals(20, send.getJSONArray("recent").length())
        assertEquals("r1.near", send.getJSONArray("recent").getString(0))
        assertFalse(send.has("refundTo"))
        // Nothing to ask: no amount, or not NEAR's.
        assertNull(TradeQuote.nearBody(must("send 5 usdc to alice.near").copy(amount = null)))
        assertNull(TradeQuote.nearBody(must("swap 0.05 eth to usdc on base")))
        assertTrue(TradeQuote.quotes(must("send 5 usdc to alice.near")))
        assertFalse(TradeQuote.quotes(must("send 5 usdc to vitalik.eth")))
    }

    private fun quote(guardId: String?, level: String?, text: String? = null, amountIn: Double = 5.02) =
        NearQuote(amountIn = amountIn, amountOut = 5.0, inUsd = 5.02, outUsd = 5.0, seconds = 35,
            guardLevel = level, guardText = text, guardId = guardId)

    /** Guard's block wins: the button says what to fix and stays off; a
     *  lookalike offers a red "Send anyway" that hands off with anyway=1;
     *  a warning only asks for a look. */
    @Test fun guardDecidesTheButton() {
        val send = must("send 5 usdc to alice.near")
        val wallet = "0xabc"
        val missing = TradeQuote.go(send, wallet, false, TradeQuote.Quote(5.0, 5.02, 5.0), 50.0,
            resolveProblem = "No NEAR account named alice.near")
        assertEquals(TradeQuote.Go("Check the name", blocked = true, connect = false), missing)
        assertEquals(TradeQuote.Alert("No NEAR account named alice.near", true, "Check the name"),
            TradeQuote.alert(send, null, "No NEAR account named alice.near"))
        val btc = must("send 0.001 btc to bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
        assertEquals("Check the address", TradeQuote.alert(btc, null, "Bad")?.fix)
        val mismatch = quote("chain-mismatch", "block", "That's an EVM address, not Solana")
        assertEquals("Check the address", TradeQuote.go(btc, wallet, false, TradeQuote.Quote(0.001), 50.0, btc.to, null, mismatch).title)
        assertEquals("Check the name", TradeQuote.alert(send, quote("no-account", "block", "No NEAR account bob.near"), null)?.fix)
        // Even without a wallet, a block says what to fix first.
        assertEquals("Check the name", TradeQuote.go(send, null, false, null, null, resolveProblem = "No NEAR account named alice.near").title)

        val look = quote("lookalike", "block", "Looks like 0xAb12…9fE0 you paid before, but it isn't")
        val anyway = TradeQuote.go(send, wallet, false, TradeQuote.Quote(5.0, 5.02, 5.0), 50.0, "alice.near", null, look)
        assertEquals(TradeQuote.Go("Send anyway", blocked = false, connect = false, red = true), anyway)
        val handed = TradeQuote.handOff(send, "alice.near", anyway = anyway.red)
        assertEquals("1", handed["anyway"])
        assertEquals("alice.near", handed["address"])
        assertEquals("near", handed["venue"])
        assertEquals("out", handed["exact"])
        assertNull(TradeQuote.handOff(send, "alice.near")["anyway"])
        // Still asking: "Send anyway", off until the quote is in.
        assertTrue(TradeQuote.go(send, wallet, true, null, 50.0, "alice.near", null, look).blocked)

        val warn = quote("new-recipient", "warn", "First time paying this address")
        assertEquals(TradeQuote.Alert("First time paying this address", false, null), TradeQuote.alert(send, warn, null))
        val live = TradeQuote.go(send, wallet, false, TradeQuote.Quote(5.0, 5.02, 5.0), 50.0, "alice.near", null, warn)
        assertEquals(TradeQuote.Go("Send 5 USDC", blocked = false, connect = false), live)
        assertEquals("Send 0.001 BTC", TradeQuote.go(btc, wallet, false, TradeQuote.Quote(0.001), 50.0, btc.to, null, quote(null, null)).title)
        // A level with no words still says something.
        assertEquals("Take a look first", TradeQuote.alert(send, quote(null, "warn"), null)?.text)
        // Uniswap's trades have no alert.
        assertNull(TradeQuote.alert(must("swap 0.05 eth to usdc on base"), warn, null))
    }

    /** Short of money, a NEAR trade's button says what's held; a chain Glyf
     *  can't sign on needs no wallet. */
    @Test fun theButtonSaysWhatsHeld() {
        val send = must("send 5 usdc to alice.near")
        val q = TradeQuote.Quote(5.0, 5.02, 5.0)
        assertEquals("You have 2.10 USDC", TradeQuote.go(send, "0xabc", false, q, 2.1, "alice.near", null, quote(null, null)).title)
        assertTrue(TradeQuote.go(send, "0xabc", false, q, 2.1, "alice.near", null, quote(null, null)).blocked)
        assertEquals("No USDC on Base", TradeQuote.go(send, "0xabc", false, q, 0.0, "alice.near", null, quote(null, null)).title)
        val swap = must("swap 0.5 eth on base to sol")
        assertEquals("You have 0.25 ETH", TradeQuote.haveText(swap, 0.25))
        assertEquals("Not enough ETH", TradeQuote.haveText(swap, null))
        // Uniswap says it as it always did.
        assertEquals("Not enough USDC", TradeQuote.go(must("swap 10 usdc to eth"), "0xabc", false, TradeQuote.Quote(0.003, 10.0, 9.98), 5.0).title)
        // Paid from Bitcoin: no wallet to connect, the app shows the deposit address.
        val fromBTC = must("swap 0.01 btc on bitcoin to usdc on base")
        val go = TradeQuote.go(fromBTC, null, false, TradeQuote.Quote(600.0, 600.0, 599.0), null)
        assertFalse(go.connect)
        assertEquals("Swap ≈ $600", go.title)
        assertEquals("Connect MetaMask", TradeQuote.go(must("swap 20 usdc on base to sol"), null, false, null, null).title)
        assertEquals("Connect Phantom", TradeQuote.go(must("swap 0.2 sol to usdc on base"), "", false, null, null).title)
    }

    /** The strip names a NEAR panel with who carries it, under NEAR's N. */
    @Test fun theHeaderSaysViaNEARIntents() {
        assertEquals("Swap via NEAR Intents", TradeQuote.headerTitle(must("swap 20 usdc on base to sol")))
        assertEquals("Move via NEAR Intents", TradeQuote.headerTitle(must("move 50 usdc from base to solana")))
        assertEquals("Send via NEAR Intents", TradeQuote.headerTitle(must("send 5 usdc to alice.near")))
        assertEquals("sponsor:near", TradeQuote.headerIcon(must("send 5 usdc to alice.near")))
        assertEquals(SponsorMenu.Sponsor.NEAR, SponsorMenu.Sponsor.of(TradeQuote.headerIcon(must("swap 20 usdc on base to sol"))))
        // Everything else keeps its name and mark.
        assertEquals("Swap", TradeQuote.headerTitle(must("swap 0.05 eth to usdc on base")))
        assertEquals("Send", TradeQuote.headerTitle(must("send 5 usdc to vitalik.eth")))
        assertEquals("trend", TradeQuote.headerIcon(must("swap 0.05 eth to usdc on base")))
    }

    /** A NEAR send's rows: To, You pay (bold, tap for another chain) and
     *  Arrives, whose time moves to the card when an alert takes the room. */
    @Test fun aNEARSendsRows() {
        val send = must("send 5 usdc to alice.near")
        val rows = TradeQuote.nearSendRows(send, quote(null, null), false, "alice.near", null)
        assertEquals(listOf("to", "pay", "arrives"), rows.map { it.id })
        assertEquals(TradeQuote.Row("to", "To", "alice.near", check = true), rows[0])
        assertEquals(TradeQuote.Row("pay", "You pay", "≈ 5.02 USDC · Base", tap = true, bold = true), rows[1])
        assertEquals(TradeQuote.Row("arrives", "Arrives", "~35 s"), rows[2])
        val asking = TradeQuote.nearSendRows(send, null, true, null, null)
        assertEquals("… · Base", asking[1].value)
        assertEquals("…", asking[2].value)
        assertFalse(asking[0].check)
        val blocked = TradeQuote.nearSendRows(send, null, false, null, "No NEAR account named alice.near")
        assertEquals(listOf("to", "pay"), blocked.map { it.id })
        assertTrue(blocked[0].red)
        assertFalse(blocked[0].check)
        val btc = TradeQuote.nearSendRows(must("send 0.001 btc to bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"),
            quote(null, null, amountIn = 61.2), false, "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", null)
        assertEquals("bc1q…5mdq", btc[0].value)
        assertFalse(btc[0].check)
        assertEquals("≈ 61.2 USDC · Base", btc[1].value)
    }

    /** A row's value shrinks from 15 to 11, then takes two lines; never "…". */
    @Test fun rowValuesFitWithoutAnEllipsis() {
        val w: (String, Double) -> Double = { t, size -> t.length * size / 2 }
        assertEquals(15.0 to 1, TradeQuote.rowFit("alice.near", 100.0, w))
        assertEquals(12.5 to 1, TradeQuote.rowFit("x".repeat(16), 100.0, w))
        val long = "nobody-glyf-zz9-and-more.near"
        val (size, lines) = TradeQuote.rowFit(long, 100.0, w)
        assertEquals(2, lines)
        assertTrue(size in 11.0..15.0)
        assertEquals(11.0 to 2, TradeQuote.rowFit("x".repeat(400), 100.0, w))
    }
}
