package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Runs shared/vault/cases.json, the cases both keyboards are held to (iOS
 *  runs the same file): a saved detail comes up by its kind's words or by
 *  the person's own label for it, and never for someone else's detail or an
 *  everyday sentence. */
class SmartVaultTest {

    private val root: JSONObject by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/vault/cases.json").exists()) dir = dir.parentFile
        val file = File(requireNotNull(dir) { "shared/vault not found above ${System.getProperty("user.dir")}" },
            "shared/vault/cases.json")
        JSONObject(file.readText())
    }

    @Test fun everyCaseOffersWhatItShould() {
        val f = root.getJSONArray("fields")
        val fields = (0 until f.length()).map { f.getJSONObject(it) }
            .map { Smart.Field(it.getString("kind"), it.getString("label"), it.getString("value")) }
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() > 0)
        val failures = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { c ->
            val want = c.getJSONArray("values").let { a -> (0 until a.length()).map { a.getString(it) } }
            val got = Smart.vaultMatches(c.getString("text"), fields).map { it.value }
            if (got == want) null else "'${c.getString("text")}': got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }
}
