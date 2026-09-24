package com.demo.glyf.ime

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
 * Call links and booking links, the twin of the Swift BackendClient's
 * scheduling calls: POST /meetings/new, GET /scheduling/slots, POST
 * /scheduling/book. Answers come back on the main thread; an error is the
 * server's own words when it has them.
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

    /** A call link: a Daily room when the server has a key, else Jitsi. Null
     *  when the server can't be reached. */
    fun newMeeting(backendURL: String, done: (String?) -> Unit) {
        pool.execute {
            val link = runCatching {
                val c = open("$backendURL/meetings/new", "POST")
                c.outputStream.use { it.write("{}".toByteArray()) }
                c.json()?.optString("url")?.takeIf { it.startsWith("http") }
            }.getOrNull()
            main.post { done(link) }
        }
    }

    /** Open times on a Cal.com link (Calendly gives only its link) from a day. */
    fun slots(backendURL: String, link: String, date: String, done: (Slots?, String?) -> Unit) {
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
     *  emails everyone the invite. */
    fun book(backendURL: String, link: String, start: Long, name: String, email: String,
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

    /** A call link made on the phone when the server can't be reached. */
    fun localCallLink(): String {
        val letters = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return "https://meet.jit.si/Glyf-" + (1..10).map { letters.random() }.joinToString("")
    }
}
