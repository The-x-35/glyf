package com.arpit.glyf.ime

import com.arpit.glyf.ime.VoiceText.Commit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** How heard words go into a field: VoiceText.commit and friends. */
class VoiceTextTest {

    private fun commit(heard: String, before: String = "", after: String = "",
                       capitals: Boolean = true, english: Boolean = true) =
        VoiceText.commit(heard, before, after, capitals, english)

    // Spacing

    @Test fun anEmptyFieldTakesTheWordsAsTheyAre() =
        assertEquals(Commit("See you soon"), commit("see you soon"))

    @Test fun aSpaceFromTheWordBefore() =
        assertEquals(Commit(" and then lunch"), commit("and then lunch", before = "Coffee"))

    @Test fun noSecondSpaceAfterOneTyped() =
        assertEquals(Commit("and then lunch"), commit("and then lunch", before = "Coffee "))

    @Test fun noSpaceAfterANewLineOrAnOpeningBracket() {
        assertEquals(Commit("Dear Sam"), commit("dear Sam", before = "Hi\n"))
        assertEquals(Commit("maybe"), commit("maybe", before = "Lunch ("))
        assertEquals(Commit("quote"), commit("quote", before = "He said \"", capitals = false))
    }

    @Test fun aClosingQuoteIsAWordEnd() =
        assertEquals(Commit(" ok"), commit("ok", before = "she said \"hi\"", capitals = false))

    @Test fun aSpaceAfterWhenTheCursorSitsAgainstAWord() =
        assertEquals(Commit(" really ", 0), commit("really", before = "It is", after = "good"))

    @Test fun noSpaceAfterBeforeAMarkOrSpace() {
        assertEquals(Commit(" today"), commit("today", before = "See you", after = "."))
        assertEquals(Commit(" today"), commit("today", before = "See you", after = " then"))
    }

    @Test fun aMarkSaidFirstSitsAgainstTheWordBefore() {
        val c = commit("comma and then lunch", before = "Coffee ")
        assertEquals(Commit(", and then lunch", 1), c)
    }

    @Test fun blankWordsTypeNothing() = assertEquals("", commit("   ").text)

    @Test fun runsOfSpacesInWhatWasHeardBecomeOne() =
        assertEquals(Commit("Call me at noon"), commit("call  me \t at noon"))

    // Capitals

    @Test fun aCapitalAfterASentenceEnds() {
        assertEquals(Commit("How are you"), commit("how are you", before = "Hi. "))
        assertEquals(Commit(" How are you"), commit("how are you", before = "Hi."))
        assertEquals(Commit("Sure"), commit("sure", before = "Really? "))
        assertEquals(Commit("Yes"), commit("yes", before = "Great!\" "))
    }

    @Test fun noCapitalMidSentence() =
        assertEquals(Commit(" and then lunch"), commit("And then lunch", before = "Coffee"))

    @Test fun aNameKeepsItsCapitalMidSentence() {
        assertEquals(Commit(" Paris in May"), commit("Paris in May", before = "We fly to"))
        assertEquals(Commit(" I think so"), commit("I think so", before = "Yes"))
        assertEquals(Commit(" NASA called"), commit("NASA called", before = "Guess what"))
    }

    @Test fun aNumbersFullStopOrAnAbbreviationIsNoSentenceEnd() {
        assertFalse(VoiceText.sentenceStart("version 3."))
        assertFalse(VoiceText.sentenceStart("bring snacks, e.g. "))
        assertTrue(VoiceText.sentenceStart("Done. "))
        assertTrue(VoiceText.sentenceStart(""))
        assertTrue(VoiceText.sentenceStart("Hi\n"))
        assertFalse(VoiceText.sentenceStart("Hi "))
    }

    @Test fun aFieldWithoutCapitalsGetsTheWordsAsHeard() {
        assertEquals(Commit("hello there"), commit("hello there", capitals = false))
        assertEquals(Commit(" And then"), commit("And then", before = "x", capitals = false))
    }

    @Test fun aCapitalAtEverySentenceInsideWhatWasSaid() =
        assertEquals(Commit("I'm late. Start without me"), commit("I'm late. start without me"))

    // Spoken punctuation (Gboard's phrases)

    @Test fun spokenMarksBecomeMarks() {
        assertEquals("see you soon.", VoiceText.spokenPunctuation("see you soon period", true))
        assertEquals("yes, please", VoiceText.spokenPunctuation("yes comma please", true))
        assertEquals("are you in?", VoiceText.spokenPunctuation("are you in question mark", true))
        assertEquals("wow!", VoiceText.spokenPunctuation("wow exclamation point", true))
        assertEquals("done. next", VoiceText.spokenPunctuation("done full stop next", true))
        assertEquals("hi\nthere", VoiceText.spokenPunctuation("hi new line there", true))
        assertEquals("one\n\ntwo", VoiceText.spokenPunctuation("one new paragraph two", true))
    }

    @Test fun spokenMarksCommitWithCapitals() =
        assertEquals(Commit("Hi Sam. How are you?"), commit("hi Sam period how are you question mark"))

    @Test fun aRecognizerThatPunctuatesKeepsTheWord() =
        assertEquals("The period ended.", VoiceText.spokenPunctuation("The period ended.", true))

    @Test fun otherLanguagesAreLeftAlone() =
        assertEquals("ciao period", VoiceText.spokenPunctuation("ciao period", false))

    @Test fun wordsThatOnlyContainAMarkWordStay() =
        assertEquals("periodically commas", VoiceText.spokenPunctuation("periodically commas", true))

    // Polish

    @Test fun polishedWordsLoseTheModelsQuotes() =
        assertEquals("See you at five.", VoiceText.polished("um see you at five", "\"See you at five.\""))

    @Test fun polishedKeepsAMidSentenceStartSmall() =
        assertEquals("so we meet at noon.", VoiceText.polished("so uh we meet at noon", "So we meet at noon."))

    @Test fun polishedKeepsANewFirstWordAsWritten() =
        assertEquals("We meet at noon.", VoiceText.polished("um we meet at noon", "We meet at noon."))

    @Test fun anEmptyPolishKeepsTheOriginal() =
        assertEquals("keep this", VoiceText.polished("keep this", "  "))
}
