package com.arpit.glyf.ime.typing

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/** One sample of a glide, in key widths: the touch divided by the column
 *  pitch, so letters sit one apart along a row and rows about 1.37 apart.
 *  [t] is seconds on any clock (the touch's). */
class GlidePoint(val x: Float, val y: Float, val t: Double)

/**
 * Shape writing over the .glyd trie (SHARK2: Kristensson & Zhai, 2004): a
 * glide is matched against each word's ideal path through its letters —
 * first by where it starts and ends and how far it travels, then by shape
 * (scale and position taken out) and by location — and the dictionary's
 * frequencies and word pairs settle what geometry leaves open. Pure logic:
 * GlyfKeyboardView feeds it the finger, GlyfIME the words before the caret.
 * Mirror of Engine/Typing/GlideDecoder.swift, constant for constant (Arpit,
 * 2026-10-07: "its guesses needs to be perfect too, see how perfect glide
 * typing is on iOS").
 */
class GlideDecoder(private val trie: GlydTrie) {

    /** Where the letter keys are, in key widths (index 0 = a). */
    class Layout(val x: FloatArray, val y: FloatArray) {
        override fun equals(other: Any?): Boolean =
            other is Layout && x.contentEquals(other.x) && y.contentEquals(other.y)
        override fun hashCode(): Int = 31 * x.contentHashCode() + y.contentHashCode()

        companion object {
            /** From the laid-out keys' centres in px; null unless all 26
             *  letters are there (a symbol layer or a digit pad has no glide
             *  typing). */
            fun of(keys: List<Triple<Char, Float, Float>>, pitch: Float): Layout? {
                val x = FloatArray(26) { Float.NaN }
                val y = FloatArray(26) { Float.NaN }
                var found = 0
                for ((letter, cx, cy) in keys) {
                    val a = letter.code - 97
                    if (a !in 0..25 || !x[a].isNaN()) continue
                    x[a] = cx / pitch
                    y[a] = cy / pitch
                    found++
                }
                if (found != 26 || pitch <= 0f) return null
                return Layout(x, y)
            }

            /** The typing engine's abstract grid (tests). */
            fun of(geometry: KeyGeometry): Layout =
                Layout(FloatArray(26) { geometry.centerX(97 + it) }, FloatArray(26) { geometry.centerY(97 + it) })
        }
    }

    enum class Capitals { NONE, FIRST, ALL }

    class Context(
        val previous: String? = null,
        val beforePrevious: String? = null,
        val capitals: Capitals = Capitals.NONE,
        val personal: PersonalLexicon? = null,
        val today: Int = TypingText.day(),
    )

    /** [score]: higher is better; the gap between two is in the same units. */
    data class Candidate(val word: String, val score: Float)

    companion object {
        // Tuning (key widths unless said otherwise), set against the 500
        // likeliest words glided by a synthetic finger (GlideDecoderTest:
        // jitter, cut corners, dwells). Same numbers as the Swift decoder.

        const val SAMPLES = 32
        /** A word may start or end this far from where the finger did. */
        const val END_REACH = 1.4f
        /** The finger must pass this close to every letter, in order. */
        const val PRUNE_REACH = 1.9f
        /** Shorter or longer than the word's path by more than this is another word. */
        const val LENGTH_RATIO = 2.0f
        /** What a path shorter or longer than the word's costs, per unit of log ratio. */
        const val LENGTH_WEIGHT = 1.0f
        /** Short paths compare as if at least this long ("a" against "as"). */
        const val LENGTH_FLOOR = 0.7f
        /** A gesture shorter than this never left its key: a one-letter word. */
        const val STILL_LENGTH = 0.9f
        /** Within this of the ideal path a point costs nothing. */
        const val LOCATION_SLACK = 0.15f
        /** Location after the two paths are time-aligned (dynamic time
         *  warping within [WARP_BAND] samples). The plain point-by-point
         *  distance only picks which words are worth aligning ([WARP_LIMIT]). */
        const val WARP_WEIGHT = 2.4f
        const val WARP_BAND = 6
        const val WARP_LIMIT = 120
        const val SHAPE_WEIGHT = 3f
        /** Where the finger landed and lifted is deliberate: it counts double. */
        const val ENDS_WEIGHT = 0.8f
        /** A sharp turn of the finger nowhere near a letter of the word. */
        const val CORNER_PENALTY = 0.25f
        const val CORNER_TURN = (60 * Math.PI / 180).toFloat()
        const val CORNER_REACH = 0.9f
        /** The whole span of the dictionary's frequency scale, as a cost. */
        const val LANGUAGE_WEIGHT = 3f
        /** Lingering on a key this long is a doubled letter ("hello", "too"). */
        const val DWELL_SECONDS = 0.14
        const val DWELL_RADIUS = 0.3f
        const val DWELL_REACH = 0.8f
        /** A dwell on a doubled letter; a dwell on no doubled letter; a
         *  doubled letter without a dwell (plenty of people never pause). */
        const val DOUBLE_BONUS = 0.45f
        const val DWELL_UNEXPLAINED = 0.3f
        const val DOUBLE_MISS = 0.08f
        /** Never seen after the previous word, when it was seen before
         *  others: ranks as if this much rarer. */
        const val UNSEEN_PAIR_MOST = 25f
        /** An acronym ("DJ", "PST") ranks as if this much rarer. */
        const val ACRONYM_PENALTY = 40f

        private const val MAX_LETTERS = 24

        /** The most probable real form at a node: entries are sorted by
         *  probability, so the first that is a word is it. */
        private fun bestEntry(trie: GlydTrie, node: Int): Int? {
            val first = trie.firstEntry(node)
            val n = trie.entryCount(node)
            for (e in first until first + n) {
                if (trie.flags(e) and (GlydTrie.FLAG_OFFENSIVE or GlydTrie.FLAG_NOT_A_WORD) == 0) return e
            }
            return null
        }

        private fun lettersOf(bytes: ByteArray, from: Int = 0, to: Int = bytes.size): String {
            val sb = StringBuilder(to - from)
            for (i in from until to) sb.append((bytes[i] + 97).toChar())
            return sb.toString()
        }
    }

    // MARK: Word index

    /** Every glide-able word once: its letters, the trie node holding its
     *  forms, and its frequency, bucketed by first and last letter. */
    private class Index(
        val letters: ByteArray,     // 0–25, words back to back
        val offset: IntArray,       // word i is letters[offset[i] until offset[i+1]]
        val node: IntArray,
        val probability: IntArray,
        val bucketStart: IntArray,  // 26 * 26 + 1
        val bucketWords: IntArray,
    ) {
        val count get() = node.size
    }

    @Volatile private var index: Index? = null
    private val indexLock = Any()

    /** Builds the index off the main thread, so the first glide pays nothing. */
    fun warm() {
        if (index != null) return
        Thread({ ensureIndex() }, "glyf-glide-index").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }.start()
    }

    private fun ensureIndex(): Index {
        index?.let { return it }
        synchronized(indexLock) {
            index?.let { return it }
            val built = build(trie)
            index = built
            return built
        }
    }

    private fun build(trie: GlydTrie): Index {
        var letters = ByteArray(1_600_000)
        var letterCount = 0
        var offset = IntArray(170_000)
        var node = IntArray(170_000)
        var prob = IntArray(170_000)
        var words = 0
        offset[0] = 0
        val path = ByteArray(MAX_LETTERS)
        // Depth-first, children pushed in order and the last popped first:
        // the Swift decoder's order, so ties break the same way.
        var stackNode = IntArray(1024)
        var stackDepth = IntArray(1024)
        var stackLetter = ByteArray(1024)
        var sp = 0
        stackNode[0] = 0; stackDepth[0] = 0; stackLetter[0] = 0; sp = 1
        while (sp > 0) {
            sp--
            val tn = stackNode[sp]
            val depth = stackDepth[sp]
            if (depth > 0) path[depth - 1] = stackLetter[sp]
            if (depth > 0 && trie.entryCount(tn) > 0) {
                val best = bestEntry(trie, tn)
                if (best != null && trie.probability(best) > 0) {
                    if (letterCount + depth > letters.size) letters = letters.copyOf(letters.size * 2)
                    if (words + 2 > node.size) {
                        node = node.copyOf(node.size * 2)
                        prob = prob.copyOf(prob.size * 2)
                        offset = offset.copyOf(offset.size * 2)
                    }
                    System.arraycopy(path, 0, letters, letterCount, depth)
                    letterCount += depth
                    node[words] = tn
                    prob[words] = trie.probability(best)
                    words++
                    offset[words] = letterCount
                }
            }
            if (depth >= MAX_LETTERS) continue
            val first = trie.firstChild(tn)
            if (first == GlydTrie.NONE) continue
            // Only words spelled with the 26 keys: a letter the board hasn't
            // got can't be glided over.
            for (c in first until first + trie.childCount(tn)) {
                val s = trie.scalar(c)
                if (s < 97 || s > 122) continue
                if (sp == stackNode.size) {
                    stackNode = stackNode.copyOf(sp * 2)
                    stackDepth = stackDepth.copyOf(sp * 2)
                    stackLetter = stackLetter.copyOf(sp * 2)
                }
                stackNode[sp] = c; stackDepth[sp] = depth + 1; stackLetter[sp] = (s - 97).toByte(); sp++
            }
        }
        val finalLetters = letters.copyOf(letterCount)
        val finalOffset = offset.copyOf(words + 1)
        val finalNode = node.copyOf(words)
        val finalProb = prob.copyOf(words)
        val counts = IntArray(26 * 26 + 1)
        for (w in 0 until words) {
            val a = finalOffset[w]; val b = finalOffset[w + 1]
            counts[finalLetters[a] * 26 + finalLetters[b - 1] + 1]++
        }
        for (i in 1 until counts.size) counts[i] += counts[i - 1]
        val bucketWords = IntArray(words)
        val fill = counts.copyOf()
        for (w in 0 until words) {
            val a = finalOffset[w]; val b = finalOffset[w + 1]
            val bucket = finalLetters[a] * 26 + finalLetters[b - 1]
            bucketWords[fill[bucket]] = w
            fill[bucket]++
        }
        return Index(finalLetters, finalOffset, finalNode, finalProb, counts, bucketWords)
    }

    /** Tests: the likeliest words the board can glide, best first. */
    fun mostFrequent(n: Int): List<String> {
        val ix = ensureIndex()
        val order = (0 until ix.count).sortedWith { a, b ->
            if (ix.probability[a] != ix.probability[b]) ix.probability[b] - ix.probability[a] else a - b
        }
        return order.take(n).map { w -> lettersOf(ix.letters, ix.offset[w], ix.offset[w + 1]) }
    }

    // MARK: Layout cache

    private var layout: Layout? = null
    /** Each word's ideal path length on the current layout. */
    private var templateLength = FloatArray(0)

    private fun prepare(layout: Layout, ix: Index) {
        if (this.layout == layout && templateLength.size == ix.count) return
        val lengths = FloatArray(ix.count)
        val lx = layout.x; val ly = layout.y
        val letters = ix.letters
        for (w in 0 until ix.count) {
            val a = ix.offset[w]; val b = ix.offset[w + 1]
            var total = 0f
            var last = letters[a].toInt()
            for (i in a + 1 until b) {
                val l = letters[i].toInt()
                if (l == last) continue
                total += hypot(lx[l] - lx[last], ly[l] - ly[last])
                last = l
            }
            lengths[w] = total
        }
        templateLength = lengths
        this.layout = layout
    }

    // MARK: Gesture

    /** What the finger did, read once per decode. */
    private class Gesture(layout: Layout) {
        val x = FloatArray(SAMPLES)
        val y = FloatArray(SAMPLES)
        /** Centred and scaled so the longer side of the box is 1. */
        val nx = FloatArray(SAMPLES)
        val ny = FloatArray(SAMPLES)
        /** The letters' centres. */
        val kx = layout.x.copyOf()
        val ky = layout.y.copyOf()
        /** Per key, which of the 32 samples lie within PRUNE_REACH of it:
         *  the ordered pass over a word's letters is then a few bit ops. */
        val near = IntArray(26)
        var length = 0f
        var cornersX = FloatArray(0)
        var cornersY = FloatArray(0)
        var dwellsX = FloatArray(0)
        var dwellsY = FloatArray(0)
    }

    /** Scratch for one word's ideal path, reused across the candidates. */
    private class Template {
        val vx = FloatArray(MAX_LETTERS)
        val vy = FloatArray(MAX_LETTERS)
        val x = FloatArray(SAMPLES)
        val y = FloatArray(SAMPLES)
        val nx = FloatArray(SAMPLES)
        val ny = FloatArray(SAMPLES)
        val rowA = FloatArray(SAMPLES)
        val rowB = FloatArray(SAMPLES)
        val doubled = IntArray(MAX_LETTERS)
    }

    private fun read(raw: List<GlidePoint>, layout: Layout): Gesture {
        val g = Gesture(layout)
        // Collapse points that didn't move.
        val xs = FloatArray(raw.size)
        val ys = FloatArray(raw.size)
        var n = 1
        xs[0] = raw[0].x; ys[0] = raw[0].y
        for (i in 1 until raw.size) {
            val p = raw[i]
            if (hypot(p.x - xs[n - 1], p.y - ys[n - 1]) > 1e-4f) { xs[n] = p.x; ys[n] = p.y; n++ }
        }
        g.length = resample(xs, ys, n, g.x, g.y)
        normalize(g.x, g.y, g.nx, g.ny)
        for (k in 0 until 26) {
            var mask = 0
            for (i in 0 until SAMPLES) {
                if (hypot(g.x[i] - g.kx[k], g.y[i] - g.ky[k]) <= PRUNE_REACH) mask = mask or (1 shl i)
            }
            g.near[k] = mask
        }
        // Corners: a smoothed copy, so jitter doesn't turn into turns.
        if (g.length > 1f) {
            val sx = FloatArray(SAMPLES); val sy = FloatArray(SAMPLES)
            sx[0] = g.x[0]; sy[0] = g.y[0]
            sx[SAMPLES - 1] = g.x[SAMPLES - 1]; sy[SAMPLES - 1] = g.y[SAMPLES - 1]
            for (i in 1 until SAMPLES - 1) {
                sx[i] = (g.x[i - 1] + g.x[i] + g.x[i + 1]) / 3f
                sy[i] = (g.y[i - 1] + g.y[i] + g.y[i + 1]) / 3f
            }
            val cx = ArrayList<Float>(); val cy = ArrayList<Float>()
            var i = 2
            while (i < SAMPLES - 2) {
                val turn = angle(sx[i] - sx[i - 2], sy[i] - sy[i - 2], sx[i + 2] - sx[i], sy[i + 2] - sy[i])
                if (turn > CORNER_TURN) {
                    cx.add(g.x[i]); cy.add(g.y[i])
                    i += 3 // one corner, not three in a row
                } else {
                    i += 1
                }
            }
            g.cornersX = cx.toFloatArray(); g.cornersY = cy.toFloatArray()
        }
        // Dwells: the finger lingering inside one key, well after the start
        // and before the lift.
        if (raw.size > 2) {
            val t0 = raw.first().t; val t1 = raw.last().t
            if (t1 - t0 > 0.2) {
                val dx = ArrayList<Float>(); val dy = ArrayList<Float>()
                var i = 0
                while (i < raw.size) {
                    var j = i
                    while (j + 1 < raw.size && hypot(raw[j + 1].x - raw[i].x, raw[j + 1].y - raw[i].y) < DWELL_RADIUS) j++
                    if (j > i && raw[j].t - raw[i].t >= DWELL_SECONDS && raw[i].t - t0 > 0.06 && t1 - raw[j].t > 0.06) {
                        dx.add((raw[i].x + raw[j].x) / 2f)
                        dy.add((raw[i].y + raw[j].y) / 2f)
                    }
                    i = j + 1
                }
                g.dwellsX = dx.toFloatArray(); g.dwellsY = dy.toFloatArray()
            }
        }
        return g
    }

    /** SAMPLES points equidistant along the polyline's first [n] vertices;
     *  returns its length. */
    private fun resample(xs: FloatArray, ys: FloatArray, n: Int, intoX: FloatArray, intoY: FloatArray): Float {
        var total = 0f
        for (i in 1 until max(n, 1)) total += hypot(xs[i] - xs[i - 1], ys[i] - ys[i - 1])
        if (total < 1e-5f) {
            for (i in 0 until SAMPLES) { intoX[i] = xs[0]; intoY[i] = ys[0] }
            return 0f
        }
        val step = total / (SAMPLES - 1)
        intoX[0] = xs[0]
        intoY[0] = ys[0]
        var seg = 1
        var done = 0f // length of segments before `seg`
        var segLen = if (n > 1) hypot(xs[1] - xs[0], ys[1] - ys[0]) else 0f
        for (i in 1 until SAMPLES - 1) {
            val target = step * i
            while (seg < n - 1 && done + segLen < target) {
                done += segLen
                seg++
                segLen = hypot(xs[seg] - xs[seg - 1], ys[seg] - ys[seg - 1])
            }
            val f = if (segLen > 0f) (target - done) / segLen else 0f
            intoX[i] = xs[seg - 1] + (xs[seg] - xs[seg - 1]) * f
            intoY[i] = ys[seg - 1] + (ys[seg] - ys[seg - 1]) * f
        }
        intoX[SAMPLES - 1] = xs[n - 1]
        intoY[SAMPLES - 1] = ys[n - 1]
        return total
    }

    private fun normalize(x: FloatArray, y: FloatArray, intoX: FloatArray, intoY: FloatArray) {
        var cx = 0f; var cy = 0f
        var minX = Float.MAX_VALUE; var maxX = -Float.MAX_VALUE
        var minY = minX; var maxY = maxX
        for (i in 0 until SAMPLES) {
            cx += x[i]; cy += y[i]
            minX = min(minX, x[i]); maxX = max(maxX, x[i])
            minY = min(minY, y[i]); maxY = max(maxY, y[i])
        }
        cx /= SAMPLES
        cy /= SAMPLES
        val side = max(maxX - minX, maxY - minY)
        val s = if (side > 1e-3f) 1f / side else 0f
        for (i in 0 until SAMPLES) {
            intoX[i] = (x[i] - cx) * s
            intoY[i] = (y[i] - cy) * s
        }
    }

    private fun angle(ax: Float, ay: Float, bx: Float, by: Float): Float {
        val la = hypot(ax, ay); val lb = hypot(bx, by)
        if (la <= 1e-5f || lb <= 1e-5f) return 0f
        return acos(((ax * bx + ay * by) / (la * lb)).coerceIn(-1f, 1f))
    }

    // MARK: Decoding

    private class Scored(val word: Int, var cost: Float, val letters: ByteArray, val node: Int?)
    private class Rough(val word: Int, val a: Int, val b: Int, val rough: Float)

    /** Ranked words for a glide, best first — at most [limit], each already
     *  cased for the field. Empty when nothing fits. */
    fun decode(raw: List<GlidePoint>, layout: Layout, context: Context = Context(), limit: Int = 4): List<Candidate> {
        if (raw.isEmpty() || limit <= 0) return emptyList()
        val ix = ensureIndex()
        prepare(layout, ix)
        val g = read(raw, layout)
        val language = Language(trie, context)
        val scored = ArrayList<Scored>(64)

        if (g.length < STILL_LENGTH) {
            // One key: the one-letter words near it, by distance and frequency.
            val px = g.x[0]; val py = g.y[0]
            for (k in 0 until 26) {
                val d = hypot(g.kx[k] - px, g.ky[k] - py)
                if (d >= 1f) continue
                val bucket = k * 26 + k
                for (slot in ix.bucketStart[bucket] until ix.bucketStart[bucket + 1]) {
                    val w = ix.bucketWords[slot]
                    if (ix.offset[w + 1] - ix.offset[w] != 1) continue
                    val letters = byteArrayOf(k.toByte())
                    val f = language.probability(letters, ix.node[w], ix.probability[w].toFloat())
                    scored.add(Scored(w, 1.5f * d + LANGUAGE_WEIGHT * (255 - f) / 255, letters, ix.node[w]))
                }
            }
        }
        // A short glide between two keys with no one-letter word near them
        // ("we" cut short) is still a word: search as for any glide. The
        // Swift decoder returned nothing there (GlideDecoderTest, 10-08).
        if (g.length >= STILL_LENGTH || (scored.isEmpty() && g.length > 0f)) {
            val startKeys = ArrayList<Int>(); val endKeys = ArrayList<Int>()
            for (k in 0 until 26) {
                if (hypot(g.kx[k] - g.x[0], g.ky[k] - g.y[0]) <= END_REACH) startKeys.add(k)
                if (hypot(g.kx[k] - g.x[SAMPLES - 1], g.ky[k] - g.y[SAMPLES - 1]) <= END_REACH) endKeys.add(k)
            }
            val template = Template()
            val gestureLength = max(g.length, LENGTH_FLOOR)
            val lengths = templateLength
            val letters = ix.letters
            // Everyone who passes the gates gets the rough score; only the
            // likeliest are worth aligning, which is where the time goes.
            var roughs = ArrayList<Rough>(256)
            for (s in startKeys) for (e in endKeys) {
                val bucket = s * 26 + e
                for (slot in ix.bucketStart[bucket] until ix.bucketStart[bucket + 1]) {
                    val w = ix.bucketWords[slot]
                    val ratio = max(lengths[w], LENGTH_FLOOR) / gestureLength
                    if (ratio > LENGTH_RATIO || ratio < 1f / LENGTH_RATIO) continue
                    val a = ix.offset[w]; val b = ix.offset[w + 1]
                    if (!passes(letters, a, b, g)) continue
                    val rough = cost(letters, a, b, g, template, warp = false).rough +
                        LENGTH_WEIGHT * abs(ln(ratio)) +
                        LANGUAGE_WEIGHT * (255 - ix.probability[w]) / 255f
                    roughs.add(Rough(w, a, b, rough))
                }
            }
            if (roughs.size > WARP_LIMIT) {
                roughs.sortBy { it.rough }
                roughs = ArrayList(roughs.subList(0, WARP_LIMIT))
            }
            for (r in roughs) {
                val ratio = max(lengths[r.word], LENGTH_FLOOR) / gestureLength
                val c = cost(letters, r.a, r.b, g, template).total + LENGTH_WEIGHT * abs(ln(ratio))
                scored.add(Scored(r.word, c, letters.copyOfRange(r.a, r.b), ix.node[r.word]))
            }
            // This person's own words the dictionary hasn't got ("cutee").
            val personal = context.personal
            if (personal != null && personal.words.isNotEmpty()) {
                for ((key, _) in personal.knownForms().take(2_000)) {
                    if (key.isEmpty() || key.length > MAX_LETTERS || key.any { it < 'a' || it > 'z' }) continue
                    val bytes = ByteArray(key.length) { (key[it] - 'a').toByte() }
                    if (bytes[0].toInt() !in startKeys || bytes[bytes.size - 1].toInt() !in endKeys) continue
                    val base = personal.probability(key, context.today) ?: continue
                    var total = 0f
                    for (i in 1 until bytes.size) {
                        if (bytes[i] == bytes[i - 1]) continue
                        val p = bytes[i].toInt(); val q = bytes[i - 1].toInt()
                        total += hypot(g.kx[p] - g.kx[q], g.ky[p] - g.ky[q])
                    }
                    val ratio = max(total, LENGTH_FLOOR) / gestureLength
                    if (ratio > LENGTH_RATIO || ratio < 1f / LENGTH_RATIO || !passes(bytes, 0, bytes.size, g)) continue
                    val c = cost(bytes, 0, bytes.size, g, template).total + LENGTH_WEIGHT * abs(ln(ratio))
                    scored.add(Scored(-1, c + LANGUAGE_WEIGHT * (255 - base) / 255, bytes, null))
                }
            }
            for (s in scored) {
                if (s.word < 0) continue
                val f = language.probability(s.letters, s.node!!, ix.probability[s.word].toFloat())
                s.cost += LANGUAGE_WEIGHT * (255 - f) / 255
            }
        }
        scored.sortWith { a, b -> if (a.cost != b.cost) a.cost.compareTo(b.cost) else a.word.compareTo(b.word) }

        val out = ArrayList<Candidate>()
        val seen = HashSet<String>()
        for (s in scored) {
            val spelled: String = if (s.node != null) {
                form(s.node, s.letters, language.previousKey) ?: continue
            } else {
                context.personal?.word(lettersOf(s.letters))?.form ?: continue
            }
            val shown = when (context.capitals) {
                Capitals.NONE -> spelled
                Capitals.FIRST -> if (TypingText.hasUppercase(spelled)) spelled else TypingText.capitalizeFirst(spelled)
                Capitals.ALL -> spelled.uppercase()
            }
            if (!seen.add(shown.lowercase())) continue
            out.add(Candidate(shown, -s.cost))
            if (out.size == limit) break
        }
        return out
    }

    /** Tests and tuning: where [word] (its letters) stood for this glide —
     *  which gate dropped it, or its costs. */
    fun explain(raw: List<GlidePoint>, layout: Layout, word: String, context: Context = Context()): String {
        val ix = ensureIndex()
        prepare(layout, ix)
        val g = read(raw, layout)
        val bytes = word.filter { it in 'a'..'z' }.map { (it - 'a').toByte() }.toByteArray()
        if (bytes.isEmpty()) return "no letters"
        val s = bytes[0].toInt(); val e = bytes[bytes.size - 1].toInt()
        val startD = hypot(g.kx[s] - g.x[0], g.ky[s] - g.y[0])
        val endD = hypot(g.kx[e] - g.x[SAMPLES - 1], g.ky[e] - g.y[SAMPLES - 1])
        var line = "len %.2f start %.2f end %.2f corners %d dwells %d".format(g.length, startD, endD, g.cornersX.size, g.dwellsX.size)
        if (startD > END_REACH || endD > END_REACH) return "$line DROPPED: ends"
        var w: Int? = null
        for (slot in ix.bucketStart[s * 26 + e] until ix.bucketStart[s * 26 + e + 1]) {
            val i = ix.bucketWords[slot]
            if (ix.letters.copyOfRange(ix.offset[i], ix.offset[i + 1]).contentEquals(bytes)) { w = i; break }
        }
        if (w == null) return "$line NOT INDEXED"
        val ratio = max(templateLength[w], LENGTH_FLOOR) / max(g.length, LENGTH_FLOOR)
        line += " ratio %.2f f %d".format(ratio, ix.probability[w])
        if (ratio > LENGTH_RATIO || ratio < 1f / LENGTH_RATIO) return "$line DROPPED: length"
        if (!passes(bytes, 0, bytes.size, g)) return "$line DROPPED: passes"
        val c = cost(bytes, 0, bytes.size, g, Template())
        val f = Language(trie, context).probability(bytes, ix.node[w], ix.probability[w].toFloat())
        val length = LENGTH_WEIGHT * abs(ln(ratio)); val lang = LANGUAGE_WEIGHT * (255 - f) / 255
        return "$line $c length %.2f lang %.2f total %.2f".format(length, lang, c.total + length + lang)
    }

    /** The word's shown spelling: the dictionary's likeliest form at the
     *  node — "don't" for d-o-n-t, "I'm" for i-m, "Monday" — except where the
     *  previous word makes the plain word the one meant ("feel ill"). */
    private fun form(node: Int, letters: ByteArray, previous: String?): String? {
        val best = bestEntry(trie, node) ?: return null
        val form = trie.form(best)
        val key = TypingText.key(form)
        if (previous != null && key == lettersOf(letters) && TypingEngine.KEPT_AFTER[key]?.contains(previous) == true) {
            val first = trie.firstEntry(node)
            for (e in first until first + trie.entryCount(node)) {
                if (trie.flags(e) and (GlydTrie.FLAG_OFFENSIVE or GlydTrie.FLAG_NOT_A_WORD) == 0 && trie.form(e) == key) {
                    return trie.form(e)
                }
            }
        }
        return form
    }

    /** The finger passed near every letter, in order: each letter must have
     *  a sample within reach at or after the one that reached the letter before. */
    private fun passes(letters: ByteArray, a: Int, b: Int, g: Gesture): Boolean {
        var from = -1 // samples still ahead
        var last = -1
        for (i in a until b) {
            val k = letters[i].toInt()
            if (k == last) continue
            last = k
            val ahead = g.near[k] and from
            if (ahead == 0) return false
            from = -1 shl Integer.numberOfTrailingZeros(ahead)
        }
        return true
    }

    /** One word's geometric costs, apart so tuning can see them. */
    class Costs(
        /** Point by point, before alignment. */
        val location: Float, val warped: Float, val shape: Float, val ends: Float,
        val corners: Float, val doubles: Float,
    ) {
        val total: Float get() = WARP_WEIGHT * warped + SHAPE_WEIGHT * shape +
            ENDS_WEIGHT * ends + CORNER_PENALTY * corners + doubles
        /** Before alignment: the point-by-point distance in the warp's place,
         *  for choosing which words to align. */
        val rough: Float get() = WARP_WEIGHT * location + SHAPE_WEIGHT * shape +
            ENDS_WEIGHT * ends + CORNER_PENALTY * corners + doubles
        override fun toString() = "warp %.2f (rough %.2f) shape %.3f ends %.2f corners %.0f doubles %.2f = %.2f"
            .format(warped, location, shape, ends, corners, doubles, total)
    }

    /** Everything but language: location, shape, the ends, corners, dwells. */
    private fun cost(letters: ByteArray, a: Int, b: Int, g: Gesture, t: Template, warp: Boolean = true): Costs {
        // The ideal path: the letters' centres, doubles collapsed.
        var m = 0
        var last = -1
        var nd = 0
        for (i in a until b) {
            val k = letters[i].toInt()
            if (k == last) { t.doubled[nd++] = k; continue }
            last = k
            t.vx[m] = g.kx[k]
            t.vy[m] = g.ky[k]
            m++
        }
        resample(t.vx, t.vy, m, t.x, t.y)
        normalize(t.x, t.y, t.nx, t.ny)

        var location = 0f; var shape = 0f
        var weights = 0f
        for (i in 0 until SAMPLES) {
            val w = if (i == 0 || i == SAMPLES - 1) 2f else 1f
            location += w * max(0f, hypot(g.x[i] - t.x[i], g.y[i] - t.y[i]) - LOCATION_SLACK)
            weights += w
            shape += hypot(g.nx[i] - t.nx[i], g.ny[i] - t.ny[i])
        }
        location /= weights
        // One key has no shape; where the finger went says it all.
        shape = if (m > 1) shape / SAMPLES else 0f
        val ends = hypot(g.x[0] - t.vx[0], g.y[0] - t.vy[0]) +
            hypot(g.x[SAMPLES - 1] - t.vx[m - 1], g.y[SAMPLES - 1] - t.vy[m - 1])

        var corners = 0f
        for (c in g.cornersX.indices) {
            var near = false
            for (v in 0 until m) {
                if (hypot(g.cornersX[c] - t.vx[v], g.cornersY[c] - t.vy[v]) <= CORNER_REACH) { near = true; break }
            }
            if (!near) corners += 1f
        }

        // A lingering finger wants a doubled letter there, and a doubled
        // letter wants the finger to have lingered.
        var doubles = 0f
        for (di in 0 until nd) {
            val k = t.doubled[di]
            var near = false
            for (d in g.dwellsX.indices) {
                if (hypot(g.dwellsX[d] - g.kx[k], g.dwellsY[d] - g.ky[k]) <= DWELL_REACH) { near = true; break }
            }
            doubles += if (near) -DOUBLE_BONUS else DOUBLE_MISS
        }
        for (d in g.dwellsX.indices) {
            var explained = false
            for (di in 0 until nd) {
                val k = t.doubled[di]
                if (hypot(g.dwellsX[d] - g.kx[k], g.dwellsY[d] - g.ky[k]) <= DWELL_REACH) { explained = true; break }
            }
            if (!explained) doubles += DWELL_UNEXPLAINED
        }
        if (!warp) return Costs(location, 0f, shape, ends, corners, doubles)

        // Time-aligned location: the cheapest monotone pairing of the two
        // paths, each pair costing its distance beyond the slack.
        val inf = Float.MAX_VALUE
        var rowA = t.rowA; var rowB = t.rowB
        java.util.Arrays.fill(rowA, inf)
        rowA[0] = pair(g, t, 0, 0)
        for (j in 1..WARP_BAND) rowA[j] = rowA[j - 1] + pair(g, t, 0, j)
        for (i in 1 until SAMPLES) {
            val lo = max(0, i - WARP_BAND); val hi = min(SAMPLES - 1, i + WARP_BAND)
            java.util.Arrays.fill(rowB, inf)
            for (j in lo..hi) {
                var best = rowA[j]
                if (j > 0) best = min(best, min(rowB[j - 1], rowA[j - 1]))
                rowB[j] = best + pair(g, t, i, j)
            }
            val swap = rowA; rowA = rowB; rowB = swap
        }
        val warped = rowA[SAMPLES - 1] / SAMPLES
        return Costs(location, warped, shape, ends, corners, doubles)
    }

    private fun pair(g: Gesture, t: Template, i: Int, j: Int): Float =
        max(0f, hypot(g.x[i] - t.x[j], g.y[i] - t.y[j]) - LOCATION_SLACK)

    // MARK: Language

    /** The frequency evidence for a word here: the dictionary's, lifted by
     *  what this person types and by the words before (FORMAT.md "Language f"). */
    private class Language(val trie: GlydTrie, val context: Context) {
        val previousKey: String? = context.previous?.let { TypingText.key(it) }?.takeIf { it.isNotEmpty() }
        private val followers: Map<Int, Int>
        private val followerFloor: Float
        private val triples: Map<Int, Int>

        init {
            var fol: Map<Int, Int> = emptyMap()
            val tri = HashMap<Int, Int>()
            val prev = previousKey?.let { entry(trie, it) }
            if (prev != null) {
                fol = trie.followers(prev)
                val twoBack = context.beforePrevious?.let { TypingText.key(it) }?.let { entry(trie, it) }
                if (twoBack != null) {
                    for ((target, p) in trie.trigrams(twoBack, prev)) tri.putIfAbsent(target, p)
                }
            }
            followers = fol
            followerFloor = (fol.values.minOrNull() ?: 0).toFloat()
            triples = tri
        }

        private fun entry(trie: GlydTrie, key: String): Int? {
            if (key.isEmpty()) return null
            val node = trie.node(key)
            if (node == GlydTrie.NONE || trie.entryCount(node) <= 0) return null
            return trie.firstEntry(node)
        }

        fun probability(letters: ByteArray, node: Int, base: Float): Float {
            var f = base
            val personal = context.personal
            val needsKey = personal != null && personal.words.isNotEmpty()
            val key = if (needsKey) lettersOf(letters) else ""
            if (needsKey) personal!!.probability(key, context.today)?.let { f = max(f, it) }
            var pair: Float? = null
            val prevKey = previousKey
            if (prevKey != null) {
                if (needsKey) personal!!.pairProbability(prevKey, key, context.today)?.let { pair = it }
                val entry = bestEntry(trie, node)
                if (entry != null) {
                    val p = followers[entry]
                    if (p != null) {
                        pair = max(pair ?: 0f, p.toFloat())
                    } else if (pair == null && followers.isNotEmpty() && !TypingText.hasUppercase(trie.form(entry))) {
                        f = max(min(f, followerFloor), f - UNSEEN_PAIR_MOST)
                    }
                    triples[entry]?.let { pair = max(pair ?: 0f, it + TypingEngine.TRIPLE_LIFT) }
                }
                pair?.let { f = max(f, it) }
            }
            if (letters.size > 1) {
                val entry = bestEntry(trie, node)
                if (entry != null) {
                    val form = trie.form(entry)
                    if (TypingText.capitalCount(form) == form.codePointCount(0, form.length)) f = max(0f, f - ACRONYM_PENALTY)
                }
            }
            return f.coerceIn(0f, 255f)
        }
    }
}
