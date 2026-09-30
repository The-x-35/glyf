package com.demo.glyf.ime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.demo.glyf.store.ClipboardStore

/**
 * The clipboard, Gboard's way, drawn as the iPhone draws it (ClipboardPanel.
 * swift, the reference: Arpit, 2026-09-30, "similar in everything as a brand
 * identity"): a header with back and edit in round keys, a row of kinds
 * (All · Text · Link · Image), then PINNED and RECENT as two columns of
 * cards sized to their text. Tap to paste; hold one and the rest dim while
 * a menu offers Paste, Save to vault, Pin and Delete.
 */
class ClipboardPanelView(
    context: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    private val onClose: () -> Unit,
    private val onPaste: (String) -> Unit,
    /** A screenshot tapped: put the image where the field takes images. */
    private val onImage: (android.net.Uri) -> Unit = {},
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = Math.round(v * density)
    private fun dpf(v: Float) = v * density

    // iOS's measures (ClipboardPanel.M).
    private val headerH = 52f
    private val filterH = 34f
    private val side = 12f
    private val gap = 10f
    private val cardPad = 14f
    private val radius = 12f
    private val sectionH = 30f
    private val clipTextSize = 15f
    private val clipMaxLines = 4

    /** What the list shows. All, Text, Link and Image are parallel kinds, so
     *  they are a row of pills; pinned is a priority, not a kind, so it stays
     *  a section at the top of whichever is picked. */
    private enum class Filter(val title: String, val glyph: String) {
        ALL("All", "lines"), TEXT("Text", "textformat"), LINK("Link", "link"), IMAGE("Image", "photo");

        fun accepts(text: String) = when (this) {
            ALL -> true
            IMAGE -> false
            LINK -> isLink(text)
            TEXT -> !isLink(text)
        }
        val showsShots get() = this == ALL || this == IMAGE
        val showsClips get() = this != IMAGE
    }

    private var filter = Filter.ALL
    private val pills = HashMap<Filter, TextView>()

    private val body = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, dp(4f), 0, dp(12f))
    }
    private val scroll = ScrollView(context).apply {
        isVerticalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        addView(body)
    }
    private val scrim = View(context).apply {
        setBackgroundColor(Glass.scrim)
        visibility = GONE
        setOnClickListener { dismissMenu() }
    }
    private var menu: View? = null
    private var lifted: View? = null
    private var editing = false
    private lateinit var editButton: FrameLayout
    private lateinit var editIcon: ToolIcon

    /** Recent screenshots, asked of MediaStore off the main thread (see
     *  loadShots). Declared before init: init's reload() reads it. */
    private var shotList: List<com.demo.glyf.ScreenshotAccess.Shot> = emptyList()

    init {
        setBackgroundColor(palette.board)
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        column.addView(header(), LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(headerH)))
        column.addView(filterRow(), LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(filterH)))
        column.addView(scroll, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(column, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(scrim, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        reload()
        loadShots()
    }

    /** Screenshots come from MediaStore off the main thread: while it indexes
     *  one that was just taken it can take seconds to answer, and a keyboard
     *  that waits on it stops taking touches (an ANR). The copies show at
     *  once; screenshots join them when the answer comes. */
    private fun loadShots() {
        if (!screenshotsOn()) return
        val app = context.applicationContext
        Thread {
            val found = com.demo.glyf.ScreenshotAccess.recent(app)
            post {
                if (found.map { it.uri } != shotList.map { it.uri }) {
                    shotList = found
                    reload()
                }
            }
        }.start()
    }

    private fun screenshotsOn(): Boolean =
        com.demo.glyf.store.SettingsStore.load(context).optBoolean("clipboardScreenshots", true)

    // ---- header ------------------------------------------------------------

    /** A round key of the key colour holding a glyph (iOS's 38pt buttons). */
    private fun roundKey(glyph: String, weight: Float, size: Float, qaId: String, desc: String,
                         onTap: () -> Unit): Pair<FrameLayout, ToolIcon> {
        val icon = ToolIcon(context, glyph, Glass.textPrimary).apply {
            solid = true
            this.weight = weight
            scale = size
        }
        val key = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Glass.surfaceCard)
            }
            setTag(com.demo.glyf.R.id.qa_id, qaId)
            contentDescription = desc
            setOnClickListener { onTap() }
            addView(icon, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        }
        return key to icon
    }

    private fun header(): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(side), 0, dp(side), 0)
        }
        row.addView(roundKey("back", 1.9f, 1.15f, "clip:back", "Close") { onClose() }.first,
            LinearLayout.LayoutParams(dp(38f), dp(38f)))
        row.addView(TextView(context).apply {
            text = "Clipboard"
            Glass.style(this, 22f, Glass.MEDIUM)
            maxLines = 1
        }, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply { leftMargin = dp(14f) })
        val (key, icon) = roundKey("edit", 1.8f, 1.05f, "clip:edit", "Edit") { toggleEditing() }
        editButton = key
        editIcon = icon
        key.visibility = if (historyOn()) VISIBLE else INVISIBLE
        row.addView(key, LinearLayout.LayoutParams(dp(38f), dp(38f)))
        return row
    }

    private fun toggleEditing() {
        editing = !editing
        (editButton.background as GradientDrawable).setColor(if (editing) Glass.accentPrimary else Glass.surfaceCard)
        editIcon.setTint(if (editing) Color.WHITE else Glass.textPrimary)
        editIcon.solid = true
        reload()
    }

    /** All · Text · Link · Image: 26dp pills, the chosen one in ink. */
    private fun filterRow(): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(side), 0, 0, 0)
        }
        for ((i, kind) in Filter.values().withIndex()) {
            val pill = TextView(context).apply {
                text = kind.title
                Glass.style(this, 13.5f, Glass.MEDIUM)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
                // The icon 11 in, the words 6 after it, 21 after them.
                compoundDrawablePadding = dp(6f)
                setPadding(dp(11f), 0, dp(21f), 0)
                setTag(com.demo.glyf.R.id.qa_id, "clip:filter:${kind.title.lowercase()}")
                contentDescription = kind.title
                setOnClickListener { select(kind) }
            }
            pills[kind] = pill
            row.addView(pill, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, dp(filterH - 8f))
                .apply { if (i > 0) leftMargin = dp(7f) })
        }
        paintPills()
        return row
    }

    private fun select(kind: Filter) {
        if (filter == kind) return
        filter = kind
        paintPills()
        reload()
    }

    private fun paintPills() {
        for ((kind, pill) in pills) {
            val on = kind == filter
            // The chosen one in ink with white words; in dark, white with
            // ink words (iOS's fix: an ink pill vanished on the dark sheet).
            val onFill = if (Glass.dark) Color.WHITE else Glass.brandInk
            val onInk = if (Glass.dark) Glass.brandInk else Color.WHITE
            val ink = if (on) onInk else Glass.textPrimary
            pill.background = Glass.pill(if (on) onFill else Glass.surfaceCard)
            pill.setTextColor(ink)
            pill.isSelected = on
            pill.setCompoundDrawablesRelativeWithIntrinsicBounds(
                ToolIcon(context, kind.glyph, ink).apply {
                    solid = true; weight = 1.9f; scale = if (kind == Filter.TEXT) 0.8f else 0.7f
                }.asDrawable(dp(16f)), null, null, null)
        }
    }

    /** On unless turned off in the app (Keyboard, Keep what you copy). */
    private fun historyOn(): Boolean =
        com.demo.glyf.store.SettingsStore.load(context).optBoolean("clipboardHistory", true)

    // ---- cards -------------------------------------------------------------

    fun reload() {
        body.removeAllViews()
        if (!historyOn()) {
            addTip("clipboard", "Clipboard history is off in the Glyf app.")
            return
        }
        val items = ClipboardStore.load(context)
        // Pinned leads, within the kind being shown.
        val clips = if (filter.showsClips) items.filter { filter.accepts(it.text) } else emptyList()
        val shots = if (filter.showsShots) shots() else emptyList()
        val pinned = clips.filter { it.pinned }
        // Recent copies and recent screenshots share one timeline, newest first.
        val recent = (clips.filter { !it.pinned }.map { Entry.Text(it) as Entry } + shots)
            .sortedByDescending { it.ts }
        if (pinned.isNotEmpty()) { addSection("PINNED"); addGrid(pinned.map { Entry.Text(it) }) }
        if (recent.isNotEmpty()) { addSection("RECENT"); addGrid(recent) }
        if (clips.isEmpty() && shots.isEmpty()) {
            addTip(if (filter == Filter.ALL) "clipboard" else filter.glyph,
                if (filter == Filter.ALL) "Nothing copied yet" else "No ${filter.title.lowercase()} copied yet")
        }
    }

    private sealed class Entry(val ts: Long) {
        class Text(val item: ClipboardStore.Item) : Entry(item.ts)
        class Image(val shot: com.demo.glyf.ScreenshotAccess.Shot) : Entry(shot.takenMs)
    }

    private val prefs get() = context.getSharedPreferences("glyf_clip", Context.MODE_PRIVATE)

    /** Screenshots from the last two days, when turned on in the app, minus
     *  the ones removed from the clipboard here. */
    private fun shots(): List<Entry> {
        if (!screenshotsOn()) return emptyList()
        val removed = prefs.getStringSet("removedShots", emptySet()) ?: emptySet()
        return shotList
            .filter { it.uri.toString() !in removed }
            .map { Entry.Image(it) }
    }

    private fun removeShot(uri: android.net.Uri) {
        val removed = (prefs.getStringSet("removedShots", emptySet()) ?: emptySet()).toMutableSet()
        removed.add(uri.toString())
        prefs.edit().putStringSet("removedShots", removed).apply()
    }

    /** PINNED, RECENT: small spaced capitals in the quiet grey. */
    private fun addSection(title: String) {
        body.addView(TextView(context).apply {
            text = title
            Glass.style(this, 12.5f, Glass.MEDIUM, Glass.textSecondary)
            letterSpacing = 0.048f
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(side + 4f), 0, 0, 0)
        }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(sectionH)))
    }

    /** A card with an accent badge over its words (iOS addTip). */
    private fun addTip(glyph: String, text: String) {
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(cardPad), dp(cardPad), dp(cardPad), dp(cardPad))
            background = Glass.card(context, radius = radius)
        }
        card.addView(FrameLayout(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Glass.withAlpha(Glass.accentPrimary, 0.14f))
            }
            addView(ToolIcon(context, glyph, Glass.accentPrimary).apply { solid = true; scale = 0.8f; weight = 1.9f },
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        }, LinearLayout.LayoutParams(dp(28f), dp(28f)))
        card.addView(TextView(context).apply {
            this.text = text
            Glass.style(this, clipTextSize)
        }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(10f)
        })
        body.addView(card, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            setMargins(dp(side), 0, dp(side), dp(gap))
        })
    }

    /** Two columns, each card as tall as it needs (Gboard's masonry): every
     *  card lands in whichever column is shorter, in the order given. */
    private fun addGrid(items: List<Entry>) {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        val cols = List(2) { LinearLayout(context).apply { orientation = LinearLayout.VERTICAL } }
        val heights = FloatArray(2)
        val screenW = resources.displayMetrics.widthPixels
        val colW = (screenW - dp(side) * 2 - dp(gap)) / 2f
        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            typeface = Glass.font(context)
            textSize = dpf(clipTextSize)
        }
        for (entry in items) {
            val c = if (heights[0] <= heights[1]) 0 else 1
            when (entry) {
                is Entry.Text -> {
                    val flat = entry.item.text.trim()
                    val textW = (colW - dp(cardPad) * 2).toInt().coerceAtLeast(1)
                    val layout = StaticLayout.Builder.obtain(flat, 0, flat.length, paint, textW)
                        .setAlignment(Layout.Alignment.ALIGN_NORMAL).setMaxLines(clipMaxLines)
                        .setIncludePad(false)
                        .setEllipsize(TextUtils.TruncateAt.END).build()
                    heights[c] += layout.height + dp(cardPad) * 2f + dp(gap)
                    cols[c].addView(card(entry.item, flat), LinearLayout.LayoutParams(
                        LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                        bottomMargin = dp(gap)
                    })
                }
                is Entry.Image -> {
                    // Screenshots are tall; the card shows the top of one.
                    val h = (colW * 1.25f).toInt()
                    heights[c] += h + dp(gap)
                    cols[c].addView(imageCard(entry.shot.uri, colW.toInt(), h),
                        LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, h).apply {
                            bottomMargin = dp(gap)
                        })
                }
            }
        }
        row.addView(cols[0], LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            leftMargin = dp(side); rightMargin = dp(gap / 2)
        })
        row.addView(cols[1], LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            leftMargin = dp(gap / 2); rightMargin = dp(side)
        })
        body.addView(row)
    }

    /** iOS's minus.circle.fill: red, over a card's top corner while editing. */
    private fun minusBadge(onTap: () -> Unit): View = object : View(context) {
        private val disc = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Glass.accentDanger
        }
        private val bar = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeWidth = dpf(2.2f)
            strokeCap = android.graphics.Paint.Cap.ROUND
        }
        override fun onDraw(c: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            c.drawCircle(cx, cy, dpf(10.5f), disc)
            c.drawLine(cx - dpf(5f), cy, cx + dpf(5f), cy, bar)
        }
    }.apply {
        contentDescription = "Delete"
        setTag(com.demo.glyf.R.id.qa_id, "clip:delete")
        setOnClickListener { onTap() }
    }

    private fun imageCard(uri: android.net.Uri, w: Int, h: Int): View {
        val image = ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = Glass.card(context, radius = radius)
            clipToOutline = true
            // "Screenshot" is also its name to the scenarios (S98).
            contentDescription = "Screenshot"
            setOnClickListener { if (!editing) onImage(uri) }
            setOnLongClickListener { if (!editing) showImageMenu(uri, this); true }
        }
        // Thumbnails off the main thread; the card is already in place.
        Thread {
            val bmp = runCatching {
                context.contentResolver.loadThumbnail(uri, android.util.Size(w, h), null)
            }.getOrNull()
            if (bmp != null) image.post { image.setImageBitmap(bmp) }
        }.start()
        if (!editing) return image
        val frame = FrameLayout(context).apply { clipChildren = false; clipToPadding = false }
        frame.addView(image, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        frame.addView(minusBadge { removeShot(uri); reload() }, LayoutParams(dp(36f), dp(36f), Gravity.TOP or Gravity.END)
            .apply { topMargin = -dp(6f); rightMargin = -dp(6f) })
        return frame
    }

    private fun card(item: ClipboardStore.Item, flat: String): View {
        val card = FrameLayout(context).apply {
            background = Glass.card(context, radius = radius)
            setTag(com.demo.glyf.R.id.qa_id, "clip:card")
            contentDescription = flat
            clipChildren = false
            clipToPadding = false
            setOnClickListener { if (!editing) onPaste(item.text) }
            setOnLongClickListener { if (!editing) showMenu(item, this); true }
        }
        card.addView(TextView(context).apply {
            text = flat
            Glass.style(this, clipTextSize)
            maxLines = clipMaxLines
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(cardPad), dp(cardPad), dp(cardPad), dp(cardPad))
        })
        if (editing) {
            card.addView(minusBadge { ClipboardStore.remove(context, item.text); reload() },
                LayoutParams(dp(36f), dp(36f), Gravity.TOP or Gravity.END).apply {
                    topMargin = -dp(6f); rightMargin = -dp(6f)
                })
        }
        return card
    }

    // ---- hold menu ---------------------------------------------------------

    private fun showMenu(item: ClipboardStore.Item, anchor: View) {
        popMenu(anchor, listOf(
            Triple("clipboard", "Paste") { dismissMenu(); onPaste(item.text) },
            Triple("vault", "Save to vault") {
                val refusal = com.demo.glyf.store.NotesStore.upsert(context, null, item.text)
                dismissMenu()
                (context as? GlyfIME)?.notice(refusal ?: "Saved to vault")
            },
            Triple(if (item.pinned) "pinslash" else "pin", if (item.pinned) "Unpin" else "Pin") {
                ClipboardStore.togglePin(context, item.text); dismissMenu(); reload()
            },
            Triple("trash", "Delete") {
                ClipboardStore.remove(context, item.text); dismissMenu(); reload()
            },
        ))
    }

    private fun showImageMenu(uri: android.net.Uri, anchor: View) {
        popMenu(anchor, listOf(
            Triple("clipboard", "Paste") { dismissMenu(); onImage(uri) },
            // Removes it from the clipboard; the screenshot stays in Photos.
            Triple("trash", "Delete") { removeShot(uri); dismissMenu(); reload() },
        ))
    }

    /** The rest dims; the held card stays bright where it was, and the menu
     *  opens beside it (below or across when there is no room). */
    private fun popMenu(anchor: View, rows: List<Triple<String, String, () -> Unit>>) {
        dismissMenu()
        performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        scrim.visibility = VISIBLE
        scrim.bringToFront()

        val loc = IntArray(2).also { anchor.getLocationInWindow(it) }
        val mine = IntArray(2).also { getLocationInWindow(it) }
        val ax = loc[0] - mine[0]
        val ay = loc[1] - mine[1]
        // The held card, bright over the scrim.
        if (anchor.width > 0 && anchor.height > 0) {
            val bmp = Bitmap.createBitmap(anchor.width, anchor.height, Bitmap.Config.ARGB_8888)
            anchor.draw(Canvas(bmp))
            val copy = ImageView(context).apply { setImageBitmap(bmp) }
            addView(copy, LayoutParams(anchor.width, anchor.height).apply { leftMargin = ax; topMargin = ay })
            lifted = copy
        }

        val menuW = dp(176f)
        val rowH = dp(50f)
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            elevation = dpf(10f)
            background = Glass.card(context, radius = 14f)
            clipToOutline = true
        }
        for ((i, row) in rows.withIndex()) {
            val (glyph, label, action) = row
            if (i > 0) box.addView(View(context).apply { setBackgroundColor(Glass.strokeHairline) },
                LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, maxOf(1, dp(0.5f))))
            // A button's own type and symbol size (17pt), as iOS draws them.
            box.addView(TextView(context).apply {
                text = label
                Glass.style(this, 17f)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    ToolIcon(context, glyph, Glass.textPrimary).apply { solid = true; weight = 1.45f; scale = 1.3f }
                        .asDrawable(dp(26f)), null, null, null)
                compoundDrawablePadding = dp(14f)
                setPadding(dp(16f), 0, dp(12f), 0)
                setTag(com.demo.glyf.R.id.qa_id, "clip:menu:${label.lowercase()}")
                setOnClickListener { action() }
            }, LinearLayout.LayoutParams(menuW, if (i > 0) rowH - maxOf(1, dp(0.5f)) else rowH))
        }

        val h = rowH * rows.size
        // Beside the card when there is room (Gboard), otherwise across from it.
        var x = ax + anchor.width + dp(8f)
        if (x + menuW > width - dp(8f)) x = ax - dp(8f) - menuW
        if (x < dp(8f)) x = minOf(maxOf(dp(8f), ax), width - menuW - dp(8f))
        val y = ay.coerceIn(dp(headerH), (height - h - dp(8f)).coerceAtLeast(dp(headerH)))
        addView(box, LayoutParams(menuW, h).apply { leftMargin = x; topMargin = y })
        menu = box
    }

    private fun dismissMenu() {
        menu?.let { removeView(it) }
        menu = null
        lifted?.let { removeView(it) }
        lifted = null
        scrim.visibility = GONE
    }

    companion object {
        /** A copy that is one web address and nothing else (iOS's rule: a
         *  link the whole way through, not a mail address). */
        fun isLink(text: String): Boolean {
            val t = text.trim()
            if (t.isEmpty() || t.length > 2048 || t.any { it.isWhitespace() }) return false
            if (t.startsWith("mailto:", ignoreCase = true) || '@' in t && !t.contains("://")) return false
            return android.util.Patterns.WEB_URL.matcher(t).matches()
        }
    }
}
