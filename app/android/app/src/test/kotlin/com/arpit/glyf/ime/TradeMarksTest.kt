package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The marks the trade panel and the sponsor panels draw (TradeMarks):
 *  every chain has its own, and their SVG paths read (ChainLogoTests on iOS). */
class TradeMarksTest {

    /** Every chain a panel offers has its own mark, and every mark's paths
     *  read (ChainLogoTests on iOS). */
    @Test fun everyChainHasAMarkThatReads() {
        for (chain in (SponsorMenu.SWAP_CHAINS + TradeEdit.FLASH_CHAINS).distinct()) {
            val mark = ChainMarks.mark(chain)
            assertTrue(chain, mark != null)
            if (mark!!.lettering == null) assertTrue(chain, mark.layers.isNotEmpty())
            for (layer in mark.layers) assertTrue(chain, SvgPath.ops(layer.d).isNotEmpty())
        }
        assertEquals(ChainMarks.mark("optimism"), ChainMarks.mark("op"))
        assertNull(ChainMarks.mark("whitechain"))
    }

    @Test fun svgPathsReadRelativeAndAbsoluteSteps() {
        val ops = SvgPath.ops("M10,10h5v5l-5,0z M0 0C1 2 3 4 5 6s1 1 2 2")
        assertEquals(SvgPath.Op('M', listOf(10f, 10f)), ops[0])
        assertEquals(SvgPath.Op('L', listOf(15f, 10f)), ops[1])
        assertEquals(SvgPath.Op('L', listOf(15f, 15f)), ops[2])
        assertEquals(SvgPath.Op('L', listOf(10f, 15f)), ops[3])
        assertEquals(SvgPath.Op('Z'), ops[4])
        assertEquals(SvgPath.Op('C', listOf(1f, 2f, 3f, 4f, 5f, 6f)), ops[6])
        // The smooth curve's first control mirrors the last one about the point.
        assertEquals(SvgPath.Op('C', listOf(7f, 8f, 6f, 7f, 7f, 8f)), ops[7])
        // "1.5.5" is two numbers, "-2-3" two more.
        assertEquals(SvgPath.Op('L', listOf(1.5f, 0.5f)), SvgPath.ops("M0 0L1.5.5")[1])
        assertEquals(SvgPath.Op('M', listOf(-2f, -3f)), SvgPath.ops("M-2-3")[0])
    }
}
