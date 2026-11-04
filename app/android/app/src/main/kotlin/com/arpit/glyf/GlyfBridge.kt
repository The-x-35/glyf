package com.arpit.glyf

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.arpit.glyf.store.Bridge
import com.arpit.glyf.store.NotesStore
import com.arpit.glyf.store.SettingsStore
import com.arpit.glyf.store.ToneProfile
import com.arpit.glyf.store.VaultStore
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
    /** The activity Google's sign-in sheet shows over; set by MainActivity. */
    var activity: android.app.Activity? = null

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
                // Android shows the picker only to the window being typed in
                // (the app focuses its practice box first), so the request
                // comes from the activity's own window, after its next frame.
                val a = activity
                val imm = (a ?: ctx).getSystemService(Context.INPUT_METHOD_SERVICE)
                    as android.view.inputmethod.InputMethodManager
                val show = Runnable { imm.showInputMethodPicker() }
                if (a != null) a.window.decorView.post(show) else show.run()
                result.success(true)
            }
            "openURL" -> {
                val url = call.argument<String>("url")
                if (url != null && url.startsWith("https://")) {
                    ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } else if (url != null && url.startsWith("solana:")) {
                    // A Solana Pay request (wallet/crypto_pay.dart), for
                    // whichever wallet takes it; false when none does.
                    try {
                        ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: android.content.ActivityNotFoundException) {
                        result.success(false)
                    }
                } else result.success(false)
            }
            // Phantom's links go to the Phantom app itself (phantom.app's own
            // app-link file isn't served there, so the package is named):
            // false when it isn't installed.
            "openPhantom" -> {
                val url = call.argument<String>("url")
                if (url == null || Uri.parse(url).host != "phantom.app") return result.success(false)
                try {
                    ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        .setPackage("app.phantom")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (_: android.content.ActivityNotFoundException) {
                    result.success(false)
                }
            }
            "walletSecretLoad" -> result.success(WalletSecrets.load(ctx, call.argument<String>("name") ?: ""))
            "walletSecretSave" -> result.success(WalletSecrets.save(ctx,
                call.argument<String>("name") ?: "", call.argument<String>("value") ?: ""))
            "walletSecretClear" -> {
                WalletSecrets.clear(ctx, call.argument<String>("name") ?: "")
                result.success(true)
            }
            "documentsPath" -> result.success(ctx.filesDir.absolutePath)
            // Debug builds: test flags for this launch only, passed the way the
            // scenario runner starts the app (am start --esa glyfArgs ...), so a
            // flag can never outlive the run that set it.
            "launchArgs" -> result.success(if (BuildConfig.DEBUG) launchArgs else emptyList<String>())

            // Signing in (SignIn.kt): the provider's ID token comes back for the
            // server to check; the Glyf session it returns is kept encrypted.
            "signInGoogle" -> {
                val a = activity
                if (a == null) {
                    result.success(mapOf("error" to "failed"))
                } else {
                    SignIn.google(a, call.argument<String>("clientId") ?: "",
                        call.argument<String>("nonce") ?: "") { result.success(it) }
                }
            }
            // Sign in with Apple is an iPhone button; Android offers Google.
            "signInApple" -> result.success(mapOf("error" to "apple_unavailable"))
            "signOutProviders" -> {
                // The keyboard's copy of that account's calendar goes too.
                com.arpit.glyf.ime.GoogleCache.clear(ctx)
                SignIn.signOut(ctx)
                // Signing out takes the Calendar and Meet grant with it.
                SignIn.disconnectGoogle(ctx) { result.success(true) }
            }
            // Google Calendar and Meet for the keyboard (GoogleAccess): Play
            // services holds the grant; the keyboard talks to Google itself.
            "googleStatus" -> result.success(SignIn.googleStatus(ctx))
            "googleConnect" -> {
                val a = activity
                if (a == null) result.success(mapOf("error" to "failed"))
                else SignIn.authorizeGoogle(a, call.argument<String>("loginHint")) { result.success(it) }
            }
            "googleDisconnect" -> SignIn.disconnectGoogle(ctx) { result.success(true) }
            "sessionLoad" -> result.success(SessionStore.load(ctx))
            "sessionSave" -> result.success(SessionStore.save(ctx, call.argument<String>("json") ?: ""))
            "sessionClear" -> {
                SessionStore.clear(ctx)
                result.success(true)
            }
            // Delete account, on the phone (below).
            "eraseLocalData" -> result.success(eraseLocalData())

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
                val engine = com.arpit.glyf.ime.typing.KeyboardTyping.engine
                val file = com.arpit.glyf.ime.typing.KeyboardTyping.lexiconFile(ctx)
                result.success(engine?.personal?.toJson()?.toString()
                    ?: if (file.exists()) file.readText() else null)
            }
            "typingEdit" -> {
                val op = call.argument<String>("op")
                if (op == null || op !in setOf("add", "forget", "reset")) { result.success(false); return }
                result.success(appendTypingEdit(op, call.argument<String>("word") ?: ""))
            }
            "vocabCustomRead" -> result.success(Bridge.readJson(ctx, "vocab-custom.json")?.toString())
            "vocabCustomWrite" -> {
                val json = call.argument<String>("json") ?: "{}"
                val ok = Bridge.write(ctx, "vocab-custom.json", json)
                com.arpit.glyf.ime.typing.KeyboardTyping.refreshPacks(ctx)
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
                // Allowed means on: the calendar is asked for during onboarding.
                result.success(JSONObject(mapOf(
                    "enabled" to granted,
                    "permission" to if (granted) "granted" else "denied",
                )).toString())
            }
            "calendarEnable" -> {
                val prefs = ctx.getSharedPreferences("glyf", Context.MODE_PRIVATE)
                // Both halves: an install from before New Event has only read.
                val granted = listOf(android.Manifest.permission.READ_CALENDAR,
                    android.Manifest.permission.WRITE_CALENDAR).all {
                    ctx.checkSelfPermission(it) == android.content.pm.PackageManager.PERMISSION_GRANTED
                }
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

    /** Adds to the edit log the keyboard replays (KeyboardTyping.applyAppEdits)
     *  and applies it now: the keyboard runs in this process. Entries older
     *  than a month, or past the last 400, are dropped. */
    private fun appendTypingEdit(op: String, word: String): Boolean {
        val now = System.currentTimeMillis().toDouble()
        val edits = Bridge.readJson(ctx, "typing-edits.json")?.optJSONArray("edits") ?: JSONArray()
        val kept = JSONArray()
        val recent = (0 until edits.length()).mapNotNull { edits.optJSONObject(it) }
            .filter { now - it.optDouble("at", 0.0) < 30 * 86_400_000.0 }.takeLast(400)
        recent.forEach { kept.put(it) }
        kept.put(JSONObject(mapOf("op" to op, "word" to word, "at" to now)))
        val ok = Bridge.write(ctx, "typing-edits.json", JSONObject(mapOf("edits" to kept)).toString())
        com.arpit.glyf.ime.typing.KeyboardTyping.applyAppEdits(ctx)
        return ok
    }

    /** Delete account's last step, after the server has deleted the account
     *  (the twin of eraseLocalData in GlyfBridge.swift). App and keyboard are
     *  one package here, so this reaches both:
     *
     *  - files/ (bridge/: settings, onboarding, vault, notes, learned words,
     *    phrases, contacts index, voice and funnel files; the telemetry
     *    log), no_backup/ (the sealed session) and the cache;
     *  - every SharedPreferences file (clipboard history, temp mail, the
     *    keyboard's own), cleared through the API so the copies this process
     *    holds in memory forget too;
     *  - every Android Keystore key the app made (session, vault, wallet);
     *  - the learned words a running keyboard holds in memory, by the same
     *    "reset" edit Vocabulary's Reset uses.
     *
     *  False when something could not be removed. */
    private fun eraseLocalData(): Boolean {
        var ok = true
        fun empty(dir: java.io.File?) {
            dir?.listFiles()?.forEach { if (!it.deleteRecursively()) ok = false }
        }
        empty(ctx.filesDir)
        empty(ctx.noBackupFilesDir)
        empty(ctx.cacheDir)
        ctx.databaseList().forEach { ctx.deleteDatabase(it) }
        java.io.File(ctx.applicationInfo.dataDir, "shared_prefs").listFiles()?.forEach { f ->
            if (f.name.endsWith(".xml")) {
                val name = f.name.removeSuffix(".xml")
                if (!ctx.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().commit()) ok = false
            }
        }
        try {
            val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            ks.aliases().toList().forEach { ks.deleteEntry(it) }
        } catch (_: Exception) {
            ok = false
        }
        com.arpit.glyf.store.Funnel.forget()
        if (!appendTypingEdit("reset", "")) ok = false
        return ok
    }
}
