package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS GlyfEngineTests.testAPlanSaysWhenTheCalendarIsBusy. */
class BusyNoteTest {
    @Test fun aPlanSaysWhenTheCalendarIsBusy() {
        val start = java.time.Instant.parse("2026-10-16T13:00:00Z").toEpochMilli()
        val end = start + 3_600_000
        val plan = EventParse.Plan("Lunch", start, end, allDay = false, hasDay = true, hasTime = true)
        val dentist = CalendarText.Event("Dentist", start + 1_800_000, start + 5_400_000, false)
        val birthday = CalendarText.Event("Sam's birthday", start - 13 * 3_600_000L, start + 11 * 3_600_000L, true)
        val later = CalendarText.Event("Gym", end, end + 3_600_000, false)
        assertEquals("busy: Dentist", EventParse.busyNote(plan, listOf(birthday, dentist)))
        assertNull(EventParse.busyNote(plan, listOf(birthday, later)))
        assertNull(EventParse.busyNote(plan.copy(allDay = true), listOf(dentist)))
    }
}
