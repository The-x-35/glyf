package com.demo.glyf.ime.typing

import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/** Prints how the engine treats real typing on the shipped dictionary. */
class RealDictionaryEval {
    private fun dict(): File? {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "app/dict/en.glyd").exists()) dir = dir.parentFile
        return dir?.let { File(it, "app/dict/en.glyd") }
    }

    @Test fun report() {
        val file = dict()
        assumeTrue(file != null)
        val engine = TypingEngine(GlydTrie.mapped(file!!))
        val cases = listOf(
            "teh", "hte", "recieve", "definately", "tomorow", "thnaks", "becuase", "wierd", "alot", "dont", "im", "cant",
            "wont", "didnt", "youre", "thats", "helo", "adress", "untill", "occured", "seperate", "goign", "waht", "jsut",
            "knwo", "abotu", "freind", "beleive", "wiht", "taht", "realy", "tommorow", "whcih", "shoudl", "coudl", "hsa",
            "arpit", "Arpit", "glyf", "zomato", "swiggy", "lol", "omg", "idk", "u", "ur", "k", "ok", "bro", "bruh",
            "hum", "bot", "id", "os", "form", "from", "acha", "accha", "yaar", "yar", "kal", "bhai", "hai", "kya", "nahi",
            "haan", "theek", "matlab", "bas", "chalo", "arre", "mera", "tera", "hua", "kar", "raha", "tha", "ho",
            "delhi", "anvika", "rohan", "priya", "figma", "bgmi", "insta", "gonna", "wanna", "gotta", "tbh", "ngl", "fr",
        )
        val start = System.nanoTime()
        for (w in cases) {
            val s = engine.suggestions(w, null, "the", sentenceStart = w[0].isUpperCase(), policy = TypingEngine.ALL)
            println(String.format("%-12s -> %-12s known=%-5s alts=%s", w, s.autocorrect ?: "·", s.known, s.alternatives))
        }
        val ms = (System.nanoTime() - start) / 1e6
        println("decode ${cases.size} words: ${"%.1f".format(ms)} ms total, ${"%.2f".format(ms / cases.size)} ms/word (JVM, cold)")
        val warm = System.nanoTime()
        repeat(3) { for (w in cases) engine.suggestions(w, null, "the", false, TypingEngine.ALL) }
        println("warm: ${"%.2f".format((System.nanoTime() - warm) / 1e6 / (3 * cases.size))} ms/word")
        for (p in listOf("thank", "good", "how", "see", "on", "happy")) println("next after $p: ${engine.predictions(p)}")
        for (w in listOf("waht", "definately", "seperate", "tommorow", "yaar", "chalo", "arre", "priya", "hsa", "bas")) {
            println("DEBUG $w: " + engine.debugCandidates(w, "the").joinToString(" | "))
        }
    }
}
