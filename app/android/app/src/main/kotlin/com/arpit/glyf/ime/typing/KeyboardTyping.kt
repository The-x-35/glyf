package com.arpit.glyf.ime.typing

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.arpit.glyf.store.Bridge
import com.arpit.glyf.store.SettingsStore
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * Everything the typing engine knows on this phone, loaded once per keyboard
 * process and saved as it learns (Android mirror of TypingStore.swift):
 *  · the base dictionary, copied out of the APK once and memory-mapped
 *  · the vocabulary packs switched on in the app
 *  · what this person types — in noBackupFilesDir, so it never reaches a
 *    cloud backup, and never leaves the device
 *  · contact names the app synced for search (bridge/contacts.json)
 */
object KeyboardTyping {
    private const val DICTIONARY_ASSET = "en.glyd"
    private const val PACKS_ASSET = "flutter_assets/assets/vocab/packs.json"
    const val LEXICON_FILE = "typing-memory.json"
    const val EDITS_FILE = "typing-edits.json"
    private const val CUSTOM_PACKS_FILE = "vocab-custom.json"

    @Volatile var engine: TypingEngine? = null
        private set
    private var loading = false
    private val waiting = ArrayList<(TypingEngine) -> Unit>()
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var packSignature = ""
    private var saveQueued = false

    fun lexiconFile(ctx: Context): File = File(File(ctx.noBackupFilesDir, "typing").apply { mkdirs() }, LEXICON_FILE)

    /** Calls [ready] on the main thread once the engine exists. */
    fun prepare(ctx: Context, ready: (TypingEngine) -> Unit) {
        val app = ctx.applicationContext
        engine?.let {
            refreshPacks(app)
            refreshContacts(app)
            applyAppEdits(app)
            ready(it)
            return
        }
        waiting.add(ready)
        if (loading) return
        loading = true
        io.execute {
            val base = try { dictionaryFile(app)?.let { GlydTrie.mapped(it) } } catch (_: Exception) { null }
            val personal = try {
                val f = lexiconFile(app)
                if (f.exists()) PersonalLexicon.fromJson(JSONObject(f.readText())) else PersonalLexicon()
            } catch (_: Exception) { PersonalLexicon() }
            personal.expire(TypingText.day())
            main.post {
                val e = TypingEngine(base, personal)
                engine = e
                loading = false
                refreshPacks(app)
                refreshContacts(app)
                applyAppEdits(app)
                val callbacks = ArrayList(waiting)
                waiting.clear()
                callbacks.forEach { it(e) }
            }
        }
    }

    /** APK assets are compressed; copy the dictionary out once (per app
     *  version) so it can be memory-mapped. */
    private fun dictionaryFile(ctx: Context): File? {
        val dir = File(ctx.noBackupFilesDir, "typing").apply { mkdirs() }
        val version = try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).lastUpdateTime
        } catch (_: Exception) { 0L }
        val out = File(dir, "en-$version.glyd")
        if (!out.exists()) {
            dir.listFiles { f -> f.name.endsWith(".glyd") }?.forEach { it.delete() }
            try {
                ctx.assets.open(DICTIONARY_ASSET).use { input -> out.outputStream().use { input.copyTo(it) } }
            } catch (_: Exception) {
                out.delete()
                return null
            }
        }
        return out
    }

    fun refreshPacks(ctx: Context) {
        val e = engine ?: return
        val settings = SettingsStore.load(ctx)
        val enabled = settings.optJSONArray("vocabPacks")?.let { a -> (0 until a.length()).map { a.getString(it) } }
            ?: defaultPacks()
        val custom = Bridge.readJson(ctx, CUSTOM_PACKS_FILE)
        val signature = enabled.joinToString(",") + "|" + (custom?.optDouble("updatedAt", 0.0) ?: 0.0)
        if (signature == packSignature) return
        packSignature = signature
        val ids = enabled.toHashSet()
        val words = ArrayList<String>()
        val phrases = ArrayList<String>()
        val packs = ArrayList<JSONObject>()
        try {
            val root = JSONObject(ctx.assets.open(PACKS_ASSET).bufferedReader().use { it.readText() })
            root.optJSONArray("packs")?.let { a -> for (i in 0 until a.length()) packs.add(a.getJSONObject(i)) }
        } catch (_: Exception) { }
        custom?.optJSONArray("packs")?.let { a -> for (i in 0 until a.length()) packs.add(a.getJSONObject(i)) }
        for (pack in packs) {
            if (pack.optString("id") !in ids) continue
            pack.optJSONArray("words")?.let { a ->
                for (i in 0 until a.length()) {
                    val entry = a.getString(i)
                    words.addAll(entry.split(' ').filter { it.isNotEmpty() })
                    if (entry.contains(' ')) phrases.add(entry)
                }
            }
            pack.optJSONArray("phrases")?.let { a ->
                for (i in 0 until a.length()) {
                    val phrase = a.getString(i)
                    words.addAll(phrase.split(' ').filter { it.isNotEmpty() })
                    phrases.add(phrase)
                }
            }
        }
        e.setPackWords(words)
        e.setPackPhrases(phrases)
    }

    /** Before anyone picks packs: Hinglish for phones set to India, where
     *  "yaar" and "kal" are words, not typos (same rule on iOS and in the app). */
    fun defaultPacks(country: String = java.util.Locale.getDefault().country): List<String> =
        if (country == "IN") listOf("local.hinglish") else emptyList()

    private var contactsStamp = -1L

    private fun refreshContacts(ctx: Context) {
        val e = engine ?: return
        val file = Bridge.file(ctx, "contacts.json")
        val stamp = if (file.exists()) file.lastModified() else 0L
        if (stamp == contactsStamp) return
        contactsStamp = stamp
        val names = ArrayList<String>()
        try {
            // GlyfBridge.syncContacts writes a bare array of {name, phones, emails}.
            val arr = org.json.JSONArray(file.readText())
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.optString("name")?.split(' ')?.filter { it.isNotEmpty() }?.let(names::addAll)
            }
        } catch (_: Exception) { }
        e.setContacts(names)
    }

    /** "My words" edits from the app, applied once each (the record lives in
     *  the lexicon file itself). */
    fun applyAppEdits(ctx: Context) {
        val e = engine ?: return
        val edits = Bridge.readJson(ctx, EDITS_FILE)?.optJSONArray("edits") ?: return
        val applied = e.personal.editsAppliedAt
        var latest = applied
        val list = (0 until edits.length()).mapNotNull { edits.optJSONObject(it) }.sortedBy { it.optDouble("at", 0.0) }
        for (edit in list) {
            val at = edit.optDouble("at", 0.0)
            if (at <= applied) continue
            val word = edit.optString("word")
            when (edit.optString("op")) {
                "add" -> e.add(word)
                "forget" -> e.forget(word)
                "reset" -> e.replacePersonal(PersonalLexicon())
            }
            latest = maxOf(latest, at)
        }
        if (latest > applied) {
            e.markEditsApplied(latest)
            scheduleSave(ctx)
        }
    }

    fun scheduleSave(ctx: Context) {
        if (saveQueued) return
        saveQueued = true
        val app = ctx.applicationContext
        main.postDelayed({ saveQueued = false; saveNow(app) }, 2_000)
    }

    fun saveNow(ctx: Context) {
        val e = engine ?: return
        val json = e.personal.toJson().toString()
        val file = lexiconFile(ctx.applicationContext)
        io.execute {
            try {
                val tmp = File(file.parentFile, "$LEXICON_FILE.tmp")
                tmp.writeText(json)
                tmp.renameTo(file)
            } catch (_: Exception) { }
        }
    }
}
