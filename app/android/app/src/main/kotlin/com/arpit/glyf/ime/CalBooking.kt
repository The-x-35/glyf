package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayOutputStream
import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Booking links, read and booked from the phone (twin of CalBooking.swift):
 * the server's scheduling routes (server/src/routes/scheduling.ts:
 * `parseBookingLink`, `bookingUrl`, the Cal.com v2 calls) ported as they
 * are, so Book a time talks to Cal.com's keyless API itself and no shared
 * rate limit stands in the way (docs/SERVER-INVENTORY.md, 2026-10-14). GET
 * /scheduling/slots and POST /scheduling/book stay as the fallback when
 * Cal.com can't be reached.
 *
 * Cal.com answers a public event's open times and takes a booking with no
 * key. Calendly gives times only to the host's own sign-in, so its link
 * comes back on the day chosen, and it books only on its own page.
 *
 * Synchronous: `http` blocks, so SchedulingClient runs this on a worker and
 * tests hand in a stand-in.
 */
object CalBooking {

    data class Link(
        /** "calcom" or "calendly". */
        val provider: String,
        /** The link without query or extra path: https://cal.com/jane/30min */
        val base: String,
        val username: String,
        val slug: String?,
        /** physics for physics.cal.com: Cal.com organisations have their own host. */
        val org: String?,
    )

    data class Response(val status: Int, val body: String)

    /** The request never left the phone (no connection, no name, no TLS):
     *  safe to ask the server instead, even for a booking. */
    class NotSent(why: String) : Exception(why)

    /** Sends a request and blocks for the answer: (method, url, headers,
     *  body). Throws [NotSent] when it never went out, anything else when it
     *  was lost on the way. */
    fun interface Http {
        fun send(method: String, url: String, headers: Map<String, String>, body: String?): Response
    }

    sealed class Outcome<out T> {
        data class Ok<T>(val value: T) : Outcome<T>()
        /** A final answer, in the server's own words. */
        data class Refused(val words: String) : Outcome<Nothing>()
        /** Cal.com couldn't be asked, and nothing was booked: the server may. */
        object Unreachable : Outcome<Nothing>()
    }

    data class SlotAt(val start: String, val url: String)
    data class SlotDay(val date: String, val slots: List<SlotAt>)
    data class Slots(val provider: String, val link: String, val bookingUrl: String,
                     val title: String?, val length: Int?, val days: List<SlotDay>)
    data class Booked(val uid: String?, val start: String?, val end: String?, val title: String?,
                      val meetingUrl: String?, val invited: List<String>)

    const val DEFAULT_API = "https://api.cal.com/v2"

    // MARK: links

    private val NAME = Regex("^[A-Za-z0-9_.-]+$")
    private val SCHEME = Regex("^https?://", RegexOption.IGNORE_CASE)

    /** A Cal.com or Calendly booking link, however it was typed
     *  ("cal.com/jane", "https://calendly.com/jane/30min?month=…"); null for
     *  anything else. */
    fun parse(raw: String): Link? {
        var s = raw.trim()
        if (s.isEmpty()) return null
        if (!SCHEME.containsMatchIn(s)) s = "https://$s"
        val uri = runCatching { URI(s) }.getOrNull() ?: return null
        var host = uri.host?.lowercase() ?: return null
        if (host.startsWith("www.")) host = host.removePrefix("www.")
        val parts = (uri.rawPath ?: "").split('/').filter { it.isNotEmpty() }.map { decode(it) ?: return null }
        if (parts.isEmpty() || parts.any { !NAME.matches(it) }) return null
        val username = parts[0]
        val slug = parts.getOrNull(1)
        val path = listOfNotNull(username, slug).joinToString("/")
        if (host == "calendly.com") return Link("calendly", "https://calendly.com/$path", username, slug, null)
        if (host == "cal.com" || host == "app.cal.com" || host.endsWith(".cal.com")) {
            val org = if (host.endsWith(".cal.com") && host != "app.cal.com") host.removeSuffix(".cal.com") else null
            val shown = if (host == "app.cal.com") "cal.com" else host
            return Link("calcom", "https://$shown/$path", username, slug, org)
        }
        return null
    }

    /** decodeURIComponent: %XX as UTF-8, nothing else touched; null when malformed. */
    private fun decode(s: String): String? {
        if ('%' !in s) return s
        val out = ByteArrayOutputStream()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%') {
                val hex = s.substring(i + 1, minOf(i + 3, s.length))
                if (hex.length != 2) return null
                out.write(hex.toIntOrNull(16) ?: return null)
                i += 3
            } else {
                out.write(c.toString().toByteArray(Charsets.UTF_8))
                i++
            }
        }
        val bytes = out.toByteArray()
        val decoder = Charsets.UTF_8.newDecoder()
        return runCatching { decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString() }.getOrNull()
    }

    /** The booking page on a day ("…?month=2026-09&date=2026-09-25"), and on
     *  one time when there is one: Cal.com goes straight to the form with `slot`. */
    fun bookingUrl(link: Link, date: String? = null, slotUtc: String? = null): String {
        val q = mutableListOf<Pair<String, String>>()
        if (date != null) {
            q += "month" to date.take(7)
            q += "date" to date
        }
        if (slotUtc != null && link.provider == "calcom") q += "slot" to slotUtc
        return if (q.isEmpty()) link.base else link.base + "?" + form(q)
    }

    /** application/x-www-form-urlencoded, as URLSearchParams writes it. */
    fun form(pairs: List<Pair<String, String>>): String {
        fun enc(s: String): String {
            val b = StringBuilder()
            for (byte in s.toByteArray(Charsets.UTF_8)) {
                val c = byte.toInt() and 0xff
                val ch = c.toChar()
                when {
                    ch in 'a'..'z' || ch in 'A'..'Z' || ch in '0'..'9' || ch == '*' || ch == '-' || ch == '.' || ch == '_' -> b.append(ch)
                    ch == ' ' -> b.append('+')
                    else -> b.append('%').append("%02X".format(c))
                }
            }
            return b.toString()
        }
        return pairs.joinToString("&") { "${enc(it.first)}=${enc(it.second)}" }
    }

    // MARK: times

    fun addDays(date: String, n: Int): String =
        runCatching { LocalDate.parse(date).plusDays(n.toLong()).toString() }.getOrDefault(date)

    private val ISO_MS: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

    /** An instant as JavaScript's `toISOString()` writes it: UTC, milliseconds. */
    fun isoUTC(ms: Long): String = ISO_MS.format(Instant.ofEpochMilli(ms))

    /** Cal.com's times ("2026-09-28T19:00:00.000+05:30"), as epoch ms. */
    fun parseTime(s: String): Long? = runCatching { OffsetDateTime.parse(s).toInstant().toEpochMilli() }.getOrNull()

    private fun validZone(tz: String) = runCatching { ZoneId.of(tz) }.isSuccess

    // MARK: Cal.com

    private fun json(s: String): Any? = runCatching { JSONTokener(s).nextValue() }.getOrNull()

    /** A GET on Cal.com's API: the body and 200, or the status it failed
     *  with (0 when nothing came back). */
    private fun calGet(api: String, path: String, version: String, http: Http): Pair<Any?, Int> {
        val r = try {
            http.send("GET", api + path, mapOf("cal-api-version" to version, "accept" to "application/json"), null)
        } catch (e: Exception) { return null to 0 }
        if (r.status !in 200..299) return null to r.status
        val body = json(r.body) ?: return null to r.status
        return body to 200
    }

    private data class EventType(val slug: String, val title: String?, val length: Int?, val bookingUrl: String?)

    private fun truthy(v: Any?): Boolean = when (v) {
        null, JSONObject.NULL -> false
        is Boolean -> v
        is Number -> v.toDouble() != 0.0 && !v.toDouble().isNaN()
        is String -> v.isNotEmpty()
        else -> true
    }

    /** The event to book on a link with no event in it ("cal.com/jane"): the
     *  shortest one that is shown. Unreachable when Cal.com didn't answer. */
    private fun firstEventType(link: Link, api: String, http: Http): Outcome<EventType?> {
        val q = mutableListOf("username" to link.username)
        link.org?.let { q += "organizationSlug" to it }
        val (body, status) = calGet(api, "/event-types?${form(q)}", "2026-06-12", http)
        if (status != 200) return Outcome.Unreachable
        val data = (body as? JSONObject)?.opt("data") as? JSONArray ?: JSONArray()
        val shown = (0 until data.length()).mapNotNull { i ->
            val t = data.opt(i) as? JSONObject ?: return@mapNotNull null
            val slug = t.opt("slug") as? String
            if (slug.isNullOrEmpty() || truthy(t.opt("hidden"))) return@mapNotNull null
            val length = (t.opt("lengthInMinutes") as? Number)?.toInt()
            EventType(slug, t.opt("title") as? String, length, t.opt("bookingUrl") as? String)
        }.sortedBy { it.length ?: 999 }
        return Outcome.Ok(shown.firstOrNull())
    }

    /** Open times on a link from `date` for `days` days, in `tz`, each with a
     *  link that opens straight on that slot (GET /scheduling/slots). */
    fun slots(raw: String, date: String, days: Int = 3, tz: String, api: String = DEFAULT_API, http: Http): Outcome<Slots> {
        val link = parse(raw) ?: return Outcome.Refused("That isn't a Cal.com or Calendly link")
        val n = days.coerceIn(1, 7)
        val zone = if (validZone(tz)) tz else "UTC"
        if (link.provider == "calendly") {
            // Times need the host's Calendly sign-in; the day itself does not.
            return Outcome.Ok(Slots("calendly", link.base, bookingUrl(link, date), null, null, emptyList()))
        }
        var full = link
        var title: String? = null
        var length: Int? = null
        if (link.slug == null) {
            val type = when (val found = firstEventType(link, api, http)) {
                is Outcome.Ok -> found.value ?: return Outcome.Refused("No bookable event on that Cal.com link")
                else -> return Outcome.Unreachable
            }
            title = type.title
            length = type.length
            // Cal.com's own page for it: a bare username can be someone in
            // an organisation, whose page lives on the organisation's host.
            val own = type.bookingUrl?.let { parse(it) }
            val base = if (own?.provider == "calcom" && own.slug != null) own.base
                else "${link.base.removeSuffix("/")}/${type.slug}"
            full = link.copy(slug = type.slug, base = base)
        }
        // A day earlier than asked, so a zone ahead of UTC keeps its morning.
        val q = mutableListOf("eventTypeSlug" to (full.slug ?: ""), "username" to link.username,
            "start" to addDays(date, -1), "end" to addDays(date, n), "timeZone" to zone)
        link.org?.let { q += "organizationSlug" to it }
        val (body, status) = calGet(api, "/slots?${form(q)}", "2024-09-04", http)
        if (status == 404) return Outcome.Refused("Cal.com doesn't know that link")
        if (status != 200) return Outcome.Unreachable
        val last = addDays(date, n)
        val data = (body as? JSONObject)?.opt("data") as? JSONObject ?: JSONObject()
        val out = data.keys().asSequence().filter { it >= date && it < last }.sorted().toList().map { d ->
            val list = data.opt(d) as? JSONArray ?: JSONArray()
            SlotDay(d, (0 until minOf(list.length(), 24)).map { i ->
                val start = (list.opt(i) as? JSONObject)?.opt("start") as? String ?: return Outcome.Unreachable
                val at = parseTime(start) ?: return Outcome.Unreachable
                SlotAt(start, bookingUrl(full, d, isoUTC(at)))
            })
        }
        return Outcome.Ok(Slots("calcom", full.base, bookingUrl(full, date), title, length, out))
    }

    // MARK: booking

    /** zod's email check, which the server runs on every address. */
    private val EMAIL = Regex("^(?!\\.)(?!.*\\.\\.)([A-Za-z0-9_'+\\-.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\\-]*\\.)+[A-Za-z]{2,}$")

    fun isEmail(s: String) = EMAIL.matches(s)

    /** What Cal.com said, when it said something a person can act on. */
    fun calMessage(body: Any?): String {
        val b = body as? JSONObject ?: return ""
        val e = b.opt("error")
        val m: Any? = if (e is JSONObject || e is JSONArray || e == JSONObject.NULL) (e as? JSONObject)?.opt("message")
            else e ?: b.opt("message")
        return when (m) {
            is String -> m
            is JSONArray -> (0 until m.length()).joinToString(", ") { m.opt(it).toString() }
            else -> ""
        }
    }

    private val TAKEN = Regex("available|booked|already|slot", RegexOption.IGNORE_CASE)
    private val OWN_PAGE = Regex("authenticat|owner|admin", RegexOption.IGNORE_CASE)

    /** Books a time on a Cal.com page with the attendee's name and email and
     *  any guests', the way Cal.com's own page does, and Cal.com emails
     *  everyone the invite (POST /scheduling/book). */
    fun book(raw: String, startMs: Long, name: String, email: String, guests: List<String>, tz: String,
             notes: String? = null, api: String = DEFAULT_API, http: Http): Outcome<Booked> {
        val who = name.trim()
        val mail = email.trim()
        val others = guests.map { it.trim() }
        val note = notes?.trim()
        if (!isEmail(mail) || mail.length > 200 || others.size > 10 || others.any { !isEmail(it) || it.length > 200 }) {
            return Outcome.Refused("Check the email addresses")
        }
        if (who.isEmpty() || who.length > 120 || raw.length < 3 || raw.length > 300 || tz.length > 64 ||
            (note?.length ?: 0) > 500) return Outcome.Refused("Bad request")
        val link = parse(raw) ?: return Outcome.Refused("That isn't a Cal.com or Calendly link")
        if (link.provider != "calcom") return Outcome.Refused("Calendly books only on its own page. Send the link instead")
        val zone = if (validZone(tz)) tz else "UTC"
        var slug = link.slug
        if (slug == null) {
            slug = when (val found = firstEventType(link, api, http)) {
                is Outcome.Ok -> (found.value ?: return Outcome.Refused("No bookable event on that Cal.com link")).slug
                else -> return Outcome.Unreachable
            }
        }
        val start = isoUTC(startMs)
        val body = JSONObject()
            .put("start", start)
            .put("eventTypeSlug", slug)
            .put("username", link.username)
            .put("attendee", JSONObject().put("name", who).put("email", mail).put("timeZone", zone))
        link.org?.let { body.put("organizationSlug", it) }
        if (others.isNotEmpty()) {
            body.put("guests", JSONArray(others.map { it.lowercase() }.distinct().filter { it != mail.lowercase() }))
        }
        if (!note.isNullOrEmpty()) body.put("bookingFieldsResponses", JSONObject().put("notes", note))
        val r = try {
            http.send("POST", "$api/bookings", mapOf("cal-api-version" to "2026-02-25",
                "content-type" to "application/json", "accept" to "application/json"), body.toString())
        } catch (e: NotSent) {
            return Outcome.Unreachable
        } catch (e: Exception) {
            return Outcome.Refused("Cal.com didn't answer. Try again")
        }
        val out = json(r.body) as? JSONObject
        if (r.status !in 200..299) {
            // Turned away for asking too often: nothing was booked, so the
            // server may ask from where it is.
            if (r.status == 429) return Outcome.Unreachable
            val said = calMessage(out)
            if (TAKEN.containsMatchIn(said)) return Outcome.Refused("That time was just taken. Pick another")
            if (OWN_PAGE.containsMatchIn(said)) return Outcome.Refused("This page only takes bookings on Cal.com itself. Send the link instead")
            return Outcome.Refused(if (said.isNotEmpty()) "Cal.com said: $said" else "Cal.com couldn't book it. Try again")
        }
        val d = out?.opt("data") as? JSONObject ?: JSONObject()
        fun str(k: String) = d.opt(k) as? String
        return Outcome.Ok(Booked(str("uid"), str("start") ?: start, str("end"), str("title"),
            str("meetingUrl") ?: str("location"), listOf(mail) + others))
    }
}
