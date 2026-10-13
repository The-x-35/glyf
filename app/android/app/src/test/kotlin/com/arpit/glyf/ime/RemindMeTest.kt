package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.TimeZone

/** iOS GlyfEngineTests.testARemindMeWithADayIsNineAM. */
class RemindMeTest {
    @Test fun aRemindMeWithADayIsNineAM() {
        val tz = TimeZone.getTimeZone("America/New_York")
        val now = java.time.Instant.parse("2026-10-14T15:00:00Z").toEpochMilli()
        val p = EventParse.looksLikePlan("remind me to call mom tomorrow", now, tz)
        assertNotNull(p)
        assertEquals("Call mom", p!!.title)
        val start = java.time.Instant.ofEpochMilli(p.start).atZone(tz.toZoneId())
        assertEquals(9, start.hour)
        assertEquals(15, start.dayOfMonth)
        assertEquals(30 * 60_000L, p.end - p.start)
        assertNull(EventParse.looksLikePlan("call mom tomorrow", now, tz))
    }
}
