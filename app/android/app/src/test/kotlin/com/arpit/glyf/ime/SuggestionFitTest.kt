package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** D108: no "…", the word shrinks instead. iOS StripPolicyTests'
 *  SuggestionFit cases, line for line. */
class SuggestionFitTest {
    /** 1pt of width per point of size per letter: easy numbers. */
    private fun linear(words: List<String>): (Int, Double) -> Double = { i, size -> words[i].length * size * 0.5 }

    @Test fun shortWordsKeepThreeEqualSlotsAtFullSize() {
        val words = listOf("the", "you", "❤️")
        val plan = SuggestionFit.plan(listOf(17.0, 17.0, 22.0), total = 314.0, spacing = 4.0, measure = linear(words))
        assertEquals(listOf(0, 1, 2), plan.map { it.item })
        assertEquals(listOf(17.0, 17.0, 22.0), plan.map { it.size })
        assertEquals("equal thirds", 1, plan.map { it.width }.toSet().size)
    }

    @Test fun aLongWordShrinksInsteadOfTruncating() {
        // 12 letters at 17 = 102 + 8 pad > 102 a slot: drawn smaller, whole.
        val words = listOf("the", "relationship", "a")
        val plan = SuggestionFit.plan(listOf(17.0, 17.0, 17.0), total = 314.0, spacing = 4.0, measure = linear(words))
        assertEquals(listOf(0, 1, 2), plan.map { it.item })
        assertTrue(plan[1].size < 17)
        assertTrue(plan[1].size >= SuggestionFit.SMALLEST)
        assertTrue(linear(words)(1, plan[1].size) + SuggestionFit.PAD <= plan[1].width)
        assertEquals(17.0, plan[0].size, 0.0)
    }

    @Test fun aWordTooLongEvenSmallGetsAWiderSlotOrItsSlotGoes() {
        val words = listOf("internationalization", "inter", "intern")
        val plan = SuggestionFit.plan(listOf(17.0, 17.0, 17.0), total = 314.0, spacing = 4.0, measure = linear(words))
        // 20 letters at 11 = 110 + 8: more than a third, so a wider slot.
        assertEquals(0, plan.first().item)
        assertEquals(SuggestionFit.SMALLEST, plan[0].size, 0.0)
        assertTrue(plan[0].width > (314 - 8) / 3.0)
        for (slot in plan) slot.item?.let { i ->
            assertTrue(linear(words)(i, slot.size) + SuggestionFit.PAD <= slot.width + 0.001)
        }
        // Nothing fits the whole bar: dropped, never cut.
        val huge = listOf("pneumonoultramicroscopicsilicovolcanoconiosis" + "x".repeat(40))
        assertTrue(SuggestionFit.plan(listOf(17.0), total = 314.0, spacing = 4.0, measure = linear(huge)).all { it.item == null })
    }

    @Test fun theSlotsFillTheBarExactly() {
        val words = listOf("internationalization", "international", "internationally")
        val plan = SuggestionFit.plan(listOf(17.0, 17.0, 17.0), total = 322.0, spacing = 4.0, measure = linear(words))
        assertEquals("the best word always stays", 0, plan.first().item)
        for (slot in plan) slot.item?.let { i ->
            assertTrue(slot.size >= SuggestionFit.SMALLEST)
            assertTrue(words[i], linear(words)(i, slot.size) + SuggestionFit.PAD <= slot.width + 0.001)
        }
        assertEquals(322.0, plan.sumOf { it.width } + 4.0 * (plan.size - 1), 0.01)
        // The pad is the caller's unit: pixels on Android.
        val px = SuggestionFit.plan(listOf(17.0), total = 900.0, spacing = 21.0, pad = 24.0) { _, size -> size * 3 }
        assertEquals(17.0, px.first().size, 0.0)
    }
}
