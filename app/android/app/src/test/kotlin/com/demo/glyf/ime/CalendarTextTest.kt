package com.demo.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** The same cases as the iOS calendar tests. */
class CalendarTextTest {
    private val tz = TimeZone.getTimeZone("Asia/Kolkata")
    private val en = Locale.US

    private fun at(h: Int, m: Int = 0): Long = Calendar.getInstance(tz).apply {
        clear(); set(2026, Calendar.SEPTEMBER, 18, h, m)
    }.timeInMillis

    private fun plain(s: String) = s.replace('\u202F', ' ')

    @Test fun sharesAnEventAndFreeTime() {
        val day = at(0)
        val events = listOf(
            CalendarText.Event("Standup", at(10), at(10, 30), false),
            CalendarText.Event("Design review", at(15), at(16), false, "Studio"),
        )
        assertEquals("📅 Design review · Fri 18 Sep, 3:00–4:00 PM · Studio",
            plain(CalendarText.insert(events[1], tz, en)))
        assertEquals("I'm free Fri 18 Sep, 9:00–10:00 AM, 10:30 AM–3:00 PM and 4:00–9:00 PM",
            plain(CalendarText.freeTime(day, events, tz, en, now = day)))
        assertEquals("I'm free Fri 18 Sep, 4:00–9:00 PM",
            plain(CalendarText.freeTime(day, events, tz, en, now = at(15, 10))))
        assertEquals("I'm free all day Fri 18 Sep", CalendarText.freeTime(day, emptyList(), tz, en, now = day))
        val allDay = listOf(CalendarText.Event("Offsite", at(0), at(0) + 86_400_000L, true))
        assertEquals("I'm busy all day Fri 18 Sep", CalendarText.freeTime(day, allDay, tz, en, now = day))
    }
}
