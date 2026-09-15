package com.demo.glyf.ime.typing

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/**
 * A `.glyd` dictionary (shared/typing/FORMAT.md): memory-mapped for the base
 * language, or built in memory for pack, added and learned words. Mirror of
 * Engine/Typing/GlydTrie.swift.
 */
class GlydTrie private constructor(private val buf: ByteBuffer) {

    companion object {
        const val NONE = -1                 // 0xFFFFFFFF as a signed int
        const val FLAG_OFFENSIVE = 1
        const val FLAG_NOT_A_WORD = 2
        const val FLAG_WHITELIST = 4
        const val FLAG_HAS_UPPER = 8

        fun wrap(bytes: ByteBuffer): GlydTrie? {
            val b = bytes.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            if (b.capacity() < 44 || b.getInt(0) != 0x44594C47 || b.getInt(4) != 1) return null
            val t = GlydTrie(b)
            return if (t.valid) t else null
        }

        fun mapped(file: File): GlydTrie? = try {
            RandomAccessFile(file, "r").use { raf ->
                wrap(raf.channel.map(FileChannel.MapMode.READ_ONLY, 0, raf.length()))
            }
        } catch (_: Exception) { null }

        fun load(bytes: ByteArray): GlydTrie? = wrap(ByteBuffer.wrap(bytes))

        /** Same layout as tools/build_dictionary.py, without bigrams. */
        fun build(words: List<Word>): GlydTrie {
            class Node {
                val children = HashMap<Int, Node>()
                val forms = ArrayList<Word>()
            }
            val root = Node()
            for (w in words) {
                val key = TypingText.key(w.form)
                if (key.isEmpty()) continue
                var node = root
                key.codePoints().forEach { cp -> node = node.children.getOrPut(cp) { Node() } }
                val flags = w.flags or (if (TypingText.hasUppercase(w.form)) FLAG_HAS_UPPER else 0)
                val i = node.forms.indexOfFirst { it.form == w.form }
                if (i >= 0) {
                    val old = node.forms[i]
                    node.forms[i] = Word(old.form, maxOf(old.probability, w.probability), old.flags or flags)
                } else {
                    node.forms.add(Word(w.form, w.probability, flags))
                }
            }
            val order = ArrayList<Pair<Node, Int>>()
            order.add(root to 0)
            var head = 0
            while (head < order.size) {
                val (node, _) = order[head++]
                for (s in node.children.keys.sorted()) order.add(node.children[s]!! to s)
            }
            val indexOf = HashMap<Node, Int>()
            order.forEachIndexed { i, p -> indexOf[p.first] = i }
            val maxProb = IntArray(order.size)
            for (i in order.indices.reversed()) {
                val node = order[i].first
                var best = 0
                for (f in node.forms) if (f.flags and (FLAG_OFFENSIVE or FLAG_NOT_A_WORD) == 0) best = maxOf(best, f.probability)
                for (c in node.children.values) best = maxOf(best, maxProb[indexOf[c]!!])
                maxProb[i] = best
            }
            val strings = java.io.ByteArrayOutputStream()
            val nodeBytes = ByteBuffer.allocate(order.size * 16).order(ByteOrder.LITTLE_ENDIAN)
            val entryList = ArrayList<Word>()
            val entryOffsets = ArrayList<Pair<Int, Int>>()
            for ((i, item) in order.withIndex()) {
                val node = item.first
                val sorted = node.children.keys.sorted()
                val firstChild = if (sorted.isEmpty()) NONE else indexOf[node.children[sorted[0]]!!]!!
                val forms = node.forms.sortedWith(compareByDescending<Word> { it.probability }.thenBy { it.form })
                nodeBytes.putInt((item.second and 0xFFFFFF) or (maxProb[i] shl 24))
                nodeBytes.putInt(firstChild)
                nodeBytes.putShort(sorted.size.toShort())
                nodeBytes.putShort(forms.size.toShort())
                nodeBytes.putInt(if (forms.isEmpty()) NONE else entryList.size)
                for (f in forms) {
                    val utf8 = f.form.toByteArray(Charsets.UTF_8)
                    entryOffsets.add(strings.size() to utf8.size)
                    strings.write(utf8)
                    entryList.add(f)
                }
            }
            val entryBytes = ByteBuffer.allocate(entryList.size * 16).order(ByteOrder.LITTLE_ENDIAN)
            entryList.forEachIndexed { i, f ->
                entryBytes.putInt(entryOffsets[i].first)
                entryBytes.putShort(entryOffsets[i].second.toShort())
                entryBytes.put(f.probability.toByte())
                entryBytes.put(f.flags.toByte())
                entryBytes.putInt(NONE)
                entryBytes.putShort(0)
                entryBytes.putShort(0)
            }
            val stringBytes = strings.toByteArray()
            val header = 44
            val nodesOff = header
            val entriesOff = nodesOff + nodeBytes.capacity()
            val stringsOff = entriesOff + entryBytes.capacity()
            val out = ByteBuffer.allocate(stringsOff + stringBytes.size).order(ByteOrder.LITTLE_ENDIAN)
            out.put("GLYD".toByteArray(Charsets.US_ASCII))
            for (v in intArrayOf(1, order.size, entryList.size, 0, stringBytes.size, nodesOff, entriesOff, stringsOff, stringsOff, 0)) out.putInt(v)
            out.put(nodeBytes.array())
            out.put(entryBytes.array())
            out.put(stringBytes)
            return load(out.array())!!
        }
    }

    data class Word(val form: String, val probability: Int, val flags: Int = 0)

    val nodeCount = buf.getInt(8)
    val entryCount = buf.getInt(12)
    private val bigramCount = buf.getInt(16)
    private val stringBytes = buf.getInt(20)
    private val nodesOff = buf.getInt(24)
    private val entriesOff = buf.getInt(28)
    private val bigramsOff = buf.getInt(32)
    private val stringsOff = buf.getInt(36)
    private val valid = nodeCount > 0 &&
        nodesOff.toLong() + nodeCount * 16L <= buf.capacity() &&
        entriesOff.toLong() + entryCount * 16L <= buf.capacity() &&
        bigramsOff.toLong() + bigramCount * 8L <= buf.capacity() &&
        stringsOff.toLong() + stringBytes <= buf.capacity()

    fun scalar(node: Int): Int = buf.getInt(nodesOff + node * 16) and 0xFFFFFF
    fun maxProbability(node: Int): Int = buf.getInt(nodesOff + node * 16) ushr 24
    fun firstChild(node: Int): Int = buf.getInt(nodesOff + node * 16 + 4)
    fun childCount(node: Int): Int = buf.getShort(nodesOff + node * 16 + 8).toInt() and 0xFFFF
    fun entryCount(node: Int): Int = buf.getShort(nodesOff + node * 16 + 10).toInt() and 0xFFFF
    fun firstEntry(node: Int): Int = buf.getInt(nodesOff + node * 16 + 12)

    fun child(node: Int, scalar: Int): Int {
        val first = firstChild(node)
        if (first == NONE) return NONE
        var lo = first
        var hi = first + childCount(node)
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            val s = scalar(mid)
            if (s == scalar) return mid
            if (s < scalar) lo = mid + 1 else hi = mid
        }
        return NONE
    }

    fun node(key: String): Int {
        var node = 0
        var i = 0
        while (i < key.length) {
            val cp = key.codePointAt(i)
            node = child(node, cp)
            if (node == NONE) return NONE
            i += Character.charCount(cp)
        }
        return node
    }

    fun form(entry: Int): String {
        val base = entriesOff + entry * 16
        val offset = buf.getInt(base)
        val length = buf.getShort(base + 4).toInt() and 0xFFFF
        val bytes = ByteArray(length)
        for (i in 0 until length) bytes[i] = buf.get(stringsOff + offset + i)
        return String(bytes, Charsets.UTF_8)
    }

    fun probability(entry: Int): Int = buf.get(entriesOff + entry * 16 + 6).toInt() and 0xFF
    fun flags(entry: Int): Int = buf.get(entriesOff + entry * 16 + 7).toInt() and 0xFF

    /** Next words recorded for this entry, most probable first: (target entry, probability). */
    fun bigrams(entry: Int): List<Pair<Int, Int>> {
        val base = entriesOff + entry * 16
        val first = buf.getInt(base + 8)
        val count = buf.getShort(base + 12).toInt() and 0xFFFF
        if (first == NONE || count == 0) return emptyList()
        return (0 until count).map { i ->
            val at = bigramsOff + (first + i) * 8
            buf.getInt(at) to (buf.get(at + 4).toInt() and 0xFF)
        }
    }

    fun bigramProbability(from: Int, to: Int): Int? = bigrams(from).firstOrNull { it.first == to }?.second
}
