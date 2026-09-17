package com.demo.glyf

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.demo.glyf.store.Bridge
import com.demo.glyf.store.NotesStore
import com.demo.glyf.store.SettingsStore
import com.demo.glyf.store.ToneProfile
import com.demo.glyf.store.VaultStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Android side of the `so.glyf/bridge` MethodChannel — same method names
 * and payloads as the Swift GlyfBridge, so the Dart layer runs unchanged.
 */
class GlyfBridge(private val ctx: Context) : MethodChannel.MethodCallHandler {

    var channel: MethodChannel? = null
    var lastDeepLink: String? = null
    /** Debug-only test flags from the intent that started this launch. */
    var launchArgs: List<String> = emptyList()

    /** Set by MainActivity — asks for READ_CONTACTS, calls back with grant. */
    var requestContactsPermission: (((Boolean) -> Unit) -> Unit)? = null
    var requestLocationPermission: (((Boolean) -> Unit) -> Unit)? = null
    var requestCalendarPermission: (((Boolean) -> Unit) -> Unit)? = null
    var requestImagesPermission: (((Boolean) -> Unit) -> Unit)? = null

    /** One coarse fix, cached into shared settings for the keyboard.
     *
     *  Deliberately last-known-only: it is instant, costs no battery, and
     *  neighbourhood accuracy is all "coffee near me" needs. Coordinates are
     *  rounded to ~1km so the cache can never pinpoint a home. */
    @Suppress("MissingPermission")
    fun cacheLocation(): Map<String, Any> {
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
            ?: return mapOf("ok" to false, "error" to "unavailable")
        val best = try {
            lm.getProviders(true)
                .mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
                .maxByOrNull { it.time }
        } catch (_: SecurityException) { null }
            ?: return mapOf("ok" to false, "error" to "nofix")

        val lat = Math.round(best.latitude * 100.0) / 100.0
        val lon = Math.round(best.longitude * 100.0) / 100.0
        val s = SettingsStore.load(ctx)
        s.put("lastLat", lat)
        s.put("lastLon", lon)
        s.put("region", java.util.Locale.getDefault().country)
        SettingsStore.save(ctx, s.toString())
        return mapOf("ok" to true, "lat" to lat, "lon" to lon)
    }

    /** Minimal name/phones/emails index into bridge/contacts.json (≤2000). */
    fun syncContacts(): Map<String, Any> {
        val rows = org.json.JSONArray()
        val byContact = LinkedHashMap<String, Pair<MutableList<String>, MutableList<String>>>()
        val names = LinkedHashMap<String, String>()
        try {
            ctx.contentResolver.query(
                android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    android.provider.ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                    android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER,
                ), null, null, null)?.use { c ->
                while (c.moveToNext() && byContact.size < 2000) {
                    val id = c.getString(0) ?: continue
                    names[id] = c.getString(1) ?: continue
                    byContact.getOrPut(id) { mutableListOf<String>() to mutableListOf() }
                        .first.add(c.getString(2) ?: "")
                }
            }
            ctx.contentResolver.query(
                android.provider.ContactsContract.CommonDataKinds.Email.CONTENT_URI,
                arrayOf(
                    android.provider.ContactsContract.CommonDataKinds.Email.CONTACT_ID,
                    android.provider.ContactsContract.CommonDataKinds.Email.DISPLAY_NAME,
                    android.provider.ContactsContract.CommonDataKinds.Email.ADDRESS,
                ), null, null, null)?.use { c ->
                while (c.moveToNext() && byContact.size < 2000) {
                    val id = c.getString(0) ?: continue
                    if (names[id] == null) names[id] = c.getString(1) ?: continue
                    byContact.getOrPut(id) { mutableListOf<String>() to mutableListOf() }
                        .second.add(c.getString(2) ?: "")
                }
            }
        } catch (_: Exception) {
            return mapOf("ok" to false, "error" to "read failed")
        }
        for ((id, lists) in byContact) {
            val name = names[id]?.trim().orEmpty()
            if (name.isEmpty()) continue
            rows.put(JSONObject(mapOf(
                "name" to name,
                "phones" to org.json.JSONArray(lists.first.filter { it.isNotBlank() }),
                "emails" to org.json.JSONArray(lists.second.filter { it.isNotBlank() }),
            )))
        }
        return if (Bridge.write(ctx, "contacts.json", rows.toString()))
            mapOf("ok" to true, "count" to rows.length())
        else mapOf("ok" to false, "error" to "store failed")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "groupPath" -> result.success(Bridge.dir(ctx).absolutePath)
            "readKeyboardPing" ->
                result.success(Bridge.readJson(ctx, "keyboard-ping.json")?.toString())
            "writeAppPong" -> result.success(true)
            "lastDeepLink" -> {
                // Taken once: the app reads it at start for the link that launched it.
                result.success(lastDeepLink)
                lastDeepLink = null
            }

            "keyboardEnabled" -> {
                // Settings.Secure ENABLED_INPUT_METHODS is sealed off from
                // targetSdk 34+; InputMethodManager is the supported road.
                val imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                    as android.view.inputmethod.InputMethodManager
                result.success(imm.enabledInputMethodList
                    .any { it.packageName == ctx.packageName })
            }
            "openSettings" -> {
                ctx.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(true)
            }
            "keyboardSelected" -> {
                val selected = try {
                    if (android.os.Build.VERSION.SDK_INT >= 33) {
                        val imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                            as android.view.inputmethod.InputMethodManager
                        imm.currentInputMethodInfo?.packageName == ctx.packageName
                    } else {
                        Settings.Secure.getString(ctx.contentResolver,
                            Settings.Secure.DEFAULT_INPUT_METHOD)
                            ?.startsWith(ctx.packageName) == true
                    }
                } catch (_: Exception) { false }
                result.success(selected)
            }
            "showImePicker" -> {
                val imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                    as android.view.inputmethod.InputMethodManager
                imm.showInputMethodPicker()
                result.success(true)
            }
            "openURL" -> {
                val url = call.argument<String>("url")
                if (url != null && url.startsWith("https://")) {
                    ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } else result.success(false)
            }
            "documentsPath" -> result.success(ctx.filesDir.absolutePath)
            // Debug builds: test flags for this launch only, passed the way the
            // scenario runner starts the app (am start --esa glyfArgs ...), so a
            // flag can never outlive the run that set it.
            "launchArgs" -> result.success(if (BuildConfig.DEBUG) launchArgs else emptyList<String>())

            "readSharedSettings" -> result.success(SettingsStore.load(ctx).toString())
            "writeSharedSettings" -> {
                val json = call.argument<String>("json") ?: ""
                result.success(SettingsStore.save(ctx, json))
            }
            "readOnboardingState" ->
                result.success(Bridge.readJson(ctx, "onboarding.json")?.toString())
            "writeOnboardingState" -> {
                val json = call.argument<String>("json") ?: "{}"
                result.success(Bridge.write(ctx, "onboarding.json", json))
            }

            // Dictation: Android IMEs get voice typing from the system; the
            // in-app recorder ships in the Android M2 pass. Clean no-ops so
            // the Dart layer degrades gracefully.
            "dictationPending" -> result.success(null)
            "dictationConsume" -> result.success(false)
            "dictationStart" -> result.success(mapOf(
                "ok" to false, "fake" to false,
                "error" to "Dictation lands in the Android update"))
            "dictationStop" -> result.success(mapOf("transcript" to "", "latencyMs" to 0))
            "dictationCancel" -> result.success(true)
            "dictationResult" -> result.success(false)

            "vaultList" -> result.success(VaultStore.load(ctx).toString())
            "vaultUpsertField" -> {
                val err = VaultStore.upsertField(
                    ctx,
                    call.argument<String>("id"),
                    call.argument<String>("kind") ?: "custom",
                    call.argument<String>("label") ?: "",
                    call.argument<String>("value") ?: "")
                result.success(mapOf("ok" to (err == null), "error" to err))
            }
            "vaultDeleteField" -> {
                VaultStore.deleteField(ctx, call.argument<String>("id") ?: "")
                result.success(true)
            }
            "vaultUpsertCombo" -> {
                val err = VaultStore.upsertCombo(
                    ctx,
                    call.argument<String>("id"),
                    call.argument<String>("label") ?: "",
                    call.argument<List<String>>("fieldIds") ?: listOf())
                result.success(mapOf("ok" to (err == null), "error" to err))
            }
            "vaultDeleteCombo" -> {
                VaultStore.deleteCombo(ctx, call.argument<String>("id") ?: "")
                result.success(true)
            }
            "vaultUpsertSnippet" -> {
                val err = VaultStore.upsertSnippet(
                    ctx,
                    call.argument<String>("trigger") ?: "",
                    call.argument<String>("text") ?: "")
                result.success(mapOf("ok" to (err == null), "error" to err))
            }
            "vaultDeleteSnippet" -> {
                VaultStore.deleteSnippet(ctx, call.argument<String>("trigger") ?: "")
                result.success(true)
            }

            "notesList" -> result.success(NotesStore.list(ctx).toString())
            "notesUpsert" -> {
                val err = NotesStore.upsert(
                    ctx, call.argument<String>("id"),
                    call.argument<String>("text") ?: "")
                result.success(mapOf("ok" to (err == null), "error" to err))
            }
            "notesDelete" -> {
                NotesStore.delete(ctx, call.argument<String>("id") ?: "")
                result.success(true)
            }

            // Typing engine: learned words ("My words"), edits, AI-made packs.
            // The IME shares this process, so a loaded engine answers live.
            "typingWords" -> {
                val engine = com.demo.glyf.ime.typing.KeyboardTyping.engine
                val file = com.demo.glyf.ime.typing.KeyboardTyping.lexiconFile(ctx)
                result.success(engine?.personal?.toJson()?.toString()
                    ?: if (file.exists()) file.readText() else null)
            }
            "typingEdit" -> {
                val op = call.argument<String>("op")
                if (op !in setOf("add", "forget", "reset")) { result.success(false); return }
                val now = System.currentTimeMillis().toDouble()
                val edits = Bridge.readJson(ctx, "typing-edits.json")?.optJSONArray("edits") ?: org.json.JSONArray()
                val kept = org.json.JSONArray()
                val recent = (0 until edits.length()).mapNotNull { edits.optJSONObject(it) }
                    .filter { now - it.optDouble("at", 0.0) < 30 * 86_400_000.0 }.takeLast(400)
                recent.forEach { kept.put(it) }
                kept.put(JSONObject(mapOf("op" to op, "word" to (call.argument<String>("word") ?: ""), "at" to now)))
                val ok = Bridge.write(ctx, "typing-edits.json", JSONObject(mapOf("edits" to kept)).toString())
                com.demo.glyf.ime.typing.KeyboardTyping.applyAppEdits(ctx)
                result.success(ok)
            }
            "vocabCustomRead" -> result.success(Bridge.readJson(ctx, "vocab-custom.json")?.toString())
            "vocabCustomWrite" -> {
                val json = call.argument<String>("json") ?: "{}"
                val ok = Bridge.write(ctx, "vocab-custom.json", json)
                com.demo.glyf.ime.typing.KeyboardTyping.refreshPacks(ctx)
                result.success(ok)
            }
            "toneProfile" -> {
                val counts = ToneProfile.load(ctx)
                result.success(JSONObject(mapOf(
                    "accepted" to counts.optJSONObject("accepted"),
                    "discarded" to counts.optJSONObject("discarded"),
                    "hint" to ToneProfile.hint(counts))).toString())
            }
            "toneReset" -> {
                ToneProfile.reset(ctx)
                result.success(true)
            }

            // Contacts search (Gboard parity) — the app owns the runtime
            // permission; the IME only reads the synced local index.
            "contactsStatus" -> {
                val granted = ctx.checkSelfPermission(
                    android.Manifest.permission.READ_CONTACTS) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                val enabled = Bridge.file(ctx, "contacts.json").exists()
                result.success(JSONObject(mapOf(
                    "enabled" to enabled,
                    "permission" to if (granted) "granted" else "notDetermined",
                )).toString())
            }
            // The phone's calendar for the keyboard's Calendar panel. The
            // keyboard shares this app's permission, so nothing is copied.
            "calendarStatus" -> {
                val granted = ctx.checkSelfPermission(android.Manifest.permission.READ_CALENDAR) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                val on = ctx.getSharedPreferences("glyf", Context.MODE_PRIVATE).getBoolean("calendarOn", false)
                result.success(JSONObject(mapOf(
                    "enabled" to (granted && on),
                    "permission" to if (granted) "granted" else "denied",
                )).toString())
            }
            "calendarEnable" -> {
                val prefs = ctx.getSharedPreferences("glyf", Context.MODE_PRIVATE)
                val granted = ctx.checkSelfPermission(android.Manifest.permission.READ_CALENDAR) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                if (granted) {
                    prefs.edit().putBoolean("calendarOn", true).apply()
                    result.success(JSONObject(mapOf("ok" to true)).toString())
                } else {
                    val ask = requestCalendarPermission
                    if (ask == null) {
                        result.success(JSONObject(mapOf("ok" to false, "error" to "denied")).toString())
                    } else ask { ok ->
                        if (ok) prefs.edit().putBoolean("calendarOn", true).apply()
                        result.success(JSONObject(
                            if (ok) mapOf("ok" to true) else mapOf("ok" to false, "error" to "denied")
                        ).toString())
                    }
                }
            }
            "calendarDisable" -> {
                ctx.getSharedPreferences("glyf", Context.MODE_PRIVATE).edit().putBoolean("calendarOn", false).apply()
                result.success(true)
            }
            "contactsEnable" -> {
                val granted = ctx.checkSelfPermission(
                    android.Manifest.permission.READ_CONTACTS) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                if (granted) {
                    result.success(JSONObject(syncContacts()).toString())
                } else {
                    val ask = requestContactsPermission
                    if (ask == null) {
                        result.success(JSONObject(mapOf(
                            "ok" to false, "error" to "denied")).toString())
                    } else {
                        ask { ok ->
                            result.success(JSONObject(
                                if (ok) syncContacts()
                                else mapOf("ok" to false, "error" to "denied")
                            ).toString())
                        }
                    }
                }
            }
            // Screenshots in the clipboard (Gboard's setting): the app asks for
            // photo access; the keyboard only lists recent screenshots.
            "screenshotAccess" -> {
                if (ScreenshotAccess.granted(ctx)) {
                    result.success(true)
                } else {
                    val ask = requestImagesPermission
                    if (ask == null) result.success(false) else ask { ok -> result.success(ok) }
                }
            }
            "contactsDisable" -> {
                Bridge.file(ctx, "contacts.json").delete()
                result.success(true)
            }

            // "Near me" searches. The IME cannot hold a runtime permission of
            // its own, so the APP asks once and caches a COARSE fix in shared
            // settings; the keyboard only reads it and forwards it with place
            // searches. Nothing is stored server-side.
            "locationStatus" -> {
                val granted = ctx.checkSelfPermission(
                    android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                val s = SettingsStore.load(ctx)
                result.success(JSONObject(mapOf(
                    "enabled" to (s.has("lastLat") && s.has("lastLon")),
                    "permission" to if (granted) "granted" else "notDetermined",
                )).toString())
            }
            "locationEnable" -> {
                val granted = ctx.checkSelfPermission(
                    android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                if (granted) {
                    result.success(JSONObject(cacheLocation()).toString())
                } else {
                    val ask = requestLocationPermission
                    if (ask == null) {
                        result.success(JSONObject(mapOf(
                            "ok" to false, "error" to "denied")).toString())
                    } else {
                        ask { ok ->
                            result.success(JSONObject(
                                if (ok) cacheLocation()
                                else mapOf("ok" to false, "error" to "denied")
                            ).toString())
                        }
                    }
                }
            }
            "locationDisable" -> {
                val s = SettingsStore.load(ctx)
                s.remove("lastLat")
                s.remove("lastLon")
                SettingsStore.save(ctx, s.toString())
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }
}
