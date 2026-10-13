package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS GlyfEngineTests.testEverydayPhrasesInOtherLanguages, line for line. */
class PhrasesTest {
    private fun q(t: String) = Smart.quickAnswer(t, region = "US")?.results

    @Test fun everydayPhrases() {
        assertEquals(listOf("gracias"), q("thank you in spanish"))
        assertEquals(listOf("おやすみなさい"), q("how do you say good night in japanese"))
        assertEquals(listOf("prost!"), q("whats cheers in german"))
        assertEquals(listOf("merci"), q("thanks in french"))
        assertEquals(listOf("gracias"), q("ok thank you in spanish"))
        assertEquals("thank you in spanish", Phrases.phraseIn("ok thank you in spanish")?.source)
        assertEquals(Smart.Insertion.REPLACE, Phrases.phraseIn("thank you in spanish")?.how(0))
        assertNull(q("i love you in hindi"))
        assertNull(q("the meeting in spanish"))
        assertNull(q("i live in spain"))
    }
}
