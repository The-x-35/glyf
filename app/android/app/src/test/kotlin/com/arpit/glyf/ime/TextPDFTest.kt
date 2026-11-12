package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A long copy pastes as a PDF (TextPDF): GlyfEngineTests'
 *  testALongCopyBecomesAPDF, and how Android lays it on pages. */
class TextPDFTest {

    @Test fun aLongCopyOffersAPDF() {
        assertFalse(TextPDF.offers("short note"))
        assertFalse(TextPDF.offers(" ".repeat(2000) + "x".repeat(999)))
        assertTrue(TextPDF.offers("x".repeat(1000)))
        // Characters, not UTF-16 units: 999 emoji are 999.
        assertFalse(TextPDF.offers("🙂".repeat(999)))
    }

    @Test fun itsTitleIsItsFirstLineShort() {
        assertEquals("Meeting notes", TextPDF.title("\nMeeting notes\nWe talked about the launch."))
        assertEquals("a".repeat(57) + "…", TextPDF.title("a".repeat(80)))
        val long = (1..60).joinToString("\n") { "Line $it: the quarterly report says revenue grew in every region this year." }
        assertTrue(TextPDF.offers(long))
        assertEquals("Line 1: the quarterly report says revenue grew in every r…", TextPDF.title(long))
        assertEquals("meeting-notes.pdf", TextPDF.fileName("Meeting notes!\nmore"))
        assertEquals("glyf.pdf", TextPDF.fileName("🙂🙂🙂"))
    }

    @Test fun linesGoOnTheNextPageWhenTheyWouldCrossTheBottom() {
        // 15 units a line, 684 a page: 45 lines a page.
        val bottoms = (1..100).map { it * 15 }
        assertEquals(listOf(0, 45, 90), TextPDF.pageStarts(bottoms, 684))
        assertEquals(listOf(0), TextPDF.pageStarts(listOf(15, 30), 684))
        assertEquals(listOf(0), TextPDF.pageStarts(emptyList(), 684))
        // A line taller than a page still gets a page of its own.
        assertEquals(listOf(0, 1), TextPDF.pageStarts(listOf(10, 900), 684))
    }
}
