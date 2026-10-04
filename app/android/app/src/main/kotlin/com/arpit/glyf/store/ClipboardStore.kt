package com.arpit.glyf.store

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * §6.1 clipboard manager, the twin of iOS ClipboardStore: the last 20 copies,
 * pinnable, an hour's life unless pinned, refusing anything secret-shaped.
 *
 * Android hands a keyboard the clipboard without asking, so unlike iOS this
 * captures on its own every time the keyboard comes up — which is the whole
 * point: what you copied earlier is still there when you need it.
 */
object ClipboardStore {
    const val FILE = "clipboard.json"
    const val MAX_ITEMS = 20
    /** Unpinned copies keep for two days; pinning is what makes one
     *  permanent (prune never drops a pinned item, whatever its age). */
    const val EXPIRY_MS = 48 * 60 * 60 * 1000L

    data class Item(val text: String, val ts: Long, val pinned: Boolean)

    fun load(ctx: Context, now: Long = System.currentTimeMillis()): List<Item> {
        val raw = try {
            val f = Bridge.file(ctx, FILE)
            if (f.exists()) JSONArray(f.readText()) else JSONArray()
        } catch (_: Exception) { JSONArray() }
        val out = mutableListOf<Item>()
        for (i in 0 until raw.length()) {
            val o = raw.optJSONObject(i) ?: continue
            val item = Item(o.optString("text"), o.optLong("ts"), o.optBoolean("pinned"))
            if (item.text.isBlank()) continue
            if (item.pinned || now - item.ts < EXPIRY_MS) out.add(item)
        }
        return out.take(MAX_ITEMS)
    }

    fun save(ctx: Context, items: List<Item>) {
        val arr = JSONArray()
        for (item in items.take(MAX_ITEMS)) {
            arr.put(JSONObject().apply {
                put("text", item.text)
                put("ts", item.ts)
                put("pinned", item.pinned)
            })
        }
        Bridge.write(ctx, FILE, arr.toString())
    }

    /** Pure so it can be tested: the new list, or null when refused. */
    fun inserting(text: String, into: List<Item>, now: Long): List<Item>? {
        if (SecretScanner.scan(text) != null) return null   // secret-shaped: never stored
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed.length > 4000) return null
        if (into.firstOrNull()?.text == trimmed) return null
        val next = mutableListOf(Item(trimmed, now, false))
        next.addAll(into.filter { it.text != trimmed || it.pinned })
        // Never evict a pinned item; drop the oldest unpinned past the cap.
        while (next.size > MAX_ITEMS) {
            val idx = next.indexOfLast { !it.pinned }
            if (idx < 0) break
            next.removeAt(idx)
        }
        return next.take(MAX_ITEMS)
    }

    /** What was copied, as text, or null when it isn't text. A picture on
     *  the clipboard (a screenshot, a GIF) is a content URI, and
     *  coerceToText opens it and reads its bytes as if they were words: a
     *  200 KB screenshot became the strip's "text", read on the main thread.
     *  A web link copied as a link is text. */
    fun clipText(ctx: Context): String? {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
            as? android.content.ClipboardManager ?: return null
        val item = try {
            cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
        } catch (_: Exception) { null } ?: return null
        item.text?.let { return it.toString() }
        val uri = item.uri ?: return null
        return if (uri.scheme == "http" || uri.scheme == "https") uri.toString() else null
    }

    /** Reads the system clipboard and files it. True when something new landed.
     *  Nothing is kept while "Keep what you copy" is off in the app (iOS
     *  checks the same setting before every capture). */
    fun captureNow(ctx: Context, settings: JSONObject = SettingsStore.load(ctx)): Boolean {
        if (!settings.optBoolean("clipboardHistory", true)) return false
        val text = clipText(ctx) ?: return false
        val next = inserting(text, load(ctx), System.currentTimeMillis()) ?: return false
        save(ctx, next)
        return true
    }

    fun togglePin(ctx: Context, text: String) {
        save(ctx, load(ctx).map { if (it.text == text) it.copy(pinned = !it.pinned) else it })
    }

    fun remove(ctx: Context, text: String) {
        save(ctx, load(ctx).filter { it.text != text })
    }

    fun clearUnpinned(ctx: Context) {
        save(ctx, load(ctx).filter { it.pinned })
    }

    /** "Just now", "2 min", "1 hr", "Yesterday" — the website's clipboard ages. */
    fun age(ts: Long, now: Long = System.currentTimeMillis()): String {
        val secs = (now - ts) / 1000
        return when {
            secs < 45 -> "Just now"
            secs < 3600 -> "${maxOf(1, secs / 60)} min"
            secs < 86_400 -> "${maxOf(1, secs / 3600)} hr"
            secs < 172_800 -> "Yesterday"
            else -> "${secs / 86_400} days"
        }
    }
}
