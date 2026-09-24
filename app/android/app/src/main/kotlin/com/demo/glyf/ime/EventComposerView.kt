package com.demo.glyf.ime

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.NumberPicker
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import java.util.Calendar

/** A field typed with the keyboard's own keys, over a strip above them. The
 *  IME feeds it; Return ends it. */
interface StripField {
    val stripText: String
    fun setStripText(text: String)
    fun endStrip()
}

/**
 * New Event, the twin of EventComposer.swift: Cancel, the name and Add along
 * the top, then rows that scroll: Title, Invitees, Starts, Ends, Video call,
 * Share in chat, All-day, the way Calendar's own sheet has them. The title
 * takes a whole plan in one line ("Lunch with Sam tomorrow 1pm") and fills
 * the times. Invitees show only with Google Calendar connected: the event then
 * goes to Google, which emails each one the invite. Share in chat puts the
 * event in the message, for the person the chat is with. The date and time
 * pills open wheels (day, hour, minute, AM/PM) in place of the rows.
 */
class EventComposerView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    start: Draft,
    private val canAdd: Boolean,
    /** Google Calendar is connected: invitees can be asked. */
    private val google: Boolean,
    private val onCancel: () -> Unit,
    private val onAdd: (Draft) -> Unit,
    /** true: a field is being typed, the letter keys should come up under a
     *  strip; false: back to the rows. */
    private val onEditTitle: (Boolean) -> Unit,
    private val onConnect: () -> Unit,
) : FrameLayout(ctx), StripField {

    data class Draft(
        val title: String,
        val start: Long,
        val end: Long,
        val allDay: Boolean,
        /** Make a call link and put it in the event (its location). */
        val videoCall: Boolean = false,
        /** Google emails each one the invite (Google Calendar connected). */
        val invitees: List<String> = emptyList(),
        /** Once added, the event goes into the message for the chat. */
        val share: Boolean = false,
    )

    private enum class Field { TITLE, INVITEES }

    private var draft = start
    /** Whatever the title said, so the rows and the event agree. */
    private var typed = start.title
    /** The invitees as typed ("sam@x.com ria@y.com"). */
    private var inviteLine = start.invitees.joinToString(" ")
    private var editing: Field? = null
    /** A field is being typed (the title or the invitees). */
    val editingTitle: Boolean get() = editing != null
    private var picking: Int = 0          // 0 none, 1 starts, 2 ends

    private val accent = Color.rgb(0x7C, 0x5C, 0xFF)
    private fun dp(v: Float) = v * resources.displayMetrics.density
    private fun dpi(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun soft(alpha: Int) =
        Color.argb(alpha, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink))

    private val column = LinearLayout(ctx)
    private val header = LinearLayout(ctx)
    private val cancel = TextView(ctx)
    private val heading = TextView(ctx)
    private val add = TextView(ctx)
    private val rows = ScrollView(ctx)
    private val card = LinearLayout(ctx)
    private val titleValue = TextView(ctx)
    private val inviteValue = TextView(ctx)
    private val startDate = pill("event:starts:date") { pick(1) }
    private val startTime = pill("event:starts:time") { pick(1) }
    private val endDate = pill("event:ends:date") { pick(2) }
    private val endTime = pill("event:ends:time") { pick(2) }
    private val allDay = Switch(ctx)
    private val video = Switch(ctx)
    private val share = Switch(ctx)
    private val note = LinearLayout(ctx)
    private val wheels = LinearLayout(ctx)
    private val dayWheel = NumberPicker(ctx)
    private val hourWheel = NumberPicker(ctx)
    private val minuteWheel = NumberPicker(ctx)
    private val ampmWheel = NumberPicker(ctx)
    private val strip = LinearLayout(ctx)
    private val stripField = LinearLayout(ctx)
    private val stripTextView = TextView(ctx)
    private val hint = TextView(ctx)
    /** The day wheel's first day; entries are days from it. */
    private var wheelFrom = 0L

    init {
        column.orientation = LinearLayout.VERTICAL

        // Cancel · New Event · Add
        header.orientation = LinearLayout.HORIZONTAL
        header.gravity = Gravity.CENTER_VERTICAL
        cancel.apply {
            text = "Cancel"; textSize = 16f; setTextColor(accent)
            setPadding(dpi(14), dpi(8), dpi(10), dpi(8))
            tag(this, "event:cancel")
            setOnClickListener { cancelTapped() }
        }
        heading.apply {
            text = "New Event"; textSize = 16f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(palette.ink); gravity = Gravity.CENTER
        }
        add.apply {
            text = "Add"; textSize = 16f; typeface = Typeface.DEFAULT_BOLD; setTextColor(accent)
            setPadding(dpi(10), dpi(8), dpi(14), dpi(8))
            tag(this, "event:add")
            setOnClickListener { addTapped() }
        }
        header.addView(cancel)
        header.addView(heading, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(add)
        column.addView(header, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(40)))

        // Title, Invitees, Starts, Ends, Video call, All-day.
        card.orientation = LinearLayout.VERTICAL
        card.background = GradientDrawable().apply { cornerRadius = dp(12f); setColor(palette.card) }
        card.addView(row().apply {
            tag(this, "event:title")
            setOnClickListener { begin(Field.TITLE) }
            titleValue.apply { textSize = 16f; maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END }
            addView(titleValue, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }, rowParams())
        if (canAdd && google) {
            card.addView(line())
            card.addView(row().apply {
                tag(this, "event:invitees")
                setOnClickListener { begin(Field.INVITEES) }
                addView(label("Invitees"), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                inviteValue.apply {
                    textSize = 15f; maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.START
                    gravity = Gravity.END
                }
                addView(inviteValue, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.6f))
            }, rowParams())
        }
        card.addView(line())
        card.addView(row().apply {
            addView(label("Starts"), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(startDate); addView(space()); addView(startTime)
        }, rowParams())
        card.addView(line())
        card.addView(row().apply {
            addView(label("Ends"), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(endDate); addView(space()); addView(endTime)
        }, rowParams())
        if (canAdd) {
            for ((toggle, name, id) in listOf(Triple(video, "Video call", "event:video"),
                                              Triple(share, "Share in chat", "event:share"),
                                              Triple(allDay, "All-day", "event:allday"))) {
                card.addView(line())
                tag(toggle, id)
                card.addView(row().apply {
                    addView(label(name), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                    addView(toggle)
                }, rowParams())
            }
            video.setOnCheckedChangeListener { _, on -> draft = draft.copy(videoCall = on) }
            share.setOnCheckedChangeListener { _, on -> draft = draft.copy(share = on) }
            allDay.setOnCheckedChangeListener { _, on -> allDayChanged(on) }
        }
        rows.isVerticalScrollBarEnabled = false
        rows.addView(card)
        column.addView(rows, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            .apply { leftMargin = dpi(12); rightMargin = dpi(12); topMargin = dpi(2); bottomMargin = dpi(6) })

        // Without the write permission: say so, and the way to it.
        if (!canAdd) {
            note.orientation = LinearLayout.HORIZONTAL
            note.gravity = Gravity.CENTER_VERTICAL
            note.addView(TextView(ctx).apply {
                text = "Let Glyf use your calendar to add events."
                textSize = 13f; setTextColor(soft(150))
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            note.addView(TextView(ctx).apply {
                text = "Connect"; textSize = 14f; typeface = Typeface.DEFAULT_BOLD; setTextColor(accent)
                setPadding(dpi(10), dpi(6), dpi(4), dpi(6))
                tag(this, "event:open-app")
                setOnClickListener { onConnect() }
            })
            column.addView(note, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = dpi(16); rightMargin = dpi(12); bottomMargin = dpi(6) })
        }

        // The wheels, in place of the rows while a pill is open.
        wheels.orientation = LinearLayout.HORIZONTAL
        wheels.gravity = Gravity.CENTER
        for ((w, id) in listOf(dayWheel to "event:wheel:day", hourWheel to "event:wheel:hour",
                               minuteWheel to "event:wheel:minute", ampmWheel to "event:wheel:ampm")) {
            tag(w, id)
            w.descendantFocusability = NumberPicker.FOCUS_BLOCK_DESCENDANTS
            if (Build.VERSION.SDK_INT >= 29) w.textColor = palette.ink
            w.setOnValueChangedListener { _, _, _ -> wheelChanged() }
            wheels.addView(w, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.MATCH_PARENT, if (w === dayWheel) 2.2f else 1f))
        }
        hourWheel.minValue = 1; hourWheel.maxValue = 12
        minuteWheel.minValue = 0; minuteWheel.maxValue = 11
        minuteWheel.displayedValues = Array(12) { String.format("%02d", it * 5) }
        ampmWheel.minValue = 0; ampmWheel.maxValue = 1
        ampmWheel.displayedValues = arrayOf("AM", "PM")
        wheels.visibility = GONE
        column.addView(wheels, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        addView(column, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        // The strip while a field is typed: Cancel, the field, Add; what it read below.
        strip.orientation = LinearLayout.VERTICAL
        strip.visibility = GONE
        val stripRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        stripRow.addView(TextView(ctx).apply {
            text = "Cancel"; textSize = 15f; setTextColor(accent)
            setPadding(dpi(12), dpi(6), dpi(8), dpi(6))
            setOnClickListener { cancelTapped() }
        })
        stripField.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(10), 0, dpi(10), 0)
            background = GradientDrawable().apply { cornerRadius = dp(10f); setColor(palette.card) }
        }
        stripTextView.apply { textSize = 15f; setTextColor(palette.ink); maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.START }
        stripField.addView(stripTextView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT))
        stripField.addView(View(ctx).apply { setBackgroundColor(accent) },
            LinearLayout.LayoutParams(dpi(2), dpi(20)).apply { leftMargin = dpi(1) })
        stripRow.addView(stripField, LinearLayout.LayoutParams(0, dpi(38), 1f))
        stripRow.addView(TextView(ctx).apply {
            text = "Add"; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(accent)
            setPadding(dpi(10), dpi(6), dpi(12), dpi(6))
            tag(this, "event:strip:add")
            setOnClickListener { addTapped() }
        })
        strip.addView(stripRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(50)))
        hint.apply { textSize = 13f; setTextColor(soft(150)); setPadding(dpi(84), 0, dpi(12), 0); tag(this, "event:hint") }
        strip.addView(hint)
        addView(strip, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        render()
    }

    // MARK: pieces

    private fun tag(v: View, id: String) = v.setTag(com.demo.glyf.R.id.qa_id, id)

    private fun row() = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dpi(14), 0, dpi(10), 0)
    }

    private fun rowParams() = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(40))

    private fun line() = View(context).apply { setBackgroundColor(soft(28)) }.also {
        it.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1).apply { leftMargin = dpi(14) }
    }

    private fun label(t: String) = TextView(context).apply { text = t; textSize = 16f; setTextColor(palette.ink) }

    private fun space() = View(context).apply { layoutParams = LinearLayout.LayoutParams(dpi(6), 1) }

    private fun pill(id: String, onTap: () -> Unit) = TextView(context).apply {
        textSize = 15f
        setTextColor(palette.ink)
        gravity = Gravity.CENTER
        setPadding(dpi(10), dpi(5), dpi(10), dpi(5))
        background = GradientDrawable().apply { cornerRadius = dp(7f); setColor(soft(20)) }
        tag(this, id)
        setOnClickListener { onTap() }
    }

    // MARK: behaviour

    private fun cancelTapped() {
        if (picking != 0) { picking = 0; render(); return }
        if (editing != null) endStrip()
        onCancel()
    }

    private fun addTapped() {
        if (picking != 0) { picking = 0; render(); return }   // the wheels' Done
        if (editing != null) endStrip()
        if (!canAdd) return
        val title = draft.title.trim().ifEmpty { "New Event" }
        onAdd(draft.copy(title = title, invitees = if (google) EventParse.people(inviteLine).second else emptyList()))
    }

    private fun begin(field: Field) {
        if (editing != null) return
        editing = field
        picking = 0
        render()
        onEditTitle(true)
    }

    /** Return on the keys, or Add: back to the rows. */
    override fun endStrip() {
        if (editing == null) return
        editing = null
        render()
        onEditTitle(false)
    }

    override val stripText: String get() = if (editing == Field.INVITEES) inviteLine else typed

    /** The keys typed into the field: a plan in the title sets the times too. */
    override fun setStripText(text: String) {
        if (editing == Field.INVITEES) {
            inviteLine = text
            draft = draft.copy(invitees = EventParse.people(text).second)
            render()
            return
        }
        typed = text
        val plan = EventParse.parse(text, dayFirst = EventParse.regionDayFirst)
        draft = if (plan.hasDay || plan.hasTime || plan.allDay) {
            draft.copy(title = plan.title, start = plan.start, end = plan.end, allDay = plan.allDay)
        } else {
            draft.copy(title = text.trim())
        }
        render()
    }

    private fun pick(which: Int) {
        if (editing != null) endStrip()
        picking = which
        val at = if (which == 1) draft.start else draft.end
        // Days from a week back to a year on, "Today" where it falls.
        val today = CalendarText.startOfDay(System.currentTimeMillis())
        wheelFrom = today - 7 * 86_400_000L
        val labels = Array(373) { i ->
            val day = Calendar.getInstance().apply { timeInMillis = wheelFrom; add(Calendar.DAY_OF_MONTH, i) }.timeInMillis
            if (day == today) "Today" else CalendarText.dayLabel(day)
        }
        dayWheel.displayedValues = null
        dayWheel.minValue = 0
        dayWheel.maxValue = labels.size - 1
        dayWheel.displayedValues = labels
        val c = Calendar.getInstance().apply { timeInMillis = at }
        dayWheel.value = daysBetween(wheelFrom, CalendarText.startOfDay(at)).coerceIn(0, labels.size - 1)
        val h = c.get(Calendar.HOUR_OF_DAY)
        hourWheel.value = if (h % 12 == 0) 12 else h % 12
        minuteWheel.value = (c.get(Calendar.MINUTE) / 5).coerceIn(0, 11)
        ampmWheel.value = if (h >= 12) 1 else 0
        render()
    }

    private fun daysBetween(a: Long, b: Long): Int {
        val ca = Calendar.getInstance().apply { timeInMillis = a }
        val cb = Calendar.getInstance().apply { timeInMillis = b }
        var n = 0
        while (ca.before(cb) && n < 1000) { ca.add(Calendar.DAY_OF_MONTH, 1); n++ }
        return n
    }

    private fun wheelChanged() {
        val c = Calendar.getInstance().apply {
            timeInMillis = wheelFrom
            add(Calendar.DAY_OF_MONTH, dayWheel.value)
        }
        if (!draft.allDay) {
            val h12 = hourWheel.value % 12
            c.set(Calendar.HOUR_OF_DAY, h12 + if (ampmWheel.value == 1) 12 else 0)
            c.set(Calendar.MINUTE, minuteWheel.value * 5)
        }
        val at = c.timeInMillis
        draft = if (picking == 1) {
            // Moving the start carries the end along, keeping the length.
            val length = maxOf(draft.end - draft.start, if (draft.allDay) 86_400_000L else 900_000L)
            draft.copy(start = at, end = at + length)
        } else {
            val floor = draft.start + if (draft.allDay) 0L else 900_000L
            draft.copy(end = maxOf(if (draft.allDay) at + 86_400_000L else at, floor))
        }
        render()
    }

    private fun allDayChanged(on: Boolean) {
        if (on == draft.allDay) return
        val day = CalendarText.startOfDay(draft.start)
        draft = if (on) {
            draft.copy(allDay = true, start = day, end = day + 86_400_000L)
        } else {
            val nine = day + 9 * 3_600_000L
            draft.copy(allDay = false, start = nine, end = nine + 3_600_000L)
        }
        render()
    }

    // MARK: render

    private fun render() {
        val stripOn = editing != null
        column.visibility = if (stripOn) GONE else VISIBLE
        rows.visibility = if (picking == 0) VISIBLE else GONE
        note.visibility = if (picking == 0 && !canAdd) VISIBLE else GONE
        wheels.visibility = if (picking != 0) VISIBLE else GONE
        strip.visibility = if (stripOn) VISIBLE else GONE
        tag(stripField, if (editing == Field.INVITEES) "event:invitees:field" else "event:title:field")

        heading.text = when (picking) { 1 -> "Starts"; 2 -> "Ends"; else -> "New Event" }
        cancel.visibility = if (picking != 0) INVISIBLE else VISIBLE
        add.text = if (picking != 0) "Done" else "Add"
        tag(add, if (picking != 0) "event:done" else "event:add")
        add.alpha = if (picking != 0 || canAdd) 1f else 0.4f
        hourWheel.visibility = if (draft.allDay) GONE else VISIBLE
        minuteWheel.visibility = if (draft.allDay) GONE else VISIBLE
        ampmWheel.visibility = if (draft.allDay) GONE else VISIBLE

        val title = draft.title.trim()
        titleValue.text = title.ifEmpty { "Title" }
        titleValue.setTextColor(if (title.isEmpty()) soft(120) else palette.ink)
        val invitees = draft.invitees
        inviteValue.text = when (invitees.size) {
            0 -> "None"
            1 -> invitees[0]
            else -> "${invitees[0]} and ${invitees.size - 1} more"
        }
        inviteValue.setTextColor(if (invitees.isEmpty()) soft(120) else palette.ink)
        stripTextView.text = stripText
        stripTextView.hint = if (editing == Field.INVITEES) "Emails, with spaces between" else "Title"
        stripTextView.setHintTextColor(soft(110))

        val sameDay = CalendarText.startOfDay(draft.start) ==
            CalendarText.startOfDay(if (draft.allDay) draft.end - 1 else draft.end)
        startDate.text = CalendarText.dayLabel(draft.start)
        startTime.text = CalendarText.clock(draft.start)
        endDate.text = CalendarText.dayLabel(if (draft.allDay) draft.end - 1 else draft.end)
        endTime.text = CalendarText.clock(draft.end)
        startTime.visibility = if (draft.allDay) GONE else VISIBLE
        endTime.visibility = if (draft.allDay) GONE else VISIBLE
        endDate.visibility = if (sameDay && !draft.allDay) GONE else VISIBLE
        if (allDay.isChecked != draft.allDay) allDay.isChecked = draft.allDay
        if (video.isChecked != draft.videoCall) video.isChecked = draft.videoCall
        if (share.isChecked != draft.share) share.isChecked = draft.share
        hint.text = when {
            editing == Field.INVITEES && invitees.isEmpty() -> "Google emails each one the invite"
            editing == Field.INVITEES -> "Invite ${invitees.joinToString(", ")}"
            draft.allDay -> CalendarText.dayLabel(draft.start)
            else -> "${CalendarText.dayLabel(draft.start)}, ${CalendarText.range(draft.start, draft.end)}"
        }
    }
}
