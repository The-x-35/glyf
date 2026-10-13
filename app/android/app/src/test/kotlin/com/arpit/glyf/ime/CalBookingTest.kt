package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URI
import java.net.URLDecoder

/** Booking links read and booked from the phone, with the server's own
 *  cases (server/test/scheduling.test.ts) against a stand-in Cal.com. */
class CalBookingTest {

    private data class Asked(val method: String, val url: String, val headers: Map<String, String>, val body: String?)

    /** Answers from a table of URL prefixes, and records what it was asked. */
    private class Fake(val table: Map<String, Pair<Int, String>>, val fail: Exception? = null) : CalBooking.Http {
        val asked = mutableListOf<Asked>()
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?): CalBooking.Response {
            asked += Asked(method, url, headers, body)
            fail?.let { throw it }
            val hit = table.entries.firstOrNull { url.startsWith(it.key) } ?: return CalBooking.Response(404, "{}")
            return CalBooking.Response(hit.value.first, hit.value.second)
        }
    }

    private fun query(url: String): Map<String, String> = URI(url).rawQuery.split('&').associate {
        val (k, v) = it.split('=', limit = 2)
        URLDecoder.decode(k, "UTF-8") to URLDecoder.decode(v, "UTF-8")
    }

    @Test fun readsCalComAndCalendlyLinksHoweverTyped() {
        assertEquals(CalBooking.Link("calcom", "https://cal.com/jane/30min", "jane", "30min", null),
            CalBooking.parse("cal.com/jane/30min"))
        assertEquals("https://cal.com/jane", CalBooking.parse("https://app.cal.com/jane")?.base)
        val org = CalBooking.parse("physics.cal.com/rick/15min")!!
        assertEquals("physics", org.org); assertEquals("rick", org.username); assertEquals("15min", org.slug)
        assertEquals(CalBooking.Link("calendly", "https://calendly.com/jane/intro", "jane", "intro", null),
            CalBooking.parse("https://calendly.com/jane/intro?month=2026-09"))
        assertNull(CalBooking.parse("cal.com"))
        assertNull(CalBooking.parse("example.com/jane"))
        assertNull(CalBooking.parse("cal.com/jane/<script>"))
        assertEquals("https://cal.com/jane", CalBooking.parse("  www.Cal.com/jane/ ")?.base)
    }

    @Test fun opensThePageOnADayAndCalComOnTheTimeItself() {
        val cal = CalBooking.parse("cal.com/jane/30min")!!
        assertEquals("https://cal.com/jane/30min?month=2026-10&date=2026-10-06&slot=2026-10-06T08%3A40%3A00.000Z",
            CalBooking.bookingUrl(cal, "2026-10-06", "2026-10-06T08:40:00.000Z"))
        val calendly = CalBooking.parse("calendly.com/jane/intro")!!
        assertEquals("https://calendly.com/jane/intro?month=2026-09&date=2026-09-25",
            CalBooking.bookingUrl(calendly, "2026-09-25", "2026-09-25T10:00:00.000Z"))
    }

    @Test fun givesCalendlysLinkOnTheDayWithoutAsking() {
        val fake = Fake(emptyMap())
        val r = CalBooking.slots("calendly.com/jane/intro", "2026-09-25", 3, "Asia/Kolkata", http = fake)
        assertEquals(CalBooking.Outcome.Ok(CalBooking.Slots("calendly", "https://calendly.com/jane/intro",
            "https://calendly.com/jane/intro?month=2026-09&date=2026-09-25", null, null, emptyList())), r)
        assertEquals(0, fake.asked.size)
    }

    @Test fun givesCalComsOpenTimesEachOpeningOnTheSlot() {
        val fake = Fake(mapOf("https://api.cal.com/v2/slots" to (200 to JSONObject().put("status", "success").put("data", JSONObject()
            .put("2026-09-27", JSONArray().put(JSONObject().put("start", "2026-09-27T23:30:00.000+05:30")))
            .put("2026-09-28", JSONArray().put(JSONObject().put("start", "2026-09-28T19:00:00.000+05:30"))
                .put(JSONObject().put("start", "2026-09-28T19:30:00.000+05:30")))
            .put("2026-09-29", JSONArray().put(JSONObject().put("start", "2026-09-29T10:00:00.000+05:30")))).toString())))
        val r = CalBooking.slots("cal.com/slot-test/30min", "2026-09-28", 1, "Asia/Kolkata", http = fake)
        val s = (r as CalBooking.Outcome.Ok).value
        assertEquals("calcom", s.provider)
        assertEquals(listOf(CalBooking.SlotDay("2026-09-28", listOf(
            CalBooking.SlotAt("2026-09-28T19:00:00.000+05:30",
                "https://cal.com/slot-test/30min?month=2026-09&date=2026-09-28&slot=2026-09-28T13%3A30%3A00.000Z"),
            CalBooking.SlotAt("2026-09-28T19:30:00.000+05:30",
                "https://cal.com/slot-test/30min?month=2026-09&date=2026-09-28&slot=2026-09-28T14%3A00%3A00.000Z"),
        ))), s.days)
        val q = query(fake.asked[0].url)
        assertEquals("30min", q["eventTypeSlug"])
        assertEquals("slot-test", q["username"])
        assertEquals("2026-09-27", q["start"])
        assertEquals("2026-09-29", q["end"])
        assertEquals("Asia/Kolkata", q["timeZone"])
        assertEquals("2024-09-04", fake.asked[0].headers["cal-api-version"])
    }

    @Test fun picksTheShortestShownEventWhenTheLinkNamesNone() {
        val fake = Fake(mapOf(
            "https://api.cal.com/v2/event-types" to (200 to JSONObject().put("status", "success").put("data", JSONArray()
                .put(JSONObject().put("slug", "60min").put("title", "Hour").put("lengthInMinutes", 60))
                .put(JSONObject().put("slug", "secret").put("title", "Hidden").put("lengthInMinutes", 5).put("hidden", true))
                .put(JSONObject().put("slug", "15min").put("title", "Quick chat").put("lengthInMinutes", 15))).toString()),
            "https://api.cal.com/v2/slots" to (200 to """{"status":"success","data":{}}"""),
        ))
        val s = (CalBooking.slots("cal.com/pick-test", "2026-09-28", 3, "UTC", http = fake) as CalBooking.Outcome.Ok).value
        assertEquals("https://cal.com/pick-test/15min", s.link)
        assertEquals("Quick chat", s.title)
        assertEquals(15, s.length)
        assertEquals(emptyList<CalBooking.SlotDay>(), s.days)
        assertEquals("15min", query(fake.asked[1].url)["eventTypeSlug"])
        assertEquals("pick-test", query(fake.asked[0].url)["username"])
        assertEquals("2026-06-12", fake.asked[0].headers["cal-api-version"])
    }

    @Test fun saysWhatWentWrongInWordsAndHandsTheRestToTheServer() {
        assertEquals(CalBooking.Outcome.Refused("That isn't a Cal.com or Calendly link"),
            CalBooking.slots("example.com/jane", "2026-09-28", 1, "UTC", http = Fake(emptyMap())))
        val gone = Fake(mapOf("https://api.cal.com/v2/slots" to (404 to """{"status":"error"}""")))
        assertEquals(CalBooking.Outcome.Refused("Cal.com doesn't know that link"),
            CalBooking.slots("cal.com/nobody-here/30min", "2026-09-28", 1, "UTC", http = gone))
        // Cal.com down or turned away: the server is asked instead.
        val down = Fake(mapOf("https://api.cal.com/v2/slots" to (503 to "{}")))
        assertEquals(CalBooking.Outcome.Unreachable, CalBooking.slots("cal.com/jane/30min", "2026-09-28", 1, "UTC", http = down))
        val offline = Fake(emptyMap(), fail = CalBooking.NotSent("no network"))
        assertEquals(CalBooking.Outcome.Unreachable, CalBooking.slots("cal.com/jane", "2026-09-28", 1, "UTC", http = offline))
        val none = Fake(mapOf("https://api.cal.com/v2/event-types" to (200 to """{"data":[{"slug":"x","hidden":true}]}""")))
        assertEquals(CalBooking.Outcome.Refused("No bookable event on that Cal.com link"),
            CalBooking.slots("cal.com/jane", "2026-09-28", 1, "UTC", http = none))
        // A stand-in's address is used as given.
        val fakeHost = Fake(mapOf("http://10.0.2.2:8796/v2/slots" to (200 to """{"data":{}}""")))
        assertTrue(CalBooking.slots("cal.com/jane/30min", "2026-09-28", 1, "UTC", "http://10.0.2.2:8796/v2", fakeHost)
            is CalBooking.Outcome.Ok)
    }

    private val start = java.time.Instant.parse("2026-09-28T13:30:00.000Z").toEpochMilli()

    @Test fun booksOnCalComWithTheAttendeeAndGuests() {
        val fake = Fake(mapOf("https://api.cal.com/v2/bookings" to (200 to JSONObject().put("status", "success").put("data", JSONObject()
            .put("uid", "bk_1").put("start", "2026-09-28T13:30:00.000Z").put("end", "2026-09-28T14:00:00.000Z")
            .put("title", "30 min between Jane and Sam Lee").put("meetingUrl", "https://app.cal.com/video/bk_1")).toString())))
        val r = CalBooking.book("cal.com/book-test/30min", start, "Sam Lee", "sam@example.com",
            listOf("ria@example.com", "SAM@example.com"), "Asia/Kolkata", http = fake)
        val b = (r as CalBooking.Outcome.Ok).value
        assertEquals("bk_1", b.uid)
        assertEquals("https://app.cal.com/video/bk_1", b.meetingUrl)
        assertEquals(listOf("sam@example.com", "ria@example.com", "SAM@example.com"), b.invited)
        val sent = JSONObject(fake.asked[0].body!!)
        assertEquals("2026-09-28T13:30:00.000Z", sent.getString("start"))
        assertEquals("30min", sent.getString("eventTypeSlug"))
        assertEquals("book-test", sent.getString("username"))
        val attendee = sent.getJSONObject("attendee")
        assertEquals("Sam Lee", attendee.getString("name"))
        assertEquals("sam@example.com", attendee.getString("email"))
        assertEquals("Asia/Kolkata", attendee.getString("timeZone"))
        assertEquals("[\"ria@example.com\"]", sent.getJSONArray("guests").toString())
        assertEquals(setOf("start", "eventTypeSlug", "username", "attendee", "guests"), sent.keys().asSequence().toSet())
        assertEquals("2026-02-25", fake.asked[0].headers["cal-api-version"])
        assertEquals("POST", fake.asked[0].method)
    }

    @Test fun saysATakenTimePlainlyAndKeepsCalendlyToItsOwnPage() {
        val taken = Fake(mapOf("https://api.cal.com/v2/bookings" to (400 to
            """{"status":"error","error":{"message":"User either already has booking at this time or is not available"}}""")))
        assertEquals(CalBooking.Outcome.Refused("That time was just taken. Pick another"),
            CalBooking.book("cal.com/book-test/30min", start, "Sam Lee", "sam@example.com", emptyList(), "Asia/Kolkata", http = taken))
        assertEquals(CalBooking.Outcome.Refused("Calendly books only on its own page. Send the link instead"),
            CalBooking.book("calendly.com/jane/intro", start, "Sam Lee", "sam@example.com", emptyList(), "UTC", http = taken))
        assertEquals(CalBooking.Outcome.Refused("Check the email addresses"),
            CalBooking.book("cal.com/book-test/30min", start, "Sam Lee", "not-an-email", emptyList(), "UTC", http = taken))
        val owner = Fake(mapOf("https://api.cal.com/v2/bookings" to (401 to """{"error":{"message":"Needs authentication"}}""")))
        assertEquals(CalBooking.Outcome.Refused("This page only takes bookings on Cal.com itself. Send the link instead"),
            CalBooking.book("cal.com/b/30min", start, "Sam", "sam@example.com", emptyList(), "UTC", http = owner))
        val other = Fake(mapOf("https://api.cal.com/v2/bookings" to (400 to """{"message":["Name too short","Bad thing"]}""")))
        assertEquals(CalBooking.Outcome.Refused("Cal.com said: Name too short, Bad thing"),
            CalBooking.book("cal.com/b/30min", start, "Sam", "sam@example.com", emptyList(), "UTC", http = other))
    }

    @Test fun handsABookingToTheServerOnlyWhenNothingWasSent() {
        val offline = Fake(emptyMap(), fail = CalBooking.NotSent("no network"))
        assertEquals(CalBooking.Outcome.Unreachable,
            CalBooking.book("cal.com/b/30min", start, "Sam", "sam@example.com", emptyList(), "UTC", http = offline))
        val busy = Fake(mapOf("https://api.cal.com/v2/bookings" to (429 to "{}")))
        assertEquals(CalBooking.Outcome.Unreachable,
            CalBooking.book("cal.com/b/30min", start, "Sam", "sam@example.com", emptyList(), "UTC", http = busy))
        // Lost on the way: it may have booked, so never a second try.
        val lost = Fake(emptyMap(), fail = java.net.SocketTimeoutException("read timed out"))
        assertEquals(CalBooking.Outcome.Refused("Cal.com didn't answer. Try again"),
            CalBooking.book("cal.com/b/30min", start, "Sam", "sam@example.com", emptyList(), "UTC", http = lost))
    }
}
