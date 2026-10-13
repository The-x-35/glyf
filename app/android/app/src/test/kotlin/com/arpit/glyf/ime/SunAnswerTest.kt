package com.arpit.glyf.ime

import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

/** iOS GlyfEngineTests.testSunriseAndSunsetOnThePhone. */
class SunAnswerTest {
    @After fun clear() { SunAnswer.lastLocation = null }

    @Test fun sunriseAndSunsetOnThePhone() {
        val sf = ZoneId.of("America/Los_Angeles")
        val morning = Instant.parse("2026-06-21T15:00:00Z")
        SunAnswer.lastLocation = 37.7749 to -122.4194
        val set = SunAnswer.answer("what time is sunset", morning, sf)!!.results.first()
        assertTrue(set, set in setOf("Sunset 8:34 PM", "Sunset 8:35 PM", "Sunset 8:36 PM"))
        val rise = SunAnswer.answer("sunrise?", morning, sf)!!.results.first()
        assertTrue(rise, rise in setOf("Sunrise 5:47 AM", "Sunrise 5:48 AM", "Sunrise 5:49 AM"))
        assertNotNull(SunAnswer.answer("ok. golden hour tomorrow", morning, sf))
        assertNull(SunAnswer.answer("caption for my sunset photo", morning, sf))
        SunAnswer.lastLocation = null
        assertNull(SunAnswer.answer("sunset", morning, sf))
    }
}
