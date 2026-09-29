package com.demo.glyf.ime

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Temp mail in the keyboard (Arpit, 2026-09-30: "option to enter temporary
 * mail and we will monitor its mails for next some times and show the mails
 * gotten on it, so user can get temporary mails directly inside their
 * keyboards"). Glyf's server holds the provider's key and hands out an
 * address with a token that reads it; the keyboard only talks to Glyf.
 * Addresses travel in request bodies, never URLs, and nothing here is ever
 * logged: not an address, a sender, a subject or a code. iOS twin: TempMail.
 */

/** One mail, as the server reads it (newest first). Kept in memory only. */
data class TempMail(
    val id: String,
    val from: String,
    val fromAddress: String,
    val subject: String,
    val text: String,
    val receivedAt: Long,
    val code: String?,
    val link: String?,
)

/** The address being watched, which survives the keyboard going away so
 *  watching carries on in the next app. Never the mails themselves. */
data class TempBox(
    val address: String,
    val token: String,
    val expiresAt: Long,
    /** The watch window: checks from [watchStart] until [watchUntil]. */
    val watchStart: Long,
    val watchUntil: Long,
    /** Two minutes after a mail with a code came (0: none yet): its job is done. */
    val codeStop: Long,
    /** Mails already told about, so each one's chip shows once. */
    val seen: Set<String>,
    /** The server said no more checks today (429): none until then, local
     *  midnight (0: not turned away). A new address keeps it. */
    val blockedUntil: Long = 0L,
)

object TempMailStore {
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("glyf_tempmail", Context.MODE_PRIVATE)

    fun load(ctx: Context): TempBox? {
        val p = prefs(ctx)
        val address = p.getString("address", null) ?: return null
        val token = p.getString("token", null) ?: return null
        return TempBox(address, token, p.getLong("expiresAt", 0), p.getLong("watchStart", 0),
            p.getLong("watchUntil", 0), p.getLong("codeStop", 0),
            p.getStringSet("seen", emptySet()).orEmpty().toSet(), p.getLong("blockedUntil", 0))
    }

    fun save(ctx: Context, box: TempBox) {
        prefs(ctx).edit()
            .putString("address", box.address).putString("token", box.token)
            .putLong("expiresAt", box.expiresAt).putLong("watchStart", box.watchStart)
            .putLong("watchUntil", box.watchUntil).putLong("codeStop", box.codeStop)
            .putStringSet("seen", box.seen)
            .putLong("blockedUntil", box.blockedUntil)
            .apply()
    }

    fun clear(ctx: Context) {
        prefs(ctx).edit().clear().apply()
    }
}

object TempMailClient {

    private val pool = Executors.newSingleThreadExecutor()

    /** What came back: the JSON on success, else the HTTP status and the
     *  server's own words for the person. */
    class Reply(val status: Int, val json: JSONObject?, val error: String?)

    private fun post(backendURL: String, path: String, body: JSONObject): Reply = try {
        val c = (URL("$backendURL$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 5000
            readTimeout = 12000
            setRequestProperty("Content-Type", "application/json")
            BackendClient.bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
        }
        c.outputStream.use { it.write(body.toString().toByteArray()) }
        val status = c.responseCode
        val stream = if (status in 200..299) c.inputStream else c.errorStream
        val json = stream?.bufferedReader()?.use { it.readText() }?.let { runCatching { JSONObject(it) }.getOrNull() }
        if (status in 200..299 && json?.optBoolean("ok") == true) Reply(status, json, null)
        else Reply(status, null, json?.optString("error")?.takeIf { it.isNotBlank() }
            ?: "Temp mail didn't answer. Try again in a moment")
    } catch (_: Exception) {
        Reply(0, null, "Couldn't reach Glyf. Check the connection")
    }

    /** A new address. [done] runs on a worker thread. */
    fun create(backendURL: String, deviceId: String, done: (Reply) -> Unit) = pool.execute {
        done(post(backendURL, "/tempmail", JSONObject().put("deviceId", deviceId)))
    }

    fun messages(backendURL: String, deviceId: String, box: TempBox, done: (Reply) -> Unit) = pool.execute {
        done(post(backendURL, "/tempmail/messages", JSONObject().put("deviceId", deviceId)
            .put("address", box.address).put("token", box.token)))
    }

    fun delete(backendURL: String, deviceId: String, box: TempBox, done: (Reply) -> Unit = {}) = pool.execute {
        done(post(backendURL, "/tempmail/delete", JSONObject().put("deviceId", deviceId)
            .put("address", box.address).put("token", box.token)))
    }

    /** The mails in a /tempmail/messages reply, newest first. */
    fun mails(json: JSONObject): List<TempMail> {
        val arr = json.optJSONArray("messages") ?: return emptyList()
        return (0 until arr.length()).mapNotNull { i ->
            val m = arr.optJSONObject(i) ?: return@mapNotNull null
            val id = m.optString("id").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            TempMail(id, m.optString("from"), m.optString("fromAddress"), m.optString("subject"),
                m.optString("text"), m.optLong("receivedAt"),
                m.optString("code").takeIf { it.isNotBlank() }, m.optString("link").takeIf { it.isNotBlank() })
        }.sortedByDescending { it.receivedAt }
    }

    /** "now", "2m", "3h", "2d": how long ago, as the inbox shows it. */
    fun ago(at: Long, now: Long = System.currentTimeMillis()): String {
        val s = ((now - at) / 1000).coerceAtLeast(0)
        return when {
            s < 60 -> "now"
            s < 3600 -> "${s / 60}m"
            s < 86400 -> "${s / 3600}h"
            else -> "${s / 86400}d"
        }
    }

    /** A watch window: 15 minutes from Create, Insert or opening the panel. */
    const val WATCH_MS = 15 * 60 * 1000L
    /** Checks every 8 s for a window's first 3 minutes, then every 20 s:
     *  Temp-Mail.io requests are counted (and a code mostly comes at once). */
    const val FAST_MS = 8_000L
    const val SLOW_MS = 20_000L
    const val FAST_FOR_MS = 3 * 60 * 1000L
    /** A code has come: two more minutes of watching, then its job is done. */
    const val AFTER_CODE_MS = 2 * 60 * 1000L

    /** Local midnight after [now]: when a day's checks come back. */
    fun nextMidnight(now: Long = System.currentTimeMillis()): Long =
        java.util.Calendar.getInstance().apply {
            timeInMillis = now
            add(java.util.Calendar.DAY_OF_YEAR, 1)
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
}
