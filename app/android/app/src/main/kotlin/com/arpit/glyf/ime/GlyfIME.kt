package com.arpit.glyf.ime

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.arpit.glyf.MainActivity
import com.arpit.glyf.store.Bridge
import com.arpit.glyf.store.SettingsStore
import com.arpit.glyf.store.VaultStore
import com.arpit.glyf.ime.typing.KeyboardTyping
import com.arpit.glyf.ime.typing.TypingEngine
import com.arpit.glyf.ime.typing.WordContext
import org.json.JSONObject
import kotlin.math.abs

/** How much text before the cursor a correction's anchor holds. */
private const val ANCHOR_CHARS = 64

/** The label a detail set aside by the debug "stash" tool carries. */
private const val STASHED = "qa-stash:"

/** The strip's height, in dp. Gboard's is 47; ours is 50, so a strip chip
 *  stands 38dp tall with room for its glow above and below (Arpit,
 *  2026-09-30: "text seems too close to border"). Whatever takes the
 *  strip's place (the Glyf bar, translate, the act panel's head) matches
 *  it, so nothing jumps. */
private const val STRIP_DP = 50

/**
 * Glyf for Android — the native IME (SPEC §1: keyboards are native per
 * platform; Flutter never runs in here). M-Android-1 slice: full typing
 * with the shared design language, field-aware autocap and layouts,
 * ;shorthand, bound-key long-press → run → Replace/Insert preview.
 */
class GlyfIME : InputMethodService(), GlyfKeyboardView.Listener {

    private lateinit var root: LinearLayout
    private lateinit var toolbar: LinearLayout
    private lateinit var keyboard: GlyfKeyboardView
    private var overlay: FrameLayout? = null
    private val main = Handler(Looper.getMainLooper())

    private var settings = JSONObject()
    private var autoShifted = false
    private var lastSpaceAt = 0L

    // Typing: suggestions, autocorrect, next word, learning (ime/typing)
    private lateinit var toolIcons: LinearLayout
    private lateinit var suggestionRow: LinearLayout
    private var suggestionsShown = emptyList<Suggestion>()
    private var toolsPinned = false
    private data class Suggestion(val text: String, val kind: Kind) {
        enum class Kind { LITERAL, CORRECTION, WORD, UNDO, FILL, EMOJI }
    }
    /** [anchor] is the text before the cursor right after the correction and
     *  its space went in: undo works from exactly there (iOS twin). [tail] is
     *  what came after the fix there: its space, or the punctuation that made
     *  the fix and then a space (WordContext.undoTail). */
    private data class Correction(val original: String, val replacement: String, val fromEngine: Boolean,
                                  var anchor: String? = null, var tail: String = "")
    private var lastCorrection: Correction? = null

    /** Engine corrections of the last few minutes. Going back into one and
     *  typing the original again is a "no": the word stays as typed and is
     *  learned ("cutee" became "cute", was deleted and typed again, and
     *  became "cute" every time). A typo typed twice ("teh") is still fixed:
     *  its correction was never gone back into. iOS: recentFixes. */
    private class RecentFix(val original: String, val replacement: String, val at: Long, var touched: Boolean = false)
    private val recentFixes = mutableListOf<RecentFix>()

    /** The last correction, while the cursor is still right after it and its
     *  space. Otherwise a backspace that later reaches the same word in other
     *  text ("free" in a pasted line) would swap it back. */
    private fun undoableCorrection(before: String): Correction? {
        val corr = lastCorrection ?: return null
        val anchor = corr.anchor ?: return null
        // Callers read different lengths before the cursor; compare the
        // stretch the anchor holds.
        return corr.takeIf {
            before.takeLast(ANCHOR_CHARS) == anchor && corr.tail.isNotEmpty() && before.endsWith(corr.replacement + corr.tail)
        }
    }

    /** [c] just went in after a word: a correction it made is undoable from
     *  here, and one it follows ([extending], undoable just before it) moves
     *  its anchor here while what came after the fix is only marks and one
     *  space (iOS anchorCorrection). */
    private fun anchorCorrection(ic: android.view.inputmethod.InputConnection, c: Char, extending: Correction?) {
        val corr = lastCorrection ?: return
        if (corr.anchor == null) {
            corr.anchor = anchorHere(ic)
            corr.tail = c.toString()
        } else if (extending === corr) {
            WordContext.undoTail(corr.tail, c)?.let { tail ->
                corr.anchor = anchorHere(ic)
                corr.tail = tail
            }
        }
    }

    /** An undone engine correction is never offered for that word again, and
     *  the word is kept (the "retype teaches" logic, PersonalLexicon.revert). */
    private fun teachUndo(corr: Correction) {
        if (!corr.fromEngine || typingPolicy() and TypingEngine.LEARNING == 0) return
        KeyboardTyping.engine?.revert(corr.original, corr.replacement)
        KeyboardTyping.scheduleSave(this)
    }
    private fun anchorHere(ic: android.view.inputmethod.InputConnection): String? =
        ic.getTextBeforeCursor(ANCHOR_CHARS, 0)?.toString()
    /** Where each letter of the word being typed was touched. */
    private val wordTouches = ArrayList<FloatArray?>()
    private var wordTouchesFor = ""

    // Search suite (Gboard parity) state
    private var searchActive = false
    private var searchTab = "web"
    private var searchQuery = ""
    private var searchStrip: FrameLayout? = null
    private var searchResults: LinearLayout? = null
    private var searchResultCount = 0
    private var searchQueryView: InlineField? = null
    private var searchStatusView: TextView? = null
    /** The tab track's thumb and tabs, and ABC (shown with results). */
    private var searchThumb: View? = null
    private var searchTabs: List<Pair<String, ToolIcon>> = emptyList()
    private var searchAbc: TextView? = null
    /// Suggestions shown while the KEYS STAY VISIBLE — you must be able to
    /// start typing over a suggestion, so this is a separate slot from
    /// `searchResults`, which does replace the keys.
    private var searchLanding: LinearLayout? = null
    /** The row under the search strip that holds the suggestion chips. It
     *  keeps its height with or without chips, and results take its place and
     *  the keys', so the keyboard never changes size while you search. */
    private var searchChipsRow: FrameLayout? = null
    private var searchChipsScroll: android.widget.HorizontalScrollView? = null

    // MARK: lifecycle

    override fun onCreate() {
        // A plan chip says when the phone's calendar already has something then.
        EventParse.busyNote = { plan ->
            if (!CalendarText.connected(this)) null
            else EventParse.busyNote(plan, CalendarText.load(this, plan.start, plan.end))
        }
        super.onCreate()
        // The server turns away anyone without a session; the keyboard reads
        // the app's and sends it with every call.
        com.arpit.glyf.ime.BackendClient.bearer = com.arpit.glyf.SessionStore.token(this)
        RatesStore.attach(filesDir)
        KeyboardTyping.prepare(this) { }
        (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager)
            .addPrimaryClipChangedListener(clipListener)
        if (com.arpit.glyf.BuildConfig.DEBUG) {
            // Debug builds take commands by broadcast, for the scenario runner:
            //   adb shell am broadcast -a com.arpit.glyf.DEBUG_TOOL --es id menu
            //   adb shell am broadcast -a com.arpit.glyf.DEBUG_TOOL --es id dump
            val filter = android.content.IntentFilter("com.arpit.glyf.DEBUG_TOOL")
            // Only a sender holding DUMP (adb shell has it, apps don't) gets in.
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                registerReceiver(debugTool, filter, "android.permission.DUMP", null, RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(debugTool, filter, "android.permission.DUMP", null)
            }
        }
    }

    private val debugTool = object : android.content.BroadcastReceiver() {
        override fun onReceive(c: android.content.Context, intent: Intent) {
            if (!::keyboard.isInitialized) return
            when (val id = intent.getStringExtra("id") ?: return) {
                "menu" -> showMenuGrid()
                "copy" -> {
                    val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    cm.setPrimaryClip(android.content.ClipData.newPlainText("",
                        intent.getStringExtra("text") ?: ""))
                }
                // Everything on top of the keys: a hold-space panel too, or
                // it stays open under keys that came back and takes the
                // next scenario's result.
                // Translate as you type too: left on, it keeps every strip
                // chip away from the scenarios after it.
                // Everything back to the letters, as a new field gets it: a
                // search left open under the keys took the next scenario's
                // typing into its old query ("coffee near mecoffee").
                "close" -> {
                    dismissOverlay()
                    dismissFeaturePanel()
                    if (searchActive) exitSearch()
                    if (barActive) exitBar()
                    if (vaultEditActive) exitVaultEdit()
                    if (translateStrip != null) exitTranslate()
                    endDictation(null)
                }
                "dump" -> writeQaState()
                // "typewriter:dark" wears a theme in light or dark (":auto"
                // follows the phone); "" goes back to today's look. Applied
                // to the next field, as a setting from the app is.
                "skin" -> {
                    val pair = intent.getStringExtra("text").orEmpty().split(":", limit = 2)
                    val s = SettingsStore.load(this@GlyfIME)
                    s.put("skin", pair[0])
                    if (pair.size == 2) s.put("appearance", pair[1])
                    com.arpit.glyf.store.Bridge.write(this@GlyfIME, SettingsStore.FILE, s.toString())
                    settings = s
                }
                "seedvault" -> {
                    // The scenarios ask for an address and a wallet address:
                    // add whichever the vault doesn't have, and touch nothing else.
                    val kinds = Smart.fields(VaultStore.load(this@GlyfIME)).map { it.kind }.toSet()
                    if ("address" !in kinds) VaultStore.upsertField(this@GlyfIME, null, "address", "Home",
                        "123 Market St, San Francisco, CA 94103")
                    if ("wallet" !in kinds) VaultStore.upsertField(this@GlyfIME, null, "wallet", "Wallet address",
                        "4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA")
                }
                // ";qa=See you soon" keeps a shorthand; ";qa=" lets it go.
                "snippet" -> {
                    val pair = intent.getStringExtra("text").orEmpty().split("=", limit = 2)
                    if (pair.size == 2) {
                        if (pair[1].isEmpty()) VaultStore.deleteSnippet(this@GlyfIME, pair[0])
                        else VaultStore.upsertSnippet(this@GlyfIME, pair[0], pair[1])
                    }
                }
                // Every detail of one kind set aside, for a scenario that
                // needs the vault without one (the email added from the keys
                // must be the one offered), then put back by "unstash". They
                // stay in the vault, as Other under a marked label, so a
                // crash in between loses nothing and nothing moves.
                "stash" -> {
                    val kind = intent.getStringExtra("text").orEmpty()
                    val fields = VaultStore.load(this@GlyfIME).optJSONArray("fields") ?: org.json.JSONArray()
                    for (i in 0 until fields.length()) {
                        val f = fields.getJSONObject(i)
                        if (kind.isEmpty() || f.optString("kind") != kind) continue
                        VaultStore.upsertField(this@GlyfIME, f.optString("id"), "custom",
                            "$STASHED$kind:${f.optString("label")}", f.optString("value"))
                    }
                }
                "unstash" -> {
                    val fields = VaultStore.load(this@GlyfIME).optJSONArray("fields") ?: org.json.JSONArray()
                    for (i in 0 until fields.length()) {
                        val f = fields.getJSONObject(i)
                        val marked = f.optString("label").takeIf { it.startsWith(STASHED) } ?: continue
                        val (kind, label) = marked.removePrefix(STASHED).split(":", limit = 2)
                            .let { it[0] to it.getOrElse(1) { "" } }
                        VaultStore.upsertField(this@GlyfIME, f.optString("id"), kind, label, f.optString("value"))
                    }
                }
                // The temp address forgotten on this phone (the scenarios end
                // with the address deleted; this is for a run cut short).
                "tempmailclear" -> {
                    TempMailStore.clear(this@GlyfIME)
                    tempMails = emptyList()
                    main.removeCallbacks(tempTick)
                }
                // Screenshot runs: the phone's clipboard (the Mac's, on the
                // emulator) is not filed while "on", so only the seeded
                // copies show; "off" files again.
                "cliphold" -> qaClipHeld = intent.getStringExtra("text") != "off"
                // Screenshot runs: the vault made from files/qa/vault-seed.json
                // ({"fields":[{kind,label,value}],"snippets":[{trigger,text}]}).
                // The runner keeps the real vault's file and puts it back.
                "qavaultseed" -> {
                    val seed = runCatching {
                        JSONObject(java.io.File(filesDir, "qa/vault-seed.json").readText())
                    }.getOrNull() ?: return
                    com.arpit.glyf.store.Bridge.file(this@GlyfIME, "vault.enc").delete()
                    val fields = seed.optJSONArray("fields") ?: org.json.JSONArray()
                    for (i in 0 until fields.length()) {
                        val f = fields.getJSONObject(i)
                        VaultStore.upsertField(this@GlyfIME, null, f.optString("kind"),
                            f.optString("label"), f.optString("value"))
                    }
                    val snippets = seed.optJSONArray("snippets") ?: org.json.JSONArray()
                    for (i in 0 until snippets.length()) {
                        val sn = snippets.getJSONObject(i)
                        VaultStore.upsertSnippet(this@GlyfIME, sn.optString("trigger"), sn.optString("text"))
                    }
                    vaultFieldsStamp = -1L
                }
                // A token mail.tm no longer takes, so the next look re-takes
                // one with the stored password (RULES.md's 401).
                "tempmailbadtoken" -> TempMailStore.load(this@GlyfIME)?.let {
                    TempMailStore.save(this@GlyfIME, it.copy(token = "expired"))
                }
                // A detail a scenario needs, as "kind|label|value" (two
                // emails for the details chip); "dropdetail" takes it away.
                "adddetail" -> {
                    val parts = intent.getStringExtra("text").orEmpty().split("|", limit = 3)
                    if (parts.size == 3) VaultStore.addField(this@GlyfIME, parts[0], parts[1], parts[2])
                }
                // A detail a scenario added, gone again (by its value).
                "dropdetail" -> {
                    val value = intent.getStringExtra("text").orEmpty()
                    val fields = VaultStore.load(this@GlyfIME).optJSONArray("fields") ?: org.json.JSONArray()
                    for (i in 0 until fields.length()) {
                        val f = fields.getJSONObject(i)
                        if (value.isNotEmpty() && f.optString("value") == value) {
                            VaultStore.deleteField(this@GlyfIME, f.optString("id"))
                        }
                    }
                }
                // What Connected tools → Calendar sets, for the scenarios.
                "calendaron" -> this@GlyfIME.getSharedPreferences("glyf", android.content.Context.MODE_PRIVATE).edit()
                    .putBoolean("calendarOn", true).apply()
                // Google Calendar and Meet as if connected, pointed at the
                // stand-in for Google's APIs (qa/fake-google.mjs); no text
                // disconnects.
                "googlefake" -> {
                    val base = intent.getStringExtra("text").orEmpty()
                    // "--es scopes meet" grants Meet alone (Calendar unticked).
                    val scopes = when (intent.getStringExtra("scopes")) {
                        "meet" -> setOf(com.arpit.glyf.store.GoogleAccess.MEET)
                        "calendar" -> setOf(com.arpit.glyf.store.GoogleAccess.CALENDAR)
                        else -> com.arpit.glyf.store.GoogleAccess.SCOPES.toSet()
                    }
                    if (base.isEmpty()) com.arpit.glyf.store.GoogleAccess.clear(this@GlyfIME)
                    else com.arpit.glyf.store.GoogleAccess.save(this@GlyfIME, com.arpit.glyf.store.GoogleAccess.Grant(
                        "emulator@example.com", scopes, base))
                }
                // "m=connector:meet" holds M for a Meet link; "m=" frees it.
                "bind" -> {
                    val pair = intent.getStringExtra("text").orEmpty().split("=", limit = 2)
                    if (pair.size == 2 && pair[0].length == 1) {
                        val s = SettingsStore.load(this@GlyfIME)
                        val b = s.optJSONObject("bindings") ?: org.json.JSONObject()
                        if (pair[1].isEmpty()) b.remove(pair[0]) else b.put(pair[0], pair[1])
                        s.put("bindings", b)
                        com.arpit.glyf.store.Bridge.write(this@GlyfIME, SettingsStore.FILE, s.toString())
                        settings = s
                        keyboard.bindings = b.keys().asSequence().associateWith { b.optString(it) }
                    }
                }
                // What Connected tools → Booking link sets ("" clears it).
                "bookinglink" -> {
                    val s = SettingsStore.load(this@GlyfIME)
                    val link = intent.getStringExtra("text").orEmpty()
                    if (link.isEmpty()) s.remove("bookingLink") else s.put("bookingLink", link)
                    com.arpit.glyf.store.Bridge.write(this@GlyfIME, SettingsStore.FILE, s.toString())
                    settings = s
                }
                "clear" -> currentInputConnection?.let { ic ->
                    ic.finishComposingText()
                    val before = ic.getTextBeforeCursor(10000, 0)?.length ?: 0
                    val after = ic.getTextAfterCursor(10000, 0)?.length ?: 0
                    ic.deleteSurroundingText(before, after)
                    updateSuggestions()
                }
                // A word the typing engine learned, forgotten and not blocked,
                // so a scenario about learning it starts clean every run.
                "forgetword" -> KeyboardTyping.engine?.let { e ->
                    val word = intent.getStringExtra("text").orEmpty()
                    if (word.isNotEmpty()) {
                        e.forget(word)
                        e.personal.unblock(word)
                        KeyboardTyping.scheduleSave(this@GlyfIME)
                    }
                }
                // The strip policy's memory (docs/STRIP-POLICY.md) wiped, so
                // one scenario's ✕ never rests a chip the next one checks.
                "policyreset" -> {
                    stripPolicy.enter("")
                    imePrefs.edit().remove("stripPolicy").apply()
                }
                "delwords" -> {
                    val n = intent.getIntExtra("count", 1)
                    onDeleteWordsPreview(n)
                    main.postDelayed({ onDeleteWordsCommit(n) }, 600)
                }
                // Voice typing with stand-in words, for an emulator with no
                // speech service: the strip listens, the words stream in, they
                // go into the field and Polish is offered. "" hears nothing.
                //   am broadcast -a com.arpit.glyf.DEBUG_TOOL --es id voicefake --es text "see you at 5 period"
                "voicefake" -> { dismissFeaturePanel(); startDictation(intent.getStringExtra("text").orEmpty()) }
                // Done, as tapped.
                "voicestop" -> dictation?.stop()
                else -> openTool(id)
            }
        }
    }

    /** Debug builds: what is on the keyboard right now, for the scenario
     *  runner (qa/android-scenarios.mjs) to find things to tap and check what
     *  happened. Keys come from the canvas; everything else from the views. */
    private fun writeQaState() {
        val out = org.json.JSONObject()
        // When it was written: a runner reading an older file knows this
        // keyboard didn't answer (another keyboard is active, or it crashed).
        out.put("at", System.currentTimeMillis())
        val keys = org.json.JSONObject()
        if (keyboard.isShown) {
            for ((id, xy) in keyboard.keyCenters()) keys.put(id, org.json.JSONArray(listOf(xy[0], xy[1])))
        }
        out.put("keys", keys)
        // Each key's rectangle in the view, so a run can check that a theme
        // moved none of them (THEMES.md §8.3).
        val rects = org.json.JSONObject()
        if (keyboard.isShown) for ((id, r) in keyboard.keyBounds())
            rects.put(id, org.json.JSONArray(listOf(r.left, r.top, r.right, r.bottom)))
        out.put("keyRects", rects)
        out.put("shifted", keyboard.shifted)
        out.put("mode", keyboard.mode.name)
        val views = org.json.JSONArray()
        fun walk(v: View) {
            if (!v.isShown) return
            val qaId = v.getTag(com.arpit.glyf.R.id.qa_id) as? String
            val label = qaId ?: v.contentDescription?.toString()
                ?: (v as? TextView)?.text?.toString()?.takeIf { it.isNotBlank() }
            if (label != null && v !== keyboard) {
                val loc = IntArray(2).also { v.getLocationOnScreen(it) }
                views.put(org.json.JSONObject()
                    .put("id", qaId ?: v.contentDescription?.toString() ?: "")
                    .put("text", (v as? TextView)?.text?.toString() ?: "")
                    .put("desc", v.contentDescription?.toString() ?: "")
                    .put("x", loc[0] + v.width / 2).put("y", loc[1] + v.height / 2)
                    .put("w", v.width).put("h", v.height)
                    // Which of a row of tabs is the one showing.
                    .put("selected", v.isSelected))
            }
            if (v is android.view.ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        if (::root.isInitialized) walk(root)
        out.put("views", views)
        val ic = currentInputConnection
        val before = ic?.getTextBeforeCursor(4000, 0)?.toString() ?: ""
        val after = ic?.getTextAfterCursor(4000, 0)?.toString() ?: ""
        out.put("text", before + after)
        out.put("cursor", before.length)
        val clip = (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager).primaryClipDescription
        out.put("clipMime", clip?.takeIf { it.mimeTypeCount > 0 }?.getMimeType(0) ?: "")
        // The notice over the keys lives on the overlay, outside the views above.
        out.put("notice", (noticeView as? TextView)?.text?.toString() ?: "")
        // Strip chips whose colours are turning: none once the keyboard is hidden.
        out.put("glowTurning", MagicChip.turning)
        // Temp mail looks so far, and the current run of turned-away ones.
        out.put("tempLooks", tempLooks)
        out.put("tempFails", tempFails)
        out.put("glowTicks", MagicChip.ticks)
        out.put("glowDrawn", MagicChip.drawn)
        out.put("clipLabel", clip?.label?.toString() ?: "")
        val dir = java.io.File(filesDir, "qa").apply { mkdirs() }
        // Written whole, then swapped in: a reader never sees half a file.
        val tmp = java.io.File(dir, "state.json.tmp")
        tmp.writeText(out.toString())
        tmp.renameTo(java.io.File(dir, "state.json"))
    }

    override fun onDestroy() {
        (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager)
            .removePrimaryClipChangedListener(clipListener)
        if (com.arpit.glyf.BuildConfig.DEBUG) runCatching { unregisterReceiver(debugTool) }
        dictation?.cancel()
        super.onDestroy()
    }

    /** The strip's height: 50, or 42 on a phone held sideways, which has
     *  little height to spare (AOSP's landscape strip is 36). */
    private val stripDp: Int
        get() = resources.configuration.let {
            if (it.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE &&
                it.smallestScreenWidthDp < 600) 42 else STRIP_DP
        }

    /** A tablet's keyboard is centred, its letter keys no wider than 1.5
     *  times their height (GlyfKeyboardView.tabletContentDp): what is left
     *  on each side, in px. */
    private fun tabletSide(): Int {
        val cfg = resources.configuration
        if (cfg.smallestScreenWidthDp < 600) return 0
        val w = cfg.screenWidthDp.toFloat()
        return dp(((w - GlyfKeyboardView.tabletContentDp(w)) / 2f).coerceAtLeast(0f).toInt())
    }

    /** Never the full-screen editor: the app stays in sight above the keys,
     *  as on iOS (Android's default covers it on every phone held sideways). */
    override fun onEvaluateFullscreenMode(): Boolean = false

    @SuppressLint("InflateParams")
    override fun onCreateInputView(): View {
        forgetSurfaces()
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            // A held top-row key's accents rise over the strip above it.
            clipChildren = false
        }
        toolbar = object : LinearLayout(this) {
            // The tools are spaced from the key's ink once both have a place.
            override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
                super.onLayout(changed, l, t, r, b)
                spaceStripTools()
            }
        }.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
            // A chip's glow reaches past it, into the strip's padding: cut
            // there, it ended in a hard edge.
            clipChildren = false
            clipToPadding = false
        }
        keyboard = GlyfKeyboardView(this, this)
        // The strip: STRIP_DP from the board's top edge to the key area.
        root.addView(toolbar, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(stripDp)))
        root.addView(keyboard)
        // Keep the key rows clear of the keyboard's navigation strip. With
        // gesture navigation Android draws a 48dp strip under an IME (hide
        // and switch-keyboard buttons) but reports only the 24dp gesture bar
        // as navigationBars; the strip is the tappable inset. Gboard clears it
        // and leaves 6dp more, measured on the emulator.
        // Start at the usual answer (a 48dp strip) so the first show is laid
        // out right; the insets below correct it where a phone differs.
        val centre = tabletSide()
        root.setPadding(centre, 0, centre, startingBottomPad())
        root.setOnApplyWindowInsetsListener { v, insets ->
            val bottom = if (android.os.Build.VERSION.SDK_INT >= 30) {
                maxOf(insets.getInsets(android.view.WindowInsets.Type.navigationBars()).bottom,
                      insets.getInsets(android.view.WindowInsets.Type.tappableElement()).bottom)
            } else @Suppress("DEPRECATION") insets.systemWindowInsetBottom
            lastBottomInset = bottom
            // Sides: a camera cutout or a navigation bar beside a phone held
            // sideways keeps the keys clear of it; a tablet's are centred.
            val side = if (android.os.Build.VERSION.SDK_INT >= 30)
                insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout())
            else null
            val left = (side?.left ?: 0) + centre
            val right = (side?.right ?: 0) + centre
            if (v.paddingBottom != bottom + dp(6) || v.paddingLeft != left || v.paddingRight != right) {
                v.setPadding(left, 0, right, bottom + dp(6))
            }
            insets
        }
        return root
    }

    /** The text before the caret at the last strip update (PhraseMemory). */
    private var phraseSeen = ""

    /** Remembers each sentence the person finishes or sends: one ending in
     *  . ! ? and a space, or the field emptied after a message (sent).
     *  Never where learning is off (passwords, incognito). iOS twin. */
    private fun notePhrases(before: String) {
        val seen = phraseSeen
        phraseSeen = before
        if (before == seen || typingPolicy() and TypingEngine.LEARNING == 0) return
        val ended = com.arpit.glyf.ime.typing.PhraseMemory.endedSentence(before)
        if (ended != null && !seen.endsWith("$ended ") && before.length > seen.length) {
            com.arpit.glyf.ime.typing.PhraseMemoryStore.record(this, ended)
        } else if (before.isEmpty() && seen.length >= 15 &&
            currentInputConnection?.getTextAfterCursor(1, 0).isNullOrEmpty() &&
            (!seen.endsWith(" ") || com.arpit.glyf.ime.typing.PhraseMemory.endedSentence(seen) == null)) {
            com.arpit.glyf.ime.typing.PhraseMemoryStore.record(this, com.arpit.glyf.ime.typing.PhraseMemory.lastSentence(seen))
        }
    }

    /** The wallet turned on in the app (Profile › Keyboard › Wallet,
     *  2026-10-14): off, no Pay tool, no Send or Buy, no Buy beside a price. */
    private val walletOn: Boolean get() = settings.optBoolean("walletEnabled", false)

    /** The bottom inset the window last reported; -1 until it has. */
    private var lastBottomInset = -1

    /** Room under the keys before the window has said how much it needs:
     *  what it said last time, else the phone's own navigation bar height
     *  (a guessed 48dp left a blank band on phones whose Android draws no
     *  hide and switch buttons under a keyboard; Arpit, 2026-10-14: "on long
     *  android phones the bottom part of keyboard is just empty"). */
    private fun startingBottomPad(): Int {
        if (lastBottomInset >= 0) return lastBottomInset + dp(6)
        val id = resources.getIdentifier("navigation_bar_height", "dimen", "android")
        val bar = if (id > 0) resources.getDimensionPixelSize(id) else dp(48)
        return bar + dp(6)
    }

    /** A view built again (a new configuration) starts clean: every strip,
     *  panel and editor belonged to the old one, and a flag left set would
     *  send the keys into an editor nobody can see. */
    private fun forgetSurfaces() {
        (featurePanel as? GamesPanelView)?.stop()
        featurePanel = null
        emojiBoard = null
        if (vaultAddOpen) watchBack(false)
        showVaultAdd = null
        vaultAddOpen = false
        overlay = null
        searchActive = false
        searchQuery = ""
        searchStrip = null; searchResults = null; searchLanding = null; searchChipsRow = null
        searchQueryView = null; searchStatusView = null; searchChipsScroll = null
        searchThumb = null; searchTabs = emptyList(); searchAbc = null
        barActive = false
        barPrompt = ""
        barStrip = null; barPromptView = null; barRunView = null; barInput = null
        vaultEditActive = false
        vaultDraft = null
        vaultEditText = ""
        vaultEditStrip = null; vaultEditView = null; vaultShortcutView = null; vaultEditStatus = null
        vaultShortcutText = ""; vaultShortcutActive = false
        translateStrip = null; translateDir = null; translateText = null; translateReplace = null
        translateSource = ""; translateResult = ""; translateSpan = ""
        stripChip = null; stripChipKind = null; stripSmartDetail = null
        actGeneration++ // a late act result must not land in the new view
        actStreamView = null; actOptionList = null
        coachOverlay = null; coachedStep = null
        main.removeCallbacks(hideNotice)
        noticeView = null
        dropMarker = null
        draggingTool = null; dragGhost = null
        gPill = null
        dictation?.cancel(); dictation = null; dictationStrip = null
    }

    /** Screenshot runs only (the "cliphold" debug tool): the clipboard is
     *  not filed and offers no paste chip, so a capture shows the seeded
     *  copies and nothing else. */
    private var qaClipHeld = false

    /** Bumped for every field, shown or not: an answer that arrives late
     *  (a calendar's Google or Cal.com reply) must not land in the next app. */
    private var inputSession = 0

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        inputSession++
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        // Signed out and back in since the keyboard last ran? Take the new one.
        com.arpit.glyf.ime.BackendClient.bearer = com.arpit.glyf.SessionStore.token(this)
        android.util.Log.d("GlyfKB", "onStartInputView restarting=$restarting overlay=${overlay != null}")
        // Setup milestones, counts only (Funnel). Android has no Full Access
        // switch: a keyboard that runs has the network.
        com.arpit.glyf.store.Funnel.mark(this, "keyboard_opened")
        com.arpit.glyf.store.Funnel.mark(this, "full_access")
        // A new field starts without caps lock, as iOS's and Gboard's do.
        if (!restarting && ::keyboard.isInitialized) { keyboard.capsLock = false; keyboard.shifted = false }
        settings = SettingsStore.load(this)
        settingsStamp = com.arpit.glyf.store.Bridge.file(this, SettingsStore.FILE).lastModified()
        showPayOutcomeIfFresh()
        val dark = when (settings.optString("appearance", "auto")) {
            "dark" -> true
            "light" -> false
            else -> resources.configuration.uiMode and
                android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
        }
        keyboard.isDark = dark
        // The surfaces' tokens (iOS Glass) read the same light or dark.
        Glass.dark = dark
        keyboard.keyTheme = settings.optString("keyTheme", "site")
        // The colour and gradient themes are retired for now (user,
        // 2026-09-27); one picked before is ignored, like on the iPhone.
        keyboard.themeBg = ""
        // A keyboard theme (docs/THEMES.md): "" or an unknown id is today's look.
        keyboard.skin = KeyboardThemes.byId(settings.optString("skin", ""))
        keyboard.skinSound = settings.optBoolean("skinSound", true)
        applySkinChrome()
        keyboard.keyBorders = settings.optBoolean("keyBorders", false)
        keyboard.themeDim = settings.optDouble("themeBrightness", 0.0).toFloat()
        keyboard.numberRow = settings.optBoolean("numberRow", false)
        keyboard.letterLayout = LetterLayout.of(settings.optString("keyLayout", "qwerty"))
        keyboard.commaKey = settings.optBoolean("commaKey", false)
        keyboard.periodKey = settings.optBoolean("periodKey", false)
        com.arpit.glyf.ime.typing.KeyboardTyping.letterRows = keyboard.letterLayout.rows
        keyboard.hapticsOn = settings.optBoolean("haptics", true)
        keyboard.clicksOn = settings.optBoolean("keyClicks", true)
        keyboard.kContext = KContext.from(info)
        keyboard.returnAction = returnActionOf(info)
        keyboard.mode = Mode.LETTERS
        keyboard.bindings = settings.optJSONObject("bindings")?.let { b ->
            b.keys().asSequence().associateWith { b.optString(it) }
        } ?: emptyMap()
        val themed = keyboard.themedBackdrop()
        if (themed != null) root.background = themed
        else root.setBackgroundColor(keyboard.backdrop())
        buildToolbar(dark || keyboard.themeBg.isNotEmpty())
        clearCoach()
        tourTyped = null
        main.removeCallbacks(tourTick)
        main.postDelayed(tourTick, 400)
        // Android hands a keyboard the clipboard without asking, so history
        // fills itself: whatever was copied since last time is kept here.
        if (!isSecureField() && !qaClipHeld) com.arpit.glyf.store.ClipboardStore.captureNow(this, settings)
        actGeneration++ // a late act result must not land in a new field
        recentFixes.clear()  // another field: its corrections are not these
        dismissedChip = null // and a chip waved off there may come here
        stripPolicy.enter(policyFieldId())
        voiceSpan = null; voiceRaw = null; voicePolishing++ // words said in the last field
        dismissOverlay()
        if (searchActive) exitSearch()
        if (barActive) exitBar()
        // A note left open would take the next app's typing into itself.
        if (vaultEditActive) exitVaultEdit()
        if (translateStrip != null) exitTranslate()
        // A new field starts on the letters, like Gboard: an emoji page or a
        // menu left open in the last one would otherwise sit under the keys.
        if (featurePanel != null) dismissFeaturePanel()
        keyboard.rebuild()
        syncAutoShift()
        refreshClipCard()
        lastCorrection = null
        wordTouches.clear()
        wordTouchesFor = ""
        toolsPinned = false
        KeyboardTyping.prepare(this) { seedOwnNames(vaultFields()); glideDecoderReady()?.warm(); updateSuggestions() }
        // A temp address being watched: carry on here, with a look at once
        // (a mail may have come while the keyboard was away).
        tempViewUp = true
        main.removeCallbacks(tempTick)
        if (TempMailStore.load(this)?.let { tempWatching(it) } == true) main.postDelayed(tempTick, 1500)
        // The microphone was allowed a moment ago from the mic: listen now, as
        // that tap meant to, without a second tap.
        if (com.arpit.glyf.MicPermissionActivity.takeFreshGrant())
            main.postDelayed({ if (currentInputConnection != null && root.isShown) startDictation() }, 350)

        // M0 ping — proof the keyboard ran (Android IMEs have network by
        // permission, so the FA flag is simply true here).
        Bridge.write(this, "keyboard-ping.json", JSONObject(mapOf(
            "ts" to System.currentTimeMillis() / 1000.0,
            "appearance" to if (dark) 2 else 1,
            "footprintMB" to 0.0,
            "hasFullAccess" to true,
            "from" to "keyboard")).toString())
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        super.onFinishInputView(finishingInput)
        endDictation(null)
        main.removeCallbacks(tourTick)
        // Temp mail is checked only while the keyboard is up.
        tempViewUp = false
        main.removeCallbacks(tempTick)
        main.removeCallbacks(tempClock)
        clearCoach()
        KeyboardTyping.saveNow(this)
    }

    /** A back press the vault's open "+" options are taking. */
    private var backForOptions = false

    /** Back puts the vault's "+" options away first; the next back hides
     *  the keyboard, as always. The whole press is theirs: put away on the
     *  down, the up went on to the app, which hid the keyboard (Android 16
     *  sends the down here and the up to the app). */
    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent): Boolean {
        if (keyCode == android.view.KeyEvent.KEYCODE_BACK && vaultAddOpen) {
            backForOptions = true
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: android.view.KeyEvent): Boolean {
        if (keyCode == android.view.KeyEvent.KEYCODE_BACK && backForOptions) {
            backForOptions = false
            showVaultAdd?.invoke(false)
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    /** From Android 13 the app takes the up of a back press (on 16 it slid
     *  the keyboard away with the options out): a callback the keyboard puts
     *  on its own window, while the options are out, is passed to the app
     *  ahead of its own. */
    private val vaultAddBack: Any? = if (android.os.Build.VERSION.SDK_INT >= 33)
        android.window.OnBackInvokedCallback { showVaultAdd?.invoke(false) } else null

    private fun watchBack(on: Boolean) {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        val dispatcher = window?.window?.onBackInvokedDispatcher ?: return
        val callback = vaultAddBack as android.window.OnBackInvokedCallback
        if (on) dispatcher.registerOnBackInvokedCallback(
            android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY, callback)
        else dispatcher.unregisterOnBackInvokedCallback(callback)
    }

    // MARK: toolbar (g keycap + essentials)

    /** What a theme changes around the keys: the strip's own background
     *  when it has one (else the board shows through), and the chip's face
     *  and accent. The chip takes them only where its face sits on the
     *  side of the mode the chip's words are set for (a dark face in light
     *  mode keeps today's glass), so its words always read. */
    private fun applySkinChrome() {
        val v = keyboard.skin?.variant(keyboard.isDark)
        toolbar.setBackgroundColor(v?.stripBackground ?: Color.TRANSPARENT)
        val faceDark = v != null &&
            GlyfKeyboardView.KeyPalette.luminance(v.chipFace) < 0.5f
        val fits = v != null && faceDark == keyboard.isDark
        Glass.skinChipFace = if (fits) v!!.chipFace else null
        Glass.skinChipAccent = if (fits) v!!.chipAccent else null
    }

    private fun buildToolbar(dark: Boolean) {
        toolbar.removeAllViews()
        stripTitleRow = null
        // A theme's strip text (checked on each of its board's stops).
        val ink = keyboard.skin?.variant(keyboard.isDark)?.stripText
            ?: if (dark) Color.WHITE else Color.rgb(18, 18, 20)

        // Glyf's own key, the same as iOS's: the app icon as a 41 by 30 pill
        // with its violet dot (GlyfMark), white with a black g on a light
        // sheet and its dark twin on a dark one. The view is the tap target;
        // the key is drawn inside it.
        val g = GlyfKeyView(this, dp(30).toFloat())
        g.dark = dark
        g.ink = ink
        g.divider = glassLook
        g.apply {
            setTag(com.arpit.glyf.R.id.qa_id, "toolbar:glyf")
            contentDescription = "Glyf menu"
            setOnClickListener {
                // While suggestions fill the strip, g brings the tools back (iOS §6.2).
                // As ✕ (over the menu, Pay or Games) it closes what is open.
                if (closing || featurePanel is ToolMenuView) {
                    dismissFeaturePanel()
                } else if (suggestionRow.visibility == View.VISIBLE) {
                    toolsPinned = true
                    applySuggestionVisibility()
                } else showMenuGrid() // iOS shell parity
            }
            setOnLongClickListener { openApp(); true }
        }
        toolbar.addView(g, LinearLayout.LayoutParams(dp(52), dp(38)))
        toolIcons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            // Spaced from the ✕, a first tool can sit nearer it than this
            // row's edge (spaceStripTools).
            clipChildren = false
        }
        toolbar.addView(toolIcons, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        suggestionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
        }
        toolbar.addView(suggestionRow, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        suggestionsShown = emptyList()

        // The strip is the person's own: the same ids, order and hidden set
        // the iOS strip reads, so a tool pinned on one phone reads the same.
        val shown = stripTools()
        for (id in shown) {
            // iOS draws the strip's tools as 21pt symbols in the ink at 78%.
            val v = ToolIcon(this, id, ink).apply { scale = 1.22f; weight = 1.4f }
            v.setTag(com.arpit.glyf.R.id.qa_id, id)
            v.contentDescription = ToolIcon.TOOLS.firstOrNull { it.first == id }?.second ?: id
            v.setOnClickListener { openTool(id) }
            v.setOnTouchListener(StripToolTouch(id))
            toolIcons.addView(v, LinearLayout.LayoutParams(0, dp(34), 1f))
        }
        stripShown = shown.toSet()
        gPill = g
    }

    /** iOS Toolbar.layoutSubviews' one gap (Arpit, 2026-10-06: "why the fuck
     *  doesnt it feel centered, why soo much space after cross"): the same
     *  air between any two inks, the key's or the ✕'s included, and five
     *  tools or more end as far in as the key starts. The gap is never wider
     *  than five tools of these widths would get: fewer keep it and gather on
     *  the strip's middle, though never nearer the key than one gap (Arpit:
     *  "they should be centered and equally spaced in case of less items").
     *  Each tool's view reaches halfway into the gaps beside it; a drop
     *  marker stands in the middle of its gap. */
    private fun spaceStripTools() {
        val lead = gPill ?: return
        if (!::toolIcons.isInitialized) return
        val row = toolIcons
        if (lead.parent !== toolbar || row.parent !== toolbar || row.visibility != View.VISIBLE) return
        // In the row's own coordinates. The g key (or the ✕) stays where it
        // is, and the tools share what is left of the strip evenly: the same
        // air before each of them and after the last (Arpit, 2026-10-06:
        // "keep g on left as it is and then place the left over in space left
        // over equally and just make sure they look good"). iOS Toolbar twin.
        val start = lead.left + lead.inkRight - row.left
        val end = toolbar.width - row.left
        val tools = (0 until row.childCount).map { row.getChildAt(it) }.filterIsInstance<ToolIcon>()
        if (tools.isEmpty()) return
        val inks = tools.map { it.inkWidth() }
        val gap = maxOf(dp(4).toFloat(), (end - start - inks.sum()) / (tools.size + 1))
        var next = start + gap
        for (i in 0 until row.childCount) {
            val child = row.getChildAt(i)
            val at = tools.indexOf(child)
            val l: Float
            val w: Float
            if (at >= 0) {
                l = next - gap / 2f
                w = inks[at] + gap
                next += inks[at] + gap
            } else {
                w = child.measuredWidth.toFloat()
                l = (next - gap / 2f - w / 2f).coerceIn(0f, maxOf(0f, row.width - w))
            }
            val left = Math.round(l)
            val right = Math.round(l + w)
            child.measure(View.MeasureSpec.makeMeasureSpec(right - left, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(child.measuredHeight, View.MeasureSpec.EXACTLY))
            child.layout(left, child.top, right, child.top + child.measuredHeight)
        }
    }

    private var gPill: GlyfKeyView? = null
    /** The tools on the strip as it was drawn: the g menu offers the rest. */
    private var stripShown: Set<String> = emptySet()

    private fun stripTools(): List<String> {
        val known = ToolIcon.TOOLS.map { it.first }.toSet()
        val order = settings.optJSONArray("toolbarOrder")
        val hidden = settings.optJSONArray("toolbarHidden")
        val hiddenSet = (0 until (hidden?.length() ?: 0)).map { hidden!!.optString(it) }.toSet()
        val ids = (0 until (order?.length() ?: 0)).map { order!!.optString(it) }
            .ifEmpty { com.arpit.glyf.store.SettingsStore.DEFAULT_STRIP }
        // Hidden as saved, then renamed: a hidden Shorthand must not hide the
        // Vault it became, while a pinned Emoji becomes a pinned GIFs.
        return ids.filter { it !in hiddenSet }.map { ToolIcon.canonical(it) }
            .filter { it in known && (it != "pay" || walletOn) }.distinct()
    }

    // MARK: a panel's name in the strip (iOS Toolbar.showPanelHeader)

    /** The open panel's ‹ and name, standing where the tools were. */
    private var stripTitleRow: LinearLayout? = null

    /** A panel is open (iOS and the website): the g key turns into ✕, and
     *  the tools give way to a ‹ (when [onBack] is a step back inside the
     *  panel, as the iPhone's shell has) and the panel's [title], with the
     *  tool's [icon] before it where iOS shows one. Returns the ‹, which is
     *  "panel:back" to the scenarios. */
    private fun showStripTitle(title: String, onBack: (() -> Unit)?, icon: String? = null): View? {
        clearStripTitle()
        gPill?.closing = true
        if (!::toolIcons.isInitialized) return null
        // A chip goes with the tools: the strip says which panel is open.
        stripChip?.let { toolbar.removeView(it) }
        stripChip = null
        stripChipKind = null
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setTag(com.arpit.glyf.R.id.qa_id, "strip:title")
        }
        // iOS starts the row 11pt past the key's ink, measured from the ✕'s
        // middle as from the key's (GlyfKeyView.markRight).
        val keyInkRight = GlyfKeyView.markRight(dp(52).toFloat(), dp(30).toFloat(), resources.displayMetrics.density)
        // The Glass look leaves room for its divider: 17 past the key, not 11.
        val from = (keyInkRight + dp(if (glassLook) 17 else 11) - dp(52)).toInt()
        // Starting nearer the ✕ than its view reaches, the row itself moves
        // over that view, so the ‹ keeps its whole target.
        val overlap = minOf(0, from - if (onBack != null) dp(4) else 0)
        val start = from - overlap
        var back: View? = null
        if (onBack != null) {
            // SF chevron.left at 15pt semibold.
            back = ToolIcon(this, "chevron", Glass.textPrimary).apply {
                solid = true
                // 13pt of ink, as iOS's chevron.left at 15 semibold.
                weight = 2.3f
                scale = 0.88f
                setTag(com.arpit.glyf.R.id.qa_id, "panel:back")
                contentDescription = "Back"
                setOnClickListener { onBack() }
            }
            // 30dp for the tap, its glyph 4dp in from where the row starts.
            row.addView(back, LinearLayout.LayoutParams(dp(30), LinearLayout.LayoutParams.MATCH_PARENT)
                .apply { leftMargin = start - dp(4) })
        }
        if (icon != null) row.addView(ToolIcon(this, icon, Glass.textPrimary).apply {
            solid = true
            weight = 1.8f
        }, LinearLayout.LayoutParams(dp(24), dp(24)).apply {
            leftMargin = if (back == null) start else -dp(2)
            rightMargin = dp(6)
        })
        row.addView(TextView(this).apply {
            text = title
            Glass.style(this, 15f, Glass.SEMIBOLD)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTag(com.arpit.glyf.R.id.qa_id, "strip:title:text")
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            if (back == null && icon == null) leftMargin = start
            else if (back != null && icon == null) leftMargin = -dp(2)
        })
        toolbar.addView(row, 1, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
            .apply { leftMargin = overlap })
        stripTitleRow = row
        applySuggestionVisibility()
        return back
    }

    /** The tools back on the strip, where a panel's name stood. */
    private fun clearStripTitle() {
        stripTitleRow?.let { if (::toolbar.isInitialized) toolbar.removeView(it) }
        stripTitleRow = null
        if (::toolIcons.isInitialized) applySuggestionVisibility()
    }

    /** Every tool opens the same way from the strip and from the g menu. */
    private fun openTool(id: String) {
        when (id) {
            "search" -> { dismissFeaturePanel(); enterSearch() }
            "clipboard" -> showClipboardPanel()
            // The menu's GIFs: the emoji board, on its GIFs tab.
            "gifs" -> showEmojiPanel(EmojiBoardView.Mode.GIFS)
            // Only the scenarios' debug tool still says "emoji": the board
            // as the emoji key opens it.
            "emoji" -> showEmojiPanel()
            "rewrite" -> {
                // The website's list of versions for what is typed; with
                // nothing typed, the bar asks what to write instead.
                dismissFeaturePanel()
                val ic = currentInputConnection
                val before = ic?.getTextBeforeCursor(2000, 0)?.toString() ?: ""
                val after = ic?.getTextAfterCursor(2000, 0)?.toString() ?: ""
                if ((before + after).isBlank()) showGlyfBar() else startAct(before, after, "rewrite")
            }
            "translate" -> { dismissFeaturePanel(); runTranslateOnField() }
            "ask" -> { dismissFeaturePanel(); onSpaceHoldOpenBar() }
            "dictation" -> { dismissFeaturePanel(); startDictation() }
            // Shorthand is a section of the vault; Keys said what My glyfs says.
            "vault", "shorthand" -> showVaultPanel()
            "calendar" -> showCalendarPanel()
            "games" -> showGamesPanel()
            "glyfs", "keys" -> showMyGlyfsPanel()
            "tempmail" -> showTempMailPanel()
            "style" -> showStylePanel()
            // Paying is signed in the app's wallet, never in the keyboard.
            "pay" -> showPayPanel(PayPanelView.Intent.Send(null, null, null))
            // The keyboard's own settings, in the keyboard (iOS's shell screen).
            "settings" -> showSettingsPanel()
        }
    }

    // MARK: voice typing, in the keyboard (Dictation, DictationStripView)

    private var dictation: Dictation? = null
    private var dictationStrip: DictationStripView? = null
    /** The keyboard's children when listening began: one more or less means
     *  something else took the strip or the keys. */
    private var dictationChildren = 0

    /** The mic types from Glyf's own keyboard (Arpit, 2026-10-06: "the mic
     *  should work inside keyboard for typing not open the app"): the strip
     *  listens and shows the words as they come, and they go into the field
     *  when the person stops talking or taps Done. Without the microphone
     *  yet, the app asks for it once over the app being typed in, and the
     *  keyboard starts listening as soon as it is back. [script]: debug
     *  builds' stand-in words (DEBUG_TOOL "voicefake"). */
    private fun startDictation(script: String? = null) {
        if (dictation != null || !::toolbar.isInitialized) return
        // Gboard keeps its mic off a password field too.
        if (isSecureField()) { notice("No voice typing in a password field"); return }
        if (script == null && !com.arpit.glyf.MicPermissionActivity.granted(this)) {
            com.arpit.glyf.MicPermissionActivity.ask(this)
            return
        }
        hideVoiceChip()
        // A half-typed word stays as typed: the words go after it, not over it.
        currentInputConnection?.finishComposingText()
        lateinit var strip: DictationStripView
        // Said marks show as marks while the words come ("hi comma" → "hi,").
        val english = java.util.Locale.getDefault().language == "en"
        val d = Dictation(this,
            onWords = { strip.words(VoiceText.spokenPunctuation(it, english)) },
            onLevel = { strip.level(it) },
            onReady = { strip.ready() },
            onStopping = { strip.stopping() },
            onEnd = { heard, note -> endDictation(heard, note) },
            script = script)
        strip = DictationStripView(this, keyboard.palette(),
            onCancel = { endDictation(null) },
            onDone = { d.stop() })
        // In the strip's place, as translate is.
        toolbar.visibility = View.GONE
        root.addView(strip, root.indexOfChild(toolbar),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(stripDp)))
        dictation = d
        dictationStrip = strip
        dictationChildren = root.childCount
        root.viewTreeObserver.addOnGlobalLayoutListener(dictationGuard)
        d.start()
    }

    /** The emoji board, a panel or the Glyf bar taking the strip or the keys
     *  ends the listening, and what was heard goes in. */
    private val dictationGuard = android.view.ViewTreeObserver.OnGlobalLayoutListener {
        val strip = dictationStrip ?: return@OnGlobalLayoutListener
        if (toolbar.visibility == View.VISIBLE || keyboard.visibility != View.VISIBLE ||
            root.childCount != dictationChildren) {
            main.post { if (dictationStrip === strip) endDictation(dictation?.heard, taken = true) }
        }
    }

    /** Listening is over: [heard] goes into the field (VoiceText.commit);
     *  with nothing heard, [note] says why. [taken]: something else has the
     *  strip now, so it stays as that left it. */
    private fun endDictation(heard: String?, note: String? = null, taken: Boolean = false) {
        val d = dictation ?: return
        dictation = null
        d.cancel()
        runCatching { root.viewTreeObserver.removeOnGlobalLayoutListener(dictationGuard) }
        dictationStrip?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        dictationStrip = null
        if (!taken) toolbar.visibility = View.VISIBLE
        if (!heard.isNullOrBlank()) insertHeard(heard.trim(), offerPolish = !taken)
        else note?.let { notice(it) }
    }

    /** Heard words as typed ones (VoiceText.commit): spaced from the words
     *  either side, a capital where a sentence starts and none mid-sentence,
     *  Gboard's spoken punctuation. Then, for a few words or more, the strip
     *  offers Polish. */
    private fun insertHeard(heard: String, offerPolish: Boolean = true) {
        val ic = currentInputConnection ?: return
        val ei = currentInputEditorInfo
        val capFlags = InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_CAP_WORDS or
            InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
        val capitals = settings.optBoolean("autocapitalize", true) && ei != null &&
            ei.inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT &&
            ei.inputType and capFlags != 0
        val before = ic.getTextBeforeCursor(64, 0)?.toString() ?: ""
        val after = ic.getTextAfterCursor(8, 0)?.toString() ?: ""
        val english = java.util.Locale.getDefault().language == "en"
        val commit = VoiceText.commit(heard, before, after, capitals, english)
        if (commit.text.isEmpty()) return
        ic.beginBatchEdit()
        if (commit.deleteBefore > 0) ic.deleteSurroundingText(commit.deleteBefore, 0)
        ic.commitText(commit.text, 1)
        ic.endBatchEdit()
        val core = commit.text.trim(' ')
        voiceSpan = if (offerPolish && core.split(Regex("\\s+")).size >= 3) commit.text else null
        voiceRaw = null
        updateSuggestions()
        syncAutoShift()
    }

    // MARK: Polish, after voice typing (the server's dictation.clean glyf)

    /** What voice typing just put in, as committed (spaces included), while
     *  it is still right before the cursor: Polish is offered for it. */
    private var voiceSpan: String? = null
    /** The words before a polish, while the polished ones are still there:
     *  the chip offers them back (Undo). */
    private var voiceRaw: String? = null
    private var voicePolishing = 0

    /** The voice chip owns the strip while what it is about sits right
     *  before the cursor; a key, a move of the cursor or another field ends it. */
    private fun voiceChipHolds(before: String): Boolean {
        val span = voiceSpan ?: return false
        return before.endsWith(span)
    }

    private fun hideVoiceChip() {
        voiceSpan = null
        voiceRaw = null
        voicePolishing++
        if (stripChipKind == "voice") hideStripChip()
    }

    /** The chip for [voiceSpan]: Polish (or Undo after one). True when shown. */
    private fun showVoiceChip(): Boolean {
        val span = voiceSpan ?: return false
        if (stripChipKind == "voice" && stripChip?.tag == span) return true
        val raw = voiceRaw
        val shown = if (raw != null) showStripChip("voice", null, span.trim(), "Undo", lead = "dictation",
                onClose = { hideVoiceChip() }) { undoPolish(raw) }
            else showStripChip("voice", null, span.trim(), "Polish", lead = "dictation",
                onClose = { hideVoiceChip() }) { polishVoice() }
        if (shown) stripChip?.tag = span
        return shown
    }

    /** Polish: the words just said, cleaned up by the server's
     *  dictation.clean glyf (fillers out, punctuation and casing fixed, the
     *  wording kept), in place of what was said. One run, as any glyf's. */
    private fun polishVoice() {
        val span = voiceSpan ?: return
        if (isSecureField()) return
        val core = span.trim(' ')
        val lead = span.substring(0, span.length - span.trimStart(' ').length)
        val tail = span.substring(span.trimEnd(' ').length)
        val run = ++voicePolishing
        com.arpit.glyf.store.Funnel.mark(this, "first_ai")
        showStripChip("voice", null, "Polishing…", "", lead = "dictation", onClose = { hideVoiceChip() }) {}
        stripChip?.tag = "polishing"
        val session = inputSession
        BackendClient.run(
            settings.optString("backendURL"), "dictation.clean", core, emptyMap(),
            settings.optString("deviceId"), settings.optString("plan", "free"),
            onToken = {},
            onDone = { text, _ -> main.post {
                if (run != voicePolishing || session != inputSession) return@post
                val ic = currentInputConnection
                val before = ic?.getTextBeforeCursor(span.length + 8, 0)?.toString() ?: ""
                if (ic == null || !before.endsWith(span)) { hideVoiceChip(); return@post }
                // An empty answer is the server giving up, not a verdict.
                if (text.isBlank()) { hideVoiceChip(); notice("Couldn't polish that"); return@post }
                val polished = lead + VoiceText.polished(core, text) + tail
                if (polished == span) { hideVoiceChip(); notice("Already reads well"); return@post }
                ic.beginBatchEdit()
                ic.deleteSurroundingText(span.length, 0)
                ic.commitText(polished, 1)
                ic.endBatchEdit()
                // Glyf wrote it: no chip offering to tidy up its own work.
                glyfWrote = polished.trim()
                voiceSpan = polished
                voiceRaw = span
                hideStripChip()
                updateSuggestions()
                syncAutoShift()
            } },
            onError = { message -> main.post {
                if (run != voicePolishing) return@post
                hideVoiceChip()
                notice(message.substringBefore(". Tap to retry").substringBefore(" Tap to retry"))
            } },
        )
    }

    /** Undo: the words as they were said, back in place of the polished ones. */
    private fun undoPolish(raw: String) {
        val span = voiceSpan ?: return
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(span.length + 8, 0)?.toString() ?: ""
        if (!before.endsWith(span)) { hideVoiceChip(); return }
        ic.beginBatchEdit()
        ic.deleteSurroundingText(span.length, 0)
        ic.commitText(raw, 1)
        ic.endBatchEdit()
        hideVoiceChip()
        updateSuggestions()
        syncAutoShift()
    }

    /** glyf://open?path=… with the path and its query as ONE encoded value,
     *  so "wallet?to=…&amount=5" arrives whole (a bare & cut the amount off). */
    private fun openAppPath(path: String, query: Map<String, String> = emptyMap()) {
        val inner = if (query.isEmpty()) path else path + "?" + query.entries.sortedBy { it.key }
            .joinToString("&") { "${it.key}=${android.net.Uri.encode(it.value)}" }
        startActivity(Intent(Intent.ACTION_VIEW,
            android.net.Uri.parse("glyf://open?path=${android.net.Uri.encode(inner)}"))
            .setPackage(packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun openApp() {
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun pasteClipboard() {
        com.arpit.glyf.store.ClipboardStore.clipText(this, allowSensitive = true)?.let { insertSpaced(it) }
    }

    /** A pasted copy is its own piece of text: never glued onto the word
     *  before it ("10.8QvS…"). iOS twin: `spaced(_:after:)`. */
    private fun insertSpaced(text: String) {
        val ic = currentInputConnection ?: return
        val last = ic.getTextBeforeCursor(1, 0)?.lastOrNull()
        ic.commitText(if (last == null || last.isWhitespace()) text else " $text", 1)
    }

    private fun insertVaultFirst() {
        val vault = VaultStore.load(this)
        val fields = vault.optJSONArray("fields") ?: return
        if (fields.length() > 0) {
            currentInputConnection?.commitText(
                fields.getJSONObject(0).optString("value"), 1)
        }
    }

    // MARK: search suite (Gboard-style: chips + query the keys type into)

    private val chromeDark get() = keyboard.isDark || keyboard.themeBg.isNotEmpty()
    private fun ink() = keyboard.palette().ink
    private fun card() = keyboard.palette().card

    /** Search as iOS draws it (SearchSurface): one 44dp row in the strip's
     *  place (✕, the tab track with a sliding thumb, the query the keys type
     *  into, the go button) over a 40dp row of suggestion chips; results
     *  take the chips' and the keys' place, with ABC to bring them back. */
    private fun enterSearch() {
        if (searchActive) return
        removeClipCard()
        searchActive = true
        searchTab = "web"
        searchQuery = ""
        // A search starts in lowercase, whatever capital the message field
        // was about to get (Gboard's, and the emoji board's search here).
        if (keyboard.shifted && autoShifted) {
            keyboard.shifted = false
            autoShifted = false
            keyboard.invalidate()
        }
        toolbar.visibility = View.GONE
        val rowH = dp(44)
        val strip = FrameLayout(this)
        strip.addView(ToolIcon(this, "close", Glass.textSecondary).apply {
            solid = true; weight = 2f; scale = 0.95f
            setTag(com.arpit.glyf.R.id.qa_id, "search:close"); contentDescription = "Close"
            setOnClickListener { exitSearch() }
        }, FrameLayout.LayoutParams(dp(32), dp(30)).apply { leftMargin = dp(2); topMargin = (rowH - dp(30)) / 2 })
        // The website's tab track: a soft pill of icon-only tabs, a key-coloured
        // thumb sliding to the chosen one.
        val tabs = listOf("web" to "search", "yt" to "playrect", "maps" to "map",
            "contacts" to "personcircle", "translate" to "bubble")
        val pillW = dp(35); val pillH = dp(30); val pad = dp(3); val gap = dp(2)
        val trackW = pillW * tabs.size + gap * (tabs.size - 1) + pad * 2
        val trackH = pillH + pad * 2
        val track = FrameLayout(this).apply { background = Glass.pill(Glass.fillSoft) }
        val thumb = View(this).apply { background = Glass.pill(Glass.surfaceCard) }
        track.addView(thumb, FrameLayout.LayoutParams(pillW, pillH).apply { leftMargin = pad; topMargin = pad })
        val tabViews = mutableListOf<Pair<String, ToolIcon>>()
        for ((i, pair) in tabs.withIndex()) {
            val (tabId, glyph) = pair
            val icon = ToolIcon(this, glyph, Glass.textSecondary).apply {
                solid = true; weight = 1.7f; scale = 1.05f
                contentDescription = when (tabId) {
                    "web" -> "Search"; "yt" -> "YouTube"; "maps" -> "Maps"
                    "contacts" -> "Contacts"; else -> "Translate"
                }
                setTag(com.arpit.glyf.R.id.qa_id, "search:tab:$tabId")
                setOnClickListener {
                    if (tabId == "translate") {
                        // The tab opens the translate strip, as on iOS.
                        exitSearch()
                        runTranslateOnField()
                        return@setOnClickListener
                    }
                    searchTab = tabId
                    styleSearchTabs(animated = true)
                    if (searchQuery.isBlank()) showLanding() else submitSearch()
                }
            }
            track.addView(icon, FrameLayout.LayoutParams(pillW, pillH).apply {
                leftMargin = pad + i * (pillW + gap); topMargin = pad
            })
            tabViews.add(tabId to icon)
        }
        strip.addView(track, FrameLayout.LayoutParams(trackW, trackH).apply {
            leftMargin = dp(34); topMargin = (rowH - trackH) / 2
        })
        val queryX = dp(34) + trackW + dp(6)
        val abc = TextView(this).apply {
            text = "ABC"
            Glass.style(this, 14f, Glass.SEMIBOLD)
            gravity = Gravity.CENTER
            visibility = View.GONE
            setTag(com.arpit.glyf.R.id.qa_id, "search:abc")
            setOnClickListener { backToLanding() }
        }
        strip.addView(abc, FrameLayout.LayoutParams(dp(46), dp(34)).apply {
            leftMargin = queryX; topMargin = (rowH - dp(34)) / 2
        })
        val query = InlineField(this, "Search…").apply {
            setTag(com.arpit.glyf.R.id.qa_id, "search:query")
            active = true
        }
        val goW = dp(34)
        strip.addView(query, FrameLayout.LayoutParams(
            maxOf(dp(60), resources.displayMetrics.widthPixels - dp(40) - dp(6) - queryX), dp(34)).apply {
            leftMargin = queryX; topMargin = (rowH - dp(34)) / 2
        })
        strip.addView(GoButton(this).apply {
            setTag(com.arpit.glyf.R.id.qa_id, "search:go"); contentDescription = "Search"
            setOnClickListener { submitSearch() }
        }, FrameLayout.LayoutParams(goW, goW, Gravity.END or Gravity.TOP).apply {
            rightMargin = dp(6); topMargin = (rowH - goW) / 2
        })
        root.addView(strip, 0, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, rowH))
        searchStrip = strip
        searchQueryView = query
        searchThumb = thumb
        searchTabs = tabViews
        searchAbc = abc
        styleSearchTabs(animated = false)
        ensureSearchChipsRow()
        showLanding()
    }

    /** iOS's go button: arrow.forward.circle.fill in the ink. */
    private class GoButton(ctx: android.content.Context) : View(ctx) {
        private val disc = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        private val arrow = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            style = android.graphics.Paint.Style.STROKE
            strokeCap = android.graphics.Paint.Cap.ROUND
            strokeJoin = android.graphics.Paint.Join.ROUND
        }
        override fun onDraw(c: android.graphics.Canvas) {
            val d = resources.displayMetrics.density
            val cx = width / 2f; val cy = height / 2f
            disc.color = if (Glass.dark) Color.WHITE else Glass.brandInk
            arrow.color = if (Glass.dark) Glass.brandInk else Color.WHITE
            arrow.strokeWidth = 2.1f * d
            c.drawCircle(cx, cy, minOf(width, height) / 2f * 0.84f, disc)
            c.drawLine(cx - 5.2f * d, cy, cx + 5.2f * d, cy, arrow)
            c.drawLine(cx + 5.2f * d, cy, cx + 1f * d, cy - 4.2f * d, arrow)
            c.drawLine(cx + 5.2f * d, cy, cx + 1f * d, cy + 4.2f * d, arrow)
        }
    }

    /** The chosen tab in the ink on the thumb, the rest grey. */
    private fun styleSearchTabs(animated: Boolean) {
        val thumb = searchThumb ?: return
        for ((i, pair) in searchTabs.withIndex()) {
            val (tabId, icon) = pair
            val on = tabId == searchTab
            icon.setTint(if (on) Glass.textPrimary else Glass.textSecondary)
            icon.solid = true
            icon.isSelected = on
            if (on) {
                val x = (dp(3) + i * (dp(35) + dp(2))).toFloat()
                val lp = thumb.layoutParams as FrameLayout.LayoutParams
                if (animated && thumb.isLaidOut) thumb.animate().translationX(x - lp.leftMargin).setDuration(220)
                    .setInterpolator(android.view.animation.OvershootInterpolator(0.6f)).start()
                else thumb.translationX = x - lp.leftMargin
            }
        }
    }

    /** What a tab shows BEFORE anything is typed: the user's own recents
     *  (local, never uploaded) then trending / popular / nearby from the
     *  server. Gboard never opens on a blank box. */
    private fun showLanding() {
        val vertical = searchTab
        // Three, like the website's landing; Contacts keeps no recents (a
        // name is not a search).
        val recents = if (vertical == "contacts") emptyList()
            else com.arpit.glyf.store.SearchRecents.list(this, vertical).take(3)
            .map { q ->
                BackendClient.SearchCard(
                    kind = "query", id = "recent-$q", title = q, url = "",
                    source = "recent")
            }
        searchStatusView?.text = ""
        // Even empty: the row forgets the last tab's chips.
        showLandingRows(recents)
        if (vertical == "contacts") {
            searchStatusView?.text =
                if (com.arpit.glyf.store.Bridge.file(this, "contacts.json").exists())
                    "Type a name"
                else "Turn on Contacts search in the Glyf app"
            return
        }
        val lat = if (settings.has("lastLat")) settings.optDouble("lastLat") else null
        val lon = if (settings.has("lastLon")) settings.optDouble("lastLon") else null
        BackendClient.suggest(
            backendURL = settings.optString("backendURL"),
            vertical = vertical,
            deviceId = settings.optString("deviceId"),
            lat = lat?.takeIf { !it.isNaN() },
            lon = lon?.takeIf { !it.isNaN() },
            country = settings.optString("region").takeIf { it.length == 2 },
            onCards = { answered, cards -> main.post {
                if (answered != searchTab || searchQuery.isNotEmpty()) return@post
                val seen = recents.map { it.title.lowercase() }.toSet()
                val merged = recents + cards.filterNot { it.title.lowercase() in seen }
                if (merged.isNotEmpty()) showLandingRows(merged)
            } },
            onError = { },
        )
    }

    private fun renderQuery() {
        searchQueryView?.show(searchQuery)
    }

    /** Contacts filter as the name is typed: the matches show as chips over
     *  keys that stay live, so the next letter narrows them (iOS). */
    private fun searchQueryChanged() {
        if (searchTab != "contacts" || searchResults != null) return
        val q = searchQuery.trim()
        if (q.isEmpty()) { showLanding(); return }
        if (!com.arpit.glyf.store.Bridge.file(this, "contacts.json").exists()) {
            showLandingRows(emptyList())
            searchStatusView?.text = "Turn on Contacts search in the Glyf app"
            return
        }
        val rows = contactMatches(q)
        showLandingRows(rows)
        searchStatusView?.text = if (rows.isEmpty()) "No contacts named “$q”" else ""
    }

    private fun submitSearch() {
        val q = searchQuery.trim()
        if (q.isEmpty()) return
        if (searchTab == "contacts") {
            val rows = contactMatches(q)
            if (rows.isEmpty()) {
                searchStatusView?.text =
                    if (com.arpit.glyf.store.Bridge.file(this, "contacts.json").exists())
                        "No contacts named “$q”"
                    else "Turn on Contacts search in the Glyf app"
            } else showSearchResults(rows)
            return
        }
        dismissLanding()
        searchStatusView?.text = "Searching…"
        val vertical = searchTab
        com.arpit.glyf.store.SearchRecents.record(this, q, vertical)
        val lat = if (settings.has("lastLat")) settings.optDouble("lastLat") else null
        val lon = if (settings.has("lastLon")) settings.optDouble("lastLon") else null
        BackendClient.search(
            backendURL = settings.optString("backendURL"),
            vertical = vertical,
            query = q,
            deviceId = settings.optString("deviceId"),
            lat = lat?.takeIf { !it.isNaN() },
            lon = lon?.takeIf { !it.isNaN() },
            country = settings.optString("region").takeIf { it.length == 2 },
            tz = java.util.TimeZone.getDefault().id,
            dark = chromeDark,
            onCards = { answered, cards -> main.post {
                // A late reply from a tab the user already left must not
                // replace what they are looking at now.
                if (answered != searchTab) return@post
                // Places near you need to know where you are: the app asks.
                val nowhere = vertical == "maps" && lat?.takeIf { !it.isNaN() } == null
                searchStatusView?.text = if (cards.isEmpty()) {
                    if (nowhere) "Turn on Nearby search in the Glyf app" else "Nothing found"
                } else ""
                if (cards.isNotEmpty()) showSearchResults(cards)
            } },
            onError = { message -> main.post { searchStatusView?.text = message } },
        )
    }

    /** Local contacts synced by the app — never leaves the device. */
    private fun contactMatches(q: String): List<BackendClient.SearchCard> {
        val file = com.arpit.glyf.store.Bridge.file(this, "contacts.json")
        if (!file.exists()) return emptyList()
        val out = mutableListOf<BackendClient.SearchCard>()
        fun row(name: String, value: String) = BackendClient.SearchCard(
            kind = "contact", id = "$name-$value", title = name,
            url = value, snippet = value)
        try {
            val arr = org.json.JSONArray(file.readText())
            val lower = q.lowercase()
            for (i in 0 until arr.length()) {
                val c = arr.getJSONObject(i)
                val name = c.optString("name")
                if (!name.lowercase().contains(lower)) continue
                val phones = c.optJSONArray("phones")
                val emails = c.optJSONArray("emails")
                for (j in 0 until (phones?.length() ?: 0)) {
                    out.add(row(name, phones!!.getString(j)))
                }
                for (j in 0 until (emails?.length() ?: 0)) {
                    out.add(row(name, emails!!.getString(j)))
                }
                if (out.size >= 20) break
            }
        } catch (_: Exception) {}
        return out
    }

    private val searchChipsHeight get() = dp(40)

    /** The 40dp row under the search row (index 1, over the keys): the
     *  suggestion chips, or in their place the status line ("Searching…",
     *  "Nothing found", "Type a name"), 12.5 grey, 16dp in (iOS). */
    private fun ensureSearchChipsRow(): android.widget.HorizontalScrollView {
        searchChipsScroll?.let { return it }
        val frame = FrameLayout(this)
        val scroll = android.widget.HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            clipToPadding = false
        }
        frame.addView(scroll, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        val status = TextView(this).apply {
            Glass.style(this, 12.5f, Glass.REGULAR, Glass.textSecondary)
            gravity = Gravity.CENTER_VERTICAL
            maxLines = 1
            setTag(com.arpit.glyf.R.id.qa_id, "search:status")
        }
        frame.addView(status, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT).apply {
            leftMargin = dp(16); rightMargin = dp(16)
        })
        root.addView(frame, 1, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, searchChipsHeight))
        searchChipsRow = frame
        searchChipsScroll = scroll
        searchStatusView = status
        return scroll
    }

    /** Suggestions as one row of chips side by side, so the keys stay where
     *  they are: a recent or trending search runs when tapped, a contact
     *  goes into the message. iOS's chips: 30dp pills of the key colour, an
     *  11 semibold mark (clock, trend arrow, phone, envelope), 13.5 medium. */
    private fun showLandingRows(cards: List<BackendClient.SearchCard>) {
        val row = ensureSearchChipsRow()
        row.removeAllViews()
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), 0, dp(4), 0)
        }
        for ((i, c) in cards.take(12).withIndex()) {
            val glyph = when {
                c.kind == "contact" -> if (c.url.contains("@")) "envelope" else "phone"
                c.source == "recent" -> "clock"
                else -> "trend"
            }
            list.addView(TextView(this).apply {
                text = if (c.kind == "contact") "${c.title} · ${c.url}" else c.title
                Glass.style(this, 13.5f, Glass.MEDIUM)
                maxLines = 1
                maxWidth = dp(230)
                ellipsize = android.text.TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_VERTICAL
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    ToolIcon(this@GlyfIME, glyph, Glass.textSecondary).apply {
                        solid = true; weight = 2f; scale = 0.72f
                    }.asDrawable(dp(15)), null, null, null)
                compoundDrawablePadding = dp(5)
                setPadding(dp(11), 0, dp(12), 0)
                background = Glass.pill(Glass.surfaceCard)
                setTag(com.arpit.glyf.R.id.qa_id, "search:row:$i")
                contentDescription = c.title
                setOnClickListener { insertResult(c) }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(30))
                .apply { rightMargin = dp(8) })
        }
        row.addView(list, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT))
        row.scrollTo(0, 0)
        searchLanding = list
        // Chips take the row; the status line gives way to them.
        if (cards.isNotEmpty()) searchStatusView?.text = ""
    }

    private fun dismissLanding() {
        searchChipsScroll?.removeAllViews()
        searchLanding = null
    }

    /** Results replace the chips and the keys (ABC returns them): the same
     *  height, so the keyboard stays put. iOS's result cards: the key
     *  colour, 15 corners, a 1dp hairline, 10dp in and 4dp apart. */
    private fun showSearchResults(cards: List<BackendClient.SearchCard>) {
        dismissSearchResults()
        dismissLanding()
        val keysHeight = keyboard.height + searchChipsHeight
        searchChipsRow?.visibility = View.GONE
        keyboard.visibility = View.GONE
        searchAbc?.visibility = View.VISIBLE
        relayoutSearchQuery()
        val panel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val scroll = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
        }
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(2), 0, dp(10))
        }
        val theme = SearchCards.Theme(
            ink = Glass.textPrimary, card = Glass.surfaceCard,
            soft = Glass.textSecondary, dp = ::dp, dark = chromeDark)
        val backendURL = settings.optString("backendURL")
        searchResultCount = cards.size
        for ((i, c) in cards.withIndex()) {
            val v = SearchCards.view(this, c, theme, backendURL) { tapped -> insertResult(tapped) }
            v.setTag(com.arpit.glyf.R.id.qa_id, "search:card:$i")
            list.addView(v, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(SearchCards.height(c.kind))).apply {
                setMargins(dp(10), dp(4), dp(10), dp(4))
            })
        }
        // Maps drawn from OpenStreetMap carry its credit, once, under the list.
        if (cards.any { it.thumb?.startsWith("/search/staticmap") == true }) {
            list.addView(TextView(this).apply {
                text = "Maps © OpenStreetMap contributors · Geoapify"
                Glass.style(this, 11f, Glass.REGULAR, Glass.textSecondary)
                gravity = Gravity.CENTER
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(26)))
        }
        scroll.addView(list)
        panel.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(panel, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, keysHeight))
        searchResults = panel
    }

    /** The query sits after ABC while results show, after the tabs otherwise. */
    private fun relayoutSearchQuery() {
        val q = searchQueryView ?: return
        val abcOn = searchAbc?.visibility == View.VISIBLE
        val trackW = dp(35) * 5 + dp(2) * 4 + dp(3) * 2
        val x = dp(34) + trackW + dp(6) + (if (abcOn) dp(46) else 0)
        q.layoutParams = (q.layoutParams as FrameLayout.LayoutParams).apply {
            leftMargin = x
            width = maxOf(dp(60), resources.displayMetrics.widthPixels - dp(40) - dp(6) - x)
        }
    }

    /** A tapped result lands in the host field, formatted per the user's
     *  paste style. Contacts are a bare phone/email, not a link. */
    private fun insertResult(c: BackendClient.SearchCard) {
        // A suggestion is not something to paste — it runs the search.
        if (c.kind == "query") {
            searchQuery = c.title
            renderQuery()
            dismissLanding()
            dismissSearchResults()
            submitSearch()
            return
        }
        val style = settings.optString("pasteStyle", "titleAndLink")
        val text = if (c.kind == "contact") c.url else c.insertText(style)
        currentInputConnection?.commitText(text, 1)
        (getSystemService(android.content.Context.CLIPBOARD_SERVICE)
            as? android.content.ClipboardManager)
            ?.setPrimaryClip(android.content.ClipData.newPlainText("glyf", text))
        notice("Inserted · copied")
    }

    private fun dismissSearchResults() {
        searchResults?.let { root.removeView(it) }
        searchResults = null
        searchChipsRow?.visibility = View.VISIBLE
        keyboard.visibility = View.VISIBLE
        if (searchAbc?.visibility == View.VISIBLE) {
            searchAbc?.visibility = View.GONE
            relayoutSearchQuery()
        }
    }

    /** ABC returns you to suggestions, never to an empty panel. */
    private fun backToLanding() {
        dismissSearchResults()
        showLanding()
    }

    private fun exitSearch() {
        searchActive = false
        dismissLanding()
        dismissSearchResults()
        searchChipsRow?.let { root.removeView(it) }
        searchChipsRow = null
        searchChipsScroll = null
        searchStatusView = null
        searchStrip?.let { root.removeView(it) }
        searchStrip = null
        searchQueryView = null
        searchThumb = null
        searchTabs = emptyList()
        searchAbc = null
        toolbar.visibility = View.VISIBLE
        syncAutoShift()
    }

    // MARK: key handling

    override fun onKey(id: String, char: String?) {
        // The calendar's fields take the letters while one is being typed:
        // New Event's title or invitees, or who a booking is for.
        (featurePanel as? CalendarPanelView)?.typing?.let { f ->
            typeIntoStrip(id, char, f.stripText, { f.setStripText(it) }) { f.endStrip() }
            // A title starts with a capital, then letters are lowercase.
            if (char != null && keyboard.shifted) { keyboard.shifted = false; keyboard.invalidate() }
            return
        }
        // The trade panel's token search takes the letters while it is typed.
        (featurePanel as? TradePanelView)?.typing?.let { f ->
            typeIntoStrip(id, char, f.stripText, { f.setStripText(it) }) { f.endStrip() }
            if (char != null && keyboard.shifted) { keyboard.shifted = false; keyboard.invalidate() }
            return
        }
        // The emoji board's search field takes the letters while it is open.
        emojiBoard?.takeIf { it.searchActive }?.let { board ->
            if (id == "shift" || id.startsWith("mode:")) typeIntoStrip(id, char, "", {}) {}
            else {
                board.type(id, char)
                // A search is lowercase unless asked: shift is one letter's.
                if (char != null && keyboard.shifted) { keyboard.shifted = false; keyboard.invalidate() }
            }
            return
        }
        if (searchActive) {
            typeIntoStrip(id, char, searchQuery, { searchQuery = it; renderQuery(); searchQueryChanged() }) {
                submitSearch()
            }
            return
        }
        if (barActive) {
            typeIntoStrip(id, char, barPrompt, { barPrompt = it; barPromptView?.show(it); styleBarRun() }) {
                runBarPrompt()
            }
            return
        }
        if (vaultEditActive) {
            val onShortcut = vaultShortcutActive
            val current = if (onShortcut) vaultShortcutText else vaultEditText
            val update: (String) -> Unit = { t ->
                if (onShortcut) { vaultShortcutText = t; vaultShortcutView?.show(t) }
                else { vaultEditText = t; vaultEditView?.show(t) }
            }
            typeIntoStrip(id, char, current, update) {
                // A note or what a shorthand types out can run to lines; a
                // shortcut goes on to what it types out; a detail is one
                // line, and return saves it.
                when (vaultDraft) {
                    is VaultDraft.Note -> update(current + "\n")
                    VaultDraft.Shorthand -> if (onShortcut) activateVaultField(shortcut = false) else update(current + "\n")
                    else -> saveVaultEdit()
                }
            }
            return
        }
        val ic = currentInputConnection ?: return
        when {
            char != null -> {
                // A fix this punctuation makes, or one whose punctuation it
                // follows ("teh!?"), stays undoable with the marks after it.
                var punctuation: Char? = null
                var extending: Correction? = null
                if (char.length == 1) {
                    val c = char[0]
                    if (c in WordContext.CORRECTION_BOUNDARIES) {
                        punctuation = c
                        if (lastCorrection?.anchor != null) {
                            extending = undoableCorrection(ic.getTextBeforeCursor(ANCHOR_CHARS, 0)?.toString() ?: "")
                        }
                        // Punctuation ends the word: correct it before the mark lands.
                        commitCurrentWord(ic)
                    } else if (!WordContext.isBoundary(c) || c == '\'' || c == '’') {
                        val current = WordContext.currentWord(ic.getTextBeforeCursor(64, 0)?.toString())
                        if (current != wordTouchesFor) {
                            wordTouches.clear()
                            repeat(current.codePointCount(0, current.length)) { wordTouches.add(null) }
                        }
                        wordTouches.add(keyboard.lastTapOffset)
                        wordTouchesFor = current + char
                    }
                }
                ic.commitText(char, 1)
                punctuation?.let { anchorCorrection(ic, it, extending) }
                if (autoShifted && keyboard.shifted) {
                    keyboard.shifted = false
                    autoShifted = false
                    keyboard.invalidate()
                }
                syncAutoShift()
                scheduleSuggestions()
            }
            id == "delete" -> {
                // Right after a glide, one backspace takes the whole word.
                if (glideBackspace(ic)) return
                val before = ic.getTextBeforeCursor(ANCHOR_CHARS, 0)?.toString() ?: ""
                // After a fix made by punctuation ("the,") backspace deletes as usual.
                val corr = undoableCorrection(before)?.takeIf { it.tail == " " }
                if (corr == null) lastCorrection = null
                if (corr != null) {
                    // Backspace right after a correction puts back what was typed
                    // (and teaches the engine to leave that word alone), the
                    // way Apple's keyboard and the iOS twin do.
                    ic.beginBatchEdit()
                    ic.deleteSurroundingText(corr.replacement.length + 1, 0)
                    ic.commitText(corr.original, 1)
                    ic.endBatchEdit()
                    lastCorrection = null
                    teachUndo(corr)
                } else if (selEnd > selStart && selStart >= 0) {
                    ic.commitText("", 1)   // a selection goes as one piece
                } else {
                    // One whole character: an emoji or a flag is several UTF-16
                    // units, and deleting one unit leaves a broken glyph.
                    val tail = ic.getTextBeforeCursor(16, 0)?.toString() ?: ""
                    val it = java.text.BreakIterator.getCharacterInstance()
                    it.setText(tail)
                    val last = it.last()
                    val prev = it.previous()
                    ic.deleteSurroundingText(if (prev == java.text.BreakIterator.DONE) 1 else last - prev, 0)
                }
                val current = WordContext.currentWord(ic.getTextBeforeCursor(64, 0)?.toString())
                // Backing into a word the engine corrected ("cute" → "cut"):
                // if the original comes back, that correction was a mistake.
                if (current.length >= 2) {
                    recentFixes.filter { it.replacement.startsWith(current, ignoreCase = true) }
                        .forEach { it.touched = true }
                }
                val n = current.codePointCount(0, current.length)
                while (wordTouches.size > n) wordTouches.removeAt(wordTouches.size - 1)
                wordTouchesFor = current
                syncAutoShift()
                scheduleSuggestions()
            }
            id == "space" -> {
                handleSpace(ic)
                translateDraftChanged()
                // Gboard's: "at 5 pm", a space after numbers brings the letters back.
                if (keyboard.mode != Mode.LETTERS) {
                    keyboard.mode = Mode.LETTERS
                    keyboard.rebuild()
                    syncAutoShift()
                }
            }
            id == "newline" -> {
                // Return held where it sends: a line break, nothing sent.
                commitCurrentWord(ic)
                ic.commitText("\n", 1)
                syncAutoShift()
                updateSuggestions()
            }
            id == "return" -> {
                commitCurrentWord(ic)
                // Return may send the message: what it said is the sentence
                // to remember, whatever the strip last saw (PhraseMemory).
                ic.getTextBeforeCursor(400, 0)?.toString()?.takeIf { it.isNotEmpty() }?.let { phraseSeen = it }
                // The field's own action where it has one (go, search, send,
                // done, next), as the key now shows; a new line otherwise.
                val action = returnActionOf(currentInputEditorInfo)
                if (action == 0 || !ic.performEditorAction(action)) ic.commitText("\n", 1)
                syncAutoShift()
                updateSuggestions()
                translateDraftChanged()
            }
            id == "shift" -> {
                keyboard.shiftTapped()
                autoShifted = false
            }
            id == "emojikey" -> showEmojiPanel()
            id.startsWith("mode:") -> {
                keyboard.mode = modeFor(id.removePrefix("mode:"))
                keyboard.rebuild()
            }
        }
    }

    /** The page a mode key opens. On the phone pad, +*# opens its symbols
     *  and 123 goes back to the digits (iOS padRows). */
    private fun modeFor(m: String): Mode = when {
        keyboard.kContext == KContext.PHONE_PAD -> if (m == "+*#") Mode.SYMBOLS1 else Mode.LETTERS
        m == "123" || m == "?123" -> Mode.SYMBOLS1
        m == "#+=" -> Mode.SYMBOLS2
        else -> Mode.LETTERS
    }

    /** The field's return action when the key should do it (go, search,
     *  send, done, next), or 0 for a new line: a field that asks for no
     *  enter action (a message box) gets its new line. */
    private fun returnActionOf(info: EditorInfo?): Int {
        info ?: return 0
        if (info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) return 0
        return when (val action = info.imeOptions and EditorInfo.IME_MASK_ACTION) {
            EditorInfo.IME_ACTION_GO, EditorInfo.IME_ACTION_SEARCH, EditorInfo.IME_ACTION_SEND,
            EditorInfo.IME_ACTION_DONE, EditorInfo.IME_ACTION_NEXT -> action
            else -> 0
        }
    }

    /** Keys typing into one of the keyboard's own strips (search query, bar
     *  instruction, note) instead of the host field. */
    private fun typeIntoStrip(id: String, char: String?, text: String,
                              update: (String) -> Unit, onReturn: () -> Unit) {
        when {
            char != null -> {
                update(text + char)
                // Shift is one letter's, as over the host field (and iOS's
                // KeyboardView): left on, a query came out "COFFEE NEAR ME".
                if (keyboard.shifted) {
                    keyboard.shifted = false
                    autoShifted = false
                    keyboard.invalidate()
                }
            }
            id == "space" -> update("$text ")
            id == "delete" -> update(text.dropLast(1))
            id == "return" -> onReturn()
            id == "shift" -> {
                keyboard.shiftTapped()
                autoShifted = false
            }
            id.startsWith("mode:") -> {
                keyboard.mode = modeFor(id.removePrefix("mode:"))
                keyboard.rebuild()
            }
        }
    }

    // MARK: space bar — cursor glide (Apple trackpad / Gboard swipe)

    /** Absolute cursor during a glide, tracked locally: onUpdateSelection
     *  arrives asynchronously and would lag a fast glide. */
    private var glideCursor = -1
    private var selStart = -1
    private var selEnd = -1

    private var settingsStamp = 0L

    /** The app may change settings while the keyboard is up (its tour does):
     *  a file stamp check, cheap enough for every selection change. */
    private fun reloadSettingsIfChanged() {
        val stamp = com.arpit.glyf.store.Bridge.file(this, SettingsStore.FILE).lastModified()
        if (stamp == settingsStamp) return
        settingsStamp = stamp
        settings = SettingsStore.load(this)
        keyboard.bindings = settings.optJSONObject("bindings")?.let { b ->
            b.keys().asSequence().associateWith { b.optString(it) }
        } ?: emptyMap()
        applyTourHint()
    }

    // MARK: tour coach (the website's, see TourCoach)

    private var coachOverlay: TourCoachOverlay? = null
    private var tourTyping = false
    /** What the keyboard already typed for the tour, so it types it once. */
    private var tourTyped: String? = null
    /** The step during which the calendar was open (the investor's day). */
    private var tourCalendarSeen: String? = null

    /** The app moves the tour along without touching the text, so the
     *  keyboard looks again a few times a second while it is up. */
    private val tourTick = object : Runnable {
        override fun run() {
            if (!::root.isInitialized) return
            reloadSettingsIfChanged()
            applyTourHint()
            main.postDelayed(this, 400)
        }
    }

    private fun tourCopied() =
        settings.optDouble("tourCopiedAt", 0.0) > System.currentTimeMillis() - 10 * 60 * 1000

    private fun tourStep(): String? {
        // A tour closed by force leaves its step behind: only a fresh one counts.
        val fresh = settings.optDouble("tourHintAt", 0.0) > System.currentTimeMillis() - 15 * 60 * 1000
        return settings.optString("tourStep").takeIf { it.isNotBlank() && fresh }
    }

    /** The step the strip was last arranged for. */
    private var coachedStep: String? = null

    private fun applyTourHint() {
        if (!::root.isInitialized || !::keyboard.isInitialized || !::toolIcons.isInitialized) return
        keyboard.tourKey = null
        val arranged = tourStep()?.let { "$it|${tourCopied()}" }
        if (arranged != coachedStep) {
            // A new chat in the tour starts clean: a panel the previous one
            // left open (its search results, say) would sit over the keys.
            val chat = tourStep()?.substringBefore(':')
            val previous = coachedStep?.substringBefore(':')
            if (chat != null && previous != null && chat != previous) dismissFeaturePanel()
            // A new step, or the address just copied, changes which chips
            // the strip may show.
            coachedStep = arranged
            refreshClipCard()
            updateSuggestions()
        }
        val step = tourStep() ?: return clearCoach()
        var state = tourState(step)
        // The investor's day was looked at: the plan can be typed after.
        if (state.panel is TourCoach.Panel.Calendar && tourCalendarSeen != step) {
            tourCalendarSeen = step
            state = state.copy(calendarSeen = true)
        }
        tourAutotype(state)
        val coach = TourCoach.coach(state) ?: return clearCoach()
        val rect = coachRect(coach.target) ?: return clearCoach()
        val overlay = coachOverlay ?: TourCoachOverlay(resources.displayMetrics.density).also {
            coachOverlay = it
            root.overlay.add(it)
        }
        overlay.setBounds(0, 0, root.width, root.height)
        overlay.target = rect
        overlay.label = coach.label
    }

    private fun clearCoach() {
        coachOverlay?.let {
            it.stop()
            root.overlay.remove(it)
        }
        coachOverlay = null
    }

    private fun tourState(step: String): TourCoach.State {
        val ic = currentInputConnection
        val text = (ic?.getTextBeforeCursor(2000, 0)?.toString() ?: "") +
            (ic?.getTextAfterCursor(2000, 0)?.toString() ?: "")
        val bindings = settings.optJSONObject("bindings")
        fun keyFor(target: String) =
            bindings?.keys()?.asSequence()?.sorted()?.firstOrNull { bindings.optString(it) == target }
        return TourCoach.State(
            step = step,
            text = text,
            panel = coachPanel(),
            // A copied address is the paste pill with Send beside it: "pay".
            chip = if (stripChipKind == "smart" || (stripChipKind == "paste" && stripSmartDetail != null))
                stripSmartDetail else stripChipKind,
            suggestions = if (suggestionRow.visibility == View.VISIBLE) suggestionsShown.map { it.text } else emptyList(),
            fields = vaultFields(),
            vaultKey = keyFor("surface:vault"),
            translateKey = keyFor("surface:translate-hud"),
            calendarKey = keyFor("connector:calendar"),
            calendarSeen = tourCalendarSeen == step,
            stripTools = setOf("search", "vault", "translate").filter { findQaView(it) != null }.toSet(),
            copied = tourCopied(),
        )
    }

    private fun coachPanel(): TourCoach.Panel {
        if (searchActive) {
            val view = when {
                searchResults != null -> TourCoach.SearchView.Results(searchResultCount)
                searchStatusView?.text?.toString() == "Searching…" -> TourCoach.SearchView.Loading
                searchLanding != null -> TourCoach.SearchView.Landing(searchLanding?.childCount ?: 0)
                else -> TourCoach.SearchView.Typing
            }
            return TourCoach.Panel.Search(searchTab, view, searchQuery)
        }
        overlay?.let { panel ->
            if (panel.tag != "act") return TourCoach.Panel.Other("act:close")
            return TourCoach.Panel.Act(
                working = findQaView("act:cancel", panel) != null,
                options = findQaView("act:option:*", panel) != null)
        }
        translateStrip?.let { return TourCoach.Panel.Translate(translateResult.isNotEmpty(), translateTarget) }
        if (barActive) return TourCoach.Panel.Other("bar:close")
        if (vaultEditActive) return TourCoach.Panel.Other("vaultedit:close")
        val panel = featurePanel ?: return TourCoach.Panel.None
        return when {
            // The "+" options cover the cards: the × first.
            panel.tag == "vault" -> if (vaultAddOpen) TourCoach.Panel.Other("vault:add") else TourCoach.Panel.Vault
            panel is ToolMenuView -> TourCoach.Panel.Menu
            panel is ClipboardPanelView -> TourCoach.Panel.Other("clip:back")
            panel is CalendarPanelView -> TourCoach.Panel.Calendar(composing = panel.composer != null)
            else -> TourCoach.Panel.Other("panel:back|panel:abc")
        }
    }

    /** Types what the tour needs typed, a letter at a time, the way the
     *  website's keyboard does: the search query, or Sofía's reply. */
    private fun tourAutotype(state: TourCoach.State) {
        if (tourTyping) return
        val panel = state.panel
        if (panel is TourCoach.Panel.Search) {
            val q = TourCoach.searchQuery(state.step) ?: return
            if (panel.tab != TourCoach.searchTab(state.step)) return
            if (panel.view is TourCoach.SearchView.Loading) return
            // Once per step on this tab: the step's own query, replacing
            // whatever an earlier chat left in the box.
            val key = "${state.step}:search:${System.identityHashCode(searchStrip)}:${panel.tab}"
            if (tourTyped == key) return
            tourTyped = key
            if (panel.query == q) return
            if (panel.query.isNotEmpty()) {
                searchQuery = ""
                renderQuery()
                dismissSearchResults()
                showLanding()
            }
            typeForTour(q, { letter ->
                if (searchActive) { searchQuery += letter; renderQuery() }
            })
            return
        }
        val text = TourCoach.autotype(state) ?: return
        val key = "${state.step}:field:${System.identityHashCode(translateStrip)}"
        if (tourTyped == key) return
        tourTyped = key
        typeForTour(text, { letter -> currentInputConnection?.commitText(letter, 1) }) {
            updateSuggestions()
            translateDraftChanged()
        }
    }

    private fun typeForTour(text: String, append: (String) -> Unit, done: (() -> Unit)? = null) {
        tourTyping = true
        val letters = text.map { it.toString() }
        for ((i, letter) in letters.withIndex()) {
            main.postDelayed({
                append(letter)
                if (i == letters.size - 1) {
                    tourTyping = false
                    done?.invoke()
                    applyTourHint()
                }
            }, 350L + i * 45L)
        }
    }

    /** The topmost visible view with this qa id; "prefix*" takes the highest match. */
    private fun findQaView(id: String, from: View = root): View? {
        val prefix = if (id.endsWith("*")) id.dropLast(1) else null
        var best: View? = null
        var bestTop = Int.MAX_VALUE
        val r = android.graphics.Rect()
        fun walk(v: View): Boolean {
            if (v.visibility != View.VISIBLE) return false
            val qa = v.getTag(com.arpit.glyf.R.id.qa_id) as? String
            if (qa != null) {
                if (prefix != null) {
                    if (qa.startsWith(prefix) && v.getGlobalVisibleRect(r) && r.height() > dp(8) && r.top < bestTop) {
                        best = v
                        bestTop = r.top
                    }
                } else if (qa == id && v.getGlobalVisibleRect(r)) {
                    best = v
                    return true
                }
            }
            if (v is android.view.ViewGroup) for (i in 0 until v.childCount) if (walk(v.getChildAt(i))) return true
            return false
        }
        walk(from)
        return best
    }

    /** Where a coach target is, in the keyboard root's coordinates. */
    private fun coachRect(target: String): RectF? {
        val origin = IntArray(2).also { root.getLocationInWindow(it) }
        for (id in target.split("|")) {
            if (id.startsWith("key:")) {
                if (!keyboard.isShown) continue
                val k = keyboard.keyRect(id.removePrefix("key:")) ?: continue
                val loc = IntArray(2).also { keyboard.getLocationInWindow(it) }
                return RectF(k).apply { offset((loc[0] - origin[0]).toFloat(), (loc[1] - origin[1]).toFloat()) }
            }
            val v = findQaView(id) ?: continue
            val r = android.graphics.Rect()
            if (!v.getGlobalVisibleRect(r)) continue
            return RectF(r).apply { offset(-origin[0].toFloat(), -origin[1].toFloat()) }
        }
        return null
    }

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int,
                                   newSelEnd: Int, candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd,
            candidatesStart, candidatesEnd)
        reloadSettingsIfChanged()
        selStart = newSelStart
        selEnd = newSelEnd
        // The cursor moved without a key (a tap in the field): suggest for
        // wherever it landed. Every commit lands here too, so it goes
        // through the same settle as the keys, never a pass per keystroke.
        if (glideCursor < 0 && !searchActive && !barActive && !vaultEditActive) scheduleSuggestions()
    }

    /** How many UTF-16 units the last [count] words before the cursor take,
     *  with the spaces after them. */
    private fun wordsSpan(before: String, count: Int): Int {
        var end = before.length
        repeat(count) {
            var i = end
            while (i > 0 && before[i - 1].isWhitespace()) i--
            while (i > 0 && !before[i - 1].isWhitespace()) i--
            end = i
        }
        return before.length - end
    }

    /** Where a gesture delete started: the cursor, and the text before it. */
    private var deleteAnchor = -1
    private var deleteBefore = ""

    override fun onDeleteWordsPreview(count: Int) {
        val ic = currentInputConnection ?: return
        if (deleteAnchor < 0) {
            if (selEnd < 0) return
            deleteAnchor = selEnd
            deleteBefore = ic.getTextBeforeCursor(2000, 0)?.toString() ?: ""
        }
        val span = wordsSpan(deleteBefore, count)
        ic.setSelection(deleteAnchor - span, deleteAnchor)
        keyboard.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
    }

    override fun onDeleteWordsCommit(count: Int) {
        val ic = currentInputConnection ?: return
        // Whole words slid away: any correction among them was gone back into.
        if (count > 0) recentFixes.forEach { it.touched = true }
        if (deleteAnchor >= 0) {
            val span = wordsSpan(deleteBefore, count)
            ic.setSelection(deleteAnchor, deleteAnchor)
            ic.deleteSurroundingText(span, 0)
        }
        deleteAnchor = -1
        deleteBefore = ""
        syncAutoShift()
        updateSuggestions()
    }

    override fun onCursorGlideBegan() {
        glideCursor = -1
        currentInputConnection?.finishComposingText()
    }

    override fun onCursorMove(graphemes: Int) {
        // In the keyboard's own strips the keys append to our text; there is
        // no host cursor to move.
        if (searchActive || barActive || vaultEditActive) return
        val ic = currentInputConnection ?: return
        val window = 12 * abs(graphemes) + 12
        val before = ic.getTextBeforeCursor(window, 0)
        val after = ic.getTextAfterCursor(window, 0)
        if (before == null || after == null) {
            arrowMove(graphemes) // editor exposes no text (terminals, some web views)
            return
        }
        val units = CursorMath.utf16Distance(graphemes, before.toString(), after.toString())
        // At an edge: send nothing. An arrow key the editor can't consume
        // bubbles up and moves FOCUS to the next view instead.
        if (units == 0) return
        if (glideCursor < 0) glideCursor = glideStart(ic, movingLeft = units < 0)
        if (glideCursor < 0) {
            arrowMove(graphemes)
            return
        }
        glideCursor += units
        ic.setSelection(glideCursor, glideCursor)
    }

    override fun onCursorGlideEnded() {
        glideCursor = -1
        syncAutoShift()
    }

    /** Where the glide starts: collapses a selection the way arrow keys do. */
    private fun glideStart(ic: android.view.inputmethod.InputConnection, movingLeft: Boolean): Int {
        val et = ic.getExtractedText(android.view.inputmethod.ExtractedTextRequest(), 0)
        if (et != null && et.selectionStart >= 0) {
            val a = et.startOffset + et.selectionStart
            val b = et.startOffset + et.selectionEnd
            return if (movingLeft) minOf(a, b) else maxOf(a, b)
        }
        if (selStart >= 0) return if (movingLeft) minOf(selStart, selEnd) else maxOf(selStart, selEnd)
        return -1
    }

    private fun arrowMove(graphemes: Int) {
        val code = if (graphemes < 0) android.view.KeyEvent.KEYCODE_DPAD_LEFT
                   else android.view.KeyEvent.KEYCODE_DPAD_RIGHT
        repeat(abs(graphemes)) { sendDownUpKeyEvents(code) }
    }

    // MARK: Glyf Bar (§6.4) — hold space, let go

    /** What Ask Glyf works on: "field", "clipboard" or "empty". */
    private data class BarInput(val text: String, val source: String)

    private var barActive = false
    private var barPrompt = ""
    private var barStrip: LinearLayout? = null
    private var barPromptView: InlineField? = null
    private var barRunView: FrameLayout? = null
    private var barInput: BarInput? = null
    /** The chips row, once shown, keeps its room while the bar is open:
     *  leaving the text out must not move the keys under the finger (iOS). */
    private var barRowShown = false

    /** Same quick glyfs, same order, same titles as iOS GlyfCatalog. */
    /** The person's own glyfs, one tap each in the bar (as on iOS). */
    private fun myGlyfs(): List<Pair<String, String>> {
        val titles = settings.optJSONObject("customTitles") ?: return emptyList()
        return titles.keys().asSequence().map { it to titles.optString(it) }
            .sortedBy { it.second.lowercase() }.toList()
    }

    override fun onSpaceHoldOpenBar() {
        // A hold inside a strip, or in a password field, is just a space.
        if (searchActive || barActive || vaultEditActive || isSecureField()) {
            onKey("space", null)
            return
        }
        // Typed text is the intent: act on it straight away. An empty field
        // gets the prompt bar instead.
        val ic = currentInputConnection
        val before = ic?.getTextBeforeCursor(2000, 0)?.toString() ?: ""
        val after = ic?.getTextAfterCursor(2000, 0)?.toString() ?: ""
        if ((before + after).isNotBlank()) startAct(before, after) else showGlyfBar()
    }

    private fun isSecureField(): Boolean {
        val type = currentInputEditorInfo?.inputType ?: return false
        val variation = type and InputType.TYPE_MASK_VARIATION
        return when (type and InputType.TYPE_MASK_CLASS) {
            InputType.TYPE_CLASS_TEXT -> variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
            InputType.TYPE_CLASS_NUMBER -> variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
            else -> false
        }
    }

    /** Field text first, else the clipboard, else the prompt runs alone. */
    private fun collectBarInput(): BarInput {
        val ic = currentInputConnection
        val before = ic?.getTextBeforeCursor(2000, 0)?.toString() ?: ""
        val after = ic?.getTextAfterCursor(2000, 0)?.toString() ?: ""
        if ((before + after).isNotBlank()) {
            return BarInput(before + after, "field")
        }
        // The newest copy in Glyf's clipboard, as iOS reads it; what the
        // system holds when that is empty or history is off.
        val kept = if (settings.optBoolean("clipboardHistory", true))
            com.arpit.glyf.store.ClipboardStore.load(this).firstOrNull()?.text else null
        val clip = kept?.takeIf { it.isNotBlank() } ?: com.arpit.glyf.store.ClipboardStore.clipText(this)
        if (!clip.isNullOrBlank()) return BarInput(clip, "clipboard")
        return BarInput("", "empty")
    }

    private fun showGlyfBar() {
        // Already up: a second strip would stack over the first, orphaned.
        if (barActive) return
        removeClipCard()
        dismissOverlay()
        barInput = collectBarInput()
        barActive = true
        barPrompt = ""
        barRowShown = false
        // The prompt starts a sentence: capitals up, as iOS's bar opens.
        if (settings.optBoolean("autocapitalize", true) && keyboard.mode == Mode.LETTERS && !keyboard.shifted) {
            keyboard.shifted = true
            autoShifted = true
            keyboard.invalidate()
        }
        toolbar.visibility = View.GONE
        val strip = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(strip, 0)
        barStrip = strip
        renderBar()
    }

    /** Ask Glyf, iOS's GlyfBar: ✕ in the g key's box, the round prompt with
     *  its sparkle where the tools were (the keys type into it) and the send
     *  arrow inside its end. Under it, only when there is something for it:
     *  the copied text the prompt will work on (tap to leave it out) and the
     *  person's own glyfs. Answers open in the act panel. */
    private fun renderBar() {
        val strip = barStrip ?: return
        strip.removeAllViews()
        val w = resources.displayMetrics.widthPixels
        val rowH = dp(stripDp)
        val row = FrameLayout(this)
        // iOS: the close is the g pill's box, 52 by 34 at 5 in, fillSoft with
        // 10 corners; the prompt starts 6 after it and ends 6 from the edge.
        val boxW = dp(52); val boxH = dp(34)
        val top = (rowH - boxH) / 2
        row.addView(FrameLayout(this).apply {
            background = Glass.card(this@GlyfIME, Glass.fillSoft, radius = 10f)
            setTag(com.arpit.glyf.R.id.qa_id, "bar:close"); contentDescription = "Close"
            addView(ToolIcon(this@GlyfIME, "close", Glass.textPrimary).apply {
                solid = true; weight = 1.9f; scale = 1.15f
            }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            setOnClickListener { exitBar() }
        }, FrameLayout.LayoutParams(boxW, boxH).apply { leftMargin = dp(5); topMargin = top })
        val left = dp(5) + boxW + dp(6)
        val fieldW = maxOf(dp(80), w - left - dp(6))
        val runD = boxH - dp(6)
        val prompt = InlineField(this, "Ask Glyf", "ask").apply {
            radiusDp = 17f
            trailingDp = 38f
            active = true
            show(barPrompt)
            setTag(com.arpit.glyf.R.id.qa_id, "bar:prompt"); contentDescription = "Ask Glyf"
        }
        row.addView(prompt, FrameLayout.LayoutParams(fieldW, boxH).apply {
            leftMargin = left; topMargin = top
        })
        val run = FrameLayout(this).apply {
            setTag(com.arpit.glyf.R.id.qa_id, "bar:run"); contentDescription = "Ask"
            addView(ToolIcon(this@GlyfIME, "arrowup", Glass.textSecondary).apply {
                solid = true; weight = 2.3f; scale = 0.74f
            }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            setOnClickListener { runBarPrompt() }
        }
        row.addView(run, FrameLayout.LayoutParams(runD, runD).apply {
            leftMargin = left + fieldW - runD - dp(3); topMargin = top + (boxH - runD) / 2
        })
        strip.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, rowH))
        barPromptView = prompt
        barRunView = run
        styleBarRun()

        // iOS's chips: 32 tall on the key colour, 16 corners, 6 apart from 6 in.
        val chips = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val input = barInput
        val context = input?.text?.trim().orEmpty()
        if (input != null && input.source != "empty" && context.isNotEmpty()) {
            val copied = input.source == "clipboard"
            chips.addView(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(11), 0, dp(11), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "bar:context")
                contentDescription = if (copied) "Copied text, tap to leave it out"
                    else "Your text, tap to leave it out"
                background = Glass.pill(Glass.surfaceCard)
                addView(ToolIcon(this@GlyfIME, if (copied) "clipboard" else "edit", Glass.accentPrimary).apply {
                    solid = true; weight = 1.9f; scale = 0.72f
                }, LinearLayout.LayoutParams(dp(16), dp(16)))
                addView(TextView(this@GlyfIME).apply {
                    text = "“${barPreview(context)}”"
                    Glass.style(this, 13f)
                    maxLines = 1
                    maxWidth = dp(200)
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(6); rightMargin = dp(8) })
                addView(ToolIcon(this@GlyfIME, "close", Glass.textSecondary).apply {
                    solid = true; weight = 2.1f; scale = 0.72f
                }, LinearLayout.LayoutParams(dp(12), dp(12)))
                setOnClickListener {
                    // Leave the copied text out: the prompt runs on its own.
                    barInput = BarInput("", "empty")
                    renderBar()
                }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply { rightMargin = dp(6) })
        }
        for ((glyfId, title) in myGlyfs()) {
            chips.addView(TextView(this).apply {
                text = title
                Glass.style(this, 13.5f, Glass.SEMIBOLD)
                gravity = Gravity.CENTER
                setPadding(dp(13), 0, dp(13), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "chip:$glyfId")
                background = Glass.pill(Glass.surfaceCard)
                setOnClickListener { runFromBar(glyfId, emptyMap(), title) }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply { rightMargin = dp(6) })
        }
        if (chips.childCount > 0 || barRowShown) {
            barRowShown = true
            strip.addView(android.widget.HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                overScrollMode = View.OVER_SCROLL_NEVER
                clipToPadding = false
                // iOS: the chips 2 above the row's middle.
                setPadding(dp(6), 0, dp(6), dp(4))
                addView(chips, FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.MATCH_PARENT))
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(44)))
        }
    }

    /** The send arrow: the ink once there is something to ask, else the
     *  field grey with a grey arrow (iOS). */
    private fun styleBarRun() {
        val run = barRunView ?: return
        val ready = barPrompt.isNotBlank()
        run.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(if (ready) Glass.textPrimary else Glass.fillField)
        }
        (run.getChildAt(0) as? ToolIcon)?.apply {
            setTint(if (!ready) Glass.textSecondary else if (Glass.dark) Glass.brandInk else Color.WHITE)
            solid = true
        }
    }

    /** One line of the context, short enough for its chip. */
    private fun barPreview(text: String): String {
        val flat = text.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        return if (flat.length > 30) flat.take(30) + "…" else flat
    }

    private fun runBarPrompt() {
        val p = barPrompt.trim()
        if (p.isEmpty()) return
        runFromBar("custom.prompt", mapOf("prompt" to p), p)
    }

    /** A bar run plays out like a held key's skill in the act panel: working,
     *  the answer, Insert (swapping the field text it read; copied text only
     *  adds). */
    private fun runFromBar(glyfId: String, vars: Map<String, String>, title: String) {
        val input = barInput ?: return
        exitBar()
        actSkill = glyfId to ""
        actSkillTitle = title
        actVars = vars
        actIntent = null
        if (input.source == "field") {
            val ic = currentInputConnection
            actBefore = ic?.getTextBeforeCursor(2000, 0)?.toString() ?: ""
            actAfter = ic?.getTextAfterCursor(2000, 0)?.toString() ?: ""
        } else {
            actBefore = ""
            actAfter = ""
        }
        actRunInput = input.text
        runAct()
    }

    private fun exitBar() {
        barActive = false
        barPrompt = ""
        barStrip?.let { root.removeView(it) }
        barStrip = null
        barPromptView = null
        barRunView = null
        toolbar.visibility = View.VISIBLE
        syncAutoShift()
    }

    // MARK: Copied-text card (Acti's copied context, Glyf's way)

    private val clipListener = android.content.ClipboardManager.OnPrimaryClipChangedListener {
        main.post { refreshClipCard() }
    }
    private val imePrefs by lazy { getSharedPreferences("glyf_ime", MODE_PRIVATE) }

    /** A copy from the last 10 minutes waits above the toolbar, quoted —
     *  tap to act on it, ✕ to dismiss it for good. The default IME may read
     *  the clipboard, so Android can show the text straight away. */
    /** Something was copied a moment ago and nothing is typed yet: it rides
     *  in the strip as one chip, text on the left and Paste on the right, the
     *  way Gboard offers a fresh copy and the way iOS does it. Never a second
     *  row above the keyboard. */
    /** Vault kinds the model may see when asked to write or fill something
     *  (iOS BackendClient.shareableKinds), only while "Let AI use your saved
     *  details" is on, and never before the person has answered "What Glyf
     *  sends" in the app. Anything secret-shaped never reaches the vault. */
    private fun shareableProfile(): Map<String, String>? {
        if (!settings.optBoolean("aiUsesVault", true) || !settings.has("aiConsent")) return null
        // Since 14 Oct 2026 each saved detail goes as a stand-in ("work email":
        // "{work email}"), never its value; StandIns.fill puts the value back
        // into what the AI wrote, on the phone (iOS twin).
        return StandIns.table(vaultFields()).keys.take(40).associateWith { "{$it}" }.ifEmpty { null }
    }

    /** What the AI wrote, with saved details in place of their stand-ins. */
    private fun withDetails(text: String): String = StandIns.fill(text, StandIns.table(vaultFields()))

    private var vaultFieldsStamp = -1L
    private var vaultFieldsCache: List<Smart.Field> = emptyList()

    /** Decrypting the vault on every keystroke is wasted work: reread it only
     *  when the file changed. */
    private fun vaultFields(): List<Smart.Field> {
        val stamp = com.arpit.glyf.store.Bridge.file(this, "vault.enc").lastModified()
        if (stamp != vaultFieldsStamp) {
            vaultFieldsCache = Smart.fields(VaultStore.load(this))
            vaultFieldsStamp = stamp
        }
        seedOwnNames(vaultFieldsCache)
        return vaultFieldsCache
    }

    /** The person's own names are words to the engine, whatever the
     *  dictionary makes of them ("hi arpit" offered armpit; iOS 10-07). The
     *  vault's details that are names too (first and last name, company,
     *  city, state) are never autocorrected (2026-11-04, iOS twin). */
    private var seededNames: Set<String> = emptySet()
    /** The vault read last seeded (vaultFields runs on every keystroke). */
    private var seededFrom: List<Smart.Field>? = null
    private fun seedOwnNames(fields: List<Smart.Field>) {
        val engine = KeyboardTyping.engine ?: return
        if (fields === seededFrom) return
        seededFrom = fields
        fun words(values: List<String>): Set<String> = values
            .flatMap { it.split(Regex("""[^\p{L}'-]+""")) }
            .filter { it.length >= 2 }.toSet()
        val names = words(fields.filter { it.kind == "name" }.map { it.value })
        val details = words(listOf("givenName", "familyName", "company", "city", "state")
            .flatMap { kind -> Smart.detailsFor(kind, fields).map { it.value } })
        engine.setOwnNames((names + details).sorted())
        if (names == seededNames) return
        for (name in names - seededNames) engine.keep(name)
        seededNames = names
        KeyboardTyping.scheduleSave(this)
    }

    private var suggestedChip: Smart.Chip.Action? = null
    /** A saved detail the model says the sentence is leading into. */
    private var suggestedDetail: Smart.Field? = null
    private var suggestedFor = ""
    /** What Glyf itself just wrote into the field (a rewrite, an answer):
     *  offering to tidy that up would be asking about its own work. */
    private var glyfWrote = ""
    private var suggestCancel: (() -> Unit)? = null
    private val suggestWork = Runnable { askForSuggestion() }

    /** The website's smart strip: a sum just typed, the saved detail the
     *  sentence asks for, a payment address, a plan, a booking page, or what
     *  the model says Glyf could do with the sentence. One chip, which owns
     *  the strip. True when shown. */
    private fun updateSmartChip(before: String): Boolean {
        val smartKinds = setOf("smart", "pay", "buy", "action", "event", "booking", "trade")
        if (searchActive || barActive || vaultEditActive || overlay != null || featurePanel != null ||
            isSecureField() || translateStrip != null) {
            if (stripChipKind in smartKinds) hideStripChip()
            return false
        }
        val tail = before.takeLast(120)
        notePhrases(before)
        // Where the phone last was, for sunrise and sunset (the app shares it).
        if (settings.has("lastLat") && settings.has("lastLon"))
            SunAnswer.lastLocation = settings.optDouble("lastLat") to settings.optDouble("lastLon")
        val region = settings.optString("region").ifEmpty { java.util.Locale.getDefault().country }
        val rates = RatesStore.snapshot(region, settings.optString("moneyCurrency"))
        val ownWallet = settings.optString("walletAddress").ifEmpty { null }
        var chip = Smart.chip(tail, vaultFields(), indianGrouping = region == "IN", rates = rates,
                              ownBooking = settings.optString("bookingLink"), ownWallet = ownWallet,
                              region = region, linkContext = before.takeLast(2048))
        // The person's own shorthand of the same name wins over ";date".
        (chip as? Smart.Chip.Convert)?.answer?.source?.takeIf { it in Smart.builtInShortcuts }?.let { token ->
            val snippets = VaultStore.load(this).optJSONArray("snippets")
            if (snippets != null && (0 until snippets.length()).any { snippets.getJSONObject(it).optString("trigger") == token }) {
                chip = null
            }
        }
        // An address on screen: a wallet (Send) or a token (Buy)? Only a
        // lookup can tell; the strip is arranged again when it lands.
        // Without the wallet on, nothing to send or buy: a price is only a price.
        if (!walletOn) chip = when (val c = chip) {
            is Smart.Chip.Pay, is Smart.Chip.Buy, is Smart.Chip.Trade -> null
            is Smart.Chip.Money -> c.copy(buy = null)
            else -> c
        }
        if (chip == null && walletOn) Smart.addressToCheck(tail, rates, ownWallet)?.let {
            RatesStore.ensureAddress(settings.optString("backendURL"), it) { updateSuggestions() }
        }
        // A send to a .sol name: its address first (NameSend).
        if (chip == null && walletOn) NameSend.parse(tail)?.let {
            NameSend.ensure(settings.optString("backendURL"), it.name) { updateSuggestions() }
        }
        // An amount or a ticker with no rate yet: ask for one; the strip is
        // arranged again when it lands.
        // A character test first: neither pattern can match without one, and
        // this runs on text that is usually just words.
        if (chip == null && tail.any { it == '$' || it.isDigit() }) {
            val backendURL = settings.optString("backendURL")
            val ticker = if (tail.contains('$')) Smart.cashtag(tail) else null
            if (ticker != null) {
                RatesStore.ensureToken(backendURL, ticker) { updateSuggestions() }
                RatesStore.ensureFiat(backendURL) { updateSuggestions() }
            } else if (Smart.coinAmount(tail) != null) {
                RatesStore.ensureToken(backendURL, Smart.coinAmount(tail)!!.third) { updateSuggestions() }
            } else if (tail.any { it.isDigit() } && (Smart.looksLikeMoney(tail) || Smart.currencyPair(tail) != null)) {
                RatesStore.ensureFiat(backendURL) { updateSuggestions() }
            }
        }
        // Nothing in the words, but the model heard the sentence asking for a detail.
        val detail = suggestedDetail
        if (chip == null && detail != null && suggestedFor == tail.trim()) chip = Smart.Chip.Vault(detail)
        // Your emails, with a temp address beside them, wherever one is asked
        // for (Arpit, 2026-10-01: "i should also see a temp mail option").
        // Android has no Full Access to wait for, as the email field's own
        // temp address chip never did.
        chip = Smart.withTempMail(chip)
        // The weather where the phone is (Open-Meteo, keyless): "is it going
        // to rain", "weather tomorrow"; asked for when the question shows.
        if (chip == null && Weather.ask(tail) != null && settings.has("lastLat") && settings.has("lastLon")) {
            val fahrenheit = region.uppercase() in setOf("US", "LR", "MM", "BS", "BZ", "KY", "PW")
            Weather.ensure(settings.optDouble("lastLat"), settings.optDouble("lastLon"), fahrenheit) { main.post { updateSuggestions() } }
            Weather.snapshot?.takeIf { it.fahrenheit == fahrenheit }?.let { w -> Weather.answer(tail, w)?.let { chip = Smart.Chip.Convert(it) } }
        }
        // A sentence the person keeps sending offers its next word in the
        // word slots (updateSuggestions), not the rest of it as a chip (D108).
        // The tour keeps the strip for the step it is coaching.
        val step = tourStep()
        if (step != null) {
            // One tap on the chip is what the coach asks for: the first value.
            // A detail's first letters offer nothing mid-tour: the chats type
            // their own words.
            if (chip is Smart.Chip.Details) chip = if (chip.typed.isNotEmpty()) null
                else chip.fields.firstOrNull()?.let { Smart.Chip.Vault(it) }
            val kind = when (chip) {
                is Smart.Chip.Calc -> "calc"
                is Smart.Chip.Money -> "money"
                is Smart.Chip.Vault -> "vault:${chip.field.kind}"
                is Smart.Chip.Details -> "vault:${chip.fields.firstOrNull()?.kind.orEmpty()}"
                is Smart.Chip.Convert -> "convert"
                is Smart.Chip.Pay -> "pay"
                is Smart.Chip.Buy -> "buy"
                is Smart.Chip.Action -> "action"
                is Smart.Chip.Event -> "event"
                is Smart.Chip.Booking -> "booking"
                is Smart.Chip.Trade -> "trade"
                null -> null
            }
            if (kind != null && !TourCoach.allowsChip(kind, step, tourCopied())) chip = null
            if (chip == null) {
                if (stripChipKind in smartKinds) hideStripChip()
                return false
            }
        }
        if (chip != null) cancelSuggestion()
        when (chip) {
            is Smart.Chip.Calc, is Smart.Chip.Vault, is Smart.Chip.Money -> {
                stripSmartDetail = when (chip) {
                    is Smart.Chip.Vault -> "vault:${chip.field.kind}"
                    is Smart.Chip.Money -> "money"
                    else -> "calc"
                }
                // A token's price can be bought, too: Buy beside Insert.
                val mint = (chip as? Smart.Chip.Money)?.buy
                // "1 SOL = $121.39": the ticker and its price, off the chip.
                val shown = (chip as? Smart.Chip.Money)?.shown?.split(" ")
                return showStripChip("smart", Smart.key(chip), Smart.display(chip), Smart.verb(chip) ?: "",
                    extra = if (mint != null) "Buy" else null,
                    onExtra = {
                        hideStripChip()
                        // A share Base has ($apple): bought there with USDC, on Uniswap (android-trade).
                        val share = shown?.getOrNull(1)?.let { TradeIntent.baseStock(it) }
                        val onBase = share?.let { TradeIntent.parse("buy \$10 of ${it.lowercase()} on base") }
                        if (onBase != null) showTradePanel(onBase)
                        else if (mint != null) showPayPanel(PayPanelView.Intent.Buy(
                            mint, shown?.getOrNull(1) ?: "", shown?.getOrNull(3)))
                    }) {
                    val ic = currentInputConnection
                    // A saved detail after "email" or "my number is", with a space between.
                    ic?.commitText(if (chip is Smart.Chip.Vault)
                        Smart.spaced(chip.field.value, ic.getTextBeforeCursor(1, 0)?.toString())
                        else Smart.insert(chip), 1)
                    hideStripChip()
                    updateSuggestions()
                }
            }
            is Smart.Chip.Convert -> {
                stripSmartDetail = "convert"
                val a = chip.answer
                return showChoiceRow("smart", a.results, temp = false, onIndex = { i ->
                    val ic = currentInputConnection
                    val text = a.insert(i)
                    when (a.how(i)) {
                        // "10 inch" → "10 inch (25.4 cm)": the answer after what was typed.
                        Smart.Insertion.BRACKET ->
                            ic?.commitText(Smart.conversionInsert(text, ic.getTextBeforeCursor(1, 0)?.toString()), 1)
                        // A link after the number.
                        Smart.Insertion.AFTER -> ic?.commitText(Smart.spaced(text, ic.getTextBeforeCursor(1, 0)?.toString()), 1)
                        // ";date" → the date: what was typed goes, the answer stays.
                        Smart.Insertion.REPLACE -> {
                            val before = ic?.getTextBeforeCursor(a.source.length + 1, 0)?.toString().orEmpty()
                            val space = if (before.endsWith(" ")) " " else ""
                            if (a.source.isNotEmpty() && (before.endsWith(a.source) || before.endsWith(a.source + " "))) {
                                ic?.deleteSurroundingText(a.source.length + space.length, 0)
                                ic?.commitText(text + space, 1)
                            } else {
                                ic?.commitText(Smart.spaced(text, before), 1)
                            }
                        }
                    }
                    // A coin, a die or a pick that was used: the next one is a new draw.
                    Smart.luck = kotlin.random.Random.nextLong().toULong() or 1UL
                    hideStripChip()
                    updateSuggestions()
                }, onTemp = {})
            }
            is Smart.Chip.Details -> {
                stripSmartDetail = "vault:${chip.fields.firstOrNull()?.kind.orEmpty()}"
                // A part types its value, as its own vault chip would; Temp
                // mail types a temp address, as the email field's chip does.
                return showDetailsChip("smart", chip, onValue = { field ->
                    val ic = currentInputConnection
                    if (chip.typed.isNotEmpty()) {
                        // Its start is typed already: the whole detail takes its place.
                        ic?.deleteSurroundingText(chip.typed.length, 0)
                        ic?.commitText(field.value, 1)
                    } else {
                        ic?.commitText(Smart.spaced(field.value, ic.getTextBeforeCursor(1, 0)?.toString()), 1)
                    }
                    hideStripChip()
                    updateSuggestions()
                }, onTemp = {
                    hideStripChip()
                    insertTempAddress()
                })
            }
            is Smart.Chip.Event -> {
                // Nothing is typed: the plan becomes a New Event to check and add.
                return showStripChip("event", null, Smart.display(chip), "Add", lead = "calendar") {
                    hideStripChip()
                    showCalendarPanel().compose(chip.plan)
                }
            }
            is Smart.Chip.Booking -> {
                // Their page's open times, to book one as the person.
                return showStripChip("booking", null, Smart.display(chip), "Book", lead = "calendar") {
                    hideStripChip()
                    showCalendarPanel().openBooking(chip.link)
                }
            }
            // The keyboard never signs: Send and Buy open in the app, which
            // has Phantom sign.
            is Smart.Chip.Pay -> {
                // A name that points nowhere: said, and nothing to send.
                if (chip.problem != null) {
                    return showStripChip("pay", Smart.key(chip), Smart.display(chip), Smart.verb(chip) ?: "OK") {
                        hideStripChip()
                    }
                }
                return showStripChip("pay", Smart.key(chip), Smart.display(chip), "Send") {
                    hideStripChip()
                    if (tourStep() != null) {
                        openAppPath("wallet", sendQuery(chip.address, chip.amount, chip.token))
                    } else {
                        showPayPanel(PayPanelView.Intent.Send(chip.address, chip.amount, chip.token))
                    }
                }
            }
            is Smart.Chip.Buy -> {
                return showStripChip("buy", Smart.key(chip), Smart.display(chip), "Buy") {
                    hideStripChip()
                    showPayPanel(PayPanelView.Intent.Buy(chip.mint, chip.symbol, chip.price))
                }
            }
            // A trade said in words: its panel over the keys, which only
            // quotes; MetaMask or Phantom signs in the app (android-trade).
            is Smart.Chip.Trade -> return showTradeChip(chip)
            else -> {}
        }
        // Talk of a call: a Google Meet link where it's wanted, only with
        // Meet connected (iOS 10-07).
        if (Smart.asksToCall(tail) && com.arpit.glyf.store.GoogleAccess.hasMeet(this)) {
            cancelSuggestion()
            val shown = showStripChip("action", null, "Add a Meet link", "") {
                hideStripChip()
                insertMeetLink()
            }
            if (shown) return true
        }
        val trimmed = tail.trim()
        // A question for a fact shows "AI answer" as it is typed (Arpit,
        // 2026-09-30: "we can detect questions too with what where like
        // words"), with no wait for the server's read (iOS Smart.question).
        // iOS asks for Full Access first; an Android keyboard always has
        // the network. A tap answers it as the server's AI answer chip does;
        // its ✕ keeps it away for these words.
        val question = if (settings.optBoolean("candidates", true)) Smart.question(tail) else null
        if (question != null) {
            cancelSuggestion()
            val shown = showStripChip("action", null, "AI answer", "", policyKey = question) {
                hideStripChip()
                val ic = currentInputConnection
                startAct(ic?.getTextBeforeCursor(4000, 0)?.toString() ?: "",
                    ic?.getTextAfterCursor(4000, 0)?.toString() ?: "", "answer")
            }
            if (!shown && stripChipKind in smartKinds) hideStripChip()
            return shown
        }
        // A tool the model named, filled in (AIAction; android-trade).
        val recommended = suggestedAction
        if (recommended != null && suggestedFor == trimmed) showRecommended(recommended)?.let { return it }
        val cached = suggestedChip
        if (cached != null && suggestedFor == trimmed) {
            return showStripChip("action", null, cached.label, "", policyKey = cached.intent + "|" + cached.query) {
                suggestedChip = null
                suggestedAction = null
                suggestedFor = ""
                hideStripChip()
                val ic = currentInputConnection
                startAct(ic?.getTextBeforeCursor(4000, 0)?.toString() ?: "",
                    ic?.getTextAfterCursor(4000, 0)?.toString() ?: "", cached.intent)
            }
        }
        if (stripChipKind in smartKinds) hideStripChip()
        scheduleSuggestion(trimmed)
        return false
    }

    /** Debounced and never for a half-typed thought: a 700ms pause on a real
     *  sentence is the only thing that asks. It never spends a run:
     *  suggestions have their own allowance on the server. */
    private fun scheduleSuggestion(text: String) {
        main.removeCallbacks(suggestWork)
        // Only once the person agreed to it ("What Glyf sends" in the app).
        if (text.length < 12 || text.split(" ").size < 3 || text == suggestedFor ||
            (glyfWrote.isNotEmpty() && text.trim().endsWith(glyfWrote)) ||
            !settings.optBoolean("candidates", true) || !settings.optBoolean("aiSuggest", false) ||
            incognitoField()) return
        main.postDelayed(suggestWork, 700)
    }

    /** A field that asks for no learning: an incognito tab, a private note.
     *  Nothing typed there goes to the server unasked. */
    private fun incognitoField(): Boolean =
        (currentInputEditorInfo?.imeOptions ?: 0) and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING != 0

    private fun askForSuggestion() {
        if (incognitoField()) return
        val ic = currentInputConnection ?: return
        val text = (ic.getTextBeforeCursor(120, 0)?.toString() ?: "").trim()
        if (text.length < 12) return
        suggestCancel?.invoke()
        val fields = vaultFields()
        suggestCancel = BackendClient.suggestAction(
            backendURL = settings.optString("backendURL"),
            text = text,
            deviceId = settings.optString("deviceId"),
            kinds = if (settings.optBoolean("aiUsesVault", true)) fields.map { it.kind }.distinct() else emptyList(),
            onAction = { action -> main.post { takeRecommended(text, action) } },
        ) { intent, label, query -> main.post {
            val now = (currentInputConnection?.getTextBeforeCursor(120, 0)?.toString() ?: "").trim()
            // The sentence moved on while we were asking: drop it.
            if (now != text) return@post
            suggestedFor = text
            suggestedAction = null
            if (intent == "detail") {
                // The model named the kind; the value is this phone's own.
                suggestedDetail = fields.firstOrNull { it.kind == label } ?: return@post
                suggestedChip = null
            } else {
                suggestedDetail = null
                suggestedChip = Smart.Chip.Action(label, query, intent)
            }
            updateSuggestions()
        } }
    }

    private fun cancelSuggestion() {
        main.removeCallbacks(suggestWork)
        suggestCancel?.invoke()
        suggestCancel = null
    }

    private fun refreshClipCard() {
        if (!::root.isInitialized || !::toolIcons.isInitialized) return
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val stamp = cm.primaryClipDescription?.timestamp ?: 0L
        val text = com.arpit.glyf.store.ClipboardStore.clipText(this)?.trim().orEmpty()
        // The parity shots hold the clipboard as seeded (debug "cliphold"):
        // what the Mac copies meanwhile must not put a paste chip in them.
        val busy = searchActive || barActive || vaultEditActive || overlay != null ||
            featurePanel != null || isSecureField() || qaClipHeld
        val fresh = stamp > 0 && System.currentTimeMillis() - stamp < (StripPolicy.PASTE_FRESH * 1000).toLong() &&
            stamp != imePrefs.getLong("clipDone", -1)
        val typed = currentInputConnection?.getTextBeforeCursor(1, 0)?.isNotEmpty() == true
        val tourBlocks = tourStep()?.let { !TourCoach.allowsChip("paste", it, tourCopied()) } == true
        if (busy || !fresh || text.isEmpty() || typed || tourBlocks ||
            com.arpit.glyf.store.SecretScanner.scan(text) != null) {
            if (stripChipKind == "paste") hideStripChip()
            return
        }
        // Used or waved off (the ✕), a copy is done: only a new one comes back.
        val used = { imePrefs.edit().putLong("clipDone", stamp).apply() }
        val dismiss = { used(); hideStripChip() }
        // A copied address is still pasted by a tap; Send (a wallet) or Buy
        // (a token) sits beside it. Nothing until the lookup says which.
        val address = Smart.payment(text)?.first?.takeIf { walletOn && it != settings.optString("walletAddress") }
        if (address != null) {
            val paste = {
                used()
                currentInputConnection?.commitText(text, 1)
                hideStripChip()
            }
            when (val kind = RatesStore.addressKind(address)) {
                null -> {
                    RatesStore.ensureAddress(settings.optString("backendURL"), address) { refreshClipCard() }
                    if (stripChipKind == "paste") hideStripChip()
                }
                is Smart.AddressKind.Token -> {
                    stripSmartDetail = "buy"
                    showStripChip("paste", kind.symbol, kind.usd?.let { Smart.price(it) } ?: Smart.shortAddress(address),
                        "Paste", extra = if (kind.buy) "Buy" else null, onExtra = {
                            used()
                            hideStripChip()
                            showPayPanel(PayPanelView.Intent.Buy(address, kind.symbol, kind.usd?.let { Smart.price(it) }))
                        }, onClose = dismiss) { paste() }
                }
                Smart.AddressKind.Wallet -> {
                    val asked = Smart.amountAsked(text)
                    stripSmartDetail = "pay"
                    showStripChip("paste", "Wallet", Smart.shortAddress(address), "Paste", extra = "Send", onExtra = {
                        used()
                        hideStripChip()
                        if (tourStep() != null) {
                            openAppPath("wallet", sendQuery(address, asked?.first, asked?.second))
                        } else {
                            showPayPanel(PayPanelView.Intent.Send(address, asked?.first, asked?.second))
                        }
                    }, onClose = dismiss) { paste() }
                }
            }
            return
        }
        stripSmartDetail = null
        // Someone's booking page, just copied: book it instead of pasting it.
        val booking = Smart.bookingLink(text, settings.optString("bookingLink"))
        if (booking != null) {
            showStripChip("paste", null, Smart.display(Smart.Chip.Booking(booking)), "Book", lead = "calendar",
                onClose = dismiss) {
                used()
                hideStripChip()
                showCalendarPanel().openBooking(booking)
            }
            return
        }
        // A copied link with trackers: clean, or as it was copied.
        Smart.cleanCopy(text)?.let { clean ->
            stripSmartDetail = "pieces"
            showChoiceRow("paste", listOf("Paste clean link", "Paste as copied"), temp = false, onIndex = { i ->
                used()
                val ic = currentInputConnection
                ic?.commitText(Smart.spaced(if (i == 0) clean else text, ic.getTextBeforeCursor(1, 0)?.toString()), 1)
                hideStripChip()
            }, onTemp = {}, onClose = dismiss)
            return
        }
        // A copy with emails, links or numbers in it: the whole, then each
        // (Gboard's paste chips).
        Smart.pieces(text)?.let { parts ->
            val all = listOf(text) + parts
            stripSmartDetail = "pieces"
            showChoiceRow("paste", listOf("Paste all") + parts, temp = false, onIndex = { i ->
                used()
                val ic = currentInputConnection
                ic?.commitText(Smart.spaced(all[i], ic.getTextBeforeCursor(1, 0)?.toString()), 1)
                hideStripChip()
            }, onTemp = {}, onClose = dismiss)
            return
        }
        showStripChip("paste", null, text.replace('\n', ' '), "Paste", onClose = dismiss) {
            used()
            currentInputConnection?.commitText(text, 1)
            hideStripChip()
        }
    }

    /** Send's link: who to, and the amount the message asked for. */
    private fun sendQuery(to: String, amount: String?, token: String?): Map<String, String> = buildMap {
        put("to", to)
        amount?.let { put("amount", it) }
        token?.let { put("token", it) }
    }

    private fun removeClipCard() {
        if (stripChipKind == "paste") hideStripChip()
    }

    private var stripChip: View? = null
    private var stripChipKind: String? = null
    /** What a "smart" chip holds, for the tour's coach: "calc" or "vault:<kind>". */
    private var stripSmartDetail: String? = null

    /** One chip across the strip: first a ✕ that waves it off, in the same
     *  place on every chip (Arpit, 2026-09-30: "we should add some button to
     *  dismiss it"), then the content, and the action last on the right. A
     *  chip waved off stays away for the same words; typing on brings chips
     *  again. [onClose] is the paste chip's own way off (that copy stays
     *  done). False when this chip was waved off for these words: not shown. */
    private fun showStripChip(kind: String, label: String?, value: String, verb: String,
                              lead: String? = null, extra: String? = null, onExtra: (() -> Unit)? = null,
                              onClose: (() -> Unit)? = null, policyKey: String? = null,
                              onTap: () -> Unit): Boolean {
        if (!policyAllows(kind, value, policyKey)) return false
        // The chip's purple, lighter so it reads on the card (Arpit,
        // 2026-09-30: "insert button text etc to be lighter colour purple so
        // it doesnt look unreadable"): over 3:1 in bold on either card.
        val accent = stripAccent()
        val secondary = chipSecondary()
        // Room is measured from the border's inner edge, 1.5dp in: the verb
        // ends 16dp inside it (an extra pill, 12dp).
        val density = resources.displayMetrics.density
        fun px(dp: Float) = Math.round(dp * density)
        val endPad = when {
            extra != null && onExtra != null -> 1.5f + 12f
            // The sparkle, at iOS's size (0.8 of the tools'), ends 4.8dp
            // inside its 22dp box.
            verb.isEmpty() -> 1.5f + 16f - 4.8f
            else -> 1.5f + 16f
        }
        val chip = chipCard(kind, endPad, onClose) ?: return false
        // A tap anywhere but the ✕ does the verb.
        chip.setOnClickListener { com.arpit.glyf.store.Funnel.mark(this, "first_answer"); policyUsed(); onTap() }
        // A lead glyph's ink sits 1.6dp inside its box; words start on their edge.
        val lead0 = px(10f - 1.6f)
        val text0 = px(10f)
        if (lead != null) chip.addView(ToolIcon(this, lead, accent).apply { solid = true },
            LinearLayout.LayoutParams(dp(18), dp(18)).apply { leftMargin = lead0; rightMargin = dp(6) })
        if (label != null) chip.addView(TextView(this).apply {
            text = label
            textSize = 13f
            setTextColor(secondary)
            setPadding(0, 0, dp(8), 0)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT).apply { if (lead == null) leftMargin = text0 })
        chip.addView(TextView(this).apply {
            text = value
            textSize = 15f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(ink())
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            if (lead == null && label == null) leftMargin = text0
        })
        if (verb.isEmpty()) {
            // The model's suggestion: its words are the action, a sparkle marks it.
            chip.addView(ToolIcon(this, "ask", accent).apply { solid = true; scale = 0.8f },
                LinearLayout.LayoutParams(dp(22), dp(22)).apply { leftMargin = dp(8) })
        } else chip.addView(TextView(this).apply {
            text = verb
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(accent)
            setPadding(dp(10), 0, 0, 0)
        })
        // A second action, as a small button, 10dp after the verb: Buy beside
        // a price, Send or Buy beside a copied address.
        if (extra != null && onExtra != null) chip.addView(TextView(this).apply {
            text = extra
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(accent)
            setPadding(dp(12), 0, dp(12), 0)
            background = GradientDrawable().apply {
                cornerRadius = dp(13).toFloat()
                setColor(Color.argb(36, 0x7C, 0x5C, 0xFF))
            }
            setTag(com.arpit.glyf.R.id.qa_id, "strip:smart:extra")
            setOnClickListener { policyUsed(); onExtra() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(26)).apply { leftMargin = dp(10) })
        placeChip(chip, kind)
        return true
    }

    /** Several saved values at once (Smart.Chip.Details: two emails, your
     *  email and a temp one), as a row of chips (Arpit, 2026-10-01: "it
     *  should be 2-3 diff strips not all in one strip"): one plain ✕ for the
     *  row, then a glowing glass chip of its own for each value, and one for
     *  Temp (its envelope and "Temp" in the chip's purple). A chip's words are
     *  its action, so there is no verb: a value types itself ([onValue]),
     *  Temp gives a temp address ([onTemp]). ChipRow lays them out as iOS's
     *  row does. False when waved off for these words. */
    private fun showDetailsChip(kind: String, details: Smart.Chip.Details,
                                onValue: (Smart.Field) -> Unit, onTemp: () -> Unit): Boolean {
        val fields = details.fields.take(3)
        return showChoiceRow(kind, fields.map { StandIns.shown(it) }, details.temp,
            onIndex = { i -> onValue(fields[i]) }, onTemp = onTemp)
    }

    /** The row itself: one ✕, a glass chip per value (a tap gives
     *  [onIndex] its place), and Temp when [temp]. Saved details and a
     *  measurement's results both draw with it. */
    private fun showChoiceRow(kind: String, values: List<String>, temp: Boolean,
                              onIndex: (Int) -> Unit, onTemp: () -> Unit,
                              onClose: (() -> Unit)? = null): Boolean {
        // A panel's name is in the strip: its chips wait for the keys.
        if (stripTitleRow != null) return false
        val key = chipKey(kind)
        if (key == dismissedChip) {
            if (stripChipKind == kind) hideStripChip()
            return false
        }
        if (!policyAllows(kind, values.joinToString(" · ") + if (temp) " · Temp" else "", null)) return false
        hideStripChip()
        val accent = stripAccent()
        val secondary = chipSecondary()
        val row = ChipRow(this, stripChipHeight()).apply {
            setTag(com.arpit.glyf.R.id.qa_id, "strip:smart")
            contentDescription = (values + if (temp) listOf("Temp mail") else emptyList()).joinToString(", ")
        }
        // The row's one ✕: plain, its 11dp cross in a 28dp target.
        row.setClose(ToolIcon(this, "close", secondary).apply {
            setTint(secondary)
            setTag(com.arpit.glyf.R.id.qa_id, "strip:smart:close")
            contentDescription = "Dismiss"
            setOnClickListener { policyDismissed(); onClose?.invoke() ?: dismissChip(key) }
        })
        fun card(id: String, said: String, onTap: () -> Unit) = MagicChip(this, chromeDark).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setTag(com.arpit.glyf.R.id.qa_id, id)
            contentDescription = said
            setOnClickListener { onTap() }
        }
        for ((i, value) in values.take(3).withIndex()) {
            val chip = card("strip:smart:choice:$i", value) { com.arpit.glyf.store.Funnel.mark(this, "first_answer"); policyUsed(); onIndex(i) }
            // An address is known by its start ("alex.s219@exa…"): cut in the
            // middle, two emails read the same ("alex….com").
            val words = TextView(this).apply {
                text = value
                textSize = 15f
                setTextColor(ink())
                gravity = Gravity.CENTER
                isSingleLine = true
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            chip.addView(words, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addPart(ChipRow.Part(chip, words, temp = false))
        }
        if (temp) {
            val chip = card("strip:smart:choice:temp", "Temp mail") { policyUsed(); onTemp() }
            // iOS: the envelope in a 17dp box, 6dp before the word.
            chip.addView(ToolIcon(this, "tempmail", accent).apply { solid = true; weight = 1.8f },
                LinearLayout.LayoutParams(dp(ChipRow.MARK.toInt()), dp(ChipRow.MARK.toInt())).apply {
                    rightMargin = dp(ChipRow.MARK_GAP.toInt())
                })
            val words = TextView(this).apply {
                text = "Temp"
                textSize = 15f
                typeface = if (android.os.Build.VERSION.SDK_INT >= 28)
                    Typeface.create(Typeface.DEFAULT, 600, false) else Typeface.DEFAULT_BOLD
                setTextColor(accent)
                isSingleLine = true
            }
            chip.addView(words, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT))
            row.addPart(ChipRow.Part(chip, words, temp = true))
        }
        // From 6dp left of where a chip starts (the ✕'s room) to where it ends.
        placeChip(row, kind, lead = dp(6))
        return true
    }

    /** Words that sit back on a chip: its small label and its ✕. */
    private fun chipSecondary() = Color.argb(170, Color.red(ink()), Color.green(ink()), Color.blue(ink()))

    /** The hairline after a chip's ✕. */
    private fun chipRule() = Color.argb(46, Color.red(ink()), Color.green(ink()), Color.blue(ink()))

    /** The card every chip is: glass with the turning, glowing border
     *  (MagicChip), laid out as Safari's app banner is: the ✕ first, then a
     *  hairline, then what the chip holds (Arpit, 2026-09-30: "no cross on
     *  right looks bad, insert should be the default action, maybe put cross
     *  in left"). [endPad] is the room after the content, in dp from the
     *  chip's edge. Null when the chip was waved off for these words, or a
     *  panel's name holds the strip. */
    private fun chipCard(kind: String, endPad: Float, onClose: (() -> Unit)?): MagicChip? {
        // A panel's name is in the strip: its chips wait for the keys.
        if (stripTitleRow != null) return null
        val key = chipKey(kind)
        if (onClose == null && key == dismissedChip) {
            if (stripChipKind == kind) hideStripChip()
            return null
        }
        hideStripChip()
        val secondary = chipSecondary()
        val density = resources.displayMetrics.density
        fun px(dp: Float) = Math.round(dp * density)
        val chip = MagicChip(this, chromeDark).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            // The cross is 11dp across in the middle of its 36dp target, so
            // 12.5dp in: the target starts 3dp from the chip's edge (the
            // cross 14dp inside the border's inner edge, 1.5dp in).
            setPadding(px(1.5f + 14f - 12.5f), 0, px(endPad), 0)
            setTag(com.arpit.glyf.R.id.qa_id, "strip:smart")
        }
        chip.addView(ToolIcon(this, "close", secondary).apply {
            setTint(secondary)
            setTag(com.arpit.glyf.R.id.qa_id, "strip:smart:close")
            contentDescription = "Dismiss"
            setOnClickListener { policyDismissed(); if (onClose != null) onClose() else dismissChip(key) }
        }, LinearLayout.LayoutParams(dp(36), dp(36)))
        // A hairline 10dp past the cross (so 2.5dp inside the ✕'s target),
        // then 10dp to the chip's words: a thumb going for them never lands
        // on the ✕.
        chip.addView(View(this).apply { setBackgroundColor(chipRule()) },
            LinearLayout.LayoutParams(maxOf(1, px(0.75f)), dp(18)).apply { leftMargin = px(-2.5f) })
        return chip
    }

    /** A strip chip's height, centred on Glyf's key (Arpit, 2026-09-30: "why
     *  did the ai strip fall below, have it at same level as glyf logo"), as
     *  on iOS: iOS's 38dp, or less where the key's middle leaves less room
     *  above or below. The strip centres it in its padded box, so the chip's
     *  middle is the key's. */
    private fun stripChipHeight(): Int {
        val stripH = toolbar.layoutParams?.height?.takeIf { it > 0 } ?: dp(stripDp)
        val keyMid = toolbar.paddingTop + (stripH - toolbar.paddingTop - toolbar.paddingBottom) / 2
        return minOf(dp(38), 2 * keyMid, 2 * (stripH - keyMid))
    }

    /** [chip] (a chip, or a details chip's row of them) into the strip,
     *  where it owns the strip until it goes; [lead] is room it takes to the
     *  left of where a chip starts (the row's ✕). */
    private fun placeChip(chip: View, kind: String, lead: Int = 0) {
        toolbar.addView(chip, 1, LinearLayout.LayoutParams(0, stripChipHeight(), 1f).apply {
            leftMargin = dp(8) - lead
            // The chip ends as far in as Glyf's key starts (the key is drawn
            // centred in its 52dp view), so the strip sits centred over the keys.
            rightMargin = ((dp(52) - GlyfMark.keyWidth(dp(30).toFloat())) / 2).toInt()
        })
        stripChip = chip
        stripChipKind = kind
        applySuggestionVisibility()
        applyTourHint()
    }

    /** The chip waved off, as its kind and the words it came for. */
    private var dismissedChip: String? = null

    private fun chipKey(kind: String): String {
        val words = currentInputConnection?.getTextBeforeCursor(120, 0)?.toString()?.trim().orEmpty()
        return "$kind\u0000$words"
    }

    // MARK: Strip policy (docs/STRIP-POLICY.md; iOS twin: present())

    /** Which chip may show and when, and what a ✕ or typing past one means
     *  for the next (Arpit, 2026-11-04: "when the user crosses it, it comes
     *  again and again ... it should not be irritating and it should be
     *  useful at the same time"). */
    private val stripPolicy = StripPolicy()
    /** When the text last changed (a key, a commit, the app). */
    private var lastEditAt = 0L
    /** The chip on screen, as the policy knows it. */
    private var shownPolicy: Pair<StripPolicy.Kind, String>? = null

    private fun nowSeconds() = System.currentTimeMillis() / 1000.0
    private fun policyFieldId() = currentInputEditorInfo?.let { "${it.packageName}/${it.fieldId}" } ?: ""

    /** Passwords get nothing; digit, phone and date boxes only what they are
     *  for (a saved detail, a copy, a mail's code). */
    private fun policyField(): StripPolicy.Field {
        if (isSecureField()) return StripPolicy.Field.SECRET
        val type = currentInputEditorInfo?.inputType ?: return StripPolicy.Field.NORMAL
        return when (type and InputType.TYPE_MASK_CLASS) {
            InputType.TYPE_CLASS_NUMBER, InputType.TYPE_CLASS_PHONE, InputType.TYPE_CLASS_DATETIME -> StripPolicy.Field.CODE
            else -> StripPolicy.Field.NORMAL
        }
    }

    private fun policyKindOf(stripKind: String, value: String): StripPolicy.Kind? = when (stripKind) {
        "voice" -> null   // the words just said, not an offer
        "paste" -> StripPolicy.Kind.PASTE
        "fill", "tempfield" -> StripPolicy.Kind.FILL
        "tempmail" -> StripPolicy.Kind.MAIL
        "event", "booking" -> StripPolicy.Kind.PLAN
        "pay", "buy", "trade" -> StripPolicy.Kind.PAY
        "action" -> if (value == "Add a Meet link") StripPolicy.Kind.PLAN else StripPolicy.Kind.AI
        else -> if (stripSmartDetail?.startsWith("vault:") == true) StripPolicy.Kind.FILL else StripPolicy.Kind.ANSWER
    }

    /** May this chip show now? False leaves the strip to the words (and a
     *  pause asks again). Draws nothing. */
    private fun policyAllows(stripKind: String, value: String, policyKey: String?): Boolean {
        val kind = policyKindOf(stripKind, value) ?: run { shownPolicy = null; return true }
        if (stripTitleRow != null) return false
        // The tour keeps the strip for the step it is coaching.
        if (tourStep() != null) { shownPolicy = null; return true }
        val id = "$stripKind|${stripSmartDetail.orEmpty()}|$value|${policyKey.orEmpty()}"
        val now = nowSeconds()
        fun no(): Boolean {
            if (stripChip != null && stripChipKind != "voice") hideStripChip()
            return false
        }
        if (!StripPolicy.allowed(kind, policyField()) || !stripPolicy.allows(kind, id, now)) {
            // A longer trade typed on past a shorter one ("buy $20 of eth" →
            // "… every day for a week") is the same intent growing, not a no:
            // look again once the quiet is over, without a keystroke (iOS twin).
            if (stripKind == "trade" && stripPolicy.quietUntil > now) {
                main.removeCallbacks(suggestionsTick)
                main.postDelayed(suggestionsTick, ((stripPolicy.quietUntil - now) * 1000).toLong() + 50)
            }
            return no()
        }
        val before = currentInputConnection?.getTextBeforeCursor(96, 0)?.toString().orEmpty()
        val word = WordContext.currentWord(before)
        val policy = typingPolicy()
        val midWord = word.isNotEmpty() && word.first().isLetter() && settings.optBoolean("candidates", true) &&
            policy and TypingEngine.SUGGESTIONS != 0 && !WordContext.insideLinkOrAddress(before)
        val typing = StripPolicy.Typing(
            sinceEdit = (android.os.SystemClock.uptimeMillis() - lastEditAt) / 1000.0,
            midWord = midWord,
            undoOnOffer = word.isEmpty() && undoableCorrection(before) != null,
        ) { engineSuggestions(word, before, policy)?.autocorrect != null }
        return when (val t = stripPolicy.timing(kind, id, typing)) {
            StripPolicy.Timing.Now -> {
                stripPolicy.shown(kind, id, before, now)
                shownPolicy = kind to id
                true
            }
            is StripPolicy.Timing.Wait -> {
                main.removeCallbacks(suggestionsTick)
                main.postDelayed(suggestionsTick, (t.seconds * 1000).toLong() + 20)
                no()
            }
            StripPolicy.Timing.Words -> no()
        }
    }

    /** The ✕: a 10 s cooldown; this chip comes again once the text changes. */
    private fun policyDismissed() {
        val (kind, id) = shownPolicy ?: return
        shownPolicy = null
        stripPolicy.dismissed(kind, id, nowSeconds())
    }

    /** Tapped: wanted. */
    private fun policyUsed() {
        shownPolicy ?: return
        shownPolicy = null
        stripPolicy.used()
    }

    /** The copy now on the clipboard is done: used, waved off or typed past. */
    private fun markClipDone() {
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val stamp = cm.primaryClipDescription?.timestamp ?: return
        imePrefs.edit().putLong("clipDone", stamp).apply()
        if (stripChipKind == "paste") hideStripChip()
    }

    /** Waved off: gone, and the strip shows what it would have without it. */
    private fun dismissChip(key: String) {
        dismissedChip = key
        hideStripChip()
        updateSuggestions()
    }

    private fun hideStripChip() {
        stripChip?.let { toolbar.removeView(it) }
        stripChip = null
        stripChipKind = null
        if (::toolIcons.isInitialized) applySuggestionVisibility()
    }

    // MARK: Act — hold space on what you typed (POST /act)

    /** Bumped on every run, close and new field, so a late reply can never
     *  land on a panel the user already left. */
    private var actGeneration = 0
    private var actBefore = ""
    private var actAfter = ""
    private var actPanelHeight = 0
    /** Set while a bound letter's skill runs in the act panel: glyf id → letter. */
    private var actSkill: Pair<String, String>? = null
    /** A bar run's own name (the prompt itself) and its vars. */
    private var actSkillTitle: String? = null
    private var actVars: Map<String, String> = emptyMap()
    /** What the run reads: the field text, or the clipboard for a skill. */
    private var actRunInput = ""
    private var actStreamView: TextView? = null
    /** The rows of a rewrite being streamed, while its versions arrive. */
    private var actOptionList: LinearLayout? = null

    /** What a tapped tool asked for (Rewrite); null lets the server decide. */
    private var actIntent: String? = null

    private fun startAct(before: String, after: String, intent: String? = null) {
        com.arpit.glyf.store.Funnel.mark(this, "first_ai")
        // A password never goes to the AI, whichever button asked.
        if (isSecureField()) return
        actSkill = null
        actSkillTitle = null
        actVars = emptyMap()
        actIntent = intent
        actBefore = before
        actAfter = after
        actRunInput = (before + after).trim()
        runAct()
    }

    /** A bound letter held → its skill runs as a HUD: the skill's name over
     *  the letter's keycap, the answer streaming in, then ↻ Copy Insert. */
    private fun startSkill(letter: String, glyfId: String, vars: Map<String, String> = emptyMap(),
                           title: String? = null) {
        com.arpit.glyf.store.Funnel.mark(this, "first_ai")
        if (isSecureField()) return
        val ic = currentInputConnection
        val before = ic?.getTextBeforeCursor(2000, 0)?.toString() ?: ""
        val after = ic?.getTextAfterCursor(2000, 0)?.toString() ?: ""
        actSkill = glyfId to letter
        actSkillTitle = title
        actVars = vars
        if ((before + after).isNotBlank()) {
            actBefore = before
            actAfter = after
            actRunInput = before + after
        } else {
            // Nothing typed: the skill reads the clipboard and Insert only adds.
            actBefore = ""
            actAfter = ""
            actRunInput = com.arpit.glyf.store.ClipboardStore.clipText(this) ?: ""
        }
        runAct()
    }

    /** Display names for bound glyfs — iOS GlyfCatalog's titles, then the
     *  names the app recorded for builder/hub glyfs, then a tidy id. */
    private fun skillTitle(glyfId: String): String {
        settings.optJSONObject("customTitles")?.optString(glyfId)?.takeIf { it.isNotBlank() }?.let { return it }
        // A built glyf whose name was lost: never its id ("user.d24774a1").
        if (glyfId.startsWith("user.") || glyfId.startsWith("hub.")) return "Untitled glyf"
        return mapOf(
            "rewrite.polite" to "Make it polite", "rewrite.tighten" to "Tighten",
            "rewrite.professional" to "Professional", "glyf.translate" to "Translate",
            "rewrite.emoji" to "Emoji-fy", "glyf.proofread" to "Proofread",
            "rewrite.tone" to "Tone shift", "social.emotion" to "Emotion check",
            "social.xreply" to "Super X reply", "keyless.weather" to "Weather",
            "keyless.quote" to "Price check", "keyless.define" to "Define",
            "keyless.wiki" to "Wiki lookup", "keyless.stock" to "Stock check",
        )[glyfId] ?: glyfId.substringAfterLast('.').replace('-', ' ')
            .replaceFirstChar { it.uppercase() }
    }

    private fun runAct() {
        val generation = ++actGeneration
        val panel = actPanel()
        actStreamView = null
        actSkill?.let { (glyfId, letter) ->
            val title = actSkillTitle ?: skillTitle(glyfId)
            buildActWorking(panel, actRunInput, title, letter.ifEmpty { null })
            val streamed = StringBuilder()
            val lat = if (settings.has("lastLat")) settings.optDouble("lastLat") else null
            val lon = if (settings.has("lastLon")) settings.optDouble("lastLon") else null
            BackendClient.run(
                settings.optString("backendURL"), glyfId, actRunInput, runVars(glyfId, actVars),
                settings.optString("deviceId"), settings.optString("plan", "free"),
                profile = shareableProfile(),
                lat = lat?.takeIf { !it.isNaN() },
                lon = lon?.takeIf { !it.isNaN() },
                onToken = { t -> main.post {
                    if (generation != actGeneration || overlay !== panel) return@post
                    streamed.append(t)
                    showActStreaming(panel, title, streamed.toString())
                } },
                onDone = { text, remaining -> main.post {
                    if (generation != actGeneration || overlay !== panel) return@post
                    showActResult(panel, BackendClient.ActResult(
                        intent = "skill", title = title, cards = emptyList(),
                        text = text, insert = text, remaining = remaining))
                } },
                onError = { message -> main.post {
                    if (generation == actGeneration && overlay === panel) showActFailure(panel, message)
                } },
            )
            return
        }
        // A sum, a conversion, money at the rates in hand, the time or the
        // date: answered here at once, no server and no run ("2+5" held for
        // a moment went to the server and back). Smart.instantAnswer.
        if (actIntent == null || actIntent == "answer") {
            val region = settings.optString("region").ifEmpty { java.util.Locale.getDefault().country }
            Smart.instantAnswer(actRunInput, RatesStore.snapshot(region, settings.optString("moneyCurrency")),
                indianGrouping = region == "IN")?.let { local ->
                val card = BackendClient.SearchCard(kind = "answer", id = "local", title = local.title, url = "",
                    say = local.say, value = local.value, sub = local.sub, art = "calc")
                showActResult(panel, BackendClient.ActResult(intent = "answer", title = local.title,
                    cards = listOf(card), text = null, insert = local.say, remaining = null))
                return
            }
        }
        val intent = actRunInput
        buildActWorking(panel, intent)
        // Versions show one by one as the model finishes each, and written
        // text as it comes: the first row is up well before the last.
        val streamed = mutableListOf<BackendClient.RewriteOption>()
        val written = StringBuilder()
        val current = { generation == actGeneration && overlay === panel }
        val lat = if (settings.has("lastLat")) settings.optDouble("lastLat") else null
        val lon = if (settings.has("lastLon")) settings.optDouble("lastLon") else null
        BackendClient.act(
            backendURL = settings.optString("backendURL"),
            text = intent,
            deviceId = settings.optString("deviceId"),
            plan = settings.optString("plan", "free"),
            lat = lat?.takeIf { !it.isNaN() },
            lon = lon?.takeIf { !it.isNaN() },
            country = settings.optString("region").takeIf { it.length == 2 },
            tz = java.util.TimeZone.getDefault().id,
            intent = actIntent,
            profile = shareableProfile(),
            onOption = { o -> main.post {
                if (!current() || streamed.any { it.id == o.id }) return@post
                streamed.add(o)
                appendActOption(panel, o, streamed.toList())
            } },
            onText = { t -> main.post {
                if (!current()) return@post
                written.append(t)
                val shown = written.toString().trim()
                if (shown.isNotEmpty()) showActStreaming(panel, intent, shown)
            } },
            onReset = { main.post {
                if (!current()) return@post
                streamed.clear()
                written.setLength(0)
                actStreamView = null
                buildActWorking(panel, intent)
            } },
            onResult = { r -> main.post {
                if (current()) showActResult(panel, r)
            } },
            onError = { message -> main.post {
                if (generation == actGeneration && overlay === panel) showActFailure(panel, message)
            } },
        )
    }

    /** What every run carries besides its own vars (iOS BackendClient.run):
     *  the tone the person keeps choosing, for prompts that ask for it, and
     *  for Translate the person's own two languages, the same pair the
     *  translate strip uses, so it never falls back to English and Hindi. */
    private fun runVars(glyfId: String, vars: Map<String, String>): Map<String, String> {
        val out = LinkedHashMap(vars)
        if ("toneHint" !in out) {
            val hint = com.arpit.glyf.store.ToneProfile.hint(com.arpit.glyf.store.ToneProfile.load(this))
            // The prompts put it straight after a sentence's full stop.
            out["toneHint"] = if (hint.isEmpty()) "" else " $hint"
        }
        if (glyfId == "glyf.translate") {
            val (primary, secondary) = translatePair()
            out.putIfAbsent("primary", primary)
            out.putIfAbsent("secondary", secondary)
        }
        return out
    }

    /** One panel for the whole act, in place of the toolbar and keys. */
    private fun actPanel(): FrameLayout {
        removeClipCard()
        (overlay as? FrameLayout)?.takeIf { it.tag == "act" }?.let {
            it.removeAllViews()
            return it
        }
        dismissOverlay()
        // Exactly the strip and the keys it stands in for, as on iOS: the
        // keyboard never grows when space is held. Results scroll.
        val keysH = if (keyboard.height > 0) keyboard.height else dp(216)
        actPanelHeight = dp(stripDp) + keysH
        val panel = FrameLayout(this).apply { tag = "act" }
        root.addView(panel, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, actPanelHeight))
        keyboard.visibility = View.GONE
        toolbar.visibility = View.GONE
        overlay = panel
        return panel
    }

    private fun buildActWorking(panel: FrameLayout, intent: String,
                                title: String? = null, letter: String? = null) {
        actOptionList = null
        panel.removeAllViews()
        panel.addView(ActRingsView(this, ink()), FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        panel.addView(actHeader(retry = false), FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, dp(stripDp), Gravity.TOP))
        if (title != null) {
            panel.addView(TextView(this).apply {
                text = title
                Glass.style(this, 15f, Glass.SEMIBOLD)
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(dp(24), 0, dp(24), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "act:skill"); contentDescription = "Working"
            }, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP).apply { topMargin = dp(53) })
        }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val mark = brandMark(letter?.uppercase() ?: "g")
        column.addView(mark, LinearLayout.LayoutParams(dp(52), dp(52)))
        column.addView(TextView(this).apply {
            val trimmed = intent.trim()
            val quoted = if (trimmed.length > 80) trimmed.take(80) + "…" else trimmed
            text = if (quoted.isEmpty()) "" else "“$quoted”"
            Glass.style(this, 14f, Glass.MEDIUM, Glass.textSecondary)
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(12), dp(24), 0)
        })
        panel.addView(column, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER).apply { bottomMargin = dp(40) })
        panel.addView(circleButton("✕", "act:cancel") { actClose() },
            FrameLayout.LayoutParams(dp(36), dp(36),
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(12) })
        android.animation.ObjectAnimator.ofPropertyValuesHolder(mark,
            android.animation.PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, 0.93f),
            android.animation.PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, 0.93f)).apply {
            duration = 900
            repeatCount = android.animation.ValueAnimator.INFINITE
            repeatMode = android.animation.ValueAnimator.REVERSE
            start()
        }
    }

    /** The result the act panel shows, for Report. */
    private var actShown: BackendClient.ActResult? = null

    /** What of a result the AI wrote, as the panel shows it: every version
     *  labelled, written text, an AI answer. Nil for what the phone worked
     *  out (a sum) or found (places, videos): there is nothing to report. */
    private fun reportable(r: BackendClient.ActResult): String? {
        val parts = mutableListOf<String>()
        r.options.forEach { parts += "${it.label}: ${it.text}" }
        r.text?.takeIf { it.isNotBlank() }?.let { parts += it }
        r.cards.filter { it.kind == "answer" && it.id != "local" }
            .forEach { c -> parts += listOfNotNull(c.title, c.say ?: c.value, c.sub).joinToString(" · ") }
        return parts.joinToString("\n\n").takeIf { it.isNotBlank() }
    }

    /** Google Play's AI-Generated Content policy: an AI result can be
     *  flagged without leaving the app. One tap sends what the panel shows,
     *  and says so. */
    private fun reportActResult() {
        val r = actShown ?: return
        val result = reportable(r) ?: return
        val feature = if (r.intent == "skill") actSkill?.first ?: "skill" else r.intent
        BackendClient.report(settings.optString("backendURL"), settings.optString("deviceId"),
            feature, result) { ok ->
            main.post { notice(if (ok) "Reported. Thanks for telling us." else "Couldn't send the report. Try again in a moment.") }
        }
    }

    /** The strip while the act panel is open, iOS's panel header: ✕ where
     *  the g was, ✦ Glyf, and ↻ at the right once there is an answer to try
     *  again, with Report (a flag) beside it when the AI wrote that answer.
     *  Laid out as the strip lays out a panel's name. */
    private fun actHeader(retry: Boolean, report: Boolean = false): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(10), dp(6), 0, dp(6))
        addView(GlyfKeyView(this@GlyfIME, dp(30).toFloat()).apply {
            closing = true
            ink = Glass.textPrimary
            dark = chromeDark
            divider = glassLook
            setTag(com.arpit.glyf.R.id.qa_id, "act:close"); contentDescription = "Close"
            setOnClickListener { actClose() }
        }, LinearLayout.LayoutParams(dp(52), dp(38)))
        clipChildren = false
        val keyInkRight = GlyfKeyView.markRight(dp(52).toFloat(), dp(30).toFloat(), resources.displayMetrics.density)
        val start = (keyInkRight + dp(if (glassLook) 17 else 11) - dp(52)).toInt()
        addView(ToolIcon(this@GlyfIME, "ask", Glass.textPrimary).apply {
            solid = true; weight = 1.8f
        }, LinearLayout.LayoutParams(dp(24), dp(24)).apply { leftMargin = start; rightMargin = dp(6) })
        addView(TextView(this@GlyfIME).apply {
            text = "Glyf"
            Glass.style(this, 15f, Glass.SEMIBOLD)
            maxLines = 1
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        if (report) addView(ToolIcon(this@GlyfIME, "flag", Glass.textSecondary).apply {
            solid = true; weight = 1.8f; scale = 0.9f
            setTag(com.arpit.glyf.R.id.qa_id, "act:report"); contentDescription = "Report"
            setOnClickListener { reportActResult() }
        }, LinearLayout.LayoutParams(dp(40), dp(34)))
        if (retry) addView(ToolIcon(this@GlyfIME, "retry", Glass.textPrimary).apply {
            solid = true; weight = 2.1f; scale = 0.92f
            setTag(com.arpit.glyf.R.id.qa_id, "act:retry"); contentDescription = "Try again"
            setOnClickListener { runAct() }
        }, LinearLayout.LayoutParams(dp(44), dp(34)).apply { rightMargin = dp(4) })
    }

    /** The answer's box: the key colour, 15 corners, a hairline, 15.5 text
     *  (iOS's text view and its insets). */
    private fun actTextBox(body: String): TextView = TextView(this).apply {
        // Saved details go in on the phone, in place of their stand-ins.
        text = withDetails(body)
        Glass.style(this, 15.5f)
        setLineSpacing(dp(1).toFloat(), 1f)
        setPadding(dp(15), dp(11), dp(15), dp(11))
        minHeight = dp(48)
        setTag(com.arpit.glyf.R.id.qa_id, "act:text"); contentDescription = "Answer"
        background = Glass.card(this@GlyfIME, Glass.surfaceCard, radius = 15f,
            stroke = Glass.strokeHairline)
    }

    /** `streaming`: versions are still arriving, so ↻ waits for the last. */
    private fun showActResult(panel: FrameLayout, r: BackendClient.ActResult, streaming: Boolean = false) {
        actStreamView = null
        actOptionList = null
        actShown = r
        panel.removeAllViews()
        val outer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        outer.addView(actHeader(retry = !streaming, report = !streaming && reportable(r) != null),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(stripDp)))
        // iOS: 4 under the strip, 10 a side; Copy and Insert 14 off the
        // bottom, and versions run to the bottom.
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(4), dp(10), if (r.options.isEmpty()) dp(14) else 0)
        }
        outer.addView(column, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        fun gap() = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { setMargins(0, 0, 0, dp(2)) }
        fun rowGap(h: Int = LinearLayout.LayoutParams.WRAP_CONTENT) = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, h).apply { setMargins(0, dp(4), 0, dp(4)) }
        if (r.options.isNotEmpty()) {
            // The website's rows: the style, then the message. Tap to put it
            // in; hold to copy it.
            for (o in r.options) list.addView(optionRow(o), rowGap())
            actOptionList = list
        } else if (!r.text.isNullOrBlank()) {
            list.addView(actTextBox(r.text), gap())
        }
        val theme = SearchCards.Theme(ink = Glass.textPrimary, card = Glass.surfaceCard,
            soft = Glass.textSecondary, dp = ::dp, dark = chromeDark)
        val backendURL = settings.optString("backendURL")
        val style = settings.optString("pasteStyle", "titleAndLink")
        // One place → a real map above its card. The server draws it with
        // Geoapify; without that key it 404s and the map simply isn't shown.
        val place = r.cards.singleOrNull()?.takeIf { it.kind == "place" && it.lat != null && it.lon != null }
        if (place != null) {
            val map = android.widget.ImageView(this).apply {
                scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
                clipToOutline = true
                outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: android.graphics.Outline) {
                        outline.setRoundRect(0, 0, view.width, view.height, dp(15).toFloat())
                    }
                }
                background = GradientDrawable().apply {
                    cornerRadius = dp(15).toFloat(); setColor(card())
                }
                setTag(com.arpit.glyf.R.id.qa_id, "act:map"); contentDescription = "Map"
                setOnClickListener { actInsert(place.insertText(style)) }
            }
            list.addView(map, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(112)).apply { setMargins(0, dp(2), 0, dp(2)) })
            val w = resources.displayMetrics.widthPixels / 2
            SearchCards.loadThumb(
                "$backendURL/search/staticmap?lat=${place.lat}&lon=${place.lon}&w=$w&h=${dp(112) / 2}" +
                    (if (chromeDark) "&dark=1" else ""),
                map, onMiss = { map.visibility = View.GONE }, maxWidth = 1200, signed = true)
        }
        for (c in r.cards) {
            // Tapping one card drops just that one — a single place from a list.
            list.addView(SearchCards.view(this, c, theme, backendURL) { tapped ->
                actInsert(if (tapped.kind == "query") tapped.url else tapped.insertText(style))
            }, rowGap(dp(SearchCards.height(c.kind))))
        }
        column.addView(ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            addView(list)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        if (r.options.isEmpty()) {
            val actions = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, dp(6), 0, 0)
            }
            // Copy and Insert only when there is one answer to take (↻ is up
            // in the strip, as on iOS).
            if (r.insert.isNotBlank()) {
                actions.addView(pill("Copy", primary = false, id = "act:copy") { actCopy(r.insert) },
                    LinearLayout.LayoutParams(0, dp(38), 0.38f))
                actions.addView(pill("Insert", primary = true, id = "act:insert", arrow = true) { actInsert(r.insert) },
                    LinearLayout.LayoutParams(0, dp(38), 0.62f).apply { leftMargin = dp(8) })
            }
            column.addView(actions)
        }
        panel.addView(outer, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    /** The skill's answer arriving token by token; actions come with the end. */
    @Suppress("UNUSED_PARAMETER")
    private fun showActStreaming(panel: FrameLayout, title: String, text: String) {
        actStreamView?.let { it.text = withDetails(text); return }
        actOptionList = null
        panel.removeAllViews()
        val outer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        outer.addView(actHeader(retry = false), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(stripDp)))
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(4), dp(10), dp(14))
        }
        outer.addView(column, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        val body = actTextBox(text)
        column.addView(ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            addView(body)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        panel.addView(outer, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        actStreamView = body
    }

    /** One version of a rewrite, the website's row: the style, then the
     *  message. Tap to put it in; hold to copy it. */
    private fun optionRow(o: BackendClient.RewriteOption): View {
        // iOS's OptionCell: the key colour, 14 corners; the style 13
        // semibold grey in a 92 column 12 from the text, 15 regular, 3 lines.
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            setTag(com.arpit.glyf.R.id.qa_id, "act:option:${o.id}")
            contentDescription = "${o.label}: ${withDetails(o.text)}"
            background = Glass.card(this@GlyfIME, Glass.surfaceCard, radius = 14f)
            setOnClickListener { actInsert(o.text) }
            setOnLongClickListener { actCopy(o.text); true }
        }
        row.addView(TextView(this).apply {
            text = o.label
            Glass.style(this, 13f, Glass.SEMIBOLD, Glass.textSecondary)
            maxLines = 1
            setPadding(0, dp(1), 0, 0)
        }, LinearLayout.LayoutParams(dp(92), LinearLayout.LayoutParams.WRAP_CONTENT).apply { rightMargin = dp(12) })
        row.addView(TextView(this).apply {
            text = withDetails(o.text)
            Glass.style(this, 15f)
            setLineSpacing(dp(1).toFloat(), 1f)
            maxLines = 3
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    /** One version the moment the model finishes it: the list fills in while
     *  the rest are written, and a row can already be tapped. The whole
     *  result redraws the panel at the end, with ↻ back in the strip. */
    private fun appendActOption(panel: FrameLayout, o: BackendClient.RewriteOption,
                                all: List<BackendClient.RewriteOption>) {
        val list = actOptionList
        if (list == null) {
            showActResult(panel, BackendClient.ActResult(intent = "rewrite", title = "Rewrite",
                cards = emptyList(), text = null, insert = "", remaining = null, options = all),
                streaming = true)
            return
        }
        val row = optionRow(o)
        list.addView(row, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { setMargins(0, dp(4), 0, dp(4)) })
        // A property animation: with animations off in Settings it lands at once.
        row.alpha = 0f
        row.animate().alpha(1f).setDuration(180).start()
    }

    private fun showActFailure(panel: FrameLayout, message: String) {
        actOptionList = null
        panel.removeAllViews()
        // iOS: the strip names the panel; the message 14 grey, centred in
        // what is left, a tap tries again.
        panel.addView(TextView(this).apply {
            text = message
            Glass.style(this, 14f, Glass.REGULAR, Glass.textSecondary)
            gravity = Gravity.CENTER
            maxLines = 3
            setPadding(dp(24), dp(stripDp), dp(24), dp(22))
            setTag(com.arpit.glyf.R.id.qa_id, "act:status"); contentDescription = "Status"
            setOnClickListener { runAct() }
        }, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        panel.addView(actHeader(retry = false), FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, dp(stripDp), Gravity.TOP))
    }

    /** Swaps exactly what the run read — both sides of the cursor. */
    private fun actInsert(raw: String) {
        val text = withDetails(raw)
        currentInputConnection?.let { ic ->
            ic.beginBatchEdit()
            ic.deleteSurroundingText(actBefore.length, actAfter.length)
            ic.commitText(text, 1)
            ic.endBatchEdit()
        }
        glyfWrote = text.trim()
        actClose()
    }

    private fun actCopy(raw: String) {
        val text = withDetails(raw)
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        cm.setPrimaryClip(android.content.ClipData.newPlainText("Glyf", text))
        notice("Copied")
    }

    private fun actClose() {
        actGeneration++
        actSkill = null
        actStreamView = null
        actBefore = ""
        actAfter = ""
        dismissOverlay()
        syncAutoShift()
    }

    /** The brand keycap: black, white glyph, the purple dot riding top-right —
     *  "g" for the space bar, the held letter for a skill. */
    private fun brandMark(glyph: String = "g"): FrameLayout = FrameLayout(this).apply {
        background = GradientDrawable().apply {
            cornerRadius = dp(13).toFloat(); setColor(Color.rgb(18, 18, 20))
        }
        // The space bar's act wears the app icon's mark, dot and all; a held
        // key its letter, with the dot in the corner like a bound key's.
        if (glyph == "g") {
            addView(GlyfMarkView(context, dp(6).toFloat()), FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            return@apply
        }
        addView(TextView(context).apply {
            text = glyph; textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(3))
        }, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        addView(View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL; setColor(Color.rgb(124, 92, 255))
            }
        }, FrameLayout.LayoutParams(dp(7), dp(7), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(6); rightMargin = dp(6)
        })
    }

    /** What TalkBack says for a symbol-only control. */
    private fun spokenFor(id: String, label: String): String = when {
        id.endsWith("close") -> "Close"
        id.endsWith("retry") -> "Try again"
        id.endsWith("copy") -> "Copy"
        id.endsWith("insert") -> "Insert"
        id.endsWith("back") -> "Back"
        id.endsWith("edit") -> "Edit"
        else -> label
    }

    /** iOS's round cancel: 36 on the key colour with a hairline, an xmark. */
    private fun circleButton(label: String, id: String, onTap: () -> Unit) = FrameLayout(this).apply {
        setTag(com.arpit.glyf.R.id.qa_id, id)
        contentDescription = spokenFor(id, label)
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(Glass.surfaceCard)
            setStroke(maxOf(1, dp(1) / 2), Glass.strokeHairline)
        }
        addView(ToolIcon(this@GlyfIME, "close", Glass.textPrimary).apply {
            solid = true; weight = 1.9f; scale = 1.05f
        }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        setOnClickListener { onTap() }
    }

    /** Black pill for the primary action, quiet hairline pills beside it;
     *  [accent] fills it with the keyboard's purple and white words, in light
     *  and dark alike (Temp mail's, as on iOS and the chips' Insert). */
    /** iOS's buttons, fully round: the primary in the ink with inverse
     *  words, the rest on the key colour with a hairline; [accent] fills it
     *  with the accent and white words (Temp mail's Insert), [field] with the
     *  field grey (Temp mail's Copy). [arrow] puts an up arrow after the word
     *  (Insert ↑). */
    private fun pill(label: String, primary: Boolean, id: String, accent: Boolean = false,
                     size: Float = 15f, field: Boolean = false, arrow: Boolean = false,
                     onTap: () -> Unit) = TextView(this).apply {
        text = label
        val words = when {
            accent -> Color.WHITE
            primary -> if (Glass.dark) Glass.brandInk else Color.WHITE
            else -> Glass.textPrimary
        }
        Glass.style(this, size, Glass.SEMIBOLD, words)
        gravity = Gravity.CENTER
        maxLines = 1
        setPadding(dp(12), 0, dp(12), 0)
        if (arrow) text = Glass.withTrailingIcon(label,
            ToolIcon(this@GlyfIME, "arrowup", words).apply {
                solid = true; weight = 2.5f; scale = 0.84f
            }.asDrawable(dp(15)), dp(5))
        setTag(com.arpit.glyf.R.id.qa_id, id)
        contentDescription = spokenFor(id, label)
        background = GradientDrawable().apply {
            cornerRadius = dp(100).toFloat()
            setColor(when {
                accent -> Glass.accentPrimary
                primary -> Glass.textPrimary
                field -> Glass.fillField
                else -> Glass.surfaceCard
            })
            if (!primary && !accent && !field) setStroke(maxOf(1, dp(1) / 2), Glass.strokeHairline)
        }
        setOnClickListener { onTap() }
    }

    /** Three quiet neutral rings breathing out from the centre while Glyf
     *  works — the purple stays on the dot. Stops with its window. */
    private class ActRingsView(context: android.content.Context, ink: Int) : View(context) {
        private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = 1.5f * context.resources.displayMetrics.density
            color = ink
        }
        private var phase = 0f
        private val animator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1800
            repeatCount = android.animation.ValueAnimator.INFINITE
            interpolator = android.view.animation.LinearInterpolator()
            addUpdateListener { phase = it.animatedValue as Float; invalidate() }
        }
        override fun onAttachedToWindow() { super.onAttachedToWindow(); animator.start() }
        override fun onDetachedFromWindow() { animator.cancel(); super.onDetachedFromWindow() }
        override fun onDraw(canvas: android.graphics.Canvas) {
            val cx = width / 2f
            val cy = height / 2f - 20f * resources.displayMetrics.density
            val maxR = minOf(width, height) * 0.55f
            for (i in 0 until 3) {
                val p = (phase + i / 3f) % 1f
                paint.alpha = ((1f - p) * 40).toInt()
                canvas.drawCircle(cx, cy, maxR * (0.35f + 0.65f * p), paint)
            }
        }
    }

    private fun handleSpace(ic: android.view.inputmethod.InputConnection) {
        val now = System.currentTimeMillis()
        val before = ic.getTextBeforeCursor(48, 0)?.toString() ?: ""

        // Double-space → ". " (§6.1)
        if (settings.optBoolean("periodShortcut", true) &&
            now - lastSpaceAt < 450 && before.isNotEmpty() &&
            before.last() == ' ' && before.length >= 2 && before[before.length - 2].isLetterOrDigit()) {
            ic.deleteSurroundingText(1, 0)
            ic.commitText(". ", 1)
            lastSpaceAt = 0
            syncAutoShift()
            return
        }
        lastSpaceAt = now

        // §6.7 shorthand: ;sig expands on the space commit.
        val token = before.split(" ", "\n").lastOrNull() ?: ""
        if (token.startsWith(";") && token.length in 3..13) {
            val vault = VaultStore.load(this)
            val snippets = vault.optJSONArray("snippets")
            if (snippets != null) {
                for (i in 0 until snippets.length()) {
                    val s = snippets.getJSONObject(i)
                    if (s.optString("trigger") == token) {
                        val (text, back) = fillShorthand(s.optString("text"))
                        ic.deleteSurroundingText(token.length, 0)
                        if (back > 0) {
                            // {cursor}: typing goes on inside what was typed out.
                            ic.commitText(text, 1)
                            cursorBack(ic, back)
                        } else {
                            ic.commitText("$text ", 1)
                            lastCorrection = Correction(token, text, fromEngine = false, anchor = anchorHere(ic), tail = " ")
                        }
                        syncAutoShift()
                        updateSuggestions()
                        return
                    }
                }
            }
        }
        // Autocorrect + learning on commit (ime/typing) — the policy keeps
        // password and address fields untouched.
        // "teh," then space: the fix stays undoable with its comma and space.
        val extending = if (lastCorrection?.anchor != null)
            undoableCorrection(ic.getTextBeforeCursor(ANCHOR_CHARS, 0)?.toString() ?: "") else null
        commitCurrentWord(ic)
        ic.commitText(" ", 1)
        // A correction this space just made is undoable from here only.
        anchorCorrection(ic, ' ', extending)
        syncAutoShift()
        updateSuggestions()
    }

    // MARK: typing engine — suggestions, autocorrect, learning

    /** What this field allows (shared/typing/FORMAT.md): nothing in password,
     *  email, URL, number and filter fields or where the app asks for no
     *  suggestions; no autocorrect for names and addresses; no learning in
     *  incognito fields or while learning is paused. */
    private fun typingPolicy(): Int {
        val ei = currentInputEditorInfo ?: return 0
        if (ei.inputType and InputType.TYPE_MASK_CLASS != InputType.TYPE_CLASS_TEXT) return 0
        val variation = ei.inputType and InputType.TYPE_MASK_VARIATION
        val flags = ei.inputType and InputType.TYPE_MASK_FLAGS
        val quiet = setOf(
            InputType.TYPE_TEXT_VARIATION_PASSWORD, InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD, InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS, InputType.TYPE_TEXT_VARIATION_URI,
            InputType.TYPE_TEXT_VARIATION_FILTER)
        if (variation in quiet) return 0
        if (flags and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS != 0) return 0
        var policy = TypingEngine.ALL
        if (!settings.optBoolean("autocorrect", true) ||
            variation == InputType.TYPE_TEXT_VARIATION_PERSON_NAME ||
            variation == InputType.TYPE_TEXT_VARIATION_POSTAL_ADDRESS) {
            policy = policy and TypingEngine.AUTOCORRECT.inv()
        }
        if (ei.imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING != 0 ||
            !settings.optBoolean("vocabLearning", true)) {
            policy = policy and TypingEngine.LEARNING.inv()
        }
        return policy
    }

    private fun engineSuggestions(word: String, before: String, policy: Int): TypingEngine.Suggestions? {
        val engine = KeyboardTyping.engine ?: return null
        // A number, or a ;trigger on its way to becoming shorthand, wants
        // none of the dictionary's guesses (iOS twin).
        val first = word.firstOrNull() ?: return null
        if (first.isDigit() || first == ';') return null
        val head = before.substring(0, before.length - word.length)
        if (head.endsWith(";")) return null
        return engine.suggestions(word, if (wordTouchesFor == word) ArrayList(wordTouches) else null,
            WordContext.previousWord(before), WordContext.wantsCapital(head), policy,
            beforePrevious = WordContext.wordBeforePrevious(before))
    }

    /** Suggestions and the smart strip are recomputed once typing settles,
     *  never inside the keystroke itself. At speed the old way put the
     *  engine, two dozen regexes and a strip rebuild between one finger
     *  going down and the next — long enough to lose the tap. Every key
     *  schedules this instead, so a burst collapses into a single pass.
     *  (iOS twin: scheduleCandidates.) */
    private val suggestionsTick = Runnable { updateSuggestions() }

    private fun scheduleSuggestions() {
        lastEditAt = android.os.SystemClock.uptimeMillis()
        main.removeCallbacks(suggestionsTick)
        main.postDelayed(suggestionsTick, 30L)
    }

    private fun updateSuggestions() {
        // A scheduled pass is now redundant, whoever asked for this one.
        main.removeCallbacks(suggestionsTick)
        // Words just said: their Polish (or Undo) chip holds the strip while
        // they sit right before the cursor.
        voiceSpan?.let { span ->
            val b = currentInputConnection?.getTextBeforeCursor(span.length + 8, 0)?.toString() ?: ""
            if (!searchActive && !barActive && !vaultEditActive && overlay == null && featurePanel == null &&
                !isSecureField() && voiceChipHolds(b)) {
                if (stripChipKind == "voice" && stripChip?.tag == "polishing") return
                if (showVoiceChip()) return
            } else hideVoiceChip()
        }
        if (showGlideStrip()) return
        if (searchActive || barActive || vaultEditActive || overlay != null) { showSuggestions(emptyList()); return }
        val policy = typingPolicy()
        val ic = currentInputConnection
        if (ic == null || !settings.optBoolean("candidates", true)) {
            showSuggestions(emptyList()); return
        }
        val before = ic.getTextBeforeCursor(96, 0)?.toString() ?: ""
        // The chip that was up: typed past it? (docs/STRIP-POLICY.md)
        stripPolicy.enter(policyFieldId())
        when (stripPolicy.observe(before, nowSeconds())) {
            // A copy shows once: typed past, it is done.
            StripPolicy.Seen.PasteIgnored -> markClipDone()
            else -> {}
        }
        // A form asking for something already in the vault: offer it, one tap
        // fills it. Android tells a keyboard what the field wants (hint,
        // autofill hints, input type), so this is exact here. It comes before
        // the field's word policy: it is no word suggestion, and the fields
        // that want none (an email field, a form's NO_SUGGESTIONS) are the
        // ones it is for (an email field never showed the saved email).
        if (before.isEmpty() && !isSecureField()) {
            val kind = Autofill.kind(currentInputEditorInfo)
            // Every saved value of the kind the field asks for (the cached
            // fields: decrypting the vault here ran on every pass); an email
            // field also offers a temp address beside your emails.
            val email = kind == "email"
            var fill = kind?.let { Smart.chip("", vaultFields(), fieldKind = it) }
            if (email) fill = Smart.withTempMail(fill)
            if (fill is Smart.Chip.Details) {
                // One part each, Temp mail last (the old email chip's "Temp").
                if (showDetailsChip("fill", fill, onValue = { field ->
                        currentInputConnection?.commitText(field.value, 1)
                        hideStripChip()
                    }, onTemp = {
                        hideStripChip()
                        insertTempAddress()
                    })) return
            } else if (fill is Smart.Chip.Vault) {
                // Same chip as iOS: the saved detail, Insert on the right.
                val value = fill.field.value
                if (showStripChip("fill", null, StandIns.shown(fill.field), "Insert") {
                    currentInputConnection?.commitText(value, 1)
                    hideStripChip()
                }) return
            } else if (email) {
                // An address still live is shown and put in again, not a new
                // one made (the chip cuts it short at the end).
                val live = TempMailStore.load(this)?.takeIf { System.currentTimeMillis() < it.expiresAt }
                if (showStripChip("tempfield", null, live?.address ?: "Temp email",
                        if (live != null) "Insert" else "Create") {
                    hideStripChip()
                    insertTempAddress()
                }) return
            }
        }
        if (stripChipKind == "fill" || stripChipKind == "tempfield") hideStripChip()
        if (policy and TypingEngine.SUGGESTIONS == 0) { showSuggestions(emptyList()); return }
        val word = WordContext.currentWord(before)
        val engine = KeyboardTyping.engine
        if (updateSmartChip(before)) return
        refreshClipCard()
        if (word.isEmpty()) {
            val corr = undoableCorrection(before)
            val previous = WordContext.previousWord(before)
            showSuggestions(when {
                // Apple's way: what was typed, in quotes, in the first slot; a
                // tap puts it back and teaches the engine. The next words keep
                // the other two slots once the space is in (iOS twin).
                corr != null -> listOf(Suggestion(corr.original, Suggestion.Kind.UNDO)) +
                    (if (engine != null && corr.tail == " " && previous != null)
                        engine.predictions(previous, policy, beforePrevious = WordContext.wordBeforePrevious(before))
                            .take(2).map { Suggestion(it, Suggestion.Kind.WORD) }
                    else emptyList())
                engine != null && before.endsWith(" ") && previous != null -> {
                    var words = engine.predictions(previous, policy, beforePrevious = WordContext.wordBeforePrevious(before))
                    // A sentence the person keeps sending offers its next
                    // word first: a word at a time, never the rest (D108).
                    if (policy and TypingEngine.LEARNING != 0) {
                        com.arpit.glyf.ime.typing.PhraseMemoryStore.get(this)
                            .nextWord(before.takeLast(120), com.arpit.glyf.ime.typing.TypingText.day())?.let { w ->
                                words = listOf(w) + words.filter { !it.equals(w, ignoreCase = true) }
                            }
                    }
                    val next = words.map { Suggestion(it, Suggestion.Kind.WORD) }
                    // The word just written brings its emoji to the last slot (iOS 10-07).
                    EmojiWords.emoji(previous)?.let { next.take(2) + Suggestion(it, Suggestion.Kind.EMOJI) } ?: next
                }
                else -> emptyList()
            })
            return
        }
        lastCorrection = null
        // Inside a link, an email or a handle the letters are no word: "com"
        // of alex@example.com offered come, company (2026-10-14).
        if (WordContext.insideLinkOrAddress(before)) { showSuggestions(emptyList()); return }
        val s = engineSuggestions(word, before, policy) ?: run { showSuggestions(emptyList()); return }
        val others = s.alternatives.map { Suggestion(it, Suggestion.Kind.WORD) }
        // With "Correct automatically" off the space keeps the word, so the
        // fix is offered as a plain word rather than promised in bold (iOS).
        val fixKind = if (settings.optBoolean("autocorrectApply", true)) Suggestion.Kind.CORRECTION
                      else Suggestion.Kind.WORD
        // The word being typed is never a chip (Arpit, 10-07: "feels like we
        // are wasting a suggestion"): the fix plus two words, or three words,
        // with the word's emoji in the last slot when there's no fix.
        showSuggestions(if (s.autocorrect != null) {
            listOf(Suggestion(s.autocorrect, fixKind)) + others.take(2)
        } else {
            val words = others.take(3)
            EmojiWords.emoji(word)?.let { words.take(2) + Suggestion(it, Suggestion.Kind.EMOJI) } ?: words
        })
    }

    private fun showSuggestions(items: List<Suggestion>) {
        if (!::suggestionRow.isInitialized) return
        // Words, never phrases: a slot holds one word (an emoji run counts as
        // one), D108 (Arpit, 2026-11-06: "only a single word suggestion").
        val list = items.filter { it.kind == Suggestion.Kind.EMOJI || it.text.none(Char::isWhitespace) }.take(3)
        if (list == suggestionsShown) { applySuggestionVisibility(); return }
        suggestionsShown = list
        val ink = ink()
        suggestionSlots = list.withIndex().map { (i, item) ->
            TextView(this).apply {
                text = when (item.kind) {
                    Suggestion.Kind.LITERAL -> "“${item.text}”"
                    // What was typed before the last autocorrect, in quotes,
                    // as Apple's bar offers it back.
                    Suggestion.Kind.UNDO -> "“${item.text}”"
                    else -> item.text
                }
                gravity = Gravity.CENTER
                maxLines = 1
                // Never "…": SuggestionFit picks a size the whole word fits at.
                ellipsize = null
                setHorizontallyScrolling(false)
                includeFontPadding = false
                setPadding(0, 0, 0, 0)
                textSize = if (item.kind == Suggestion.Kind.EMOJI) 22f else 17f   // the system bar's size (a 12dp cap height)
                typeface = if (item.kind == Suggestion.Kind.CORRECTION) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                setTextColor(if (item.kind == Suggestion.Kind.LITERAL) Color.argb(150, Color.red(ink), Color.green(ink), Color.blue(ink)) else ink)
                if (item.kind == Suggestion.Kind.CORRECTION) {
                    background = GradientDrawable().apply {
                        cornerRadius = dp(8).toFloat()
                        setColor(Color.argb(if (chromeDark) 40 else 22, Color.red(ink), Color.green(ink), Color.blue(ink)))
                    }
                }
                setTag(com.arpit.glyf.R.id.qa_id, "suggest:$i")
                setOnClickListener { suggestionTapped(item) }
            }
        }
        suggestionFitWidth = -1
        if (!suggestionFitListening) {
            suggestionFitListening = true
            suggestionRow.addOnLayoutChangeListener { v, l, _, r, _, _, _, _, _ ->
                if (r - l != suggestionFitWidth && r - l > 0) v.post { layoutSuggestionSlots() }
            }
        }
        layoutSuggestionSlots()
        if (list.isEmpty()) toolsPinned = false
        applySuggestionVisibility()
    }

    /** The word slots, as built for [suggestionsShown]; laid out by
     *  layoutSuggestionSlots once the row's width is known. */
    private var suggestionSlots: List<TextView> = emptyList()
    private var suggestionFitWidth = -1
    private var suggestionFitListening = false

    /** Always three slots with a hairline between them, like the system bar,
     *  every word whole: a long word shrinks to fit its slot, then takes a
     *  wider one, else it is left out (SuggestionFit, D108). */
    private fun layoutSuggestionSlots() {
        val row = suggestionRow
        val ink = ink()
        val gap = dp(3)
        // Before the first layout: the row's share of the keyboard's width.
        val width = row.width.takeIf { it > 0 } ?: (resources.displayMetrics.widthPixels - dp(64))
        suggestionFitWidth = row.width
        row.removeAllViews()
        if (suggestionSlots.isEmpty()) return
        val scaled = resources.displayMetrics.scaledDensity
        val paint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        val titles = suggestionSlots.map { it.text.toString() }
        val faces = suggestionSlots.map { it.typeface }
        val full = suggestionsShown.map { if (it.kind == Suggestion.Kind.EMOJI) 22.0 else 17.0 }
        val plan = SuggestionFit.plan(full, total = (width - 2 * gap).toDouble(), spacing = (dp(1) + 2 * gap).toDouble(),
                                      pad = dp(8).toDouble()) { i, size ->
            paint.typeface = faces[i]
            paint.textSize = (size * scaled).toFloat()
            kotlin.math.ceil(paint.measureText(titles[i]).toDouble())
        }
        for ((j, slot) in plan.withIndex()) {
            if (j > 0) row.addView(View(this).apply {
                setBackgroundColor(Color.argb(if (chromeDark) 70 else 40, Color.red(ink), Color.green(ink), Color.blue(ink)))
            }, LinearLayout.LayoutParams(dp(1), dp(22)).apply { gravity = Gravity.CENTER_VERTICAL })
            val v: View = slot.item?.let { i -> suggestionSlots[i].also { it.textSize = slot.size.toFloat() } } ?: View(this)
            (v.parent as? android.view.ViewGroup)?.removeView(v)
            row.addView(v, LinearLayout.LayoutParams(slot.width.toInt(), dp(32)).apply {
                marginStart = gap; marginEnd = gap
            })
        }
    }

    private fun applySuggestionVisibility() {
        if (stripTitleRow != null) {
            // An open panel's name owns the strip.
            suggestionRow.visibility = View.GONE
            toolIcons.visibility = View.GONE
            return
        }
        if (stripChip != null) {
            // A chip owns the strip while it is up.
            suggestionRow.visibility = View.GONE
            toolIcons.visibility = View.GONE
            return
        }
        val showing = suggestionsShown.isNotEmpty() && !toolsPinned
        suggestionRow.visibility = if (showing) View.VISIBLE else View.GONE
        toolIcons.visibility = if (showing) View.GONE else View.VISIBLE
    }

    private fun suggestionTapped(item: Suggestion) {
        // Another guess for the word a glide just put in replaces it.
        if (glideSwap(item)) return
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(96, 0)?.toString() ?: ""
        val word = WordContext.currentWord(before)
        val previous = WordContext.previousWord(before)
        val engine = KeyboardTyping.engine
        val policy = typingPolicy()
        when (item.kind) {
            Suggestion.Kind.FILL -> {
                ic.commitText(item.text, 1)
                showSuggestions(emptyList())
                return
            }
            Suggestion.Kind.UNDO -> {
                val corr = lastCorrection ?: return
                val now = ic.getTextBeforeCursor(ANCHOR_CHARS, 0)?.toString() ?: ""
                val undo = undoableCorrection(now)?.let { WordContext.undo(now, it.original, it.replacement, it.tail) }
                if (undo != null) {
                    ic.beginBatchEdit()
                    ic.deleteSurroundingText(undo.first, 0)
                    ic.commitText(undo.second, 1)
                    ic.endBatchEdit()
                    teachUndo(corr)
                }
                lastCorrection = null
            }
            Suggestion.Kind.EMOJI -> {
                // After the word, a space each side; the word itself stays.
                if (word.isNotEmpty()) engine?.commit(word, previous, false, policy)
                ic.commitText((if (word.isEmpty()) "" else " ") + item.text + " ", 1)
            }
            Suggestion.Kind.LITERAL -> {
                // Exactly what they typed, on purpose: keep it and never fix it
                // (remembered only where the field allows learning).
                if (policy and TypingEngine.LEARNING != 0) engine?.keep(word)
                engine?.commit(word, previous, false, policy)
                ic.commitText(" ", 1)
            }
            else -> {
                ic.beginBatchEdit()
                if (word.isNotEmpty()) ic.deleteSurroundingText(word.length, 0)
                ic.commitText(item.text + " ", 1)
                ic.endBatchEdit()
                engine?.commit(item.text, previous, false, policy)
            }
        }
        KeyboardTyping.scheduleSave(this)
        wordTouches.clear()
        wordTouchesFor = ""
        syncAutoShift()
        updateSuggestions()
    }

    /** A word just ended (space, punctuation, return): autocorrect it when
     *  the engine is sure, then learn what was actually kept. */
    private fun commitCurrentWord(ic: android.view.inputmethod.InputConnection) {
        val before = ic.getTextBeforeCursor(96, 0)?.toString() ?: ""
        val word = WordContext.currentWord(before)
        val touchesSnapshot = wordTouchesFor == word
        wordTouchesFor = if (touchesSnapshot) word else ""
        try {
            if (word.isEmpty()) return
            // A link, an email or a handle: its parts are not words to fix or learn.
            if (WordContext.insideLinkOrAddress(before)) return
            val engine = KeyboardTyping.engine ?: return
            val policy = typingPolicy()
            val previous = WordContext.previousWord(before)
            val head = before.substring(0, before.length - word.length)
            val sentenceStart = WordContext.wantsCapital(head)
            var kept = word
            // What this word may teach: a typo left standing teaches nothing.
            var learn = policy
            val nowMs = System.currentTimeMillis()
            recentFixes.removeAll { nowMs - it.at > 300_000 }
            val refused = recentFixes.firstOrNull { it.touched && it.original.equals(word, ignoreCase = true) }
            if (refused != null) {
                // Corrected, gone back into, and typed the same again: keep it.
                recentFixes.remove(refused)
                if (policy and TypingEngine.LEARNING != 0) engine.revert(word, refused.replacement)
            } else if (policy and TypingEngine.AUTOCORRECT != 0) {
                val fix = engineSuggestions(word, before, policy)?.autocorrect
                // "Correct automatically" off: the word stands exactly as
                // typed and the fix waits in the strip for a tap (iOS twin).
                // Left standing but not chosen, it is not learned: typed
                // twice it would never be fixed again (RESEARCH-IMPROVEMENTS-APP 12).
                if (fix != null && fix != word && !settings.optBoolean("autocorrectApply", true)) {
                    learn = learn and TypingEngine.LEARNING.inv()
                }
                if (fix != null && fix != word && settings.optBoolean("autocorrectApply", true)) {
                    ic.beginBatchEdit()
                    ic.deleteSurroundingText(word.length, 0)
                    ic.commitText(fix, 1)
                    if (selStart >= 0) {
                        ic.commitCorrection(android.view.inputmethod.CorrectionInfo(selStart - word.length, word, fix))
                    }
                    ic.endBatchEdit()
                    lastCorrection = Correction(word, fix, fromEngine = true)
                    recentFixes.add(RecentFix(word, fix, nowMs))
                    while (recentFixes.size > 8) recentFixes.removeAt(0)
                    kept = fix
                    // A capital typed mid-sentence was meant: twice, and it's a name.
                    engine.noteCorrected(word, fix, sentenceStart, policy)
                }
            } else if (policy and TypingEngine.LEARNING != 0 && !settings.optBoolean("autocorrect", true) &&
                engine.wouldFix(word, previous, sentenceStart, WordContext.wordBeforePrevious(before))) {
                // Autocorrect switched off: what it would have fixed is a
                // typo, not a word to learn. (Fields that turn suggestions
                // off — NO_SUGGESTIONS, passwords, URI, email — have no
                // policy at all, so nothing is learned there.)
                learn = learn and TypingEngine.LEARNING.inv()
            }
            val autoCapitalized = sentenceStart && settings.optBoolean("autocapitalize", true)
            engine.commit(kept, previous, autoCapitalized, learn)
            KeyboardTyping.scheduleSave(this)
        } finally {
            wordTouches.clear()
            wordTouchesFor = ""
        }
    }

    /** Field-aware autocap, the Android way: getCursorCapsMode already
     *  honors the editor's cap flags — Apple-parity for free. */
    private fun syncAutoShift() {
        if (searchActive || barActive || vaultEditActive) return
        if (keyboard.mode != Mode.LETTERS) return
        if (!settings.optBoolean("autocapitalize", true)) {
            // Turned off: a shift the board put on by itself is let go too
            // (iOS's first letter came out capital anyway, 2026-10-14).
            if (keyboard.shifted && autoShifted) {
                keyboard.shifted = false
                autoShifted = false
                keyboard.invalidate()
            }
            return
        }
        val ei = currentInputEditorInfo ?: return
        val ic = currentInputConnection ?: return
        val caps = if (ei.inputType != InputType.TYPE_NULL)
            ic.getCursorCapsMode(ei.inputType) else 0
        val wants = caps != 0
        if (wants != keyboard.shifted) {
            keyboard.shifted = wants
            autoShifted = wants
            keyboard.invalidate()
        }
    }

    // Glide typing (Arpit, 2026-10-07: "implement glide typing, like glide
    // over keyboard to type; its guesses needs to be perfect too"; 10-08:
    // "do glide and other things u made for android as well"). The iOS
    // twin is GlyfKeyboardViewController's "Glide typing" block: the lift
    // puts the best guess and a space in, the other guesses wait in the
    // strip while the caret stays after the word, a tap on one swaps it, and
    // one backspace takes the word and its space and offers them back.

    private var glideDecoder: com.arpit.glyf.ime.typing.GlideDecoder? = null
    private var glide: com.arpit.glyf.ime.typing.GlideState? = null
    /** The words the strip offers after a glide, while the text before the
     *  caret is still [Pair.first]. */
    private var glideStrip: Pair<String, List<String>>? = null

    override fun glideAllowed(): Boolean =
        settings.optBoolean("glideTyping", true) && bindingsLive() &&
            typingPolicy() and TypingEngine.SUGGESTIONS != 0

    override fun onGlideMoved(points: List<com.arpit.glyf.ime.typing.GlidePoint>,
                              layout: com.arpit.glyf.ime.typing.GlideDecoder.Layout): String? =
        glideDecode(points, layout, 1).firstOrNull()?.word

    override fun onGlideEnded(points: List<com.arpit.glyf.ime.typing.GlidePoint>,
                              layout: com.arpit.glyf.ime.typing.GlideDecoder.Layout) {
        val guesses = glideDecode(points, layout, 4).map { it.word }
        val word = guesses.firstOrNull() ?: return
        val ic = currentInputConnection ?: return
        val policy = typingPolicy()
        val before = ic.getTextBeforeCursor(96, 0)?.toString() ?: ""
        val typing = WordContext.currentWord(before)
        if (typing.isNotEmpty()) {
            // A word being typed is finished first, the way the space bar would.
            commitCurrentWord(ic)
            ic.commitText(" ", 1)
        } else if (before.isNotEmpty() && before.last() in WordContext.CORRECTION_BOUNDARIES) {
            // "hello," then a glide: the word gets its space, as Apple's does.
            ic.commitText(" ", 1)
        }
        val previous = if (typing.isEmpty()) WordContext.previousWord(before) else typing
        val capitalized = keyboard.shifted
        ic.commitText("$word ", 1)
        lastCorrection = null
        wordTouches.clear()
        wordTouchesFor = ""
        val anchor = anchorHere(ic) ?: ""
        glide = com.arpit.glyf.ime.typing.GlideState(word, guesses.drop(1), anchor)
        glideStrip = anchor to guesses.drop(1)
        KeyboardTyping.engine?.commit(word, previous, capitalized, policy)
        KeyboardTyping.scheduleSave(this)
        // Shift is one word's.
        if (keyboard.shifted) {
            keyboard.shifted = false
            autoShifted = false
            keyboard.invalidate()
        }
        syncAutoShift()
        updateSuggestions()
    }

    /** The decoder over the base dictionary, once the engine has loaded it. */
    private fun glideDecoderReady(): com.arpit.glyf.ime.typing.GlideDecoder? {
        if (glideDecoder == null) {
            KeyboardTyping.engine?.base?.let { glideDecoder = com.arpit.glyf.ime.typing.GlideDecoder(it) }
        }
        return glideDecoder
    }

    /** The words before the caret, the capitals the board shows, and this
     *  person's own words, for the decoder's language side. */
    private fun glideDecode(points: List<com.arpit.glyf.ime.typing.GlidePoint>,
                            layout: com.arpit.glyf.ime.typing.GlideDecoder.Layout,
                            limit: Int): List<com.arpit.glyf.ime.typing.GlideDecoder.Candidate> {
        val engine = KeyboardTyping.engine ?: return emptyList()
        val decoder = glideDecoderReady() ?: return emptyList()
        val before = currentInputConnection?.getTextBeforeCursor(96, 0)?.toString() ?: ""
        val current = WordContext.currentWord(before)
        // A word being typed is finished first, so it becomes the previous one.
        val previous = if (current.isEmpty()) WordContext.previousWord(before) else current
        val beforePrevious = if (current.isEmpty()) WordContext.wordBeforePrevious(before) else WordContext.previousWord(before)
        val context = com.arpit.glyf.ime.typing.GlideDecoder.Context(
            previous = previous, beforePrevious = beforePrevious,
            capitals = if (keyboard.capsLock) com.arpit.glyf.ime.typing.GlideDecoder.Capitals.ALL
                       else if (keyboard.shifted) com.arpit.glyf.ime.typing.GlideDecoder.Capitals.FIRST
                       else com.arpit.glyf.ime.typing.GlideDecoder.Capitals.NONE,
            personal = engine.personal)
        return decoder.decode(points, layout, context, limit)
    }

    /** The glide's other guesses, while the caret is still right after it;
     *  false once anything else happened, and the usual strip takes over. */
    private fun showGlideStrip(): Boolean {
        val strip = glideStrip ?: return false
        val ic = currentInputConnection
        if (ic == null || searchActive || barActive || vaultEditActive || overlay != null ||
            !settings.optBoolean("candidates", true) || strip.second.isEmpty() || anchorHere(ic) != strip.first) {
            glideStrip = null
            return false
        }
        if (stripChip != null) hideStripChip()
        toolsPinned = false
        showSuggestions(strip.second.take(3).map { Suggestion(it, Suggestion.Kind.WORD) })
        return true
    }

    /** One backspace right after a glide removes the word and its space and
     *  offers it and the other guesses back; the next backspace is ordinary. */
    private fun glideBackspace(ic: android.view.inputmethod.InputConnection): Boolean {
        val g = glide ?: return false
        glide = null
        if (!g.isCurrent(anchorHere(ic))) return false
        ic.deleteSurroundingText(g.deleteCount, 0)
        lastCorrection = null
        glideStrip = (anchorHere(ic) ?: "") to (listOf(g.word) + g.alternatives)
        syncAutoShift()
        updateSuggestions()
        return true
    }

    /** A tap on another guess swaps the glided word for it. */
    private fun glideSwap(item: Suggestion): Boolean {
        if (item.kind != Suggestion.Kind.WORD) return false
        val g = glide ?: return false
        val ic = currentInputConnection ?: return false
        if (!g.isCurrent(anchorHere(ic))) return false
        ic.beginBatchEdit()
        ic.deleteSurroundingText(g.deleteCount, 0)
        ic.commitText(item.text + " ", 1)
        ic.endBatchEdit()
        val anchor = anchorHere(ic) ?: ""
        val others = g.others(item.text)
        glide = com.arpit.glyf.ime.typing.GlideState(item.text, others, anchor)
        glideStrip = anchor to others
        KeyboardTyping.engine?.commit(item.text, g.previousWord, false, typingPolicy())
        KeyboardTyping.scheduleSave(this)
        syncAutoShift()
        updateSuggestions()
        return true
    }

    // MARK: bound keys → run → preview (the §6.4 loop, Android slice)

    /** Holds run their bindings only over the host field: never while the
     *  keys type into one of Glyf's own strips (a second strip would stack
     *  on the first), and never in a password (iOS kbBindingsLive). */
    override fun bindingsLive(): Boolean =
        !searchActive && !barActive && !vaultEditActive && emojiBoard?.searchActive != true &&
            (featurePanel as? CalendarPanelView)?.typing == null && !isSecureField()

    override fun onBoundKeyHeld(char: String, glyfId: String) {
        // Something opened a strip while the key was held: it is a letter.
        if (!bindingsLive()) {
            onKey(char, if (keyboard.shifted) char.uppercase() else char)
            return
        }
        runBinding(char, glyfId)
    }

    /** What a bound key does: held on the keys, or tapped in My glyfs. */
    private fun runBinding(char: String, glyfId: String) {
        when (glyfId) {
            "surface:vault" -> { showVaultPanel(); return }
            // The vault panel is where the notes are.
            "surface:notes" -> { showVaultPanel(); return }
            "surface:translate-hud" -> { runTranslateOnField(); return }
            "surface:tones" -> { showTonesPanel(char); return }
            // C by default: the calendar lives in the keyboard, not the app.
            "connector:calendar", "connector:mockcal" -> { dismissFeaturePanel(); showCalendarPanel(); return }
            "connector:meet" -> { insertMeetLink(); return }
        }
        if (glyfId.startsWith("surface:") || glyfId.startsWith("connector:")) {
            openApp()
            return
        }
        if (isSecureField()) return // no AI in password fields
        startSkill(char, glyfId)
    }

    /** A fresh Google Meet link, straight into the message. */
    private fun insertMeetLink() {
        CallLink.make(this) { url, note ->
            if (url == null) {
                note?.let { notice(it) }
                return@make
            }
            val ic = currentInputConnection ?: return@make
            val last = ic.getTextBeforeCursor(1, 0)?.lastOrNull()
            ic.commitText((if (last != null && !last.isWhitespace()) " " else "") + "Join me on a call: $url", 1)
            updateSuggestions()
        }
    }

    private fun dismissOverlay() {
        overlay?.let { root.removeView(it) }
        overlay = null
        if (::keyboard.isInitialized) {
            keyboard.visibility = View.VISIBLE
            toolbar.visibility = View.VISIBLE
        }
    }

    // MARK: feature panels (iOS shell parity: menu grid, vault, notes, emoji)

    private var featurePanel: View? = null

    private fun dismissFeaturePanel() {
        (featurePanel as? GamesPanelView)?.stop()
        featurePanel?.let { root.removeView(it) }
        featurePanel = null
        emojiBoard = null
        if (vaultAddOpen) watchBack(false)
        showVaultAdd = null
        vaultAddOpen = false
        slideStripTools { gPill?.closing = false }
        clearStripTitle()
        dropMarker?.let { if (::toolIcons.isInitialized) toolIcons.removeView(it) }
        dropMarker = null
        keyboard.visibility = View.VISIBLE
        // The clipboard panel takes the toolbar's space too; always give it back.
        if (::toolbar.isInitialized) toolbar.visibility = View.VISIBLE
    }

    /** A panel in place of the keys: [panel] the whole of it, [body] its rows,
     *  which scroll inside [stage], the frame for anything that floats over
     *  them, and [back], the strip's ‹ (null with no step back). */
    private data class PanelShell(val panel: LinearLayout, val body: LinearLayout,
                                  val stage: FrameLayout, val back: View?)

    /** Container that replaces the keys. As on the iPhone, the panel spends
     *  no row on its own header: the strip names it, the g key is its ✕ and
     *  a ‹ leads where it has a step back ([onBack]; a panel opened as a
     *  tool steps back to the g menu, as iOS's shell does).
     *  @param bottomBar adds the ABC / backspace row the system emoji
     *  keyboard has at its foot — muscle memory, on both platforms.
     *  @param pad the body's padding in dp (left, top, right, bottom). */
    private fun panelShell(title: String, bottomBar: Boolean = false,
                           onBack: (() -> Unit)? = { showMenuGrid() },
                           pad: IntArray = intArrayOf(10, 2, 10, 8), icon: String? = null,
                           /** One of iOS's shell screens, which the Glass look heads. */
                           shell: Boolean = true): PanelShell {
        dismissFeaturePanel()
        keyboard.visibility = View.GONE
        val panel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(pad[0]), dp(pad[1]), dp(pad[2]), dp(pad[3]))
        }
        val scroll = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            addView(body)
        }
        val stage = FrameLayout(this).apply {
            addView(scroll, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        }
        val barH = if (bottomBar) dp(40) else 0
        // The Glass look gives each screen a header row of its own, as iOS's
        // shell does there (‹, the name, ✕), under the strip's.
        val header = if (glassLook && shell) FrameLayout(this) else null
        val headerH = if (header != null) dp(36) else 0
        if (header != null) panel.addView(header, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, headerH))
        panel.addView(stage, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, keyboard.height - barH - headerH))
        if (bottomBar) {
            val bar = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(10), 0, dp(10), 0)
            }
            bar.addView(TextView(this).apply {
                text = "ABC"; textSize = 15f; setTextColor(ink())
                setPadding(dp(6), dp(6), dp(14), dp(6))
                setTag(com.arpit.glyf.R.id.qa_id, "panel:abc")
                setOnClickListener { dismissFeaturePanel() }
            })
            bar.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
            bar.addView(TextView(this).apply {
                text = "⌫"; textSize = 18f; setTextColor(ink())
                setPadding(dp(14), dp(4), dp(8), dp(4))
                setOnClickListener { onKey("delete", null) }
            })
            panel.addView(bar, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, barH))
        }
        root.addView(panel)
        featurePanel = panel
        val back = showStripTitle(title, onBack, icon)
        if (header != null) fillShellHeader(header, title, onBack, back)
        return PanelShell(panel, body, stage, back)
    }

    /** The app's Glass look (Keyboard › Look › Glass): iOS draws its shell
     *  as lists there (GlyfShell with solidLook off), each screen under a
     *  header row of its own, every row 52 tall, and the vault a list. */
    private val glassLook get() = keyboard.keyTheme == "glass" && keyboard.themeBg.isEmpty()

    private fun shellRows(body: LinearLayout) =
        ShellRows(this, body, if (glassLook) ShellRows.TWO_LINE_H else ShellRows.ROW_H)

    /** iOS's shell header in the Glass look: ‹ (the same step back as the
     *  strip's, options put away first), the name centred, ✕ in grey. */
    private fun fillShellHeader(header: FrameLayout, title: String, onBack: (() -> Unit)?, stripBack: View?) {
        if (onBack != null) header.addView(ToolIcon(this, "chevron", Glass.textPrimary).apply {
            solid = true; weight = 1.7f; scale = 1.25f
            setTag(com.arpit.glyf.R.id.qa_id, "shell:back"); contentDescription = "Back"
            setOnClickListener { if (stripBack != null) stripBack.performClick() else onBack() }
        }, FrameLayout.LayoutParams(dp(44), FrameLayout.LayoutParams.MATCH_PARENT).apply { leftMargin = dp(4) })
        header.addView(TextView(this).apply {
            text = title
            Glass.style(this, 15f, Glass.SEMIBOLD)
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT).apply {
            leftMargin = dp(52); rightMargin = dp(52)
        })
        header.addView(ToolIcon(this, "close", Glass.textSecondary).apply {
            solid = true; weight = 1.5f; scale = 1.45f
            setTag(com.arpit.glyf.R.id.qa_id, "shell:close"); contentDescription = "Close"
            setOnClickListener { dismissFeaturePanel() }
        }, FrameLayout.LayoutParams(dp(44), FrameLayout.LayoutParams.MATCH_PARENT, Gravity.END).apply { rightMargin = dp(4) })
    }

    /** "Open in Glyf app ↗" at the foot of a Glass-look list that has more
     *  in the app (iOS's footer, 30 tall); what scrolls ends above it. */
    private fun pinOpenInApp(stage: FrameLayout, path: String): Int {
        val h = dp(30)
        stage.getChildAt(0)?.let { scroll ->
            scroll.layoutParams = (scroll.layoutParams as FrameLayout.LayoutParams).apply { bottomMargin = h }
        }
        stage.addView(TextView(this).apply {
            text = "Open in Glyf app ↗"
            Glass.style(this, 13f, Glass.MEDIUM, Glass.accentPrimary)
            gravity = Gravity.CENTER
            setTag(com.arpit.glyf.R.id.qa_id, "shell:openapp")
            setOnClickListener { dismissFeaturePanel(); openAppPath(path) }
        }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, h, Gravity.BOTTOM))
        return h
    }

    private fun cardRow(body: LinearLayout, title: String, snippet: String,
                        onTap: () -> Unit) {
        val cardV = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat(); setColor(card())
            }
            setOnClickListener { onTap() }
        }
        cardV.addView(TextView(this).apply {
            text = title; textSize = 14f; setTextColor(ink())
            typeface = Typeface.DEFAULT_BOLD; maxLines = 1
        })
        if (snippet.isNotBlank()) cardV.addView(TextView(this).apply {
            text = snippet; textSize = 12f
            setTextColor(Color.argb(160, 128, 128, 136)); maxLines = 2
        })
        val lp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT)
        lp.setMargins(0, 0, 0, dp(7))
        body.addView(cardV, lp)
    }

    /** The g menu: every tool the strip doesn't show, in one scrolling grid
     *  (ToolMenuView), the twin of the iOS shell. The strip stays up so a
     *  tile can be dropped on it, and the g pill turns into the way out. */
    private fun showMenuGrid() {
        dismissFeaturePanel()
        if (toolbar.height == 0) return
        val panelH = keyboard.height
        keyboard.visibility = View.GONE
        toolsPinned = true
        applySuggestionVisibility()
        val menu = ToolMenuView(this, keyboard.palette(), onStrip = stripShown,
            onOpen = { id -> openTool(id) },
            onDragOverStrip = { rawX -> showStripDropMarker(rawX) },
            onPinToStrip = { id, rawX -> pinToStrip(id, rawX) },
            onSponsor = { showSponsorPanel(it) },
        )
        root.addView(menu, root.indexOfChild(keyboard) + 1,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, panelH))
        featurePanel = menu
        slideStripTools { gPill?.closing = true }
    }

    private var dropMarker: View? = null

    private fun stripIndexAt(rawX: Float): Int {
        val loc = IntArray(2)
        for (i in 0 until toolIcons.childCount) {
            val child = toolIcons.getChildAt(i)
            if (child === dropMarker) continue
            child.getLocationOnScreen(loc)
            if (rawX < loc[0] + child.width / 2f) return i
        }
        return toolIcons.childCount
    }

    private fun showStripDropMarker(rawX: Float?) {
        dropMarker?.let { toolIcons.removeView(it) }
        dropMarker = null
        if (rawX == null) return
        val marker = View(this).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(2).toFloat()
                setColor(Color.rgb(0x7C, 0x5C, 0xFF))
            }
        }
        val index = stripIndexAt(rawX).coerceAtMost(toolIcons.childCount)
        toolIcons.addView(marker, index, LinearLayout.LayoutParams(dp(3), dp(24)))
        dropMarker = marker
    }

    private fun pinToStrip(id: String, rawX: Float) {
        showStripDropMarker(null)
        val current = stripTools().toMutableList()
        val index = stripIndexAt(rawX).coerceIn(0, current.size)
        val existing = current.indexOf(id)
        if (existing >= 0) current.removeAt(existing)
        current.add(if (existing in 0 until index) index - 1 else index, id)
        val hidden = settings.optJSONArray("toolbarHidden")
        val keepHidden = org.json.JSONArray()
        for (i in 0 until (hidden?.length() ?: 0)) {
            if (hidden!!.optString(i) != id) keepHidden.put(hidden.optString(i))
        }
        settings.put("toolbarOrder", org.json.JSONArray(current))
        settings.put("toolbarHidden", keepHidden)
        SettingsStore.save(this, settings.toString())
        dismissFeaturePanel()
        buildToolbar(keyboard.isDark || keyboard.themeBg.isNotEmpty())
        notice("Added to the strip")
    }

    // MARK: strip customising (hold a tool, drag it; iOS's twin)

    /** The strip tool being dragged, and the copy of it under the finger
     *  (iOS dragGhost), in the root's overlay so it can cross from the strip
     *  into the g menu. */
    private var draggingTool: String? = null
    private var dragGhost: View? = null

    /** Hold a strip tool and it lifts (iOS Toolbar.itemLong): slide it along
     *  the strip to reorder, or down into the g menu's grid to keep it there.
     *  A tap is still a tap. */
    private inner class StripToolTouch(private val id: String) : View.OnTouchListener {
        private val slop = android.view.ViewConfiguration.get(this@GlyfIME).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var held: View? = null
        private val lift = Runnable { held?.let { beginToolDrag(id, it, downX, downY) } }

        override fun onTouch(v: View, e: android.view.MotionEvent): Boolean {
            when (e.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    held = v
                    main.postDelayed(lift, 320)
                }
                android.view.MotionEvent.ACTION_MOVE -> when {
                    draggingTool == id -> moveToolDrag(e.rawX, e.rawY)
                    // Moving first is not a pick-up.
                    abs(e.rawX - downX) > slop || abs(e.rawY - downY) > slop -> main.removeCallbacks(lift)
                }
                android.view.MotionEvent.ACTION_UP -> {
                    main.removeCallbacks(lift)
                    // Posted, as a view's own click is: a tool may rebuild
                    // the strip this touch is still being handed through.
                    if (draggingTool == id) stripToolDropped(id, v, e.rawX, e.rawY)
                    else if (e.x >= -slop && e.y >= -slop && e.x <= v.width + slop && e.y <= v.height + slop) main.post { v.performClick() }
                }
                android.view.MotionEvent.ACTION_CANCEL -> {
                    main.removeCallbacks(lift)
                    if (draggingTool == id) stripToolDropped(id, v, null, null)
                }
            }
            return true
        }
    }

    private fun beginToolDrag(id: String, from: View, rawX: Float, rawY: Float) {
        draggingTool = id
        from.alpha = 0.25f
        from.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        // iOS's ghost: the tool on a 44 card, 12 corners, a soft shadow.
        val side = dp(44)
        val ghost = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(Glass.surfaceCard)
            }
            elevation = dp(6).toFloat()
            addView(ToolIcon(this@GlyfIME, id, Glass.textPrimary).apply {
                scale = 1.4f; weight = 1.25f; solid = true
            }, FrameLayout.LayoutParams(side, side, Gravity.CENTER))
        }
        ghost.measure(View.MeasureSpec.makeMeasureSpec(side, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(side, View.MeasureSpec.EXACTLY))
        ghost.layout(0, 0, side, side)
        root.overlay.add(ghost)
        dragGhost = ghost
        moveToolDrag(rawX, rawY)
    }

    private fun moveToolDrag(rawX: Float, rawY: Float) {
        val id = draggingTool ?: return
        dragGhost?.let { g ->
            val at = IntArray(2).also { root.getLocationOnScreen(it) }
            val l = Math.round(rawX - at[0] - g.width / 2f)
            val t = Math.round(rawY - at[1] - g.height / 2f)
            g.layout(l, t, l + g.width, t + g.height)
        }
        val overStrip = stripContains(rawX, rawY)
        showStripDropMarker(if (overStrip) rawX else null)
        // Over the g menu's grid, the tiles open a slot where it would land.
        (featurePanel as? ToolMenuView)?.hoverIncoming(id, if (overStrip) null else rawX, rawY)
    }

    /** Over the strip, with iOS's allowance round it (toolbarContains). */
    private fun stripContains(rawX: Float, rawY: Float): Boolean {
        val at = IntArray(2).also { toolbar.getLocationOnScreen(it) }
        return rawX >= at[0] - dp(8) && rawX <= at[0] + toolbar.width + dp(8) &&
            rawY >= at[1] - dp(10) && rawY <= at[1] + toolbar.height + dp(10)
    }

    /** A held strip tool let go (raw point; nulls when the touch was taken
     *  away). Along the strip it takes its new place; over the g menu's grid
     *  it lands in the slot it opened there and the strip closes behind it
     *  (Arpit, 2026-10-06: "when i drag the icon from top strip into below
     *  area, it should come in the below area not disaaper, it should move
     *  from up to down"); anywhere else it goes back to its place. The strip
     *  changes once this touch is through: the held view is its target. */
    private fun stripToolDropped(id: String, view: View, rawX: Float?, rawY: Float?) {
        val menu = featurePanel as? ToolMenuView
        val at = if (rawX != null && rawY != null) rawX to rawY else null
        if (at != null && stripContains(at.first, at.second)) {
            menu?.hoverIncoming(id, null, null)
            settleToolDrag(null)
            view.alpha = 1f
            moveStripTool(id, view, stripIndexAt(at.first))
            return
        }
        val landed = at?.let { menu?.landIncoming(id, it.first, it.second) }
        if (menu != null && landed != null) {
            settleToolDrag(landed.first)
            menu.revealTile(id)
            val was = settings.optJSONArray("toolbarHidden")
            val hidden = (0 until (was?.length() ?: 0)).map { was!!.optString(it) }.filter { it != id } + id
            settings.put("toolbarOrder", org.json.JSONArray(stripTools().filter { it != id } + hidden))
            settings.put("toolbarHidden", org.json.JSONArray(hidden))
            settings.put("menuOrder", org.json.JSONArray(landed.second))
            SettingsStore.save(this, settings.toString())
            stripShown = stripShown - id
            main.post { slideStripTools { toolIcons.removeView(view) } }
            return
        }
        menu?.hoverIncoming(id, null, null)
        val home = if (view.isAttachedToWindow) IntArray(2).also { view.getLocationOnScreen(it) } else null
        settleToolDrag(home?.let {
            val cx = it[0] + view.width / 2
            val cy = it[1] + view.height / 2
            android.graphics.Rect(cx - dp(22), cy - dp(22), cx + dp(22), cy + dp(22))
        })
        view.animate().alpha(1f).setDuration(240).start()
    }

    /** A strip tool moved along the strip to [index], counted with it still
     *  in its old place. */
    private fun moveStripTool(id: String, view: View, index: Int) {
        val shown = stripTools().toMutableList()
        val from = shown.indexOf(id)
        if (from < 0) return
        val to = (if (from < index) index - 1 else index).coerceIn(0, shown.size - 1)
        if (to == from) return
        shown.removeAt(from)
        shown.add(to, id)
        val was = settings.optJSONArray("toolbarHidden")
        val hidden = (0 until (was?.length() ?: 0)).map { was!!.optString(it) }
        settings.put("toolbarOrder", org.json.JSONArray(shown + hidden.filter { it !in shown }))
        SettingsStore.save(this, settings.toString())
        main.post {
            if (view.parent !== toolIcons) return@post
            slideStripTools {
                toolIcons.removeView(view)
                toolIcons.addView(view, to.coerceAtMost(toolIcons.childCount))
            }
        }
    }

    /** The strip's tools glide from where they were to where [change] puts
     *  them, as iOS's row does (Toolbar.removeItem, and the surface spring
     *  as the g turns into ✕ and back). */
    private fun slideStripTools(change: () -> Unit) {
        if (!::toolIcons.isInitialized || !toolIcons.isAttachedToWindow) return change()
        val row = toolIcons
        val was = HashMap<View, Float>()
        for (i in 0 until row.childCount) row.getChildAt(i).let { if (it.width > 0) was[it] = it.x + it.width / 2f }
        change()
        val observer = row.viewTreeObserver
        observer.addOnPreDrawListener(object : android.view.ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                (if (observer.isAlive) observer else row.viewTreeObserver).removeOnPreDrawListener(this)
                for (i in 0 until row.childCount) {
                    val v = row.getChildAt(i)
                    val dx = (was[v] ?: continue) - (v.left + v.width / 2f)
                    if (dx == 0f) continue
                    v.translationX = dx
                    v.animate().translationX(0f).setDuration(240).start()
                }
                return true
            }
        })
    }

    /** The ghost settles on where the tool now lives ([target], on screen),
     *  taking its size as it fades into it; with nowhere to go it just goes. */
    private fun settleToolDrag(target: android.graphics.Rect?) {
        val ghost = dragGhost
        dragGhost = null
        draggingTool = null
        showStripDropMarker(null)
        if (ghost == null) return
        if (target == null) {
            root.overlay.remove(ghost)
            return
        }
        val at = IntArray(2).also { root.getLocationOnScreen(it) }
        val from = android.graphics.Rect(ghost.left, ghost.top, ghost.right, ghost.bottom)
        val to = android.graphics.Rect(target).apply { offset(-at[0], -at[1]) }
        android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 240
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener {
                val f = it.animatedFraction
                ghost.layout(from.left + Math.round((to.left - from.left) * f),
                    from.top + Math.round((to.top - from.top) * f),
                    from.right + Math.round((to.right - from.right) * f),
                    from.bottom + Math.round((to.bottom - from.bottom) * f))
                ghost.alpha = 1f - f
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    root.overlay.remove(ghost)
                }
            })
            start()
        }
    }

    /** My glyfs: what each key holds first ("Hold V"), then the glyfs this
     *  person built that are on no key, then Build your own, as iOS lists
     *  them: one grouped card of rows, each with its tool's mark. A tap does
     *  what holding the key does (the Keys panel said the same, so it went). */
    private fun showMyGlyfsPanel() {
        val (_, body) = panelShell("My glyfs", pad = intArrayOf(0, 0, 0, 8))
        val rows = shellRows(body)
        val bindings = settings.optJSONObject("bindings")
        val bound = mutableSetOf<String>()
        for (letter in "qwertyuiopasdfghjklzxcvbnm".map { it.toString() }) {
            val target = bindings?.optString(letter)?.takeIf { it.isNotBlank() } ?: continue
            bound.add(target)
            rows.row(ShellRows.Row(bindingTitle(target), glyph = bindingGlyph(target),
                detail = "Hold ${letter.uppercase()}", qaId = "glyfs:key:$letter") {
                dismissFeaturePanel()
                runBinding(letter, target)
            })
        }
        val titles = settings.optJSONObject("customTitles")
        val own = titles?.keys()?.asSequence()?.filter { it !in bound }
            ?.sortedBy { skillTitle(it).lowercase() }?.toList() ?: emptyList()
        for ((i, id) in own.withIndex()) {
            rows.row(ShellRows.Row(skillTitle(id), glyph = "ask", qaId = "glyfs:own:$i") {
                dismissFeaturePanel()
                startSkill("", id)
            })
        }
        rows.row(ShellRows.Row("Build your own", glyph = "plus", qaId = "glyfs:build") {
            dismissFeaturePanel(); openAppPath("build")
        })
        rows.flush()
    }

    /** Style (Arpit, 2026-10-03: "option to stylise text in glyf menu like
     *  bold italic underline, cut, etc"): each style shows what it makes of
     *  the words picked out, or of the message so far, and a tap restyles
     *  them (GlyfShell's "style"). */
    private fun showStylePanel() {
        val (_, body) = panelShell("Style", pad = intArrayOf(0, 0, 0, 8))
        val rows = shellRows(body)
        val ic = currentInputConnection
        val picked = ic?.getSelectedText(0)?.toString().orEmpty()
        val sample = picked.ifEmpty { ic?.getTextBeforeCursor(2000, 0)?.toString().orEmpty() }.trim()
        rows.header(if (sample.isEmpty()) "Type something, then pick a style" else "Tap a style to restyle your text")
        // How long it is, for a post or a bio with a limit.
        if (sample.isNotEmpty()) rows.row(ShellRows.Row(Smart.textCount(sample), letter = "#", chevron = false, qaId = "shell:style:count"))
        for (style in Smart.TextStyle.values()) {
            val text = if (sample.isEmpty()) style.title else sample.take(40)
            rows.row(ShellRows.Row(Smart.styled(text, style), letter = styleLetter(style), detail = style.title,
                qaId = "shell:style:${style.id}") { applyStyle(style) })
        }
        rows.flush()
    }

    private fun styleLetter(style: Smart.TextStyle) = when (style) {
        Smart.TextStyle.BOLD, Smart.TextStyle.SERIF_BOLD -> "B"
        Smart.TextStyle.ITALIC -> "I"
        Smart.TextStyle.BOLD_ITALIC -> "BI"
        Smart.TextStyle.UNDERLINE -> "U"
        Smart.TextStyle.STRIKE -> "S"
        Smart.TextStyle.SCRIPT -> "𝓢"
        Smart.TextStyle.DOUBLE_STRUCK -> "𝔻"
        Smart.TextStyle.MONOSPACE -> "M"
        Smart.TextStyle.BUBBLE -> "Ⓐ"
        Smart.TextStyle.SMALL_CAPS -> "ᴀ"
        Smart.TextStyle.WIDE -> "Ｗ"
        Smart.TextStyle.UPSIDE_DOWN -> "∀"
        Smart.TextStyle.PLAIN -> "Aa"
        Smart.TextStyle.UPPER -> "AB"
        Smart.TextStyle.LOWER -> "ab"
        Smart.TextStyle.TITLE_CASE -> "Ab"
        Smart.TextStyle.SENTENCE_CASE -> "A."
    }

    /** A shorthand's blanks filled where the phone is ({date}, {clipboard}…). */
    private fun fillShorthand(template: String): Pair<String, Int> =
        Smart.fillIn(template, region = settings.optString("region").ifEmpty { java.util.Locale.getDefault().country },
            clipboard = { com.arpit.glyf.store.ClipboardStore.clipText(this) })

    /** A shorthand typed out from the vault, its blanks filled. */
    private fun insertShorthand(template: String) {
        val ic = currentInputConnection ?: return
        val (text, back) = fillShorthand(template)
        ic.commitText(text, 1)
        if (back > 0) cursorBack(ic, back)
    }

    /** The cursor moved back into what was just typed ({cursor}). */
    private fun cursorBack(ic: android.view.inputmethod.InputConnection, back: Int) {
        val et = ic.getExtractedText(android.view.inputmethod.ExtractedTextRequest(), 0) ?: return
        val at = et.startOffset + et.selectionStart - back
        if (at >= 0) ic.setSelection(at, at)
    }

    /** The words picked out become their styled form; with none, the
     *  message so far does. */
    private fun applyStyle(style: Smart.TextStyle) {
        val ic = currentInputConnection ?: return
        val picked = ic.getSelectedText(0)?.toString().orEmpty()
        if (picked.isNotEmpty()) {
            ic.commitText(Smart.styled(picked, style), 1)
        } else {
            val before = ic.getTextBeforeCursor(2000, 0)?.toString().orEmpty()
            if (before.isBlank()) { notice("Type something first"); return }
            ic.deleteSurroundingText(before.length, 0)
            ic.commitText(Smart.styled(before, style), 1)
        }
        dismissFeaturePanel()
        notice(style.title)
        updateSuggestions()
    }

    /** The keyboard's settings, in the keyboard, as the iPhone keeps them
     *  (GlyfShell "settings"): the same sections and words as the app's
     *  Keyboard screen, a switch per row, the whole row flipping it. */
    private fun showSettingsPanel() {
        val (_, body) = panelShell("Settings", pad = intArrayOf(0, 0, 0, 8))
        val rows = shellRows(body)
        fun toggle(title: String, key: String, default: Boolean, apply: (Boolean) -> Unit = {}) {
            val sw = GlassSwitch(this, settings.optBoolean(key, default)) { on ->
                settings.put(key, on)
                SettingsStore.save(this, settings.toString())
                apply(on)
            }
            rows.row(ShellRows.Row(title, trailing = sw, chevron = false, qaId = "toggle:$title") {
                sw.set(!sw.isOn, animated = true)
            })
        }
        rows.header("Typing")
        toggle("Autocorrect", "autocorrect", true)
        toggle("Correct automatically", "autocorrectApply", true)
        toggle("Suggestions", "candidates", true)
        toggle("Auto-capitalize", "autocapitalize", true)
        toggle("Double-space for period", "periodShortcut", true)
        toggle("Number row", "numberRow", false) { on ->
            keyboard.numberRow = on
            keyboard.rebuild()
        }
        toggle("Glide typing", "glideTyping", true)
        rows.header("Feel")
        toggle("Sound on keypress", "keyClicks", true) { keyboard.clicksOn = it }
        toggle("Haptic feedback on keypress", "haptics", true) { keyboard.hapticsOn = it }
        rows.header("More")
        val paste = GlassSwitch(this, settings.optString("pasteStyle", "titleAndLink") == "titleAndLink") { on ->
            settings.put("pasteStyle", if (on) "titleAndLink" else "linkOnly")
            SettingsStore.save(this, settings.toString())
        }
        rows.row(ShellRows.Row("Paste title with link", trailing = paste, chevron = false,
            qaId = "toggle:Paste title with link") { paste.set(!paste.isOn, animated = true) })
        rows.row(ShellRows.Row("Toolbar items", glyph = "sliders", qaId = "shell:toolbar") {
            showToolbarItemsPanel()
        })
        rows.flush()
    }

    /** The strip's tools, one row each: its switch, and a ↑ that moves it a
     *  place up the strip (the first has nowhere to go). iOS "toolbar". */
    private fun showToolbarItemsPanel() {
        val (_, body) = panelShell("Toolbar", onBack = { showSettingsPanel() }, pad = intArrayOf(0, 0, 0, 8))
        val rows = shellRows(body)
        val order = settings.optJSONArray("toolbarOrder")?.let { a -> (0 until a.length()).map { a.optString(it) } }
            ?.map { ToolIcon.canonical(it) }?.distinct()
            ?.ifEmpty { null } ?: com.arpit.glyf.store.SettingsStore.DEFAULT_STRIP
        val hidden = settings.optJSONArray("toolbarHidden")?.let { a -> (0 until a.length()).map { a.optString(it) } }
            ?.toSet() ?: emptySet()
        for ((position, id) in order.withIndex()) {
            val title = ToolIcon.TOOLS.firstOrNull { it.first == id }?.second ?: id.replaceFirstChar { it.uppercase() }
            val sw = GlassSwitch(this, id !in hidden) { visible ->
                val keep = org.json.JSONArray()
                val was = settings.optJSONArray("toolbarHidden")
                for (i in 0 until (was?.length() ?: 0)) if (was!!.optString(i) != id) keep.put(was.optString(i))
                if (!visible) keep.put(id)
                settings.put("toolbarHidden", keep)
                settings.put("toolbarOrder", org.json.JSONArray(order))
                SettingsStore.save(this, settings.toString())
                refreshStripUnder("Toolbar") { showSettingsPanel() }
            }
            val trailing = if (position == 0) sw else LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(ToolIcon(this@GlyfIME, "arrowup", Glass.textSecondary).apply {
                    solid = true; weight = 2f; scale = 0.8f
                    setTag(com.arpit.glyf.R.id.qa_id, "toggle:$title:up")
                    contentDescription = "Move up"
                    setOnClickListener {
                        val moved = order.toMutableList()
                        java.util.Collections.swap(moved, position, position - 1)
                        settings.put("toolbarOrder", org.json.JSONArray(moved))
                        SettingsStore.save(this@GlyfIME, settings.toString())
                        showToolbarItemsPanel()
                        refreshStripUnder("Toolbar") { showSettingsPanel() }
                    }
                }, LinearLayout.LayoutParams(dp(34), dp(34)).apply { rightMargin = dp(6) })
                addView(sw)
            }
            rows.row(ShellRows.Row(title, trailing = trailing, chevron = false, qaId = "toggle:$title") {
                sw.set(!sw.isOn, animated = true)
            })
        }
        rows.flush()
    }

    /** The strip redrawn for a changed tool list, with the open panel's name
     *  and way back on it again. */
    private fun refreshStripUnder(title: String, onBack: () -> Unit) {
        buildToolbar(keyboard.isDark || keyboard.themeBg.isNotEmpty())
        if (featurePanel != null) showStripTitle(title, onBack)
    }

    /** A held key's mark in My glyfs: the tool it opens, or the spark every
     *  glyf wears (iOS glyfIcon). */
    private fun bindingGlyph(target: String) = when (target) {
        "surface:vault", "surface:notes" -> "vault"
        "surface:translate-hud" -> "translate"
        "surface:tones" -> "rewrite"
        "connector:calendar", "connector:mockcal" -> "calendar"
        "connector:meet" -> "video"
        else -> "ask"
    }

    /** What a key holds, by name: a panel by its own, a glyf by its title. */
    private fun bindingTitle(target: String): String = when (target) {
        "surface:vault" -> "Vault"
        "surface:translate-hud" -> "Translate"
        "surface:tones" -> "Rewrite"
        "surface:notes" -> "Notes"
        "connector:calendar", "connector:mockcal" -> "Calendar"
        "connector:meet" -> "Meet link"
        else -> if (target.startsWith("surface:") || target.startsWith("connector:"))
            target.substringAfter(':').replace('-', ' ').replaceFirstChar { it.uppercase() }
        else skillTitle(target)
    }

    /** The Rewrite hold (iOS TonesPopup): four tones over the keys; one tap
     *  rewrites the draft in that tone, the answer in the act panel. */
    private fun showTonesPanel(letter: String) {
        val (_, body) = panelShell("Rewrite your draft as…", onBack = null, shell = false)
        val tones = listOf(
            "Natural" to "natural, human", "Professional" to "professional",
            "Casual" to "casual", "Gen-Z" to "gen-z playful")
        for (pair in tones.chunked(2)) {
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for ((i, tone) in pair.withIndex()) {
                val (label, value) = tone
                row.addView(TextView(this).apply {
                    text = label; textSize = 15f
                    typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.CENTER
                    setTextColor(ink())
                    setTag(com.arpit.glyf.R.id.qa_id, "tones:${label.lowercase()}")
                    background = GradientDrawable().apply {
                        cornerRadius = dp(12).toFloat(); setColor(card())
                    }
                    setOnClickListener {
                        dismissFeaturePanel()
                        startSkill(letter, "rewrite.tone", mapOf("tone" to value), label)
                    }
                }, LinearLayout.LayoutParams(0, dp(52), 1f).apply { if (i > 0) leftMargin = dp(10) })
            }
            body.addView(row, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { setMargins(dp(4), dp(6), dp(4), dp(4)) })
        }
    }

    /** Vault = your details, your shorthand and your notes, drawn as the
     *  iPhone and the website draw them: cards three to a row, a small label
     *  over its value, three rows filling the panel (more scroll). Tap one to
     *  put it in; hold a note to edit it. A note, a detail or a shorthand is
     *  added from the "+" in the corner, typed on the keys.
     *  @param reveal the card just saved, scrolled into view (below the
     *  fold it looked as if nothing had been saved). */
    private fun showVaultPanel(reveal: String? = null) {
        if (glassLook) { showVaultList(reveal); return }
        val (panel, body, stage, back) = panelShell("Vault", pad = intArrayOf(6, 0, 6, 0))
        panel.tag = "vault"
        val tiles = mutableListOf<View>()
        for ((i, f) in vaultFields().withIndex()) tiles += vaultTile("vault:card:$i", f.title.uppercase(), f.value) {
            currentInputConnection?.commitText(f.value, 1)
            dismissFeaturePanel()
        }
        // Shorthand: the shortcut as it is typed, over what it types out.
        val snippets = VaultStore.load(this).optJSONArray("snippets") ?: org.json.JSONArray()
        for (i in 0 until snippets.length()) {
            val sn = snippets.getJSONObject(i)
            tiles += vaultTile("vault:shorthand:$i", sn.optString("trigger"), sn.optString("text")) {
                insertShorthand(sn.optString("text"))
                dismissFeaturePanel()
            }
        }
        val notes = com.arpit.glyf.store.NotesStore.list(this)
        for (i in 0 until notes.length()) {
            val n = notes.getJSONObject(i)
            val text = n.optString("text")
            val id = n.optString("id")
            tiles += vaultTile("vault:note:$i", "NOTE", text, onHold = { enterVaultEdit(VaultDraft.Note(id), text) }) {
                currentInputConnection?.commitText(text, 1)
                dismissFeaturePanel()
            }
        }
        vaultGrid(body, tiles)
        addVaultPlus(stage, body, back)
        val scroll = body.parent as? ScrollView ?: return
        val card = tiles.firstOrNull { reveal != null && it.getTag(com.arpit.glyf.R.id.qa_id) == reveal } ?: return
        // Once it has a place: the scroll is set after the panel's layout.
        card.addOnLayoutChangeListener(object : View.OnLayoutChangeListener {
            override fun onLayoutChange(v: View, l: Int, t: Int, r: Int, b: Int,
                                        ol: Int, ot: Int, orr: Int, ob: Int) {
                v.removeOnLayoutChangeListener(this)
                val row = v.parent as? View ?: return
                scroll.post { scroll.scrollTo(0, row.top) }
            }
        })
    }

    /** The vault in the Glass look, iOS's list: a detail's name over its
     *  value, a shortcut over what it types out, a note's first line with
     *  its edit button, each a tap to type; the "+" over the list and "Open
     *  in Glyf app ↗" under it. The same ids as the cards. */
    private fun showVaultList(reveal: String?) {
        val (panel, body, stage, back) = panelShell("Vault", pad = intArrayOf(0, 0, 0, 8))
        panel.tag = "vault"
        val rows = shellRows(body)
        fun oneLine(t: String) = t.split('\n').map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" ")
        for ((i, f) in vaultFields().withIndex()) rows.row(ShellRows.Row(f.title, glyph = "vault",
            subtitle = oneLine(StandIns.masked(f)), chevron = false, qaId = "vault:card:$i") {
            currentInputConnection?.commitText(f.value, 1)
            dismissFeaturePanel()
        })
        val snippets = VaultStore.load(this).optJSONArray("snippets") ?: org.json.JSONArray()
        for (i in 0 until snippets.length()) {
            val sn = snippets.getJSONObject(i)
            rows.row(ShellRows.Row(sn.optString("trigger"), letter = ";", subtitle = oneLine(sn.optString("text")),
                chevron = false, qaId = "vault:shorthand:$i") {
                insertShorthand(sn.optString("text"))
                dismissFeaturePanel()
            })
        }
        val notes = com.arpit.glyf.store.NotesStore.list(this)
        for (i in 0 until notes.length()) {
            val n = notes.getJSONObject(i)
            val text = n.optString("text")
            val id = n.optString("id")
            // iOS: square.and.pencil in the accent, a 34dp tap target of its own.
            val edit = FrameLayout(this).apply {
                addView(ToolIcon(this@GlyfIME, "edit", Glass.accentPrimary).apply {
                    solid = true; weight = 1.8f; scale = 0.85f
                    contentDescription = "Edit"
                    setTag(com.arpit.glyf.R.id.qa_id, "vault:note:$i:edit")
                    setOnClickListener { enterVaultEdit(VaultDraft.Note(id), text) }
                }, FrameLayout.LayoutParams(dp(34), dp(34)))
            }
            rows.row(ShellRows.Row(oneLine(text.lineSequence().firstOrNull().orEmpty()), glyph = "notes",
                trailing = edit, chevron = false, qaId = "vault:note:$i") {
                currentInputConnection?.commitText(text, 1)
                dismissFeaturePanel()
            })
        }
        rows.flush()
        val foot = pinOpenInApp(stage, "vault")
        addVaultPlus(stage, body, back, foot)
        // What was just added, in view.
        if (reveal != null) body.post {
            val row = (0 until body.childCount).map { body.getChildAt(it) }
                .firstOrNull { it.getTag(com.arpit.glyf.R.id.qa_id) == reveal } ?: return@post
            (body.parent as? ScrollView)?.scrollTo(0, row.top)
        }
    }

    /** One vault card, iOS's: a small label (11 semibold, spaced) over its
     *  value (13 medium), the pair centred, on the key colour. */
    private fun vaultTile(id: String, label: String, value: String, onHold: (() -> Unit)? = null,
                          onTap: () -> Unit): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(8), 0, dp(8), 0)
        background = Glass.card(this@GlyfIME, radius = 12f)
        setTag(com.arpit.glyf.R.id.qa_id, id)
        setOnClickListener { onTap() }
        if (onHold != null) setOnLongClickListener { onHold(); true }
        if (label.isNotEmpty()) addView(TextView(this@GlyfIME).apply {
            text = label
            Glass.style(this, 11f, Glass.SEMIBOLD, Glass.textSecondary)
            letterSpacing = 0.04f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_VERTICAL
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(15)))
        addView(TextView(this@GlyfIME).apply {
            text = value
            Glass.style(this, 13f, Glass.MEDIUM)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_VERTICAL
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(17))
            .apply { if (label.isNotEmpty()) topMargin = dp(2) })
    }

    /** Cards three to a row, 6dp apart, three rows filling the panel as on
     *  the iPhone; more than nine scroll. */
    private fun vaultGrid(body: LinearLayout, tiles: List<View>) {
        val gap = dp(6)
        val cardH = ((keyboard.height - gap * 2) / 3).coerceAtLeast(dp(56))
        for ((r, row) in tiles.chunked(3).withIndex()) {
            val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (i in 0 until 3) {
                val lp = LinearLayout.LayoutParams(0, cardH, 1f).apply { if (i > 0) leftMargin = gap }
                line.addView(row.getOrNull(i) ?: View(this), lp)
            }
            body.addView(line, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { if (r > 0) topMargin = gap })
        }
    }

    /** Whether the vault's "+" has its options out. */
    private var vaultAddOpen = false
    /** Puts the vault's "+" options out (true) or away; null with no vault up. */
    private var showVaultAdd: ((Boolean) -> Unit)? = null

    /** One "+" floating in the vault's bottom corner, over the cards as they
     *  scroll, for the three things the vault keeps (user, 2026-09-29: "a
     *  single plus icon floating button in bottom right corner, which
     *  expands to show this as options when clicked"). Open, it is a "×"
     *  with three pills stacked over it, iOS's: the key colour, an accent
     *  mark, the words; a tap beside them, the ×, ‹ or back puts them away. */
    private fun addVaultPlus(stage: FrameLayout, body: LinearLayout, back: View?, foot: Int = 0) {
        val size = 46
        val margin = 12
        val gap = 6
        // Scrolled to the end, the last card clears the "+".
        body.setPadding(body.paddingLeft, body.paddingTop, body.paddingRight, dp(size + margin + 6))
        // No wash over the cards (Arpit: "why white layover when menu open,
        // that looks bad"): the layer only catches the tap that closes the
        // options.
        val dim = View(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            visibility = View.GONE
            setTag(com.arpit.glyf.R.id.qa_id, "vault:add:dim")
            setOnClickListener { showVaultAdd?.invoke(false) }
        }
        val options = LinearLayout(this).apply { visibility = View.GONE }
        val starts = listOf<Triple<String, String, () -> Unit>>(
            Triple("note", "New note") { enterVaultEdit(VaultDraft.Note(null), "") },
            Triple("detail", "New detail") { showDetailKinds() },
            // The ; is there already: only the word is left to type.
            Triple("shorthand", "New shorthand") { enterVaultEdit(VaultDraft.Shorthand, ";") },
        )
        // Each led by its accent mark, as on iOS: a note, the vault's card, a bolt.
        val glyphs = mapOf("note" to "notes", "detail" to "vault", "shorthand" to "bolt")
        // One width for the three: the longest title's.
        val paint = android.text.TextPaint(android.text.TextPaint.ANTI_ALIAS_FLAG).apply {
            typeface = Glass.font(this@GlyfIME, Glass.MEDIUM)
            textSize = dp(15).toFloat()
        }
        val textW = starts.maxOf { paint.measureText(it.second) }
        val optionW = dp(14 + 18 + 8 + 18) + Math.ceil(textW.toDouble()).toInt()
        for ((id, label, start) in starts) options.addView(TextView(this).apply {
            text = label
            Glass.style(this, 15f, Glass.MEDIUM)
            gravity = Gravity.CENTER_VERTICAL
            maxLines = 1
            setCompoundDrawablesRelativeWithIntrinsicBounds(
                ToolIcon(context, glyphs.getValue(id), Glass.accentPrimary).apply {
                    scale = 0.8f; solid = true; weight = 2f
                }.asDrawable(dp(18)), null, null, null)
            compoundDrawablePadding = dp(8)
            setPadding(dp(14), 0, dp(18), 0)
            background = Glass.pill(Glass.surfaceCard)
            // Lifted off the cards behind it, as on iOS.
            elevation = dp(3).toFloat()
            setTag(com.arpit.glyf.R.id.qa_id, "vault:new:$id")
            setOnClickListener { start() }
        })
        val plus = PlusButton(this).apply {
            setTag(com.arpit.glyf.R.id.qa_id, "vault:add")
            contentDescription = "Add"
        }
        vaultAddOpen = false
        showVaultAdd = { open ->
            vaultAddOpen = open
            backForOptions = false
            watchBack(open)
            dim.visibility = if (open) View.VISIBLE else View.GONE
            plus.contentDescription = if (open) "Close" else "Add"
            plus.turnTo(if (open) 45f else 0f)
            if (open) {
                // Three pills as tall as the room allows (a phone on its side
                // has little over half a panel), stacked over the "+"; beside
                // it where even the shortest stack doesn't fit.
                val room = stage.height - foot - dp(margin + size + 10 + 6)
                val pillH = ((room - dp(gap) * 2) / 3).coerceIn(dp(28), dp(36))
                val stacked = room >= pillH * 3 + dp(gap) * 2
                options.orientation = if (stacked) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
                options.gravity = if (stacked) Gravity.END else Gravity.CENTER_VERTICAL
                for (i in 0 until options.childCount) {
                    options.getChildAt(i).layoutParams = LinearLayout.LayoutParams(
                        if (stacked) optionW else LinearLayout.LayoutParams.WRAP_CONTENT, pillH).apply {
                        if (i > 0) { if (stacked) topMargin = dp(gap) else leftMargin = dp(gap) }
                    }
                }
                options.layoutParams = (options.layoutParams as FrameLayout.LayoutParams).apply {
                    bottomMargin = foot + if (stacked) dp(margin + size + 10) else dp(margin) + (dp(size) - pillH) / 2
                    marginEnd = dp(if (stacked) margin else margin + size + 8)
                }
                options.alpha = 0f
                options.translationY = dp(8).toFloat()
                options.visibility = View.VISIBLE
                options.animate().alpha(1f).translationY(0f).setDuration(200)
                    .setInterpolator(android.view.animation.DecelerateInterpolator()).start()
            } else options.visibility = View.GONE
        }
        plus.setOnClickListener { showVaultAdd?.invoke(!vaultAddOpen) }
        // ‹ puts the options away first, as back does; then it steps back.
        back?.setOnClickListener { if (vaultAddOpen) showVaultAdd?.invoke(false) else showMenuGrid() }
        stage.addView(dim, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        stage.addView(options, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.END))
        stage.addView(plus, FrameLayout.LayoutParams(dp(size), dp(size), Gravity.BOTTOM or Gravity.END).apply {
            bottomMargin = dp(margin) + foot; marginEnd = dp(margin)
        })
    }

    /** The vault's "+": a filled accent disc with a white plus, drawn so it
     *  sits true in the middle and becomes a "×" turned an eighth. Only the
     *  drawing turns: a turned view reports itself somewhere else on
     *  screen, and a tap sent there missed it. */
    private class PlusButton(ctx: android.content.Context) : View(ctx) {
        private val disc = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Glass.accentPrimary
        }
        private val bar = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeCap = android.graphics.Paint.Cap.ROUND
            // SF's plus at 20pt semibold.
            strokeWidth = 2.4f * ctx.resources.displayMetrics.density
        }
        /** Degrees: 0 is the plus, 45 the ×. */
        private var turn = 0f

        fun turnTo(degrees: Float) {
            android.animation.ValueAnimator.ofFloat(turn, degrees).apply {
                duration = 200
                interpolator = android.view.animation.DecelerateInterpolator()
                addUpdateListener { turn = it.animatedValue as Float; invalidate() }
            }.start()
        }

        override fun onDraw(c: android.graphics.Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val r = minOf(width, height) / 2f
            c.drawCircle(cx, cy, r, disc)
            val arm = 8f * resources.displayMetrics.density
            c.save()
            c.rotate(turn, cx, cy)
            c.drawLine(cx - arm, cy, cx + arm, cy, bar)
            c.drawLine(cx, cy - arm, cx, cy + arm, bar)
            c.restore()
        }
    }

    /** Where the phone is, as the app last said (else the phone's own). */
    private val inIndia get() =
        settings.optString("region").ifEmpty { java.util.Locale.getDefault().country } == "IN"

    /** A kind a detail can be, named as the app's Vault screen names it:
     *  its kind, name, the label it is kept under, and iOS's symbol. */
    private data class DetailKindInfo(val kind: String, val name: String, val label: String, val glyph: String)

    /** The kinds a detail can be (iOS DetailKind.addable). UPI only where
     *  people pay with it. */
    private fun detailKinds(): List<DetailKindInfo> = buildList {
        add(DetailKindInfo("name", "Name", "Name", "person"))
        add(DetailKindInfo("email", "Email", "Email", "at"))
        add(DetailKindInfo("phone", "Phone", "Phone", "phone"))
        add(DetailKindInfo("address", "Address", "Home", "house"))
        if (inIndia) add(DetailKindInfo("upi", "UPI", "UPI", "rupee"))
        add(DetailKindInfo("wallet", "Wallet address", "Wallet address", "wallet"))
        add(DetailKindInfo("link", "Link", "Link", "link"))
        // Anything goes in the vault, encrypted on the phone (2026-10-14).
        add(DetailKindInfo("card", "Card", "Card", "card"))
        add(DetailKindInfo("password", "Password", "Password", "key"))
        add(DetailKindInfo("custom", "Other", "Other", "tag"))
    }

    /** New detail, first what kind it is, as the vault's own grid: a card
     *  per kind, its symbol over its name. The value is then typed on the
     *  keys, in the strip a note uses. */
    private fun showDetailKinds() {
        if (glassLook) {
            // iOS's list in the Glass look: each kind's mark, its name, a chevron.
            val (panel, body) = panelShell("New detail", onBack = { showVaultPanel() }, pad = intArrayOf(0, 0, 0, 8))
            panel.tag = "vault:kinds"
            val rows = shellRows(body)
            for (k in detailKinds()) rows.row(ShellRows.Row(k.name, glyph = k.glyph, qaId = "vault:kind:${k.kind}") {
                enterVaultEdit(VaultDraft.Detail(k.kind, k.name, k.label), "")
            })
            rows.flush()
            return
        }
        val (panel, body) = panelShell("New detail", onBack = { showVaultPanel() }, pad = intArrayOf(6, 0, 6, 0))
        panel.tag = "vault:kinds"
        val tiles = detailKinds().map { k ->
            // Symbol over name, centred as a column (iOS: 22 + 5 + 17).
            object : TextView(this) {
                override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
                    super.onSizeChanged(w, h, ow, oh)
                    val top = ((h - dp(22 + 5 + 17)) / 2).coerceAtLeast(0)
                    if (paddingTop != top) post { setPadding(dp(6), top, dp(6), 0) }
                }
            }.apply {
                text = k.name
                Glass.style(this, 13f, Glass.MEDIUM)
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                maxLines = 1
                // "Wallet address" is a card's whole width on a small phone:
                // a touch smaller beats cut short.
                setAutoSizeTextTypeUniformWithConfiguration(10, 13, 1, android.util.TypedValue.COMPLEX_UNIT_DIP)
                setCompoundDrawablesRelativeWithIntrinsicBounds(null,
                    ToolIcon(context, k.glyph, Glass.textPrimary).apply {
                        solid = true; weight = 1.2f; scale = 1.25f
                    }.asDrawable(dp(22)), null, null)
                compoundDrawablePadding = dp(5)
                setPadding(dp(6), 0, dp(6), 0)
                background = Glass.card(this@GlyfIME, radius = 12f)
                setTag(com.arpit.glyf.R.id.qa_id, "vault:kind:${k.kind}")
                setOnClickListener { enterVaultEdit(VaultDraft.Detail(k.kind, k.name, k.label), "") }
            }
        }
        vaultGrid(body, tiles)
    }

    /** Gboard's clipboard, identical to the iOS panel: it takes the whole
     *  keyboard, toolbar included, the way Gboard's does. */
    private fun showClipboardPanel() {
        if (!qaClipHeld) com.arpit.glyf.store.ClipboardStore.captureNow(this, settings)
        dismissFeaturePanel()
        keyboard.visibility = View.GONE
        toolbar.visibility = View.GONE
        val panel = ClipboardPanelView(
            this, keyboard.palette(),
            onClose = {
                dismissFeaturePanel()
                toolbar.visibility = View.VISIBLE
            },
            onPaste = { text ->
                insertSpaced(text)
                dismissFeaturePanel()
                toolbar.visibility = View.VISIBLE
            },
            onImage = { uri ->
                dismissFeaturePanel()
                toolbar.visibility = View.VISIBLE
                insertImage(uri)
            },
        )
        root.addView(panel, android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
            keyboard.height + toolbar.height))
        featurePanel = panel
    }

    /** The Calendar tool: a month and the chosen day's events, in place of
     *  the keys (iOS CalendarSurface). */
    /** g menu → Games: Snake and Chomp over the keys, the strip staying put. */
    /** Paying stays in the keyboard; only the signature is Phantom's,
     *  reached through a flash of the app (PayPanelView). */
    private fun showPayPanel(intent: PayPanelView.Intent) {
        dismissFeaturePanel()
        val keysH = if (keyboard.height > 0) keyboard.height else dp(216)
        keyboard.visibility = View.GONE
        val panel = PayPanelView(
            this, keyboard.palette(),
            backendURL = settings.optString("backendURL"),
            walletAddress = settings.optString("walletAddress").takeIf { it.isNotEmpty() },
            intent = intent,
            onHandOff = { query -> dismissFeaturePanel(); openAppPath("pay", query) },
            onConnect = { dismissFeaturePanel(); openAppPath("wallet") },
            onToast = { notice(it) },
            onClose = { dismissFeaturePanel() },
            clipText = { com.arpit.glyf.store.ClipboardStore.clipText(this) },
        )
        root.addView(panel, root.indexOfChild(keyboard),
            android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, keysH))
        featurePanel = panel
        // iOS: the strip names it, "✕ [dollarsign.circle] Pay"; a buy by
        // what it buys ("Buy AAPL"), its panel then all cards.
        showStripTitle(if (intent is PayPanelView.Intent.Buy) "Buy ${intent.symbol}" else "Pay",
            onBack = null, icon = "pay")
    }

    // MARK: Trading (android-trade): the trade chip and panel, the g menu's
    // Uniswap and Definitive panels, and the strip's recommended action.
    // The keyboard only quotes; MetaMask or Phantom signs in the app
    // (Arpit, 2026-11-12: "the wallet would be external wallet only").

    /** A tool the model named for the sentence (AIAction), filled in; shown
     *  in place of its text chip. */
    private var suggestedAction: Smart.Chip? = null

    /** POST /suggest named a tool: kept for these words, if they still stand. */
    private fun takeRecommended(text: String, action: AIAction) {
        val now = (currentInputConnection?.getTextBeforeCursor(120, 0)?.toString() ?: "").trim()
        if (now != text || featurePanel != null) return
        val chip = action.chip ?: return
        // Without the wallet on, nothing to trade; a Meet link only with Meet.
        if (chip is Smart.Chip.Trade && !walletOn) return
        if (chip is Smart.Chip.Action && chip.intent == "meet" && !com.arpit.glyf.store.GoogleAccess.hasMeet(this)) return
        suggestedFor = text
        suggestedDetail = null
        suggestedChip = null
        suggestedAction = chip
        updateSuggestions()
    }

    /** The recommended action's chip, which opens its tool with the values
     *  in it; nothing runs from the strip. Null falls through to the rest. */
    private fun showRecommended(chip: Smart.Chip): Boolean? {
        val used = { suggestedAction = null; suggestedFor = "" }
        return when (chip) {
            is Smart.Chip.Trade -> showTradeChip(chip, used)
            is Smart.Chip.Event -> showStripChip("event", null, Smart.display(chip), "Add", lead = "calendar") {
                used(); hideStripChip()
                showCalendarPanel().compose(chip.plan)
            }
            is Smart.Chip.Action -> showStripChip("action", null, chip.label, "", policyKey = chip.intent + "|" + chip.query) {
                used(); hideStripChip()
                when {
                    chip.intent == "meet" -> insertMeetLink()
                    chip.intent.startsWith("open:") -> openRecommended(chip.intent.removePrefix("open:"), chip.query)
                    else -> {
                        val ic = currentInputConnection
                        startAct(ic?.getTextBeforeCursor(4000, 0)?.toString() ?: "",
                            ic?.getTextAfterCursor(4000, 0)?.toString() ?: "", chip.intent)
                    }
                }
            }
            else -> null
        }
    }

    /** Search, YouTube or Maps with the model's query searched, or the
     *  translate strip set to its language (iOS openRecommended). */
    private fun openRecommended(tool: String, query: String) {
        if (tool == "translate") {
            if (translateStrip == null) runTranslateOnField()
            translateForced = query
            translateTarget = query
            translateSource = ""
            translateDraftChanged()
            return
        }
        enterSearch()
        searchTab = when (tool) { "youtube" -> "yt"; "maps" -> "maps"; else -> "web" }
        styleSearchTabs(animated = false)
        searchQuery = query
        renderQuery()
        submitSearch()
    }

    /** The strip's trade chip: the venue, the whole order, and what a tap does. */
    private fun showTradeChip(chip: Smart.Chip.Trade, used: (() -> Unit)? = null): Boolean =
        showStripChip("trade", Smart.key(chip), Smart.display(chip), Smart.verb(chip) ?: "Set",
            policyKey = "trade|" + chip.intent.title) {
            used?.invoke()
            hideStripChip()
            showTradePanel(chip.intent)
        }

    /** The trade panel over the keys (TradePanelView): the strip names it,
     *  its button hands the trade to the app (glyf://open?path=trade?…),
     *  and with no wallet for the chain it opens Profile › Wallet. */
    private fun showTradePanel(intent: TradeIntent) {
        dismissFeaturePanel()
        val keysH = if (keyboard.height > 0) keyboard.height else dp(216)
        keyboard.visibility = View.GONE
        lateinit var panel: TradePanelView
        panel = TradePanelView(
            this, keyboard.palette(),
            backendURL = settings.optString("backendURL"),
            evmAddress = settings.optString("evmAddress").ifEmpty { null },
            solanaAddress = settings.optString("walletAddress").ifEmpty { null },
            start = intent,
            // A Solana send goes to the app's Phantom send, the rest to its
            // Trade screen (MetaMask; Phantom for Flash on Solana).
            onHandOff = { query ->
                dismissFeaturePanel()
                val (path, q) = TradeQuote.destination(query)
                openAppPath(path, q)
            },
            onConnect = { dismissFeaturePanel(); openAppPath("wallet") },
            onToast = { notice(it) },
            onTitle = { title -> showStripTitle(title, onBack = null, icon = "trend") },
            clipText = { com.arpit.glyf.store.ClipboardStore.clipText(this) },
            // A token search: a strip over the letter keys, like New Event's title.
            onSearching = { searching ->
                keyboard.visibility = if (searching) View.VISIBLE else View.GONE
                panel.layoutParams = (panel.layoutParams as LinearLayout.LayoutParams).apply {
                    height = if (searching) dp(100) else keysH
                }
                if (searching) { keyboard.mode = Mode.LETTERS; keyboard.shifted = false; keyboard.rebuild() }
            },
        )
        root.addView(panel, root.indexOfChild(keyboard),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, keysH))
        featurePanel = panel
        showStripTitle(TradeQuote.headerTitle(intent.kind), onBack = null, icon = "trend")
    }

    /** A sponsor's panel from the g menu's top row: everything it does as
     *  rows, the trade typed first (SponsorMenu, SponsorPanel). */
    private fun showSponsorPanel(sponsor: SponsorMenu.Sponsor) {
        val typed = currentInputConnection?.getTextBeforeCursor(200, 0)?.toString().orEmpty()
        val (_, body) = panelShell(sponsor.title, pad = intArrayOf(0, 0, 0, 8))
        SponsorPanel.fill(this, shellRows(body), sponsor, typed,
            onOption = { sponsorOption(it, typed) },
            onChain = { SponsorMenu.flashChain = it; showSponsorPanel(sponsor) })
    }

    private fun sponsorOption(option: SponsorMenu.Option, typed: String) {
        when (val a = SponsorMenu.action(option, typed, SponsorMenu.flashChain)) {
            is SponsorMenu.Action.Trade -> showTradePanel(a.intent)
            is SponsorMenu.Action.OpenApp -> { dismissFeaturePanel(); openAppPath(a.path) }
            // Buying SOL with what the wallet holds, Jupiter's route.
            SponsorMenu.Action.SolanaSwap -> showPayPanel(PayPanelView.Intent.Buy(PayPanelView.WSOL, "SOL",
                RatesStore.cryptoUsd("SOL")?.let { "$" + String.format(java.util.Locale.US, "%.2f", it) }))
            null -> {}
        }
    }

    // MARK: end of Trading (android-trade)

    /** A payment finished while the keyboard was away (the app wrote how it
     *  went into shared settings): said once, back in the chat. */
    private fun showPayOutcomeIfFresh() {
        val raw = settings.optString("walletOutcome")
        if (raw.isEmpty()) return
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val at = obj.optDouble("at", 0.0)
        if (imePrefs.getLong("payOutcomeAt", 0L) == at.toLong()) return
        imePrefs.edit().putLong("payOutcomeAt", at.toLong()).apply()
        if (System.currentTimeMillis() / 1000.0 - at > 5 * 60) return
        val title = obj.optString("title")
        if (title.isEmpty()) return
        val detail = obj.optString("detail")
        notice(if (detail.isEmpty()) title else "$title · $detail")
    }

    private fun showGamesPanel() {
        dismissFeaturePanel()
        val keysH = if (keyboard.height > 0) keyboard.height else dp(216)
        keyboard.visibility = View.GONE
        val panel = GamesPanelView(this, keyboard.palette())
        root.addView(panel, root.indexOfChild(keyboard),
            android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, keysH))
        featurePanel = panel
        // iOS: the strip names it, "✕ [gamecontroller] Games".
        showStripTitle("Games", onBack = null, icon = "games")
    }

    private fun showCalendarPanel(): CalendarPanelView {
        dismissFeaturePanel()
        val keysH = if (keyboard.height > 0) keyboard.height else dp(216)
        keyboard.visibility = View.GONE
        lateinit var panel: CalendarPanelView
        val session = inputSession
        panel = CalendarPanelView(
            this, keyboard.palette(),
            // The tour's investor chat plays on a practice day: nothing it
            // adds reaches a real calendar.
            practice = tourStep()?.startsWith("investor:") == true,
            backendURL = settings.optString("backendURL"),
            bookingLink = settings.optString("bookingLink").trim().takeIf { it.isNotEmpty() },
            onInsert = insert@{ text ->
                // Only into the field the calendar was opened over.
                if (session != inputSession) return@insert
                // A sentence of its own, never glued to the last word (iOS spaced()).
                val ic = currentInputConnection
                val last = ic?.getTextBeforeCursor(1, 0)?.lastOrNull()
                ic?.commitText(if (last != null && !last.isWhitespace()) " $text" else text, 1)
                dismissFeaturePanel()
            },
            onClose = { dismissFeaturePanel() },
            // The calendar is asked for during onboarding; after that it is
            // Android's to allow, on Glyf's own page in Settings.
            onConnect = {
                dismissFeaturePanel()
                runCatching {
                    startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.fromParts("package", packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            },
            // A field being typed: a strip over the letter keys, like emoji search.
            onTitleEditing = { editing ->
                keyboard.visibility = if (editing) View.VISIBLE else View.GONE
                panel.layoutParams = (panel.layoutParams as android.widget.LinearLayout.LayoutParams).apply {
                    height = if (editing) dp(92) else keysH
                }
                if (editing) { keyboard.mode = Mode.LETTERS; keyboard.shifted = true; keyboard.rebuild() }
            },
        )
        // Above the keys, so the title strip sits over them when they show.
        root.addView(panel, root.indexOfChild(keyboard),
            android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, keysH))
        featurePanel = panel
        // iOS: the strip names it, "✕ [calendar] Calendar".
        showStripTitle("Calendar", onBack = null, icon = "calendar")
        return panel
    }

    /** A screenshot goes in as an image where the field takes images (chat
     *  apps do), the way Gboard sends one; anywhere else it is copied so it
     *  can be pasted by hand. */
    private fun insertImage(uri: android.net.Uri) {
        // MediaStore is asked on a worker: while it indexes a screenshot that
        // was just taken it can take seconds to answer, and the keyboard
        // must keep taking touches meanwhile.
        Thread {
            val type = runCatching { contentResolver.getType(uri) }.getOrNull() ?: "image/png"
            val clip = runCatching { android.content.ClipData.newUri(contentResolver, "Screenshot", uri) }
                .getOrElse { android.content.ClipData("Screenshot", arrayOf(type), android.content.ClipData.Item(uri)) }
            main.post {
                val mimes = currentInputEditorInfo?.contentMimeTypes ?: emptyArray()
                if (mimes.any { android.content.ClipDescription.compareMimeTypes(type, it) }) {
                    val info = android.view.inputmethod.InputContentInfo(uri,
                        android.content.ClipDescription("Screenshot", arrayOf(type)))
                    val sent = currentInputConnection?.commitContent(info,
                        android.view.inputmethod.InputConnection.INPUT_CONTENT_GRANT_READ_URI_PERMISSION,
                        null) == true
                    if (sent) return@post
                }
                val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                cm.setPrimaryClip(clip)
                notice("Screenshot copied")
            }
        }.start()
    }

    // MARK: in-keyboard vault editing (strip above the keys, like search)

    /** What the strip over the keys is writing into the vault. */
    private sealed class VaultDraft {
        /** A note; [id] when it is one being changed. */
        data class Note(val id: String?) : VaultDraft()
        /** A detail of one kind, kept under that kind's [label]. */
        data class Detail(val kind: String, val name: String, val label: String) : VaultDraft()
        /** A shorthand: its shortcut (";sig") and what it types out, side by
         *  side as on iOS, the shortcut typed first. */
        object Shorthand : VaultDraft()
    }

    private var vaultEditActive = false
    private var vaultDraft: VaultDraft? = null
    /** The note, the detail, or what a shorthand types out. */
    private var vaultEditText = ""
    /** A shorthand's shortcut. */
    private var vaultShortcutText = ""
    /** The keys are typing a shorthand's shortcut, not what it types out. */
    private var vaultShortcutActive = false
    private var vaultEditStrip: FrameLayout? = null
    private var vaultEditView: InlineField? = null
    private var vaultShortcutView: InlineField? = null
    /** Why Save didn't save, in the strip under the fields (iOS). */
    private var vaultEditStatus: TextView? = null

    /** Adding to the vault without leaving the keyboard, iOS's strip
     *  (NoteEditSurface): ✕, the field(s) the keys type into, Save, and a
     *  line under them for why a save was refused. A note, a detail of the
     *  kind picked, or a shorthand's shortcut beside what it types out. */
    private fun enterVaultEdit(draft: VaultDraft, initial: String) {
        dismissFeaturePanel()
        if (searchActive) exitSearch()
        // One thing at a time: the open strip goes before the next.
        if (vaultEditActive) exitVaultEdit()
        vaultEditActive = true
        vaultDraft = draft
        val shorthand = draft == VaultDraft.Shorthand
        vaultShortcutText = if (shorthand) initial else ""
        vaultEditText = if (shorthand) "" else initial
        toolbar.visibility = View.GONE
        // The keys for what is typed: @ at hand for an email, a dial pad for
        // a phone number, letters for everything else (even over a number
        // field, where a note had no letters to type with).
        keyboard.kContext = when ((draft as? VaultDraft.Detail)?.kind) {
            "email", "upi" -> KContext.EMAIL
            "link" -> KContext.URL
            "phone" -> KContext.PHONE_PAD
            else -> KContext.TEXT
        }
        keyboard.mode = Mode.LETTERS
        autoShifted = false
        keyboard.rebuild()
        val strip = FrameLayout(this)
        strip.addView(ToolIcon(this, "close", Glass.textSecondary).apply {
            solid = true
            weight = 2f
            scale = 0.95f
            setTag(com.arpit.glyf.R.id.qa_id, "vaultedit:close")
            contentDescription = "Close"
            setOnClickListener { exitVaultEdit() }
        }, FrameLayout.LayoutParams(dp(36), dp(34)).apply { leftMargin = dp(2); topMargin = dp(8) })
        val placeholder = when (draft) {
            is VaultDraft.Note -> "Write a note…"
            is VaultDraft.Detail -> draft.name
            VaultDraft.Shorthand -> "Types out"
        }
        // The kind's mark stays in the field once what is typed replaces its name.
        val glyph = (draft as? VaultDraft.Detail)?.let { d -> detailKinds().firstOrNull { it.kind == d.kind }?.glyph }
        val field = InlineField(this, placeholder, glyph).apply {
            setTag(com.arpit.glyf.R.id.qa_id, "vaultedit:field")
            show(vaultEditText)
            setOnClickListener { activateVaultField(shortcut = false) }
        }
        val fieldsW = resources.displayMetrics.widthPixels - dp(120)
        if (shorthand) {
            // [;shortcut][types out], the shortcut a third of the way.
            val w = minOf(dp(112), (fieldsW * 0.36f).toInt())
            val shortcut = InlineField(this, "Shortcut").apply {
                setTag(com.arpit.glyf.R.id.qa_id, "vaultedit:shortcut")
                show(vaultShortcutText)
                setOnClickListener { activateVaultField(shortcut = true) }
            }
            strip.addView(shortcut, FrameLayout.LayoutParams(w, dp(34)).apply {
                leftMargin = dp(40); topMargin = dp(8)
            })
            strip.addView(field, FrameLayout.LayoutParams(fieldsW - w - dp(6), dp(34)).apply {
                leftMargin = dp(40) + w + dp(6); topMargin = dp(8)
            })
            vaultShortcutView = shortcut
        } else strip.addView(field, FrameLayout.LayoutParams(fieldsW, dp(34)).apply {
            leftMargin = dp(40); topMargin = dp(8)
        })
        // The ink's own pill: black on a light board, white on a dark one.
        strip.addView(TextView(this).apply {
            text = "Save"
            Glass.style(this, 14f, Glass.BOLD, if (Glass.dark) Glass.brandInk else Color.WHITE)
            gravity = Gravity.CENTER
            background = Glass.pill(Glass.textPrimary)
            setTag(com.arpit.glyf.R.id.qa_id, "vaultedit:save")
            setOnClickListener { saveVaultEdit() }
        }, FrameLayout.LayoutParams(dp(62), dp(30), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(10); rightMargin = dp(10)
        })
        val status = TextView(this).apply {
            Glass.style(this, 12f, Glass.REGULAR, Glass.accentDanger)
            gravity = Gravity.CENTER
            maxLines = 2
            setTag(com.arpit.glyf.R.id.qa_id, "vaultedit:status")
        }
        strip.addView(status, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(34)).apply {
            leftMargin = dp(12); rightMargin = dp(12); topMargin = dp(48)
        })
        root.addView(strip, 0, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(96)))
        vaultEditStrip = strip
        vaultEditView = field
        vaultEditStatus = status
        activateVaultField(shortcut = shorthand)
    }

    /** The keys type into the shortcut ([shortcut]) or the main field. */
    private fun activateVaultField(shortcut: Boolean) {
        vaultShortcutActive = shortcut && vaultShortcutView != null
        vaultShortcutView?.active = vaultShortcutActive
        vaultEditView?.active = !vaultShortcutActive
        // Words start with a capital: a note, a name, an address or what a
        // shorthand types out; a shortcut, an email, a link or a wallet
        // never do (";Sig" would never expand from ";sig").
        val empty = if (vaultShortcutActive) vaultShortcutText.isEmpty() else vaultEditText.isEmpty()
        keyboard.shifted = empty && when (val d = vaultDraft) {
            is VaultDraft.Note -> true
            is VaultDraft.Detail -> d.kind in setOf("name", "address", "custom")
            VaultDraft.Shorthand -> !vaultShortcutActive
            null -> false
        }
        autoShifted = false
        keyboard.invalidate()
    }

    /** Saved where the app's Vault screen reads it, and in use at once: a
     *  detail feeds the strip's chips, a shorthand expands on the space. A
     *  refusal (a secret, a shortcut that isn't one) shows under the fields. */
    private fun saveVaultEdit() {
        val text = vaultEditText
        val d = vaultDraft ?: return
        var trigger = ""
        val err = when (d) {
            is VaultDraft.Note -> com.arpit.glyf.store.NotesStore.upsert(this, d.id, text)
            is VaultDraft.Detail -> VaultStore.addField(this, d.kind, d.label, text)
            VaultDraft.Shorthand -> {
                // "sig" is ";sig": the ; is the shortcut's, whoever typed it.
                trigger = vaultShortcutText.trim().lowercase().let { if (it.startsWith(";")) it else ";$it" }
                VaultStore.triggerRefusal(trigger) ?: VaultStore.upsertSnippet(this, trigger, text.trim())
            }
        }
        if (err != null) {
            vaultEditStatus?.text = err
            return
        }
        vaultFieldsStamp = -1L
        // Its card: a new detail is the last one, a new note the first.
        val reveal = when (d) {
            is VaultDraft.Detail -> "vault:card:${vaultFields().lastIndex}"
            VaultDraft.Shorthand -> {
                val snippets = VaultStore.load(this).optJSONArray("snippets") ?: org.json.JSONArray()
                (0 until snippets.length()).firstOrNull { snippets.getJSONObject(it).optString("trigger") == trigger }
                    ?.let { "vault:shorthand:$it" }
            }
            is VaultDraft.Note -> {
                val notes = com.arpit.glyf.store.NotesStore.list(this)
                (if (d.id == null) 0 else (0 until notes.length()).firstOrNull {
                    notes.getJSONObject(it).optString("id") == d.id
                })?.let { "vault:note:$it" }
            }
        }
        exitVaultEdit()
        showVaultPanel(reveal)
    }

    private fun exitVaultEdit() {
        vaultEditActive = false
        vaultDraft = null
        vaultEditStrip?.let { root.removeView(it) }
        vaultEditStrip = null
        vaultEditView = null
        vaultShortcutView = null
        vaultEditStatus = null
        vaultEditText = ""
        vaultShortcutText = ""
        vaultShortcutActive = false
        toolbar.visibility = View.VISIBLE
        // The host field's own keys again.
        val host = KContext.from(currentInputEditorInfo)
        if (keyboard.kContext != host || keyboard.mode != Mode.LETTERS) {
            keyboard.kContext = host
            keyboard.mode = Mode.LETTERS
            keyboard.rebuild()
        }
        syncAutoShift()
    }

    // MARK: temp mail (TempMail.kt): an address on mail.tm, watched from here

    /** The watched address's mails, newest first: in memory only, never on disk. */
    private var tempMails: List<TempMail> = emptyList()
    private var tempChecking = false
    private var tempCreating = false
    /** Checks in a row that mail.tm turned away (429) or that got no answer. */
    private var tempFails = 0
    /** Looks asked for so far (the scenarios read it). */
    private var tempLooks = 0
    /** The keyboard is up: temp mail is only checked then. */
    private var tempViewUp = false
    /** The watching line on the panel, kept to count down in place. */
    private var tempLine: TextView? = null

    private val tempTick = Runnable { checkTempMail() }
    private val tempClock = object : Runnable {
        override fun run() {
            if (featurePanel?.tag != "tempmail") return
            renderTempLine()
            main.postDelayed(this, 1000)
        }
    }

    /** mail.tm, or the stand-in a test run points the keyboard at. */
    // The stand-in mail server is for debug builds only; a shipped build
    // sends the inbox login nowhere but mail.tm.
    private fun tempBase() = if (!com.arpit.glyf.BuildConfig.DEBUG) TempMailRules.DEFAULT_BASE
        else settings.optString("tempMailBase").ifBlank { TempMailRules.DEFAULT_BASE }

    private fun tempPanelShowing() = featurePanel?.tag == "tempmail" || featurePanel?.tag == "tempmail:mail"

    /** Checked from Create, Insert or opening the panel for 15 minutes, and
     *  for two minutes after a mail with a code (unless the panel is open). */
    private fun tempWatching(box: TempBox, now: Long = System.currentTimeMillis()) =
        now < box.expiresAt && now < box.watchUntil &&
            (box.codeAt == 0L || now < box.codeAt + TempMailRules.AFTER_CODE_MS || tempPanelShowing())

    /** A new watch window, from now. */
    private fun restartTempWatch(box: TempBox): TempBox =
        box.copy(watchUntil = System.currentTimeMillis() + TempMailRules.WATCH_MS, codeAt = 0L)
            .also { TempMailStore.save(this, it) }

    /** The next look: every 8 s for a window's first 3 minutes and while the
     *  panel is open, every 20 s after; a minute's rest after three looks in
     *  a row were turned away or lost. */
    private fun scheduleTempCheck() {
        main.removeCallbacks(tempTick)
        if (!tempViewUp) return
        val box = TempMailStore.load(this) ?: return
        if (!tempWatching(box)) return
        val delay = when {
            tempFails >= TempMailRules.FAILS_BEFORE_REST -> { tempFails = 0; TempMailRules.REST_MS }
            tempPanelShowing() || System.currentTimeMillis() - box.watchStart < TempMailRules.FAST_FOR_MS ->
                TempMailRules.FAST_MS
            else -> TempMailRules.SLOW_MS
        }
        main.postDelayed(tempTick, delay)
    }

    private fun checkTempMail() {
        if (!tempViewUp) return
        val box = TempMailStore.load(this) ?: return
        val now = System.currentTimeMillis()
        if (now >= box.expiresAt) { endTempBox("That address has expired", letGo = true); return }
        if (!tempWatching(box, now)) { renderTempLine(); return }
        if (tempChecking) { scheduleTempCheck(); return }
        tempChecking = true
        tempLooks++
        MailTm.check(tempBase(), box, tempMails.associateBy { it.id }) { mails, status, used ->
            main.post {
                tempChecking = false
                // Replaced or deleted meanwhile: that answer is for no one.
                var latest = TempMailStore.load(this)?.takeIf { it.address == box.address } ?: return@post
                // A new token (mail.tm's first 401) is kept for the next look.
                if (used.token != latest.token) latest = latest.copy(token = used.token).also { TempMailStore.save(this, it) }
                when {
                    // A second 401: the address is gone at mail.tm.
                    status == 401 -> {
                        endTempBox("That address has expired", letGo = false)
                        return@post
                    }
                    // The list came; a read turned away counts as a miss.
                    mails != null -> {
                        tempFails = if (status == 200) 0 else 1
                        gotTempMails(latest, mails)
                    }
                    // Turned away (429) or no answer: skip this look.
                    else -> tempFails++
                }
                scheduleTempCheck()
            }
        }
    }

    private fun gotTempMails(box: TempBox, mails: List<TempMail>) {
        val changed = mails.map { it.id } != tempMails.map { it.id }
        tempMails = mails
        val fresh = mails.filter { it.id !in box.seen }
        var next = box.copy(seen = box.seen + fresh.map { it.id })
        // A code has come: two more minutes of watching, then its job is done.
        if (next.codeAt == 0L && fresh.any { it.code != null }) next = next.copy(codeAt = System.currentTimeMillis())
        if (next != box) TempMailStore.save(this, next)
        when {
            featurePanel?.tag == "tempmail" -> if (changed) showTempInbox()
            // An open mail stays open; the inbox catches up when ‹ goes back to it.
            featurePanel?.tag == "tempmail:mail" -> {}
            else -> fresh.firstOrNull()?.let { showTempMailChip(it) }
        }
    }

    /** A new mail on the strip: a code to put in, or the mail to open. */
    private fun showTempMailChip(mail: TempMail) {
        if (!::toolbar.isInitialized || searchActive || barActive || vaultEditActive || isSecureField()) return
        val code = mail.code
        if (code != null) {
            showStripChip("tempmail", null, "$code · ${mail.from}", "Insert") {
                currentInputConnection?.commitText(code, 1)
                hideStripChip()
            }
        } else {
            showStripChip("tempmail", null, "Mail from ${mail.from}", "Open") {
                hideStripChip()
                showTempMailPanel(mail.id)
            }
        }
    }

    /** The address gone (expired, or mail.tm no longer knows it): forgotten
     *  here too, and let go on mail.tm when it may still be there. */
    private fun endTempBox(message: String?, letGo: Boolean) {
        val box = TempMailStore.load(this)
        if (letGo && box != null) MailTm.delete(tempBase(), box)
        TempMailStore.clear(this)
        tempMails = emptyList()
        main.removeCallbacks(tempTick)
        message?.let { notice(it) }
        if (stripChipKind == "tempmail") hideStripChip()
        if (tempPanelShowing()) showTempInbox()
    }

    /** A new address on mail.tm, then [then] with it; words for the person
     *  when it can't. The one it replaces (New) is let go once the new one
     *  is here. */
    private fun createTempBox(then: (TempBox) -> Unit) {
        if (tempCreating) return
        tempCreating = true
        val old = TempMailStore.load(this)
        val base = tempBase()
        MailTm.create(base) { box, status ->
            main.post {
                tempCreating = false
                if (box == null) {
                    notice(MailTm.createNotice(status))
                    return@post
                }
                TempMailStore.save(this, box)
                tempMails = emptyList()
                tempFails = 0
                if (old != null && old.address != box.address) MailTm.delete(base, old)
                scheduleTempCheck()
                then(box)
            }
        }
    }

    /** An email field's Create, or a chip's Temp mail: the live address,
     *  else a new one, typed in (after "email", with a space between), and
     *  watched from now. */
    private fun insertTempAddress() {
        val live = TempMailStore.load(this)?.takeIf { System.currentTimeMillis() < it.expiresAt }
        val put = { box: TempBox ->
            val ic = currentInputConnection
            ic?.commitText(Smart.spaced(box.address, ic.getTextBeforeCursor(1, 0)?.toString()), 1)
            restartTempWatch(box)
            scheduleTempCheck()
            updateSuggestions()
        }
        if (live != null) put(live) else createTempBox(put)
    }

    /** Temp mail: the address and its inbox, or [openId]'s mail opened.
     *  Opening it starts a new watch window, with a look at once. */
    private fun showTempMailPanel(openId: String? = null) {
        TempMailStore.load(this)?.let { box ->
            if (System.currentTimeMillis() >= box.expiresAt) { endTempBox("That address has expired", letGo = true); return@let }
            restartTempWatch(box)
        }
        val mail = openId?.let { id -> tempMails.firstOrNull { it.id == id } }
        if (mail != null) showTempMail(mail) else showTempInbox()
        main.removeCallbacks(tempTick)
        if (TempMailStore.load(this) != null) checkTempMail()
    }

    private fun showTempInbox() {
        val (panel, body, stage) = panelShell("Temp mail", pad = intArrayOf(12, 8, 12, 8))
        panel.tag = "tempmail"
        tempLine = null
        pinTempCredit(stage)
        val box = TempMailStore.load(this)
        if (box == null) {
            // iOS: a 200 by 44 accent pill in the middle of the panel.
            stage.addView(pill("Create address", primary = true, id = "tempmail:create", accent = true, size = 14f) {
                createTempBox { if (featurePanel?.tag == "tempmail") showTempInbox() }
            }, FrameLayout.LayoutParams(dp(200), dp(44), Gravity.CENTER).apply { bottomMargin = dp(20) })
            return
        }
        // iOS's address card, 82 tall: the address on a line of its own, its
        // middle given up where it doesn't fit; Insert and Copy under it, New
        // and Delete at the far end.
        val cardV = FrameLayout(this).apply {
            background = Glass.card(this@GlyfIME, Glass.surfaceCard, radius = 12f)
        }
        cardV.addView(TextView(this).apply {
            text = box.address
            Glass.style(this, 15f, Glass.MEDIUM)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
            gravity = Gravity.CENTER_VERTICAL
            setTag(com.arpit.glyf.R.id.qa_id, "tempmail:address")
        }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(22)).apply {
            leftMargin = dp(14); rightMargin = dp(14); topMargin = dp(10)
        })
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        actions.addView(pill("Insert", primary = true, id = "tempmail:insert", accent = true, size = 14f) {
            // Typed, and the panel stays: its inbox is what comes next.
            tempInsert(box.address)
            restartTempWatch(box)
            renderTempLine()
            scheduleTempCheck()
        }.apply { minWidth = dp(84); setPadding(dp(16), 0, dp(16), 0) },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)))
        actions.addView(pill("Copy", primary = false, id = "tempmail:copy", size = 14f, field = true) {
            (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager)
                .setPrimaryClip(android.content.ClipData.newPlainText("", box.address))
            notice("Copied")
        }.apply { minWidth = dp(72); setPadding(dp(14), 0, dp(14), 0) },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply { leftMargin = dp(8) })
        actions.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
        actions.addView(smallAction("New", "tempmail:new") {
            createTempBox { if (featurePanel?.tag == "tempmail") showTempInbox() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)))
        actions.addView(smallAction("Delete", "tempmail:delete") {
            MailTm.delete(tempBase(), box)
            TempMailStore.clear(this)
            tempMails = emptyList()
            main.removeCallbacks(tempTick)
            if (stripChipKind == "tempmail") hideStripChip()
            showTempInbox()
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)))
        cardV.addView(actions, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(32)).apply {
            leftMargin = dp(10); rightMargin = dp(4); topMargin = dp(40)
        })
        body.addView(cardV, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(82)))
        // "Watching · 14:32 left", or "Stopped · Watch again": 12 grey, 6
        // under the card and 4 in.
        val line = TextView(this).apply {
            Glass.style(this, 12f, Glass.REGULAR, Glass.textSecondary)
            gravity = Gravity.CENTER_VERTICAL
            maxLines = 1
        }
        body.addView(line, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(22)).apply {
            leftMargin = dp(4); topMargin = dp(6)
        })
        tempLine = line
        renderTempLine()
        main.removeCallbacks(tempClock)
        main.postDelayed(tempClock, 1000)
        if (tempMails.isEmpty()) {
            // Centred in what is left above the credit, as iOS's inbox is.
            val rest = keyboard.height - dp(20) - dp(8 + 82 + 6 + 22 + 4) - dp(8)
            body.addView(TextView(this).apply {
                text = "No mail yet"
                Glass.style(this, 14f, Glass.REGULAR, Glass.textSecondary)
                gravity = Gravity.CENTER
                setTag(com.arpit.glyf.R.id.qa_id, "tempmail:empty")
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, maxOf(dp(40), rest)).apply {
                topMargin = dp(4)
            })
        } else for ((i, mail) in tempMails.withIndex()) body.addView(tempRow(i, mail),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(52)).apply {
                topMargin = if (i == 0) dp(4) else dp(6)
            })
    }

    /** mail.tm asks to be linked to where it is used: a quiet line pinned
     *  at the panel's foot on every screen of it (what scrolls ends above
     *  it), opening its site. */
    private fun pinTempCredit(stage: FrameLayout) {
        val h = dp(20)
        stage.getChildAt(0)?.let { scroll ->
            scroll.layoutParams = (scroll.layoutParams as FrameLayout.LayoutParams).apply { bottomMargin = h }
        }
        stage.addView(TextView(this).apply {
            text = "via mail.tm"
            Glass.style(this, 11f, Glass.REGULAR, Glass.textSecondary)
            gravity = Gravity.CENTER
            setPadding(dp(16), 0, dp(16), 0)
            setTag(com.arpit.glyf.R.id.qa_id, "tempmail:credit")
            setOnClickListener {
                runCatching {
                    startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://mail.tm"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, h,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))
    }

    private fun renderTempLine() {
        val line = tempLine ?: return
        val box = TempMailStore.load(this) ?: return
        val left = box.watchUntil - System.currentTimeMillis()
        if (tempWatching(box) && left > 0) {
            val s = left / 1000
            line.text = "Watching · %d:%02d left".format(s / 60, s % 60)
            line.setTag(com.arpit.glyf.R.id.qa_id, "tempmail:watching")
            line.setOnClickListener(null)
            line.isClickable = false
        } else {
            val words = android.text.SpannableString("Stopped · Watch again")
            words.setSpan(android.text.style.ForegroundColorSpan(Glass.chipAccent), 10, words.length, 0)
            words.setSpan(android.text.style.TypefaceSpan(Glass.font(this, Glass.SEMIBOLD)), 10, words.length, 0)
            line.text = words
            line.setTag(com.arpit.glyf.R.id.qa_id, "tempmail:watch")
            line.setOnClickListener {
                restartTempWatch(TempMailStore.load(this) ?: return@setOnClickListener)
                renderTempLine()
                checkTempMail()
            }
        }
    }

    /** A mail in the inbox, iOS's 52 tall row: who and when, then what,
     *  with a code to put in straight away on a pill at the end. */
    private fun tempRow(i: Int, mail: TempMail): View {
        val row = FrameLayout(this).apply {
            background = Glass.card(this@GlyfIME, Glass.surfaceCard, radius = 12f)
            setTag(com.arpit.glyf.R.id.qa_id, "tempmail:row:$i")
            setOnClickListener { showTempMail(mail) }
        }
        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        top.addView(TextView(this).apply {
            text = mail.from.ifBlank { mail.fromAddress }
            Glass.style(this, 14f, Glass.BOLD)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        top.addView(TextView(this).apply {
            text = TempMailRules.ago(mail.receivedAt)
            Glass.style(this, 12f, Glass.REGULAR, Glass.textSecondary)
            gravity = Gravity.END
            maxLines = 1
            minWidth = dp(40)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(8) })
        row.addView(top, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(18)).apply {
            leftMargin = dp(12); rightMargin = dp(12); topMargin = dp(8)
        })
        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        bottom.addView(TextView(this).apply {
            text = mail.subject
            Glass.style(this, 13f, Glass.REGULAR, Glass.textSecondary)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val code = mail.code
        // One run of words, so the scenarios read the code off the pill.
        if (code != null) bottom.addView(TextView(this).apply {
            val words = android.text.SpannableString("$code  Insert")
            words.setSpan(android.text.style.ForegroundColorSpan(Glass.chipAccent), code.length + 2, words.length, 0)
            text = words
            Glass.style(this, 13f, Glass.SEMIBOLD)
            fontFeatureSettings = "tnum"
            gravity = Gravity.CENTER
            maxLines = 1
            setPadding(dp(10), 0, dp(10), 0)
            background = Glass.pill(Glass.fillField)
            setTag(com.arpit.glyf.R.id.qa_id, "tempmail:rowcode:$i")
            setOnClickListener { tempInsert(code) }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(22)).apply { leftMargin = dp(8) })
        row.addView(bottom, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(22)).apply {
            leftMargin = dp(12); rightMargin = if (code != null) dp(8) else dp(12); topMargin = dp(26)
        })
        return row
    }

    /** One mail, iOS's: the subject and who, the code big on a card with
     *  Copy and Insert at its end, the link, then the words. */
    private fun showTempMail(mail: TempMail) {
        val (panel, body, stage) = panelShell("Temp mail", onBack = { showTempInbox() },
            pad = intArrayOf(12, 10, 12, 12))
        panel.tag = "tempmail:mail"
        pinTempCredit(stage)
        main.removeCallbacks(tempClock)
        body.addView(TextView(this).apply {
            text = mail.subject.ifBlank { mail.from }
            Glass.style(this, 16f, Glass.SEMIBOLD)
            setTag(com.arpit.glyf.R.id.qa_id, "tempmail:subject")
        })
        body.addView(TextView(this).apply {
            text = "${mail.from.ifBlank { mail.fromAddress }} · ${TempMailRules.ago(mail.receivedAt)}"
            Glass.style(this, 12f, Glass.REGULAR, Glass.textSecondary)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_VERTICAL
            setTag(com.arpit.glyf.R.id.qa_id, "tempmail:from")
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(16)).apply { topMargin = dp(2) })
        val code = mail.code
        if (code != null) {
            val block = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(14), 0, dp(10), 0)
                background = Glass.card(this@GlyfIME, Glass.surfaceCard, radius = 12f)
            }
            block.addView(TextView(this).apply {
                text = code
                Glass.style(this, 28f, Glass.SEMIBOLD)
                fontFeatureSettings = "tnum"
                letterSpacing = 0.07f
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
                setAutoSizeTextTypeUniformWithConfiguration(17, 28, 1, android.util.TypedValue.COMPLEX_UNIT_DIP)
                setTag(com.arpit.glyf.R.id.qa_id, "tempmail:code")
            }, LinearLayout.LayoutParams(0, dp(44), 1f).apply { rightMargin = dp(10) })
            block.addView(pill("Copy", primary = false, id = "tempmail:code:copy", size = 14f, field = true) {
                (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager)
                    .setPrimaryClip(android.content.ClipData.newPlainText("", code))
                notice("Copied")
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(34)))
            block.addView(pill("Insert", primary = true, id = "tempmail:code:insert", accent = true, size = 14f) {
                tempInsert(code)
            }.apply { setPadding(dp(14), 0, dp(14), 0) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(34)).apply { leftMargin = dp(8) })
            body.addView(block, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(56)).apply {
                topMargin = dp(10)
            })
        }
        val link = mail.link
        if (link != null) body.addView(pill("Insert link", primary = false, id = "tempmail:link", size = 14f, field = true) {
            tempInsert(link)
        }.apply { setPadding(dp(14), 0, dp(14), 0) },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply {
                topMargin = if (code != null) dp(8) else dp(10)
            })
        body.addView(TextView(this).apply {
            text = mail.text
            Glass.style(this, 14f)
            setLineSpacing(dp(2).toFloat(), 1f)
            setTag(com.arpit.glyf.R.id.qa_id, "tempmail:text")
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = if (link != null) dp(8) else if (code != null) dp(8) else dp(10)
        })
    }

    /** Temp mail's Insert (the address, a code, a link): typed into the
     *  message, and the panel stays (Arpit, 2026-10-01: "when i click insert
     *  in temp mail i should not redirect back to keyboard, should stay
     *  here"), saying so over the keys. */
    private fun tempInsert(text: String) {
        currentInputConnection?.commitText(text, 1)
        notice("Added to the message")
    }

    /** A quiet text action beside the card's buttons (New, Delete): 13
     *  medium grey, 8 either side (iOS). */
    private fun smallAction(label: String, id: String, onTap: () -> Unit) = TextView(this).apply {
        text = label
        Glass.style(this, 13f, Glass.MEDIUM, Glass.textSecondary)
        gravity = Gravity.CENTER
        setPadding(dp(8), 0, dp(8), 0)
        setTag(com.arpit.glyf.R.id.qa_id, id)
        setOnClickListener { onTap() }
    }

    /** The strip chip's lighter purple, for words that act. */
    private fun stripAccent() = Glass.skinChipAccent
        ?: if (chromeDark) Color.rgb(0xC3, 0xB4, 0xFF) else Color.rgb(0x8A, 0x6C, 0xFF)

    // MARK: emoji board (EmojiBoard.swift twin: Emoji, Stickers, GIFs, Emoticons)

    private var emojiBoard: EmojiBoardView? = null
    /** The board's full height: the strip plus the keys it stands in for. */
    private var emojiBoardFull = 0

    private val emojiHost = object : EmojiBoardView.Host {
        override val backendURL: String get() = settings.optString("backendURL")
        override val palette: GlyfKeyboardView.KeyPalette get() = keyboard.palette()
        override val dark: Boolean get() = chromeDark
        override val online: Boolean get() = runCatching {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            cm.activeNetwork != null
        // Can't tell: try the network, and let the request say.
        }.getOrDefault(true)
        override fun commitText(text: String, spaced: Boolean) {
            val ic = currentInputConnection ?: return
            val before = ic.getTextBeforeCursor(1, 0)?.toString().orEmpty()
            // ":-)" is a word of its own; glued to the last one it reads "later:-)".
            val out = if (spaced && before.isNotEmpty() && !before.last().isWhitespace()) " $text" else text
            ic.commitText(out, 1)
        }
        override fun deleteBackward() = onKey("delete", null)
        override fun backToLetters() = dismissFeaturePanel()
        override fun searchChanged(active: Boolean) {
            val board = emojiBoard ?: return
            // Searching shows the letter keys under a strip (Apple's and
            // Gboard's emoji search); closing it gives the board back its keys.
            keyboard.visibility = if (active) View.VISIBLE else View.GONE
            board.layoutParams = (board.layoutParams as LinearLayout.LayoutParams).apply {
                height = if (active) dp(96) else emojiBoardFull
            }
            // The field's auto-capital shift is not the search's: start lower.
            if (active) { keyboard.mode = Mode.LETTERS; keyboard.shifted = false; keyboard.rebuild() }
        }
        override fun sendMedia(item: MediaItem, kind: MediaKind, done: (Boolean) -> Unit) =
            sendMediaItem(item, kind, done)
    }

    /** The board on Emoji from the emoji key; on GIFs from the menu's tile. */
    private fun showEmojiPanel(mode: EmojiBoardView.Mode = EmojiBoardView.Mode.EMOJI) {
        dismissFeaturePanel()
        val barH = if (toolbar.height > 0) toolbar.height else dp(stripDp)
        val keysH = if (keyboard.height > 0) keyboard.height else dp(216)
        emojiBoardFull = barH + keysH
        val board = EmojiBoardView(this, emojiHost)
        toolbar.visibility = View.GONE
        keyboard.visibility = View.GONE
        root.addView(board, 0, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, emojiBoardFull))
        featurePanel = board
        emojiBoard = board
        if (mode != board.mode) board.setMode(mode)
    }

    /**
     * A GIF or sticker into the field. Android lets a keyboard hand an image
     * to a field that says it takes one (`commitContent`, what Gboard does):
     * then it simply arrives in the message. Anywhere else it is copied, the
     * way iOS always has to, and the person pastes it.
     */
    private fun sendMediaItem(item: MediaItem, kind: MediaKind, done: (Boolean) -> Unit) {
        val noun = if (kind == MediaKind.GIFS) "GIF" else "Sticker"
        MediaClient.fullData(item.url) { bytes ->
            if (bytes == null || bytes.size < 8) {
                notice("That ${noun.lowercase()} didn't download. Try again")
                done(false)
                return@fullData
            }
            val gif = bytes[0] == 'G'.code.toByte() && bytes[1] == 'I'.code.toByte() && bytes[2] == 'F'.code.toByte()
            val mime = if (gif) "image/gif" else "image/png"
            // The file is written on a worker (a GIF can be megabytes and the
            // disk can be busy); only the hand-over runs on the main thread.
            Thread {
                val uri = runCatching {
                    val dir = java.io.File(cacheDir, "media").apply { mkdirs() }
                    // Only the latest few stay: they are handed over, not kept.
                    dir.listFiles()?.sortedBy { it.lastModified() }?.dropLast(4)?.forEach { it.delete() }
                    val file = java.io.File(dir, "glyf-${System.currentTimeMillis()}.${if (gif) "gif" else "png"}")
                        .apply { writeBytes(bytes) }
                    androidx.core.content.FileProvider.getUriForFile(this, "$packageName.media", file)
                }.getOrNull()
                main.post {
                    if (uri == null) { done(false); return@post }
                    val accepted = currentInputEditorInfo?.contentMimeTypes.orEmpty()
                    val fits = accepted.any { android.content.ClipDescription.compareMimeTypes(mime, it) }
                    val ic = currentInputConnection
                    if (fits && ic != null) {
                        val info = android.view.inputmethod.InputContentInfo(
                            uri, android.content.ClipDescription(noun, arrayOf(mime)), null)
                        val ok = ic.commitContent(info,
                            android.view.inputmethod.InputConnection.INPUT_CONTENT_GRANT_READ_URI_PERMISSION, null)
                        if (ok) { done(true); return@post }
                    }
                    val clip = android.content.ClipData(noun, arrayOf(mime), android.content.ClipData.Item(uri))
                    (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(clip)
                    notice("$noun copied. Paste it in the message")
                    done(true)
                }
            }.start()
        }
    }

    /** Toolbar translate — same as iOS: runs glyf.translate on the field. */
    // MARK: Translate strip (iOS TranslationHUD twin)

    private var translateStrip: LinearLayout? = null
    /** What Replace just put in; see applyTranslation. */
    private var translateReplaced = ""
    private var translateDir: TextView? = null
    private var translateText: TextView? = null
    private var translateReplace: TextView? = null
    private var translateSource = ""
    private var translateResult = ""
    private var translateDetected: String? = null
    private var translateTarget: String? = null
    private var translateForced: String? = null
    /** The end of the draft that was translated, as it stands in the field:
     *  Replace swaps exactly this, never anything before it (iOS lastWindow). */
    private var translateSpan = ""

    /** The person's two languages: the phone's first, and the other one they
     *  type in (last detected), else the phone's next, else the region's. */
    private fun translatePair(): Pair<String, String> {
        val locales = resources.configuration.locales
        val names = (0 until locales.size()).map { locales[it].getDisplayLanguage(java.util.Locale.ENGLISH) }
        val primary = names.firstOrNull() ?: "English"
        val region = locales[0].country
        val fallback = if (region == "IN") (if (primary == "Hindi") "English" else "Hindi")
                       else (if (primary == "English") "Spanish" else "English")
        val typed = settings.optString("translateOther").takeIf { it.isNotBlank() && it != primary }
        return primary to (typed ?: names.drop(1).firstOrNull { it != primary } ?: fallback)
    }

    /** Translate takes the strip's place, the way it does on iOS. */
    private fun runTranslateOnField() {
        if (translateStrip != null) { exitTranslate(); return }
        if (isSecureField()) return
        dismissFeaturePanel()
        val strip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(4), 0)
        }
        // iOS's translate bar (TranslationHUD): the direction in a pill of
        // the key colour, the translation 17 semibold on one line (its end
        // in view), Replace in iMessage blue, and a quiet ✕.
        val dir = TextView(this).apply {
            text = "Translate"
            Glass.style(this, 13f, Glass.SEMIBOLD)
            gravity = Gravity.CENTER
            maxLines = 1
            setPadding(dp(12), 0, dp(12), 0)
            background = Glass.pill(Glass.surfaceCard)
            setTag(com.arpit.glyf.R.id.qa_id, "hud:direction")
            setOnClickListener { cycleTranslateTarget() }
        }
        val text = TextView(this).apply {
            text = "…"
            Glass.style(this, 17f, Glass.SEMIBOLD)
            isSingleLine = true
            ellipsize = android.text.TextUtils.TruncateAt.START
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), 0, dp(8), 0)
            // The direction pill grows ("Translate" → "English → Spanish")
            // as the translation lands: fit again to the room left.
            addOnLayoutChangeListener { v, l, _, r, _, oldL, _, oldR, _ ->
                if (r - l != oldR - oldL) fitTranslation(v as TextView, (v as TextView).text.toString())
            }
        }
        val replace = TextView(this).apply {
            this.text = "Replace"
            Glass.style(this, 14f, Glass.SEMIBOLD, Color.WHITE)
            gravity = Gravity.CENTER
            background = Glass.pill(Color.rgb(0x0A, 0x84, 0xFF))
            alpha = 0.3f
            setTag(com.arpit.glyf.R.id.qa_id, "hud:replace")
            setOnClickListener { applyTranslation() }
        }
        val close = ToolIcon(this, "close", Glass.textSecondary).apply {
            solid = true; weight = 2f; scale = 0.95f
            setTag(com.arpit.glyf.R.id.qa_id, "hud:close"); contentDescription = "Close"
            setOnClickListener { exitTranslate() }
        }
        strip.addView(dir, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(30)))
        strip.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        strip.addView(replace, LinearLayout.LayoutParams(dp(84), dp(30)))
        strip.addView(close, LinearLayout.LayoutParams(dp(36), dp(34)))
        toolbar.visibility = View.GONE
        root.addView(strip, root.indexOfChild(toolbar),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(stripDp)))
        translateStrip = strip
        translateDir = dir
        translateText = text
        translateReplace = replace
        translateForced = null
        translateSource = ""
        translateDraftChanged()
    }

    private fun exitTranslate() {
        translateStrip?.let { root.removeView(it) }
        translateStrip = null
        translateSource = ""
        translateResult = ""
        toolbar.visibility = View.VISIBLE
    }

    /** What of a draft gets translated: all of it up to 280 characters,
     *  else its end from the start of a sentence (or at least of a word), so
     *  no word is cut in half (iOS TranslationHUD.window). */
    private fun translateWindow(draft: String): String {
        if (draft.length <= 280) return draft
        var tail = draft.takeLast(280)
        // Never half an emoji at the cut.
        if (Character.isLowSurrogate(tail[0])) tail = tail.drop(1)
        val sentence = Regex("""[.!?\n]\s+""").find(tail)?.range?.last?.plus(1)
        if (sentence != null && sentence < tail.length) return tail.substring(sentence)
        val space = tail.indexOf(' ')
        return if (space >= 0) tail.substring(space + 1) else tail
    }

    /** Called on word commits: translate what is typed so far. */
    private fun translateDraftChanged() {
        if (translateStrip == null || isSecureField()) return
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(2000, 0)?.toString() ?: ""
        val window = translateWindow(before)
        val text = window.trim()
        translateSpan = window
        if (text.isEmpty() || text == translateSource || text == translateReplaced) return
        translateReplaced = ""
        translateSource = text
        translateResult = ""
        translateText?.let { fitTranslation(it, "…") }
        translateReplace?.alpha = 0.3f
        val (primary, secondary) = translatePair()
        BackendClient.translate(settings.optString("backendURL"), settings.optString("deviceId"),
            text, primary, secondary, translateForced) { result ->
            main.post {
                if (result == null || translateSource != text || translateStrip == null) return@post
                translateDetected = result.detected
                translateTarget = result.target
                translateDir?.text = "${result.detected} → ${result.target}"
                translateText?.let { fitTranslation(it, result.text) }
                translateResult = result.text
                translateReplace?.alpha = 1f
                if (result.detected != primary && result.detected != "Unknown" &&
                    settings.optString("translateOther") != result.detected) {
                    settings.put("translateOther", result.detected)
                    SettingsStore.save(this, settings.toString())
                }
            }
        }
    }

    private fun cycleTranslateTarget() {
        val (primary, secondary) = translatePair()
        val options = listOf(primary, secondary, "English", "Hindi", "Spanish", "French")
            .distinct().filter { it != translateDetected }
        if (options.isEmpty()) return
        val current = translateTarget ?: options[0]
        val next = options[(options.indexOf(current) + 1).mod(options.size)]
        translateForced = next
        translateTarget = next
        translateDir?.text = "${translateDetected ?: "Translate"} → $next"
        translateSource = ""
        translateDraftChanged()
    }

    private fun applyTranslation() {
        if (translateResult.isEmpty()) return
        val ic = currentInputConnection ?: return
        // Only what was translated goes, and only while it still ends the
        // text: anything typed since, or before it, stays untouched.
        val span = translateSpan
        val before = ic.getTextBeforeCursor(span.length + 1, 0)?.toString() ?: ""
        if (span.isEmpty() || !before.endsWith(span)) {
            notice("The text changed since the translation")
            return
        }
        // The space the draft ended on stays after the translation.
        val trailing = span.takeLastWhile { it.isWhitespace() }
        ic.beginBatchEdit()
        ic.deleteSurroundingText(span.length, 0)
        ic.commitText(translateResult + trailing, 1)
        ic.endBatchEdit()
        // The draft is now the translation: don't translate it back, and
        // rest rather than show "…" as if waiting (iOS twin).
        translateReplaced = translateResult.trim()
        translateSource = ""
        translateResult = ""
        translateText?.text = ""
        translateReplace?.alpha = 0.3f
    }

    /** The translation in the bar: one line at 17, shrinking to 14; then two
     *  lines at 14 when they hold all of it; else one line at 14 with its
     *  start cut, the newest words in view (iOS twin: TranslationHUD.fitText).
     *  Beside the direction pill a 411 dp phone showed only "…emos a las 8!"
     *  of "¡Nos vemos a las 8!". (Android's own autosize never shrinks an
     *  ellipsized single line: it always "fits".) */
    private fun fitTranslation(tv: TextView, s: String) {
        tv.text = s
        val room = tv.width - tv.paddingLeft - tv.paddingRight
        if (room <= 0) { tv.post { if (tv.text.toString() == s) fitTranslation(tv, s) }; return }
        val paint = android.text.TextPaint(tv.paint)
        fun px(sp: Float) = android.util.TypedValue.applyDimension(
            android.util.TypedValue.COMPLEX_UNIT_SP, sp, resources.displayMetrics)
        var sp = 17f
        paint.textSize = px(sp)
        while (sp > 14f && paint.measureText(s) > room) { sp -= 0.5f; paint.textSize = px(sp) }
        val twoLines = paint.measureText(s) > room &&
            android.text.StaticLayout.Builder.obtain(s, 0, s.length, paint, room).build().lineCount <= 2
        if (twoLines) {
            tv.isSingleLine = false
            tv.maxLines = 2
            tv.ellipsize = android.text.TextUtils.TruncateAt.END
        } else {
            tv.isSingleLine = true
            tv.ellipsize = android.text.TextUtils.TruncateAt.START
        }
        tv.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, sp)
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private var noticeView: View? = null
    private val hideNotice = Runnable {
        noticeView?.let { if (::root.isInitialized) root.overlay.remove(it) }
        noticeView = null
    }

    /** A short message over the keys ("Copied", "Connect Google Meet in
     *  Glyf › Connected tools"). Not a system Toast, and not a PopupWindow:
     *  Android draws a keyboard's window above both, so either one sits
     *  under the keys where nobody sees it. It goes on the keyboard's own
     *  overlay instead. iOS twin: KeyboardToast. */
    fun notice(text: String) {
        main.post {
            if (!::root.isInitialized || !root.isShown || root.width == 0) {
                android.widget.Toast.makeText(this, text, android.widget.Toast.LENGTH_SHORT).show()
                return@post
            }
            main.removeCallbacks(hideNotice)
            noticeView?.let { root.overlay.remove(it) }
            // iOS's KeyboardToast: a 28 tall pill, 14 corners, near-black at
            // 94%, 13 semibold white, 8 into the keyboard's view (iOS 26's
            // sheet band sits above that view; Android has none).
            val label = TextView(this).apply {
                this.text = text
                Glass.style(this, 13f, Glass.SEMIBOLD, Color.WHITE)
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(dp(13), 0, dp(13), 0)
                background = GradientDrawable().apply {
                    cornerRadius = dp(14).toFloat()
                    setColor(Color.argb(240, 31, 31, 31))
                }
                setTag(com.arpit.glyf.R.id.qa_id, "kb:notice")
            }
            label.measure(
                View.MeasureSpec.makeMeasureSpec(root.width - dp(24), View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(dp(28), View.MeasureSpec.EXACTLY))
            val left = (root.width - label.measuredWidth) / 2
            val top = dp(8)
            label.layout(left, top, left + label.measuredWidth, top + label.measuredHeight)
            root.overlay.add(label)
            noticeView = label
            main.postDelayed(hideNotice, 2400)
        }
    }
}
