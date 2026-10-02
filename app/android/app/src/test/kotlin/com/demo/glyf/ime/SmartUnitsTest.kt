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

    @Test fun aMeasurementIsAChipAndATapAddsItInBrackets() {
        assertEquals(Smart.Chip.Convert("10 inch", listOf("25.4 cm", "0.254 m")),
            Smart.chip("lets 10 inch", emptyList(), region = "US"))
        // A sum is still a sum.
        assertTrue(Smart.chip("12+30", emptyList(), region = "US") is Smart.Chip.Calc)
        assertEquals(" (25.4 cm)", Smart.conversionInsert("25.4 cm", "lets 10 inch"))
        assertEquals("(25.4 cm) ", Smart.conversionInsert("25.4 cm", "lets 10 inch "))
    }
}
