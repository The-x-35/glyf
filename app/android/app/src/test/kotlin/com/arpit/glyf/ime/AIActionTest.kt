package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Recurring buys read on the phone and the strip's recommended actions
 *  from POST /suggest (AIAction). The twin of AIActionTests.swift. */
class AIActionTest {

    private val month = 30 * 86_400
    private fun read(text: String) = TradeIntent.parse(text) ?: throw AssertionError(text)

    @Test fun aDCAEachMonthIsOneFlashTWAPOfItsFirstMonth() {
        val i = read("dca $20 in eth each month")
        assertEquals(TradeIntent.Kind.TWAP, i.kind)
        assertEquals("Flash", i.venue)
        assertEquals("ETH", i.buy)
        assertEquals("USDC", i.sell)
        assertTrue(i.amountIsUSD)
        // Flash runs a TWAP 30 days at most: the order is the first month.
        assertEquals("20", i.amount)
        assertEquals(month, i.durationSeconds)
        val plan = i.plan!!
        assertEquals(RecurringPlan("20", RecurringPlan.Period.MONTH, periods = 12, placed = 1), plan)
        assertEquals("DCA $20 of ETH monthly", i.title)
        assertEquals("$20 monthly · 12 months", plan.summary)
        assertEquals("Flash runs 30 days at most · 1 of 12 months", plan.capNote)
    }

    @Test fun theWaysPeopleSayIt() {
        val weekly = read("dca 20$ eth weekly")
        assertEquals(RecurringPlan.Period.WEEK, weekly.plan?.period)
        assertEquals("20", weekly.plan?.every)
        assertEquals(4, weekly.plan?.periods)
        assertEquals("80", weekly.amount)
        assertEquals(28 * 86_400, weekly.durationSeconds)
        assertNull(weekly.plan?.capNote)

        val btc = read("buy $50 of btc every week for 3 months")
        assertEquals("WBTC", btc.buy)
        assertEquals(13, btc.plan?.periods)
        assertEquals(4, btc.plan?.placed)
        assertEquals("200", btc.amount)
        assertEquals("Flash runs 30 days at most · 4 of 13 weeks", btc.plan?.capNote)

        val sol = read("invest 100 usdc in sol monthly")
        assertEquals("SOL", sol.buy)
        assertEquals("USDC", sol.sell)
        assertEquals("solana", sol.chainName)
        assertEquals("100", sol.amount)
        assertEquals("DCA $100 of SOL monthly", sol.title)

        assertEquals(2, TradeIntent.parse("dca $10 into eth every 2 weeks")?.plan?.interval)
        assertEquals(4, TradeIntent.parse("dca $10 into eth biweekly")?.plan?.periods)
        assertEquals(12, TradeIntent.parse("invest $25 in eth monthly for a year")?.plan?.periods)
        assertEquals("arbitrum", TradeIntent.parse("Buy $30 of ETH every month on arbitrum.")?.chainName)
    }

    @Test fun aShortScheduleStaysTheTWAPItWas() {
        // Inside Flash's 30 days: one order spread over the whole span, as before.
        val i = read("buy $20 of eth every day for a week")
        assertNull(i.plan)
        assertEquals("140", i.amount)
        assertEquals("Buy $20 of ETH every day for 7 days", i.title)
        // Past 30 days ("weekly" read as 7 weeks): now the recurring plan.
        val long = read("dca $50 into eth weekly")
        assertEquals(RecurringPlan.Period.WEEK, long.plan?.period)
        assertTrue((long.durationSeconds ?: 0) <= RecurringPlan.FLASH_MAX_SECONDS)
    }

    @Test fun notEveryRepeatIsATrade() {
        assertNull(TradeIntent.parse("i put $20 in the jar every month"))
        assertNull(TradeIntent.parse("dca $20 in usdc each month"))
        assertNull(TradeIntent.parse("we should invest more time in this every week"))
    }

    // MARK: actions from the server

    private fun action(tool: String, params: Map<String, Any>, label: String = "x"): AIAction? {
        val p = JSONObject()
        for ((k, v) in params) p.put(k, v)
        return AIAction.from(JSONObject().put("tool", tool).put("label", label).put("params", p))
    }

    @Test fun aDCAActionOpensTheTradePanelFilledIn() {
        val a = action("trade.dca", mapOf("asset" to "ETH", "every" to 20, "period" to "month"),
            label = "DCA $20 of ETH monthly · Flash")!!
        val chip = a.chip as Smart.Chip.Trade
        assertEquals(TradeIntent.parse("dca $20 in eth each month"), chip.intent)
        assertEquals(12, chip.intent.plan?.periods)
        val weeks = action("trade.dca", mapOf("asset" to "WBTC", "every" to "50", "period" to "week", "periods" to 13))!!
        assertEquals(4, weeks.trade?.plan?.placed)
    }

    @Test fun tradeActionsReadAsTheWordsWould() {
        val cases = listOf(
            Triple(mapOf("type" to "stop-loss", "asset" to "ETH", "price" to "3000"), "trade.flash", "stop loss eth at 3000"),
            Triple(mapOf("type" to "take-profit", "asset" to "ETH", "price" to 4500, "amount" to 0.1), "trade.flash", "take profit 0.1 eth at 4500"),
            Triple(mapOf("type" to "limit", "asset" to "ETH", "side" to "buy", "usd" to true, "amount" to 100, "price" to 2800), "trade.flash", "buy $100 of eth at 2800"),
            Triple(mapOf("type" to "bracket", "asset" to "ETH", "price" to 4500, "stopPrice" to 3000), "trade.flash", "my eth tp 4500 sl 3000"),
            Triple(mapOf("type" to "trailing-stop", "asset" to "ETH", "trailPercent" to 5), "trade.flash", "trail my eth by 5%"),
            Triple(mapOf("type" to "twap", "asset" to "ETH", "amount" to 100, "hours" to 48), "trade.flash", "buy $100 of eth over 2 days"),
            Triple(mapOf("sell" to "ETH", "buy" to "USDC", "amount" to 0.05, "chain" to "base"), "trade.swap", "swap 0.05 eth to usdc on base"),
            Triple(mapOf("sell" to "USDC", "buy" to "ETH", "amount" to 20, "usd" to true), "trade.swap", "buy $20 of eth"),
            Triple(mapOf("asset" to "USDC", "amount" to 50, "from" to "base", "to" to "arbitrum"), "trade.bridge", "move 50 usdc from base to arbitrum"),
        )
        for ((params, tool, words) in cases) {
            val a = action(tool, params) ?: throw AssertionError(words)
            assertEquals(words, TradeIntent.parse(words), a.trade)
        }
    }

    @Test fun otherToolsOpenTheirPanels() {
        val event = action("calendar.event", mapOf("title" to "Dinner with Sam", "when" to "friday 8pm"))?.chip as Smart.Chip.Event
        assertTrue(event.plan.hasDay)
        assertTrue(event.plan.hasTime)
        assertEquals(Smart.Chip.Action("Add a Meet link", "", "meet"), action("meet.link", emptyMap())?.chip)
        assertEquals(Smart.Chip.Action("YouTube: dune 2 trailer", "dune 2 trailer", "open:youtube"),
            action("youtube", mapOf("query" to "dune 2 trailer"), label = "YouTube: dune 2 trailer")?.chip)
        // The Shorts tab (2026-11-06), as on the iPhone.
        assertEquals(Smart.Chip.Action("Shorts: cats", "cats", "open:shorts"),
            action("shorts", mapOf("query" to "cats"), label = "Shorts: cats")?.chip)
        assertNull(action("shorts", mapOf("query" to "")))
        assertEquals(Smart.Chip.Action("x", "ramen near me", "open:maps"), action("maps", mapOf("query" to "ramen near me"))?.chip)
        assertEquals(Smart.Chip.Action("x", "Spanish", "open:translate"), action("translate", mapOf("to" to "spanish"))?.chip)
        assertEquals(Smart.Chip.Action("x", "", "rewrite"), action("rewrite", emptyMap())?.chip)
        assertEquals(Smart.Chip.Action("x", "10 km in miles", "answer"), action("convert", mapOf("query" to "10 km in miles"))?.chip)
    }

    @Test fun whatThisPhoneCantOpenIsDropped() {
        assertNull(action("trade.yolo", emptyMap()))
        assertNull(action("trade.flash", mapOf("type" to "stop-loss", "asset" to "DOGE", "price" to 1)))
        assertNull(action("calendar.event", mapOf("title" to "stuff", "when" to "sometime")))
        assertNull(action("search", mapOf("query" to "")))
        assertNull(action("booking.link", emptyMap()))
        // Sends to a name aren't one of this phone's tools.
        assertNull(action("send", mapOf("to" to "arpit.eth", "amount" to 5, "token" to "USDC")))
        assertNull(AIAction.from(JSONObject().put("tool", "meet.link")))
        assertNull(action("rewrite", emptyMap(), label = "x".repeat(81)))
    }

    @Test fun thePanelShowsThePlanUntilItIsChanged() {
        val i = read("dca $20 in eth each month")
        assertEquals("Over · Flash max", i.planOverRow?.first)
        assertEquals("30 days · month 1 of 12", i.planOverRow?.second)
        assertEquals("4 weeks · weeks 1–4 of 13", TradeIntent.parse("buy $50 of btc every week for 3 months")?.planOverRow?.second)
        assertEquals("4 weeks · $20 weekly", TradeIntent.parse("dca 20$ eth weekly")?.planOverRow?.second)
        i.amount = "35"
        assertNull(i.planOverRow)
        assertNull(TradeIntent.parse("buy $20 of eth every day for a week")?.planOverRow)
    }

    /** The live AI's answer for "grab 10 dollars of tesla whenever it slips
     *  under 300" opens as $10 of Tesla at $300 on Base. */
    @Test fun anAIFlashOrderKeepsTheTypedValues() {
        val a = AIAction("trade.flash", "Buy TSLA at $300 · Flash",
            mapOf("type" to "limit", "asset" to "TSLA", "amount" to "10", "usd" to "true", "price" to "300"))
        val t = a.trade!!
        assertEquals(TradeIntent.Kind.LIMIT, t.kind)
        assertEquals("10", t.amount)
        assertTrue(t.amountIsUSD)
        assertEquals("300", t.price)
        assertEquals("TSLA", t.buy)
        assertEquals("base", t.chainName)
    }
}
