package com.arpit.glyf.ime.typing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS GlyfEngineTests.testRepeatedSentencesAreOfferedBack, line for line. */
class PhraseMemoryTest {
    @Test fun repeatedSentencesAreOfferedBack() {
        val m = PhraseMemory()
        val day = 20_000
        repeat(2) { m.record("On my way, be there in 10!", day) }
        assertNull(m.completion("on my ", day))
        m.record("on my way, be there in 10", day)
        assertEquals("way, be there in 10", m.completion("On my ", day))
        assertEquals("be there in 10", m.completion("ok. On my way, ", day))
        assertNull(m.completion("On my wa", day))
        assertNull(m.completion("On ", day))
        assertNull(m.completion("On my ", day + 61))
        val n = PhraseMemory()
        repeat(3) {
            n.record("your code is 482913 for login", day)
            n.record("see https://tryglyf.com for more", day)
            n.record("ok cool", day)
        }
        assertTrue(n.entries.isEmpty())
        assertEquals("On my way, be there soon!", PhraseMemory.endedSentence("Hi. On my way, be there soon! "))
        assertNull(PhraseMemory.endedSentence("On my way"))
        assertEquals("Running late today", PhraseMemory.lastSentence("Hi! Running late today"))
        // Saved and read back.
        val back = PhraseMemory.fromJson(m.toJson())
        assertEquals("way, be there in 10", back.completion("On my ", day))
    }
}
