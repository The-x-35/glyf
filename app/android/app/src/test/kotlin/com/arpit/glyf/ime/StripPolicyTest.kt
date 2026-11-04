package com.arpit.glyf.ime

import com.arpit.glyf.ime.StripPolicy.Kind
import com.arpit.glyf.ime.StripPolicy.Seen
import com.arpit.glyf.ime.StripPolicy.Timing
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** docs/STRIP-POLICY.md. iOS's StripPolicyTests.swift has the same cases. */
class StripPolicyTest {

    private val app = "com.google.android.apps.messaging"
    private val t0 = 1_800_000_000.0

    private fun typing(since: Double, midWord: Boolean = false, undo: Boolean = false, fix: Boolean = false) =
        StripPolicy.Typing(since, midWord, undo) { fix }

    @Test fun theNumbersAreTheDocs() {
        assertEquals(0.4, StripPolicy.SETTLE, 0.0)
        assertEquals(1.0, StripPolicy.MID_WORD_PAUSE, 0.0)
        assertEquals(8.0, StripPolicy.GAP, 0.0)
        assertEquals(2, StripPolicy.WORDS_PAST)
        assertEquals(1.0, StripPolicy.SEEN_FOR, 0.0)
        assertEquals(2, StripPolicy.IGNORES_PER_DISMISSAL)
        assertEquals(600.0, StripPolicy.APP_MUTE, 0.0)
        assertEquals(3, StripPolicy.BACKOFF_AFTER)
        assertEquals(86_400.0, StripPolicy.BACKOFF_WINDOW, 0.0)
        assertEquals(86_400.0, StripPolicy.BACKOFF, 0.0)
        assertEquals(180.0, StripPolicy.PASTE_FRESH, 0.0)
        assertEquals(48, StripPolicy.MAX_ENTRIES)
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

    @Test fun aDismissedChipNeverComesBackInThatField() {
        val p = StripPolicy()
        p.enter("doc1")
        p.dismissed(Kind.ANSWER, "calc|2+5 = 7", app, t0)
        assertFalse(p.allows(Kind.ANSWER, "calc|2+5 = 7", app, t0 + 86_400 * 3))
        p.enter("doc2")
        assertTrue(p.allows(Kind.ANSWER, "calc|2+5 = 7", app, t0 + StripPolicy.APP_MUTE + 1))
    }

    @Test fun aDismissalMutesThatKindInThatAppForTenMinutes() {
        val p = StripPolicy()
        p.dismissed(Kind.AI, "ai|1", app, t0)
        assertFalse(p.allows(Kind.ANSWER, "calc|x", app, t0 + 7))
        assertTrue(p.allows(Kind.ANSWER, "calc|x", app, t0 + 8))
        assertTrue(p.allows(Kind.AI, "ai|2", "com.whatsapp", t0 + 8))
        assertFalse(p.allows(Kind.AI, "ai|2", app, t0 + 599))
        assertTrue(p.allows(Kind.AI, "ai|2", app, t0 + 600))
    }

    @Test fun threeDismissalsInADayRestTheKindEverywhere() {
        val p = StripPolicy()
        p.dismissed(Kind.AI, "ai|1", "a", t0)
        p.dismissed(Kind.AI, "ai|2", "b", t0 + 3600)
        assertTrue(p.allows(Kind.AI, "ai|3", "c", t0 + 7200))
        p.dismissed(Kind.AI, "ai|3", "c", t0 + 7200)
        assertFalse(p.allows(Kind.AI, "ai|4", "d", t0 + 7200 + 3600))
        assertTrue(p.allows(Kind.ANSWER, "calc|x", "d", t0 + 7200 + 3600))
        assertTrue(p.allows(Kind.AI, "ai|4", "d", t0 + 7200 + 86_400))
        val q = StripPolicy()
        q.dismissed(Kind.PLAN, "p1", "a", t0)
        q.dismissed(Kind.PLAN, "p2", "a", t0 + 86_400)
        q.dismissed(Kind.PLAN, "p3", "b", t0 + 86_400 + 60)
        assertTrue(q.allows(Kind.PLAN, "p4", "c", t0 + 86_400 + 120))
    }

    @Test fun typingPastTwiceCountsAsOneDismissal() {
        val p = StripPolicy()
        p.shown(Kind.AI, "ai|q1", "what is the capital of france", t0)
        assertEquals(Seen.Nothing, p.observe("what is the capital of france and", app, t0 + 2))
        assertEquals(Seen.Ignored(Kind.AI), p.observe("what is the capital of france and its", app, t0 + 3))
        assertFalse(p.allows(Kind.AI, "ai|q1", app, t0 + 60))
        assertTrue(p.allows(Kind.AI, "ai|q2", app, t0 + 60))
        p.shown(Kind.AI, "ai|q2", "who won", t0 + 60)
        assertEquals(Seen.Ignored(Kind.AI), p.observe("who won the game", app, t0 + 62))
        assertFalse(p.allows(Kind.AI, "ai|q3", app, t0 + 120))
        assertTrue(p.allows(Kind.AI, "ai|q3", app, t0 + 62 + 600))
    }

    @Test fun aGlimpseOrAnEditIsNoVerdict() {
        val p = StripPolicy()
        p.shown(Kind.ANSWER, "a", "lets 10 inch", t0)
        assertEquals(Seen.Nothing, p.observe("lets 10 inch of snow", app, t0 + 0.5))
        assertNull(p.onScreen)
        assertTrue(p.allows(Kind.ANSWER, "a", app, t0 + 1))
        p.shown(Kind.ANSWER, "b", "2+5", t0)
        assertEquals(Seen.Nothing, p.observe("2+", app, t0 + 5))
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
        assertEquals(Seen.Nothing, p.observe("", app, t0 + 1))
        assertEquals(Seen.PasteIgnored, p.observe("h", app, t0 + 2))
        p.dismissed(Kind.PASTE, "paste|a", app, t0 + 10)
        assertFalse(p.allows(Kind.PASTE, "paste|a", app, t0 + 100))
        assertTrue(p.allows(Kind.PASTE, "paste|b", app, t0 + 18))
    }

    @Test fun codesAndPasswordsGetOnlyTheirChips() {
        for (kind in Kind.values()) {
            assertTrue(StripPolicy.allowed(kind, StripPolicy.Field.NORMAL))
            assertFalse(StripPolicy.allowed(kind, StripPolicy.Field.SECRET))
        }
        assertEquals(setOf(Kind.FILL, Kind.PASTE, Kind.MAIL),
            Kind.values().filter { StripPolicy.allowed(it, StripPolicy.Field.CODE) }.toSet())
    }

    @Test fun aMailIsNeverMuted() {
        val p = StripPolicy()
        for (i in 0 until 5) p.dismissed(Kind.MAIL, "mail|$i", app, t0 + i)
        assertTrue(p.allows(Kind.MAIL, "mail|9", app, t0 + 6))
        assertFalse(p.allows(Kind.MAIL, "mail|1", app, t0 + 6))
        assertTrue(p.mutes.isEmpty())
        assertTrue(p.backoffs.isEmpty())
        assertTrue(p.allows(Kind.ANSWER, "calc|x", app, t0 + 6))
    }

    @Test fun usingAChipStartsTheCountOver() {
        val p = StripPolicy()
        p.shown(Kind.ANSWER, "a1", "x", t0)
        assertEquals(Seen.Ignored(Kind.ANSWER), p.observe("x y z", app, t0 + 2))
        p.used(Kind.ANSWER, app)
        p.shown(Kind.ANSWER, "a2", "q", t0 + 20)
        assertEquals(Seen.Ignored(Kind.ANSWER), p.observe("q r s", app, t0 + 22))
        assertTrue(p.allows(Kind.ANSWER, "a3", app, t0 + 40))
    }

    @Test fun theStoreStaysSmallAndSurvivesARoundTrip() {
        val p = StripPolicy()
        for (i in 0 until 60) p.dismissed(Kind.AI, "ai|$i", "app$i", t0 + i * 30_000.0)
        assertTrue(p.mutes.size <= StripPolicy.MAX_ENTRIES)
        p.shown(Kind.ANSWER, "a", "a", t0)
        p.observe("a b c", "s", t0 + 2)
        val back = StripPolicy(JSONObject(p.json().toString()))
        assertEquals(p.mutes, back.mutes)
        assertEquals(p.backoffs, back.backoffs)
        assertEquals(p.refusals, back.refusals)
        assertEquals(p.softs.mapValues { it.value.first }, back.softs.mapValues { it.value.first })
        back.prune(t0 + 60 * 30_000.0 + 86_400 * 2)
        assertTrue(back.mutes.isEmpty())
        assertTrue(back.refusals.isEmpty())
        assertTrue(back.softs.isEmpty())
        assertNotNull(StripPolicy(null).json().opt("v"))
    }
}
