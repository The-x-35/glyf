package com.demo.glyf.ime

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.demo.glyf.store.ClipboardStore

/**
 * The clipboard, Gboard's way — the twin of ClipboardPanel.swift, so both
 * platforms look and behave the same: back and edit in the header,
 * PINNED and RECENT as two columns of cards sized to their text, tap to
 * paste, hold for Paste · Pin · Delete over a dimmed panel.
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
    private fun dp(v: Float) = (v * density).toInt()
    private fun dpf(v: Float) = v * density

    private val body = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(context).apply {
        isVerticalScrollBarEnabled = false
        addView(body)
    }
    private val scrim = View(context).apply {
        setBackgroundColor(Color.argb(184, Color.red(palette.board),
            Color.green(palette.board), Color.blue(palette.board)))
        visibility = GONE
        setOnClickListener { dismissMenu() }
    }
    private var menu: View? = null
    private var editing = false

    /** Recent screenshots, asked of MediaStore off the main thread (see
     *  loadShots). Declared before init: init's reload() reads it. */
    private var shotList: List<com.demo.glyf.ScreenshotAccess.Shot> = emptyList()

    init {
        setBackgroundColor(palette.board)
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        column.addView(header(), LinearLayout.LayoutParams(
            LayoutParams.MATCH_PARENT, dp(52f)))
        column.addView(scroll, LinearLayout.LayoutParams(
            LayoutParams.MATCH_PARENT, 0, 1f))
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

    private fun circle(icon: String, onTap: () -> Unit): View = ToolIcon(context, icon, palette.ink).apply {
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(palette.card)
        }
        setOnClickListener { onTap() }
    }

    private fun header(): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12f), 0, dp(12f), 0)
        }
        row.addView(circle("back") { onClose() }.apply {
            setTag(com.demo.glyf.R.id.qa_id, "clip:back"); contentDescription = "Close"
        }, LinearLayout.LayoutParams(dp(38f), dp(38f)))
        row.addView(TextView(context).apply {
            text = "Clipboard"
            textSize = 22f
            setTextColor(palette.ink)
            setPadding(dp(14f), 0, 0, 0)
        }, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        if (historyOn()) {
            row.addView(circle("edit") { editing = !editing; reload() },
                LinearLayout.LayoutParams(dp(38f), dp(38f)))
        }
        return row
    }

    /** On unless turned off in the app (Keyboard, Keep what you copy). */
    private fun historyOn(): Boolean =
        com.demo.glyf.store.SettingsStore.load(context).optBoolean("clipboardHistory", true)

    // ---- cards -------------------------------------------------------------

    fun reload() {
        body.removeAllViews()
        if (!historyOn()) {
            addTip("Clipboard history is off in the Glyf app.")
            return
        }
        val items = ClipboardStore.load(context)
        val pinned = items.filter { it.pinned }
        // Recent copies and recent screenshots share one timeline, newest first.
        val recent = (items.filter { !it.pinned }.map { Entry.Text(it) as Entry } + shots())
            .sortedByDescending { it.ts }
        if (pinned.isNotEmpty()) { addSection("PINNED"); addGrid(pinned.map { Entry.Text(it) }) }
        if (recent.isNotEmpty()) { addSection("RECENT"); addGrid(recent) }
        if (items.isEmpty() && recent.isEmpty()) {
            addSection("TIPS")
            addTip("Anything you copy shows up here. Tap a clip to paste it, hold it to pin.")
        }
    }

    private sealed class Entry(val ts: Long) {
        class Text(val item: ClipboardStore.Item) : Entry(item.ts)
        class Image(val shot: com.demo.glyf.ScreenshotAccess.Shot) : Entry(shot.takenMs)
    }

    private val prefs get() = context.getSharedPreferences("glyf_clip", Context.MODE_PRIVATE)

    /** Screenshots from the last hour, when turned on in the app, minus the
     *  ones removed from the clipboard here. */
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

    private fun addSection(title: String) {
        body.addView(TextView(context).apply {
            text = title
            textSize = 12.5f
            letterSpacing = 0.05f
            setTextColor(palette.inkSoft)
            setPadding(dp(16f), dp(8f), 0, dp(6f))
        })
    }

    private fun addTip(text: String) {
        body.addView(TextView(context).apply {
            this.text = text
            textSize = 15f
            setTextColor(palette.ink)
            setPadding(dp(14f), dp(14f), dp(14f), dp(14f))
            background = GradientDrawable().apply {
                cornerRadius = dpf(12f); setColor(palette.card)
            }
        }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            setMargins(dp(12f), 0, dp(12f), dp(10f))
        })
    }

    /** Two columns; each card goes into whichever column is shorter. */
    private fun addGrid(items: List<Entry>) {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        val cols = List(2) { LinearLayout(context).apply { orientation = LinearLayout.VERTICAL } }
        val heights = FloatArray(2)
        val screenW = resources.displayMetrics.widthPixels
        val colW = (screenW - dp(12f) * 2 - dp(10f)) / 2f
        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply { textSize = dpf(15f) }
        for (entry in items) {
            val c = if (heights[0] <= heights[1]) 0 else 1
            when (entry) {
                is Entry.Text -> {
                    val flat = entry.item.text.trim()
                    val textW = (colW - dp(14f) * 2).toInt().coerceAtLeast(1)
                    val layout = StaticLayout.Builder.obtain(flat, 0, flat.length, paint, textW)
                        .setAlignment(Layout.Alignment.ALIGN_NORMAL).setMaxLines(4)
                        .setEllipsize(TextUtils.TruncateAt.END).build()
                    heights[c] += layout.height + dp(14f) * 2f + dp(10f)
                    cols[c].addView(card(entry.item, flat), LinearLayout.LayoutParams(
                        LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                        bottomMargin = dp(10f)
                    })
                }
                is Entry.Image -> {
                    // Screenshots are tall; the card shows the top of one.
                    val h = (colW * 1.25f).toInt()
                    heights[c] += h + dp(10f)
                    cols[c].addView(imageCard(entry.shot.uri, colW.toInt(), h),
                        LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, h).apply {
                            bottomMargin = dp(10f)
                        })
                }
            }
        }
        row.addView(cols[0], LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            leftMargin = dp(12f); rightMargin = dp(5f)
        })
        row.addView(cols[1], LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            leftMargin = dp(5f); rightMargin = dp(12f)
        })
        body.addView(row)
    }

    private fun imageCard(uri: android.net.Uri, w: Int, h: Int): View {
        val image = android.widget.ImageView(context).apply {
            scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
            background = GradientDrawable().apply {
                cornerRadius = dpf(12f); setColor(palette.card)
            }
            clipToOutline = true
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
        val frame = FrameLayout(context)
        frame.addView(image, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        frame.addView(TextView(context).apply {
            text = "−"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL; setColor(Color.rgb(240, 68, 56))
            }
            setOnClickListener { removeShot(uri); reload() }
        }, LayoutParams(dp(24f), dp(24f), Gravity.TOP or Gravity.END))
        return frame
    }

    private fun card(item: ClipboardStore.Item, flat: String): View {
        val card = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                cornerRadius = dpf(12f); setColor(palette.card)
            }
            setOnClickListener { if (!editing) onPaste(item.text) }
            setOnLongClickListener { if (!editing) showMenu(item, this); true }
        }
        card.addView(TextView(context).apply {
            text = flat
            textSize = 15f
            maxLines = 4
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(palette.ink)
            setPadding(dp(14f), dp(14f), dp(14f), dp(14f))
        })
        if (editing) {
            card.addView(TextView(context).apply {
                text = "−"
                textSize = 16f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL; setColor(Color.rgb(240, 68, 56))
                }
                setOnClickListener {
                    ClipboardStore.remove(context, item.text)
                    reload()
                }
            }, LayoutParams(dp(24f), dp(24f), Gravity.TOP or Gravity.END))
        }
        return card
    }

    // ---- hold menu ---------------------------------------------------------

    private fun showMenu(item: ClipboardStore.Item, anchor: View) {
        popMenu(anchor, listOf(
            Triple("⎘", "Paste") { dismissMenu(); onPaste(item.text) },
            Triple("🔒", "Save to vault") {
                val refusal = com.demo.glyf.store.NotesStore.upsert(context, null, item.text)
                dismissMenu()
                android.widget.Toast.makeText(context, refusal ?: "Saved to vault",
                    android.widget.Toast.LENGTH_SHORT).show()
            },
            Triple("📌", if (item.pinned) "Unpin" else "Pin") {
                ClipboardStore.togglePin(context, item.text); dismissMenu(); reload()
            },
            Triple("🗑", "Delete") {
                ClipboardStore.remove(context, item.text); dismissMenu(); reload()
            },
        ))
    }

    private fun showImageMenu(uri: android.net.Uri, anchor: View) {
        popMenu(anchor, listOf(
            Triple("⎘", "Paste") { dismissMenu(); onImage(uri) },
            // Removes it from the clipboard; the screenshot stays in Photos.
            Triple("🗑", "Delete") { removeShot(uri); dismissMenu(); reload() },
        ))
    }

    private fun popMenu(anchor: View, rows: List<Triple<String, String, () -> Unit>>) {
        dismissMenu()
        performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        scrim.visibility = VISIBLE
        scrim.bringToFront()

        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            elevation = dpf(8f)
            background = GradientDrawable().apply {
                cornerRadius = dpf(14f); setColor(palette.card)
            }
        }
        for ((icon, label, action) in rows) {
            box.addView(TextView(context).apply {
                text = "$icon    $label"
                textSize = 16f
                setTextColor(palette.ink)
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(18f), 0, dp(18f), 0)
                setOnClickListener { action() }
            }, LinearLayout.LayoutParams(dp(176f), dp(50f)))
        }

        val loc = IntArray(2).also { anchor.getLocationInWindow(it) }
        val mine = IntArray(2).also { getLocationInWindow(it) }
        val ax = loc[0] - mine[0]
        val ay = loc[1] - mine[1]
        val menuW = dp(176f)
        var x = ax + anchor.width + dp(8f)
        if (x + menuW > width - dp(8f)) x = ax - dp(8f) - menuW
        if (x < dp(8f)) x = dp(8f)
        val y = ay.coerceIn(dp(52f), (height - dp(50f) * rows.size).coerceAtLeast(dp(52f)))
        addView(box, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            leftMargin = x; topMargin = y
        })
        menu = box
    }

    private fun dismissMenu() {
        menu?.let { removeView(it) }
        menu = null
        scrim.visibility = GONE
    }
}
