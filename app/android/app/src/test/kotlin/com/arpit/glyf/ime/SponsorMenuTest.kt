package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The g menu's sponsor row (Uniswap, Definitive, NEAR Intents): which apps show, what
 *  each one's panel lists, and what every option on it puts up. A tap on a
 *  card only opens its panel (Arpit, 2026-11-06: "should not trigger a
 *  thing by default. It should show all the options"). The twin of
 *  SponsorMenuTests.swift. */
class SponsorMenuTest {

    private fun options(entries: List<SponsorMenu.Entry>) =
        entries.mapNotNull { (it as? SponsorMenu.Entry.Row)?.option }

    private fun trade(option: SponsorMenu.Option, typed: String = "", chain: String = "base"): TradeIntent {
        val a = SponsorMenu.action(option, typed, chain)
        if (a !is SponsorMenu.Action.Trade) fail("$option should open the trade panel")
        return (a as SponsorMenu.Action.Trade).intent
    }

    @Test fun uniswapDefinitiveAndNEARIntentsAndNothingElse() {
        assertEquals(listOf(SponsorMenu.Sponsor.UNISWAP, SponsorMenu.Sponsor.DEFINITIVE, SponsorMenu.Sponsor.NEAR),
            SponsorMenu.sponsors)
        assertEquals(listOf("Uniswap", "Definitive", "NEAR Intents"), SponsorMenu.Sponsor.values().map { it.title })
        assertEquals(SponsorMenu.Sponsor.NEAR, SponsorMenu.Sponsor.of("sponsor:near"))
        assertNull(SponsorMenu.Sponsor.of("sponsor:0g"))
    }

    @Test fun eachSponsorIsAShellScreen() {
        for (sponsor in SponsorMenu.Sponsor.values()) assertEquals(sponsor, SponsorMenu.Sponsor.of(sponsor.screenId))
        assertEquals("sponsor:definitive", SponsorMenu.Sponsor.DEFINITIVE.screenId)
        assertNull(SponsorMenu.Sponsor.of("vault"))
        assertNull(SponsorMenu.Sponsor.of("sponsor:world"))
    }

    @Test fun optionIdsRoundTrip() {
        val all = mutableListOf(SponsorMenu.Option.Swap, SponsorMenu.Option.Jupiter, SponsorMenu.Option.Typed,
            SponsorMenu.Option.OpenOrders, SponsorMenu.Option.NearTrade)
        all += SponsorMenu.NEAR_STARTERS.map { SponsorMenu.Option.NearStarter(it.first) }
        all += SponsorMenu.SWAP_CHAINS.map { SponsorMenu.Option.SwapOn(it) }
        all += SponsorMenu.ORDER_KINDS.map { SponsorMenu.Option.Order(it) }
        for (option in all) assertEquals(option.id, option, SponsorMenu.Option.of(option.id))
        assertNull(SponsorMenu.Option.of("swap:polygon"))
        assertNull(SponsorMenu.Option.of("order:send"))
        assertNull(SponsorMenu.Option.of("receipts"))
        assertNull(SponsorMenu.Option.of("near:moon"))
        assertNull(SponsorMenu.Option.of("nope"))
    }

    // MARK: Uniswap

    @Test fun uniswapListsSwapAndEveryChain() {
        val entries = SponsorMenu.entries(SponsorMenu.Sponsor.UNISWAP, "")
        assertEquals(listOf(SponsorMenu.Option.Swap) +
            listOf("base", "ethereum", "arbitrum", "optimism", "unichain").map { SponsorMenu.Option.SwapOn(it) } +
            listOf(SponsorMenu.Option.Jupiter), options(entries))
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.Swap, "Swap", "10 USDC → ETH", "swaparrows"), entries[0])
        assertEquals(SponsorMenu.Entry.Header("Chains"), entries[1])
        assertEquals("Ethereum", (entries[3] as SponsorMenu.Entry.Row).title)
    }

    @Test fun uniswapSwapIsTheStarterOnBase() {
        val t = trade(SponsorMenu.Option.Swap)
        assertEquals(TradeIntent.Kind.SWAP, t.kind)
        assertEquals("Uniswap", t.venue)
        assertEquals("10", t.amount)
        assertEquals("USDC", t.sell)
        assertEquals("ETH", t.buy)
        assertEquals("base", t.chainName)
    }

    @Test fun uniswapSwapTakesTheSwapAlreadyTypedAndSaysSo() {
        val typed = "sure. swap 0.05 eth to usdc on arbitrum"
        assertEquals(TradeIntent.parse(typed), trade(SponsorMenu.Option.Swap, typed))
        val entries = SponsorMenu.entries(SponsorMenu.Sponsor.UNISWAP, typed)
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.Swap, "Swap", "0.05 ETH → USDC", "swaparrows"), entries[0])
        // A Flash order typed is not Uniswap's: the starter swap instead.
        assertEquals(SponsorMenu.starterSwap("base"), trade(SponsorMenu.Option.Swap, "stop-loss eth at 2800"))
    }

    @Test fun eachChainStartsASwapThere() {
        for (chain in SponsorMenu.SWAP_CHAINS) {
            val t = trade(SponsorMenu.Option.SwapOn(chain))
            assertEquals(TradeIntent.Kind.SWAP, t.kind)
            assertEquals(chain, t.chainName)
            assertEquals("USDC", t.sell)
            assertEquals("ETH", t.buy)
        }
    }

    // MARK: Definitive

    @Test fun definitiveListsTheChainEveryOrderTypeAndOpenOrders() {
        val entries = SponsorMenu.entries(SponsorMenu.Sponsor.DEFINITIVE, "hello")
        assertEquals(SponsorMenu.Entry.ChainPicker, entries.first())
        assertEquals(SponsorMenu.Entry.Header("Orders"), entries[1])
        assertEquals(SponsorMenu.ORDER_KINDS.map { SponsorMenu.Option.Order(it) } + SponsorMenu.Option.OpenOrders, options(entries))
        val titles = entries.mapNotNull { (it as? SponsorMenu.Entry.Row)?.title }
        assertEquals(listOf("Limit buy", "Stop buy", "Stop-loss", "Take profit", "Bracket", "Trailing stop",
            "TWAP", "Bridge", "Open orders"), titles)
        assertEquals("→ Arbitrum", SponsorMenu.orderDetail(TradeIntent.Kind.BRIDGE, "base"))
        assertEquals("→ Base", SponsorMenu.orderDetail(TradeIntent.Kind.BRIDGE, "solana"))
    }

    @Test fun definitiveOffersTheFlashOrderTypedFirst() {
        val typed = "stop-loss eth at 2800"
        val entries = SponsorMenu.entries(SponsorMenu.Sponsor.DEFINITIVE, typed)
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.Typed, "Stop-loss ETH at $2,800", null, "textcursor"), entries[2])
        assertEquals(TradeIntent.parse(typed), trade(SponsorMenu.Option.Typed, typed))
        // A swap typed is Uniswap's, not an order: no typed row.
        assertFalse(options(SponsorMenu.entries(SponsorMenu.Sponsor.DEFINITIVE, "swap 1 eth to usdc")).contains(SponsorMenu.Option.Typed))
        assertNull(SponsorMenu.action(SponsorMenu.Option.Typed, "hello"))
    }

    @Test fun everyOrderTypeStartsOnBaseWithETH() {
        for (kind in SponsorMenu.ORDER_KINDS) {
            val t = trade(SponsorMenu.Option.Order(kind))
            assertEquals(kind, t.kind)
            assertEquals("Flash", t.venue)
            assertEquals("$kind", "base", t.chainName)
        }
        val limit = trade(SponsorMenu.Option.Order(TradeIntent.Kind.LIMIT))
        assertEquals("ETH", limit.buy)
        assertEquals("USDC", limit.sell)
        assertEquals("20", limit.amount)
        assertTrue(limit.amountIsUSD)
        val stopLoss = trade(SponsorMenu.Option.Order(TradeIntent.Kind.STOP_LOSS))
        assertEquals("ETH", stopLoss.sell)
        assertNull("guards everything held", stopLoss.amount)
        val trail = trade(SponsorMenu.Option.Order(TradeIntent.Kind.TRAILING_STOP))
        assertEquals("10", trail.trailPercent)
        assertNull(trail.price)
        assertFalse(trail.awaitingPrice)
        val twap = trade(SponsorMenu.Option.Order(TradeIntent.Kind.TWAP))
        assertEquals("20", twap.amount)
        assertEquals(86_400, twap.durationSeconds)
        val bridge = trade(SponsorMenu.Option.Order(TradeIntent.Kind.BRIDGE))
        assertEquals("USDC", bridge.sell)
        assertEquals("arbitrum", bridge.toChain)
    }

    @Test fun pricedOrdersWaitForTheMarketAndSitTheRightSideOfIt() {
        val cases = listOf(Triple(TradeIntent.Kind.LIMIT, -5.0, null), Triple(TradeIntent.Kind.STOP, 5.0, null),
            Triple(TradeIntent.Kind.STOP_LOSS, -10.0, null), Triple(TradeIntent.Kind.TAKE_PROFIT, 10.0, null),
            Triple(TradeIntent.Kind.BRACKET, 10.0, -10.0))
        for ((kind, pct, stopPct) in cases) {
            val t = trade(SponsorMenu.Option.Order(kind))
            assertNull("$kind: no made-up price", t.price)
            assertEquals("$kind", pct, t.pricePercent)
            assertEquals("$kind", stopPct, t.stopPercent)
            assertTrue(t.awaitingPrice)
        }
        val stopLoss = SponsorMenu.priced(trade(SponsorMenu.Option.Order(TradeIntent.Kind.STOP_LOSS)), 3_183.42)
        assertEquals("2870", stopLoss.price)
        assertFalse(stopLoss.awaitingPrice)
        assertEquals("Stop-loss ETH at $2,870", stopLoss.title)
        assertEquals("2870", stopLoss.query["price"])
        val bracket = SponsorMenu.priced(trade(SponsorMenu.Option.Order(TradeIntent.Kind.BRACKET)), 3_000.0)
        assertEquals("3300", bracket.price)
        assertEquals("2700", bracket.stopPrice)
        assertEquals("2850", SponsorMenu.priced(trade(SponsorMenu.Option.Order(TradeIntent.Kind.LIMIT)), 3_000.0).price)
        assertEquals("3150", SponsorMenu.priced(trade(SponsorMenu.Option.Order(TradeIntent.Kind.STOP)), 3_000.0).price)
        // No price, no change: the panel keeps waiting rather than guess.
        val waiting = trade(SponsorMenu.Option.Order(TradeIntent.Kind.TAKE_PROFIT))
        assertEquals(waiting, SponsorMenu.priced(waiting, 0.0))
    }

    @Test fun pricesRoundTheWayPeopleSayThem() {
        assertEquals("2870", SponsorMenu.roundPrice(2_865.07))
        assertEquals("142", SponsorMenu.roundPrice(142.37))
        assertEquals("21.46", SponsorMenu.roundPrice(21.456))
        assertEquals("0.1235", SponsorMenu.roundPrice(0.123456))
    }

    @Test fun onSolanaTheOrdersAreSOLs() {
        for (kind in SponsorMenu.ORDER_KINDS) {
            val t = trade(SponsorMenu.Option.Order(kind), chain = "solana")
            assertEquals(kind, t.kind)
            assertEquals("$kind", "solana", t.chainName)
        }
        assertEquals("SOL", trade(SponsorMenu.Option.Order(TradeIntent.Kind.STOP_LOSS), chain = "solana").sell)
        assertEquals("SOL", trade(SponsorMenu.Option.Order(TradeIntent.Kind.LIMIT), chain = "solana").buy)
        assertEquals("SOL", trade(SponsorMenu.Option.Order(TradeIntent.Kind.TRAILING_STOP), chain = "solana").sell)
        assertEquals("base", trade(SponsorMenu.Option.Order(TradeIntent.Kind.BRIDGE), chain = "solana").toChain)
    }

    /** Solana sits under Uniswap's chains as Jupiter, and opens the
     *  keyboard's Buy panel. */
    @Test fun solanaSwapsGoThroughJupiter() {
        val entries = SponsorMenu.entries(SponsorMenu.Sponsor.UNISWAP, "")
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.Jupiter, "Solana", "Jupiter", "chain:solana"), entries.last())
        assertEquals(SponsorMenu.Action.SolanaSwap, SponsorMenu.action(SponsorMenu.Option.Jupiter, ""))
        assertEquals("Jupiter", TradeIntent.parse("swap 10 usdc to usdt on solana")?.venue)
        assertEquals("Uniswap", TradeIntent.parse("swap 10 usdc to eth on base")?.venue)
    }

    @Test fun openOrdersOpensTheApp() {
        assertEquals(SponsorMenu.Action.OpenApp("evm-wallet"), SponsorMenu.action(SponsorMenu.Option.OpenOrders, ""))
    }

    // MARK: NEAR Intents

    @Test fun nearIntentsStartsWithUSDCOnBaseToSOL() {
        val entries = SponsorMenu.entries(SponsorMenu.Sponsor.NEAR, "")
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.NearTrade, "Swap", "20 USDC → SOL", "swaparrows"), entries[0])
        assertEquals(SponsorMenu.Entry.Header("Across chains"), entries[1])
        assertEquals(listOf(SponsorMenu.Option.NearTrade, SponsorMenu.Option.NearStarter("base-solana"),
            SponsorMenu.Option.NearStarter("solana-base"), SponsorMenu.Option.NearStarter("base-near")), options(entries))
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.NearStarter("base-solana"), "Base → Solana", "20 USDC → SOL",
            "chain:solana"), entries[2])
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.NearStarter("solana-base"), "Solana → Base", "0.1 SOL → USDC",
            "chain:base"), entries[3])
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.NearStarter("base-near"), "Base → NEAR", "20 USDC → NEAR",
            "chain:near"), entries[4])
        val t = trade(SponsorMenu.Option.NearTrade)
        assertEquals("NEAR Intents", t.venue)
        assertEquals("USDC", t.sell)
        assertEquals("base", t.chainName)
        assertEquals("SOL", t.buy)
        assertEquals("solana", t.buyChain)
        for ((id, _) in SponsorMenu.NEAR_STARTERS) assertTrue(id, trade(SponsorMenu.Option.NearStarter(id)).isNear)
    }

    @Test fun nearIntentsTakesTheNEARTradeTyped() {
        val typed = "ok. send 5 usdc to alice.near"
        assertEquals(TradeIntent.parse(typed), trade(SponsorMenu.Option.NearTrade, typed))
        assertEquals(SponsorMenu.Entry.Row(SponsorMenu.Option.NearTrade, "Send", "5 USDC to alice.near", "swaparrows"),
            SponsorMenu.entries(SponsorMenu.Sponsor.NEAR, typed)[0])
        // A Uniswap swap typed isn't NEAR's: the starter instead.
        assertEquals(SponsorMenu.nearStarter("base-solana"), trade(SponsorMenu.Option.NearTrade, "swap 1 eth to usdc"))
    }

    /** The Definitive panel's bridge starter on Solana stays Flash's: the
     *  same words typed would go through NEAR Intents. */
    @Test fun flashsOwnBridgeStarterStaysFlashs() {
        val t = SponsorMenu.starter(TradeIntent.Kind.BRIDGE, "solana")
        assertEquals(TradeIntent.Kind.BRIDGE, t?.kind)
        assertEquals("Flash", t?.venue)
        assertTrue(TradeIntent.parse("move 10 usdc from solana to base")!!.isNear)
    }
}
