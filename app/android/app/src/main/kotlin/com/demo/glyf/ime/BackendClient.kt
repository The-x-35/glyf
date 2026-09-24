package com.demo.glyf.ime

import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Keyboard → backend, SSE. Mirror of the Swift BackendClient: the IME
 *  never holds provider keys; prompts and models live server-side. */
object BackendClient {

    private val pool = Executors.newCachedThreadPool()

    /** The signed-in session, kept fresh by the IME: the server turns away
     *  anyone without one. */
    @Volatile
    @JvmStatic
    var bearer: String? = null

    private fun HttpURLConnection.signIn() {
        bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
    }

    data class ToolRow(val title: String, val snippet: String, val url: String)

    /** POST /tools/run — keyless search-suite tools; rows for the panel. */
    fun tool(
        backendURL: String,
        id: String,
        args: Map<String, String>,
        deviceId: String,
        onRows: (List<ToolRow>) -> Unit,
        onError: (String) -> Unit,
    ) {
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL("$backendURL/tools/run").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 12000
                    setRequestProperty("Content-Type", "application/json")
                    signIn()
                }
                val body = JSONObject(mapOf(
                    "id" to id, "args" to JSONObject(args as Map<*, *>),
                    "deviceId" to deviceId))
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                val text = conn.inputStream.bufferedReader().readText()
                val result = JSONObject(text).optString("result", "[]")
                val arr = org.json.JSONArray(result)
                val rows = mutableListOf<ToolRow>()
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    rows.add(ToolRow(
                        o.optString("title"),
                        o.optString("snippet", o.optString("url")),
                        o.optString("url")))
                }
                onRows(rows)
            } catch (e: Exception) {
                android.util.Log.e("GlyfKB", "tool failed: $e")
                onError("Couldn't search right now")
            } finally {
                conn?.disconnect()
            }
        }
    }

    /** Mirrors server/src/lib/searchcards.ts and the Swift SearchCard.
     *  One class rather than a sealed hierarchy: `kind` decides which fields
     *  the row reads, and an unknown field never breaks an old client. */
    data class SearchCard(
        val kind: String,
        val id: String,
        val title: String,
        val url: String,
        val emoji: String? = null,
        val extra: String? = null,
        /** An answer is sent as the answer; when set, a tap inserts exactly this. */
        val say: String? = null,
        // answer
        val value: String? = null,
        val sub: String? = null,
        val art: String? = null,
        val source: String? = null,
        // link
        val snippet: String? = null,
        val domain: String? = null,
        val thumb: String? = null,
        // video
        val channel: String? = null,
        val duration: String? = null,
        val live: Boolean = false,
        // place
        val address: String? = null,
        val rating: Double? = null,
        val ratingCount: Int? = null,
        val openNow: Boolean? = null,
        val distance: String? = null,
        /** Present on place cards from every maps provider. */
        val lat: Double? = null,
        val lon: Double? = null,
    ) {
        /** What a tap puts in the host field. Kept identical to the Swift
         *  version and the server's composeInsert. */
        fun insertText(style: String): String {
            say?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            if (style == "linkOnly" || title.isBlank()) return url
            val lines = mutableListOf(url, "${if (emoji != null) "$emoji " else ""}$title")
            extra?.trim()?.takeIf { it.isNotEmpty() }?.let { lines.add(it) }
            return lines.joinToString("\n")
        }
    }

    /** POST /search — the Search / YouTube / Maps tabs. Callbacks land on the
     *  pool thread; callers must post to the main looper themselves. */
    fun search(
        backendURL: String,
        vertical: String,
        query: String,
        deviceId: String,
        lat: Double? = null,
        lon: Double? = null,
        country: String? = null,
        tz: String? = null,
        onCards: (String, List<SearchCard>) -> Unit,
        onError: (String) -> Unit,
    ) {
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL("$backendURL/search").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 15000
                    setRequestProperty("Content-Type", "application/json")
                    signIn()
                }
                val body = JSONObject().apply {
                    put("vertical", vertical)
                    put("query", query)
                    put("deviceId", deviceId)
                    if (lat != null && lon != null) { put("lat", lat); put("lon", lon) }
                    if (country != null && country.length == 2) put("country", country)
                    if (tz != null) put("tz", tz)
                }
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                val json = JSONObject(conn.inputStream.bufferedReader().readText())
                onCards(json.optString("vertical", vertical), parseCards(json))
            } catch (e: Exception) {
                android.util.Log.e("GlyfKB", "search failed: $e")
                onError("Couldn't search right now")
            } finally {
                conn?.disconnect()
            }
        }
    }

    /** POST /suggest — the model names what Glyf could do with the sentence
     *  ("Tidy this up", "Show me places"), or nothing. Silent on failure. */
    fun suggestAction(
        backendURL: String,
        text: String,
        deviceId: String,
        kinds: List<String> = emptyList(),
        onResult: (intent: String, label: String, query: String) -> Unit,
    ): () -> Unit {
        val cancelled = java.util.concurrent.atomic.AtomicBoolean(false)
        pool.execute {
            try {
                val c = (URL("$backendURL/suggest").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 4000
                    readTimeout = 8000
                    setRequestProperty("Content-Type", "application/json")
                    signIn()
                }
                val body = JSONObject().put("text", text).put("deviceId", deviceId)
                // The kinds of detail saved, never the details.
                if (kinds.isNotEmpty()) body.put("kinds", org.json.JSONArray(kinds))
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                if (c.responseCode !in 200..299 || cancelled.get()) return@execute
                val json = JSONObject(c.inputStream.bufferedReader().readText())
                val s = json.optJSONObject("suggestion") ?: return@execute
                val intent = s.optStringOrNull("intent") ?: return@execute
                val label = s.optStringOrNull("label") ?: return@execute
                if (!cancelled.get()) onResult(intent, label, s.optStringOrNull("query") ?: text)
            } catch (_: Exception) { /* no chip */ }
        }
        return { cancelled.set(true) }
    }

    /** GET /search/suggest — the landing state for a tab (trending searches,
     *  popular videos, nearby places). The user's own recents stay on the
     *  device and are merged in by the caller. */
    fun suggest(
        backendURL: String,
        vertical: String,
        deviceId: String,
        lat: Double? = null,
        lon: Double? = null,
        country: String? = null,
        onCards: (String, List<SearchCard>) -> Unit,
        onError: (String) -> Unit,
    ) {
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                val q = StringBuilder("vertical=$vertical&deviceId=$deviceId")
                if (lat != null && lon != null) q.append("&lat=$lat&lon=$lon")
                if (country != null && country.length == 2) q.append("&country=$country")
                conn = (URL("$backendURL/search/suggest?$q").openConnection()
                    as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 5000
                    readTimeout = 12000
                    // The gate turns away a request without a session; the
                    // landing rows were silently empty without this.
                    signIn()
                }
                val json = JSONObject(conn.inputStream.bufferedReader().readText())
                onCards(json.optString("vertical", vertical), parseCards(json))
            } catch (e: Exception) {
                android.util.Log.e("GlyfKB", "suggest failed: $e")
                onError("")
            } finally {
                conn?.disconnect()
            }
        }
    }

    data class Translation(val detected: String, val target: String, val text: String)

    /** POST /translate — detects the language and picks the direction from
     *  the person's two languages (iOS twin). Callback on the pool thread. */
    fun translate(
        backendURL: String,
        deviceId: String,
        text: String,
        primary: String,
        secondary: String,
        target: String?,
        done: (Translation?) -> Unit,
    ) {
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL("$backendURL/translate").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 15000
                    setRequestProperty("Content-Type", "application/json")
                    signIn()
                }
                val body = JSONObject().apply {
                    put("text", text); put("deviceId", deviceId)
                    put("primary", primary); put("secondary", secondary)
                    if (target != null) put("target", target)
                }
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                val json = JSONObject(conn.inputStream.bufferedReader().readText())
                val out = json.optString("translation").takeIf { it.isNotBlank() }?.let {
                    Translation(json.optString("detected"), json.optString("target"), it)
                }
                done(out)
            } catch (e: Exception) {
                android.util.Log.e("GlyfKB", "translate failed: $e")
                done(null)
            } finally {
                conn?.disconnect()
            }
        }
    }

    /** POST /act result — mirrors the Swift `BackendClient.ActResult`. */
    data class RewriteOption(val id: String, val label: String, val text: String)

    data class ActResult(
        val intent: String,
        val title: String,
        val cards: List<SearchCard>,
        val text: String?,
        val insert: String,
        val remaining: Int?,
        /** A rewrite's versions (Basic, Professional, Polite…), when offered. */
        val options: List<RewriteOption> = emptyList(),
    )

    /** POST /act — hold space on typed text: the server routes the intent
     *  (place, list, answer, video, rewrite). Callbacks land on the pool
     *  thread; callers post to the main looper. */
    fun act(
        backendURL: String,
        text: String,
        deviceId: String,
        plan: String,
        lat: Double? = null,
        lon: Double? = null,
        country: String? = null,
        tz: String? = null,
        intent: String? = null,
        profile: Map<String, String>? = null,
        onResult: (ActResult) -> Unit,
        onError: (String) -> Unit,
    ) {
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                val c = (URL("$backendURL/act").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 40000
                    setRequestProperty("Content-Type", "application/json")
                    signIn()
                }
                conn = c
                val body = JSONObject().apply {
                    put("text", text)
                    put("deviceId", deviceId)
                    put("plan", plan)
                    if (lat != null && lon != null) { put("lat", lat); put("lon", lon) }
                    if (country != null && country.length == 2) put("country", country)
                    if (tz != null) put("tz", tz)
                    if (intent != null) put("intent", intent)
                    if (!profile.isNullOrEmpty()) put("profile", JSONObject(profile))
                }
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                val ok = c.responseCode in 200..299
                val raw = (if (ok) c.inputStream else c.errorStream)?.bufferedReader()?.readText() ?: ""
                val json = if (raw.isNotBlank()) JSONObject(raw) else JSONObject()
                if (!ok || !json.optBoolean("ok")) {
                    onError(json.optStringOrNull("error") ?: "Couldn't do that right now. Tap to retry.")
                    return@execute
                }
                val textOut = json.optStringOrNull("text")
                onResult(ActResult(
                    intent = json.optString("intent", "rewrite"),
                    title = json.optString("title"),
                    cards = parseCards(json),
                    text = textOut,
                    insert = json.optStringOrNull("insert") ?: textOut ?: "",
                    remaining = if (json.has("remaining")) json.optInt("remaining") else null,
                    options = json.optJSONArray("options")?.let { arr ->
                        (0 until arr.length()).mapNotNull { i ->
                            arr.optJSONObject(i)?.let { o ->
                                RewriteOption(o.optString("id"), o.optString("label"), o.optString("text"))
                                    .takeIf { it.text.isNotBlank() }
                            }
                        }
                    } ?: emptyList(),
                ))
            } catch (e: Exception) {
                android.util.Log.e("GlyfKB", "act failed: $e")
                onError("Couldn't reach Glyf. Tap to retry.")
            } finally {
                conn?.disconnect()
            }
        }
    }

    private fun parseCards(json: JSONObject): List<SearchCard> {
        val arr = json.optJSONArray("cards") ?: org.json.JSONArray()
        val cards = mutableListOf<SearchCard>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            cards.add(SearchCard(
                kind = o.optString("kind", "link"),
                id = o.optString("id", "$i"),
                title = o.optString("title"),
                url = o.optString("url"),
                emoji = o.optStringOrNull("emoji"),
                extra = o.optStringOrNull("extra"),
                say = o.optStringOrNull("say"),
                value = o.optStringOrNull("value"),
                sub = o.optStringOrNull("sub"),
                art = o.optStringOrNull("art"),
                source = o.optStringOrNull("source"),
                snippet = o.optStringOrNull("snippet"),
                domain = o.optStringOrNull("domain"),
                thumb = o.optStringOrNull("thumb"),
                channel = o.optStringOrNull("channel"),
                duration = o.optStringOrNull("duration"),
                live = o.optBoolean("live", false),
                address = o.optStringOrNull("address"),
                rating = if (o.has("rating")) o.optDouble("rating") else null,
                ratingCount = if (o.has("ratingCount")) o.optInt("ratingCount") else null,
                openNow = if (o.has("openNow")) o.optBoolean("openNow") else null,
                distance = o.optStringOrNull("distance"),
                lat = if (o.has("lat") && !o.isNull("lat")) o.optDouble("lat") else null,
                lon = if (o.has("lon") && !o.isNull("lon")) o.optDouble("lon") else null,
            ))
        }
        return cards
    }

    /** optString() turns a missing key into "", which would render as an
     *  empty line rather than being skipped. */
    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null

    fun run(
        backendURL: String,
        glyfId: String,
        input: String,
        vars: Map<String, String>,
        deviceId: String,
        plan: String,
        onToken: (String) -> Unit,
        onDone: (String, Int?) -> Unit,
        onError: (String) -> Unit,
    ) {
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                android.util.Log.d("GlyfKB", "run start url=$backendURL glyf=$glyfId")
                conn = (URL("$backendURL/glyf/run").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 30000
                    setRequestProperty("Content-Type", "application/json")
                    signIn()
                    setRequestProperty("Accept", "text/event-stream")
                }
                val body = JSONObject(mapOf(
                    "glyfId" to glyfId, "input" to input,
                    "vars" to JSONObject(vars as Map<*, *>),
                    "deviceId" to deviceId, "plan" to plan))
                conn.outputStream.use { it.write(body.toString().toByteArray()) }

                val reader = BufferedReader(conn.inputStream.reader())
                var event = "message"
                var full = ""
                var finished = false
                reader.forEachLine { line ->
                    when {
                        line.startsWith("event:") -> event = line.substring(6).trim()
                        line.startsWith("data:") -> {
                            val data = JSONObject(line.substring(5).trim())
                            when (event) {
                                "token" -> {
                                    val t = data.optString("t")
                                    full += t
                                    onToken(t)
                                }
                                "done" -> {
                                    finished = true
                                    android.util.Log.d("GlyfKB", "done len=${data.optString("text", full).length}")
                                    onDone(data.optString("text", full),
                                        if (data.has("remaining")) data.optInt("remaining") else null)
                                }
                                "error" -> {
                                    finished = true
                                    onError(data.optString("message", "Something went wrong"))
                                }
                            }
                        }
                    }
                }
                if (!finished) {
                    android.util.Log.d("GlyfKB", "stream ended unfinished http=${conn.responseCode}")
                    onError("Couldn't reach Glyf. Tap to retry.")
                }
            } catch (e: Exception) {
                android.util.Log.e("GlyfKB", "run failed: $e")
                onError("Couldn't reach Glyf. Tap to retry.")
            } finally {
                conn?.disconnect()
            }
        }
    }
}
