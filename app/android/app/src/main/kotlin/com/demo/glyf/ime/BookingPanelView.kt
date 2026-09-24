package com.demo.glyf.ime

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Book a time, the twin of BookingSheet.swift: the day's open times on a
 * Cal.com page, as pills. Tapping one asks who it is for, one line with a
 * name, an email and any guests' emails ("Sam Lee sam@x.com ria@y.com"), then
 * books it through Cal.com, which emails everyone the invite. "Send the link"
 * puts the page, or the time on it, in the message instead. Calendly shares
 * times only with the host's own sign-in, so it offers the page on that day.
 *
 * `mine` is the person's own page (from the app): the who is the other
 * person. Someone else's page (a link in the chat) starts from the person's
 * own name and email in the vault.
 */
class BookingPanelView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    private val backendURL: String,
    private val link: String,
    startDay: Long,
    private val mine: Boolean,
    me: String,
    private val onBack: () -> Unit,
    private val onInsert: (String) -> Unit,
    /** true: the who is being typed, the keys should come up under a strip. */
    private val onEditWho: (Boolean) -> Unit,
) : FrameLayout(ctx), StripField {

    private var day = CalendarText.startOfDay(startDay)
    private var pageURL: String? = null
    private var request = 0
    private var picked: SchedulingClient.Slot? = null
    private var who = if (mine) "" else me
    var editingWho = false
        private set
    private var whoDraft = ""

    private val accent = Color.rgb(0x7C, 0x5C, 0xFF)
    private fun dp(v: Float) = v * resources.displayMetrics.density
    private fun dpi(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun soft(alpha: Int) =
        Color.argb(alpha, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink))

    private val column = LinearLayout(ctx)
    private val title = TextView(ctx)
    private val dayLabel = TextView(ctx)
    private val prev = TextView(ctx)
    private val next = TextView(ctx)
    private val grid = GridLayout(ctx)
    private val gridScroll = ScrollView(ctx)
    private val status = TextView(ctx)
    private val spinner = ProgressBar(ctx)
    private val whoCard = LinearLayout(ctx)
    private val whoValue = TextView(ctx)
    private val note = TextView(ctx)
    private val linkButton = TextView(ctx)
    private val bookButton = TextView(ctx)
    private val strip = LinearLayout(ctx)
    private val stripTextView = TextView(ctx)
    private val stripHint = TextView(ctx)

    init {
        column.orientation = LinearLayout.VERTICAL
        val header = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        header.addView(TextView(ctx).apply {
            text = "‹"; textSize = 22f; setTextColor(palette.ink); gravity = Gravity.CENTER
            setPadding(dpi(14), 0, dpi(10), dpi(2))
            tag(this, "booking:back"); contentDescription = "Back"
            setOnClickListener { back() }
        })
        title.apply { textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.ink); maxLines = 1 }
        header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        dayLabel.apply { textSize = 13f; setTextColor(soft(150)) }
        header.addView(dayLabel)
        for ((v, label, id, step) in listOf(Quad(prev, "‹", "booking:prev", -1), Quad(next, "›", "booking:next", 1))) {
            v.apply {
                text = label; textSize = 20f; setTextColor(palette.ink); gravity = Gravity.CENTER
                setPadding(dpi(10), 0, dpi(10), dpi(2))
                tag(this, id)
                setOnClickListener { step(step) }
            }
            header.addView(v)
        }
        column.addView(header, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(40)))

        // The times, four to a row.
        val body = FrameLayout(ctx)
        grid.columnCount = 4
        gridScroll.isVerticalScrollBarEnabled = false
        gridScroll.addView(grid)
        body.addView(gridScroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        status.apply { textSize = 14f; setTextColor(soft(150)); gravity = Gravity.CENTER; tag(this, "booking:status") }
        body.addView(status, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        body.addView(spinner, LayoutParams(dpi(28), dpi(28), Gravity.CENTER))

        // Who, once a time is picked.
        whoCard.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(14), 0, dpi(14), 0)
            background = GradientDrawable().apply { cornerRadius = dp(12f); setColor(palette.card) }
            tag(this, "booking:who")
            setOnClickListener { beginWho() }
            addView(TextView(ctx).apply { text = if (mine) "For" else "You"; textSize = 16f; setTextColor(palette.ink) },
                LinearLayout.LayoutParams(dpi(56), LinearLayout.LayoutParams.WRAP_CONTENT))
            whoValue.apply { textSize = 15f; gravity = Gravity.END; maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.START }
            addView(whoValue, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }
        val confirm = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        confirm.addView(whoCard, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(44)))
        note.apply { textSize = 13f; setTextColor(soft(150)); setPadding(dpi(4), dpi(6), dpi(4), 0); tag(this, "booking:note") }
        confirm.addView(note)
        body.addView(confirm, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        column.addView(body, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            .apply { leftMargin = dpi(12); rightMargin = dpi(12) })

        val actions = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        for ((b, id, filled) in listOf(Triple(linkButton, "booking:link", false), Triple(bookButton, "booking:book", true))) {
            b.apply {
                textSize = 14f; typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
                setTextColor(if (filled) Color.WHITE else palette.ink)
                background = GradientDrawable().apply { cornerRadius = dp(19f); setColor(if (filled) accent else palette.card) }
                tag(this, id)
            }
            actions.addView(b, LinearLayout.LayoutParams(0, dpi(38), 1f).apply { if (filled) leftMargin = dpi(8) })
        }
        linkButton.setOnClickListener { sendLink() }
        bookButton.text = "Book it"
        bookButton.setOnClickListener { book() }
        column.addView(actions, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(38))
            .apply { leftMargin = dpi(12); rightMargin = dpi(12); bottomMargin = dpi(8); topMargin = dpi(4) })
        addView(column, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        // The strip while the who is typed.
        strip.orientation = LinearLayout.VERTICAL
        strip.visibility = GONE
        val stripRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        stripRow.addView(TextView(ctx).apply {
            text = "Cancel"; textSize = 15f; setTextColor(accent)
            setPadding(dpi(12), dpi(6), dpi(8), dpi(6))
            setOnClickListener { endWho(keep = false) }
        })
        val field = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(10), 0, dpi(10), 0)
            background = GradientDrawable().apply { cornerRadius = dp(10f); setColor(palette.card) }
            tag(this, "booking:who:field")
        }
        stripTextView.apply {
            textSize = 15f; setTextColor(palette.ink); maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.START
            hint = "Name and email, then guests"; setHintTextColor(soft(110))
        }
        field.addView(stripTextView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        field.addView(View(ctx).apply { setBackgroundColor(accent) }, LinearLayout.LayoutParams(dpi(2), dpi(20)).apply { leftMargin = dpi(1) })
        stripRow.addView(field, LinearLayout.LayoutParams(0, dpi(38), 1f))
        stripRow.addView(TextView(ctx).apply {
            text = "Done"; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(accent)
            setPadding(dpi(10), dpi(6), dpi(12), dpi(6))
            tag(this, "booking:who:done")
            setOnClickListener { endWho() }
        })
        strip.addView(stripRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(50)))
        stripHint.apply { textSize = 13f; setTextColor(soft(150)); setPadding(dpi(84), 0, dpi(12), 0); tag(this, "booking:who:hint") }
        strip.addView(stripHint)
        addView(strip, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        load()
    }

    private data class Quad(val v: TextView, val label: String, val id: String, val step: Int)

    private fun tag(v: View, id: String) = v.setTag(com.demo.glyf.R.id.qa_id, id)

    // MARK: behaviour

    private fun back() {
        if (picked != null) { picked = null; note.text = ""; render(); return }
        onBack()
    }

    private fun step(n: Int) {
        val d = Calendar.getInstance().apply { timeInMillis = day; add(Calendar.DAY_OF_MONTH, n) }.timeInMillis
        // Nothing to book in the past.
        if (d < CalendarText.startOfDay(System.currentTimeMillis())) return
        day = d
        load()
    }

    private fun iso(ms: Long) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(ms)

    private fun load() {
        picked = null
        grid.removeAllViews()
        status.text = ""
        spinner.visibility = VISIBLE
        // A later day's answer wins over an earlier one still on its way.
        val ticket = ++request
        render()
        SchedulingClient.slots(backendURL, link, iso(day)) { result, error ->
            if (ticket != request) return@slots
            spinner.visibility = GONE
            if (result == null) {
                status.text = error ?: "Couldn't reach the booking page"
                render(); return@slots
            }
            pageURL = result.bookingUrl
            if (result.provider != "calcom") {
                status.text = "Calendly shows times only on its own page. Send the link for this day."
                render(); return@slots
            }
            val now = System.currentTimeMillis()
            val open = result.days.firstOrNull { it.date == iso(day) }?.slots?.filter { it.start > now }.orEmpty()
            if (open.isEmpty()) status.text = "Nothing open this day"
            val cellW = ((width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels) - dpi(24) - dpi(8) * 3) / 4
            for ((i, slot) in open.withIndex()) {
                grid.addView(TextView(context).apply {
                    text = CalendarText.clock(slot.start); textSize = 15f; gravity = Gravity.CENTER
                    setTextColor(palette.ink)
                    background = GradientDrawable().apply { cornerRadius = dp(10f); setColor(palette.card) }
                    tag(this, "booking:slot:$i")
                    setOnClickListener { pick(slot) }
                }, GridLayout.LayoutParams().apply {
                    width = cellW; height = dpi(36)
                    setMargins(0, 0, if (i % 4 == 3) 0 else dpi(8), dpi(8))
                })
            }
            render()
        }
    }

    private fun pick(slot: SchedulingClient.Slot) {
        picked = slot
        note.text = "Cal.com emails the invite to everyone."
        render()
        // Nobody to book for yet: straight to typing who.
        if (EventParse.people(who).second.isEmpty()) beginWho()
    }

    private fun beginWho() {
        if (editingWho) return
        editingWho = true
        whoDraft = who
        render()
        onEditWho(true)
    }

    fun endWho(keep: Boolean = true) {
        if (!editingWho) return
        if (keep) who = whoDraft.trim()
        editingWho = false
        render()
        onEditWho(false)
    }

    override val stripText: String get() = whoDraft
    override fun setStripText(text: String) { whoDraft = text; render() }
    override fun endStrip() = endWho()

    /** "Sam Lee · sam@x.com · 1 guest". */
    private fun summary(line: String): String? {
        val (name, emails) = EventParse.people(line)
        val first = emails.firstOrNull() ?: return if (name.isEmpty()) null else "$name · add an email"
        val parts = mutableListOf(name, first).filter { it.isNotEmpty() }.toMutableList()
        val guests = emails.size - 1
        if (guests > 0) parts += if (guests == 1) "1 guest" else "$guests guests"
        return parts.joinToString(" · ")
    }

    private fun sendLink() {
        val p = picked
        if (p != null) {
            onInsert("How about ${CalendarText.dayLabel(p.start)} at ${CalendarText.clock(p.start)}? Book it here: ${p.url}")
            return
        }
        val page = pageURL ?: if (link.startsWith("http")) link else "https://$link"
        onInsert("Pick a time that works for you: $page")
    }

    private fun book() {
        val p = picked ?: return
        if (editingWho) endWho()
        val (name0, emails) = EventParse.people(who)
        val email = emails.firstOrNull()
        if (email == null) {
            note.text = if (mine) "Add their email to book it." else "Add your email to book it."
            beginWho(); return
        }
        val name = name0.ifEmpty { email.substringBefore("@") }
        bookButton.isEnabled = false
        bookButton.text = "Booking…"
        SchedulingClient.book(backendURL, link, p.start, name, email, emails.drop(1)) { booked, error ->
            bookButton.isEnabled = true
            bookButton.text = "Book it"
            if (booked == null) { note.text = error ?: "Couldn't book it. Try again"; return@book }
            val at = booked.start ?: p.start
            val people = booked.invited.ifEmpty { emails }
            val list = if (people.size > 1) people.dropLast(1).joinToString(", ") + " and " + people.last() else people.first()
            var line = "Booked for ${CalendarText.dayLabel(at)}, ${CalendarText.clock(at)}. The invite is on its way to $list."
            booked.meetingUrl?.let { line += " Call: $it" }
            onInsert(line)
        }
    }

    // MARK: render

    private fun render() {
        val p = picked
        column.visibility = if (editingWho) GONE else VISIBLE
        strip.visibility = if (editingWho) VISIBLE else GONE
        title.text = if (p != null) "${CalendarText.dayLabel(p.start)} · ${CalendarText.clock(p.start)}" else "Book a time"
        dayLabel.text = CalendarText.dayLabel(day)
        val confirming = p != null
        for (v in listOf(dayLabel, prev, next)) v.visibility = if (confirming) GONE else VISIBLE
        prev.alpha = if (day > CalendarText.startOfDay(System.currentTimeMillis())) 1f else 0.3f
        gridScroll.visibility = if (confirming) GONE else VISIBLE
        status.visibility = if (confirming || status.text.isNullOrEmpty()) GONE else VISIBLE
        if (confirming) spinner.visibility = GONE
        (whoCard.parent as View).visibility = if (confirming) VISIBLE else GONE
        bookButton.visibility = if (confirming) VISIBLE else GONE
        linkButton.text = if (confirming) "Send the link" else "Send my link"
        val s = summary(who)
        whoValue.text = s ?: if (mine) "Their name and email" else "Your name and email"
        whoValue.setTextColor(if (s == null) soft(120) else palette.ink)
        stripTextView.text = whoDraft
        stripHint.text = summary(whoDraft) ?: if (mine) "Their name and email, then any guests"
            else "Your name and email, then any guests"
    }
}
