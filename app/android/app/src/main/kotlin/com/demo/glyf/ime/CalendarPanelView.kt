package com.demo.glyf.ime

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
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
 * The keyboard's calendar, the twin of CalendarSurface on iOS: a month on the
 * left, the chosen day on the right. Tap an event to put it in the message,
 * or share when you are free that day.
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

    private val grid = MonthGrid(ctx)
    private val monthLabel = TextView(ctx)
    private val dayTitle = TextView(ctx)
    private val agenda = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }

    private fun dp(v: Float) = v * resources.displayMetrics.density
    private fun dpi(v: Int) = (v * resources.displayMetrics.density).toInt()

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

        val body = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        // Left: month
        val left = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setPadding(dpi(10), 0, dpi(6), dpi(6)) }
        val monthRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        monthLabel.apply { textSize = 14.5f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink) }
        monthRow.addView(monthLabel, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        monthRow.addView(arrow("‹", "calendar:prev") { shift(-1) })
        monthRow.addView(arrow("›", "calendar:next") { shift(1) })
        left.addView(monthRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(30)))
        left.addView(grid, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        body.addView(left, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1.25f))
        body.addView(View(ctx).apply { setBackgroundColor(Color.argb(28, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink))) },
            LinearLayout.LayoutParams(dpi(1), LinearLayout.LayoutParams.MATCH_PARENT).apply { setMargins(0, dpi(6), 0, dpi(10)) })

        // Right: the chosen day
        val right = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setPadding(dpi(10), 0, dpi(10), dpi(8)) }
        dayTitle.apply { textSize = 14f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink) }
        right.addView(dayTitle, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(28)))
        right.addView(ScrollView(ctx).apply { isVerticalScrollBarEnabled = false; addView(agenda) },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        right.addView(TextView(ctx).apply {
            text = if (connected) "Share free time" else "Connect calendar"
            textSize = 13.5f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            background = GradientDrawable().apply { cornerRadius = dp(18f); setColor(accent) }
            setTag(com.demo.glyf.R.id.qa_id, if (connected) "calendar:free" else "calendar:connect")
            setOnClickListener {
                if (connected) onInsert(CalendarText.freeTime(selected, events)) else onConnect()
            }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(36)).apply { topMargin = dpi(6) })
        body.addView(right, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        root.addView(body, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
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

    private fun shift(step: Int) {
        month.add(Calendar.MONTH, step)
        loadEvents()
        render()
    }

    private fun render() {
        monthLabel.text = SimpleDateFormat(
            android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMMyyyy"),
            Locale.getDefault()).format(month.time)
        grid.invalidate()
        dayTitle.text = CalendarText.dayLabel(selected)
        agenda.removeAllViews()
        if (!connected) return
        val day = CalendarText.on(selected, events)
        if (day.isEmpty()) {
            agenda.addView(TextView(context).apply {
                text = "Nothing planned"; textSize = 13f
                setTextColor(Color.argb(150, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink)))
            })
        }
        for ((i, e) in day.withIndex()) {
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dpi(8), dpi(6), dpi(8), dpi(6))
                background = GradientDrawable().apply { cornerRadius = dp(10f); setColor(palette.card) }
                setTag(com.demo.glyf.R.id.qa_id, "calendar:event:$i")
                contentDescription = CalendarText.insert(e)
                setOnClickListener { onInsert(CalendarText.insert(e)) }
            }
            row.addView(View(context).apply {
                background = GradientDrawable().apply { cornerRadius = dp(1.5f); setColor(e.color ?: accent) }
            }, LinearLayout.LayoutParams(dpi(3), LinearLayout.LayoutParams.MATCH_PARENT).apply { rightMargin = dpi(7) })
            val text = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
            text.addView(TextView(context).apply {
                this.text = if (e.allDay) "All day" else CalendarText.clock(e.start)
                textSize = 11f
                setTextColor(Color.argb(150, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink)))
            })
            text.addView(TextView(context).apply {
                this.text = e.title; textSize = 13.5f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink)
                maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
            })
            row.addView(text)
            agenda.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { bottomMargin = dpi(6) })
        }
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
            val headH = dp(16f)
            val cellH = (height - headH) / 6f
            text.textSize = dp(10.5f)
            text.typeface = Typeface.DEFAULT_BOLD
            text.color = Color.argb(140, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink))
            val names = SimpleDateFormat("EEEEE", Locale.getDefault())
            val cal = Calendar.getInstance().apply { set(Calendar.DAY_OF_WEEK, month.firstDayOfWeek) }
            for (i in 0 until 7) {
                c.drawText(names.format(cal.time), w * i + w / 2, dp(12f), text)
                cal.add(Calendar.DAY_OF_WEEK, 1)
            }
            val today = CalendarText.startOfDay(System.currentTimeMillis())
            for (i in 0 until 42) {
                val day = cellDay(i) ?: continue
                val cx = w * (i % 7) + w / 2
                val cy = headH + cellH * (i / 7) + cellH / 2
                val r = minOf(w, cellH) / 2 - dp(1.5f)
                val isToday = day == today
                val isSelected = day == selected
                if (isToday) {
                    fill.color = accent
                    c.drawCircle(cx, cy, r, fill)
                } else if (isSelected) {
                    fill.color = Color.argb(34, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink))
                    c.drawCircle(cx, cy, r, fill)
                }
                text.textSize = dp(13.5f)
                text.typeface = if (isToday || isSelected) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                text.color = if (isToday) Color.WHITE else palette.ink
                val dom = Calendar.getInstance().apply { timeInMillis = day }.get(Calendar.DAY_OF_MONTH)
                c.drawText("$dom", cx, cy - (text.descent() + text.ascent()) / 2, text)
                if (CalendarText.on(day, events).isNotEmpty()) {
                    fill.color = if (isToday) Color.WHITE else accent
                    c.drawCircle(cx, cy + r - dp(3.5f), dp(2f), fill)
                }
            }
        }

        override fun onTouchEvent(e: MotionEvent): Boolean {
            if (e.action == MotionEvent.ACTION_UP) {
                val w = width / 7f
                val headH = dp(16f)
                val cellH = (height - headH) / 6f
                if (e.y < headH) return true
                val col = (e.x / w).toInt().coerceIn(0, 6)
                val row = ((e.y - headH) / cellH).toInt().coerceIn(0, 5)
                cellDay(row * 7 + col)?.let {
                    selected = it
                    render()
                }
            }
            return true
        }
    }
}
