package com.demo.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Runs shared/units/strip-cases.json (iOS runs the same file): a
 *  measurement the message ends on, in the other system, one chip per
 *  result, and never for "5 min", "4g", "1 m" or a range. */
class SmartUnitsTest {

    private val root: JSONObject by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/units/strip-cases.json").exists()) dir = dir.parentFile
        val file = File(requireNotNull(dir) { "shared/units not found above ${System.getProperty("user.dir")}" },
            "shared/units/strip-cases.json")
        JSONObject(file.readText())
    }

    @Test fun aMeasurementShowsInTheOtherSystem() {
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() > 30)
        val failures = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { c ->
            val want = c.getJSONArray("results").let { a -> (0 until a.length()).map { a.getString(it) } }
            val region = c.optString("region").ifEmpty { null }
            val got = Smart.conversions(c.getString("text"), region)?.results.orEmpty()
            if (got == want) null else "'${c.getString("text")}' ($region): got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    /** shared/zones/strip-cases.json: a time in someone else's zone, in the
     *  phone's own, with "now" fixed. */
    @Test fun aTimeInAnotherZoneShowsInYours() {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/zones/strip-cases.json").exists()) dir = dir.parentFile
        val zones = JSONObject(File(requireNotNull(dir), "shared/zones/strip-cases.json").readText())
        val now = java.time.Instant.parse(zones.getString("now"))
        val cases = zones.getJSONArray("cases")
        val failures = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { c ->
            val want = c.getJSONArray("results").let { a -> (0 until a.length()).map { a.getString(it) } }
            val here = java.time.ZoneId.of(c.getString("here"))
            val got = Smart.zoneTimes(c.getString("text"), now, here, c.optString("region").ifEmpty { null })?.results.orEmpty()
            if (got == want) null else "'${c.getString("text")}' in $here: got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    /** shared/quick/strip-cases.json: bills, arrivals, spans, dates in
     *  words, a bare temperature and a time in a city, each with its own "now". */
    @Test fun theStripWorksOutBillsArrivalsAndDates() {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/quick/strip-cases.json").exists()) dir = dir.parentFile
        val quick = JSONObject(File(requireNotNull(dir), "shared/quick/strip-cases.json").readText())
        val cases = quick.getJSONArray("cases")
        val failures = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { c ->
            val want = c.getJSONArray("results").let { a -> (0 until a.length()).map { a.getString(it) } }
            val answer = Smart.quickAnswer(c.getString("text"), java.time.Instant.parse(c.getString("now")),
                java.time.ZoneId.of(c.getString("here")), c.optString("region").ifEmpty { null })
            val got = answer?.results.orEmpty()
            if (got != want) return@mapNotNull "'${c.getString("text")}' (${c.optString("region")}): got $got, want $want"
            val inserts = c.optJSONArray("inserts")?.let { a -> (0 until a.length()).map { a.getString(it) } }
            if (inserts != null && answer != null && got.indices.map { answer.insert(it) } != inserts)
                return@mapNotNull "'${c.getString("text")}': inserts ${got.indices.map { answer.insert(it) }}, want $inserts"
            val hows = c.optJSONArray("how")?.let { a -> (0 until a.length()).map { a.getString(it) } }
            if (hows != null && answer != null && got.indices.map { answer.how(it).name.lowercase() } != hows)
                return@mapNotNull "'${c.getString("text")}': how ${got.indices.map { answer.how(it).name.lowercase() }}, want $hows"
            null
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    /** shared/quick/paste-cases.json: a copy shown in its parts. */
    @Test fun aCopyShowsInItsParts() {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/quick/paste-cases.json").exists()) dir = dir.parentFile
        val cases = JSONObject(File(requireNotNull(dir), "shared/quick/paste-cases.json").readText()).getJSONArray("cases")
        val failures = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { c ->
            val want = if (c.isNull("parts")) null else c.getJSONArray("parts").let { a -> (0 until a.length()).map { a.getString(it) } }
            val got = Smart.pieces(c.getString("copy"))
            if (got == want) null else "'${c.getString("copy")}': got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    /** shared/style/cases.json: text in each of Style's styles, and Plain
     *  turning it back. */
    @Test fun textTakesEachStyleAndPlainTurnsItBack() {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/style/cases.json").exists()) dir = dir.parentFile
        val root = JSONObject(File(requireNotNull(dir), "shared/style/cases.json").readText())
        val back = root.getJSONArray("plainBack").let { a -> (0 until a.length()).map { a.getString(it) } }
        val cases = root.getJSONArray("cases")
        val failures = mutableListOf<String>()
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val text = c.getString("text")
            val styled = c.getJSONObject("styled")
            for (id in styled.keys()) {
                val style = Smart.TextStyle.of(id)
                if (style == null) { failures.add("no style $id"); continue }
                val got = Smart.styled(text, style)
                if (got != styled.getString(id)) failures.add("$id '$text': got $got, want ${styled.getString(id)}")
                if (id in back && Smart.plainText(got) != text) failures.add("plain of $id '$got': got ${Smart.plainText(got)}")
            }
        }
        // A style starts from plain letters: bold over italic is bold.
        assertEquals(Smart.styled("Hi", Smart.TextStyle.BOLD), Smart.styled(Smart.styled("Hi", Smart.TextStyle.ITALIC), Smart.TextStyle.BOLD))
        // Plain leaves what was never styled: ™, ½, emoji.
        assertEquals("Glyf™ ½ 🎉", Smart.plainText("Glyf™ ½ 🎉"))
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test fun aMeasurementIsAChipAndATapAddsItInBrackets() {
        assertEquals(Smart.Chip.Convert(Smart.Conversions("10 inch", listOf("25.4 cm", "0.254 m"))),
            Smart.chip("lets 10 inch", emptyList(), region = "US"))
        // A sum is still a sum.
        assertTrue(Smart.chip("12+30", emptyList(), region = "US") is Smart.Chip.Calc)
        assertEquals(" (25.4 cm)", Smart.conversionInsert("25.4 cm", "lets 10 inch"))
        assertEquals("(25.4 cm) ", Smart.conversionInsert("25.4 cm", "lets 10 inch "))
    }
}
