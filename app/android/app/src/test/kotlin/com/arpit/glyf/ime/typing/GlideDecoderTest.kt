package com.arpit.glyf.ime.typing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Glide typing's decoder against the dictionary the keyboard ships: the 500
 * likeliest words glided by a believable synthetic finger (Arpit,
 * 2026-10-07: "its guesses needs to be perfect too"), the named cases, and
 * how long a decode takes. RunnerTests/GlideDecoderTests.swift's twin, held
 * to the same numbers.
 */
class GlideDecoderTest {

    companion object {
        private var cached: GlideDecoder? = null

        private fun repo(): File {
            var dir: File? = File(System.getProperty("user.dir")).absoluteFile
            while (dir != null && !File(dir, "app/dict/en.glyd").exists()) dir = dir.parentFile
            return dir ?: File(".")
        }

        fun decoder(): GlideDecoder {
            cached?.let { return it }
            val dict = File(repo(), "app/dict/en.glyd")
            assumeTrue("app/dict/en.glyd not built", dict.exists())
            return GlideDecoder(GlydTrie.mapped(dict)!!).also { cached = it }
        }

        /**
         * The letters as GlyfKeyboardView.layoutKeys places them on a phone
         * [widthDp] wide: 6.5 dp margins, 6 dp gaps, ten columns; the middle
         * row centred, the bottom row after a 1.5-column shift; rows as tall
         * as GlyfKeyboardView.rowPitchDp makes them (54, easing to 56 from
         * 402 dp). In key widths.
         */
        fun layout(widthDp: Float, rows: List<String> = KeyGeometry.ROWS): GlideDecoder.Layout {
            val margin = 6.5f
            val gap = 6f
            val pitch = (widthDp - 2 * margin + gap) / 10f
            val rowH = 54f + 2f * ((widthDp - 402f) / 12f).coerceIn(0f, 1f)
            val keys = ArrayList<Triple<Char, Float, Float>>()
            // Each row centred in the ten columns (QWERTY: 0, 0.5, 1.5).
            val starts = rows.map { (10 - it.length) / 2f }
            rows.forEachIndexed { r, row ->
                row.forEachIndexed { c, ch ->
                    if (ch !in 'a'..'z') return@forEachIndexed
                    val x = margin + (starts[r] + c) * pitch + (pitch - gap) / 2f
                    keys.add(Triple(ch, x, (r + 0.5f) * rowH))
                }
            }
            return GlideDecoder.Layout.of(keys, pitch)!!
        }
    }

    // Synthetic finger

    class SplitMix64(private var state: Long) {
        fun next(): Long {
            state += -0x61c8864680b583ebL // 0x9E3779B97F4A7C15
            var z = state
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L // 0xBF58476D1CE4E5B9
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L // 0x94D049BB133111EB
            return z xor (z ushr 31)
        }
        fun unit(): Float = (next() ushr 40).toFloat() / (1 shl 24).toFloat()
        fun gaussian(): Float {
            val u1 = max(unit(), 1e-7f); val u2 = unit()
            return sqrt(-2f * ln(u1)) * cos(2f * Math.PI.toFloat() * u2)
        }
    }

    /**
     * A believable path for [word]: each letter's centre missed by a
     * Gaussian [jitter] (key widths), one interior letter in five cut a third
     * of the way toward the line between its neighbours (most of a key at
     * most), sampled every 0.12 key widths with a little noise at ~8 key
     * widths a second, and half the doubled letters held for 0.18 s.
     */
    private fun gesture(word: String, layout: GlideDecoder.Layout, rng: SplitMix64,
                        jitter: Float = 0.25f, shortcut: Float = 0.2f, dwell: Float = 0.5f): List<GlidePoint> {
        val vx = ArrayList<Float>(); val vy = ArrayList<Float>(); val doubled = ArrayList<Boolean>()
        var last = -1
        for (ch in word) {
            val k = ch.code - 97
            if (k !in 0..25) continue
            if (k == last) { doubled[doubled.size - 1] = true; continue }
            last = k
            vx.add(layout.x[k] + jitter * rng.gaussian())
            vy.add(layout.y[k] + jitter * rng.gaussian())
            doubled.add(false)
        }
        if (vx.isEmpty()) return emptyList()
        if (vx.size > 2) {
            for (i in 1 until vx.size - 1) {
                if (rng.unit() >= shortcut) continue
                val dx = vx[i + 1] - vx[i - 1]; val dy = vy[i + 1] - vy[i - 1]
                val len2 = max(dx * dx + dy * dy, 1e-6f)
                val f = ((vx[i] - vx[i - 1]) * dx + (vy[i] - vy[i - 1]) * dy) / len2
                val fc = max(0f, min(1f, f))
                val cx = vx[i - 1] + dx * fc; val cy = vy[i - 1] + dy * fc
                val d = hypot(cx - vx[i], cy - vy[i])
                val move = min(0.35f * d, 0.9f)
                if (d > 1e-4f) {
                    vx[i] = vx[i] + (cx - vx[i]) / d * move
                    vy[i] = vy[i] + (cy - vy[i]) / d * move
                }
            }
        }
        val out = ArrayList<GlidePoint>()
        var t = 0.0
        val speed = 8f
        fun emit(x: Float, y: Float) { out.add(GlidePoint(x + 0.03f * rng.gaussian(), y + 0.03f * rng.gaussian(), t)) }
        if (vx.size == 1) {
            repeat(10) { emit(vx[0], vy[0]); t += 0.015 }
            return out
        }
        emit(vx[0], vy[0])
        for (i in 1 until vx.size) {
            val len = hypot(vx[i] - vx[i - 1], vy[i] - vy[i - 1])
            val steps = max(1, (len / 0.12f).toInt())
            for (s in 1..steps) {
                val f = s.toFloat() / steps
                t += (len / steps / speed).toDouble()
                emit(vx[i - 1] + (vx[i] - vx[i - 1]) * f, vy[i - 1] + (vy[i] - vy[i - 1]) * f)
            }
            if (doubled[i] && rng.unit() < dwell) {
                repeat(3) { t += 0.06; emit(vx[i], vy[i]) }
            }
        }
        return out
    }

    // Tests

    /** The 500 likeliest words, each glided once with jitter and shortcuts,
     *  at the Android phone widths (393 dp: Pixel 7/8; 411 dp: most other
     *  phones; 427 dp: the Avici_API_36 emulator, a Pixel 9 Pro XL; 360 dp:
     *  small phones): top-1 ≥ 93%, top-3 ≥
     *  98%, and a fast decode. */
    @Test fun frequentWordsAccuracyAndSpeed() {
        val decoder = decoder()
        val words = decoder.mostFrequent(500)
        assertEquals(500, words.size)
        // Warm the JIT and the index so the timings are the decoder's.
        run {
            val lay = layout(411f)
            val rng = SplitMix64(1)
            for (w in words.take(200)) decoder.decode(gesture(w, lay, rng), lay)
        }
        for ((width, seed) in listOf(393f to 7L, 411f to 11L, 427f to 17L, 360f to 13L)) {
            val lay = layout(width)
            val rng = SplitMix64(seed)
            var top1 = 0; var top3 = 0
            val times = ArrayList<Double>()
            val misses = ArrayList<String>()
            for (w in words) {
                val g = gesture(w, lay, rng)
                val start = System.nanoTime()
                val out = decoder.decode(g, lay)
                times.add((System.nanoTime() - start) / 1e6)
                val keys = out.map { TypingText.key(it.word) }
                if (keys.firstOrNull() == w) top1++ else misses.add("$w→${out.map { it.word }}")
                if (w in keys.take(3)) top3++
            }
            times.sort()
            val median = times[times.size / 2]; val p95 = times[(times.size * 0.95).toInt()]
            val report = "glide %.0fdp: top-1 %.1f%% top-3 %.1f%%; decode median %.2f ms, p95 %.2f ms, max %.2f ms"
                .format(width, top1 / 5.0, top3 / 5.0, median, p95, times.last())
            println(report)
            println("  top-1 misses: " + misses.take(25).joinToString("  "))
            assertTrue("top-1 below 93%: $report", top1 >= 465)
            assertTrue("top-3 below 98%: $report", top3 >= 490)
            assertTrue("decode too slow: $report", median < 30)
        }
    }

    /** Glide reads the keys where they are drawn, so the other letter
     *  layouts (Keyboard › Layout › Letters) glide as well as QWERTY: the
     *  same 500 words at 411 dp, top-1 ≥ 90%, top-3 ≥ 97%. */
    @Test fun otherLetterLayoutsGlide() {
        val decoder = decoder()
        val words = decoder.mostFrequent(500)
        for (letters in listOf(com.arpit.glyf.ime.LetterLayout.QWERTZ,
                com.arpit.glyf.ime.LetterLayout.AZERTY, com.arpit.glyf.ime.LetterLayout.COLEMAK)) {
            val lay = layout(411f, letters.rows)
            val rng = SplitMix64(7)
            var top1 = 0; var top3 = 0
            for (w in words) {
                val keys = decoder.decode(gesture(w, lay, rng), lay).map { TypingText.key(it.word) }
                if (keys.firstOrNull() == w) top1++
                if (w in keys.take(3)) top3++
            }
            val report = "glide ${letters.id}: top-1 ${top1 / 5.0}% top-3 ${top3 / 5.0}%"
            println(report)
            assertTrue(report, top1 >= 450)
            assertTrue(report, top3 >= 485)
        }
    }

    /** The words anyone tries first, on an ideal path and on a jittery one. */
    @Test fun namedWords() {
        val decoder = decoder()
        val lay = layout(411f)
        val cases = listOf(
            "the" to "the", "you" to "you", "hello" to "hello", "world" to "world", "thanks" to "thanks",
            "tomorrow" to "tomorrow", "coffee" to "coffee", "i" to "I", "to" to "to", "it" to "it", "is" to "is",
            "dont" to "don't", "im" to "I'm", "monday" to "Monday",
        )
        val rng = SplitMix64(3)
        for ((glide, want) in cases) {
            val ideal = decoder.decode(gesture(glide, lay, rng, jitter = 0f, shortcut = 0f, dwell = 1f), lay)
            assertEquals("ideal $glide: ${ideal.map { it.word }}", want, ideal.firstOrNull()?.word)
            val shaky = decoder.decode(gesture(glide, lay, rng), lay)
            assertEquals("jittered $glide: ${shaky.map { it.word }}", want, shaky.firstOrNull()?.word)
        }
    }

    /** The field's capitals and the previous word shape the answer. */
    @Test fun context() {
        val decoder = decoder()
        val lay = layout(411f)
        val rng = SplitMix64(5)
        fun glide(w: String) = gesture(w, lay, rng, jitter = 0f, shortcut = 0f)

        assertEquals("Hello", decoder.decode(glide("hello"), lay,
            GlideDecoder.Context(capitals = GlideDecoder.Capitals.FIRST)).firstOrNull()?.word)
        assertEquals("HELLO", decoder.decode(glide("hello"), lay,
            GlideDecoder.Context(capitals = GlideDecoder.Capitals.ALL)).firstOrNull()?.word)

        // "feel ill" is sick, not "feel I'll" (TypingEngine.KEPT_AFTER).
        assertEquals("I'll", decoder.decode(glide("ill"), lay).firstOrNull()?.word)
        assertEquals("ill", decoder.decode(glide("ill"), lay, GlideDecoder.Context(previous = "feel")).firstOrNull()?.word)

        // The words before lift what follows them.
        assertEquals("to", decoder.decode(glide("to"), lay,
            GlideDecoder.Context(previous = "want", beforePrevious = "I")).firstOrNull()?.word)

        // A word only this person uses glides too.
        val personal = PersonalLexicon()
        repeat(3) { personal.commit("cutee", null, 20_000) }
        val own = decoder.decode(glide("cutee"), lay, GlideDecoder.Context(personal = personal, today = 20_000))
        assertTrue("${own.map { it.word }}", own.any { it.word == "cutee" })
    }

    /** A symbol layer has no letters to glide over. */
    @Test fun layoutNeedsAllLetters() {
        assertNull(GlideDecoder.Layout.of(listOf(Triple('a', 10f, 10f)), 40f))
        assertNotNull(layout(390f))
    }

    /** The glide's state: one backspace takes word and space, a swap keeps
     *  the rest on offer, and the word before is what learning sees. */
    @Test fun glideState() {
        val g = GlideState("hello", listOf("help", "jello"), "I said hello ")
        assertEquals(6, g.deleteCount)
        assertTrue(g.isCurrent("I said hello "))
        assertEquals(listOf("hello", "jello"), g.others("help"))
        assertEquals("said", g.previousWord)
    }
}
