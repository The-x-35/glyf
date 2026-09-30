package com.demo.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Runs shared/tempmail/cases.json, the cases both keyboards are held to
 *  (iOS runs the same file), through the Kotlin port of RULES.md: the code
 *  a mail carries, the link it asks to be opened, and its HTML as text. */
class TempMailTest {

    private val cases: JSONObject by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/tempmail/cases.json").exists()) dir = dir.parentFile
        val file = File(requireNotNull(dir) { "shared/tempmail not found above ${System.getProperty("user.dir")}" },
            "shared/tempmail/cases.json")
        JSONObject(file.readText())
    }

    private fun JSONObject.nullable(key: String): String? = if (isNull(key)) null else getString(key)

    @Test fun everyCodeCase() {
        val list = cases.getJSONArray("codes")
        assertTrue(list.length() > 0)
        val failures = (0 until list.length()).map { list.getJSONObject(it) }.mapNotNull { c ->
            val got = TempMailRules.extractCode(c.getString("subject"), c.getString("text"))
            val want = c.nullable("code")
            if (got == want) null else "'${c.getString("subject")}': got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test fun everyLinkCase() {
        val list = cases.getJSONArray("links")
        assertTrue(list.length() > 0)
        val failures = (0 until list.length()).map { list.getJSONObject(it) }.mapNotNull { c ->
            val got = TempMailRules.extractLink(c.getString("text"), c.getString("html"))
            val want = c.nullable("link")
            if (got == want) null else "'${c.getString("text")}${c.getString("html")}': got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test fun everyHtmlCase() {
        val list = cases.getJSONArray("html")
        assertTrue(list.length() > 0)
        for (i in 0 until list.length()) {
            val c = list.getJSONObject(i)
            assertEquals(c.getString("text"), TempMailRules.htmlToText(c.getString("html")))
        }
    }

    @Test fun aMailReadsItsSenderTextAndCode() {
        // The shape GET /messages/{id} answers with: no plain text, only HTML.
        val mail = TempMailRules.mail(JSONObject("""{"id":"m1","from":{"address":"no-reply@acme.example","name":""},
            "subject":"Welcome","text":"","html":["<p>Your verification code is <b>482913</b>.</p>"],
            "createdAt":"2026-09-30T10:00:00+00:00"}"""))!!
        assertEquals("no-reply@acme.example", mail.from)   // no name: the address
        assertEquals("Your verification code is 482913 .", mail.text)
        assertEquals("482913", mail.code)
    }

    @Test fun agoReadsAsTheInboxShowsIt() {
        val now = 1_000_000_000L
        assertEquals("now", TempMailRules.ago(now - 30_000, now))
        assertEquals("2m", TempMailRules.ago(now - 2 * 60_000, now))
        assertEquals("3h", TempMailRules.ago(now - 3 * 3_600_000, now))
        assertEquals("1d", TempMailRules.ago(now - 26 * 3_600_000, now))
        // A clock a little behind mail.tm's still reads "now".
        assertEquals("now", TempMailRules.ago(now + 5_000, now))
    }
}
