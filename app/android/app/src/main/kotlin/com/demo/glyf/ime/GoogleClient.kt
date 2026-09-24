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
        Failure.RECONNECT -> "Reconnect Google in the Glyf app"
        Failure.UNREACHABLE -> "Couldn't reach Google"
        else -> "Google said no"
    }

    /** The event on Google Calendar's web page, and its Meet call. */
    data class Added(val link: String?, val meet: String?)

    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    private fun base(g: GoogleAccess.Grant): String? =
        g.fakeBase?.takeIf { BuildConfig.DEBUG && it.isNotEmpty() }

    private fun meetUrl(g: GoogleAccess.Grant) =
        (base(g)?.let { "$it/v2/spaces" } ?: "https://meet.googleapis.com/v2/spaces")

    private fun eventsUrl(g: GoogleAccess.Grant) =
        (base(g)?.let { "$it/calendar/v3/calendars/primary/events" }
            ?: "https://www.googleapis.com/calendar/v3/calendars/primary/events") + "?" + GoogleEvent.QUERY

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
                json.optString("hangoutLink").takeIf { it.startsWith("https://") }), null)
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

/** A link to call on: the person's own Google Meet when they connected
 *  Google, else the server's (a Daily room with its key, a Jitsi one
 *  without), else one made right here. `note` says why Meet wasn't used,
 *  when it was meant to be. The twin of CallLink in GoogleClient.swift. */
object CallLink {
    fun make(ctx: Context, backendURL: String, done: (url: String, note: String?) -> Unit) {
        fun fallback(note: String?) = SchedulingClient.newMeeting(backendURL) { link ->
            done(link ?: SchedulingClient.localCallLink(), note)
        }
        if (!GoogleAccess.hasMeet(ctx)) return fallback(null)
        GoogleClient.newMeet(ctx) { url, failure ->
            if (url != null) done(url, null) else fallback(GoogleClient.say(failure ?: GoogleClient.Failure.REFUSED))
        }
    }
}
