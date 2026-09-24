package com.demo.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** The same cases as EventParseTests.swift, against the same fixed morning:
 *  Wednesday 23 September 2026, 10:00 in India, weeks starting Monday. */
class EventParseTest {
    private val tz = TimeZone.getTimeZone("Asia/Kolkata")
    private val now: Long = Calendar.getInstance(tz).apply {
        clear(); set(2026, Calendar.SEPTEMBER, 23, 10, 0)
    }.timeInMillis

    private fun fmt(ms: Long): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply { timeZone = tz }.format(ms)

    /** "title | start – end | flags", flags: D (a day was named), T (a time), A (all day). */
    private fun read(text: String, dayFirst: Boolean = true): String {
        val p = EventParse.parse(text, now, tz, dayFirst, Calendar.MONDAY)
        val flags = (if (p.hasDay) "D" else "") + (if (p.hasTime) "T" else "") + (if (p.allDay) "A" else "")
        return "${p.title} | ${fmt(p.start)} – ${fmt(p.end)} | $flags"
    }

    private fun plan(text: String) = EventParse.looksLikePlan(text, now, tz, true, Calendar.MONDAY) != null

    @Test fun daysAndTimes() {
        assertEquals("Lunch with Sam | 2026-09-24 13:00 – 2026-09-24 14:00 | DT", read("Lunch with Sam tomorrow 1pm"))
        assertEquals("Call | 2026-09-23 17:00 – 2026-09-23 18:00 | T", read("call at 5"))
        assertEquals("Standup | 2026-09-24 09:00 – 2026-09-24 10:00 | T", read("standup at 9"))
        assertEquals("Dinner | 2026-09-25 20:00 – 2026-09-25 21:00 | DT", read("dinner friday 8pm"))
        assertEquals("Meet | 2026-09-24 17:00 – 2026-09-24 18:00 | DT", read("let's meet tomorrow at 5"))
        assertEquals("Meet | 2026-09-23 18:00 – 2026-09-23 19:00 | T", read("let’s meet at 6"))
        assertEquals("Demo | 2026-09-25 15:00 – 2026-09-25 16:00 | DT", read("25 sep 3pm demo"))
        assertEquals(" | 2026-09-30 16:00 – 2026-09-30 17:00 | DT", read("sep 30 at 4"))
        assertEquals("Meeting | 2026-09-23 15:30 – 2026-09-23 16:30 | T", read("meeting at 3:30"))
        assertEquals("Call | 2026-09-23 17:30 – 2026-09-23 18:30 | T", read("5.30pm call"))
        assertEquals("Sync | 2026-09-23 17:00 – 2026-09-23 18:00 | T", read("17:00 sync"))
        assertEquals("Lunch | 2026-09-23 12:00 – 2026-09-23 13:00 | T", read("noon lunch"))
        assertEquals("Launch | 2026-09-24 00:00 – 2026-09-24 01:00 | DT", read("midnight launch"))
        assertEquals("Dinner | 2026-09-23 20:00 – 2026-09-23 21:00 | T", read("dinner at 8"))
        assertEquals("Sync | 2026-09-30 11:00 – 2026-09-30 12:00 | DT", read("sync on the 30th at 11"))
        assertEquals("Rent due | 2026-10-05 09:00 – 2026-10-05 10:00 | D", read("rent due the 5th"))
    }

    @Test fun rangesDurationsAndRelative() {
        assertEquals("Meeting | 2026-09-24 10:30 – 2026-09-24 11:30 | DT", read("meeting 10:30-11:30am tomorrow"))
        assertEquals("Review | 2026-09-28 11:00 – 2026-09-28 13:00 | DT", read("review 11-1pm on monday"))
        assertEquals("Party | 2026-09-23 17:00 – 2026-09-23 19:00 | T", read("from 5 to 7 party"))
        assertEquals("Workshop | 2026-09-24 10:00 – 2026-09-24 12:00 | DT", read("workshop tomorrow 10am for 2 hours"))
        assertEquals("Call | 2026-09-23 10:30 – 2026-09-23 11:30 | DT", read("call in 30 mins"))
        assertEquals("Offsite | 2026-09-25 00:00 – 2026-09-26 00:00 | DA", read("offsite all day friday"))
    }

    @Test fun partsOfTheDayAndWeeks() {
        assertEquals("Dinner | 2026-09-23 20:00 – 2026-09-23 21:00 | DT", read("dinner tonight"))
        assertEquals("Drinks | 2026-09-24 18:00 – 2026-09-24 19:00 | DT", read("tomorrow evening drinks"))
        assertEquals("Coffee | 2026-10-02 09:00 – 2026-10-02 10:00 | D", read("next friday coffee"))
        assertEquals("Trip | 2026-09-26 09:00 – 2026-09-26 10:00 | D", read("weekend trip"))
        assertEquals("Meeting | 2026-09-23 17:00 – 2026-09-23 18:00 | T", read("good morning! meeting at 5"))
        assertFalse(EventParse.parse("I slept late last night", now, tz, true, Calendar.MONDAY).hasTime)
    }

    @Test fun hinglish() {
        assertEquals("Milte hain | 2026-09-24 17:00 – 2026-09-24 18:00 | DT", read("kal 5 baje milte hain"))
        assertEquals("Interview | 2026-09-25 11:00 – 2026-09-25 12:00 | DT", read("parso 11 baje interview"))
        assertEquals("Dinner | 2026-09-24 19:00 – 2026-09-24 20:00 | DT", read("kal shaam 7 baje dinner"))
    }

    @Test fun numericDatesFollowTheRegion() {
        assertEquals("Christmas lunch | 2026-12-25 13:00 – 2026-12-25 14:00 | D", read("25/12 christmas lunch"))
        assertEquals("Christmas lunch | 2026-12-25 13:00 – 2026-12-25 14:00 | D", read("12/25 christmas lunch", dayFirst = false))
    }

    @Test fun nothingSaidIsTheNextHour() {
        assertEquals("Dentist | 2026-09-23 11:00 – 2026-09-23 12:00 | ", read("Dentist"))
        assertEquals("5 people are coming | 2026-09-23 11:00 – 2026-09-23 12:00 | ", read("at 5 people are coming"))
    }

    @Test fun googleEventBody() {
        val start = Calendar.getInstance(tz).apply { clear(); set(2026, Calendar.SEPTEMBER, 25, 15, 0) }.timeInMillis
        val timed = GoogleEvent.body("Review", start, start + 3_600_000L, false, listOf("sam@example.com"),
            true, tz, "r1")
        assertEquals("Review", timed.getString("summary"))
        assertEquals("2026-09-25T15:00:00+05:30", timed.getJSONObject("start").getString("dateTime"))
        assertEquals("2026-09-25T16:00:00+05:30", timed.getJSONObject("end").getString("dateTime"))
        assertEquals("Asia/Kolkata", timed.getJSONObject("end").getString("timeZone"))
        assertEquals("sam@example.com", timed.getJSONArray("attendees").getJSONObject(0).getString("email"))
        val create = timed.getJSONObject("conferenceData").getJSONObject("createRequest")
        assertEquals("hangoutsMeet", create.getJSONObject("conferenceSolutionKey").getString("type"))
        assertEquals("r1", create.getString("requestId"))

        // All day: days, Google's end day not included; nobody asked, no call.
        val day = Calendar.getInstance(tz).apply { clear(); set(2026, Calendar.SEPTEMBER, 25) }.timeInMillis
        val allDay = GoogleEvent.body("Offsite", day, day + 86_400_000L, true, emptyList(), false, tz)
        assertEquals("2026-09-25", allDay.getJSONObject("start").getString("date"))
        assertEquals("2026-09-26", allDay.getJSONObject("end").getString("date"))
        assertFalse(allDay.has("attendees"))
        assertFalse(allDay.has("conferenceData"))
        assertEquals("sendUpdates=all&conferenceDataVersion=1", GoogleEvent.QUERY)
    }

    @Test fun peopleLine() {
        assertEquals("Sam Lee" to listOf("sam@x.com", "ria@y.com"), EventParse.people("Sam Lee sam@x.com, Ria@Y.com"))
        assertEquals("" to listOf("a@b.co"), EventParse.people("a@b.co a@b.co"))
        assertEquals("Just a name" to emptyList<String>(), EventParse.people("Just a name"))
        assertEquals("Arpit Singh" to listOf("arpit@gmail.com"), EventParse.people("<Arpit Singh> (arpit@gmail.com)"))
    }

    @Test fun whatCountsAsAPlan() {
        assertTrue(plan("let's grab coffee at 4"))
        assertTrue(plan("dinner friday 8pm?"))
        assertTrue(plan("call me tomorrow at 11"))
        assertTrue(plan("kal 5 baje milte hain"))
        assertFalse(plan("see you tomorrow"))
        assertFalse(plan("I woke up at 7"))
        assertFalse(plan("good morning"))
        assertFalse(plan("split is 3480/4"))
        assertFalse(plan("at 5 people are coming"))
        // What the calendar itself typed is already in the calendar.
        assertFalse(plan("📅 Lunch with Sam · Fri, Sep 25, 1:00–2:00 PM"))
        assertFalse(plan("I'm free Fri 25 Sep, 9:00 AM–1:00 PM and 3:00–9:00 PM"))
    }
}
