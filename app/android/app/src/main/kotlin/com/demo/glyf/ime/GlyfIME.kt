package com.demo.glyf.ime

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
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
import com.demo.glyf.MainActivity
import com.demo.glyf.store.Bridge
import com.demo.glyf.store.SettingsStore
import com.demo.glyf.store.VaultStore
import com.demo.glyf.ime.typing.KeyboardTyping
import com.demo.glyf.ime.typing.TypingEngine
import com.demo.glyf.ime.typing.WordContext
import org.json.JSONObject
import kotlin.math.abs

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
        enum class Kind { LITERAL, CORRECTION, WORD, UNDO, FILL }
    }
    private data class Correction(val original: String, val replacement: String, val fromEngine: Boolean)
    private var lastCorrection: Correction? = null
    /** Where each letter of the word being typed was touched. */
    private val wordTouches = ArrayList<FloatArray?>()
    private var wordTouchesFor = ""

    // Search suite (Gboard parity) state
    private var searchActive = false
    private var searchTab = "web"
    private var searchQuery = ""
    private var searchStrip: LinearLayout? = null
    private var searchResults: LinearLayout? = null
    private var searchQueryView: TextView? = null
    private var searchStatusView: TextView? = null
    /// Suggestions shown while the KEYS STAY VISIBLE — you must be able to
    /// start typing over a suggestion, so this is a separate slot from
    /// `searchResults`, which does replace the keys.
    private var searchLanding: LinearLayout? = null

    // MARK: lifecycle

    override fun onCreate() {
        super.onCreate()
        KeyboardTyping.prepare(this) { }
        (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager)
            .addPrimaryClipChangedListener(clipListener)
        if (com.demo.glyf.BuildConfig.DEBUG) {
            // Injected taps never reach an IME window on the emulator, so debug
            // builds open panels by broadcast to check them:
            //   adb shell am broadcast -a com.demo.glyf.DEBUG_TOOL --es id menu
            val filter = android.content.IntentFilter("com.demo.glyf.DEBUG_TOOL")
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                registerReceiver(debugTool, filter, RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(debugTool, filter)
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
                "close" -> dismissFeaturePanel()
                "delwords" -> {
                    val n = intent.getIntExtra("count", 1)
                    onDeleteWordsPreview(n)
                    main.postDelayed({ onDeleteWordsCommit(n) }, 600)
                }
                else -> openTool(id)
            }
        }
    }

    override fun onDestroy() {
        (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager)
            .removePrimaryClipChangedListener(clipListener)
        if (com.demo.glyf.BuildConfig.DEBUG) runCatching { unregisterReceiver(debugTool) }
        super.onDestroy()
    }

    @SuppressLint("InflateParams")
    override fun onCreateInputView(): View {
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
        }
        keyboard = GlyfKeyboardView(this, this)
        // Gboard's toolbar: 47dp from the board's top edge to the key area.
        root.addView(toolbar, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(47)))
        root.addView(keyboard)
        // Keep the key rows clear of the keyboard's navigation strip. With
        // gesture navigation Android draws a 48dp strip under an IME (hide
        // and switch-keyboard buttons) but reports only the 24dp gesture bar
        // as navigationBars; the strip is the tappable inset. Gboard clears it
        // and leaves 6dp more, measured on the emulator.
        // Start at the usual answer (a 48dp strip) so the first show is laid
        // out right; the insets below correct it where a phone differs.
        root.setPadding(0, 0, 0, dp(48) + dp(6))
        root.setOnApplyWindowInsetsListener { v, insets ->
            val bottom = if (android.os.Build.VERSION.SDK_INT >= 30) {
                maxOf(insets.getInsets(android.view.WindowInsets.Type.navigationBars()).bottom,
                      insets.getInsets(android.view.WindowInsets.Type.tappableElement()).bottom)
            } else @Suppress("DEPRECATION") insets.systemWindowInsetBottom
            if (v.paddingBottom != bottom + dp(6)) v.setPadding(0, 0, 0, bottom + dp(6))
            insets
        }
        return root
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        android.util.Log.d("GlyfKB", "onStartInputView restarting=$restarting overlay=${overlay != null}")
        settings = SettingsStore.load(this)
        settingsStamp = com.demo.glyf.store.Bridge.file(this, SettingsStore.FILE).lastModified()
        val dark = when (settings.optString("appearance", "auto")) {
            "dark" -> true
            "light" -> false
            else -> resources.configuration.uiMode and
                android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
        }
        keyboard.isDark = dark
        keyboard.keyTheme = settings.optString("keyTheme", "site")
        keyboard.themeBg = settings.optString("themeBg", "")
        keyboard.keyBorders = settings.optBoolean("keyBorders", false)
        keyboard.themeDim = settings.optDouble("themeBrightness", 0.0).toFloat()
        keyboard.numberRow = settings.optBoolean("numberRow", false)
        keyboard.hapticsOn = settings.optBoolean("haptics", true)
        keyboard.clicksOn = settings.optBoolean("keyClicks", true)
        keyboard.kContext = KContext.from(info)
        keyboard.mode = Mode.LETTERS
        keyboard.bindings = settings.optJSONObject("bindings")?.let { b ->
            b.keys().asSequence().associateWith { b.optString(it) }
        } ?: emptyMap()
        val themed = keyboard.themedBackdrop()
        if (themed != null) root.background = themed
        else root.setBackgroundColor(keyboard.backdrop())
        buildToolbar(dark || keyboard.themeBg.isNotEmpty())
        applyTourHint()
        // Android hands a keyboard the clipboard without asking, so history
        // fills itself: whatever was copied since last time is kept here.
        if (!isSecureField()) com.demo.glyf.store.ClipboardStore.captureNow(this)
        actGeneration++ // a late act result must not land in a new field
        dismissOverlay()
        if (searchActive) exitSearch()
        if (barActive) exitBar()
        if (translateStrip != null) exitTranslate()
        keyboard.rebuild()
        syncAutoShift()
        refreshClipCard()
        lastCorrection = null
        wordTouches.clear()
        wordTouchesFor = ""
        toolsPinned = false
        KeyboardTyping.prepare(this) { updateSuggestions() }

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
        KeyboardTyping.saveNow(this)
    }

    // MARK: toolbar (g keycap + essentials)

    private fun buildToolbar(dark: Boolean) {
        toolbar.removeAllViews()
        val ink = if (dark) Color.WHITE else Color.rgb(18, 18, 20)

        val g = TextView(this).apply {
            text = "g"
            setTextColor(Color.WHITE)
            textSize = 19f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.rgb(18, 18, 20))
                // The brand pill stays black everywhere; on dark chrome a
                // faint ring keeps it from melting into the backdrop.
                if (dark) setStroke(dp(1), Color.argb(96, 255, 255, 255))
            }
            setOnClickListener {
                // While suggestions fill the strip, g brings the tools back (iOS §6.2).
                if (featurePanel is ToolMenuView) {
                    dismissFeaturePanel()
                } else if (suggestionRow.visibility == View.VISIBLE) {
                    toolsPinned = true
                    applySuggestionVisibility()
                } else showMenuGrid() // iOS shell parity
            }
            setOnLongClickListener { openApp(); true }
        }
        toolbar.addView(g, LinearLayout.LayoutParams(dp(38), dp(30)))
        toolIcons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
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
        for (id in stripTools()) {
            val v = ToolIcon(this, id, ink)
            v.contentDescription = id
            v.setOnClickListener { openTool(id) }
            toolIcons.addView(v, LinearLayout.LayoutParams(0, dp(34), 1f))
        }
        gPill = g
    }

    private var gPill: TextView? = null

    private fun stripTools(): List<String> {
        val known = ToolIcon.TOOLS.map { it.first }.toSet()
        val order = settings.optJSONArray("toolbarOrder")
        val hidden = settings.optJSONArray("toolbarHidden")
        val hiddenSet = (0 until (hidden?.length() ?: 0)).map { hidden!!.optString(it) }.toSet()
        val ids = (0 until (order?.length() ?: 0)).map { order!!.optString(it) }
            .ifEmpty { listOf("search", "clipboard", "vault", "dictation", "translate") }
        return ids.filter { it in known && it !in hiddenSet }.distinct()
    }

    /** Every tool opens the same way from the strip and from the g menu. */
    private fun openTool(id: String) {
        when (id) {
            "search" -> { dismissFeaturePanel(); enterSearch() }
            "clipboard" -> showClipboardPanel()
            "emoji" -> showEmojiPanel()
            "rewrite" -> { dismissFeaturePanel(); showGlyfBar() }
            "translate" -> { dismissFeaturePanel(); runTranslateOnField() }
            "ask" -> { dismissFeaturePanel(); onSpaceHoldOpenBar() }
            "dictation" -> { dismissFeaturePanel(); startVoiceTyping() }
            "vault" -> showVaultPanel()
            "glyfs" -> showMyGlyfsPanel()
            "shorthand" -> showShorthandPanel()
            "keys" -> showKeysPanel()
            // Paying is signed in the app's wallet, never in the keyboard.
            "pay" -> { dismissFeaturePanel(); openAppPath("wallet") }
            "settings" -> { dismissFeaturePanel(); openApp() }
        }
    }

    /** Voice typing is the system's: hand over to the voice keyboard the
     *  person already has (Google voice typing, usually), the way Gboard's
     *  mic does, and come back to Glyf when they switch again. */
    private fun startVoiceTyping() {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
        for (info in imm.enabledInputMethodList) {
            for (sub in imm.getEnabledInputMethodSubtypeList(info, true)) {
                if (sub.mode == "voice") {
                    switchInputMethod(info.id, sub)
                    return
                }
            }
        }
        android.widget.Toast.makeText(this, "No voice typing on this phone",
            android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun openAppPath(path: String) {
        startActivity(Intent(Intent.ACTION_VIEW,
            android.net.Uri.parse("glyf://open?path=$path"))
            .setPackage(packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun openApp() {
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun pasteClipboard() {
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        cm.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()?.let {
            currentInputConnection?.commitText(it, 1)
        }
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

    private fun enterSearch() {
        if (searchActive) return
        removeClipCard()
        searchActive = true
        searchTab = "web"
        searchQuery = ""
        toolbar.visibility = View.GONE
        val strip = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(4), dp(8), dp(4))
        }
        val chips = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun chip(label: String, tabId: String, mark: android.graphics.drawable.Drawable?) {
            val c = TextView(this).apply {
                text = label
                textSize = 12.5f
                gravity = Gravity.CENTER
                setPadding(dp(11), dp(5), dp(13), dp(5))
                // The brand marks keep their own colour through the active
                // state; only the label follows the chip.
                mark?.setBounds(0, 0, dp(15), dp(15))
                setCompoundDrawables(mark, null, null, null)
                compoundDrawablePadding = dp(6)
                setOnClickListener {
                    searchTab = tabId
                    styleChips(chips)
                    if (searchQuery.isBlank()) showLanding() else submitSearch()
                }
                tag = tabId
            }
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, dp(30))
            lp.setMargins(0, 0, dp(7), 0)
            chips.addView(c, lp)
        }
        chip("Search", "web", SearchCards.GoogleMark())
        chip("YouTube", "yt", SearchCards.YouTubeMark())
        chip("Maps", "maps", SearchCards.PinMark())
        chip("Contacts", "contacts", null)
        val chipScroll = android.widget.HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(chips)
        }
        styleChips(chips)

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(5), 0, 0)
        }
        val back = TextView(this).apply {
            text = "✕"; textSize = 16f; setTextColor(ink())
            setPadding(dp(6), 0, dp(10), 0)
            setOnClickListener { exitSearch() }
        }
        val query = TextView(this).apply {
            hint = "Type, then ⏎"
            textSize = 15f
            setTextColor(ink())
            setHintTextColor(Color.argb(120, 128, 128, 136))
            setPadding(dp(12), dp(7), dp(12), dp(7))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat(); setColor(card())
            }
        }
        val go = TextView(this).apply {
            text = "→"; textSize = 18f; setTextColor(ink())
            setPadding(dp(12), 0, dp(6), 0)
            setOnClickListener { submitSearch() }
        }
        row.addView(back)
        row.addView(query, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(go)
        val status = TextView(this).apply {
            textSize = 11.5f; setTextColor(Color.GRAY); setPadding(dp(8), dp(2), 0, 0)
        }
        strip.addView(chipScroll)
        strip.addView(row)
        strip.addView(status)
        root.addView(strip, 0)
        searchStrip = strip
        searchQueryView = query
        searchStatusView = status
        showLanding()
    }

    /** What a tab shows BEFORE anything is typed: the user's own recents
     *  (local, never uploaded) then trending / popular / nearby from the
     *  server. Gboard never opens on a blank box. */
    private fun showLanding() {
        val vertical = searchTab
        val recents = com.demo.glyf.store.SearchRecents.list(this, vertical)
            .map { q ->
                BackendClient.SearchCard(
                    kind = "query", id = "recent-$q", title = q, url = "",
                    source = "recent")
            }
        if (recents.isNotEmpty()) showLandingRows(recents)
        if (vertical == "contacts") {
            searchStatusView?.text =
                if (com.demo.glyf.store.Bridge.file(this, "contacts.json").exists())
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

    private fun styleChips(chips: LinearLayout) {
        for (i in 0 until chips.childCount) {
            val c = chips.getChildAt(i) as TextView
            val active = c.tag == searchTab
            c.setTextColor(if (active) card() else ink())
            c.background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(if (active) ink() else card())
            }
        }
    }

    private fun renderQuery() {
        searchQueryView?.text = searchQuery
    }

    private fun submitSearch() {
        val q = searchQuery.trim()
        if (q.isEmpty()) return
        if (searchTab == "contacts") {
            val rows = contactMatches(q)
            if (rows.isEmpty()) {
                searchStatusView?.text =
                    if (com.demo.glyf.store.Bridge.file(this, "contacts.json").exists())
                        "No contact matches"
                    else "Turn on Contacts search in the Glyf app"
            } else showSearchResults(rows)
            return
        }
        searchStatusView?.text = "Searching…"
        val vertical = searchTab
        com.demo.glyf.store.SearchRecents.record(this, q, vertical)
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
            onCards = { answered, cards -> main.post {
                // A late reply from a tab the user already left must not
                // replace what they are looking at now.
                if (answered != searchTab) return@post
                searchStatusView?.text = if (cards.isEmpty()) "Nothing found" else ""
                if (cards.isNotEmpty()) showSearchResults(cards)
            } },
            onError = { message -> main.post { searchStatusView?.text = message } },
        )
    }

    /** Local contacts synced by the app — never leaves the device. */
    private fun contactMatches(q: String): List<BackendClient.SearchCard> {
        val file = com.demo.glyf.store.Bridge.file(this, "contacts.json")
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

    /** Suggestion rows above the keys. Capped at three so the keyboard keeps
     *  most of the screen and typing stays possible. */
    private fun showLandingRows(cards: List<BackendClient.SearchCard>) {
        dismissLanding()
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(2), dp(10), dp(2))
        }
        val theme = SearchCards.Theme(
            ink = ink(), card = card(),
            soft = Color.argb(170, 128, 128, 136), dp = ::dp)
        val backendURL = settings.optString("backendURL")
        for (c in cards.take(3)) {
            val v = SearchCards.view(this, c, theme, backendURL) { tapped -> insertResult(tapped) }
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.setMargins(0, 0, 0, dp(6))
            panel.addView(v, lp)
        }
        // Index 1 = directly under the search strip, above the key grid.
        root.addView(panel, 1)
        searchLanding = panel
    }

    private fun dismissLanding() {
        searchLanding?.let { root.removeView(it) }
        searchLanding = null
    }

    /** Results replace the keys (ABC returns), Gboard-style. */
    private fun showSearchResults(cards: List<BackendClient.SearchCard>) {
        dismissSearchResults()
        dismissLanding()
        val keysHeight = keyboard.height
        keyboard.visibility = View.GONE
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(4), dp(10), dp(10))
        }
        val abc = TextView(this).apply {
            text = "ABC"; textSize = 14f; setTextColor(ink())
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(6), dp(4), dp(6), dp(6))
            setOnClickListener { backToLanding() }
        }
        panel.addView(abc)
        val scroll = ScrollView(this).apply { isVerticalScrollBarEnabled = false }
        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val theme = SearchCards.Theme(
            ink = ink(), card = card(),
            soft = Color.argb(170, 128, 128, 136), dp = ::dp)
        val backendURL = settings.optString("backendURL")
        for (c in cards) {
            val v = SearchCards.view(this, c, theme, backendURL) { tapped -> insertResult(tapped) }
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.setMargins(0, 0, 0, dp(8))
            list.addView(v, lp)
        }
        scroll.addView(list)
        panel.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, keysHeight - dp(30)))
        root.addView(panel)
        searchResults = panel
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
        android.widget.Toast.makeText(
            this, "Inserted · copied", android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun dismissSearchResults() {
        searchResults?.let { root.removeView(it) }
        searchResults = null
        keyboard.visibility = View.VISIBLE
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
        searchStrip?.let { root.removeView(it) }
        searchStrip = null
        toolbar.visibility = View.VISIBLE
        syncAutoShift()
    }

    // MARK: key handling

    override fun onKey(id: String, char: String?) {
        if (searchActive) {
            typeIntoStrip(id, char, searchQuery, { searchQuery = it; renderQuery() }) {
                submitSearch()
            }
            return
        }
        if (barActive) {
            typeIntoStrip(id, char, barPrompt, { barPrompt = it; barPromptView?.text = it }) {
                runBarPrompt()
            }
            return
        }
        if (noteEditActive) {
            val update = { t: String -> noteEditText = t; noteEditView?.text = t }
            typeIntoStrip(id, char, noteEditText, update) { update(noteEditText + "\n") }
            return
        }
        val ic = currentInputConnection ?: return
        when {
            char != null -> {
                if (char.length == 1) {
                    val c = char[0]
                    if (c in WordContext.CORRECTION_BOUNDARIES) {
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
                if (autoShifted && keyboard.shifted) {
                    keyboard.shifted = false
                    autoShifted = false
                    keyboard.invalidate()
                }
                syncAutoShift()
                updateSuggestions()
            }
            id == "delete" -> {
                val corr = lastCorrection
                val before = ic.getTextBeforeCursor(64, 0)?.toString() ?: ""
                if (corr != null && before.endsWith(corr.replacement + " ")) {
                    // Backspace right after a correction puts back what was typed
                    // (and teaches the engine to leave that word alone).
                    ic.deleteSurroundingText(corr.replacement.length + 1, 0)
                    ic.commitText(corr.original, 1)
                    lastCorrection = null
                    if (corr.fromEngine) {
                        KeyboardTyping.engine?.revert(corr.original, corr.replacement)
                        KeyboardTyping.scheduleSave(this)
                    }
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
                val n = current.codePointCount(0, current.length)
                while (wordTouches.size > n) wordTouches.removeAt(wordTouches.size - 1)
                wordTouchesFor = current
                syncAutoShift()
                updateSuggestions()
            }
            id == "space" -> { handleSpace(ic); translateDraftChanged() }
            id == "return" -> {
                commitCurrentWord(ic)
                ic.commitText("\n", 1)
                syncAutoShift()
                updateSuggestions()
                translateDraftChanged()
            }
            id == "shift" -> {
                keyboard.shifted = !keyboard.shifted
                autoShifted = false
                keyboard.invalidate()
            }
            id == "emojikey" -> showEmojiPanel()
            id.startsWith("mode:") -> {
                keyboard.mode = when (id.removePrefix("mode:")) {
                    "123", "?123" -> Mode.SYMBOLS1
                    "#+=" -> Mode.SYMBOLS2
                    else -> Mode.LETTERS
                }
                keyboard.rebuild()
            }
        }
    }

    /** Keys typing into one of the keyboard's own strips (search query, bar
     *  instruction, note) instead of the host field. */
    private fun typeIntoStrip(id: String, char: String?, text: String,
                              update: (String) -> Unit, onReturn: () -> Unit) {
        when {
            char != null -> update(text + char)
            id == "space" -> update("$text ")
            id == "delete" -> update(text.dropLast(1))
            id == "return" -> onReturn()
            id == "shift" -> {
                keyboard.shifted = !keyboard.shifted
                keyboard.invalidate()
            }
            id.startsWith("mode:") -> {
                keyboard.mode = when (id.removePrefix("mode:")) {
                    "123", "?123" -> Mode.SYMBOLS1
                    "#+=" -> Mode.SYMBOLS2
                    else -> Mode.LETTERS
                }
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
        val stamp = com.demo.glyf.store.Bridge.file(this, SettingsStore.FILE).lastModified()
        if (stamp == settingsStamp) return
        settingsStamp = stamp
        settings = SettingsStore.load(this)
        keyboard.bindings = settings.optJSONObject("bindings")?.let { b ->
            b.keys().asSequence().associateWith { b.optString(it) }
        } ?: emptyMap()
        applyTourHint()
    }

    /** The tour's ring: a key, the strip chip, or the g pill. */
    private fun applyTourHint() {
        val hint = settings.optString("tourHint").takeIf { it.isNotBlank() }
        keyboard.tourKey = hint?.takeIf { it != "chip" && it != "g" }
        val ringColor = Color.rgb(0x7C, 0x5C, 0xFF)
        (stripChip?.background as? GradientDrawable)?.setStroke(
            if (hint == "chip") dp(2) else 0, ringColor)
        (gPill?.background as? GradientDrawable)?.setStroke(
            if (hint == "g") dp(2) else 0, ringColor)
    }

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int,
                                   newSelEnd: Int, candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd,
            candidatesStart, candidatesEnd)
        reloadSettingsIfChanged()
        selStart = newSelStart
        selEnd = newSelEnd
        // The cursor moved without a key (a tap in the field): suggest for
        // wherever it landed.
        if (glideCursor < 0 && !searchActive && !barActive && !noteEditActive) main.post { updateSuggestions() }
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
        if (searchActive || barActive || noteEditActive) return
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

    private data class BarInput(val text: String, val source: String,
                                val consumedBefore: Int, val consumedAfter: Int = 0)

    private var barActive = false
    private var barPrompt = ""
    private var barStrip: LinearLayout? = null
    private var barPromptView: TextView? = null
    private var barInput: BarInput? = null

    /** Same quick glyfs, same order, same titles as iOS GlyfCatalog. */
    /** The person's own glyfs, one tap each in the bar (as on iOS). */
    private fun myGlyfs(): List<Pair<String, String>> {
        val titles = settings.optJSONObject("customTitles") ?: return emptyList()
        return titles.keys().asSequence().map { it to titles.optString(it) }
            .sortedBy { it.second.lowercase() }.toList()
    }

    override fun onSpaceHoldOpenBar() {
        // A hold inside a strip, or in a password field, is just a space.
        if (searchActive || barActive || noteEditActive || isSecureField()) {
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
            return BarInput(before + after, "field", before.length, after.length)
        }
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val clip = cm.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
        if (!clip.isNullOrBlank()) return BarInput(clip, "clipboard", 0)
        return BarInput("", "empty", 0)
    }

    private fun showGlyfBar() {
        removeClipCard()
        dismissOverlay()
        val input = collectBarInput()
        barInput = input
        barActive = true
        barPrompt = ""
        toolbar.visibility = View.GONE
        val secondary = Color.argb(170, 128, 128, 136)

        val strip = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(4), dp(8), dp(6))
        }

        // What the bar will read, and close.
        val head = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        head.addView(TextView(this).apply {
            text = when (input.source) {
                "field" -> "FIELD TEXT"
                "clipboard" -> "CLIPBOARD"
                else -> "NO INPUT — prompt runs alone"
            }
            textSize = 10.5f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.04f
            setTextColor(secondary)
            setPadding(dp(9), dp(2), dp(9), dp(2))
            background = GradientDrawable().apply {
                cornerRadius = dp(9).toFloat(); setColor(card())
            }
        })
        head.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
        head.addView(TextView(this).apply {
            text = "✕"; textSize = 16f; setTextColor(ink())
            setPadding(dp(12), 0, dp(6), 0)
            contentDescription = "bar:close"
            setOnClickListener { exitBar() }
        })

        // The instruction the keys type into, and run.
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(5), 0, 0)
        }
        val prompt = TextView(this).apply {
            hint = "Tell Glyf what to do…"
            textSize = 15f
            maxLines = 2
            setTextColor(ink())
            setHintTextColor(Color.argb(120, 128, 128, 136))
            setPadding(dp(12), dp(7), dp(12), dp(7))
            contentDescription = "bar:prompt"
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat(); setColor(card())
            }
        }
        val run = TextView(this).apply {
            text = "↑"; textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(card())
            contentDescription = "bar:run"
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL; setColor(ink())
            }
            setOnClickListener { runBarPrompt() }
        }
        row.addView(prompt, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(run, LinearLayout.LayoutParams(dp(34), dp(34)).apply { leftMargin = dp(8) })

        // Quick glyfs.
        val chips = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for ((glyfId, title) in myGlyfs()) {
            chips.addView(TextView(this).apply {
                text = title; textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(ink())
                setPadding(dp(13), dp(6), dp(13), dp(6))
                contentDescription = "chip:$glyfId"
                background = GradientDrawable().apply {
                    cornerRadius = dp(15).toFloat(); setColor(card())
                    setStroke(1, Color.argb(if (chromeDark) 40 else 26, 128, 128, 136))
                }
                setOnClickListener { runFromBar(glyfId, emptyMap()) }
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT).apply { rightMargin = dp(6) })
        }
        val chipScroll = android.widget.HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setPadding(0, dp(7), 0, 0)
            addView(chips)
        }

        strip.addView(head)
        strip.addView(row)
        strip.addView(chipScroll)
        root.addView(strip, 0)
        barStrip = strip
        barPromptView = prompt
    }

    private fun runBarPrompt() {
        val p = barPrompt.trim()
        if (p.isEmpty()) return
        runFromBar("custom.prompt", mapOf("prompt" to p))
    }

    private fun runFromBar(glyfId: String, vars: Map<String, String>) {
        val input = barInput ?: return
        exitBar()
        showRunOverlay(glyfId, input.text, input.consumedBefore, input.consumedAfter, vars)
    }

    private fun exitBar() {
        barActive = false
        barPrompt = ""
        barStrip?.let { root.removeView(it) }
        barStrip = null
        barPromptView = null
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
    private fun refreshClipCard() {
        if (!::root.isInitialized || !::toolIcons.isInitialized) return
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val stamp = cm.primaryClipDescription?.timestamp ?: 0L
        val text = cm.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()?.trim().orEmpty()
        val busy = searchActive || barActive || noteEditActive || overlay != null ||
            featurePanel != null || isSecureField()
        val fresh = stamp > 0 && System.currentTimeMillis() - stamp < 10 * 60 * 1000 &&
            stamp != imePrefs.getLong("clipDone", -1)
        val typed = currentInputConnection?.getTextBeforeCursor(1, 0)?.isNotEmpty() == true
        if (busy || !fresh || text.isEmpty() || typed ||
            com.demo.glyf.store.SecretScanner.scan(text) != null) {
            if (stripChipKind == "paste") hideStripChip()
            return
        }
        showStripChip("paste", null, text.replace('\n', ' '), "Paste") {
            imePrefs.edit().putLong("clipDone", stamp).apply()
            currentInputConnection?.commitText(text, 1)
            hideStripChip()
        }
    }

    private fun removeClipCard() {
        if (stripChipKind == "paste") hideStripChip()
    }

    private var stripChip: View? = null
    private var stripChipKind: String? = null

    /** One chip across the strip: content on the left, the action on the right. */
    private fun showStripChip(kind: String, label: String?, value: String, verb: String,
                              onTap: () -> Unit) {
        hideStripChip()
        val chip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), 0, dp(14), 0)
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(card())
            }
            contentDescription = "strip:smart"
            setOnClickListener { onTap() }
        }
        if (label != null) chip.addView(TextView(this).apply {
            text = label
            textSize = 13f
            setTextColor(Color.argb(170, Color.red(ink()), Color.green(ink()), Color.blue(ink())))
            setPadding(0, 0, dp(8), 0)
        })
        chip.addView(TextView(this).apply {
            text = value
            textSize = 15f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(ink())
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        chip.addView(TextView(this).apply {
            text = verb
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.rgb(0x7C, 0x5C, 0xFF))
            setPadding(dp(10), 0, 0, 0)
        })
        toolbar.addView(chip, 1, LinearLayout.LayoutParams(0, dp(34), 1f).apply {
            leftMargin = dp(8)
        })
        stripChip = chip
        stripChipKind = kind
        applySuggestionVisibility()
        applyTourHint()
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
    /** What the run reads: the field text, or the clipboard for a skill. */
    private var actRunInput = ""
    private var actStreamView: TextView? = null

    private fun startAct(before: String, after: String) {
        actSkill = null
        actBefore = before
        actAfter = after
        actRunInput = (before + after).trim()
        runAct()
    }

    /** A bound letter held → its skill runs as a HUD: the skill's name over
     *  the letter's keycap, the answer streaming in, then ↻ Copy Insert. */
    private fun startSkill(letter: String, glyfId: String) {
        val ic = currentInputConnection
        val before = ic?.getTextBeforeCursor(2000, 0)?.toString() ?: ""
        val after = ic?.getTextAfterCursor(2000, 0)?.toString() ?: ""
        actSkill = glyfId to letter
        if ((before + after).isNotBlank()) {
            actBefore = before
            actAfter = after
            actRunInput = before + after
        } else {
            // Nothing typed: the skill reads the clipboard and Insert only adds.
            val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
            actBefore = ""
            actAfter = ""
            actRunInput = cm.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString() ?: ""
        }
        runAct()
    }

    /** Display names for bound glyfs — iOS GlyfCatalog's titles, then the
     *  names the app recorded for builder/hub glyfs, then a tidy id. */
    private fun skillTitle(glyfId: String): String {
        settings.optJSONObject("customTitles")?.optString(glyfId)?.takeIf { it.isNotBlank() }?.let { return it }
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
            val title = skillTitle(glyfId)
            buildActWorking(panel, actRunInput, title, letter)
            val vars = if (glyfId == "glyf.translate")
                mapOf("target" to settings.optString("translateTarget", "English")) else emptyMap()
            val streamed = StringBuilder()
            BackendClient.run(
                settings.optString("backendURL"), glyfId, actRunInput, vars,
                settings.optString("deviceId"), settings.optString("plan", "free"),
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
        val intent = actRunInput
        buildActWorking(panel, intent)
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
            onResult = { r -> main.post {
                if (generation == actGeneration && overlay === panel) showActResult(panel, r)
            } },
            onError = { message -> main.post {
                if (generation == actGeneration && overlay === panel) showActFailure(panel, message)
            } },
        )
    }

    /** One panel for the whole act, in place of the toolbar and keys. */
    private fun actPanel(): FrameLayout {
        removeClipCard()
        (overlay as? FrameLayout)?.takeIf { it.tag == "act" }?.let {
            it.removeAllViews()
            return it
        }
        dismissOverlay()
        // Results need room for a map and a card or two under it.
        actPanelHeight = keyboard.height + dp(44) + dp(140)
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
        panel.removeAllViews()
        panel.addView(ActRingsView(this, ink()), FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        if (title != null) {
            panel.addView(TextView(this).apply {
                text = title; textSize = 15f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setTextColor(ink())
                contentDescription = "act:skill"
            }, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP).apply { topMargin = dp(14) })
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
            textSize = 14f
            maxLines = 2
            gravity = Gravity.CENTER
            setTextColor(Color.argb(170, 128, 128, 136))
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

    private fun showActResult(panel: FrameLayout, r: BackendClient.ActResult) {
        actStreamView = null
        panel.removeAllViews()
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(2), dp(10), dp(10))
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(TextView(this).apply {
            text = "✕"; textSize = 16f; setTextColor(ink())
            setPadding(dp(6), 0, dp(12), 0)
            contentDescription = "act:close"
            setOnClickListener { actClose() }
        })
        header.addView(TextView(this).apply {
            text = r.title; textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(ink())
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        column.addView(header, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(40)))

        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        fun gap() = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { setMargins(0, 0, 0, dp(8)) }
        if (!r.text.isNullOrBlank()) {
            list.addView(TextView(this).apply {
                text = r.text
                textSize = 15.5f
                setTextColor(ink())
                setPadding(dp(12), dp(10), dp(12), dp(10))
                contentDescription = "act:text"
                background = GradientDrawable().apply {
                    cornerRadius = dp(15).toFloat(); setColor(card())
                }
            }, gap())
        }
        val theme = SearchCards.Theme(ink = ink(), card = card(),
            soft = Color.argb(170, 128, 128, 136), dp = ::dp)
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
                contentDescription = "act:map"
                setOnClickListener { actInsert(place.insertText(style)) }
            }
            list.addView(map, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(112)).apply { setMargins(0, 0, 0, dp(8)) })
            val w = resources.displayMetrics.widthPixels / 2
            SearchCards.loadThumb(
                "$backendURL/search/staticmap?lat=${place.lat}&lon=${place.lon}&w=$w&h=${dp(112) / 2}" +
                    (if (chromeDark) "&dark=1" else ""),
                map, onMiss = { map.visibility = View.GONE }, maxWidth = 1200)
        }
        for (c in r.cards) {
            // Tapping one card drops just that one — a single place from a list.
            list.addView(SearchCards.view(this, c, theme, backendURL) { tapped ->
                actInsert(if (tapped.kind == "query") tapped.url else tapped.insertText(style))
            }, gap())
        }
        column.addView(ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            addView(list)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), 0, 0)
        }
        actions.addView(pill("↻", primary = false, id = "act:retry") { runAct() },
            LinearLayout.LayoutParams(dp(44), dp(38)))
        actions.addView(pill("Copy", primary = false, id = "act:copy") { actCopy(r.insert) },
            LinearLayout.LayoutParams(0, dp(38), 0.38f).apply { leftMargin = dp(8) })
        actions.addView(pill("Insert ↑", primary = true, id = "act:insert") { actInsert(r.insert) },
            LinearLayout.LayoutParams(0, dp(38), 0.62f).apply { leftMargin = dp(8) })
        column.addView(actions)
        panel.addView(column, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    /** The skill's answer arriving token by token; actions come with the end. */
    private fun showActStreaming(panel: FrameLayout, title: String, text: String) {
        actStreamView?.let { it.text = text; return }
        panel.removeAllViews()
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(2), dp(10), dp(10))
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(TextView(this).apply {
            this.text = "✕"; textSize = 16f; setTextColor(ink())
            setPadding(dp(6), 0, dp(12), 0)
            contentDescription = "act:close"
            setOnClickListener { actClose() }
        })
        header.addView(TextView(this).apply {
            this.text = title; textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(ink())
        })
        column.addView(header, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(40)))
        val body = TextView(this).apply {
            this.text = text
            textSize = 15.5f
            setTextColor(ink())
            setPadding(dp(12), dp(10), dp(12), dp(10))
            contentDescription = "act:text"
            background = GradientDrawable().apply {
                cornerRadius = dp(15).toFloat(); setColor(card())
            }
        }
        column.addView(ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            addView(body)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        panel.addView(column, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        actStreamView = body
    }

    private fun showActFailure(panel: FrameLayout, message: String) {
        panel.removeAllViews()
        panel.addView(TextView(this).apply {
            text = message
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Color.argb(170, 128, 128, 136))
            setPadding(dp(24), 0, dp(24), 0)
            contentDescription = "act:status"
            setOnClickListener { runAct() }
        }, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        panel.addView(TextView(this).apply {
            text = "✕"; textSize = 16f; setTextColor(ink())
            setPadding(dp(14), dp(10), dp(14), dp(10))
            contentDescription = "act:close"
            setOnClickListener { actClose() }
        }, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.START))
    }

    /** Swaps exactly what the run read — both sides of the cursor. */
    private fun actInsert(text: String) {
        currentInputConnection?.let { ic ->
            ic.beginBatchEdit()
            ic.deleteSurroundingText(actBefore.length, actAfter.length)
            ic.commitText(text, 1)
            ic.endBatchEdit()
        }
        actClose()
    }

    private fun actCopy(text: String) {
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        cm.setPrimaryClip(android.content.ClipData.newPlainText("Glyf", text))
        android.widget.Toast.makeText(this, "Copied", android.widget.Toast.LENGTH_SHORT).show()
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

    private fun circleButton(label: String, id: String, onTap: () -> Unit) = TextView(this).apply {
        text = label; textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(ink())
        contentDescription = id
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(card())
            setStroke(1, Color.argb(if (chromeDark) 40 else 26, 128, 128, 136))
        }
        setOnClickListener { onTap() }
    }

    /** Black pill for the primary action, quiet hairline pills beside it. */
    private fun pill(label: String, primary: Boolean, id: String, onTap: () -> Unit) = TextView(this).apply {
        text = label; textSize = 15f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setTextColor(if (primary) card() else ink())
        contentDescription = id
        background = GradientDrawable().apply {
            cornerRadius = dp(19).toFloat()
            setColor(if (primary) ink() else card())
            if (!primary) setStroke(1, Color.argb(if (chromeDark) 40 else 26, 128, 128, 136))
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
                        ic.deleteSurroundingText(token.length, 0)
                        ic.commitText(s.optString("text") + " ", 1)
                        lastCorrection = Correction(token, s.optString("text"), fromEngine = false)
                        syncAutoShift()
                        updateSuggestions()
                        return
                    }
                }
            }
        }
        // Autocorrect + learning on commit (ime/typing) — the policy keeps
        // password and address fields untouched.
        commitCurrentWord(ic)
        ic.commitText(" ", 1)
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
        val head = before.substring(0, before.length - word.length)
        return engine.suggestions(word, if (wordTouchesFor == word) ArrayList(wordTouches) else null,
            WordContext.previousWord(before), WordContext.wantsCapital(head), policy)
    }

    private fun updateSuggestions() {
        if (searchActive || barActive || noteEditActive || overlay != null) { showSuggestions(emptyList()); return }
        val policy = typingPolicy()
        val ic = currentInputConnection
        if (ic == null || policy and TypingEngine.SUGGESTIONS == 0 || !settings.optBoolean("candidates", true)) {
            showSuggestions(emptyList()); return
        }
        val before = ic.getTextBeforeCursor(96, 0)?.toString() ?: ""
        val word = WordContext.currentWord(before)
        val engine = KeyboardTyping.engine
        // A form asking for something already in the vault: offer it, one tap
        // fills it. Android tells a keyboard what the field wants (hint,
        // autofill hints, input type), so this is exact here.
        if (before.isEmpty() && !isSecureField()) {
            val fill = Autofill.match(currentInputEditorInfo, VaultStore.load(this))
            if (fill != null) {
                // Same chip as iOS: the saved detail, Insert on the right.
                showStripChip("fill", null, fill, "Insert") {
                    currentInputConnection?.commitText(fill, 1)
                    hideStripChip()
                }
                return
            }
        }
        if (stripChipKind == "fill") hideStripChip()
        refreshClipCard()
        if (word.isEmpty()) {
            val corr = lastCorrection
            val previous = WordContext.previousWord(before)
            showSuggestions(when {
                corr != null -> listOf(Suggestion(corr.original, Suggestion.Kind.UNDO))
                engine != null && before.endsWith(" ") && previous != null ->
                    engine.predictions(previous, policy).map { Suggestion(it, Suggestion.Kind.WORD) }
                else -> emptyList()
            })
            return
        }
        lastCorrection = null
        val s = engineSuggestions(word, before, policy) ?: run { showSuggestions(emptyList()); return }
        val others = s.alternatives.map { Suggestion(it, Suggestion.Kind.WORD) }
        showSuggestions(when {
            s.autocorrect != null -> listOf(Suggestion(word, Suggestion.Kind.LITERAL),
                Suggestion(s.autocorrect, Suggestion.Kind.CORRECTION)) + others.take(1)
            others.isEmpty() -> emptyList()
            else -> listOf(Suggestion(word, if (s.known) Suggestion.Kind.WORD else Suggestion.Kind.LITERAL)) + others.take(2)
        })
    }

    private fun showSuggestions(items: List<Suggestion>) {
        if (!::suggestionRow.isInitialized) return
        val list = items.take(3)
        if (list == suggestionsShown) { applySuggestionVisibility(); return }
        suggestionsShown = list
        suggestionRow.removeAllViews()
        val ink = ink()
        for ((i, item) in list.withIndex()) {
            val tv = TextView(this).apply {
                text = when (item.kind) {
                    Suggestion.Kind.LITERAL -> "“${item.text}”"
                    Suggestion.Kind.UNDO -> "↩ ${item.text}"
                    else -> item.text
                }
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                textSize = 16f
                typeface = if (item.kind == Suggestion.Kind.CORRECTION) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                setTextColor(if (item.kind == Suggestion.Kind.LITERAL) Color.argb(150, Color.red(ink), Color.green(ink), Color.blue(ink)) else ink)
                if (item.kind == Suggestion.Kind.CORRECTION) {
                    background = GradientDrawable().apply {
                        cornerRadius = dp(8).toFloat()
                        setColor(Color.argb(if (chromeDark) 40 else 22, Color.red(ink), Color.green(ink), Color.blue(ink)))
                    }
                }
                contentDescription = "suggest:$i"
                setOnClickListener { suggestionTapped(item) }
            }
            suggestionRow.addView(tv, LinearLayout.LayoutParams(0, dp(32), 1f).apply { marginStart = dp(3); marginEnd = dp(3) })
        }
        if (list.isEmpty()) toolsPinned = false
        applySuggestionVisibility()
    }

    private fun applySuggestionVisibility() {
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
                if (before.endsWith(corr.replacement + " ")) {
                    ic.deleteSurroundingText(corr.replacement.length + 1, 0)
                    ic.commitText(corr.original + " ", 1)
                    if (corr.fromEngine) engine?.revert(corr.original, corr.replacement)
                }
                lastCorrection = null
            }
            Suggestion.Kind.LITERAL -> {
                // Exactly what they typed, on purpose: keep it and never fix it.
                engine?.keep(word)
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
            val engine = KeyboardTyping.engine ?: return
            val policy = typingPolicy()
            val previous = WordContext.previousWord(before)
            val head = before.substring(0, before.length - word.length)
            var kept = word
            if (policy and TypingEngine.AUTOCORRECT != 0) {
                val fix = engineSuggestions(word, before, policy)?.autocorrect
                if (fix != null && fix != word) {
                    ic.beginBatchEdit()
                    ic.deleteSurroundingText(word.length, 0)
                    ic.commitText(fix, 1)
                    if (selStart >= 0) {
                        ic.commitCorrection(android.view.inputmethod.CorrectionInfo(selStart - word.length, word, fix))
                    }
                    ic.endBatchEdit()
                    lastCorrection = Correction(word, fix, fromEngine = true)
                    kept = fix
                }
            }
            val autoCapitalized = WordContext.wantsCapital(head) && settings.optBoolean("autocapitalize", true)
            engine.commit(kept, previous, autoCapitalized, policy)
            KeyboardTyping.scheduleSave(this)
        } finally {
            wordTouches.clear()
            wordTouchesFor = ""
        }
    }

    /** Field-aware autocap, the Android way: getCursorCapsMode already
     *  honors the editor's cap flags — Apple-parity for free. */
    private fun syncAutoShift() {
        if (searchActive || barActive || noteEditActive) return
        if (!settings.optBoolean("autocapitalize", true)) return
        if (keyboard.mode != Mode.LETTERS) return
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

    // MARK: bound keys → run → preview (the §6.4 loop, Android slice)

    override fun onBoundKeyHeld(char: String, glyfId: String) {
        when (glyfId) {
            "surface:vault" -> { showVaultPanel(); return }
            "surface:translate-hud" -> { runTranslateOnField(); return }
            "surface:tones" -> { dismissFeaturePanel(); showGlyfBar(); return }
        }
        if (glyfId.startsWith("surface:") || glyfId.startsWith("connector:")) {
            openApp()
            return
        }
        if (isSecureField()) return // no AI in password fields
        startSkill(char, glyfId)
    }

    private fun showRunOverlay(glyfId: String, input: String, consumedBefore: Int,
                               consumedAfter: Int = 0,
                               extraVars: Map<String, String> = emptyMap()) {
        dismissOverlay()
        val dark = keyboard.isDark
        val card = if (dark) Color.rgb(44, 44, 46) else Color.WHITE
        val ink = if (dark) Color.WHITE else Color.rgb(18, 18, 20)

        val panel = FrameLayout(this).apply {
            setBackgroundColor(keyboard.backdrop())
        }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(16))
        }
        val status = TextView(this).apply {
            text = "Running…"
            setTextColor(if (dark) Color.LTGRAY else Color.DKGRAY)
            textSize = 12.5f
        }
        val result = TextView(this).apply {
            setTextColor(ink)
            textSize = 15f
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(card)
            }
        }
        val scroll = ScrollView(this).apply { addView(result) }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            visibility = View.GONE
        }

        fun action(label: String, primary: Boolean, onTap: () -> Unit) {
            val b = Button(this).apply {
                text = label
                isAllCaps = false
                textSize = 14f
                setTextColor(if (primary) card else ink)
                background = GradientDrawable().apply {
                    cornerRadius = dp(17).toFloat()
                    setColor(if (primary) ink else card)
                }
                setOnClickListener { onTap() }
            }
            val lp = LinearLayout.LayoutParams(0, dp(38), 1f)
            lp.setMargins(dp(4), dp(8), dp(4), 0)
            actions.addView(b, lp)
        }

        var finalText = ""
        action("Replace", true) {
            val ic = currentInputConnection ?: return@action
            // Swap exactly the text the run read — both sides of the cursor.
            // With the cursor glided mid-sentence, deleting only the before-
            // part left the old tail after the rewrite.
            ic.beginBatchEdit()
            ic.deleteSurroundingText(consumedBefore, consumedAfter)
            ic.commitText(finalText, 1)
            ic.endBatchEdit()
            dismissOverlay()
        }
        action("Insert", false) {
            currentInputConnection?.commitText(finalText, 1)
            dismissOverlay()
        }
        action("✕", false) { dismissOverlay() }

        column.addView(status)
        column.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        column.addView(actions)
        panel.addView(column)
        root.addView(panel, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, keyboard.height + dp(44)))
        keyboard.visibility = View.GONE
        toolbar.visibility = View.GONE
        overlay = panel

        val vars = (if (glyfId == "glyf.translate")
            mapOf("target" to settings.optString("translateTarget", "English"))
        else emptyMap()) + extraVars

        BackendClient.run(
            settings.optString("backendURL"),
            glyfId, input, vars,
            settings.optString("deviceId"),
            settings.optString("plan", "free"),
            onToken = { t -> main.post { result.text = "${result.text}$t" } },
            onDone = { text, remaining ->
                main.post {
                    android.util.Log.d("GlyfKB", "ui done attached=${result.isAttachedToWindow}")
                    finalText = text
                    result.text = text
                    status.text = remaining?.let { "$it runs left today" } ?: " "
                    actions.visibility = View.VISIBLE
                }
            },
            onError = { message -> main.post { status.text = message } },
        )
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
        featurePanel?.let { root.removeView(it) }
        featurePanel = null
        gPill?.text = "g"
        dropMarker?.let { if (::toolIcons.isInitialized) toolIcons.removeView(it) }
        dropMarker = null
        keyboard.visibility = View.VISIBLE
        // The clipboard panel takes the toolbar's space too; always give it back.
        if (::toolbar.isInitialized) toolbar.visibility = View.VISIBLE
    }

    /** Container that replaces the keys; header row = back + title. */
    /** @param bottomBar adds the ABC / backspace row the system emoji
     *  keyboard has at its foot — muscle memory, on both platforms. */
    private fun panelShell(title: String, bottomBar: Boolean = false):
            Pair<LinearLayout, LinearLayout> {
        dismissFeaturePanel()
        keyboard.visibility = View.GONE
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(2), dp(10), dp(8))
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(TextView(this).apply {
            text = "‹"; textSize = 22f; setTextColor(ink())
            setPadding(dp(8), 0, dp(14), dp(2))
            setOnClickListener { dismissFeaturePanel() }
        })
        header.addView(TextView(this).apply {
            text = title; textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(ink())
        })
        panel.addView(header, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(34)))
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val scroll = ScrollView(this).apply { addView(body) }
        val barH = if (bottomBar) dp(40) else 0
        panel.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, keyboard.height - dp(36) - barH))
        if (bottomBar) {
            val bar = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            bar.addView(TextView(this).apply {
                text = "ABC"; textSize = 15f; setTextColor(ink())
                setPadding(dp(6), dp(6), dp(14), dp(6))
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
        return panel to body
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

    /** The g menu: every tool in one scrolling grid (ToolMenuView), the twin
     *  of the iOS shell. The strip stays up so a tile can be dropped on it,
     *  and the g pill turns into the way out. */
    private fun showMenuGrid() {
        dismissFeaturePanel()
        if (toolbar.height == 0) return
        val panelH = keyboard.height
        keyboard.visibility = View.GONE
        toolsPinned = true
        applySuggestionVisibility()
        val menu = ToolMenuView(this, keyboard.palette(),
            onOpen = { id -> openTool(id) },
            onDragOverStrip = { rawX -> showStripDropMarker(rawX) },
            onPinToStrip = { id, rawX -> pinToStrip(id, rawX) },
        )
        root.addView(menu, root.indexOfChild(keyboard) + 1,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, panelH))
        featurePanel = menu
        gPill?.text = "✕"
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
        android.widget.Toast.makeText(this, "Added to the strip",
            android.widget.Toast.LENGTH_SHORT).show()
    }

    /** The glyfs this person built in the app; tap one to run it on what is
     *  typed, the same as holding its key. */
    private fun showMyGlyfsPanel() {
        val (_, body) = panelShell("My glyfs")
        val titles = settings.optJSONObject("customTitles")
        val bindings = settings.optJSONObject("bindings")
        val ids = titles?.keys()?.asSequence()?.toList()?.sortedBy { titles.optString(it).lowercase() }
            ?: emptyList()
        for (id in ids) {
            val key = bindings?.keys()?.asSequence()?.firstOrNull { bindings.optString(it) == id }
            cardRow(body, titles!!.optString(id), key?.let { "Hold ${it.uppercase()}" } ?: "") {
                dismissFeaturePanel()
                startSkill(key ?: "", id)
            }
        }
        cardRow(body, "＋ Build your own", "") { dismissFeaturePanel(); openAppPath("build") }
    }

    /** What each key holds. */
    private fun showKeysPanel() {
        val (_, body) = panelShell("Keys")
        val bindings = settings.optJSONObject("bindings") ?: return
        for (letter in "qwertyuiopasdfghjklzxcvbnm".map { it.toString() }) {
            val target = bindings.optString(letter).takeIf { it.isNotBlank() } ?: continue
            val title = when (target) {
                "surface:vault" -> "Vault"
                "surface:translate-hud" -> "Translate"
                "surface:tones" -> "Rewrite"
                else -> skillTitle(target)
            }
            cardRow(body, "Hold ${letter.uppercase()}", title) {}
        }
    }

    /** Vault = your info + your notes (notes editable right here). */
    private fun showVaultPanel() {
        val (_, body) = panelShell("Vault")
        val vault = VaultStore.load(this)
        val fields = vault.optJSONArray("fields")
        for (i in 0 until (fields?.length() ?: 0)) {
            val f = fields!!.getJSONObject(i)
            cardRow(body, f.optString("label"), f.optString("value")) {
                currentInputConnection?.commitText(f.optString("value"), 1)
                dismissFeaturePanel()
            }
        }
        val notes = com.demo.glyf.store.NotesStore.list(this)
        for (i in 0 until notes.length()) {
            val n = notes.getJSONObject(i)
            val text = n.optString("text")
            val id = n.optString("id")
            cardRow(body, text.lineSequence().first().take(44), "✎ tap title · edit") {
                currentInputConnection?.commitText(text, 1)
                dismissFeaturePanel()
            }
            // Replace the helper subline with a real edit affordance: long
            // press the card edits instead of inserting.
            (body.getChildAt(body.childCount - 1)).setOnLongClickListener {
                enterNoteEdit(id, text); true
            }
        }
        cardRow(body, "＋ New note", "") { enterNoteEdit(null, "") }
    }

    /** Gboard's clipboard, identical to the iOS panel: it takes the whole
     *  keyboard, toolbar included, the way Gboard's does. */
    private fun showClipboardPanel() {
        com.demo.glyf.store.ClipboardStore.captureNow(this)
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
                currentInputConnection?.commitText(text, 1)
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

    /** A screenshot goes in as an image where the field takes images (chat
     *  apps do), the way Gboard sends one; anywhere else it is copied so it
     *  can be pasted by hand. */
    private fun insertImage(uri: android.net.Uri) {
        val mimes = currentInputEditorInfo?.contentMimeTypes ?: emptyArray()
        val type = contentResolver.getType(uri) ?: "image/png"
        val accepts = mimes.any { android.content.ClipDescription.compareMimeTypes(type, it) }
        if (accepts) {
            val info = android.view.inputmethod.InputContentInfo(uri,
                android.content.ClipDescription("Screenshot", arrayOf(type)))
            val sent = currentInputConnection?.commitContent(info,
                android.view.inputmethod.InputConnection.INPUT_CONTENT_GRANT_READ_URI_PERMISSION,
                null) == true
            if (sent) return
        }
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        cm.setPrimaryClip(android.content.ClipData.newUri(contentResolver, "Screenshot", uri))
        android.widget.Toast.makeText(this, "Screenshot copied",
            android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun showShorthandPanel() {
        val (_, body) = panelShell("Shorthand")
        val snippets = VaultStore.load(this).optJSONArray("snippets")
        if (snippets == null || snippets.length() == 0) {
            cardRow(body, "No shorthand yet", "") { openApp() }
            return
        }
        for (i in 0 until snippets.length()) {
            val s = snippets.getJSONObject(i)
            cardRow(body, s.optString("trigger"), s.optString("text")) {
                currentInputConnection?.commitText(s.optString("text"), 1)
                dismissFeaturePanel()
            }
        }
    }

    // MARK: in-keyboard note editing (strip above the keys, like search)

    private var noteEditActive = false
    private var noteEditId: String? = null
    private var noteEditText = ""
    private var noteEditStrip: LinearLayout? = null
    private var noteEditView: TextView? = null

    private fun enterNoteEdit(id: String?, initial: String) {
        dismissFeaturePanel()
        if (searchActive) exitSearch()
        noteEditActive = true
        noteEditId = id
        noteEditText = initial
        toolbar.visibility = View.GONE
        val strip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
        }
        strip.addView(TextView(this).apply {
            text = "✕"; textSize = 16f; setTextColor(ink())
            setPadding(dp(6), 0, dp(10), 0)
            setOnClickListener { exitNoteEdit() }
        })
        val field = TextView(this).apply {
            hint = "Write a note…"
            text = noteEditText
            textSize = 15f
            maxLines = 2
            setTextColor(ink())
            setHintTextColor(Color.argb(120, 128, 128, 136))
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat(); setColor(card())
            }
        }
        strip.addView(field, LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        strip.addView(TextView(this).apply {
            text = "Save"; textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(card())
            setPadding(dp(16), dp(8), dp(16), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(15).toFloat(); setColor(ink())
            }
            setOnClickListener { saveNote() }
        })
        root.addView(strip, 0)
        noteEditStrip = strip
        noteEditView = field
    }

    private fun saveNote() {
        val err = com.demo.glyf.store.NotesStore.upsert(this, noteEditId, noteEditText)
        if (err != null) {
            android.widget.Toast.makeText(this, err, android.widget.Toast.LENGTH_SHORT).show()
            return
        }
        exitNoteEdit()
        showVaultPanel()
    }

    private fun exitNoteEdit() {
        noteEditActive = false
        noteEditStrip?.let { root.removeView(it) }
        noteEditStrip = null
        toolbar.visibility = View.VISIBLE
    }

    private val emojiCats = linkedMapOf(
        "😊" to "😀 😃 😄 😁 😆 😅 😂 🤣 😊 🙂 😉 😍 🥰 😘 😗 😙 😚 🤗 🤩 🥳 😎 🤓 😏 😌",
        "👋" to "👋 🤚 ✋ 🖐 👌 🤌 ✌️ 🤞 🤟 🤘 👍 👎 👊 ✊ 🤛 🤜 👏 🙌 👐 🤲 🙏 💪 🫶 🤝",
        "❤️" to "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ♥️ 💌 💋 😻 🫀",
        "🐶" to "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🦄 🐝 🦋 🐢 🐬 🐳",
        "🍕" to "🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🥭 🍍 🥥 🍅 🥑 🍕 🍔 🍟 🌮 🍣 🍜 🍩 ☕",
        "⚽" to "⚽ 🏀 🏈 ⚾ 🎾 🏐 🏉 🎱 🏓 🏸 🥊 ⛳ 🛹 🛼 🏄 🏊 🚴 🎮 🎲 🎯 �against 🎤 🎧 🎬",
    )

    private fun showEmojiPanel() {
        val (_, body) = panelShell("Emoji", bottomBar = true)
        for ((_, list) in emojiCats) {
            val emojis = list.split(" ").filter { it.isNotBlank() && !it.contains("against") }
            var i = 0
            while (i < emojis.size) {
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                }
                for (j in i until minOf(i + 8, emojis.size)) {
                    val e = emojis[j]
                    row.addView(TextView(this).apply {
                        text = e; textSize = 24f; gravity = Gravity.CENTER
                        setPadding(0, dp(5), 0, dp(5))
                        setOnClickListener {
                            currentInputConnection?.commitText(e, 1)
                        }
                    }, LinearLayout.LayoutParams(0,
                        LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                }
                body.addView(row)
                i += 8
            }
        }
    }

    /** Toolbar translate — same as iOS: runs glyf.translate on the field. */
    // MARK: Translate strip (iOS TranslationHUD twin)

    private var translateStrip: LinearLayout? = null
    private var translateDir: TextView? = null
    private var translateText: TextView? = null
    private var translateReplace: TextView? = null
    private var translateSource = ""
    private var translateResult = ""
    private var translateDetected: String? = null
    private var translateTarget: String? = null
    private var translateForced: String? = null
    private var translateConsumed = 0

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
        dismissFeaturePanel()
        val strip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(4), 0)
        }
        val dir = TextView(this).apply {
            text = "Translate"
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(ink())
            gravity = Gravity.CENTER
            setPadding(dp(12), 0, dp(12), 0)
            background = GradientDrawable().apply { cornerRadius = dp(15).toFloat(); setColor(card()) }
            setOnClickListener { cycleTranslateTarget() }
        }
        val text = TextView(this).apply {
            text = "…"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.START
            setTextColor(ink())
            setPadding(dp(10), 0, dp(8), 0)
        }
        val replace = TextView(this).apply {
            this.text = "Replace"
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(dp(14), 0, dp(14), 0)
            background = GradientDrawable().apply {
                cornerRadius = dp(15).toFloat(); setColor(Color.rgb(0x0A, 0x84, 0xFF))
            }
            alpha = 0.3f
            setOnClickListener { applyTranslation() }
        }
        val close = TextView(this).apply {
            this.text = "✕"
            textSize = 14f
            setTextColor(Color.argb(170, Color.red(ink()), Color.green(ink()), Color.blue(ink())))
            setPadding(dp(10), dp(8), dp(8), dp(8))
            setOnClickListener { exitTranslate() }
        }
        strip.addView(dir, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(30)))
        strip.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        strip.addView(replace, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(30)))
        strip.addView(close)
        toolbar.visibility = View.GONE
        root.addView(strip, root.indexOfChild(toolbar),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(47)))
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

    /** Called on word commits: translate what is typed so far. */
    private fun translateDraftChanged() {
        if (translateStrip == null) return
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(2000, 0)?.toString() ?: ""
        val text = before.takeLast(280).trim()
        translateConsumed = before.length
        if (text.isEmpty() || text == translateSource) return
        translateSource = text
        translateResult = ""
        translateText?.text = "…"
        translateReplace?.alpha = 0.3f
        val (primary, secondary) = translatePair()
        BackendClient.translate(settings.optString("backendURL"), settings.optString("deviceId"),
            text, primary, secondary, translateForced) { result ->
            main.post {
                if (result == null || translateSource != text || translateStrip == null) return@post
                translateDetected = result.detected
                translateTarget = result.target
                translateDir?.text = "${result.detected} → ${result.target}"
                translateText?.text = result.text
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
        ic.deleteSurroundingText(translateConsumed, 0)
        ic.commitText(translateResult, 1)
        translateSource = ""
        translateResult = ""
        translateText?.text = "…"
        translateReplace?.alpha = 0.3f
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
