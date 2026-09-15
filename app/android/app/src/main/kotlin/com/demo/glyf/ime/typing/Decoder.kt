package com.demo.glyf.ime.typing

import java.util.PriorityQueue
import kotlin.math.abs
import kotlin.math.max

/** The QWERTY letter grid in key widths (FORMAT.md "Scoring"). Mirror of
 *  KeyGeometry in Engine/Typing/Decoder.swift. */
class KeyGeometry(val rowPitch: Float = 1.44f) {
    private val xs = FloatArray(26) { Float.NaN }
    private val ys = FloatArray(26) { Float.NaN }

    init {
        ROWS.forEachIndexed { r, row ->
            row.forEachIndexed { k, ch ->
                val i = ch.code - 97
                xs[i] = k + 0.5f + OFFSETS[r]
                ys[i] = (r + 0.5f) * rowPitch
            }
        }
    }

    fun hasKey(scalar: Int): Boolean = scalar in 97..122
    fun centerX(scalar: Int): Float = xs[scalar - 97]
    fun centerY(scalar: Int): Float = ys[scalar - 97]

    fun squaredDistance(x: Float, y: Float, scalar: Int): Float {
        if (!hasKey(scalar)) return 1.44f
        val dx = x - centerX(scalar)
        val dy = y - centerY(scalar)
        return dx * dx + dy * dy
    }

    /** AOSP proximity: within one key width of the key's edge. */
    fun isNear(x: Float, y: Float, scalar: Int): Boolean {
        if (!hasKey(scalar)) return false
        val dx = max(abs(x - centerX(scalar)) - 0.5f, 0f)
        val dy = max(abs(y - centerY(scalar)) - rowPitch / 2f, 0f)
        return dx * dx + dy * dy < 1f
    }

    companion object {
        val ROWS = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
        val OFFSETS = floatArrayOf(0f, 0.5f, 1.5f)
    }
}

/** One typed letter: the key it produced and where the finger landed
 *  (offset from the key's center in key widths; null = dead center). */
class TouchPoint(codePoint: Int, offset: FloatArray?, geometry: KeyGeometry) {
    val scalar: Int = TypingText.base(codePoint)
    val onKey: Boolean = geometry.hasKey(scalar)
    val x: Float = if (onKey) geometry.centerX(scalar) + (offset?.get(0) ?: 0f) else 0f
    val y: Float = if (onKey) geometry.centerY(scalar) + (offset?.get(1) ?: 0f) else 0f
}

/** Candidate search over one dictionary — AOSP LatinIME's typing traversal
 *  (FORMAT.md). Mirror of Decoder in Engine/Typing/Decoder.swift. */
object Decoder {
    const val PROXIMITY = 1
    const val FAR_SUBSTITUTION = 2
    const val FIRST_LETTER_FAR_SUBSTITUTION = 4
    const val OMISSION_SAME = 8
    const val OMISSION_OTHER = 16
    const val INSERTION_SAME = 32
    const val INSERTION_OTHER = 64
    const val TRANSPOSITION = 128
    const val COMPLETION = 256
    const val TRAILING_INSERTION = 512

    const val BEAM_FIRST = 310
    const val BEAM = 170

    class Hit(val node: Int, val spatial: Float, val kinds: Int) {
        val exact: Boolean get() = kinds == 0
    }

    /** Cheapest first; ties broken as on iOS so the beam keeps the same states. */
    private val STATE_ORDER = compareBy<State>({ it.spatial }, { it.node }, { it.kinds })

    private data class State(
        val node: Int, val spatial: Float, val proximityCount: Int, val editCount: Int,
        val depth: Int, val kinds: Int, val last: Int,
    )

    private fun sweet(x: Float): Float = when {
        x < 0.25f -> 0.24f * x / 0.25f
        x < 1f -> (0.24f * (1f - x) + 1.2f * (x - 0.25f)) / 0.75f
        else -> 1.2f
    }

    fun search(trie: GlydTrie, points: List<TouchPoint>, geometry: KeyGeometry, completionLimit: Int = 8): List<Hit> {
        val n = points.size
        if (n == 0 || n > 48) return emptyList()
        val layers = Array(n + 2) { ArrayList<State>() }
        layers[0].add(State(0, 0f, 0, 0, 0, 0, 0))
        val hits = ArrayList<Hit>()

        fun type(i: Int, b: Int): Int {
            val p = points[i]
            if (b == p.scalar) return 0
            if (!p.onKey || !geometry.hasKey(b)) return 3
            return if (geometry.isNear(p.x, p.y, b)) 1 else 2
        }

        fun distance(i: Int, b: Int): Float {
            val p = points[i]
            if (!p.onKey) return if (b == p.scalar) 0f else 1.2f
            return geometry.squaredDistance(p.x, p.y, b)
        }

        /** Returns (cost, new proximity count, new kinds). */
        fun matched(i: Int, b: Int, t: Int, s: State): Triple<Float, Int, Int> {
            var cost = 0.1524f * sweet(distance(i, b))
            var prox = s.proximityCount
            var kinds = s.kinds
            if (t == 1) {
                cost += if (i == 0) 0.072f else 0.0694f
                if (prox == 0) cost += 0.07788f
                prox += 1
                kinds = kinds or PROXIMITY
            }
            return Triple(cost, prox, kinds)
        }

        fun push(layer: Int, s: State) { if (s.spatial < 3f) layers[layer].add(s) }

        fun emit(s: State, trailing: Float) {
            if (trie.entryCount(s.node) == 0 || s.depth == 0) return
            var kinds = s.kinds
            var cost = s.spatial + trailing
            if (trailing > 0f) kinds = kinds or TRAILING_INSERTION
            if (s.proximityCount > 0) cost += 0.0683f
            if (s.editCount > 0 || trailing > 0f) cost += 0.0362f
            hits.add(Hit(s.node, cost, kinds))
        }

        for (i in 0 until n) {
            var layer: List<State> = layers[i]
            layers[i] = ArrayList()
            if (layer.isEmpty()) continue
            val cap = if (i == 0) BEAM_FIRST else BEAM
            if (layer.size > cap) layer = layer.sortedWith(STATE_ORDER).take(cap)
            for (s in layer) {
                val errorsAllowed = s.spatial / (i + 1).toFloat() < 0.095f
                val first = trie.firstChild(s.node)
                if (first != GlydTrie.NONE) {
                    val end = first + trie.childCount(s.node)
                    for (c in first until end) {
                        val b = TypingText.base(trie.scalar(c))
                        val t = type(i, b)

                        if (errorsAllowed && t != 0) {
                            val g0 = trie.firstChild(c)
                            if (g0 != GlydTrie.NONE) {
                                val same = s.depth > 0 && b == s.last
                                val omission = if (s.depth == 0) 0.5256f else if (same) 0.345f else 0.467f
                                for (g in g0 until g0 + trie.childCount(c)) {
                                    val gb = TypingText.base(trie.scalar(g))
                                    val gt = type(i, gb)
                                    if (gt > 1) continue
                                    val (cost, prox, kinds) = matched(i, gb, gt, s)
                                    push(i + 1, State(g, s.spatial + (omission + cost), prox, s.editCount + 1, s.depth + 2,
                                        kinds or (if (same) OMISSION_SAME else OMISSION_OTHER), gb))
                                }
                            }
                        }

                        when {
                            t == 0 || t == 1 -> {
                                val (cost, prox, kinds) = matched(i, b, t, s)
                                push(i + 1, State(c, s.spatial + cost, prox, s.editCount, s.depth + 1, kinds, b))
                            }
                            t == 2 && errorsAllowed -> {
                                val kinds = s.kinds or FAR_SUBSTITUTION or (if (s.depth == 0) FIRST_LETTER_FAR_SUBSTITUTION else 0)
                                push(i + 1, State(c, s.spatial + (0.3806f + 0.1524f * sweet(distance(i, b))),
                                    s.proximityCount, s.editCount + 1, s.depth + 1, kinds, b))
                            }
                        }
                    }

                    if (errorsAllowed && i + 1 < n) {
                        for (c1 in first until end) {
                            val b1 = TypingText.base(trie.scalar(c1))
                            if (type(i + 1, b1) > 1) continue
                            val g0 = trie.firstChild(c1)
                            if (g0 == GlydTrie.NONE) continue
                            for (c2 in g0 until g0 + trie.childCount(c1)) {
                                val b2 = TypingText.base(trie.scalar(c2))
                                if (type(i, b2) > 1) continue
                                push(i + 2, State(c2, s.spatial + (0.5608f + 0.1524f * (distance(i + 1, b1) + distance(i, b2))),
                                    s.proximityCount, s.editCount + 1, s.depth + 2, s.kinds or TRANSPOSITION, b2))
                            }
                        }
                        val nextScalar = points[i + 1].scalar
                        val here = points[i]
                        val fatFinger = (i > 0 && points[i - 1].onKey && geometry.isNear(points[i - 1].x, points[i - 1].y, here.scalar)) ||
                            (points[i + 1].onKey && geometry.isNear(points[i + 1].x, points[i + 1].y, here.scalar))
                        for (c in first until end) {
                            val b = TypingText.base(trie.scalar(c))
                            if (b != nextScalar) continue
                            val same = here.scalar == b
                            val cost = (if (s.depth == 0) 0.639f else 0f) +
                                (if (same) 0.5508f else if (fatFinger) 0.674f else 0.7248f) +
                                0.1524f * distance(i + 1, b)
                            push(i + 2, State(c, s.spatial + cost, s.proximityCount, s.editCount + 1, s.depth + 1,
                                s.kinds or (if (same) INSERTION_SAME else INSERTION_OTHER), b))
                        }
                    }
                }
                if (i == n - 1) emit(s, 0.8128f)
            }
        }

        var finals: List<State> = layers[n]
        if (finals.size > BEAM) finals = finals.sortedWith(STATE_ORDER).take(BEAM)
        for (s in finals) emit(s, 0f)
        if (completionLimit > 0) hits.addAll(completions(trie, finals, completionLimit))
        return hits
    }

    private class Item(val node: Int, val spatial: Float, val added: Int, val kinds: Int,
                       val proximity: Int, val edits: Int, val bound: Float)

    private fun completionCost(added: Int): Float = 0.4836f + 0.00624f * (added - 1).toFloat()
    private fun languageCost(p: Int): Float = 1.1214f * (255 - p).toFloat() / 255f

    private fun completions(trie: GlydTrie, seeds: List<State>, limit: Int): List<Hit> {
        val heap = PriorityQueue<Item>(64) { a, b -> if (a.bound != b.bound) a.bound.compareTo(b.bound) else a.node.compareTo(b.node) }
        for (s in seeds.sortedWith(STATE_ORDER).take(24)) {
            if (s.spatial >= 0.6f) continue
            val first = trie.firstChild(s.node)
            if (first == GlydTrie.NONE) continue
            for (c in first until first + trie.childCount(s.node)) {
                if (trie.maxProbability(c) == 0) continue
                heap.add(Item(c, s.spatial, 1, s.kinds or COMPLETION, s.proximityCount, s.editCount,
                    s.spatial + completionCost(1) + languageCost(trie.maxProbability(c))))
            }
        }
        val out = ArrayList<Hit>()
        var pops = 0
        while (out.size < limit && pops < 2_000) {
            val item = heap.poll() ?: break
            pops++
            if (trie.entryCount(item.node) > 0) {
                var cost = item.spatial + completionCost(item.added)
                if (item.proximity > 0) cost += 0.0683f
                if (item.edits > 0) cost += 0.0362f
                out.add(Hit(item.node, cost, item.kinds))
            }
            if (item.added >= 24) continue
            val first = trie.firstChild(item.node)
            if (first == GlydTrie.NONE) continue
            for (c in first until first + trie.childCount(item.node)) {
                if (trie.maxProbability(c) == 0) continue
                val added = item.added + 1
                heap.add(Item(c, item.spatial, added, item.kinds, item.proximity, item.edits,
                    item.spatial + completionCost(added) + languageCost(trie.maxProbability(c))))
            }
        }
        return out
    }
}
