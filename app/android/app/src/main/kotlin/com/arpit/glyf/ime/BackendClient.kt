package com.arpit.glyf.ime

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

    /** Private AI on NEAR AI Cloud: "near" while the app's switch is on
     *  (shared settings `privateAI`, SettingsStore.privateAIHeader), sent as
     *  X-Glyf-AI with every call; null sends nothing. Kept by the IME as it
     *  reads its settings. */
    @Volatile
    @JvmStatic
    var privateAI: String? = null

    private fun HttpURLConnection.signIn() = session(this)

    /** What every call to Glyf's server carries: the session, and the
     *  private-AI choice when there is one (iOS's URLRequest.glyfSession). */
    @JvmStatic
    fun session(conn: HttpURLConnection) {
        bearer?.let { conn.setRequestProperty("Authorization", "Bearer $it") }
        privateAI?.let { conn.setRequestProperty("X-Glyf-AI", it) }
    }

    /** POST /report — flag an AI result (Google Play's AI-Generated Content
     *  policy). `onDone(true)` once the server has it. */
    fun report(
        backendURL: String,
        deviceId: String,
        feature: String,
        result: String,
        onDone: (Boolean) -> Unit,
    ) {
        pool.execute {
            var conn: HttpURLConnection? = null
            val ok = try {
                conn = (URL("$backendURL/report").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 10000
                    setRequestProperty("Content-Type", "application/json")
                    signIn()
                }
                val body = JSONObject(mapOf(
                    "deviceId" to deviceId, "feature" to feature.take(64),
                    "result" to result.take(4000), "platform" to "android"))
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                conn.responseCode in 200..299
            } catch (_: Exception) {
                false
            } finally {
                conn?.disconnect()
            }
            onDone(ok)
        }
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
        // short (the Shorts tab, 2026-11-06; also channel, duration, thumb)
        val seconds: Int? = null,
        /** YouTube reported a taller-than-wide player: the thumbnail is its
         *  9:16 frame centred on YouTube's own filler. */
        val portrait: Boolean? = null,
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
        /** The keyboard's theme: a maps search draws its places' maps in it
         *  before the cards ask for them. */
        dark: Boolean? = null,
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
                    if (dark != null) put("dark", dark)
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
     *  ("Tidy this up", "Show me places"), or nothing. Silent on failure, and
     *  never one of the person's runs: suggestions have their own allowance. */
    fun suggestAction(
        backendURL: String,
        text: String,
        deviceId: String,
        kinds: List<String> = emptyList(),
        /** Given, the phone asks for a tool the model names (actions:true)
         *  and opens it prefilled (AIAction); it wins over the text chip. */
        onAction: ((AIAction) -> Unit)? = null,
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
                // It also opens NEAR Intents' tools (near.swap … near.pot.pay).
                if (onAction != null) body.put("actions", true).put("near", true)
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                if (c.responseCode !in 200..299 || cancelled.get()) return@execute
                val json = JSONObject(c.inputStream.bufferedReader().readText())
                // A tool the model named, checked by the server, wins over its text chip.
                if (onAction != null) json.optJSONObject("action")?.let { AIAction.from(it) }?.let {
                    if (!cancelled.get()) onAction(it)
                    return@execute
                }
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
     *  (place, list, answer, video, rewrite, write). With `onOption` the
     *  answer streams: each version of a rewrite the moment the model
     *  finishes it, written text as it comes (`onText`), and `onReset` when
     *  the model was swapped midway. Callbacks land on the pool thread;
     *  callers post to the main looper. */
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
        onOption: ((RewriteOption) -> Unit)? = null,
        onText: ((String) -> Unit)? = null,
        onReset: (() -> Unit)? = null,
        onResult: (ActResult) -> Unit,
        onError: (String) -> Unit,
    ) {
        val failed = "Couldn't do that right now. Tap to retry."
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                val streaming = onOption != null
                val c = (URL("$backendURL/act").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 40000
                    setRequestProperty("Content-Type", "application/json")
                    if (streaming) setRequestProperty("Accept", "text/event-stream")
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
                    if (streaming) put("stream", true)
                }
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                val ok = c.responseCode in 200..299
                val sse = c.contentType?.startsWith("text/event-stream") == true
                if (!ok || !sse) {
                    val raw = (if (ok) c.inputStream else c.errorStream)?.bufferedReader()?.readText() ?: ""
                    val json = if (raw.isNotBlank()) JSONObject(raw) else JSONObject()
                    if (!ok || !json.optBoolean("ok")) onError(json.optStringOrNull("error") ?: failed)
                    else onResult(parseActResult(json))
                    return@execute
                }
                // Server-sent events: "event: <type>" then "data: <json>", a
                // blank line after each.
                var event = "message"
                val data = StringBuilder()
                var finished = false
                c.inputStream.bufferedReader().useLines { lines ->
                    for (line in lines) {
                        when {
                            line.startsWith("event:") -> event = line.removePrefix("event:").trim()
                            line.startsWith("data:") -> data.append(line.removePrefix("data:").trim())
                            line.isEmpty() && data.isNotEmpty() -> {
                                val json = JSONObject(data.toString())
                                data.setLength(0)
                                when (event) {
                                    "option" -> RewriteOption(json.optString("id"), json.optString("label"),
                                        json.optString("text")).takeIf { it.text.isNotBlank() }?.let { onOption?.invoke(it) }
                                    "text" -> json.optStringOrNull("t")?.let { onText?.invoke(it) }
                                    "reset" -> onReset?.invoke()
                                    "done" -> { finished = true; onResult(parseActResult(json)) }
                                    "error" -> { finished = true; onError(json.optStringOrNull("error") ?: failed) }
                                }
                                event = "message"
                            }
                        }
                    }
                }
                if (!finished) onError("Couldn't reach Glyf. Tap to retry.")
            } catch (e: Exception) {
                android.util.Log.e("GlyfKB", "act failed: $e")
                onError("Couldn't reach Glyf. Tap to retry.")
            } finally {
                conn?.disconnect()
            }
        }
    }

    private fun parseActResult(json: JSONObject): ActResult {
        val textOut = json.optStringOrNull("text")
        return ActResult(
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
        )
    }

    fun parseCards(json: JSONObject): List<SearchCard> {
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
                seconds = if (o.has("seconds") && !o.isNull("seconds")) o.optInt("seconds") else null,
                portrait = if (o.has("portrait") && !o.isNull("portrait")) o.optBoolean("portrait") else null,
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

    /** POST /glyf/run, streamed. Like iOS it carries the shareable details
     *  (for prompts that fill something in) and the phone's coarse fix (so
     *  Weather can answer for here when no place is named). */
    fun run(
        backendURL: String,
        glyfId: String,
        input: String,
        vars: Map<String, String>,
        deviceId: String,
        plan: String,
        profile: Map<String, String>? = null,
        lat: Double? = null,
        lon: Double? = null,
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
                if (!profile.isNullOrEmpty()) body.put("profile", JSONObject(profile as Map<*, *>))
                if (lat != null && lon != null) { body.put("lat", lat); body.put("lon", lon) }
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
