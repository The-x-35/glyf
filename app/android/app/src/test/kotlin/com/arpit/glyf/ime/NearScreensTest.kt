package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The NEAR screens on the Android keyboard, as the iPhone's were fixed in
 *  02c7471: the strip's whole chips (a bill split's answer, a payout without
 *  its pot), the pot proposal's card, and Earn's panel (the time on the
 *  card, You get without the APY, the notice on one line, everything out
 *  never stopped by the coin's balance). TradeIntentTests.swift and
 *  AIActionTests.swift's twins. */
class NearScreensTest {
    /** A stand-in font: every character half the size wide. */
    private val measure = { text: String, size: Double -> text.length * size * 0.5 }

    private fun read(text: String) = TradeIntent.parse(text) ?: throw AssertionError(text)

    // MARK: the strip's whole chips (ChipFit.whole, ChipFit.shorter)

    @Test fun aBillSplitTooWideShowsItsAnswer() {
        val a = Smart.quickAnswer("dinner was \$90 for the four of us", region = "US") ?: throw AssertionError("no split")
        val chip = Smart.Chip.Convert(a)
        val value = Smart.display(chip)
        assertEquals("\$90 for the four of us = \$22.50 each", value)
        assertEquals("\$22.50 each", ChipFit.shorter(chip))
        // Room for 20 characters at 11 (110): the whole (35) never fits.
        val f = ChipFit.whole(value, 15.0, 110.0, ChipFit.shorter(chip), measure)
        assertEquals(ChipFit.Fit("\$22.50 each", 15.0, true, 1), f)
        assertFalse(f.text.contains("…"))
        assertFalse(f.text.endsWith("="))
        // With the room, the whole sum.
        assertEquals(value, ChipFit.whole(value, 15.0, 400.0, ChipFit.shorter(chip), measure).text)
    }

    @Test fun aPotPayoutTooWideDropsItsPot() {
        val ask = PotAsk.parse("pay the caterer \$120 from the build pot") ?: throw AssertionError("no payout")
        val chip = Smart.Chip.Action(ask.label, NearPay.chipQuery(ask.params), "near:pot.pay")
        assertEquals("Propose \$120 to caterer from the build pot · Sputnik DAO", chip.label)
        assertEquals("Propose \$120 to caterer · Sputnik DAO", ChipFit.shorter(chip))
        // 23 characters of room at 11 (126.5): only "Propose $120 to caterer".
        val f = ChipFit.whole(chip.label, 15.0, 130.0, ChipFit.shorter(chip), measure)
        assertEquals("Propose \$120 to caterer", f.text)
        assertTrue(f.fits)
        assertEquals(1, f.lines)
        // A look at the pot, or any other action, has nothing shorter.
        assertNull(ChipFit.shorter(Smart.Chip.Action("See the trip pot · Sputnik DAO", "{}", "near:pot")))
        assertNull(ChipFit.shorter(Smart.Chip.Action("Add a Meet link", "", "meet")))
    }

    @Test fun stillTooWideWrapsOnTwoLinesBetweenWords() {
        val value = "Propose \$120 to the caterer for the build"
        // 41 characters, 225.5 wide at 11 on one line. In 130: three lines
        // at 13 and 12.5, two at 12 ("Propose $120 to the" / "caterer for the build").
        assertEquals(3, ChipFit.lines(value, 13.0, 130.0, measure))
        assertEquals(2, ChipFit.lines(value, 12.0, 130.0, measure))
        val f = ChipFit.whole(value, 15.0, 130.0, null, measure)
        assertEquals(2, f.lines)
        assertTrue(f.fits)
        assertEquals(value, f.text)
        assertEquals(12.0, f.size, 0.0)
        // A word wider than a line would be cut mid-word: never fits.
        assertNull(ChipFit.lines("Supercalifragilistic", 15.0, 50.0, measure))
        val none = ChipFit.whole("x".repeat(60), 15.0, 50.0, null, measure)
        assertEquals(ChipFit.Fit("x".repeat(60), ChipFit.SMALLEST, false, 2), none)
    }

    @Test fun whatFitsOnOneLineStaysOnOne() {
        val f = ChipFit.whole("Swap 10 USDC → ETH · Base", 15.0, 400.0, null, measure)
        assertEquals(ChipFit.Fit("Swap 10 USDC → ETH · Base", 15.0, true, 1), f)
        // Losing the last part comes before the shorter words.
        val g = ChipFit.whole("Propose \$120 to caterer · Sputnik DAO", 15.0, 130.0, "x", measure)
        assertEquals("Propose \$120 to caterer", g.text)
    }

    // MARK: the pot proposal's card

    @Test fun aProposalLeadsWithWhoAndPutsTheTermsUnder() {
        val link = JSONObject().put("ok", true)
            .put("url", "https://trezu.app/build.sputnik-dao.near/payments")
            .put("fill", JSONObject().put("amount", "120").put("coin", "USDC"))
            .put("bond", "0.1").put("proposers", "everyone").put("threshold", JSONObject().put("words", "3 of 5"))
        val p = PotProposal.of(true, link, "efiz.near", null)
        assertEquals("Propose \$120 to efiz.near", p.headline)
        assertEquals("Needs 3 of 5 · bond 0.1 NEAR", p.terms)
        assertEquals("Type 120 USDC", p.fill)
        assertEquals("Needs 3 of 5 · bond 0.1 NEAR\nType 120 USDC", p.detail)
        // No threshold or bond: only what to type.
        val bare = PotProposal.of(true, JSONObject().put("ok", true)
            .put("fill", JSONObject().put("amount", "5").put("coin", "NEAR")), "a.near", null)
        assertEquals("Propose 5 NEAR to a.near", bare.headline)
        assertNull(bare.terms)
        assertEquals("Type 5 NEAR", bare.detail)
        assertNull(PotProposal(error = "x").detail)
    }

    // MARK: Earn's panel

    private val gauntlet = EarnQuote.of(true, JSONObject().put("ok", true).put("amountInUsd", "49.97")
        .put("amountOutUsd", "49.75").put("timeSeconds", 52)
        .put("vault", JSONObject().put("id", "gtusdcp").put("name", "Gauntlet USDC Prime").put("protocol", "Morpho").put("apy", 4.51))
        .put("words", "≈ \$49.75 in Gauntlet USDC Prime at 4.51% APY"))

    @Test fun earnsTimeRidesOnTheCardAndYouGetDropsTheAPY() {
        val i = read("put \$50 to work")
        assertEquals("≈ \$49.75 in Gauntlet USDC Prime", gauntlet.rowWords)
        val rows = TradeQuote.earnRows(i, gauntlet, false)
        assertEquals(listOf("≈ \$49.75 in Gauntlet USDC Prime", "Morpho · 4.51% APY"), rows.map { it.value })
        assertFalse(rows.any { it.id == "arrives" })
        val quote = TradeQuote.Quote(null, 49.97, 49.75)
        assertEquals("≈ \$49.97 · ~52 s", TradeQuote.earnCardLine(i, quote, gauntlet).joinToString(" · "))
        // Out: what comes back is worth, and its time.
        assertEquals(listOf("≈ \$49.75", "~52 s"), TradeQuote.earnCardLine(read("withdraw \$20 from earn"), quote, gauntlet))
        assertEquals(emptyList<String>(), TradeQuote.earnCardLine(i, null, null))
        // Words without an APY stay as they are; none stays none.
        assertEquals("≈ \$5 in Taler USDC", EarnQuote(words = "≈ \$5 in Taler USDC").rowWords)
        assertNull(EarnQuote().rowWords)
    }

    @Test fun earnsNoticeFitsOneLine() {
        val n = EarnQuote.NOTICE.length   // 59
        // Room for it at 13: 13.
        assertEquals(13.0, EarnQuote.noticeSize(n * 6.5 + 1) { s -> n * s * 0.5 }!!, 0.0)
        // A little less: half points smaller, down to 11.
        assertEquals(12.0, EarnQuote.noticeSize(n * 6.0 + 1) { s -> n * s * 0.5 }!!, 0.0)
        assertEquals(11.0, EarnQuote.noticeSize(n * 5.5 + 1) { s -> n * s * 0.5 }!!, 0.0)
        // Too narrow even at 11: it wraps.
        assertNull(EarnQuote.noticeSize(n * 5.0) { s -> n * s * 0.5 })
    }

    @Test fun takingAllOutIsNeverStoppedByTheCoinsBalance() {
        val out = read("take my usdc out of earn")
        assertFalse(out.spendsHeldCoin)
        assertTrue(read("put \$50 to work").spendsHeldCoin)
        assertTrue(read("swap 0.05 eth to usdc on base").spendsHeldCoin)
        // No USDC on Base, and the button still takes everything out.
        assertFalse(TradeQuote.short(out, 0.0, null))
        assertFalse(TradeQuote.short(read("withdraw \$20 from earn"), 0.0, null))
        val go = TradeQuote.earnGo(out, null, false, EarnQuote(vaultName = "Gauntlet USDC Prime"), null)
        assertEquals("Take out all USDC", go.title)
        assertFalse(go.blocked)
        assertEquals("All your USDC back on Base",
            TradeQuote.earnRows(out, EarnQuote(vaultName = "Gauntlet USDC Prime"), false)[0].value)
        assertEquals("Take out 20 USDC", TradeQuote.earnGo(read("withdraw \$20 from earn"), null, false, gauntlet, null).title)
        // A swap still checks what's held.
        assertTrue(TradeQuote.short(read("swap 5 usdc to eth on base"), 2.1, null))
    }

    @Test fun twoLineRowValuesBreakBetweenWords() {
        val w: (String, Double) -> Double = { t, size -> t.length * size / 2 }
        // "≈ $49.75 in Gauntlet USDC Prime" (31): one line needs 170.5 at 11.
        val (size, lines) = TradeQuote.rowFit("≈ \$49.75 in Gauntlet USDC Prime", 120.0, w)
        assertEquals(2, lines)
        // Broken between words, both lines fit at that size.
        assertTrue((ChipFit.lines("≈ \$49.75 in Gauntlet USDC Prime", size, 120.0, w) ?: 9) <= 2)
    }
}
