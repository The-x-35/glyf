package com.arpit.glyf.ime

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Booking links, the twin of the Swift BackendClient's scheduling calls:
 * straight with Cal.com (CalBooking.kt), with GET /scheduling/slots and POST
 * /scheduling/book as the fallback. Answers come back on the main thread; an
 * error is the server's own words when it has them.
 */
object SchedulingClient {

    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    data class Slot(val start: Long, val url: String)
    data class Day(val date: String, val slots: List<Slot>)
    data class Slots(val provider: String, val bookingUrl: String, val days: List<Day>)
    data class Booked(val start: Long?, val meetingUrl: String?, val invited: List<String>)

    private fun open(url: String, method: String = "GET"): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 5000
            readTimeout = 15000
            BackendClient.bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
            if (method == "POST") {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }

    /** The body, whatever the status, as JSON (or null). */
    private fun HttpURLConnection.json(): JSONObject? = runCatching {
        val stream = if (responseCode in 200..299) inputStream else errorStream
        JSONObject(stream.bufferedReader().readText())
    }.getOrNull()

    private fun iso(ms: Long): String =
        java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }.format(ms)

    private fun parseTime(s: String): Long? = runCatching { java.time.OffsetDateTime.parse(s).toInstant().toEpochMilli() }.getOrNull()

    /** Cal.com's API, or the stand-in a test names in settings
     *  (`calcomBase`, qa/fake-scheduling.mjs). */
    private fun api(calcomBase: String?): String =
        calcomBase?.trim()?.removeSuffix("/")?.takeIf { it.isNotEmpty() } ?: CalBooking.DEFAULT_API

    /** Cal.com over HTTP, blocking. A request that never went out (no
     *  connection, no name, no TLS) throws NotSent, so a booking can be
     *  handed to the server without booking twice. */
    private val calHttp = CalBooking.Http { method, url, headers, body ->
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 5000
            readTimeout = if (method == "POST") 12000 else 8000
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
            if (body != null) doOutput = true
        }
        try {
            try { c.connect() } catch (e: java.io.IOException) { throw CalBooking.NotSent(e.toString()) }
            if (body != null) c.outputStream.use { it.write(body.toByteArray()) }
            val status = c.responseCode
            val stream = if (status in 200..299) c.inputStream else c.errorStream
            CalBooking.Response(status, stream?.bufferedReader()?.readText().orEmpty())
        } finally { c.disconnect() }
    }

    /** Open times on a Cal.com link (Calendly gives only its link) from a
     *  day. Straight from Cal.com's keyless API (CalBooking.kt); the server
     *  only when Cal.com can't be reached (SERVER-INVENTORY.md, 2026-10-14). */
    fun slots(backendURL: String, link: String, date: String, calcomBase: String? = null,
              done: (Slots?, String?) -> Unit) {
        pool.execute {
            when (val r = CalBooking.slots(link, date, 1, TimeZone.getDefault().id, api(calcomBase), calHttp)) {
                is CalBooking.Outcome.Ok -> {
                    val s = r.value
                    val days = s.days.map { d ->
                        Day(d.date, d.slots.mapNotNull { at -> parseTime(at.start)?.let { Slot(it, at.url) } })
                    }
                    main.post { done(Slots(s.provider, s.bookingUrl, days), null) }
                }
                is CalBooking.Outcome.Refused -> main.post { done(null, r.words) }
                CalBooking.Outcome.Unreachable -> slotsFromServer(backendURL, link, date, done)
            }
        }
    }

    /** GET /scheduling/slots: the fallback when Cal.com can't be reached. */
    private fun slotsFromServer(backendURL: String, link: String, date: String, done: (Slots?, String?) -> Unit) {
        pool.execute {
            var result: Slots? = null
            var error: String? = null
            runCatching {
                val q = "link=${URLEncoder.encode(link, "UTF-8")}&date=$date&days=1" +
                    "&tz=${URLEncoder.encode(TimeZone.getDefault().id, "UTF-8")}"
                val c = open("$backendURL/scheduling/slots?$q")
                val json = c.json()
                if (c.responseCode == 200 && json != null) {
                    val days = json.optJSONArray("days") ?: JSONArray()
                    result = Slots(json.optString("provider"), json.optString("bookingUrl"),
                        (0 until days.length()).map { i ->
                            val d = days.getJSONObject(i)
                            val s = d.optJSONArray("slots") ?: JSONArray()
                            Day(d.optString("date"), (0 until s.length()).mapNotNull { j ->
                                val o = s.getJSONObject(j)
                                parseTime(o.optString("start"))?.let { Slot(it, o.optString("url")) }
                            })
                        })
                } else error = json?.optString("error")?.takeIf { it.isNotEmpty() }
            }
            main.post { done(result, error) }
        }
    }

    /** Books a time on a Cal.com page with the attendee and guests; Cal.com
     *  emails everyone the invite. Straight with Cal.com (CalBooking.kt); the
     *  server only when the request never reached Cal.com, so nothing is
     *  booked twice. */
    fun book(backendURL: String, link: String, start: Long, name: String, email: String,
             guests: List<String>, calcomBase: String? = null, done: (Booked?, String?) -> Unit) {
        pool.execute {
            when (val r = CalBooking.book(link, start, name, email, guests, TimeZone.getDefault().id,
                api = api(calcomBase), http = calHttp)) {
                is CalBooking.Outcome.Ok -> {
                    val b = r.value
                    main.post {
                        done(Booked(b.start?.let { parseTime(it) }, b.meetingUrl?.takeIf { it.startsWith("http") },
                            b.invited), null)
                    }
                }
                is CalBooking.Outcome.Refused -> main.post { done(null, r.words) }
                CalBooking.Outcome.Unreachable -> bookOnServer(backendURL, link, start, name, email, guests, done)
            }
        }
    }

    /** POST /scheduling/book: the fallback when Cal.com can't be reached. */
    private fun bookOnServer(backendURL: String, link: String, start: Long, name: String, email: String,
                             guests: List<String>, done: (Booked?, String?) -> Unit) {
        pool.execute {
            var booked: Booked? = null
            var error: String? = null
            runCatching {
                val c = open("$backendURL/scheduling/book", "POST")
                val body = JSONObject().put("link", link).put("start", iso(start)).put("name", name)
                    .put("email", email).put("guests", JSONArray(guests)).put("tz", TimeZone.getDefault().id)
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                val json = c.json()
                if (c.responseCode == 200 && json?.optBoolean("ok") == true) {
                    val invited = json.optJSONArray("invited") ?: JSONArray()
                    booked = Booked(parseTime(json.optString("start")),
                        json.optString("meetingUrl").takeIf { it.startsWith("http") },
                        (0 until invited.length()).map { invited.getString(it) })
                } else error = json?.optString("error")?.takeIf { it.isNotEmpty() }
            }.onFailure { error = null }
            main.post { done(booked, error) }
        }
    }
}
