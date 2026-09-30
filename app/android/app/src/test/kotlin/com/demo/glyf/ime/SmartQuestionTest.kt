package com.demo.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Runs shared/questions/cases.json, the cases both keyboards are held to
 *  (iOS runs the same file): a question for a fact offers "AI answer" as it
 *  is typed, and chat, plans, the news and half-typed questions offer none. */
class SmartQuestionTest {

    private val cases: JSONObject by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/questions/cases.json").exists()) dir = dir.parentFile
        val file = File(requireNotNull(dir) { "shared/questions not found above ${System.getProperty("user.dir")}" },
            "shared/questions/cases.json")
        JSONObject(file.readText())
    }

    @Test fun everyQuestionIsAsked() {
        val list = cases.getJSONArray("ask")
        assertTrue(list.length() > 0)
        val failures = (0 until list.length()).map { list.getJSONObject(it) }.mapNotNull { c ->
            val got = Smart.question(c.getString("text"))
            val want = c.getString("question")
            if (got == want) null else "'${c.getString("text")}': got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test fun nothingElseIsAsked() {
        val list = cases.getJSONArray("not")
        assertTrue(list.length() > 0)
        val failures = (0 until list.length()).map { list.getString(it) }.mapNotNull { text ->
            val got = Smart.question(text)
            if (got == null) null else "'$text': got '$got', want none"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }
}
