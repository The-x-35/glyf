package com.arpit.glyf.ime

import com.arpit.glyf.ime.StripPolicy.Kind
import com.arpit.glyf.ime.StripPolicy.Seen
import com.arpit.glyf.ime.StripPolicy.Timing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** docs/STRIP-POLICY.md. iOS's StripPolicyTests.swift has the same cases. */
class StripPolicyTest {

    private val t0 = 1_800_000_000.0

    private fun typing(since: Double, midWord: Boolean = false, undo: Boolean = false, fix: Boolean = false) =
        StripPolicy.Typing(since, midWord, undo) { fix }

    @Test fun theNumbersAreTheDocs() {
        assertEquals(0.4, StripPolicy.SETTLE, 0.0)
        assertEquals(1.0, StripPolicy.MID_WORD_PAUSE, 0.0)
        assertEquals(10.0, StripPolicy.CROSS_QUIET, 0.0)
        assertEquals(5.0, StripPolicy.IGNORE_QUIET, 0.0)
        assertEquals(2, StripPolicy.WORDS_PAST)
        assertEquals(1.0, StripPolicy.SEEN_FOR, 0.0)
        assertEquals(180.0, StripPolicy.PASTE_FRESH, 0.0)
    }

    @Test fun aChipWaitsForAPause() {
        val p = StripPolicy()
        assertEquals(Timing.Wait(0.4), p.timing(Kind.ANSWER, "a", typing(0.0)))
        assertEquals(Timing.Now, p.timing(Kind.ANSWER, "a", typing(0.4)))
        assertEquals(Timing.Now, p.timing(Kind.AI, "a", typing(5.0)))
    }

    @Test fun wordsWinMidWordAndAfterAFix() {
        val p = StripPolicy()
        assertEquals(Timing.Wait(1.0), p.timing(Kind.ANSWER, "a", typing(0.0, midWord = true)))
        assertEquals(Timing.Now, p.timing(Kind.ANSWER, "a", typing(1.0, midWord = true)))
        assertEquals(Timing.Words, p.timing(Kind.ANSWER, "a", typing(9.0, midWord = true, fix = true)))
        assertEquals(Timing.Words, p.timing(Kind.AI, "a", typing(9.0, undo = true)))
        assertEquals(Timing.Now, p.timing(Kind.FILL, "f", typing(0.5, midWord = true, fix = true)))
        p.shown(Kind.ANSWER, "a", "2+5", t0)
        assertEquals(Timing.Now, p.timing(Kind.ANSWER, "a", typing(0.0, midWord = true, fix = true)))
    }

    @Test fun aCrossIsATenSecondCooldown() {
        val p = StripPolicy()
        p.enter("doc1")
        p.shown(Kind.ANSWER, "calc|2+5", "2+5", t0)
        p.dismissed(Kind.ANSWER, "calc|2+5", t0)
        assertEquals(Seen.Nothing, p.observe("2+50", t0 + 3))
        assertFalse(p.allows(Kind.ANSWER, "calc|2+50", t0 + 3))
        assertFalse(p.allows(Kind.AI, "ai|1", t0 + 9.9))
        assertTrue(p.allows(Kind.ANSWER, "calc|2+50", t0 + 10))
        assertTrue(p.allows(Kind.AI, "ai|1", t0 + 10))
    }

    @Test fun theCrossedChipComesAgainOnceTheTextChanges() {
        val p = StripPolicy()
        p.shown(Kind.ANSWER, "calc|2+5", "2+5", t0)
        p.dismissed(Kind.ANSWER, "calc|2+5", t0)
        assertEquals(Seen.Nothing, p.observe("2+5", t0 + 30))
        assertFalse(p.allows(Kind.ANSWER, "calc|2+5", t0 + 30))
        p.observe("2+50", t0 + 31)
        p.observe("2+5", t0 + 32)
        assertTrue(p.allows(Kind.ANSWER, "calc|2+5", t0 + 32))
        p.shown(Kind.ANSWER, "calc|2+5", "2+5", t0 + 33)
        p.dismissed(Kind.ANSWER, "calc|2+5", t0 + 33)
        p.observe("2+56", t0 + 44)
        assertTrue(p.allows(Kind.ANSWER, "calc|2+56", t0 + 44))
    }

    @Test fun typingPastIsAShortQuiet() {
        val p = StripPolicy()
        p.shown(Kind.AI, "ai|q1", "what is the capital of france", t0)
        assertEquals(Seen.Nothing, p.observe("what is the capital of france and", t0 + 2))
        assertEquals(Seen.Ignored(Kind.AI), p.observe("what is the capital of france and its", t0 + 3))
        assertFalse(p.allows(Kind.AI, "ai|q2", t0 + 7))
        assertTrue(p.allows(Kind.AI, "ai|q2", t0 + 8))
    }

    @Test fun aGlimpseOrAnEditIsNoVerdict() {
        val p = StripPolicy()
        p.shown(Kind.ANSWER, "a", "lets 10 inch", t0)
        assertEquals(Seen.Nothing, p.observe("lets 10 inch of snow", t0 + 0.5))
        assertNull(p.onScreen)
        assertTrue(p.allows(Kind.ANSWER, "a", t0 + 1))
        p.shown(Kind.ANSWER, "b", "2+5", t0)
        assertEquals(Seen.Nothing, p.observe("2+", t0 + 5))
        assertNull(p.onScreen)
    }

    @Test fun aWordGrowingIsNotAWordPast() {
        assertEquals(0, StripPolicy.wordsPast("2+5", "2+50"))
        assertEquals(1, StripPolicy.wordsPast("2+5", "2+50 is"))
        assertEquals(2, StripPolicy.wordsPast("2+5", "2+5 is it"))
        assertNull(StripPolicy.wordsPast("2+5", "2+"))
        assertEquals(2, StripPolicy.wordsPast("", "hi there"))
        assertEquals("my email is", StripPolicy.anchor("my email is  "))
        assertEquals(40, StripPolicy.anchor("a".repeat(50)).length)
    }

    @Test fun aCopyShowsOnce() {
        val p = StripPolicy()
        p.shown(Kind.PASTE, "paste|hello", "", t0)
        assertEquals(Seen.Nothing, p.observe("", t0 + 1))
        assertEquals(Seen.PasteIgnored, p.observe("h", t0 + 2))
    }

    @Test fun codesAndPasswordsGetOnlyTheirChips() {
        for (kind in Kind.values()) {
            assertTrue(StripPolicy.allowed(kind, StripPolicy.Field.NORMAL))
            assertFalse(StripPolicy.allowed(kind, StripPolicy.Field.SECRET))
        }
        val code = Kind.values().filter { StripPolicy.allowed(it, StripPolicy.Field.CODE) }.toSet()
        assertEquals(setOf(Kind.FILL, Kind.PASTE, Kind.MAIL), code)
    }

    @Test fun aMailHasNoCooldown() {
        val p = StripPolicy()
        p.shown(Kind.MAIL, "mail|1", "", t0)
        p.dismissed(Kind.MAIL, "mail|1", t0)
        assertTrue(p.allows(Kind.MAIL, "mail|2", t0 + 1))
        assertFalse(p.allows(Kind.MAIL, "mail|1", t0 + 1))
        assertTrue(p.allows(Kind.ANSWER, "calc|x", t0 + 1))
    }

    @Test fun aNewFieldStartsClean() {
        val p = StripPolicy()
        p.enter("doc1")
        p.shown(Kind.ANSWER, "a", "x", t0)
        p.dismissed(Kind.ANSWER, "a", t0)
        p.enter("doc2")
        assertTrue(p.allows(Kind.ANSWER, "a", t0 + 1))
    }
}
