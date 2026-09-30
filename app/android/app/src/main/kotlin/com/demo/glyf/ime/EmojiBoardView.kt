package com.demo.glyf.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Outline
import android.graphics.drawable.AnimatedImageDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.StaggeredGridLayoutManager
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * The emoji board, Android twin of the iOS EmojiBoard: Apple's emoji keyboard
 * layout (search field on top, the section's name, a grid that pages sideways,
 * ABC · categories · delete along the bottom) with Gboard's tabs as four glyphs
 * at the end of the search row: Emoji, Stickers, GIFs, Emoticons.
 *
 * GIFs and stickers are KLIPY's (called from the phone, as its terms ask) or
 * Noto's animated emoji (no key). Android can put an image straight into a
 * field that accepts one (`commitContent`), which the host does; elsewhere it
 * copies it, as iOS always must.
 */
@SuppressLint("ViewConstructor")
class EmojiBoardView(ctx: Context, private val host: Host) : LinearLayout(ctx) {

    interface Host {
        val backendURL: String
        val palette: GlyfKeyboardView.KeyPalette
        val dark: Boolean
        val online: Boolean
        /** Types text; `spaced` puts a space in front after a word. */
        fun commitText(text: String, spaced: Boolean)
        fun deleteBackward()
        fun backToLetters()
        /** The search field opened or closed: the letter keys show under
         *  the strip while it is open. */
        fun searchChanged(active: Boolean)
        /** Put a GIF or sticker in the field, or copy it; done(true) once sent. */
        fun sendMedia(item: MediaItem, kind: MediaKind, done: (Boolean) -> Unit)
    }

    enum class Mode(val id: String, val placeholder: String) {
        EMOJI("emoji", "Search Emoji"),
        STICKERS("stickers", "Search Stickers"),
        GIFS("gifs", "Search GIFs"),
        EMOTICONS("emoticons", "Search Emoticons");

        val kind: MediaKind?
            get() = when (this) { GIFS -> MediaKind.GIFS; STICKERS -> MediaKind.STICKERS; else -> null }
    }

    /** One entry on the bottom bar of a media or emoticon page. */
    private data class Chip(
        val id: String,
        val title: String? = null,
        val glyph: String? = null,
        val icon: String? = null,
        /** What it searches: "" trending, null the recents. */
        val query: String?,
        val label: String,
        val noto: Boolean = false,
    )

    private val main = Handler(Looper.getMainLooper())
    private fun dp(v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics)
    private fun dp(v: Int) = dp(v.toFloat()).toInt()

    var mode = Mode.EMOJI
        private set
    var searchActive = false
        private set
    private var query = ""
    private val selectedChip = mutableMapOf<Mode, String>()

    // Palette
    private val ink get() = host.palette.ink
    private val soft get() = host.palette.inkSoft
    private val sectionGrey get() = if (host.dark) Color.rgb(153, 153, 153) else Color.rgb(140, 143, 148)
    private val thumbColor get() = Color.argb(if (host.dark) 46 else 26, Color.red(ink), Color.green(ink), Color.blue(ink))
    private val fieldFill get() = if (host.dark) Color.argb(26, 255, 255, 255) else Color.argb(122, 255, 255, 255)

    // Views
    private val topRow = LinearLayout(ctx)
    private val abcStrip = TextView(ctx)
    private val field = LinearLayout(ctx)
    private val fieldIcon = ToolIcon(ctx, "search", 0)
    private val fieldText = TextView(ctx)
    private val caret = View(ctx)
    private val closeStrip = TextView(ctx)
    private val modeBar = LinearLayout(ctx)
    private val modeViews = mutableListOf<View>()
    private val labelRow = LinearLayout(ctx)
    private val sectionLabel = TextView(ctx)
    private val attribution = TextView(ctx)
    private val content = FrameLayout(ctx)
    private val emojiList = RecyclerView(ctx)
    private val mediaList = RecyclerView(ctx)
    private val emoticonList = RecyclerView(ctx)
    private val status = TextView(ctx)
    private val spinner = ProgressBar(ctx)
    private val suggestionScroll = HorizontalScrollView(ctx)
    private val suggestionRow = LinearLayout(ctx)
    private val bottomBar = LinearLayout(ctx)
    private val abc = TextView(ctx)
    private val tabsRow = LinearLayout(ctx)
    private val chipScroll = HorizontalScrollView(ctx)
    private val chipRow = LinearLayout(ctx)
    private val delete = ToolIcon(ctx, "delete", 0)
    private var tonePopup: View? = null

    // Emoji data
    private var sections: List<Pair<String, List<String>>> = emptyList()
    private var flat: List<String> = emptyList()
    private var sectionStarts: IntArray = IntArray(0)
    private var currentSection = 0
    private val tabViews = mutableListOf<View>()

    // Media state
    private var feedKey = ""
    private var feedTitle = ""
    private var feedSource = MediaSource.NOTO
    private var feedQuery: String? = null
    private var items: MutableList<MediaItem> = mutableListOf()
    private var next: String? = null
    private var loading = false
    private var sendingIndex = -1
    private var emoticons: List<String> = emptyList()

    init {
        orientation = VERTICAL
        setPadding(dp(8), dp(4), dp(8), 0)
        buildTop()
        buildLabel()
        buildContent()
        buildSuggestions()
        buildBottom()
        reloadSections()
        applyPalette()
        setMode(Mode.EMOJI)
    }

    // MARK: building

    /** Inter at iOS's weights: [bold] is semibold (the section labels,
     *  ":-)"), [weight] names another (the KLIPY credit's medium). */
    private fun styleText(v: TextView, size: Float, bold: Boolean = false, weight: Int? = null) {
        v.setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        v.typeface = Glass.font(context, weight ?: if (bold) Glass.SEMIBOLD else Glass.REGULAR)
        v.includeFontPadding = false
    }

    private fun tag(v: View, id: String) = v.setTag(com.demo.glyf.R.id.qa_id, id)

    private fun buildTop() {
        topRow.orientation = HORIZONTAL
        topRow.gravity = Gravity.CENTER_VERTICAL
        abcStrip.text = "ABC"
        styleText(abcStrip, 14f, bold = true)
        abcStrip.gravity = Gravity.CENTER_VERTICAL
        abcStrip.setPadding(dp(4), 0, dp(10), 0)
        abcStrip.setOnClickListener { exitSearch() }
        abcStrip.visibility = GONE   // only while the search strip is up
        tag(abcStrip, "emoji:abc")
        topRow.addView(abcStrip, LayoutParams(LayoutParams.WRAP_CONTENT, dp(36)).apply { gravity = Gravity.CENTER_VERTICAL })

        field.orientation = HORIZONTAL
        field.gravity = Gravity.CENTER_VERTICAL
        field.setPadding(dp(8), 0, dp(10), 0)
        field.addView(fieldIcon, LayoutParams(dp(24), dp(24)))
        styleText(fieldText, 17f)
        fieldText.maxLines = 1
        fieldText.ellipsize = TextUtils.TruncateAt.START
        fieldText.setPadding(dp(6), 0, 0, 0)
        field.addView(fieldText, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        caret.visibility = GONE
        field.addView(caret, LayoutParams(dp(2), dp(20)).apply { leftMargin = dp(1) })
        field.setOnClickListener { enterSearch() }
        tag(field, "emoji:search")
        topRow.addView(field, LayoutParams(0, dp(36), 1f))

        closeStrip.text = "✕"
        styleText(closeStrip, 15f)
        closeStrip.gravity = Gravity.CENTER
        closeStrip.setOnClickListener { exitSearch() }
        closeStrip.visibility = GONE
        tag(closeStrip, "emoji:close")
        topRow.addView(closeStrip, LayoutParams(dp(36), dp(36)))

        modeBar.orientation = HORIZONTAL
        modeBar.gravity = Gravity.CENTER_VERTICAL
        for (m in Mode.values()) {
            val v: View = when (m) {
                Mode.EMOJI -> ToolIcon(context, "emoji", 0)
                Mode.STICKERS -> ToolIcon(context, "sticker", 0)
                Mode.GIFS -> ToolIcon(context, "gif", 0)
                Mode.EMOTICONS -> TextView(context).apply {
                    this.text = ":-)"; styleText(this, 14f, bold = true); gravity = Gravity.CENTER
                }
            }
            v.contentDescription = when (m) {
                Mode.EMOJI -> "Emoji"; Mode.STICKERS -> "Stickers"; Mode.GIFS -> "GIFs"; Mode.EMOTICONS -> "Emoticons"
            }
            tag(v, "emoji:mode:${m.id}")
            v.setOnClickListener { setMode(m) }
            modeBar.addView(v, LayoutParams(dp(34), dp(34)).apply { leftMargin = dp(2) })
            modeViews.add(v)
        }
        topRow.addView(modeBar, LayoutParams(LayoutParams.WRAP_CONTENT, dp(36)).apply { leftMargin = dp(8) })
        addView(topRow, LayoutParams(LayoutParams.MATCH_PARENT, dp(44)))
    }

    private fun buildLabel() {
        labelRow.orientation = HORIZONTAL
        labelRow.gravity = Gravity.CENTER_VERTICAL
        styleText(sectionLabel, 12f, bold = true)
        sectionLabel.letterSpacing = 0.02f
        sectionLabel.maxLines = 1
        sectionLabel.ellipsize = TextUtils.TruncateAt.END
        tag(sectionLabel, "emoji:section")
        labelRow.addView(sectionLabel, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        styleText(attribution, 11f, weight = Glass.MEDIUM)
        attribution.maxLines = 1
        tag(attribution, "emoji:attribution")
        labelRow.addView(attribution, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        labelRow.setPadding(dp(6), 0, dp(6), 0)
        addView(labelRow, LayoutParams(LayoutParams.MATCH_PARENT, dp(20)))
    }

    private fun buildContent() {
        // Emoji: five rows, paging sideways, one section after another.
        emojiList.layoutManager = GridLayoutManager(context, 5, GridLayoutManager.HORIZONTAL, false)
        emojiList.adapter = EmojiAdapter()
        emojiList.overScrollMode = OVER_SCROLL_NEVER
        emojiList.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                dismissTones()
                if (searchActive) return
                val first = (rv.layoutManager as GridLayoutManager).findFirstVisibleItemPosition()
                if (first < 0) return
                val s = sectionStarts.indexOfLast { it <= first }.coerceAtLeast(0)
                if (s != currentSection) highlightTab(s)
            }
        })
        content.addView(emojiList, FrameLayout.LayoutParams(-1, -1))

        mediaList.layoutManager = StaggeredGridLayoutManager(2, StaggeredGridLayoutManager.VERTICAL)
        mediaList.adapter = MediaAdapter()
        mediaList.setPadding(0, dp(2), 0, dp(10))
        mediaList.clipToPadding = false
        mediaList.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                if (!rv.canScrollVertically(1)) loadMore()
            }
        })
        tag(mediaList, "emoji:media")
        content.addView(mediaList, FrameLayout.LayoutParams(-1, -1))

        emoticonList.layoutManager = GridLayoutManager(context, 3)
        emoticonList.adapter = EmoticonAdapter()
        tag(emoticonList, "emoji:emoticons")
        content.addView(emoticonList, FrameLayout.LayoutParams(-1, -1))

        styleText(status, 15f)
        status.gravity = Gravity.CENTER
        status.setPadding(dp(24), 0, dp(24), 0)
        status.visibility = GONE
        status.setOnClickListener { retry() }
        tag(status, "emoji:status")
        content.addView(status, FrameLayout.LayoutParams(-1, -1))
        spinner.visibility = GONE
        content.addView(spinner, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER))
        addView(content, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
    }

    private fun buildSuggestions() {
        suggestionRow.orientation = HORIZONTAL
        suggestionRow.gravity = Gravity.CENTER_VERTICAL
        suggestionScroll.isHorizontalScrollBarEnabled = false
        suggestionScroll.addView(suggestionRow, FrameLayout.LayoutParams(-2, -1))
        suggestionScroll.visibility = GONE
        tag(suggestionScroll, "emoji:suggestions")
        addView(suggestionScroll, LayoutParams(LayoutParams.MATCH_PARENT, dp(44)))
    }

    private fun buildBottom() {
        bottomBar.orientation = HORIZONTAL
        bottomBar.gravity = Gravity.CENTER_VERTICAL
        abc.text = "ABC"
        styleText(abc, 15f)
        abc.gravity = Gravity.CENTER
        abc.setOnClickListener { host.backToLetters() }
        tag(abc, "emoji:letters")
        bottomBar.addView(abc, LayoutParams(dp(48), dp(36)))

        tabsRow.orientation = HORIZONTAL
        tabsRow.gravity = Gravity.CENTER_VERTICAL
        val tabIcons = listOf("clock", "emoji", "bear", "food", "ball", "car", "bulb", "heart", "flag")
        tabIcons.forEachIndexed { i, icon ->
            val t = ToolIcon(context, icon, 0)
            t.contentDescription = if (i == 0) "Frequently used" else EmojiData.titles[EmojiData.categories[i - 1].first]
            tag(t, "emoji:tab:$i")
            t.setOnClickListener { jump(i) }
            tabsRow.addView(t, LayoutParams(0, dp(32), 1f))
            tabViews.add(t)
        }
        bottomBar.addView(tabsRow, LayoutParams(0, dp(36), 1f))

        chipRow.orientation = HORIZONTAL
        chipRow.gravity = Gravity.CENTER_VERTICAL
        chipScroll.isHorizontalScrollBarEnabled = false
        chipScroll.isHorizontalFadingEdgeEnabled = true
        chipScroll.setFadingEdgeLength(dp(12))
        chipScroll.addView(chipRow, FrameLayout.LayoutParams(-2, -1))
        tag(chipScroll, "emoji:chips")
        bottomBar.addView(chipScroll, LayoutParams(0, dp(36), 1f))

        delete.contentDescription = "Delete"
        delete.setOnClickListener { host.deleteBackward() }
        tag(delete, "emoji:delete")
        bottomBar.addView(delete, LayoutParams(dp(48), dp(36)))
        addView(bottomBar, LayoutParams(LayoutParams.MATCH_PARENT, dp(44)))
    }

    // MARK: palette

    /** Colours from the keyboard's palette; again when light and dark flip. */
    fun applyPalette() {
        abcStrip.setTextColor(ink)
        abc.setTextColor(ink)
        closeStrip.setTextColor(soft)
        field.background = GradientDrawable().apply { cornerRadius = dp(12f); setColor(fieldFill) }
        fieldIcon.setTint(soft)
        caret.setBackgroundColor(Color.rgb(124, 92, 255))
        renderField()
        sectionLabel.setTextColor(sectionGrey)
        attribution.setTextColor(sectionGrey)
        status.setTextColor(soft)
        delete.setTint(ink)
        highlightMode()
        highlightTab(currentSection)
        buildChips()
        emojiList.adapter?.notifyDataSetChanged()
        emoticonList.adapter?.notifyDataSetChanged()
    }

    private fun circle(size: Float = 30f) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL; setColor(thumbColor); setSize(dp(size.toInt()), dp(size.toInt()))
    }
    private fun capsule() = GradientDrawable().apply { cornerRadius = dp(15f); setColor(thumbColor) }

    private fun highlightMode() {
        modeViews.forEachIndexed { i, v ->
            val on = i == mode.ordinal
            // Selected, so TalkBack (and the scenarios) can tell which tab is on.
            v.isSelected = on
            v.background = if (on) circle(32f) else null
            when (v) {
                is ToolIcon -> v.setTint(if (on) ink else soft)
                is TextView -> v.setTextColor(if (on) ink else soft)
            }
        }
    }

    // MARK: modes

    fun setMode(m: Mode) {
        dismissTones()
        mode = m
        highlightMode()
        val emoji = m == Mode.EMOJI
        emojiList.visibility = if (emoji) VISIBLE else GONE
        tabsRow.visibility = if (emoji) VISIBLE else GONE
        chipScroll.visibility = if (emoji) GONE else VISIBLE
        mediaList.visibility = if (m.kind != null) VISIBLE else GONE
        emoticonList.visibility = if (m == Mode.EMOTICONS) VISIBLE else GONE
        setStatus(null)
        spinner.visibility = GONE
        attribution.text = ""
        renderField()
        when (m) {
            Mode.EMOJI -> { buildChips(); highlightTab(currentSection) }
            Mode.EMOTICONS -> {
                buildChips()
                selectChip(selectedChip[m] ?: if (TextRecents.load(context, RECENT_EMOTICONS).isEmpty()) "classic" else "recents")
            }
            Mode.GIFS, Mode.STICKERS -> {
                items.clear(); mediaList.adapter?.notifyDataSetChanged()
                spinner.visibility = VISIBLE
                MediaClient.loadConfig(host.backendURL) {
                    if (mode != m) return@loadConfig
                    spinner.visibility = GONE
                    renderField()
                    buildChips()
                    selectChip(selectedChip[m] ?: "trending")
                }
            }
        }
    }

    private val klipyOn get() = MediaClient.config?.klipy != null

    private val placeholder: String
        get() = if ((mode == Mode.GIFS || mode == Mode.STICKERS) && klipyOn) "Search KLIPY" else mode.placeholder

    private fun chips(): List<Chip> {
        val recents = Chip("recents", icon = "clock", query = null, label = "Recently used")
        return when (mode) {
            Mode.GIFS -> listOf(recents, Chip("trending", title = "Trending", query = "", label = "Trending")) +
                GIF_FEELINGS.map { Chip(it.second, title = it.first, query = it.second, label = it.first) }
            Mode.STICKERS -> {
                val list = mutableListOf(recents,
                    Chip("trending", icon = if (klipyOn) "flame" else "star", query = "",
                        label = if (klipyOn) "Trending" else "Popular"))
                list += STICKER_FEELINGS.map { Chip(it.second, glyph = it.first, query = it.second,
                    label = it.second.replaceFirstChar { c -> c.uppercase() }) }
                if (klipyOn) list += Chip("noto", icon = "emoji", query = "", label = "Animated emoji", noto = true)
                list
            }
            Mode.EMOTICONS -> listOf(recents) + EmoticonData.categories.map {
                Chip(it.first, title = it.second, query = it.first, label = it.second)
            }
            Mode.EMOJI -> emptyList()
        }
    }

    private fun buildChips() {
        chipRow.removeAllViews()
        for (chip in chips()) {
            val v: View = when {
                chip.icon != null -> ToolIcon(context, chip.icon, 0)
                chip.glyph != null -> TextView(context).apply {
                    this.text = chip.glyph; setTextSize(TypedValue.COMPLEX_UNIT_SP, 21f); gravity = Gravity.CENTER
                }
                else -> TextView(context).apply {
                    this.text = chip.title; styleText(this, 15f); gravity = Gravity.CENTER
                    setPadding(dp(10), 0, dp(10), 0)
                }
            }
            v.contentDescription = chip.label
            tag(v, "emoji:chip:${chip.id}")
            v.setOnClickListener { selectChip(chip.id) }
            val w = if (chip.title != null) LayoutParams.WRAP_CONTENT else dp(36)
            chipRow.addView(v, LayoutParams(w, dp(30)).apply { rightMargin = dp(2) })
        }
        placeChipThumb()
    }

    private fun placeChipThumb() {
        val list = chips()
        val chosen = list.indexOfFirst { it.id == selectedChip[mode] }
        for (i in 0 until chipRow.childCount) {
            val v = chipRow.getChildAt(i)
            val on = i == chosen
            v.background = when {
                !on -> null
                list[i].title != null -> capsule()
                else -> circle(30f)
            }
            when (v) {
                is ToolIcon -> v.setTint(if (on) ink else soft)
                is TextView -> v.setTextColor(if (on) ink else soft)
            }
            v.isSelected = on
        }
        if (chosen >= 0) chipRow.getChildAt(chosen)?.let { c ->
            chipScroll.post { chipScroll.smoothScrollTo(maxOf(0, c.left - dp(40)), 0) }
        }
    }

    private fun selectChip(id: String) {
        val chip = chips().firstOrNull { it.id == id } ?: return
        selectedChip[mode] = id
        placeChipThumb()
        when (mode) {
            Mode.EMOTICONS -> {
                emoticons = if (id == "recents") TextRecents.load(context, RECENT_EMOTICONS) else EmoticonData.items(id)
                sectionLabel.text = chip.label.uppercase()
                setStatus(if (emoticons.isEmpty()) "Emoticons you send show up here" else null)
                emoticonList.adapter?.notifyDataSetChanged()
                emoticonList.scrollToPosition(0)
            }
            Mode.GIFS, Mode.STICKERS -> {
                val source = sourceFor(chip)
                val title = when {
                    chip.query == null -> "RECENTLY USED"
                    chip.query.isEmpty() -> if (chip.noto) "ANIMATED EMOJI" else if (source == MediaSource.KLIPY) "TRENDING" else "POPULAR"
                    else -> chip.label.uppercase()
                }
                load(title, chip.id, chip.query, source)
            }
            Mode.EMOJI -> {}
        }
    }

    private fun sourceFor(chip: Chip?): MediaSource = when {
        mode == Mode.GIFS -> MediaSource.KLIPY
        chip?.noto == true -> MediaSource.NOTO
        klipyOn -> MediaSource.KLIPY
        else -> MediaSource.NOTO
    }

    // MARK: media feeds

    private fun setStatus(text: String?) {
        status.text = text ?: ""
        status.visibility = if (text == null || mode == Mode.EMOJI) GONE else VISIBLE
    }

    private fun load(title: String, key: String, q: String?, source: MediaSource) {
        val kind = mode.kind ?: return
        feedKey = key; feedTitle = title; feedSource = source; feedQuery = q
        items.clear(); next = null; loading = true; sendingIndex = -1
        sectionLabel.text = title
        attribution.text = ""
        (mediaList.layoutManager as StaggeredGridLayoutManager).spanCount = if (kind == MediaKind.STICKERS) 4 else 2
        mediaList.adapter?.notifyDataSetChanged()
        setStatus(null)
        if (q == null && source == MediaSource.NOTO) {
            loading = false
            items.addAll(MediaRecents.load(context, kind))
            setStatus(if (items.isEmpty()) "Stickers you send show up here" else null)
            mediaList.adapter?.notifyDataSetChanged()
            return
        }
        if (!host.online) {
            loading = false
            setStatus("Couldn't load. Check the connection and tap to try again")
            return
        }
        if (source == MediaSource.KLIPY && !klipyOn) {
            loading = false
            setStatus("GIFs aren't set up yet")
            return
        }
        spinner.visibility = VISIBLE
        MediaClient.page(context, host.backendURL, kind, source, q, null) { page ->
            if (feedKey != key || mode.kind != kind) return@page
            spinner.visibility = GONE
            loading = false
            if (page == null) {
                setStatus("Couldn't load. Check the connection and tap to try again")
                return@page
            }
            items.addAll(page.items)
            next = page.next
            attribution.text = page.attribution ?: ""
            val noun = if (kind == MediaKind.GIFS) "GIFs" else "stickers"
            setStatus(when {
                page.items.isNotEmpty() -> null
                q == null -> "${noun.replaceFirstChar { it.uppercase() }} you send show up here"
                q.isEmpty() -> "Nothing here right now"
                else -> "No $noun for “$q”"
            })
            mediaList.adapter?.notifyDataSetChanged()
            mediaList.scrollToPosition(0)
        }
    }

    private fun loadMore() {
        val kind = mode.kind ?: return
        val cursor = next ?: return
        if (loading) return
        if (feedQuery == null && feedSource == MediaSource.NOTO) return
        loading = true
        val key = feedKey
        MediaClient.page(context, host.backendURL, kind, feedSource, feedQuery, cursor) { page ->
            if (feedKey != key || mode.kind != kind) return@page
            loading = false
            page ?: return@page
            val known = items.map { it.id }.toSet()
            val fresh = page.items.filter { it.id !in known }
            next = if (fresh.isEmpty()) null else page.next
            if (fresh.isEmpty()) return@page
            val start = items.size
            items.addAll(fresh)
            mediaList.adapter?.notifyItemRangeInserted(start, fresh.size)
        }
    }

    private fun retry() {
        if (mode.kind == null || loading || feedKey.isEmpty()) return
        load(feedTitle, feedKey, feedQuery, feedSource)
    }

    private fun send(index: Int) {
        val kind = mode.kind ?: return
        if (sendingIndex >= 0 || index !in items.indices) return
        val item = items[index]
        sendingIndex = index
        mediaList.adapter?.notifyItemChanged(index)
        val q = feedQuery
        host.sendMedia(item, kind) { sent ->
            val at = sendingIndex
            sendingIndex = -1
            if (at in items.indices) mediaList.adapter?.notifyItemChanged(at)
            if (sent) {
                MediaRecents.push(context, item, kind)
                if (item.slug != null) MediaClient.reportShare(context, item, kind, q)
            }
        }
    }

    // MARK: emoji

    private fun reloadSections() {
        val recents = TextRecents.load(context, RECENT_EMOJI, DEFAULT_RECENTS)
        sections = listOf("recents" to recents) + EmojiData.categories
        // Every section starts a new column, as on Apple's board: its last
        // column is filled out with blanks, which also leaves Apple's gap
        // between sections. Otherwise a tab jump lands mid-column and the
        // name above the grid snaps back to the section before.
        val padded = sections.map { (_, list) -> list + List((ROWS - list.size % ROWS) % ROWS) { "" } }
        flat = padded.flatten()
        var at = 0
        sectionStarts = IntArray(sections.size) { i -> at.also { at += padded[i].size } }
        emojiList.adapter?.notifyDataSetChanged()
    }

    private fun jump(section: Int) {
        dismissTones()
        if (section !in sectionStarts.indices) return
        (emojiList.layoutManager as GridLayoutManager).scrollToPositionWithOffset(sectionStarts[section], 0)
        highlightTab(section)
    }

    private fun highlightTab(section: Int) {
        currentSection = section
        tabViews.forEachIndexed { i, v ->
            val on = i == section
            v.background = if (on) circle(30f) else null
            (v as? ToolIcon)?.setTint(if (on) ink else soft)
        }
        if (mode == Mode.EMOJI && !searchActive) {
            val id = sections.getOrNull(section)?.first
            sectionLabel.text = EmojiData.titles[id] ?: ""
        }
    }

    private fun pickEmoji(e: String) {
        dismissTones()
        TextRecents.push(context, RECENT_EMOJI, e)
        host.commitText(e, spaced = false)
    }

    private fun showTones(base: String, anchor: View) {
        val variants = EmojiData.variants(base)
        if (variants.size < 2) return
        dismissTones()
        val pop = LinearLayout(context).apply {
            orientation = HORIZONTAL
            elevation = dp(6f)
            background = GradientDrawable().apply { cornerRadius = dp(12f); setColor(host.palette.card) }
            setPadding(dp(4), dp(2), dp(4), dp(2))
        }
        for (v in variants) {
            pop.addView(TextView(context).apply {
                this.text = v; setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f); gravity = Gravity.CENTER
                setOnClickListener { pickEmoji(v) }
            }, LayoutParams(dp(40), dp(44)))
        }
        val w = dp(40) * variants.size + dp(8)
        val loc = IntArray(2); anchor.getLocationInWindow(loc)
        val mine = IntArray(2); content.getLocationInWindow(mine)
        val x = (loc[0] - mine[0] + anchor.width / 2 - w / 2).coerceIn(dp(4), content.width - w - dp(4))
        val y = (loc[1] - mine[1] - dp(50)).coerceAtLeast(0)
        content.addView(pop, FrameLayout.LayoutParams(w, dp(48)).apply { leftMargin = x; topMargin = y })
        tonePopup = pop
    }

    private fun dismissTones() {
        tonePopup?.let { content.removeView(it) }
        tonePopup = null
    }

    // MARK: search

    private fun renderField() {
        val empty = query.isEmpty()
        fieldText.text = if (empty) placeholder else query
        fieldText.setTextColor(if (empty) soft else ink)
        fieldText.contentDescription = placeholder
        caret.visibility = if (searchActive) VISIBLE else GONE
    }

    private fun enterSearch() {
        if (searchActive) return
        searchActive = true
        query = ""
        abcStrip.visibility = VISIBLE
        closeStrip.visibility = VISIBLE
        modeBar.visibility = GONE
        labelRow.visibility = GONE
        content.visibility = GONE
        bottomBar.visibility = GONE
        suggestionScroll.visibility = VISIBLE
        renderField()
        queryChanged()
        host.searchChanged(true)
    }

    fun exitSearch() {
        if (!searchActive) return
        searchActive = false
        query = ""
        abcStrip.visibility = GONE
        closeStrip.visibility = GONE
        modeBar.visibility = VISIBLE
        labelRow.visibility = VISIBLE
        content.visibility = VISIBLE
        bottomBar.visibility = VISIBLE
        suggestionScroll.visibility = GONE
        renderField()
        host.searchChanged(false)
    }

    /** A key while the strip is up (the host routes them here). */
    fun type(id: String, char: String?) {
        when {
            char != null -> { query += char; queryChanged() }
            id == "space" -> { query += " "; queryChanged() }
            id == "delete" -> { query = query.dropLast(1); queryChanged() }
            id == "return" -> returnPressed()
        }
        renderField()
    }

    private fun returnPressed() {
        val q = query.trim()
        if ((mode == Mode.GIFS || mode == Mode.STICKERS) && q.isNotEmpty()) runSearch(q) else exitSearch()
    }

    private fun runSearch(q: String) {
        exitSearch()
        selectedChip.remove(mode)
        placeChipThumb()
        load("“$q”".uppercase(), "q:${q.lowercase()}", q, sourceFor(null))
    }

    private var suggestSeq = 0

    private fun queryChanged() {
        renderField()
        val typed = query.trim()
        when (mode) {
            Mode.EMOJI -> showSuggestions(if (typed.isEmpty()) TextRecents.load(context, RECENT_EMOJI, DEFAULT_RECENTS)
                else EmojiData.search(typed), emoji = true)
            Mode.EMOTICONS -> {
                val hits = if (typed.isEmpty()) TextRecents.load(context, RECENT_EMOTICONS)
                    else EmoticonData.categories.filter { it.second.lowercase().startsWith(typed.lowercase()) }
                        .flatMap { it.third }
                showSuggestions(hits.take(24), emoticons = true)
            }
            Mode.GIFS, Mode.STICKERS -> {
                showSuggestions(if (typed.isEmpty()) emptyList() else listOf(typed))
                if (typed.isEmpty() || sourceFor(null) != MediaSource.KLIPY) return
                val seq = ++suggestSeq
                main.postDelayed({
                    if (seq != suggestSeq) return@postDelayed
                    MediaClient.suggest(typed) { terms ->
                        if (seq != suggestSeq || query.trim() != typed) return@suggest
                        showSuggestions((listOf(typed) + terms).distinctBy { it.lowercase() }.take(8))
                    }
                }, 250)
            }
        }
    }

    private fun showSuggestions(list: List<String>, emoji: Boolean = false, emoticons: Boolean = false) {
        suggestionRow.removeAllViews()
        list.forEachIndexed { i, s ->
            val v = TextView(context).apply {
                this.text = s
                gravity = Gravity.CENTER
                if (emoji) setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f) else {
                    styleText(this, 16f, bold = i == 0 && !emoticons)
                    setTextColor(ink)
                    setPadding(dp(13), 0, dp(13), 0)
                    background = GradientDrawable().apply { cornerRadius = dp(18f); setColor(host.palette.card) }
                }
                tag(this, "emoji:suggestion:$i")
                setOnClickListener {
                    when {
                        emoji -> pickEmoji(s)
                        emoticons -> typeEmoticon(s)
                        else -> runSearch(s)
                    }
                }
            }
            suggestionRow.addView(v, LayoutParams(if (emoji) dp(44) else LayoutParams.WRAP_CONTENT, dp(36))
                .apply { rightMargin = dp(6) })
        }
    }

    private fun typeEmoticon(t: String) {
        TextRecents.push(context, RECENT_EMOTICONS, t, keep = 24)
        host.commitText(t, spaced = true)
    }

    // MARK: adapters

    private inner class EmojiHolder(val tv: TextView) : RecyclerView.ViewHolder(tv)

    private inner class EmojiAdapter : RecyclerView.Adapter<EmojiHolder>() {
        override fun getItemCount() = flat.size
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): EmojiHolder {
            val tv = TextView(parent.context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
                gravity = Gravity.CENTER
                includeFontPadding = false
            }
            val rowH = maxOf(dp(36), parent.height / 5)
            tv.layoutParams = RecyclerView.LayoutParams(dp(47), rowH)
            return EmojiHolder(tv)
        }
        override fun onBindViewHolder(h: EmojiHolder, position: Int) {
            val e = flat[position]
            h.tv.text = e
            h.tv.contentDescription = e.ifEmpty { null }
            if (e.isEmpty()) {
                h.tv.setOnClickListener(null)
                h.tv.setOnLongClickListener(null)
                h.tv.isClickable = false
            } else {
                h.tv.setOnClickListener { pickEmoji(e) }
                h.tv.setOnLongClickListener { showTones(e, h.tv); true }
            }
            val rowH = maxOf(dp(36), emojiList.height / 5)
            if (h.tv.layoutParams.height != rowH) h.tv.layoutParams = RecyclerView.LayoutParams(dp(47), rowH)
        }
    }

    private inner class MediaHolder(val frame: FrameLayout, val image: ImageView, val busy: ProgressBar) :
        RecyclerView.ViewHolder(frame) { var url: String? = null }

    private inner class MediaAdapter : RecyclerView.Adapter<MediaHolder>() {
        override fun getItemCount() = items.size
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MediaHolder {
            val frame = FrameLayout(parent.context)
            val image = ImageView(parent.context)
            frame.addView(image, FrameLayout.LayoutParams(-1, -1))
            val busy = ProgressBar(parent.context).apply { visibility = GONE }
            frame.addView(busy, FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER))
            return MediaHolder(frame, image, busy)
        }
        override fun onBindViewHolder(h: MediaHolder, position: Int) {
            val item = items[position]
            val sticker = mode == Mode.STICKERS
            val spans = if (sticker) 4 else 2
            val gap = if (sticker) 0 else dp(6)
            val colW = ((mediaList.width - gap * (spans - 1)) / spans).coerceAtLeast(dp(40))
            val height = if (sticker) colW else (colW / item.aspect).toInt()
            h.frame.layoutParams = StaggeredGridLayoutManager.LayoutParams(-1, height).apply {
                setMargins(gap / 2, gap / 2, gap / 2, gap / 2)
            }
            val pad = if (sticker) dp(7) else 0
            h.image.setPadding(pad, pad, pad, pad)
            h.image.scaleType = if (sticker) ImageView.ScaleType.FIT_CENTER else ImageView.ScaleType.CENTER_CROP
            h.frame.background = if (sticker) null else GradientDrawable().apply {
                cornerRadius = dp(8f); setColor(Color.argb(170, Color.red(host.palette.card),
                    Color.green(host.palette.card), Color.blue(host.palette.card)))
            }
            h.frame.clipToOutline = !sticker
            h.frame.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, dp(8f))
                }
            }
            h.frame.contentDescription = item.title ?: if (sticker) "Sticker" else "GIF"
            tag(h.frame, "emoji:media:$position")
            h.frame.setOnClickListener { send(h.bindingAdapterPosition) }
            h.busy.visibility = if (position == sendingIndex) VISIBLE else GONE
            h.image.alpha = if (position == sendingIndex) 0.45f else 1f
            if (h.url == item.preview && h.image.drawable != null) return
            h.url = item.preview
            (h.image.drawable as? AnimatedImageDrawable)?.stop()
            h.image.setImageDrawable(null)
            val target = maxOf(colW, dp(60))
            MediaClient.previewData(item.preview) { bytes ->
                if (bytes == null || h.url != item.preview) return@previewData
                decodePool.execute {
                    val d = decode(bytes, target)
                    main.post {
                        if (h.url != item.preview || d == null) return@post
                        h.image.setImageDrawable(d)
                        if (d is AnimatedImageDrawable && animationsOn()) d.start()
                    }
                }
            }
        }
        override fun onViewRecycled(h: MediaHolder) {
            (h.image.drawable as? AnimatedImageDrawable)?.stop()
            h.image.setImageDrawable(null)
            h.url = null
        }
    }

    /** Small GIFs animate (AnimatedImageDrawable decodes one frame at a time);
     *  anything wider than 320px is decoded down to the tile's size. */
    private fun decode(bytes: ByteArray, target: Int): Drawable? = runCatching {
        ImageDecoder.decodeDrawable(ImageDecoder.createSource(ByteBuffer.wrap(bytes))) { decoder, info, _ ->
            val w = info.size.width
            if (w > 320) {
                val scale = target.toFloat() / w
                decoder.setTargetSize(maxOf(1, (w * scale).toInt()), maxOf(1, (info.size.height * scale).toInt()))
            }
        }
    }.getOrNull()

    private fun animationsOn() =
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f

    private inner class EmoticonHolder(val tv: TextView) : RecyclerView.ViewHolder(tv)

    private inner class EmoticonAdapter : RecyclerView.Adapter<EmoticonHolder>() {
        override fun getItemCount() = emoticons.size
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): EmoticonHolder {
            val tv = TextView(parent.context).apply {
                styleText(this, 17f)
                gravity = Gravity.CENTER
                maxLines = 1
                setAutoSizeTextTypeUniformWithConfiguration(10, 17, 1, TypedValue.COMPLEX_UNIT_SP)
                layoutParams = RecyclerView.LayoutParams(-1, dp(46))
            }
            return EmoticonHolder(tv)
        }
        override fun onBindViewHolder(h: EmoticonHolder, position: Int) {
            val t = emoticons[position]
            h.tv.text = t
            h.tv.setTextColor(ink)
            h.tv.contentDescription = t
            tag(h.tv, "emoji:emoticon:$position")
            h.tv.setOnClickListener { typeEmoticon(t) }
        }
    }

    companion object {
        /** Two decoders for every board the keyboard ever opens: a pool per
         *  board was never shut down, so each emoji tap-in left two threads. */
        private val decodePool = Executors.newFixedThreadPool(2) { r ->
            Thread(r, "glyf-emoji-decode").apply { isDaemon = true }
        }
        const val ROWS = 5
        const val RECENT_EMOJI = "emoji-recents.json"
        const val RECENT_EMOTICONS = "emoticon-recents.json"
        val DEFAULT_RECENTS = listOf("😂", "❤️", "👍", "🙏", "😊", "🔥", "🎉", "😍")
        val GIF_FEELINGS = listOf(
            "Haha" to "haha", "Love" to "love", "Sad" to "sad", "Yes" to "yes", "No" to "no",
            "Wow" to "wow", "OMG" to "omg", "Thanks" to "thank you", "Hi" to "hello", "Bye" to "bye",
            "Miss you" to "miss you", "Hug" to "hug", "Party" to "party", "Dance" to "dance",
            "Congrats" to "congratulations", "Birthday" to "happy birthday", "Good night" to "good night",
            "Facepalm" to "facepalm", "Sleepy" to "sleepy", "Hungry" to "hungry", "Awkward" to "awkward",
        )
        val STICKER_FEELINGS = listOf(
            "😂" to "laughing", "❤️" to "love", "👍" to "thumbs up", "😢" to "sad", "😡" to "angry",
            "🎉" to "party", "🙏" to "thank you", "👋" to "hello", "😴" to "sleepy", "😮" to "wow",
            "🐶" to "dog", "🐱" to "cat", "🍕" to "food", "🎂" to "birthday",
        )
    }
}
