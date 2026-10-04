package com.arpit.glyf.ime.typing

import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Both engines on the same inputs, line for line (off unless asked for).
 * GLYF_PARITY_DIR holds in.tsv — previous word, typed, "1" at a sentence
 * start, the word before the previous — and this writes kotlin.tsv beside it; RunnerTests'
 * testParityDump writes swift.tsv from the same file. They must match.
 *
 *   GLYF_PARITY_DIR=/tmp/parity ./gradlew :app:testDebugUnitTest --tests '*TypingParity*' --rerun
 */
class TypingParity {
    @Test fun dump() {
        val dir = System.getenv("GLYF_PARITY_DIR")?.let { File(it) }
        assumeTrue(dir != null && File(dir, "in.tsv").exists())
        var root: File? = File(System.getProperty("user.dir")).absoluteFile
        while (root != null && !File(root, "app/dict/en.glyd").exists()) root = root.parentFile
        val engine = TypingEngine(GlydTrie.mapped(File(root, "app/dict/en.glyd")))
        val out = StringBuilder()
        for (line in File(dir, "in.tsv").readLines()) {
            val (previous, typed, start, twoBack) = (line.split('\t') + listOf("", "", "", "")).take(4)
            val prev = previous.ifEmpty { null }
            val prev2 = twoBack.ifEmpty { null }
            if (typed.isEmpty()) {
                out.append(engine.predictions(prev, TypingEngine.ALL, 20_000, prev2).joinToString(",")).append('\n')
                continue
            }
            val s = engine.suggestions(typed, null, prev, start == "1", TypingEngine.ALL, 20_000, prev2)
            out.append(s.autocorrect ?: "-").append('\t').append(s.alternatives.joinToString(","))
                .append('\t').append(if (s.known) "known" else "").append('\n')
        }
        File(dir!!, "kotlin.tsv").writeText(out.toString())
    }
}
