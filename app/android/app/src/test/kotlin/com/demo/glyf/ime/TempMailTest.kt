package com.demo.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Calendar

/** Temp mail's rules that need no phone: when a turned-away day ends, and
 *  how the inbox says when a mail came. */
class TempMailTest {

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int) =
        Calendar.getInstance().apply {
            clear()
            set(year, month, day, hour, minute)
        }.timeInMillis

    @Test fun checksComeBackAtLocalMidnight() {
        // A 429 late in the evening lasts only until the day ends.
        assertEquals(at(2026, Calendar.OCTOBER, 1, 0, 0),
            TempMailClient.nextMidnight(at(2026, Calendar.SEPTEMBER, 30, 23, 59)))
        // One just after midnight waits for the next one, a day on.
        assertEquals(at(2026, Calendar.OCTOBER, 2, 0, 0),
            TempMailClient.nextMidnight(at(2026, Calendar.OCTOBER, 1, 0, 1)))
        // Across a year.
        assertEquals(at(2027, Calendar.JANUARY, 1, 0, 0),
            TempMailClient.nextMidnight(at(2026, Calendar.DECEMBER, 31, 12, 0)))
    }

    @Test fun agoReadsAsTheInboxShowsIt() {
        val now = 1_000_000_000L
        assertEquals("now", TempMailClient.ago(now - 30_000, now))
        assertEquals("2m", TempMailClient.ago(now - 2 * 60_000, now))
        assertEquals("3h", TempMailClient.ago(now - 3 * 3_600_000, now))
        assertEquals("1d", TempMailClient.ago(now - 26 * 3_600_000, now))
        // A clock a little behind the server's still reads "now".
        assertEquals("now", TempMailClient.ago(now + 5_000, now))
    }
}
