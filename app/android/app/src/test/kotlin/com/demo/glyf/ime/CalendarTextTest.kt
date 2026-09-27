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

    @Test fun anEventAddedToGoogleShowsUntilThePhoneHasIt() {
        val added = CalendarText.Event("Demo call", at(18), at(19), false,
            "https://meet.google.com/abc-defg-hij", googleId = "e1")
        val lunch = CalendarText.Event("Lunch", at(13), at(14), false)

        // Not on the phone yet: the list shows the keyboard's copy, still waiting.
        val (shown, pending) = CalendarText.withAdded(listOf(added), listOf(lunch), now = at(12))
        assertEquals(listOf("Lunch", "Demo call"), shown.map { it.title })
        assertEquals(listOf(added), pending)

        // Google synced it: the phone's copy (same title, same start) is the one shown.
        val synced = CalendarText.Event("demo call ", at(18), at(19), false, id = 9L)
        val later = CalendarText.withAdded(listOf(added), listOf(lunch, synced), now = at(12))
        assertEquals(listOf(lunch, synced), later.first)
        assertEquals(emptyList<CalendarText.Event>(), later.second)

        // Another event at the same time is not it; an event long over is let go.
        val gym = CalendarText.Event("Gym", at(18), at(19), false)
        assertEquals(listOf(added), CalendarText.withAdded(listOf(added), listOf(gym), now = at(12)).second)
        assertEquals(emptyList<CalendarText.Event>(),
            CalendarText.withAdded(listOf(added), emptyList(), now = at(12) + 7 * 86_400_000L).second)
    }

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

    @Test fun googleListBecomesEventsAndItsCopyWins() {
        val zone = java.util.TimeZone.getTimeZone("Asia/Kolkata")
        val json = org.json.JSONObject("""{"items":[
            {"summary":"Standup","id":"e1","status":"confirmed",
             "start":{"dateTime":"2026-09-28T11:00:00+05:30"},
             "end":{"dateTime":"2026-09-28T11:30:00+05:30"}},
            {"summary":"Off","id":"e2",
             "start":{"date":"2026-09-29"},"end":{"date":"2026-09-30"}},
            {"summary":"Gone","id":"e3","status":"cancelled",
             "start":{"dateTime":"2026-09-28T15:00:00+05:30"},
             "end":{"dateTime":"2026-09-28T16:00:00+05:30"}}
        ]}""")
        val google = GoogleEvent.eventsFromList(json, zone)
        assertEquals(2, google.size)
        assertEquals("Standup", google[0].title)
        assertEquals(false, google[0].allDay)
        assertEquals(true, google[1].allDay)
        assertEquals(86_400_000L, google[1].end - google[1].start)

        // The phone still holds Standup at its old time (edited on the web):
        // Google's copy wins for that day; what only the phone knows stays.
        val old = CalendarText.Event("Standup", google[0].start - 3_600_000, google[0].end - 3_600_000, false)
        val dentist = CalendarText.Event("Dentist", google[0].start + 7_200_000, google[0].end + 7_200_000, false)
        val merged = CalendarText.withGoogle(google, listOf(old, dentist), zone)
        assertEquals(1, merged.count { it.title == "Standup" })
        assertEquals(google[0].start, merged.first { it.title == "Standup" }.start)
        assertEquals(true, dentist in merged)
        assertEquals(listOf(dentist), CalendarText.withGoogle(emptyList(), listOf(dentist), zone))

        // Renamed on the web: same iCalendar UID, new title. One row, Google's.
        val web = google[0].copy(title = "Standup (moved)", external = "abc123@google.com")
        val stale = CalendarText.Event("Standup", web.start, web.end, false,
            external = "abc123@google.com", owner = "arpit@gmail.com")
        assertEquals(listOf("Dentist", "Standup (moved)"),
            CalendarText.withGoogle(listOf(web), listOf(stale, dentist), zone).map { it.title }.sorted())

        // Deleted on the web: the phone's copy in the account's own calendar
        // goes too; other calendars stay.
        val holiday = CalendarText.Event("Holiday", web.start, web.end, true,
            owner = "en.indian#holiday@group.v.calendar.google.com")
        assertEquals(listOf(holiday),
            CalendarText.withGoogle(emptyList(), listOf(stale, holiday), zone, primary = "Arpit@gmail.com"))
    }
}
