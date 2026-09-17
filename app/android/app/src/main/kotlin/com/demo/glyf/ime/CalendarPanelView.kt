package com.demo.glyf.ime

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * The keyboard's calendar, the twin of CalendarSurface on iOS: the day's
 * events, full width, because that is what you reach for mid-message. Tap one
 * to put it in the message, or share when you are free that day. Month opens
 * the grid to jump to another day.
 */
class CalendarPanelView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    private val onInsert: (String) -> Unit,
    private val onClose: () -> Unit,
    private val onConnect: () -> Unit,
) : FrameLayout(ctx) {

    private val accent = Color.rgb(0x7C, 0x5C, 0xFF)
    private val connected = CalendarText.connected(ctx)
    private var month: Calendar = Calendar.getInstance().apply {
        set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }
    private var selected: Long = CalendarText.startOfDay(System.currentTimeMillis())
    private var events: List<CalendarText.Event> = emptyList()

    /** The grid is a detour for picking another day; the events are the point. */
    private var showingMonth = false

    private val grid = MonthGrid(ctx)
    private val title = TextView(ctx)
    private val modeButton = TextView(ctx)
    private val agendaScroll = ScrollView(ctx)
    private val agenda = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
    private val action = TextView(ctx)

    private fun dp(v: Float) = v * resources.displayMetrics.density
    private fun dpi(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun soft(alpha: Int) =
        Color.argb(alpha, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink))

    init {
        loadEvents()
        val root = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        // Header: close, then the tool's name, like the other panels.
        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(8), 0, dpi(8), 0)
        }
        header.addView(TextView(ctx).apply {
            text = "✕"; textSize = 16f; setTextColor(palette.ink)
            setPadding(dpi(8), dpi(6), dpi(12), dpi(6))
            setTag(com.demo.glyf.R.id.qa_id, "calendar:close"); contentDescription = "Close"
            setOnClickListener { onClose() }
        })
        header.addView(TextView(ctx).apply {
            text = "Calendar"; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink)
        })
        root.addView(header, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(40)))

        // The day (or the month, on the grid), with the way to the other.
        val dayRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(12), 0, dpi(10), 0)
        }
        title.apply { textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink) }
        dayRow.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        dayRow.addView(arrow("‹", "calendar:prev") { step(-1) })
        dayRow.addView(arrow("›", "calendar:next") { step(1) })
        modeButton.apply {
            textSize = 13f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink); gravity = Gravity.CENTER
            setPadding(dpi(14), 0, dpi(14), 0)
            background = GradientDrawable().apply { cornerRadius = dp(15f); setColor(palette.card) }
            setTag(com.demo.glyf.R.id.qa_id, "calendar:month")
            setOnClickListener { toggleMonth() }
        }
        dayRow.addView(modeButton, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dpi(30))
            .apply { leftMargin = dpi(6) })
        root.addView(dayRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(36)))

        // One space, holding either the events or the month.
        val body = FrameLayout(ctx)
        agendaScroll.apply { isVerticalScrollBarEnabled = false; addView(agenda) }
        agenda.setPadding(dpi(12), dpi(4), dpi(12), dpi(4))
        body.addView(agendaScroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        body.addView(grid, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply {
            leftMargin = dpi(10); rightMargin = dpi(10); bottomMargin = dpi(6)
        })
        root.addView(body, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        action.apply {
            text = if (connected) "Share free time" else "Connect calendar"
            textSize = 14f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            background = GradientDrawable().apply { cornerRadius = dp(19f); setColor(accent) }
            setTag(com.demo.glyf.R.id.qa_id, if (connected) "calendar:free" else "calendar:connect")
            setOnClickListener {
                if (connected) onInsert(CalendarText.freeTime(selected, events)) else onConnect()
            }
        }
        root.addView(action, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(38)).apply {
            leftMargin = dpi(12); rightMargin = dpi(12); bottomMargin = dpi(8); topMargin = dpi(4)
        })

        addView(root, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        render()
    }

    private fun arrow(label: String, id: String, onTap: () -> Unit) = TextView(context).apply {
        text = label; textSize = 20f; setTextColor(palette.ink); gravity = Gravity.CENTER
        setPadding(dpi(10), 0, dpi(10), dpi(2))
        setTag(com.demo.glyf.R.id.qa_id, id)
        setOnClickListener { onTap() }
    }

    private fun loadEvents() {
        val from = (month.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -7) }.timeInMillis
        val to = (month.clone() as Calendar).apply { add(Calendar.MONTH, 1); add(Calendar.DAY_OF_MONTH, 7) }.timeInMillis
        events = CalendarText.load(context, from, to)
    }

    /** The arrows walk days on the list, months on the grid. */
    private fun step(direction: Int) {
        if (showingMonth) {
            month.add(Calendar.MONTH, direction)
            loadEvents()
        } else {
            val next = Calendar.getInstance().apply {
                timeInMillis = selected
                add(Calendar.DAY_OF_MONTH, direction)
            }
            selected = CalendarText.startOfDay(next.timeInMillis)
            val sameMonth = next.get(Calendar.MONTH) == month.get(Calendar.MONTH) &&
                next.get(Calendar.YEAR) == month.get(Calendar.YEAR)
            if (!sameMonth) {
                month = (next.clone() as Calendar).apply {
                    set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                }
                loadEvents()
            }
        }
        render()
    }

    private fun toggleMonth() {
        showingMonth = !showingMonth
        if (showingMonth) {
            val day = Calendar.getInstance().apply { timeInMillis = selected }
            val sameMonth = day.get(Calendar.MONTH) == month.get(Calendar.MONTH) &&
                day.get(Calendar.YEAR) == month.get(Calendar.YEAR)
            if (!sameMonth) {
                month = (day.clone() as Calendar).apply {
                    set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                }
                loadEvents()
            }
        }
        render()
    }

    private fun render() {
        title.text = if (showingMonth) {
            SimpleDateFormat(
                android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMMyyyy"),
                Locale.getDefault()).format(month.time)
        } else {
            CalendarText.dayLabel(selected)
        }
        modeButton.text = if (showingMonth) "Done" else "Month"
        modeButton.contentDescription = if (showingMonth) "Close the month" else "Open the month"
        grid.visibility = if (showingMonth) View.VISIBLE else View.GONE
        agendaScroll.visibility = if (showingMonth) View.GONE else View.VISIBLE
        action.visibility = if (showingMonth) View.GONE else View.VISIBLE
        grid.invalidate()

        agenda.removeAllViews()
        if (!connected || showingMonth) return
        val day = CalendarText.on(selected, events)
        if (day.isEmpty()) {
            agenda.addView(TextView(context).apply {
                text = "Nothing planned"; textSize = 14f; setTextColor(soft(150))
                setPadding(dpi(2), dpi(10), 0, 0)
            })
        }
        for ((i, e) in day.withIndex()) {
            agenda.addView(eventRow(e, i), LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { bottomMargin = dpi(8) })
        }
    }

    private fun eventRow(e: CalendarText.Event, index: Int): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(8), dpi(9), dpi(10), dpi(9))
            background = GradientDrawable().apply { cornerRadius = dp(12f); setColor(palette.card) }
            setTag(com.demo.glyf.R.id.qa_id, "calendar:event:$index")
            contentDescription = CalendarText.insert(e)
            setOnClickListener { onInsert(CalendarText.insert(e)) }
        }
        row.addView(View(context).apply {
            background = GradientDrawable().apply { cornerRadius = dp(2f); setColor(e.color ?: accent) }
        }, LinearLayout.LayoutParams(dpi(4), dpi(34)).apply { rightMargin = dpi(10) })

        val time = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        time.addView(TextView(context).apply {
            text = if (e.allDay) "All day" else CalendarText.clock(e.start)
            textSize = if (e.allDay) 13f else 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(palette.ink)
            maxLines = 1
        })
        if (!e.allDay) {
            time.addView(TextView(context).apply {
                text = CalendarText.clock(e.end); textSize = 12f; setTextColor(soft(150)); maxLines = 1
            })
        }
        row.addView(time, LinearLayout.LayoutParams(dpi(66), LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { rightMargin = dpi(6) })

        val text = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        text.addView(TextView(context).apply {
            this.text = e.title; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink)
            maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
        })
        val place = e.location
        if (!place.isNullOrEmpty()) {
            text.addView(TextView(context).apply {
                this.text = place; textSize = 12.5f; setTextColor(soft(150))
                maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
            })
        }
        row.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    /** The month, drawn: weekday initials, day numbers, today filled, the
     *  chosen day ringed, a dot under days with something on. */
    private inner class MonthGrid(ctx: Context) : View(ctx) {
        private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)

        private fun cellDay(i: Int): Long? {
            val first = month.get(Calendar.DAY_OF_WEEK)
            val offset = (first - month.firstDayOfWeek + 7) % 7
            val days = month.getActualMaximum(Calendar.DAY_OF_MONTH)
            val n = i - offset
            if (n < 0 || n >= days) return null
            return (month.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, n) }.timeInMillis
        }

        override fun onDraw(c: Canvas) {
            val w = width / 7f
            val headH = dp(20f)
            val cellH = (height - headH) / 6f
            text.textSize = dp(11f)
            text.typeface = Typeface.DEFAULT_BOLD
            text.color = soft(140)
            val names = SimpleDateFormat("EEEEE", Locale.getDefault())
            val cal = Calendar.getInstance().apply { set(Calendar.DAY_OF_WEEK, month.firstDayOfWeek) }
            for (i in 0 until 7) {
                c.drawText(names.format(cal.time), w * i + w / 2, dp(14f), text)
                cal.add(Calendar.DAY_OF_WEEK, 1)
            }
            val today = CalendarText.startOfDay(System.currentTimeMillis())
            for (i in 0 until 42) {
                val day = cellDay(i) ?: continue
                val cx = w * (i % 7) + w / 2
                val cy = headH + cellH * (i / 7) + cellH / 2
                val r = minOf(w, cellH) / 2 - dp(2f)
                val isToday = day == today
                val isSelected = day == selected
                if (isToday) {
                    fill.color = accent
                    c.drawCircle(cx, cy, r, fill)
                } else if (isSelected) {
                    fill.color = soft(34)
                    c.drawCircle(cx, cy, r, fill)
                }
                text.textSize = dp(15f)
                text.typeface = if (isToday || isSelected) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                text.color = if (isToday) Color.WHITE else palette.ink
                val dom = Calendar.getInstance().apply { timeInMillis = day }.get(Calendar.DAY_OF_MONTH)
                c.drawText("$dom", cx, cy - (text.descent() + text.ascent()) / 2, text)
                if (CalendarText.on(day, events).isNotEmpty()) {
                    fill.color = if (isToday) Color.WHITE else accent
                    c.drawCircle(cx, cy + r - dp(4f), dp(2f), fill)
                }
            }
        }

        /** Picking a day is what the grid is for, so it closes behind you. */
        override fun onTouchEvent(e: MotionEvent): Boolean {
            if (e.action == MotionEvent.ACTION_UP) {
                val w = width / 7f
                val headH = dp(20f)
                val cellH = (height - headH) / 6f
                if (e.y < headH) return true
                val col = (e.x / w).toInt().coerceIn(0, 6)
                val row = ((e.y - headH) / cellH).toInt().coerceIn(0, 5)
                cellDay(row * 7 + col)?.let {
                    selected = it
                    showingMonth = false
                    render()
                }
            }
            return true
        }
    }
}
