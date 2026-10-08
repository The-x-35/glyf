package com.arpit.glyf.ime.typing

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Runs shared/typing/golden-cases.json — the same cases RunnerTests runs on
 *  iOS — plus the pieces underneath. */
class TypingEngineTest {

    private val today = 20_000

    private val sharedDir: File by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/typing/golden-cases.json").exists()) dir = dir.parentFile
        File(requireNotNull(dir) { "shared/typing not found above ${System.getProperty("user.dir")}" }, "shared/typing")
    }

    private fun goldenTrie(): GlydTrie =
        requireNotNull(GlydTrie.mapped(File(sharedDir, "golden.glyd"))) {
            "compile it: python3 tools/build_dictionary.py shared/typing/golden.combined shared/typing/golden.glyd"
        }

    private fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }

    @Test fun goldenCases() {
        val failures = runCases(File(sharedDir, "golden-cases.json"), goldenTrie())
        assertTrue("\n" + failures.joinToString("\n"), failures.isEmpty())
    }

    /** The same expectations on the dictionary the keyboards ship. */
    @Test fun realDictionaryCases() {
        val repo = sharedDir.parentFile.parentFile
        val dict = File(repo, "app/dict/en.glyd")
        org.junit.Assume.assumeTrue("app/dict/en.glyd not built", dict.exists())
        val failures = runCases(File(sharedDir, "real-cases.json"), GlydTrie.mapped(dict)!!, File(repo, "app/assets/vocab/packs.json"))
        assertTrue("\n" + failures.joinToString("\n"), failures.isEmpty())
    }

    /** A word typed in full offers its completions, not its neighbours (iOS twin). */
    @Test fun aKnownWordOffersCompletionsNotNeighbours() {
        val repo = sharedDir.parentFile.parentFile
        val dict = File(repo, "app/dict/en.glyd")
        org.junit.Assume.assumeTrue("app/dict/en.glyd not built", dict.exists())
        val engine = TypingEngine(GlydTrie.mapped(dict)!!)
        val noon = engine.suggestions("noon", previous = "at", sentenceStart = false)
        assertTrue(noon.known)
        assertTrue("${noon.alternatives}", "moon" !in noon.alternatives)
        val the = engine.suggestions("the", previous = "at", sentenceStart = false)
        assertTrue("${the.alternatives}", the.alternatives.all { it.lowercase().startsWith("the") })
        val its = engine.suggestions("its", previous = "think", sentenceStart = false)
        assertTrue("${its.alternatives}", "it's" in its.alternatives)
        val thier = engine.suggestions("thier", previous = "at", sentenceStart = false)
        assertEquals("their", thier.autocorrect)
        assertTrue(thier.alternatives.isNotEmpty())
    }

    /** Pack words and phrases by id, split the way the keyboards load them. */
    private fun packContent(packsFile: File?, ids: List<String>): Pair<List<String>, List<String>> {
        if (packsFile == null || ids.isEmpty()) return emptyList<String>() to emptyList()
        val packs = JSONObject(packsFile.readText()).getJSONArray("packs")
        val words = ArrayList<String>()
        val phrases = ArrayList<String>()
        for (i in 0 until packs.length()) {
            val pack = packs.getJSONObject(i)
            if (pack.getString("id") !in ids) continue
            pack.optJSONArray("words")?.strings()?.forEach { e ->
                words.addAll(e.split(' ').filter { it.isNotEmpty() }); if (' ' in e) phrases.add(e)
            }
            pack.optJSONArray("phrases")?.strings()?.forEach { p ->
                words.addAll(p.split(' ').filter { it.isNotEmpty() }); phrases.add(p)
            }
        }
        return words to phrases
    }

    private fun runCases(file: File, trie: GlydTrie, packsFile: File? = null): List<String> {
        val root = JSONObject(file.readText())
        val rowPitch = root.optDouble("rowPitch", 1.44).toFloat()
        val cases = root.getJSONArray("cases")
        val failures = ArrayList<String>()

        for (ci in 0 until cases.length()) {
            val c = cases.getJSONObject(ci)
            val name = c.optString("name")
            val engine = TypingEngine(trie, geometry = KeyGeometry(rowPitch))
            val state = c.optJSONObject("state") ?: JSONObject()
            val lexicon = PersonalLexicon()
            state.optJSONArray("learned")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val item = arr.getJSONArray(i)
                    repeat(item.getInt(1)) { lexicon.commit(item.getString(0), null, today) }
                }
            }
            state.optJSONArray("pairs")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val item = arr.getJSONArray(i)
                    repeat(item.getInt(2)) { lexicon.commit(item.getString(1), item.getString(0), today) }
                }
            }
            state.optJSONArray("kept")?.strings()?.forEach { lexicon.keep(it, today) }
            state.optJSONArray("rejected")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val item = arr.getJSONArray(i)
                    // A revert keeps the typed word too; without "kept" the case tests the block alone.
                    if (state.has("kept")) lexicon.revert(item.getString(0), item.getString(1), today)
                    else lexicon.reject(item.getString(0), item.getString(1))
                }
            }
            // Removed in the app's "My words".
            state.optJSONArray("forgotten")?.strings()?.forEach { lexicon.forget(it) }
            state.optJSONArray("addedWords")?.strings()?.forEach { lexicon.add(it, today) }
            engine.replacePersonal(lexicon)
            engine.setPackWords(state.optJSONArray("packWords")?.strings() ?: emptyList())
            engine.setContacts(state.optJSONArray("contacts")?.strings() ?: emptyList())
            engine.setPackPhrases(state.optJSONArray("packPhrases")?.strings() ?: emptyList())
            state.optJSONArray("packs")?.strings()?.let { ids ->
                val (words, phrases) = packContent(packsFile, ids)
                engine.setPackWords(words)
                engine.setPackPhrases(phrases)
            }

            val policyJson = c.optJSONObject("policy") ?: JSONObject()
            var policy = TypingEngine.ALL
            if (policyJson.has("autocorrect") && !policyJson.getBoolean("autocorrect")) policy = policy and TypingEngine.AUTOCORRECT.inv()
            if (policyJson.has("suggestions") && !policyJson.getBoolean("suggestions")) policy = policy and TypingEngine.SUGGESTIONS.inv()
            if (policyJson.has("learning") && !policyJson.getBoolean("learning")) policy = policy and TypingEngine.LEARNING.inv()

            val typed = c.optString("typed", "")
            val previous = if (c.has("previous")) c.getString("previous") else null
            val beforePrevious = if (c.has("beforePrevious")) c.getString("beforePrevious") else null
            val expect = c.optJSONObject("expect") ?: JSONObject()

            if (typed.isEmpty()) {
                val predictions = engine.predictions(previous, policy, today, beforePrevious)
                expect.optJSONArray("predictionsInclude")?.strings()?.forEach {
                    if (it !in predictions) failures.add("$name: predictions $predictions lack $it")
                }
                continue
            }

            val touches = c.optJSONArray("touches")?.let { arr ->
                (0 until arr.length()).map { i -> arr.getJSONArray(i).let { floatArrayOf(it.getDouble(0).toFloat(), it.getDouble(1).toFloat()) } }
            }
            val s = engine.suggestions(typed, touches, previous, c.optBoolean("sentenceStart", false), policy, today,
                beforePrevious)
            if (expect.has("autocorrect")) {
                val want = if (expect.isNull("autocorrect")) null else expect.getString("autocorrect")
                if (s.autocorrect != want) failures.add("$name: autocorrect ${s.autocorrect} ≠ $want (alternatives ${s.alternatives})")
            }
            expect.optJSONArray("autocorrectNot")?.strings()?.forEach {
                if (s.autocorrect == it) failures.add("$name: autocorrected to $it")
            }
            if (expect.has("known") && expect.getBoolean("known") != s.known) failures.add("$name: known ${s.known}")
            val offered = s.alternatives + listOfNotNull(s.autocorrect)
            expect.optJSONArray("alternativesInclude")?.strings()?.forEach {
                if (it !in offered) failures.add("$name: $offered lack $it")
            }
            expect.optJSONArray("alternativesExclude")?.strings()?.forEach {
                if (it in offered) failures.add("$name: $offered include $it")
            }
            if (expect.has("alternativesMax") && s.alternatives.size > expect.getInt("alternativesMax")) {
                failures.add("$name: ${s.alternatives.size} alternatives")
            }
            if (expect.has("alternativesFirst") && s.alternatives.firstOrNull() != expect.getString("alternativesFirst")) {
                failures.add("$name: first alternative ${s.alternatives.firstOrNull()} ≠ ${expect.getString("alternativesFirst")}")
            }
        }
        return failures
    }

    @Test fun builtTrieReadsLikeTheCompiledOne() {
        val trie = GlydTrie.build(listOf(
            GlydTrie.Word("Zomato", 160), GlydTrie.Word("zoom", 120),
            GlydTrie.Word("it's", 200), GlydTrie.Word("its", 180),
        ))
        val node = trie.node("its")
        assertEquals(2, trie.entryCount(node))
        assertEquals("it's", trie.form(trie.firstEntry(node)))
        val z = trie.node("zomato")
        assertEquals("Zomato", trie.form(trie.firstEntry(z)))
        assertTrue(trie.flags(trie.firstEntry(z)) and GlydTrie.FLAG_HAS_UPPER != 0)
        assertEquals(200, trie.maxProbability(0))
        assertEquals(GlydTrie.NONE, trie.node("zz"))
    }

    @Test fun compiledDictionaryHasWhitelistsAndBigrams() {
        val trie = goldenTrie()
        val dont = trie.node("dont")
        assertEquals("don't", trie.form(trie.firstEntry(dont)))
        assertTrue(trie.flags(trie.firstEntry(dont)) and GlydTrie.FLAG_WHITELIST != 0)
        val thank = trie.node("thank")
        assertEquals(listOf("you"), trie.bigrams(trie.firstEntry(thank)).map { trie.form(it.first) })
    }

    /** Words inside a link, an email or a handle are not corrected or
     *  learned ("youtu" of youtu.be became "youth" in S226). */
    @Test fun nothingInsideALinkOrAnAddressIsCorrected() {
        assertTrue(com.arpit.glyf.ime.typing.WordContext.insideLinkOrAddress("check https://youtu"))
        assertTrue(com.arpit.glyf.ime.typing.WordContext.insideLinkOrAddress("mail me at sam@gmial"))
        assertTrue(com.arpit.glyf.ime.typing.WordContext.insideLinkOrAddress("ask @arpit"))
        assertTrue(com.arpit.glyf.ime.typing.WordContext.insideLinkOrAddress("go to www.exampel"))
        assertFalse(com.arpit.glyf.ime.typing.WordContext.insideLinkOrAddress("i saw the youtu"))
        assertFalse(com.arpit.glyf.ime.typing.WordContext.insideLinkOrAddress("https://x.com great"))
    }

    @Test fun editDistanceAndKeys() {
        assertEquals(1, TypingText.editDistance(TypingText.scalars("teh"), TypingText.scalars("the")))
        assertEquals(1, TypingText.editDistance(TypingText.scalars("arpit"), TypingText.scalars("armpit")))
        assertEquals(2, TypingText.editDistance(TypingText.scalars("glyf"), TypingText.scalars("glyph")))
        assertEquals("dont", TypingText.key("Don’t"))
        assertEquals("followup", TypingText.key("Follow-up"))
        assertEquals('e'.code, TypingText.base('É'.code))
        assertEquals("The", TypingText.matchCase("Teh", "the"))
        assertEquals("Pune", TypingText.matchCase("pune", "Pune"))
    }

    @Test fun learningAndForgetting() {
        val lexicon = PersonalLexicon()
        lexicon.commit("glyf", null, today)
        assertFalse(lexicon.isKnown("glyf"))
        lexicon.commit("glyf", "try", today)
        assertTrue(lexicon.isKnown("glyf"))
        assertEquals(111.3f, lexicon.probability("glyf", today)!!, 0.5f)
        lexicon.commit("glyf", null, today)
        assertEquals(119.9f, lexicon.probability("glyf", today)!!, 0.5f)
        assertTrue(lexicon.probability("glyf", today + 400)!! < 111f)
        assertTrue(lexicon.isKnown("glyf"))
        lexicon.forget("glyf")
        assertFalse(lexicon.isKnown("glyf"))
        lexicon.commit("glyf", null, today)
        lexicon.commit("glyf", null, today)
        assertFalse(lexicon.isKnown("glyf"))
    }

    @Test fun lexiconSurvivesJson() {
        val lexicon = PersonalLexicon()
        repeat(3) { lexicon.commit("chai", null, today) }
        repeat(2) { lexicon.commit("pe", "chai", today) }
        lexicon.revert("teh", "the", today)
        lexicon.forget("damn")
        val copy = PersonalLexicon.fromJson(JSONObject(lexicon.toJson().toString()))
        assertEquals(lexicon.toJson().toString(), copy.toJson().toString())
        assertTrue(copy.isRejected("teh", "the"))
        assertTrue(copy.isBlocked("damn"))
        assertNotNull(copy.pairProbability("chai", "pe", today))
    }

    @Test fun revertBlocksThePairAndUnlearnsTheCorrection() {
        val engine = TypingEngine(goldenTrie())
        assertEquals("the", engine.suggestions("teh", null, null, false, TypingEngine.ALL, today).autocorrect)
        engine.commit("the", null, false, TypingEngine.ALL, today)
        engine.revert("teh", "the", today)
        val again = engine.suggestions("teh", null, null, false, TypingEngine.ALL, today)
        assertNull(again.autocorrect)
        assertTrue(again.known)
        assertNull(engine.personal.word("the"))
    }

    @Test fun autoCapitalizedFirstWordIsLearnedLowercase() {
        val engine = TypingEngine(goldenTrie())
        engine.commit("Hello", null, true, TypingEngine.ALL, today)
        assertEquals("hello", engine.personal.word("hello")?.form)
        engine.commit("Arpit", null, true, TypingEngine.ALL, today)
        assertEquals("Arpit", engine.personal.word("arpit")?.form)
    }

    @Test fun nothingIsLearnedWhereLearningIsOff() {
        val engine = TypingEngine(goldenTrie())
        engine.commit("secretword", null, false, TypingEngine.SUGGESTIONS, today)
        engine.commit("4242424242424242", null, false, TypingEngine.ALL, today)
        engine.commit("me@glyf.so", null, false, TypingEngine.ALL, today)
        assertTrue(engine.personal.words.isEmpty())
    }

    @Test fun learnedWordsBecomeSearchable() {
        val engine = TypingEngine(goldenTrie())
        repeat(3) { engine.commit("Zomato", null, false, TypingEngine.ALL, today) }
        val s = engine.suggestions("zomat", null, null, false, TypingEngine.ALL, today)
        assertTrue(s.toString(), "Zomato" in s.alternatives + listOfNotNull(s.autocorrect))
    }
}
