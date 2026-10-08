package com.arpit.glyf.store

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Shared state between the Flutter app and the IME — same JSON files and
 * schemas as iOS's App Group bridge, living in filesDir/bridge/ (app and
 * keyboard are one package on Android, so sharing is just the filesystem).
 */
object Bridge {
    fun dir(ctx: Context): File =
        File(ctx.filesDir, "bridge").apply { mkdirs() }

    fun file(ctx: Context, name: String): File = File(dir(ctx), name)

    fun readJson(ctx: Context, name: String): JSONObject? = try {
        val f = file(ctx, name)
        if (f.exists()) JSONObject(f.readText()) else null
    } catch (_: Exception) { null }

    fun write(ctx: Context, name: String, content: String): Boolean = try {
        val f = file(ctx, name)
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(content)
        tmp.renameTo(f)
        true
    } catch (_: Exception) { false }
}

/** Mirrors iOS GlyfSettings — same keys, same defaults (schemaVersion 3). */
object SettingsStore {
    const val FILE = "settings.json"

    /** The strip's tools for anyone who hasn't moved them (iOS
     *  GlyfSettings.Toolbar.defaultOrder). */
    val DEFAULT_STRIP = listOf("search", "clipboard", "vault", "calendar", "tempmail")

    /** The deployed API. Changing the domain? This is the only place. */
    const val PRODUCTION_BACKEND = "https://api.tryglyf.com"

    private val isDebug get() = com.arpit.glyf.BuildConfig.DEBUG

    private fun defaultBackendURL() =
        if (isDebug) "http://10.0.2.2:8787" else PRODUCTION_BACKEND

    /** Shipped builds must never point at a laptop, even on old installs. */
    private fun productionized(url: String): String {
        // A debug build must not inherit a production URL persisted by a
        // release install — dev work would silently leave the dev server.
        if (isDebug) return if (url == PRODUCTION_BACKEND) defaultBackendURL() else url
        val dev = listOf("127.0.0.1", "localhost", "10.0.2.2", "0.0.0.0")
        return if (dev.any { url.contains(it) }) PRODUCTION_BACKEND else url
    }

    fun defaults(): JSONObject = JSONObject().apply {
        put("schemaVersion", 9)
        put("haptics", true)
        put("keyClicks", true)
        put("numberRow", false)
        // Swipe-to-type over the letters (iOS GlyfSettings.glideTyping).
        put("glideTyping", true)
        put("autocorrect", true)
        put("autocapitalize", true)
        put("periodShortcut", true)
        put("candidates", true)
        put("oneHanded", "off")
        // Arpit, 2026-10-06: "from top bar remove mic and translate and
        // instead add calendar and temp mail for default".
        put("toolbarOrder", JSONArray(DEFAULT_STRIP))
        put("toolbarHidden", JSONArray())
        // Two holds only: V shares your details, C opens the calendar. Every
        // other letter is the person's to bind; hold-space AI covers the rest.
        put("bindings", JSONObject(mapOf(
            "v" to "surface:vault",
            "c" to "connector:calendar")))
        put("customTitles", JSONObject())
        put("translationHUD", false)
        put("proUnlocked", false)
        put("plan", "free")
        // What the strip converts money into; "auto" follows the region.
        put("moneyCurrency", "auto")
        // Apply a correction on the space, or only offer it in the strip.
        put("autocorrectApply", true)
        put("appearance", "auto")
        put("keyTheme", "site")
        put("themeBg", "")          // "" | color:#RRGGBB | grad:<id>
        put("keyBorders", false)
        put("themeBrightness", 0.0)
    // Search paste style: "titleAndLink" (Gboard default) | "linkOnly".
    put("pasteStyle", "titleAndLink")
        put("backendURL", defaultBackendURL())
        put("deviceId", UUID.randomUUID().toString().lowercase())
        put("translateTarget", "English")
    }

    fun load(ctx: Context): JSONObject {
        val current = Bridge.readJson(ctx, FILE)
        if (current == null) {
            val fresh = defaults()
            Bridge.write(ctx, FILE, fresh.toString())
            return fresh
        }
        // Additive fill for keys older files miss (matches iOS migrated()).
        val base = defaults()
        var changed = false
        for (key in base.keys()) {
            if (!current.has(key)) {
                current.put(key, base.get(key))
                changed = true
            }
        }
        // v3 -> v4: the keyboard wears the website look. Anyone still on the
        // old default moves over; a deliberate pick (classic, glow) stays.
        if (current.optInt("schemaVersion", 1) < 4) {
            if (current.optString("keyTheme", "glass") == "glass") {
                current.put("keyTheme", "site")
            }
            val order = current.optJSONArray("toolbarOrder")
            if (order != null) {
                val kept = JSONArray()
                for (i in 0 until order.length()) {
                    val id = order.optString(i)
                    if (id != "settings") kept.put(id)
                }
                current.put("toolbarOrder", kept)
            }
            current.put("schemaVersion", 4)
            changed = true
        }
        // v5/v6: drop the canned glyf bindings; keep S, T and built glyfs.
        if (current.optInt("schemaVersion", 1) < 6) {
            val kept = JSONObject()
            val b = current.optJSONObject("bindings") ?: JSONObject()
            val built = current.optJSONObject("customTitles") ?: JSONObject()
            for (k in b.keys()) {
                val target = b.optString(k)
                if (target == "surface:vault" || target == "surface:translate-hud" ||
                    built.has(target)) {
                    kept.put(k, target)
                }
            }
            if (!kept.has("v") && !kept.has("s")) kept.put("v", "surface:vault")
            if (!kept.has("t")) kept.put("t", "surface:translate-hud")
            current.put("bindings", kept)
            current.put("schemaVersion", 6)
            changed = true
        }
        // v7: the strip matches iOS. Emoji left it (the bottom row has an emoji
        // key), unless someone hid it on purpose.
        if (current.optInt("schemaVersion", 1) < 7) {
            val hidden = current.optJSONArray("toolbarHidden")
            val emojiHidden = (0 until (hidden?.length() ?: 0)).any { hidden!!.optString(it) == "emoji" }
            if (!emojiHidden) {
                val order = current.optJSONArray("toolbarOrder") ?: JSONArray()
                val kept = JSONArray()
                for (i in 0 until order.length()) {
                    if (order.optString(i) != "emoji") kept.put(order.optString(i))
                }
                current.put("toolbarOrder", kept)
            }
            current.put("schemaVersion", 7)
            changed = true
        }
        // v8: the vault moves to V, the letter it is named for (as on iOS).
        if (current.optInt("schemaVersion", 1) < 8) {
            val b = current.optJSONObject("bindings") ?: JSONObject()
            if (b.optString("s") == "surface:vault" &&
                (!b.has("v") || b.optString("v") == "surface:vault")) {
                b.remove("s")
                b.put("v", "surface:vault")
            }
            val hasVault = b.keys().asSequence().any { b.optString(it) == "surface:vault" }
            if (!hasVault && !b.has("v")) b.put("v", "surface:vault")
            current.put("bindings", b)
            current.put("schemaVersion", 8)
            changed = true
        }
        // v8 → v9: every saved strip starts over once from the new default
        // (Calendar and Temp mail where Voice and Translate were).
        if (current.optInt("schemaVersion", 1) < 9) {
            current.put("toolbarOrder", JSONArray(DEFAULT_STRIP))
            current.put("toolbarHidden", JSONArray())
            current.put("schemaVersion", 9)
            changed = true
        }
        // Every load, as on iOS: Search leads the strip and the default tools
        // are all present (anyone can hide one; losing one is a bug).
        run {
            val order = current.optJSONArray("toolbarOrder") ?: JSONArray()
            val ids = (0 until order.length()).map { order.optString(it) }.toMutableList()
            val before = ids.toList()
            if ("search" !in ids) ids.add(0, "search")
            for (id in DEFAULT_STRIP) {
                if (id !in ids) ids.add(id)
            }
            if (ids != before) {
                current.put("toolbarOrder", JSONArray(ids))
                changed = true
            }
        }
        val fixed = productionized(current.optString("backendURL"))
        if (fixed != current.optString("backendURL")) {
            current.put("backendURL", fixed)
            changed = true
        }
        if (changed) Bridge.write(ctx, FILE, current.toString())
        return current
    }

    fun save(ctx: Context, json: String): Boolean = try {
        JSONObject(json) // validate
        Bridge.write(ctx, FILE, json)
    } catch (_: Exception) { false }
}

/** The user's recent searches, per tab — device-only.
 *
 *  Mirrors the iOS SearchRecents. Google publishes no API for a person's own
 *  Search history, and YouTube removed watch-history access from its Data API
 *  years ago, so "recent" can only ever mean "typed on this phone". */
object SearchRecents {
    const val FILE = "search-recents.json"
    const val MAX_PER_VERTICAL = 6

    fun list(ctx: Context, vertical: String): List<String> {
        val root = Bridge.readJson(ctx, FILE) ?: return emptyList()
        val arr = root.optJSONArray(vertical) ?: return emptyList()
        return (0 until arr.length()).map { arr.getString(it) }
    }

    fun record(ctx: Context, query: String, vertical: String) {
        val q = query.trim()
        if (q.length < 2) return
        val root = Bridge.readJson(ctx, FILE) ?: JSONObject()
        val existing = list(ctx, vertical)
            .filterNot { it.equals(q, ignoreCase = true) }
        val next = (listOf(q) + existing).take(MAX_PER_VERTICAL)
        root.put(vertical, JSONArray(next))
        Bridge.write(ctx, FILE, root.toString())
    }
}

object NotesStore {
    const val FILE = "notes.json"

    fun list(ctx: Context): JSONArray = try {
        val f = Bridge.file(ctx, FILE)
        if (f.exists()) JSONArray(f.readText()) else JSONArray()
    } catch (_: Exception) { JSONArray() }

    /** Returns an error string when refused (secrets never become notes). */
    fun upsert(ctx: Context, id: String?, text: String): String? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return "Write something first"
        if (trimmed.length > 2000) return "Notes max out at 2000 characters"
        SecretScanner.scan(trimmed)?.let { return it }
        val notes = list(ctx)
        val now = java.time.Instant.now().toString()
        var found = false
        for (i in 0 until notes.length()) {
            val n = notes.getJSONObject(i)
            if (n.optString("id") == id) {
                n.put("text", trimmed); n.put("updatedAt", now); found = true
            }
        }
        if (!found) {
            val fresh = JSONObject(mapOf(
                "id" to UUID.randomUUID().toString().lowercase(),
                "text" to trimmed, "updatedAt" to now))
            val rebuilt = JSONArray().put(fresh)
            for (i in 0 until notes.length()) rebuilt.put(notes.get(i))
            Bridge.write(ctx, FILE, rebuilt.toString())
            return null
        }
        Bridge.write(ctx, FILE, notes.toString())
        return null
    }

    fun delete(ctx: Context, id: String) {
        val notes = list(ctx)
        val kept = JSONArray()
        for (i in 0 until notes.length()) {
            val n = notes.getJSONObject(i)
            if (n.optString("id") != id) kept.put(n)
        }
        Bridge.write(ctx, FILE, kept.toString())
    }
}

/** §6.15 tone profile — same bucket counters as iOS. */
object ToneProfile {
    const val FILE = "tone-profile.json"

    fun load(ctx: Context): JSONObject =
        Bridge.readJson(ctx, FILE) ?: JSONObject(mapOf(
            "accepted" to JSONObject(), "discarded" to JSONObject()))

    fun reset(ctx: Context) {
        Bridge.write(ctx, FILE,
            JSONObject(mapOf("accepted" to JSONObject(),
                             "discarded" to JSONObject())).toString())
    }

    fun hint(counts: JSONObject): String {
        val accepted = counts.optJSONObject("accepted") ?: return ""
        val discarded = counts.optJSONObject("discarded") ?: JSONObject()
        var best: Pair<String, Int>? = null
        for (bucket in accepted.keys()) {
            val net = accepted.optInt(bucket) - discarded.optInt(bucket)
            if (net >= 3 && net > (best?.second ?: 0)) best = bucket to net
        }
        val phrase = when (best?.first) {
            "concise" -> "brief and to the point"
            "warm" -> "warm and personable"
            "formal" -> "polished and formal"
            "playful" -> "light and playful"
            else -> return ""
        }
        return "The user tends to prefer writing that is $phrase."
    }
}
