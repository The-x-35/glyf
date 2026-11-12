package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** NEAR Intents Earn, pay links and the group pot on the Android keyboard:
 *  the twins of TradeIntentTests.swift's Earn tests and AIActionTests.swift's
 *  NEAR tool, pay link and pot tests, case for case. */
class NearEarnPotTest {

    private fun read(text: String) = TradeIntent.parse(text) ?: throw AssertionError(text)
    private fun action(tool: String, params: Map<String, Any>, label: String = "x"): AIAction? =
        AIAction.from(JSONObject().put("tool", tool).put("label", label).put("params", JSONObject(params)))

    // MARK: Earn phrases (docs/NEAR-SPEC.md, Phrases)

    @Test fun earnPhrasesAreReadOnThePhone() {
        val fifty = read("put $50 to work")
        assertEquals(TradeIntent.Kind.EARN, fifty.kind)
        assertFalse(fifty.earnOut)
        assertEquals("50", fifty.amount)
        assertEquals("USDC", fifty.sell)
        assertEquals("base", fifty.chainName)
        assertEquals("gtusdcp", fifty.earnVault)
        assertEquals("Morpho", fifty.earnProtocol)
        assertEquals("NEAR Intents", fifty.venue)
        assertEquals("Put 50 USDC to work", fifty.title)
        for (t in listOf("put 50 usdc to work", "earn on 50 usdc", "earn yield on $50", "park 50 usdc", "park $50 in earn",
                "sounds good. put $50 to work", "Put 50 bucks to work")) {
            val i = TradeIntent.parse(t)
            assertEquals(t, TradeIntent.Kind.EARN, i?.kind)
            assertEquals(t, "50", i?.amount)
            assertEquals(t, "USDC", i?.sell)
            assertEquals(t, false, i?.earnOut)
        }
        val sol = read("put 0.5 sol to work")
        assertEquals("SOL", sol.sell)
        assertEquals("solana", sol.chainName)
        assertEquals("kamino-sol", sol.earnVault)
        assertEquals("Kamino", sol.earnProtocol)
        val stake = read("stake .5 sol in a vault")
        assertEquals("0.5", stake.amount)
        assertEquals("SOL", stake.sell)
        val fromSol = read("put 50 usdc on solana to work")
        assertEquals("solana", fromSol.chainName)
        assertEquals("base", fromSol.earnVaultChain)
        assertEquals("base", TradeIntent.parse("park 50 usdc on base")?.chainName)
    }

    @Test fun takingItOutOfEarn() {
        val all = read("take my usdc out of earn")
        assertEquals(TradeIntent.Kind.EARN, all.kind)
        assertTrue(all.earnOut)
        assertNull(all.amount)
        assertEquals("Take your USDC out of Earn", all.title)
        assertEquals(mapOf("venue" to "near", "kind" to "earn", "direction" to "out", "coin" to "USDC", "chain" to "base", "all" to "1"),
            all.query)
        val solAll = read("take my sol out of earn")
        assertEquals("SOL", solAll.sell)
        assertEquals("solana", solAll.chainName)
        val twenty = read("take 20 usdc out of earn")
        assertEquals("20", twenty.amount)
        assertEquals("Take 20 USDC out of Earn", twenty.title)
        assertNull(twenty.query["all"])
        assertEquals("20", TradeIntent.parse("withdraw $20 from earn")?.amount)
        val toSol = read("take 20 usdc out of earn to solana")
        assertEquals("solana", toSol.chainName)
        assertEquals("solana", toSol.query["chain"])
        assertEquals("out", toSol.query["direction"])
    }

    @Test fun wordsThatAreNotEarnStayWords() {
        for (t in listOf("take it out", "put the kids to work", "park the car", "pay the caterer $120",
                "put 50 doge to work", "earn on 5 eth", "I need to get to work")) {
            assertNotEquals(t, TradeIntent.Kind.EARN, TradeIntent.parse(t)?.kind)
        }
        assertNull(TradeIntent.parse("put $50 to work", near = false))
    }

    @Test fun theEarnChipAndItsHandOff() {
        val chip = Smart.chip("put $50 to work", emptyList()) as Smart.Chip.Trade
        assertEquals("NEAR Intents", Smart.key(chip))
        assertEquals("Put 50 USDC to work · Morpho", Smart.display(chip))
        assertEquals("Earn", Smart.verb(chip))
        assertEquals("Morpho · NEAR Intents", chip.intent.detail)
        assertEquals(mapOf("venue" to "near", "kind" to "earn", "direction" to "in", "coin" to "USDC", "chain" to "base", "amount" to "50"),
            chip.intent.query)
        val out = Smart.chip("take my sol out of earn", emptyList()) as Smart.Chip.Trade
        assertEquals("Take out", Smart.verb(out))
        assertEquals("Take your SOL out of Earn · Kamino", Smart.display(out))
        val taler = TradeIntent.earn("USDC", "10", false, null, "taler-usdc")!!
        assertEquals("ethereum", taler.chainName)
        assertEquals("taler-usdc", taler.query["vault"])
        assertEquals("Enter an amount", TradeEdit.problem(taler.copy(amount = null)))
        assertNull(TradeIntent.earn("SOL", "1", false, null, "gtusdcp"))
        assertNull(TradeIntent.earn("DOGE", "1", false, null))
        assertNull(TradeEdit.problem(read("take my usdc out of earn")))
        assertEquals(listOf("base"), TradeEdit.chains(read("put $50 to work")))
        // The panel's preview body, and none for everything out.
        val body = TradeQuote.earnBody(read("put $50 to work"))!!
        assertEquals("50", body.getString("amount"))
        assertEquals("in", body.getString("direction"))
        assertEquals("base", body.getString("chain"))
        assertNull(TradeQuote.earnBody(read("take my usdc out of earn")))
        assertEquals("Earn via NEAR Intents", TradeQuote.headerTitle(read("put $50 to work")))
        assertEquals("Take out of Earn via NEAR Intents", TradeQuote.headerTitle(read("take my usdc out of earn")))
    }

    /** Earn needs the wallet the coins leave and the one the shares land in. */
    @Test fun earnNeedsBothItsWallets() {
        val fromSol = read("put 50 usdc on solana to work")
        assertEquals("MetaMask", TradeIntent.missingWallet(fromSol, null, "7xKX", null))
        assertEquals("Phantom", TradeIntent.missingWallet(fromSol, "0xab", null, null))
        assertNull(TradeIntent.missingWallet(fromSol, "0xab", "7xKX", null))
        assertNull(TradeIntent.missingWallet(read("put $50 to work"), "0xab", null, null))
        val go = TradeQuote.earnGo(fromSol, TradeIntent.missingWallet(fromSol, null, "7xKX", null), false, null, null)
        assertEquals("Connect MetaMask", go.title)
        assertTrue(go.connect)
        assertEquals("Asking NEAR Intents", TradeQuote.earnGo(fromSol, null, true, null, null).title)
        assertEquals("Take out all USDC", TradeQuote.earnTitle(read("take my usdc out of earn")))
    }

    @Test fun anEarnQuoteReads() {
        val live = JSONObject().put("ok", true).put("dry", true).put("amountInUsd", "49.98").put("amountOutUsd", "49.75")
            .put("timeSeconds", 52).put("kind", "earn").put("direction", "in")
            .put("vault", JSONObject().put("id", "gtusdcp").put("name", "Gauntlet USDC Prime").put("protocol", "Morpho").put("apy", 4.5))
            .put("words", "≈ $49.75 in Gauntlet USDC Prime at 4.5% APY")
        val q = EarnQuote.of(true, live)
        assertEquals("≈ $49.75 in Gauntlet USDC Prime at 4.5% APY", q.words)
        assertEquals("Morpho · 4.5% APY", q.vaultLine("x"))
        assertEquals("~52 s", q.time)
        assertNull(q.error)
        val none = EarnQuote.of(true, JSONObject().put("ok", true)
            .put("vault", JSONObject().put("name", "Taler USDC").put("protocol", "Taler").put("apy", JSONObject.NULL)))
        assertEquals("APY n/a", none.apyText)
        assertEquals("Earn takes USDC or SOL, not DOGE",
            EarnQuote.of(false, JSONObject().put("ok", false).put("error", "Earn takes USDC or SOL, not DOGE")).error)
        assertEquals("No quote right now", EarnQuote.of(false, null).error)
        val list = JSONObject().put("ok", true).put("vaults", JSONArray()
            .put(JSONObject().put("id", "gtusdcp").put("name", "Gauntlet USDC Prime").put("protocol", "Morpho").put("apy", 4.5))
            .put(JSONObject().put("id", "kamino-sol").put("name", "Kamino SOL Balanced").put("protocol", "Kamino").put("apy", 4.24)))
        val kamino = EarnQuote.vault("kamino-sol", list)
        assertEquals("Kamino SOL Balanced", kamino.vaultName)
        assertEquals("4.24% APY", kamino.apyText)
        assertEquals("Yield isn't guaranteed; NEAR Intents doesn't run the vault", EarnQuote.NOTICE)
        val rows = TradeQuote.earnRows(read("take my usdc out of earn"), kamino.copy(vaultName = "Gauntlet USDC Prime"), false)
        assertEquals(listOf("All your USDC back on Base from Gauntlet USDC Prime", "Kamino · 4.24% APY"), rows.map { it.value })
        assertEquals(listOf("You get", "Vault", "Arrives"), TradeQuote.earnRows(read("put $50 to work"), q, false).map { it.label })
    }

    @Test fun coinsHaveTheirOwnLogos() {
        for (s in listOf("BTC", "ZEC", "NEAR", "SOL", "USDC", "ETH")) assertNotNull(s, TradeIntent.coinLogos[s])
        assertNull(TradeIntent.coinLogos["PEPE"])
    }

    // MARK: NEAR Intents' tools (server lib/actions.ts, near: true)

    @Test fun nearSwapAndSendOpenTheNearPanelThroughTheWords() {
        val swap = action("near.swap", mapOf("sell" to "USDC", "buy" to "SOL", "amount" to "20", "sellChain" to "base"))!!
        val t = (swap.chip as Smart.Chip.Trade).intent
        assertTrue(t.isNear)
        assertEquals("20", t.amount)
        assertEquals("base", t.chainName)
        assertEquals("solana", t.buyChain)
        assertEquals(TradeIntent.parse("swap 20 usdc on base to sol"), t)
        val btc = action("near.swap", mapOf("sell" to "USDC", "buy" to "BTC", "amount" to 50))!!.trade!!
        assertEquals("bitcoin", btc.buyChain)
        assertEquals("BTC", btc.buy)
        assertEquals("base", btc.chainName)
        val bare = action("near.swap", mapOf("sell" to "SOL", "buy" to "USDC", "buyChain" to "base"))!!.trade!!
        assertNull(bare.amount)
        assertEquals("Swap SOL → USDC", bare.title)
        val move = action("near.swap", mapOf("sell" to "USDC", "buy" to "USDC", "amount" to 50, "buyChain" to "solana"))!!.trade!!
        assertEquals("Move 50 USDC to Solana", move.title)
        assertNull(action("near.swap", mapOf("sell" to "USDC", "buy" to "ETH", "amount" to 5, "sellChain" to "base", "buyChain" to "arbitrum")))

        val send = action("near.send", mapOf("to" to "alice.near", "amount" to "5", "coin" to "USDC"))!!.trade!!
        assertEquals(TradeIntent.Kind.SEND, send.kind)
        assertEquals("alice.near", send.to)
        assertEquals("near", send.buyChain)
        assertEquals("out", send.query["exact"])
        val withSol = action("near.send", mapOf("to" to "bob.near", "amount" to 10, "coin" to "USDC", "with" to "SOL"))!!.trade!!
        assertEquals("SOL", withSol.sell)
        assertEquals("solana", withSol.chainName)
        val arb = action("near.send", mapOf("to" to "bob.near", "amount" to 10, "coin" to "USDC", "with" to "USDC", "withChain" to "arbitrum"))!!.trade!!
        assertEquals("arbitrum", arb.chainName)
        val fromSol = action("near.send", mapOf("to" to "bob.near", "amount" to 10, "withChain" to "solana"))!!.trade!!
        assertEquals("solana", fromSol.chainName)
        assertEquals("USDC", fromSol.sell)
    }

    @Test fun nearEarnOpensEarnMode() {
        val fifty = action("near.earn", mapOf("amount" to "50", "coin" to "USDC"))!!.trade!!
        assertEquals(TradeIntent.Kind.EARN, fifty.kind)
        assertEquals(TradeIntent.parse("put $50 to work"), fifty)
        assertEquals("solana", action("near.earn", mapOf("amount" to 0.5, "coin" to "SOL"))!!.trade!!.chainName)
        val out = action("near.earn", mapOf("coin" to "USDC", "out" to true))!!.trade!!
        assertTrue(out.earnOut)
        assertNull(out.amount)
        assertEquals("1", out.query["all"])
        val twenty = action("near.earn", mapOf("coin" to "USDC", "amount" to 20, "out" to true, "chain" to "solana"))!!.trade!!
        assertEquals("20", twenty.amount)
        assertEquals("solana", twenty.chainName)
        val bare = action("near.earn", mapOf("coin" to "USDC"))!!.trade!!
        assertNull(bare.amount)
        assertFalse(bare.earnOut)
        assertEquals("Put USDC to work", bare.title)
    }

    @Test fun nearRequestAndThePotAreChipsWithTheirParams() {
        val req = action("near.request", mapOf("amount" to "90", "count" to 4, "us" to true, "note" to "dinner"),
            label = "Request $22.50 each · NEAR Intents")!!
        val chip = req.chip as Smart.Chip.Action
        assertEquals("Request $22.50 each · NEAR Intents", chip.label)
        assertEquals("near:request", chip.intent)
        assertEquals("Request", Smart.verb(chip))
        assertEquals(PayAsk("90", count = 4, us = true, note = "dinner"), PayAsk.of(NearPay.params(chip.query)))
        assertNull(action("near.request", mapOf("note" to "dinner")))

        val pot = action("near.pot", mapOf("pot" to "trip"), label = "See the trip pot · Sputnik DAO")!!.chip as Smart.Chip.Action
        assertEquals("near:pot", pot.intent)
        assertEquals("trip", PotAsk.of(NearPay.params(pot.query), false)?.pot)
        assertEquals("See", Smart.verb(pot))
        val pay = action("near.pot.pay", mapOf("to" to "the caterer", "amount" to "120", "coin" to "USDC"),
            label = "Propose $120 to caterer from the pot · Sputnik DAO")!!.chip as Smart.Chip.Action
        assertEquals("near:pot.pay", pay.intent)
        val payAsk = PotAsk.of(NearPay.params(pay.query), true)!!
        assertEquals("the caterer", payAsk.to)
        assertEquals("120", payAsk.amount)
        assertEquals("Propose", Smart.verb(pay))
        assertNull(action("near.pot.pay", mapOf("amount" to "120")))
    }

    // MARK: pay links (NearPay.kt)

    @Test fun theRequesterIsPaidInTheirOwnWallet() {
        fun r(chain: String?, evm: String?, sol: String?, near: String?) =
            PayAsk.receiver(chain, evm, sol, near)?.let { "${it.first}@${it.second}" }
        assertEquals("7xKX@solana", r("solana", "0xab", "7xKX", "me.near"))
        assertEquals("0xab@arbitrum", r("arbitrum", "0xab", "7xKX", null))
        assertEquals("me.near@near", r("near", "0xab", null, "me.near"))
        assertEquals("0xab@base", r(null, "0xab", "7xKX", "me.near"))
        assertEquals("trip.sputnik-dao.near@near", r(null, null, "7xKX", "trip.sputnik-dao.near"))
        assertNull(r("solana", "0xab", null, null))
        assertNull(r(null, null, "7xKX", null))
        assertEquals("Add a wallet in Glyf to get paid", PayAsk.NO_WALLET)
        val body = PayAsk("90", count = 4, us = true, note = "dinner").body("0xab", "base")
        assertEquals("90", body.getString("amount"))
        assertEquals(4, body.getInt("count"))
        assertTrue(body.getBoolean("us"))
        assertEquals("dinner", body.getString("note"))
        assertEquals("0xab", body.getString("to"))
        assertEquals("base", body.getString("chain"))
        assertFalse(body.has("each"))
        val each = PayAsk.of(mapOf("amount" to "22.5", "each" to "true", "count" to "4", "chain" to "solana"))!!
        assertTrue(each.body("7xKX", "solana").getBoolean("each"))
    }

    @Test fun aBillSplitInDollarsCanBeRequested() {
        val c = Smart.billMath("dinner was $90 for 4 of us")!!
        assertEquals(listOf("$22.50 each"), c.results)
        assertEquals(PayAsk("90", count = 4, us = true, note = "dinner"), c.request)
        val chip = Smart.Chip.Convert(c)
        assertEquals("Insert", Smart.verb(chip))
        assertEquals(PayAsk("1200", count = 6, note = "cabin"), Smart.billMath("the cabin is $1,200 for 6 people")?.request)
        assertEquals("cab", Smart.billMath("split the cab $60 3 ways")?.request?.note)
        assertNull(Smart.billMath("split the bill $60 3 ways")?.request?.note)
        assertEquals(false, Smart.billMath("split $90 between 4 people")?.request?.us)
        assertNull(Smart.billMath("split ₹900 between 4 people")!!.request)
        assertNull(Smart.verb(Smart.Chip.Convert(Smart.billMath("split ₹900 between 4 people")!!)))
    }

    // MARK: the group pot

    @Test fun potPhrasesAreReadOnThePhone() {
        assertEquals(PotAsk(false, pot = "trip"), PotAsk.parse("how much is in the trip pot"))
        assertEquals(PotAsk(false), PotAsk.parse("what's in the pot?"))
        assertEquals(PotAsk(false, pot = "trip"), PotAsk.parse("check the trip pot"))
        assertEquals(PotAsk(false), PotAsk.parse("pot balance"))
        assertEquals(PotAsk(false, dao = "build.sputnik-dao.near"), PotAsk.parse("how much is in build.sputnik-dao.near"))
        assertEquals(PotAsk(true, to = "the caterer", amount = "120", coin = "USDC"), PotAsk.parse("pay the caterer $120 from the pot"))
        assertEquals(PotAsk(true, pot = "trip", to = "caterer.near", amount = "120", coin = "USDC", note = "catering"),
            PotAsk.parse("pay caterer.near 120 usdc from the trip pot for catering"))
        assertEquals(PotAsk(true, to = "bob.near", amount = "5", coin = "NEAR"), PotAsk.parse("send bob.near 5 near out of the pot"))
        for (t in listOf("pay the caterer $120", "the pot is on the stove", "take it out")) assertNull(t, PotAsk.parse(t))
        val look = Smart.chip("how much is in the trip pot", emptyList()) as Smart.Chip.Action
        assertEquals("near:pot", look.intent)
        assertEquals("See the trip pot · Sputnik DAO", look.label)
        val pay = Smart.chip("pay the caterer $120 from the pot", emptyList()) as Smart.Chip.Action
        assertEquals("near:pot.pay", pay.intent)
        assertEquals("Propose $120 to caterer from the pot · Sputnik DAO", pay.label)
        assertEquals("Propose 5 NEAR to bob.near from the pot · Sputnik DAO",
            PotAsk(true, to = "bob.near", amount = "5", coin = "NEAR").label)
    }

    @Test fun whichPot() {
        val trip = PotAsk(false, pot = "trip")
        assertEquals("lisbon.sputnik-dao.near", trip.daoAccount("lisbon.sputnik-dao.near", null))
        assertEquals("club.sputnik-dao.near", trip.daoAccount(null, "club.sputnik-dao.near"))
        assertEquals("trip.sputnik-dao.near", trip.daoAccount(null, "me.near"))
        assertEquals("build.sputnik-dao.near", PotAsk(false, dao = "build.sputnik-dao.near").daoAccount("x.sputnik-dao.near", null))
        assertNull(PotAsk(false).daoAccount(null, "me.near"))
        assertEquals("Add your pot in Glyf", PotAsk.NO_POT)
        assertTrue(PotAsk.isNEARAccount("caterer.near"))
        assertFalse(PotAsk.isNEARAccount("the caterer"))
    }

    @Test fun thePotCardReads() {
        val pot = JSONObject().put("ok", true).put("dao", "trip.sputnik-dao.near")
            .put("text", "The trip pot holds 42.5 NEAR · 140.5 USDC. 4 members, payouts need 2 of 3. 2 proposals open")
            .put("links", JSONObject().put("trezu", "https://trezu.app/trip.sputnik-dao.near/dashboard"))
            .put("proposals", JSONArray()
                .put(JSONObject().put("id", 5).put("kind", "Transfer").put("description", "Caterer").put("amount", "12.5")
                    .put("coin", "NEAR").put("receiver", "caterer.near").put("status", "InProgress").put("approvalsNeeded", 1)
                    .put("url", "https://trezu.app/trip.sputnik-dao.near/requests/5"))
                .put(JSONObject().put("id", 4).put("kind", "AddMemberToRole").put("description", "Add dee\nPlease")
                    .put("amount", JSONObject.NULL).put("status", "InProgress").put("approvalsNeeded", 2)
                    .put("url", "https://trezu.app/trip.sputnik-dao.near/requests/4"))
                .put(JSONObject().put("id", 3).put("kind", "Transfer").put("amount", "1").put("coin", "USDC")
                    .put("receiver", "x.near").put("status", "Approved")))
        val v = PotView.of(true, pot)
        assertEquals("The trip pot holds 42.5 NEAR · 140.5 USDC. 4 members, payouts need 2 of 3. 2 proposals open", v.text)
        assertEquals(listOf("#5 12.5 NEAR to caterer.near · 1 more approval", "#4 Add dee · 2 more approvals"), v.open.map { it.line })
        assertEquals("https://trezu.app/trip.sputnik-dao.near/requests/5", v.open.first().url)
        assertEquals("No Sputnik DAO nope.sputnik-dao.near",
            PotView.of(false, JSONObject().put("ok", false).put("error", "No Sputnik DAO nope.sputnik-dao.near")).error)

        val link = JSONObject().put("ok", true)
            .put("url", "https://trezu.app/trip.sputnik-dao.near/payments?address=caterer.near&token=usdc")
            .put("fill", JSONObject().put("amount", "120").put("coin", "USDC").put("note", "catering"))
            .put("text", "Proposing 120 USDC to caterer.near from the trip pot for catering. Vote: https://trezu.app/trip.sputnik-dao.near/requests")
            .put("bond", "0.1").put("proposers", "everyone").put("threshold", JSONObject().put("words", "2 of 3"))
        val p = PotProposal.of(true, link, "caterer.near", null)
        assertEquals("Propose $120 to caterer.near · needs 2 of 3 · bond 0.1 NEAR", p.headline)
        assertEquals("Type 120 USDC, note: catering", p.fill)
        assertFalse(p.notMember)
        link.put("proposers", JSONArray().put("ana.near").put("ben.near"))
        assertTrue(PotProposal.of(true, link, "caterer.near", "me.near").notMember)
        assertFalse(PotProposal.of(true, link, "caterer.near", "Ben.near").notMember)
        assertEquals("Only members can propose from this pot", PotProposal.MEMBERS_ONLY)
    }
}
