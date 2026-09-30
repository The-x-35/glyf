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
 * the grid to jump to another day. + makes an event (in Google Calendar,
 * which emails the invitees, when Google is connected; with a call link if
 * asked; into the message if shared), the camera puts a call link in the
 * message, and Book a time shows the open times on the person's Cal.com page.
 * Holding an event opens the clipboard's kind of menu: Edit (the composer,
 * as Edit Event) and Delete.
 */
class CalendarPanelView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    private val onInsert: (String) -> Unit,
    private val onClose: () -> Unit,
    private val onConnect: () -> Unit,
    /** A field is being typed (true) or done (false): the letter keys come
     *  up under a strip while it is. */
    private val onTitleEditing: (Boolean) -> Unit = {},
    private val backendURL: String = "",
    /** The person's own Cal.com or Calendly page, set in the app. */
    private val bookingLink: String? = null,
) : FrameLayout(ctx) {

    private val accent = Color.rgb(0x7C, 0x5C, 0xFF)
    private val connected = CalendarText.connected(ctx)
    /** New Event, while it is open. */
    var composer: EventComposerView? = null
        private set
    /** Book a time, while it is open. */
    var booking: BookingPanelView? = null
        private set
    /** Whatever is taking the keys: New Event's title or invitees, or who a
     *  booking is for. */
    val typing: StripField?
        get() = composer?.takeIf { it.editingTitle } ?: booking?.takeIf { it.editingWho }
    private val panelBody = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
    /** The event just added, lit for a moment in the day's list. */
    private var justAdded: CalendarText.Event? = null
    /** Its row, so the light can go out without rebuilding the list. */
    private var litRow: View? = null
    /** Add was tapped and the call link is on its way: once is enough. */
    private var adding = false
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
    private val actions = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }

    private fun dp(v: Float) = v * resources.displayMetrics.density
    private fun dpi(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun soft(alpha: Int) =
        Color.argb(alpha, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink))

    /** Google's list for the window on screen, once it has answered; the
     *  window it covers, so month steps only refetch when they leave it. */
    private var googleFetched: List<CalendarText.Event>? = null
    private var googleWindow: Pair<Long, Long>? = null
    /** How the last ask went, said under the day's events. */
    private var googleNote: String? = null
    private fun primary() = com.demo.glyf.store.GoogleAccess.load(context)?.email

    /** The hold menu, over a scrim like the clipboard's. */
    private val scrim = View(ctx).apply {
        setBackgroundColor(Glass.scrim)
        visibility = GONE
        setTag(com.demo.glyf.R.id.qa_id, "calendar:scrim")
        setOnClickListener { dismissMenu() }
    }
    private var menu: View? = null
    /** Deleted here: kept off the list while the phone's own copy catches up. */
    private val gone = mutableSetOf<String>()

    init {
        // Google connected: its last answer for THIS account at once, then
        // ask again; the phone's own calendars show from the start.
        if (com.demo.glyf.store.GoogleAccess.hasCalendar(ctx)) {
            val email = primary()
            googleFetched = GoogleCache.load(ctx, email)
            googleNote = "Google Calendar" + (email?.let { " · $it" } ?: "") + " · syncing…"
        }
        loadEvents()
        val root = panelBody
        // The strip names the panel (✕, the calendar's mark, "Calendar"), as
        // on iOS: the panel spends no row on a header of its own.
        // The day (or the month, on the grid), with the way to the other.
        val dayRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(12), 0, dpi(12), 0)
        }
        title.apply { Glass.style(this, 15f, Glass.SEMIBOLD); maxLines = 1 }
        dayRow.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        dayRow.addView(arrow("chevron", "calendar:prev") { step(-1) })
        dayRow.addView(arrow("chevronright", "calendar:next") { step(1) })
        modeButton.apply {
            Glass.style(this, 13f, Glass.SEMIBOLD)
            gravity = Gravity.CENTER
            background = Glass.pill(Glass.surfaceCard)
            setTag(com.demo.glyf.R.id.qa_id, "calendar:month")
            setOnClickListener { toggleMonth() }
        }
        dayRow.addView(modeButton, LinearLayout.LayoutParams(dpi(76), dpi(30)).apply { leftMargin = dpi(6) })
        // A call link for the chat, without making an event.
        dayRow.addView(FrameLayout(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Glass.surfaceCard) }
            setTag(com.demo.glyf.R.id.qa_id, "calendar:call"); contentDescription = "Send a call link"
            addView(ToolIcon(ctx, "video", Glass.textPrimary).apply { solid = true; weight = 2f; scale = 0.78f },
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            setOnClickListener { v -> insertCallLink(v) }
        }, LinearLayout.LayoutParams(dpi(30), dpi(30)).apply { leftMargin = dpi(6) })
        // Calendar's own + for a new event, at the end of the row.
        dayRow.addView(FrameLayout(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Glass.surfaceCard) }
            setTag(com.demo.glyf.R.id.qa_id, "calendar:new"); contentDescription = "New event"
            addView(ToolIcon(ctx, "plus", Glass.textPrimary).apply { solid = true; weight = 2f; scale = 0.8f },
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            setOnClickListener { compose(null) }
        }, LinearLayout.LayoutParams(dpi(30), dpi(30)).apply { leftMargin = dpi(6) })
        root.addView(dayRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(40)))

        // One space, holding either the events or the month.
        val body = FrameLayout(ctx)
        agendaScroll.apply { isVerticalScrollBarEnabled = false; addView(agenda) }
        agenda.setPadding(dpi(12), dpi(4), dpi(12), dpi(4))
        body.addView(agendaScroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        body.addView(grid, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply {
            leftMargin = dpi(10); rightMargin = dpi(10); bottomMargin = dpi(6)
        })
        root.addView(body, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        // The day itself is the thing people most often type: "September 30".
        actions.addView(TextView(ctx).apply {
            text = "Insert date"
            Glass.style(this, 13f, Glass.SEMIBOLD)
            gravity = Gravity.CENTER
            background = Glass.pill(Glass.surfaceCard)
            setTag(com.demo.glyf.R.id.qa_id, "calendar:date")
            setOnClickListener { onInsert(dateText(selected)) }
        }, LinearLayout.LayoutParams(0, dpi(38), 1f))
        action.apply {
            text = if (connected) "Share free time" else "Allow Calendar in Settings"
            Glass.style(this, 13f, Glass.SEMIBOLD, Color.WHITE)
            gravity = Gravity.CENTER
            maxLines = 1
            background = Glass.pill(accent)
            setTag(com.demo.glyf.R.id.qa_id, if (connected) "calendar:free" else "calendar:connect")
            setOnClickListener {
                if (connected) onInsert(CalendarText.freeTime(selected, events)) else onConnect()
            }
        }
        actions.addView(action, LinearLayout.LayoutParams(0, dpi(38), 1f).apply { leftMargin = dpi(8) })
        // The person's own booking page, when the app has one.
        if (bookingLink != null) {
            actions.addView(TextView(ctx).apply {
                text = "Book a time"
                Glass.style(this, 13f, Glass.SEMIBOLD)
                gravity = Gravity.CENTER
                background = Glass.pill(Glass.surfaceCard)
                setTag(com.demo.glyf.R.id.qa_id, "calendar:book")
                setOnClickListener { openBooking() }
            }, LinearLayout.LayoutParams(0, dpi(38), 1f).apply { leftMargin = dpi(8) })
        }
        root.addView(actions, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(38)).apply {
            leftMargin = dpi(12); rightMargin = dpi(12); bottomMargin = dpi(8); topMargin = dpi(4)
        })

        addView(root, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(scrim, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        render()
    }

    /** New Event, filled from a plan when there is one ("dinner friday 8pm"),
     *  else the chosen day at the next hour (9 AM on another day). */
    fun compose(plan: EventParse.Plan?) {
        val draft = if (plan != null) {
            // The plan is in the message already: nothing more goes in. Its
            // day is the calendar's, so Cancel shows what else is on then.
            show(plan.start)
            loadEvents()
            EventComposerView.Draft(plan.title, plan.start, plan.end, plan.allDay)
        } else {
            val now = System.currentTimeMillis()
            val start = if (selected == CalendarText.startOfDay(now)) {
                Calendar.getInstance().apply {
                    timeInMillis = now; set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0); add(Calendar.HOUR_OF_DAY, 1)
                }.timeInMillis
            } else selected + 9 * 3_600_000L
            // Made from the calendar in a chat, it is most often for the person
            // the chat is with: it goes into the message once added.
            EventComposerView.Draft("", start, start + 3_600_000L, false, share = true)
        }
        present(draft, CalendarText.canAdd(context), edit = false) { add(it) }
    }

    /** New Event or Edit Event over the calendar; [onSave] gets the event
     *  Add (or Save) was tapped on. */
    private fun present(draft: EventComposerView.Draft, canAdd: Boolean, edit: Boolean,
                        onSave: (EventComposerView.Draft) -> Unit) {
        dismissMenu()
        composer?.let { removeView(it) }
        val c = EventComposerView(context, palette, draft, canAdd,
            google = com.demo.glyf.store.GoogleAccess.hasCalendar(context),
            meet = com.demo.glyf.store.GoogleAccess.hasCalendar(context) ||
                com.demo.glyf.store.GoogleAccess.hasMeet(context),
            onCancel = { closeComposer() },
            onAdd = onSave,
            onEditTitle = { editing -> onTitleEditing(editing) },
            onConnect = onConnect,
            edit = edit,
        )
        addView(c, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        composer = c
        panelBody.visibility = View.INVISIBLE
    }

    private fun closeComposer() {
        val wasEditing = composer?.editingTitle == true
        composer?.let { removeView(it) }
        composer = null
        panelBody.visibility = View.VISIBLE
        if (wasEditing) onTitleEditing(false)
        render()
    }

    /** Book a time on the person's own page, or on someone else's (a link in
     *  the chat): then it starts from their own name and email in the vault. */
    fun openBooking(other: String? = null) {
        val link = other ?: bookingLink ?: return
        if (composer != null) closeComposer()
        closeBooking()
        val (name, email) = me()
        val b = BookingPanelView(context, palette, backendURL, link, selected, mine = other == null,
            me = listOfNotNull(name, email).joinToString(" "),
            onBack = { closeBooking() },
            onInsert = onInsert,
            onEditWho = { editing -> onTitleEditing(editing) },
        )
        addView(b, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        booking = b
        panelBody.visibility = View.INVISIBLE
    }

    private fun closeBooking() {
        val b = booking ?: return
        val wasEditing = b.editingWho
        removeView(b)
        booking = null
        panelBody.visibility = View.VISIBLE
        if (wasEditing) onTitleEditing(false)
        render()
    }

    /** The person's name and email, from the vault. */
    private fun me(): Pair<String?, String?> {
        val fields = Smart.fields(com.demo.glyf.store.VaultStore.load(context))
        return fields.firstOrNull { it.kind == "name" }?.value to fields.firstOrNull { it.kind == "email" }?.value
    }

    /** The person's own Google Meet link, straight into the message. Without
     *  Google connected the calendar stays open and says how to get one. */
    private fun insertCallLink(button: View) {
        button.isEnabled = false
        CallLink.make(context) { url, note ->
            button.isEnabled = true
            if (url != null) deliver("Join me on a call: $url") else note?.let { toast(it) }
        }
    }

    /** An answer that came back from Google or Cal.com goes in only while
     *  this panel is still up: closed, or the field changed, it is dropped. */
    private fun deliver(text: String) {
        if (isAttachedToWindow) onInsert(text)
    }

    /** "sam@x.com", "sam@x.com and ria@y.com", "sam@x.com and 2 others". */
    private fun people(emails: List<String>): String = when (emails.size) {
        0 -> ""
        1 -> emails[0]
        2 -> "${emails[0]} and ${emails[1]}"
        else -> "${emails[0]} and ${emails.size - 1} others"
    }

    private fun toast(text: String) =
        (context as? GlyfIME)?.notice(text) ?: android.widget.Toast.makeText(context, text, android.widget.Toast.LENGTH_SHORT).show()

    /** With Google Calendar connected the event goes there, where Google
     *  emails the invitees and makes the Meet call; otherwise the phone's
     *  calendar takes it. Either way Share in chat puts it in the message. */
    private fun add(d: EventComposerView.Draft) {
        if (adding) return
        adding = true
        if (!com.demo.glyf.store.GoogleAccess.hasCalendar(context)) return saveHere(d, null)
        GoogleClient.addEvent(context, d.title, d.start, d.end, d.allDay, d.invitees, d.videoCall) { added, failure ->
            if (added != null) {
                adding = false
                addedToGoogle(d, added)
            } else {
                // Not lost: the phone's calendar takes it, and the toast says
                // why Google didn't (and so nobody was emailed).
                saveHere(d, GoogleClient.say(failure ?: GoogleClient.Failure.REFUSED))
            }
        }
    }

    private fun saveHere(d: EventComposerView.Draft, note: String?) {
        if (!d.videoCall) {
            adding = false
            return save(d, null, note)
        }
        // The Meet link first, so the event carries it and so does the message.
        CallLink.make(context) { url, meetNote ->
            adding = false
            save(d, url, note ?: meetNote)
        }
    }

    private fun addedToGoogle(d: EventComposerView.Draft, added: GoogleClient.Added) {
        val said = if (d.invitees.isEmpty()) "Added to Google Calendar"
            else "Added. Google emailed the invite to ${people(d.invitees)}"
        val event = CalendarText.Event(d.title, d.start, d.end, d.allDay, location = added.meet, googleId = added.id)
        // The phone's calendar gets it on Google's next sync; until then the
        // keyboard's list shows it anyway.
        GoogleAdded.remember(context, event)
        if (d.share) {
            closeComposer()
            deliver(CalendarText.insert(event))
            toast(said)
            return
        }
        show(d.start)
        justAdded = event
        closeComposer()
        loadEvents()
        render()
        toast(said)
        unlightLater()
    }

    /** The list on [day]: where a plan is for, and where an event lands once added. */
    private fun show(day: Long) {
        selected = CalendarText.startOfDay(day)
        month = Calendar.getInstance().apply {
            timeInMillis = selected; set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        showingMonth = false
    }

    /** By its id, or, once the phone's own copy has replaced the keyboard's,
     *  by what it is and when. */
    private fun isJustAdded(e: CalendarText.Event): Boolean {
        val a = justAdded ?: return false
        return (a.id != null && a.id == e.id) || (a.googleId != null && a.googleId == e.googleId) ||
            (a.title == e.title && a.start == e.start)
    }

    private fun unlightLater() = postDelayed({
        justAdded = null
        (litRow?.background as? GradientDrawable)?.setStroke(0, Color.TRANSPARENT)
        litRow = null
    }, 2500)

    private fun save(d: EventComposerView.Draft, callLink: String?, note: String?) {
        val added = CalendarText.add(context, d.title, d.start, d.end, d.allDay,
            location = callLink, notes = callLink?.let { "Join the call: $it" })
        if (added == null) {
            toast("Couldn't add the event. Try again")
            return
        }
        val said = "Added to ${added.second}" + (note?.let { ". $it" } ?: "")
        if (d.share) {
            closeComposer()
            deliver(CalendarText.insert(added.first))
            toast(said)
            return
        }
        show(d.start)
        justAdded = added.first
        closeComposer()
        loadEvents()
        render()
        toast(said)
        unlightLater()
    }

    private fun arrow(glyph: String, id: String, onTap: () -> Unit) =
        ToolIcon(context, glyph, Glass.textPrimary).apply {
            solid = true; weight = 2.2f; scale = 0.82f
            setTag(com.demo.glyf.R.id.qa_id, id)
            contentDescription = if (glyph == "chevron") "Previous" else "Next"
            setOnClickListener { onTap() }
            layoutParams = LinearLayout.LayoutParams(dpi(34), dpi(34))
        }

    /** "September 30", in the phone's own order for month and day (iOS). */
    private fun dateText(day: Long): String = SimpleDateFormat(
        android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMMd"),
        Locale.getDefault()).format(java.util.Date(day))


    private fun loadEvents() {
        val from = (month.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -7) }.timeInMillis
        val to = (month.clone() as Calendar).apply { add(Calendar.MONTH, 1); add(Calendar.DAY_OF_MONTH, 7) }.timeInMillis
        // Google connected: that account's calendar, live from Google, over
        // the phone's own calendars; the phone's (possibly stale) copy of
        // that same account gives way, so nothing shows twice or late.
        val phone = CalendarText.load(context, from, to)
        val google = googleFetched
        val base = if (google != null && com.demo.glyf.store.GoogleAccess.hasCalendar(context))
            CalendarText.withGoogle(google, phone, primary = primary()) else phone
        events = GoogleAdded.merged(context, base).filterNot(::isGone)
        refreshGoogle(from, to)
    }

    /** Asks Google for the window: the phone only has what it synced. */
    private fun refreshGoogle(from: Long, to: Long) {
        if (!com.demo.glyf.store.GoogleAccess.hasCalendar(context)) return
        googleWindow?.let { if (it.first <= from && it.second >= to) return }
        GoogleClient.listEvents(context, from, to) { list, failure ->
            val email = primary()
            if (list == null) {
                // Nothing new: its last answer when there is one, else the
                // phone's own calendar, and the note says which.
                googleNote = "Google Calendar didn't sync: " + GoogleClient.say(failure ?: GoogleClient.Failure.REFUSED) +
                    if (googleFetched != null) ". Showing the last sync" else ""
            } else {
                googleWindow = from to to
                googleFetched = list
                GoogleCache.save(context, list, email)
                googleNote = "Google Calendar" + (email?.let { " · $it" } ?: "") + " · updated " +
                    java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date())
            }
            val phone = CalendarText.load(context, from, to)
            val google = googleFetched
            val base = if (google != null) CalendarText.withGoogle(google, phone, primary = primary()) else phone
            events = GoogleAdded.merged(context, base).filterNot(::isGone)
            render()
        }
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
        modeButton.layoutParams = (modeButton.layoutParams as LinearLayout.LayoutParams).apply {
            width = dpi(if (showingMonth) 66 else 76)
        }
        modeButton.contentDescription = if (showingMonth) "Close the month" else "Open the month"
        grid.visibility = if (showingMonth) View.VISIBLE else View.GONE
        agendaScroll.visibility = if (showingMonth) View.GONE else View.VISIBLE
        actions.visibility = if (showingMonth) View.GONE else View.VISIBLE
        grid.invalidate()

        agenda.removeAllViews()
        litRow = null
        // Google's list shows even without the phone's calendar permission.
        if ((!connected && googleFetched == null) || showingMonth) return
        val day = CalendarText.on(selected, events)
        if (day.isEmpty()) {
            agenda.addView(TextView(context).apply {
                text = "Nothing planned"
                Glass.style(this, 14f, Glass.REGULAR, Glass.textSecondary)
                gravity = Gravity.CENTER_VERTICAL
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(40)))
        }
        for ((i, e) in day.withIndex()) {
            val row = eventRow(e, i)
            agenda.addView(row, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { bottomMargin = dpi(8) })
            if (isJustAdded(e)) {
                litRow = row
                // Said as well as shown, until the list is next drawn.
                if (android.os.Build.VERSION.SDK_INT >= 30) row.stateDescription = "Just added"
                // Into view once laid out, the way Calendar shows a new event.
                agendaScroll.post { agendaScroll.smoothScrollTo(0, maxOf(0, row.top - dpi(4))) }
            }
        }
        googleNote?.let { said ->
            agenda.addView(TextView(context).apply {
                text = said
                Glass.style(this, 12f, Glass.REGULAR, Glass.textSecondary)
                maxLines = 2
                setPadding(dpi(2), dpi(4), 0, 0)
                setTag(com.demo.glyf.R.id.qa_id, "calendar:google")
            })
        }
    }

    private fun eventRow(e: CalendarText.Event, index: Int): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(10), dpi(10), dpi(12), dpi(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(12f); setColor(Glass.surfaceCard)
                // What was just added, lit for a moment so the eye finds it.
                if (isJustAdded(e)) setStroke(dpi(2), accent)
            }
            setTag(com.demo.glyf.R.id.qa_id, "calendar:event:$index")
            contentDescription = CalendarText.insert(e)
            setOnClickListener { onInsert(CalendarText.insert(e)) }
            setOnLongClickListener { v -> holdMenu(e, v); true }
        }
        row.addView(View(context).apply {
            background = GradientDrawable().apply { cornerRadius = dp(2f); setColor(e.color ?: accent) }
        }, LinearLayout.LayoutParams(dpi(4), dpi(34)).apply { rightMargin = dpi(10) })

        val time = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        time.addView(TextView(context).apply {
            text = if (e.allDay) "All day" else CalendarText.clock(e.start)
            Glass.style(this, if (e.allDay) 13f else 14f, Glass.SEMIBOLD)
            maxLines = 1
        })
        if (!e.allDay) {
            time.addView(TextView(context).apply {
                text = CalendarText.clock(e.end)
                Glass.style(this, 12f, Glass.REGULAR, Glass.textSecondary)
                maxLines = 1
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(2) })
        }
        row.addView(time, LinearLayout.LayoutParams(dpi(74), LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { rightMargin = dpi(8) })

        val text = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        text.addView(TextView(context).apply {
            this.text = e.title
            Glass.style(this, 15f, Glass.SEMIBOLD)
            maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
        })
        val place = e.location
        if (!place.isNullOrEmpty()) {
            text.addView(TextView(context).apply {
                this.text = place
                Glass.style(this, 12.5f, Glass.REGULAR, Glass.textSecondary)
                maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(2) })
        }
        row.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    // ---- hold menu (Edit · Delete), the clipboard's own ----------------------

    private fun goneKeys(e: CalendarText.Event): List<String> =
        // A repeating event's occurrences share their UID; the start tells them apart.
        listOfNotNull(e.googleId, e.external?.let { "$it@${e.start}" })

    private fun isGone(e: CalendarText.Event) = gone.isNotEmpty() && goneKeys(e).any { it in gone }

    /** Why the event can't be changed from the keyboard, when it can't. */
    private fun refusal(e: CalendarText.Event): String? = when {
        // Google's own are changed at Google; the rest in the phone's calendar.
        e.googleId != null -> null
        !CalendarText.canAdd(context) -> "Allow Calendar for Glyf in Settings"
        !e.writable -> "${e.calendar ?: "This calendar"} is read-only"
        else -> null
    }

    private fun holdMenu(e: CalendarText.Event, anchor: View) {
        refusal(e)?.let { return toast(it) }
        performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        popMenu(anchor, listOf(
            MenuRow("edit", "Edit", "calendar:menu:edit") { dismissMenu(); edit(e) },
            MenuRow("trash", "Delete", "calendar:menu:delete", destructive = true) { confirmDelete(e, anchor) },
        ))
    }

    /** Delete asks once more, the way Calendar does: an event can have guests. */
    private fun confirmDelete(e: CalendarText.Event, anchor: View) {
        popMenu(anchor, listOf(
            MenuRow("trash", if (e.repeats) "Delete This Event Only" else "Delete Event", "calendar:menu:confirm",
                destructive = true) { dismissMenu(); delete(e) },
            MenuRow("close", "Cancel", "calendar:menu:cancel") { dismissMenu() },
        ))
    }

    private class MenuRow(val icon: String, val label: String, val id: String,
                          val destructive: Boolean = false, val action: () -> Unit)

    /** The menu under the held event when there is room, else over it. */
    private fun popMenu(anchor: View, rows: List<MenuRow>) {
        menu?.let { removeView(it) }
        scrim.visibility = VISIBLE
        scrim.bringToFront()
        val danger = Glass.accentDanger
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            elevation = dp(10f)
            minimumWidth = dpi(176)
            background = Glass.card(context, radius = 14f)
            clipToOutline = true
        }
        for ((i, row) in rows.withIndex()) {
            if (i > 0) box.addView(View(context).apply { setBackgroundColor(Glass.strokeHairline) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, maxOf(1, dpi(1) / 2)))
            val ink = if (row.destructive) danger else Glass.textPrimary
            box.addView(TextView(context).apply {
                text = row.label
                Glass.style(this, 17f, Glass.REGULAR, ink)
                maxLines = 1
                gravity = Gravity.CENTER_VERTICAL
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    ToolIcon(context, row.icon, ink).apply { solid = true; weight = 1.45f; scale = 1.2f }
                        .asDrawable(dpi(26)), null, null, null)
                compoundDrawablePadding = dpi(14)
                setPadding(dpi(16), 0, dpi(18), 0)
                setTag(com.demo.glyf.R.id.qa_id, row.id)
                setOnClickListener { row.action() }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpi(50)))
        }
        box.measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.AT_MOST), MeasureSpec.UNSPECIFIED)
        val w = box.measuredWidth
        val h = box.measuredHeight
        val loc = IntArray(2).also { anchor.getLocationInWindow(it) }
        val mine = IntArray(2).also { getLocationInWindow(it) }
        val top = loc[1] - mine[1]
        val right = loc[0] - mine[0] + anchor.width
        val x = (right - w).coerceIn(dpi(8), maxOf(dpi(8), width - w - dpi(8)))
        var y = top + anchor.height + dpi(6)
        if (y + h > height - dpi(6)) y = top - dpi(6) - h
        y = y.coerceIn(dpi(6), maxOf(dpi(6), height - h - dpi(6)))
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

    /** Edit Event: the composer on the event's own title and times. */
    private fun edit(e: CalendarText.Event) {
        val draft = EventComposerView.Draft(e.title, e.start, e.end, e.allDay)
        // Google's own need only the network; the rest, the phone's calendar.
        present(draft, e.googleId != null || CalendarText.canAdd(context), edit = true) { saveEdit(e, it) }
    }

    private fun saveEdit(old: CalendarText.Event, d: EventComposerView.Draft) {
        if (adding) return
        val googleId = old.googleId
        if (googleId == null) {
            val (changed, failure) = CalendarText.update(context, old, d.title, d.start, d.end, d.allDay)
            if (changed != null) edited(changed) else toast(say(failure, "save"))
            return
        }
        adding = true
        GoogleClient.updateEvent(context, googleId, d.title, d.start, d.end, d.allDay) { listed, failure ->
            adding = false
            if (failure != null) return@updateEvent toast("Couldn't save it: ${GoogleClient.say(failure)}")
            val changed = listed ?: old.copy(title = d.title, start = d.start, end = d.end, allDay = d.allDay)
            googleFetched?.let { list ->
                googleFetched = list.map { if (it.googleId == googleId) changed else it }
                GoogleCache.save(context, googleFetched ?: emptyList(), primary())
            }
            GoogleAdded.forget(context, googleId, changed)
            edited(changed)
        }
    }

    private fun edited(e: CalendarText.Event) {
        show(e.start)
        justAdded = e
        closeComposer()
        loadEvents()
        render()
        toast("Saved")
        unlightLater()
    }

    private fun delete(e: CalendarText.Event) {
        val googleId = e.googleId
        if (googleId == null) {
            val failure = CalendarText.remove(context, e)
            if (failure == null || failure == CalendarText.Change.NOT_FOUND) {
                loadEvents()
                render()
            }
            toast(if (failure == null) "Event deleted" else say(failure, "delete"))
            return
        }
        // Off the list at once; back, with Google's reason, if it says no.
        val keys = goneKeys(e)
        gone += keys
        loadEvents()
        render()
        GoogleClient.deleteEvent(context, googleId) { failure ->
            if (failure == null) {
                googleFetched?.let { list ->
                    googleFetched = list.filter { it.googleId != googleId }
                    GoogleCache.save(context, googleFetched ?: emptyList(), primary())
                }
                GoogleAdded.forget(context, googleId)
                toast("Event deleted")
            } else {
                gone -= keys.toSet()
                toast("Couldn't delete it: ${GoogleClient.say(failure)}")
            }
            loadEvents()
            render()
        }
    }

    private fun say(failure: CalendarText.Change?, doing: String) = when (failure) {
        CalendarText.Change.READ_ONLY -> "This calendar is read-only"
        CalendarText.Change.NOT_FOUND -> "It's no longer in the calendar"
        else -> "Couldn't $doing it. Try again"
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
            text.typeface = Glass.font(context, Glass.SEMIBOLD)
            text.color = Glass.textSecondary
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
                    fill.color = Glass.fillSoft
                    c.drawCircle(cx, cy, r, fill)
                }
                text.textSize = dp(15f)
                text.typeface = Glass.font(context, if (isToday || isSelected) Glass.SEMIBOLD else Glass.REGULAR)
                text.color = if (isToday) Color.WHITE else Glass.textPrimary
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
