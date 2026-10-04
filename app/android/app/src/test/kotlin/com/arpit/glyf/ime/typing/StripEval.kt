package com.arpit.glyf.ime.typing

import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.random.Random

/**
 * How good the strip is on real sentences the dictionary's word pairs never
 * saw (tools/typing/build_ngrams.py holds one Tatoeba sentence in ten out).
 * Off unless asked for:
 *
 *   GLYF_EVAL_SENTENCES=~/.cache/glyf-typing/heldout.txt GLYF_EVAL_DICT=app/dict/en.glyd \
 *   GLYF_EVAL_N=2000 ./gradlew :app:testDebugUnitTest --tests '*StripEval*' -i
 *
 * What the strip shows beside the typed word is two words: the fix and one
 * more, or two more (GlyfIME.updateSuggestions). "Seen" means in those two.
 */
class StripEval {
    private val rows = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
    private val neighbours: Map<Char, List<Char>> = run {
        val pos = HashMap<Char, Pair<Int, Float>>()
        rows.forEachIndexed { r, row -> row.forEachIndexed { c, ch -> pos[ch] = r to (c + r * 0.5f) } }
        pos.keys.associateWith { a ->
            val (ra, xa) = pos[a]!!
            pos.filter { (b, p) -> b != a && Math.abs(p.first - ra) <= 1 && Math.abs(p.second - xa) <= 1.01f }.keys.toList()
        }
    }

    private var lastKind = ""
    private val kindNames = listOf("substitution", "omission", "transposition", "insertion")

    private fun typo(word: String, rnd: Random): String? {
        val letters = word.filter { it.isLetter() }.lowercase()
        if (letters.length < 3) return null
        if (word.contains('\'') && rnd.nextInt(3) == 0) { lastKind = "apostrophe"; return word.replace("'", "").lowercase() }
        val i = rnd.nextInt(1, letters.length)          // never the first letter
        val ch = letters[i]
        val kind = rnd.nextInt(4)
        lastKind = kindNames[kind]
        return when (kind) {
            0 -> neighbours[ch]?.randomOrNull(rnd)?.let { letters.substring(0, i) + it + letters.substring(i + 1) }
            1 -> letters.removeRange(i, i + 1)
            2 -> if (i < letters.length - 1) letters.substring(0, i) + letters[i + 1] + letters[i] + letters.substring(i + 2) else null
            else -> neighbours[ch]?.randomOrNull(rnd)?.let { letters.substring(0, i) + it + letters.substring(i) }
        }?.takeIf { it != letters }
    }

    private val token = Regex("[A-Za-z]+(?:['’][A-Za-z]+)*|\\S")

    private fun runs(sentence: String): List<List<String>> {
        val out = ArrayList<List<String>>()
        var run = ArrayList<String>()
        for (m in token.findAll(sentence.replace('’', '\''))) {
            val t = m.value
            if (t[0].isLetter()) run.add(t) else { if (run.isNotEmpty()) out.add(run); run = ArrayList() }
        }
        if (run.isNotEmpty()) out.add(run)
        return out
    }

    private class Tally(val name: String) {
        var n = 0; var hit = 0
        fun add(ok: Boolean) { n++; if (ok) hit++ }
        override fun toString() = "%-34s %6.1f%%  (%d of %d)".format(name, 100.0 * hit / maxOf(n, 1), hit, n)
    }

    @Test fun report() {
        val sentencesPath = System.getenv("GLYF_EVAL_SENTENCES")?.replace("~", System.getProperty("user.home"))
        assumeTrue(sentencesPath != null && File(sentencesPath).exists())
        var root: File? = File(System.getProperty("user.dir")).absoluteFile
        while (root != null && !File(root, "app/dict").exists()) root = root.parentFile
        val dictPath = System.getenv("GLYF_EVAL_DICT") ?: "app/dict/en.glyd"
        val dict = File(dictPath).takeIf { it.isAbsolute } ?: File(root, dictPath)
        val engine = TypingEngine(GlydTrie.mapped(dict))
        val limit = System.getenv("GLYF_EVAL_N")?.toIntOrNull() ?: 2000
        val sentences = File(sentencesPath!!).readLines().filter { it.isNotBlank() }.take(limit)
        val rnd = Random(42)
        val sample = Random(7)   // picks examples without moving the typos' stream

        val next = Tally("next word in the 3 predictions")
        val after = (1..3).map { Tally("after $it letter(s): in the 2 shown") }
        val fixed = Tally("typo: autocorrected to the word")
        val offered = Tally("typo: fixed or shown")
        val wrong = Tally("correct word changed by autocorrect")
        val misfixed = Tally("typo: autocorrected to another word")
        val examples = ArrayList<String>()
        val heldBack = java.util.TreeMap<String, Int>()
        val heldExamples = HashMap<String, MutableList<String>>()
        val misfixExamples = ArrayList<String>()
        val wrongExamples = ArrayList<String>()
        val byKind = java.util.TreeMap<String, Tally>()
        val kindHeld = java.util.TreeMap<String, Int>()
        val kindExamples = HashMap<String, MutableList<String>>()

        for (sentence in sentences) {
            for (run in runs(sentence)) {
                for ((i, word) in run.withIndex()) {
                    val prev = if (i > 0) run[i - 1] else null
                    // GLYF_EVAL_ONE_WORD=1: the previous word alone, as before word triples.
                    val prev2 = if (i > 1 && System.getenv("GLYF_EVAL_ONE_WORD") == null) run[i - 2] else null
                    val start = i == 0
                    val target = word.lowercase()
                    // Names are left out: the pairs never predict them, and the
                    // test sentences are full of "Tom" and "Mary".
                    val name = word.any { it.isUpperCase() } && !start && word != "I" && !word.startsWith("I'")
                    if (name) continue
                    if (prev != null) next.add(engine.predictions(prev, TypingEngine.ALL, TypingText.day(), prev2).any { it.lowercase() == target })
                    for (k in 1..3) {
                        val letters = word.filter { it.isLetter() }
                        if (letters.length <= k) continue
                        val typed = letters.substring(0, k).let { if (word == "I" || word.startsWith("I'")) it else it.lowercase() }
                        val s = engine.suggestions(typed, null, prev, start, TypingEngine.ALL, TypingText.day(), prev2)
                        val shown = (listOfNotNull(s.autocorrect) + s.alternatives).take(2)
                        after[k - 1].add(shown.any { it.lowercase() == target })
                    }
                    val asTyped = if (start || word == "I" || word.startsWith("I'")) word else word.lowercase()
                    if (asTyped.length >= 2 && !word.any { it.isUpperCase() && word != "I" && !word.startsWith("I'") && !start }) {
                        val s = engine.suggestions(asTyped, null, prev, start, TypingEngine.ALL, TypingText.day(), prev2)
                        val changed = s.autocorrect != null && s.autocorrect.lowercase() != asTyped.lowercase()
                        wrong.add(changed)
                        if (changed) wrongExamples.add("WRONG  '${prev ?: ""} $asTyped' -> ${s.autocorrect}")
                    }
                    if (word.any { it.isUpperCase() } && !start && word != "I" && !word.startsWith("I'")) continue
                    val t = typo(word, rnd) ?: continue
                    val s = engine.suggestions(t, null, prev, start, TypingEngine.ALL, TypingText.day(), prev2)
                    val ok = s.autocorrect?.lowercase() == target
                    fixed.add(ok)
                    byKind.getOrPut(lastKind) { Tally("typo ($lastKind): autocorrected") }.add(ok)
                    if (!ok && lastKind == System.getenv("GLYF_EVAL_KIND")) {
                        val why = if (s.autocorrect != null) "misfix" else engine.lastHeldBack ?: "none"
                        kindHeld[why] = (kindHeld[why] ?: 0) + 1
                        val shown0 = (listOfNotNull(s.autocorrect) + s.alternatives).take(2)
                        val list = kindExamples.getOrPut(why) { ArrayList() }
                        if (list.size < 14) list.add("'${prev ?: ""} $t'(${word})->${s.autocorrect ?: ""}${shown0}")
                    }
                    misfixed.add(s.autocorrect != null && !ok)
                    if (s.autocorrect != null && !ok && misfixExamples.size < 40) misfixExamples.add("'${prev ?: ""} $t' (meant $word) -> ${s.autocorrect}")
                    val shown = (listOfNotNull(s.autocorrect) + s.alternatives).take(2)
                    offered.add(ok || shown.any { it.lowercase() == target })
                    if (s.autocorrect == null && shown.firstOrNull()?.lowercase() == target) {
                        val why = engine.lastHeldBack ?: "none"
                        heldBack[why] = (heldBack[why] ?: 0) + 1
                        val list = heldExamples.getOrPut(why) { ArrayList() }
                        if (list.size < 10) list.add("'${prev ?: ""} $t'->${shown}")
                    }
                    if (!ok && examples.size < 60 && sample.nextInt(8) == 0) {
                        val what = if (s.autocorrect != null) "MISFIX" else "MISS  "
                        examples.add("$what '${prev ?: ""} $t' (meant $word) -> auto=${s.autocorrect} shown=$shown")
                    }
                }
            }
        }
        println("EVAL dictionary ${dict.name}, ${sentences.size} sentences")
        for (t in listOf(next) + after + listOf(fixed, offered, misfixed, wrong) + byKind.values) println("EVAL $t")
        heldBack.entries.sortedByDescending { it.value }.forEach { println("EVAL held back (top word right): ${it.key} ${it.value}") }
        heldExamples.forEach { (k, v) -> println("EVAL eg $k: ${v.joinToString("  ")}") }
        misfixExamples.forEach { println("EVAL misfix $it") }
        wrongExamples.forEach { println("EVAL $it") }
        kindHeld.entries.sortedByDescending { it.value }.forEach { println("EVAL kind-miss ${it.key} ${it.value}: ${kindExamples[it.key]?.joinToString("  ")}") }
    }
}
