package com.demo.glyf.ime

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.TextView
import com.demo.glyf.store.SettingsStore
import org.json.JSONArray
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

/**
 * The g menu, the twin of GlyfShell's grid on iOS: every tool that is not on
 * the strip, in one grid that scrolls, four to a row, two rows showing with
 * the third peeking in. A tool is in one place, the strip or the menu, never
 * both. Tap a tile to open it. Hold one to pick it up: move it around the
 * grid to reorder (saved as `menuOrder`), or up past the grid onto the strip
 * to keep it there.
 */
class ToolMenuView(
    context: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    /** The tools the strip shows right now; the menu leaves them out. */
    private val onStrip: Set<String>,
    private val onOpen: (String) -> Unit,
    /** Finger over the strip while dragging (raw x), or null when it left. */
    private val onDragOverStrip: (Float?) -> Unit,
    /** A tile released over the strip. */
    private val onPinToStrip: (String, Float) -> Unit,
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    /** Tiles are placed by position, which a ScrollView cannot measure (it
     *  hands its child an unbounded height), so the grid reports its own. */
    private var gridHeight = 0
    private val grid = object : FrameLayout(context) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            setMeasuredDimension(measuredWidth, max(gridHeight, measuredHeight))
        }
    }
    private val scroll = object : ScrollView(context) {
        // While a tile is held the grid must not scroll out from under it.
        override fun onInterceptTouchEvent(ev: MotionEvent) =
            dragging == null && super.onInterceptTouchEvent(ev)
    }.apply {
        isVerticalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
        addView(grid)
    }
    private val tiles = LinkedHashMap<String, View>()
    private var order: MutableList<String> = savedOrder(context).filter { it !in onStrip }.toMutableList()
    private var dragging: String? = null

    /** Four tiles a row on a phone, more on a wide screen (a tile about 110 dp). */
    private val cols: Int get() = (width / dp(110f)).toInt().coerceIn(4, 8)
    private val gap get() = dp(8f)
    private val side get() = dp(6f)
    private val tileW get() = (width - side * 2 - gap * (cols - 1)) / cols
    private val tileH get() = max(dp(64f), (height - dp(40f) - gap) / 2)

    init {
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        for ((id, title) in ToolIcon.TOOLS) {
            if (id in order) tiles[id] = tile(id, title).also { grid.addView(it) }
        }
    }

    private fun tile(id: String, title: String): View {
        // iOS's tile: the key colour, 14pt corners, no edge.
        val cell = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(14f)
                setColor(Glass.surfaceCard)
            }
            contentDescription = title
            setTag(com.demo.glyf.R.id.qa_id, "shell:tile:$id")
        }
        // The glyph answers to "menu:<tool>" (the temp mail spec's id for its
        // tile), the tile itself to "shell:tile:<tool>" as ever.
        // Its symbol at 22pt in the ink, over its name (12 medium).
        // iOS's menu marks GIFs with play.square.stack (the strip and the
        // board keep the boxed "GIF").
        cell.addView(ToolIcon(context, if (id == "gifs") "playstack" else id, Glass.textPrimary).apply {
            scale = 1.4f
            weight = 1.25f
            solid = true
            setTag(com.demo.glyf.R.id.qa_id, "menu:$id")
        }, LayoutParams(LayoutParams.MATCH_PARENT, dp(26f).toInt(), Gravity.TOP))
        cell.addView(TextView(context).apply {
            text = title
            Glass.style(this, 12f, Glass.MEDIUM)
            gravity = Gravity.CENTER
            maxLines = 1
        }, LayoutParams(LayoutParams.MATCH_PARENT, dp(15f).toInt(), Gravity.TOP).apply {
            leftMargin = dp(2f).toInt(); rightMargin = dp(2f).toInt()
        })
        cell.setOnTouchListener(TileTouch(id))
        return cell
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        if (width == 0) return
        layoutTiles(animated = false)
    }

    /** Tiles in `order`, four to a row; the one being held follows the finger. */
    private fun layoutTiles(animated: Boolean) {
        val w = tileW
        val h = tileH
        // Icon over caption, centred as a column with an 8pt gap (iOS).
        val iconH = dp(26f)
        val capH = dp(15f)
        val top = (h - iconH - dp(8f) - capH) / 2
        for ((i, id) in order.withIndex()) {
            val cell = tiles[id] ?: continue
            val lp = cell.layoutParams as LayoutParams
            if (lp.width != w.toInt() || lp.height != h.toInt()) {
                lp.width = w.toInt(); lp.height = h.toInt()
                cell.layoutParams = lp
                (cell as FrameLayout).getChildAt(0).translationY = top
                cell.getChildAt(1).translationY = top + iconH + dp(8f)
            }
            if (id == dragging) continue
            val x = side + (i % cols) * (w + gap)
            val y = (i / cols) * (h + gap)
            if (animated) cell.animate().x(x).y(y).setDuration(180).start()
            else { cell.x = x; cell.y = y }
        }
        val rows = ceil(order.size / cols.toDouble()).toInt()
        val gridH = (rows * (h + gap) - gap + side).toInt()
        if (gridHeight != gridH) {
            gridHeight = gridH
            grid.post { grid.requestLayout() }
        }
    }

    private fun indexAt(xInGrid: Float, yInGrid: Float): Int {
        val c = ((xInGrid - side) / (tileW + gap)).toInt().coerceIn(0, cols - 1)
        val r = (yInGrid / (tileH + gap)).toInt().coerceAtLeast(0)
        return (r * cols + c).coerceIn(0, order.size - 1)
    }

    private inner class TileTouch(private val id: String) : OnTouchListener {
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private val handler = Handler(Looper.getMainLooper())
        private var downX = 0f
        private var downY = 0f
        private var grabX = 0f
        private var grabY = 0f
        private var overStrip = false
        private val lift = Runnable { pickUp() }

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY
                    grabX = e.x; grabY = e.y
                    handler.postDelayed(lift, 300)
                    v.alpha = 0.7f
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (dragging != id) {
                        // Moving first is a scroll, not a pick-up.
                        if (abs(e.rawX - downX) > slop || abs(e.rawY - downY) > slop) {
                            handler.removeCallbacks(lift)
                            v.alpha = 1f
                            scroll.requestDisallowInterceptTouchEvent(false)
                            return false
                        }
                        return true
                    }
                    follow(v, e)
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(lift)
                    v.alpha = 1f
                    if (dragging == id) drop(e) else onOpen(id)
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(lift)
                    v.alpha = 1f
                    if (dragging == id) drop(null)
                    return true
                }
            }
            return false
        }

        private fun pickUp() {
            val cell = tiles[id] ?: return
            dragging = id
            scroll.requestDisallowInterceptTouchEvent(true)
            cell.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            cell.bringToFront()
            cell.elevation = dp(6f)
            cell.animate().scaleX(1.08f).scaleY(1.08f).setDuration(120).start()
        }

        private fun follow(v: View, e: MotionEvent) {
            val loc = IntArray(2).also { grid.getLocationOnScreen(it) }
            val gx = e.rawX - loc[0]
            val gy = e.rawY - loc[1]
            v.x = gx - grabX
            v.y = gy - grabY
            val menuTop = IntArray(2).also { this@ToolMenuView.getLocationOnScreen(it) }[1]
            overStrip = e.rawY < menuTop
            onDragOverStrip(if (overStrip) e.rawX else null)
            if (overStrip) return
            val to = indexAt(gx, gy)
            val from = order.indexOf(id)
            if (to != from) {
                order.removeAt(from)
                order.add(to, id)
                layoutTiles(animated = true)
            }
        }

        private fun drop(e: MotionEvent?) {
            val cell = tiles[id] ?: return
            dragging = null
            cell.elevation = 0f
            cell.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
            onDragOverStrip(null)
            if (overStrip && e != null) {
                overStrip = false
                layoutTiles(animated = true)
                onPinToStrip(id, e.rawX)
                return
            }
            layoutTiles(animated = true)
            // The strip's tools keep their places in the saved order, so one
            // that leaves the strip comes back to the menu where it was.
            val shown = order.iterator()
            val merged = savedOrder(context).map { if (it in onStrip) it else shown.next() }
            val s = SettingsStore.load(context)
            s.put("menuOrder", JSONArray(merged))
            SettingsStore.save(context, s.toString())
        }
    }

    companion object {
        /** The saved order, with tools added since it was saved at the end. */
        fun savedOrder(ctx: Context): MutableList<String> {
            val known = ToolIcon.TOOLS.map { it.first }
            val saved = SettingsStore.load(ctx).optJSONArray("menuOrder")
            val out = mutableListOf<String>()
            for (i in 0 until (saved?.length() ?: 0)) {
                // An order saved with Emoji, Keys or Shorthand in it places
                // the tools that took them over.
                val id = ToolIcon.canonical(saved!!.optString(i))
                if (id in known && id !in out) out.add(id)
            }
            known.filter { it !in out }.forEach { out.add(it) }
            return out
        }
    }
}
