package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The strip chip's words never end in "…" (D108): smaller first, then the
 *  last " · " part goes whole. */
class ChipFitTest {
    /** A stand-in font: every character half the size wide. */
    private val measure = { text: String, size: Double -> text.length * size * 0.5 }

    @Test fun wordsThatFitStayAsTheyAre() {
        val f = ChipFit.fit("Swap 10 USDC → ETH · Base", 15.0, 400.0, measure)
        assertEquals(ChipFit.Fit("Swap 10 USDC → ETH · Base", 15.0, true), f)
    }

    @Test fun aLittleTooWideIsDrawnSmaller() {
        val text = "Stop-loss 0.5 ETH at \$2,800 · Base"   // 34 characters: 255 wide at 15
        val f = ChipFit.fit(text, 15.0, 220.0, measure)
        assertEquals(text, f.text)
        assertEquals(12.5, f.size, 0.0)   // 212.5 wide
        assertTrue(f.fits)
    }

    @Test fun tooWideEvenSmallLosesTheChainWhole() {
        val text = "Stop-loss 0.5 ETH at \$2,800 · Base"
        // At 11 the whole is 187 wide; without " · Base" (27 characters) 202.5 at 15.
        val f = ChipFit.fit(text, 15.0, 180.0, measure)
        assertEquals("Stop-loss 0.5 ETH at \$2,800", f.text)
        assertEquals(13.0, f.size, 0.0)
        assertFalse(f.text.contains("…"))
    }

    @Test fun onlyTheLastPartEverGoes() {
        val bracket = "ETH TP \$4,500 · SL \$3,000 · Base"
        assertEquals(listOf(bracket, "ETH TP \$4,500 · SL \$3,000"), ChipFit.candidates(bracket))
        val f = ChipFit.fit(bracket, 15.0, 60.0, measure)
        // Nothing fits: the shortest at the smallest size, clipped, never cut with "…".
        assertEquals(ChipFit.Fit("ETH TP \$4,500 · SL \$3,000", ChipFit.SMALLEST, false), f)
        assertEquals(listOf("7xKX…gAsU"), ChipFit.candidates("7xKX…gAsU"))
    }
}
