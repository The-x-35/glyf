package com.demo.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The same steps as the iOS TourCoach tests: both keyboards coach alike. */
class TourCoachTest {
    private val home = Smart.Field("address", "Home", "12 Hill Road, Bandra")

    @Test fun mapsSearchLikeTheWebsite() {
        var s = TourCoach.State(step = "sakshi:0", text = "")
        assertEquals(TourCoach.Coach("search", "Search"), TourCoach.coach(s))
        s = s.copy(panel = TourCoach.Panel.Search("web", TourCoach.SearchView.Landing(0), ""))
        assertEquals(TourCoach.Coach("search:tab:maps", "Maps"), TourCoach.coach(s))
        s = s.copy(panel = TourCoach.Panel.Search("maps", TourCoach.SearchView.Typing, "coffee near me"))
        assertEquals(TourCoach.Coach("search:go", "Search"), TourCoach.coach(s))
        s = s.copy(panel = TourCoach.Panel.Search("maps", TourCoach.SearchView.Results(4), "coffee near me"))
        assertEquals(TourCoach.Coach("search:card:*", "Tap to share"), TourCoach.coach(s))
        assertNull(TourCoach.coach(s.copy(panel = TourCoach.Panel.None, text = "📍 Blue Tokai · Bandra")))
    }

    @Test fun throughTheMenuWhenTheToolIsOffTheStrip() {
        var s = TourCoach.State(step = "kabir:0", text = "", stripTools = emptySet())
        assertEquals(TourCoach.Coach("toolbar:glyf", "Tap g"), TourCoach.coach(s))
        s = s.copy(panel = TourCoach.Panel.Menu)
        assertEquals(TourCoach.Coach("shell:tile:search", "Search"), TourCoach.coach(s))
        assertEquals(false, TourCoach.allowsChip("paste", "sakshi:0"))
        assertEquals(true, TourCoach.allowsChip("vault:upi", "zoya:1"))
        assertEquals(false, TourCoach.allowsChip("paste", "semi:0"))
        assertEquals(true, TourCoach.allowsChip("paste", "semi:0", copied = true))
    }

    @Test fun vaultOpensOnWhicheverKeyHoldsIt() {
        var s = TourCoach.State(step = "mumma:0", text = "",
            fields = listOf(Smart.Field("name", "Name", "Arpit"), home), vaultKey = "v")
        assertEquals(TourCoach.Coach("key:v", "Hold V"), TourCoach.coach(s))
        assertEquals(TourCoach.Coach("key:q", "Hold Q"), TourCoach.coach(s.copy(vaultKey = "q")))
        s = s.copy(panel = TourCoach.Panel.Vault)
        assertEquals(TourCoach.Coach("vault:card:1", "Tap Home"), TourCoach.coach(s))
        assertNull(TourCoach.coach(s.copy(panel = TourCoach.Panel.None, text = "12 Hill Road, Bandra")))
    }

    @Test fun hinglishSuggestions() {
        val s = TourCoach.State(step = "rohan:0", text = "haan yaar pakak",
            suggestions = listOf("pakak", "pakka", "pakad"))
        assertEquals(TourCoach.Coach("suggest:1", "Tap pakka"), TourCoach.coach(s))
        assertEquals(TourCoach.Coach("suggest:1", "Tap definitely"), TourCoach.coach(
            s.copy(text = "haan yaar pakka definately", suggestions = listOf("definately", "definitely"))))
    }

    @Test fun rewriteMathAndTranslate() {
        val neha = TourCoach.State(step = "neha:0", text = "ya ill send it by 6 dont worry")
        assertEquals(TourCoach.Coach("key:space", "Hold glyf"), TourCoach.coach(neha))
        assertNull(TourCoach.coach(neha.copy(panel = TourCoach.Panel.Act(working = true, options = false))))
        assertEquals(TourCoach.Coach("act:option:work", "Professional"),
            TourCoach.coach(neha.copy(panel = TourCoach.Panel.Act(working = false, options = true))))

        assertEquals(TourCoach.Coach("strip:smart", "Tap"),
            TourCoach.coach(TourCoach.State(step = "zoya:0", text = "3480/4", chip = "calc")))

        val sofia = TourCoach.State(step = "sofia:0", text = "", translateKey = "t")
        assertEquals(TourCoach.Coach("key:t", "Hold T"), TourCoach.coach(sofia))
        val open = sofia.copy(panel = TourCoach.Panel.Translate(ready = false, target = null))
        assertEquals("see you tomorrow", TourCoach.autotype(open))
        assertEquals(TourCoach.Coach("hud:replace", "Replace"), TourCoach.coach(
            open.copy(text = "see you tomorrow", panel = TourCoach.Panel.Translate(ready = true, target = "Spanish"))))
    }
}
