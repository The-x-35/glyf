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
 * The g menu, the twin of GlyfShell's grid on iOS: every tool in one grid that
 * scrolls, four to a row, two rows showing with the third peeking in. Tap a
 * tile to open it. Hold one to pick it up: move it around the grid to reorder
 * (saved as `menuOrder`), or up past the grid onto the strip to keep it there.
 */
class ToolMenuView(
    context: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
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
    private var order: MutableList<String> = savedOrder(context)
    private var dragging: String? = null

    private val cols = 4
    private val gap get() = dp(8f)
    private val side get() = dp(6f)
    private val tileW get() = (width - side * 2 - gap * (cols - 1)) / cols
    private val tileH get() = max(dp(64f), (height - dp(40f) - gap) / 2)

    init {
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        for ((id, title) in ToolIcon.TOOLS) tiles[id] = tile(id, title).also { grid.addView(it) }
    }

    private fun tile(id: String, title: String): View {
        val cell = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(14f)
                setColor(palette.card)
            }
            contentDescription = title
        }
        cell.addView(ToolIcon(context, id, palette.ink).apply { scale = 1.15f },
            LayoutParams(LayoutParams.MATCH_PARENT, dp(28f).toInt(), Gravity.TOP))
        cell.addView(TextView(context).apply {
            text = title
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(palette.ink)
            maxLines = 1
        }, LayoutParams(LayoutParams.MATCH_PARENT, dp(16f).toInt(), Gravity.TOP))
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
        val iconH = dp(28f)
        val capH = dp(16f)
        val top = (h - iconH - dp(6f) - capH) / 2
        for ((i, id) in order.withIndex()) {
            val cell = tiles[id] ?: continue
            val lp = cell.layoutParams as LayoutParams
            if (lp.width != w.toInt() || lp.height != h.toInt()) {
                lp.width = w.toInt(); lp.height = h.toInt()
                cell.layoutParams = lp
                (cell as FrameLayout).getChildAt(0).translationY = top
                cell.getChildAt(1).translationY = top + iconH + dp(6f)
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
            val s = SettingsStore.load(context)
            s.put("menuOrder", JSONArray(order))
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
                val id = saved!!.optString(i)
                if (id in known && id !in out) out.add(id)
            }
            known.filter { it !in out }.forEach { out.add(it) }
            return out
        }
    }
}
