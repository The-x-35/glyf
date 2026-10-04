package com.arpit.glyf.ime

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors

/** One GIF or sticker, whichever source found it (the iOS MediaItem twin). */
data class MediaItem(
    val id: String,
    val title: String?,
    /** Small image for the grid: an animated GIF (KLIPY) or a still (Noto). */
    val preview: String,
    val pw: Double?,
    val ph: Double?,
    /** The file that is sent, sized for a message. */
    val url: String,
    val w: Double?,
    val h: Double?,
    /** KLIPY's slug, for its share count and recents. Null for Noto. */
    val slug: String? = null,
) {
    /** Width over height for the grid; square when unknown. */
    val aspect: Float get() {
        val width = pw ?: w ?: 1.0
        val height = ph ?: h ?: 1.0
        if (width <= 0 || height <= 0) return 1f
        return (width / height).coerceIn(0.4, 3.0).toFloat()
    }

    fun toJson(): JSONObject = JSONObject().put("id", id).put("title", title)
        .put("preview", preview).put("pw", pw).put("ph", ph)
        .put("url", url).put("w", w).put("h", h).put("slug", slug)

    companion object {
        fun from(o: JSONObject): MediaItem? {
            // org.json answers "null" (the word) for a JSON null: check first.
            fun str(k: String) = if (o.isNull(k)) null else o.optString(k).ifEmpty { null }
            fun num(k: String) = if (o.isNull(k)) null else o.optDouble(k).takeIf { !it.isNaN() }
            val id = str("id") ?: return null
            val preview = str("preview") ?: return null
            val url = str("url") ?: return null
            return MediaItem(id, str("title"), preview, num("pw"), num("ph"),
                url, num("w"), num("h"), str("slug"))
        }
    }
}

data class MediaPage(val items: List<MediaItem>, val next: String?, val attribution: String?)

enum class MediaKind(val path: String) { GIFS("gifs"), STICKERS("stickers") }

/** KLIPY's results never share a grid with anything else (its terms). */
enum class MediaSource { KLIPY, NOTO }

/**
 * GIFs and stickers for the emoji board, the Android twin of MediaClient.swift.
 *
 * KLIPY replaced Tenor's closed API; its terms want calls and file loads to
 * come from the device, so the keyboard calls it with the key our server
 * hands a signed-in phone (`/media/config`). Noto Animated Emoji (CC BY 4.0)
 * are stickers with no key, listed by our server. Callbacks run on the main
 * thread.
 */
object MediaClient {

    data class Klipy(val key: String, val base: String, val contentFilter: String)
    data class Config(val klipy: Klipy?, val emojiStickers: Boolean)

    private val pool = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())

    @Volatile var config: Config? = null
        private set
    private var configAt = 0L

    /** Downloaded previews by URL, bounded by bytes. Previews only, on the
     *  phone: the one thing KLIPY's terms allow to be kept. */
    private val cache = object : LruCache<String, ByteArray>(12 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray) = value.size
    }

    /** A random id for this install, for KLIPY's recents. Not the person. */
    fun customerId(ctx: Context): String {
        val prefs = ctx.getSharedPreferences("glyf.media", Context.MODE_PRIVATE)
        prefs.getString("customerId", null)?.let { return it }
        val id = UUID.randomUUID().toString()
        prefs.edit().putString("customerId", id).apply()
        return id
    }

    private val language: String
        get() = Locale.getDefault().language.ifEmpty { "en" }

    private fun open(url: String, bearer: String? = null): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 6000
            readTimeout = 12000
            bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
        }

    // MARK: config

    fun loadConfig(backendURL: String, done: (Config?) -> Unit) {
        config?.let { if (System.currentTimeMillis() - configAt < 3_600_000) { done(it); return } }
        pool.execute {
            var parsed: Config? = null
            try {
                val c = open("$backendURL/media/config", BackendClient.bearer)
                if (c.responseCode == 200) {
                    val o = JSONObject(c.inputStream.bufferedReader().readText())
                    val k = o.optJSONObject("klipy")
                    val klipy = k?.let {
                        val key = it.optString("key")
                        if (key.isEmpty()) null
                        else Klipy(key, it.optString("base"), it.optString("contentFilter", "high"))
                    }
                    parsed = Config(klipy, o.optBoolean("emojiStickers", true))
                }
                c.disconnect()
            } catch (_: Exception) { }
            main.post {
                if (parsed != null) { config = parsed; configAt = System.currentTimeMillis() }
                done(parsed ?: config)
            }
        }
    }

    // MARK: feeds

    /** Trending when `query` is empty; `query == null` is KLIPY's recents. */
    fun page(
        ctx: Context, backendURL: String, kind: MediaKind, source: MediaSource,
        query: String?, page: String?, done: (MediaPage?) -> Unit,
    ) {
        if (source == MediaSource.NOTO) return notoPage(backendURL, query ?: "", page, done)
        val klipy = config?.klipy
        if (klipy == null) { main.post { done(null) }; return }
        val customer = customerId(ctx)
        val path = when {
            query == null -> "recent/$customer"
            query.isEmpty() -> "trending"
            else -> "search"
        }
        val q = StringBuilder("page=${page ?: "1"}&per_page=24&customer_id=$customer")
            .append("&locale=$language&content_filter=${klipy.contentFilter}")
            .append("&format_filter=").append(if (kind == MediaKind.GIFS) "gif" else "gif,png")
        if (!query.isNullOrEmpty()) q.append("&q=").append(URLEncoder.encode(query.take(80), "UTF-8"))
        pool.execute {
            var result: MediaPage? = null
            try {
                val c = open("${klipy.base}${klipy.key}/${kind.path}/$path?$q")
                if (c.responseCode == 200) {
                    result = parseKlipy(c.inputStream.bufferedReader().readText(), kind)
                }
                c.disconnect()
            } catch (_: Exception) { }
            main.post { done(result) }
        }
    }

    /** KLIPY's envelope: {result, data: {data: [items], current_page,
     *  has_next}}; each item has file.{hd,md,sm,xs}.{gif,webp,png,jpg}. Ads
     *  (type "ad") are skipped: this keyboard shows none. */
    fun parseKlipy(body: String, kind: MediaKind): MediaPage? {
        val root = runCatching { JSONObject(body) }.getOrNull() ?: return null
        if (root.has("result") && !root.optBoolean("result")) return null
        val data = root.optJSONObject("data") ?: return null
        val list = data.optJSONArray("data") ?: return null
        val formats = if (kind == MediaKind.GIFS) listOf("gif") else listOf("gif", "png")
        fun variant(file: JSONObject, sizes: List<String>): Triple<String, Double?, Double?>? {
            for (size in sizes) {
                val set = file.optJSONObject(size) ?: continue
                for (f in formats) {
                    val v = set.optJSONObject(f) ?: continue
                    val url = v.optString("url").ifEmpty { continue }
                    return Triple(url, v.optDouble("width").takeIf { !it.isNaN() },
                        v.optDouble("height").takeIf { !it.isNaN() })
                }
            }
            return null
        }
        val items = (0 until list.length()).mapNotNull { i ->
            val raw = list.optJSONObject(i) ?: return@mapNotNull null
            if (raw.optString("type") == "ad" || raw.has("content")) return@mapNotNull null
            val file = raw.optJSONObject("file") ?: return@mapNotNull null
            val slug = (if (raw.isNull("slug")) "" else raw.optString("slug")).ifEmpty { raw.optString("id") }
            val preview = variant(file, listOf("sm", "xs", "md")) ?: return@mapNotNull null
            val full = variant(file, listOf("md", "hd", "sm")) ?: return@mapNotNull null
            MediaItem("klipy:$slug", if (raw.isNull("title")) null else raw.optString("title").ifEmpty { null },
                preview.first, preview.second, preview.third,
                full.first, full.second, full.third, slug)
        }
        val hasNext = data.optBoolean("has_next", false)
        val current = data.optInt("current_page", 1)
        return MediaPage(items, if (hasNext) (current + 1).toString() else null, "Powered by KLIPY")
    }

    private fun notoPage(backendURL: String, query: String, page: String?, done: (MediaPage?) -> Unit) {
        val q = StringBuilder("page=${page ?: "1"}")
        if (query.isNotEmpty()) q.append("&q=").append(URLEncoder.encode(query.take(60), "UTF-8"))
        pool.execute {
            var result: MediaPage? = null
            try {
                val c = open("$backendURL/media/emoji-stickers?$q", BackendClient.bearer)
                if (c.responseCode == 200) {
                    val o = JSONObject(c.inputStream.bufferedReader().readText())
                    val arr = o.optJSONArray("items") ?: JSONArray()
                    val items = (0 until arr.length()).mapNotNull { MediaItem.from(arr.getJSONObject(it)) }
                    result = MediaPage(items, o.optString("next").ifEmpty { null }.takeIf { !o.isNull("next") },
                        o.optString("attribution").ifEmpty { null })
                }
                c.disconnect()
            } catch (_: Exception) { }
            main.post { done(result) }
        }
    }

    /** KLIPY's completions for what has been typed; nothing without KLIPY. */
    fun suggest(query: String, done: (List<String>) -> Unit) {
        val klipy = config?.klipy
        if (klipy == null || query.isEmpty()) { done(emptyList()); return }
        pool.execute {
            var terms = emptyList<String>()
            try {
                val c = open("${klipy.base}${klipy.key}/autocomplete/" +
                    URLEncoder.encode(query.take(50), "UTF-8").replace("+", "%20") +
                    "?limit=6&locale=$language")
                if (c.responseCode == 200) terms = parseTerms(c.inputStream.bufferedReader().readText())
                c.disconnect()
            } catch (_: Exception) { }
            main.post { done(terms) }
        }
    }

    fun parseTerms(body: String): List<String> {
        fun strings(a: JSONArray?): List<String>? = a?.let { arr ->
            (0 until arr.length()).mapNotNull { i ->
                arr.opt(i).let { v ->
                    when (v) {
                        is String -> v
                        is JSONObject -> v.optString("query").ifEmpty { v.optString("term") }.ifEmpty { null }
                        else -> null
                    }
                }
            }
        }
        runCatching { JSONArray(body) }.getOrNull()?.let { return strings(it) ?: emptyList() }
        val o = runCatching { JSONObject(body) }.getOrNull() ?: return emptyList()
        o.optJSONArray("data")?.let { return strings(it) ?: emptyList() }
        return strings(o.optJSONObject("data")?.optJSONArray("data")) ?: emptyList()
    }

    /** Tells KLIPY one was sent (its trending, this install's recents). */
    fun reportShare(ctx: Context, item: MediaItem, kind: MediaKind, query: String?) {
        val klipy = config?.klipy ?: return
        val slug = item.slug ?: return
        val customer = customerId(ctx)
        pool.execute {
            try {
                val c = open("${klipy.base}${klipy.key}/${kind.path}/share/$slug").apply {
                    requestMethod = "POST"
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                }
                val body = JSONObject().put("customer_id", customer)
                if (!query.isNullOrEmpty()) body.put("q", query)
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                c.responseCode
                c.disconnect()
            } catch (_: Exception) { }
        }
    }

    // MARK: files

    fun previewData(url: String, done: (ByteArray?) -> Unit) {
        cache.get(url)?.let { done(it); return }
        pool.execute {
            val bytes = fetchBytes(url)
            main.post {
                if (bytes != null) cache.put(url, bytes)
                done(bytes)
            }
        }
    }

    /** The file to send: fetched on tap, never cached. */
    fun fullData(url: String, done: (ByteArray?) -> Unit) {
        pool.execute {
            val bytes = fetchBytes(url)
            main.post { done(bytes) }
        }
    }

    private fun fetchBytes(url: String): ByteArray? = try {
        val c = open(url)
        val ok = c.responseCode in 200..299
        val bytes = if (ok) c.inputStream.use { it.readBytes() } else null
        c.disconnect()
        bytes
    } catch (_: Exception) { null }
}

/** Noto stickers sent recently (KLIPY keeps its own list). */
object MediaRecents {
    private fun file(ctx: Context, kind: MediaKind) =
        com.arpit.glyf.store.Bridge.file(ctx, "media-recents-${kind.path}.json")

    fun load(ctx: Context, kind: MediaKind): List<MediaItem> = runCatching {
        val arr = JSONArray(file(ctx, kind).readText())
        (0 until arr.length()).mapNotNull { MediaItem.from(arr.getJSONObject(it)) }
    }.getOrDefault(emptyList())

    fun push(ctx: Context, item: MediaItem, kind: MediaKind) {
        if (item.slug != null) return
        val list = listOf(item) + load(ctx, kind).filter { it.id != item.id }
        runCatching {
            file(ctx, kind).writeText(JSONArray(list.take(30).map { it.toJson() }).toString())
        }
    }
}

/** Emoji and emoticons sent recently, newest first (iOS twins). */
object TextRecents {
    fun load(ctx: Context, name: String, fallback: List<String> = emptyList()): List<String> = runCatching {
        val arr = JSONArray(com.arpit.glyf.store.Bridge.file(ctx, name).readText())
        (0 until arr.length()).map { arr.getString(it) }
    }.getOrDefault(fallback)

    fun push(ctx: Context, name: String, value: String, keep: Int = 32) {
        val list = listOf(value) + load(ctx, name).filter { it != value }
        runCatching {
            com.arpit.glyf.store.Bridge.file(ctx, name).writeText(JSONArray(list.take(keep)).toString())
        }
    }
}
