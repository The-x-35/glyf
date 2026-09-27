package com.demo.glyf.ime

import android.accounts.Account
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.demo.glyf.BuildConfig
import com.demo.glyf.store.GoogleAccess
import com.google.android.gms.auth.GoogleAuthUtil
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * The keyboard's own calls to Google, on the grant in GoogleAccess: a fresh
 * access token from Google Play services, a Meet link, an event in the
 * person's Google Calendar. Nothing here goes through Glyf's server.
 * Callbacks arrive on the main thread. The twin of GoogleClient.swift.
 */
object GoogleClient {

    enum class Failure { NOT_CONNECTED, RECONNECT, UNREACHABLE, REFUSED }

    /** What to tell the person when Google didn't do it. */
    fun say(f: Failure): String = when (f) {
        Failure.RECONNECT -> "Sign in with Google again in Glyf"
        Failure.UNREACHABLE -> "Couldn't reach Google"
        else -> "Google said no"
    }

    /** The event on Google Calendar's web page, and its Meet call. */
    data class Added(val link: String?, val meet: String?, val id: String? = null)

    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    private fun base(g: GoogleAccess.Grant): String? =
        g.fakeBase?.takeIf { BuildConfig.DEBUG && it.isNotEmpty() }

    private fun meetUrl(g: GoogleAccess.Grant) =
        (base(g)?.let { "$it/v2/spaces" } ?: "https://meet.googleapis.com/v2/spaces")

    private fun eventsUrl(g: GoogleAccess.Grant) =
        (base(g)?.let { "$it/calendar/v3/calendars/primary/events" }
            ?: "https://www.googleapis.com/calendar/v3/calendars/primary/events") + "?" + GoogleEvent.QUERY

    private fun listUrl(g: GoogleAccess.Grant, from: Long, to: Long): String {
        val iso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
        iso.timeZone = java.util.TimeZone.getTimeZone("UTC")
        val head = base(g)?.let { "$it/calendar/v3/calendars/primary/events" }
            ?: "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        return head + "?timeMin=" + iso.format(java.util.Date(from)) +
            "&timeMax=" + iso.format(java.util.Date(to)) +
            "&singleEvents=true&orderBy=startTime&maxResults=250"
    }

    /** A token from Google Play services: no screen when the person already
     *  agreed; RECONNECT when Google wants to ask them again. */
    fun accessToken(ctx: Context, done: (String?, Failure?) -> Unit) {
        val g = GoogleAccess.load(ctx) ?: return run { main.post { done(null, Failure.NOT_CONNECTED) } }
        if (base(g) != null) return run { main.post { done("fake-access", null) } }
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(g.scopes.map { Scope(it) })
            .apply { g.email?.let { setAccount(Account(it, "com.google")) } }
            .build()
        Identity.getAuthorizationClient(ctx).authorize(request)
            .addOnSuccessListener { r ->
                val token = r.accessToken
                if (r.hasResolution() || token == null) done(null, Failure.RECONNECT) else done(token, null)
            }
            .addOnFailureListener { done(null, Failure.UNREACHABLE) }
    }

    /** A Meet link of the person's own ("https://meet.google.com/abc-defg-hij"). */
    fun newMeet(ctx: Context, done: (String?, Failure?) -> Unit) {
        val g = GoogleAccess.load(ctx)
        if (g == null || GoogleAccess.MEET !in g.scopes) return run { main.post { done(null, Failure.NOT_CONNECTED) } }
        post(ctx, meetUrl(g), JSONObject()) { json, f ->
            val uri = json?.optString("meetingUri")?.takeIf { it.startsWith("https://") }
            done(uri, if (uri == null) f ?: Failure.REFUSED else null)
        }
    }

    /** The event in the person's own Google Calendar. Google emails each
     *  guest the invite and makes the Meet call when `video` is on. */
    fun addEvent(ctx: Context, title: String, start: Long, end: Long, allDay: Boolean,
                 guests: List<String>, video: Boolean, done: (Added?, Failure?) -> Unit) {
        val g = GoogleAccess.load(ctx)
        if (g == null || GoogleAccess.CALENDAR !in g.scopes) return run { main.post { done(null, Failure.NOT_CONNECTED) } }
        post(ctx, eventsUrl(g), GoogleEvent.body(title, start, end, allDay, guests, video)) { json, f ->
            if (json == null) done(null, f ?: Failure.REFUSED)
            else done(Added(json.optString("htmlLink").takeIf { it.isNotEmpty() },
                json.optString("hangoutLink").takeIf { it.startsWith("https://") },
                json.optString("id").takeIf { it.isNotEmpty() }), null)
        }
    }

    /** The person's Google Calendar between two moments, each recurrence
     *  its own event: what Google has NOW, changes made anywhere included. */
    fun listEvents(ctx: Context, from: Long, to: Long,
                   done: (List<CalendarText.Event>?, Failure?) -> Unit) {
        val g = GoogleAccess.load(ctx)
        if (g == null || GoogleAccess.CALENDAR !in g.scopes) {
            return run { main.post { done(null, Failure.NOT_CONNECTED) } }
        }
        get(ctx, listUrl(g, from, to)) { json, f ->
            if (json == null) done(null, f ?: Failure.REFUSED)
            else done(GoogleEvent.eventsFromList(json), null)
        }
    }

    /** GETs with a token, once more with a fresh one on a stale 401. */
    private fun get(ctx: Context, url: String, retry: Boolean = true,
                    done: (JSONObject?, Failure?) -> Unit) {
        accessToken(ctx) { token, failure ->
            if (token == null) return@accessToken done(null, failure)
            pool.execute {
                var code = 0
                var json: JSONObject? = null
                runCatching {
                    val c = (URL(url).openConnection() as HttpURLConnection).apply {
                        requestMethod = "GET"
                        connectTimeout = 6000
                        readTimeout = 12000
                        setRequestProperty("Authorization", "Bearer $token")
                    }
                    code = c.responseCode
                    val stream = if (code in 200..299) c.inputStream else c.errorStream
                    json = stream?.bufferedReader()?.readText()?.let { runCatching { JSONObject(it) }.getOrNull() }
                }
                main.post {
                    when {
                        code in 200..299 && json != null -> done(json, null)
                        code == 401 && retry && token != "fake-access" -> get(ctx, url, false, done)
                        else -> done(null, if (code == 0) Failure.UNREACHABLE
                                          else if (code == 401) Failure.RECONNECT else Failure.REFUSED)
                    }
                }
            }
        }
    }

    /** POSTs with a token, and once more with a fresh one if Google says
     *  the token went stale on the way. */
    private fun post(ctx: Context, url: String, body: JSONObject, retry: Boolean = true,
                     done: (JSONObject?, Failure?) -> Unit) {
        accessToken(ctx) { token, failure ->
            if (token == null) return@accessToken done(null, failure)
            pool.execute {
                var code = 0
                var json: JSONObject? = null
                runCatching {
                    val c = (URL(url).openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        doOutput = true
                        connectTimeout = 6000
                        readTimeout = 12000
                        setRequestProperty("Authorization", "Bearer $token")
                        setRequestProperty("Content-Type", "application/json")
                    }
                    c.outputStream.use { it.write(body.toString().toByteArray()) }
                    code = c.responseCode
                    val stream = if (code in 200..299) c.inputStream else c.errorStream
                    json = stream?.bufferedReader()?.readText()?.let { runCatching { JSONObject(it) }.getOrNull() }
                }
                if (code == 401 && retry && token != "fake-access") {
                    // Play services hands the same token out until told it's stale.
                    runCatching { GoogleAuthUtil.clearToken(ctx, token) }
                    main.post { post(ctx, url, body, false, done) }
                    return@execute
                }
                main.post {
                    when {
                        code in 200..299 && json != null -> done(json, null)
                        code == 0 -> done(null, Failure.UNREACHABLE)
                        code == 401 -> done(null, Failure.RECONNECT)
                        else -> done(null, Failure.REFUSED)
                    }
                }
            }
        }
    }
}

/** A call link: the person's own Google Meet, and nothing else. Without
 *  Google connected, or when Google says no, there is no link and `note`
 *  says what to do. The twin of CallLink in GoogleClient.swift. */
object CallLink {
    const val CONNECT_FIRST = "Connect Google Meet in Glyf › Connected tools"

    fun make(ctx: Context, done: (url: String?, note: String?) -> Unit) {
        if (!GoogleAccess.hasMeet(ctx)) {
            Handler(Looper.getMainLooper()).post { done(null, CONNECT_FIRST) }
            return
        }
        GoogleClient.newMeet(ctx) { url, failure ->
            if (url != null) done(url, null) else done(null, GoogleClient.say(failure ?: GoogleClient.Failure.REFUSED))
        }
    }
}

/** Events the keyboard added to Google Calendar, kept so its calendar can show
 *  them before the phone's own calendar has them (CalendarText.withAdded).
 *  The twin of GoogleAdded in GoogleClient.swift. */
object GoogleAdded {
    private const val FILE = "google-added.json"

    fun remember(ctx: Context, event: CalendarText.Event) = save(ctx, (load(ctx) + event).takeLast(30))

    /** `events` with every added event the phone doesn't show yet. */
    fun merged(ctx: Context, events: List<CalendarText.Event>,
               now: Long = System.currentTimeMillis()): List<CalendarText.Event> {
        val added = load(ctx)
        if (added.isEmpty()) return events
        val (shown, pending) = CalendarText.withAdded(added, events, now)
        if (pending.size != added.size) save(ctx, pending)
        return shown
    }

    private fun load(ctx: Context): List<CalendarText.Event> = runCatching {
        val rows = org.json.JSONArray(java.io.File(ctx.filesDir, FILE).readText())
        (0 until rows.length()).map { i ->
            val o = rows.getJSONObject(i)
            CalendarText.Event(o.getString("title"), o.getLong("start"), o.getLong("end"), o.optBoolean("allDay"),
                location = o.optString("location").takeIf { it.isNotEmpty() },
                googleId = o.optString("id").takeIf { it.isNotEmpty() })
        }
    }.getOrDefault(emptyList())

    private fun save(ctx: Context, events: List<CalendarText.Event>) {
        val rows = org.json.JSONArray()
        for (e in events) rows.put(org.json.JSONObject().apply {
            put("title", e.title); put("start", e.start); put("end", e.end); put("allDay", e.allDay)
            e.location?.let { put("location", it) }
            e.googleId?.let { put("id", it) }
        })
        runCatching { java.io.File(ctx.filesDir, FILE).writeText(rows.toString()) }
    }
}
