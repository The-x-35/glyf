package com.arpit.glyf.ime

import android.content.Context
import android.provider.CalendarContract
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * The phone's calendar in the keyboard, the twin of CalendarText.swift: events
 * read straight from the calendar provider (the keyboard shares the app's
 * permission), and the words it puts in a message. The formatting is pure and
 * unit tested in CalendarTextTest.
 */
object CalendarText {

    data class Event(
        val title: String,
        val start: Long,
        val end: Long,
        val allDay: Boolean,
        val location: String? = null,
        val color: Int? = null,
        /** The provider's event id, when known: the one just added is lit by it. */
        val id: Long? = null,
        /** Google's id, for an event the keyboard added to Google Calendar. */
        val googleId: String? = null,
        /** The iCalendar UID (the provider's uid2445, Google's iCalUID). */
        val external: String? = null,
        /** Who owns its calendar: the Google account's email for its own
         *  (primary) calendar. */
        val owner: String? = null,
        /** One occurrence of a repeating event: changing or deleting it
         *  touches this one only. */
        val repeats: Boolean = false,
        /** Its calendar's name, and whether this keyboard may change it
         *  (holidays, birthdays and subscriptions can't be). */
        val calendar: String? = null,
        val writable: Boolean = true,
        /** The occurrence's start as the provider keeps it (all-day ones on
         *  UTC days): what a change to one occurrence of a series names. */
        val begin: Long? = null,
    )

    /** Why a change to the phone's calendar didn't happen. */
    enum class Change { NOT_FOUND, READ_ONLY, FAILED }

    /** Events added to Google Calendar from the keyboard reach the phone's
     *  calendar only when Google next syncs it (and never on a phone without
     *  the Google account), so until the phone has one the list shows the
     *  keyboard's own copy. The phone has it once an event with the same title
     *  starts within a minute of it; one that ended over a day ago is let go.
     *  Returns the list to show and the copies still waiting. */
    /** The phone's events with Google's own list (what Google has NOW)
     *  layered in. The phone's copy of anything Google listed goes, matched
     *  by iCalendar UID, and so does everything the phone shows from the
     *  account's own calendar (`primary`, its email): Google's list is the
     *  truth there, so an event deleted or renamed on the web goes too. A
     *  same-title, same-day match catches what has no UID. Smart.swift's
     *  twin is CalendarText.withGoogle. */
    fun withGoogle(google: List<Event>, phone: List<Event>,
                   zone: java.util.TimeZone = java.util.TimeZone.getDefault(),
                   primary: String? = null): List<Event> {
        val externals = google.mapNotNull { it.external }.toSet()
        val own = primary?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        fun key(e: Event): String {
            val cal = java.util.Calendar.getInstance(zone).apply {
                timeInMillis = e.start
                set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
            }
            return e.title.trim().lowercase() + "|" + cal.timeInMillis
        }
        val googleKeys = google.map(::key).toSet()
        return phone.filter { e ->
            !(e.external != null && e.external in externals) &&
                !(own != null && e.owner?.lowercase() == own) &&
                key(e) !in googleKeys
        } + google
    }

    fun withAdded(added: List<Event>, events: List<Event>,
                  now: Long = System.currentTimeMillis()): Pair<List<Event>, List<Event>> {
        fun key(title: String) = title.trim().lowercase()
        val pending = added.filter { a ->
            a.end > now - 86_400_000L && events.none { e ->
                kotlin.math.abs(e.start - a.start) < 60_000L && key(e.title) == key(a.title)
            }
        }
        return (events + pending) to pending
    }

    fun granted(ctx: Context): Boolean =
        ctx.checkSelfPermission(android.Manifest.permission.READ_CALENDAR) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    /** Allowed. The calendar is asked for during onboarding, and after that
     *  it is Android's to allow in Settings: allowed means on. */
    fun connected(ctx: Context): Boolean = granted(ctx)

    /** Events touching [fromMs, toMs), from every calendar on the phone. */
    fun load(ctx: Context, fromMs: Long, toMs: Long): List<Event> {
        if (!connected(ctx)) return emptyList()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            android.content.ContentUris.appendId(it, fromMs)
            android.content.ContentUris.appendId(it, toMs)
        }.build()
        val cols = arrayOf(
            CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION, CalendarContract.Instances.DISPLAY_COLOR,
            CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.UID_2445,
            CalendarContract.Instances.OWNER_ACCOUNT, CalendarContract.Instances.RRULE,
            CalendarContract.Instances.RDATE, CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.CALENDAR_ACCESS_LEVEL,
        )
        val out = mutableListOf<Event>()
        runCatching {
            ctx.contentResolver.query(uri, cols, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
                while (c.moveToNext() && out.size < 1500) {
                    val allDay = c.getInt(3) == 1
                    val begin = c.getLong(1)
                    var start = begin
                    var end = c.getLong(2)
                    if (allDay) {
                        // All-day instances are stored in UTC days.
                        start = utcDayToLocal(start)
                        end = utcDayToLocal(end)
                    }
                    out += Event(
                        title = c.getString(0)?.trim().takeUnless { it.isNullOrEmpty() } ?: "Busy",
                        start = start, end = maxOf(end, start), allDay = allDay,
                        location = c.getString(4)?.takeIf { it.isNotBlank() },
                        color = if (c.isNull(5)) null else c.getInt(5),
                        id = c.getLong(6),
                        external = c.getString(7)?.takeIf { it.isNotBlank() },
                        owner = c.getString(8)?.takeIf { it.isNotBlank() },
                        repeats = !c.getString(9).isNullOrBlank() || !c.getString(10).isNullOrBlank(),
                        calendar = c.getString(11)?.takeIf { it.isNotBlank() },
                        writable = c.isNull(12) ||
                            c.getInt(12) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR,
                        begin = begin,
                    )
                }
            }
        }
        return out
    }

    /** Adding events needs the write half of the calendar permission, which
     *  installs from before New Event never asked for. */
    fun canAdd(ctx: Context): Boolean =
        connected(ctx) && ctx.checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    /** Where new events go: the phone's primary calendar people can write to,
     *  else any writable one, else a local "Glyf" calendar made once (a phone
     *  with no account, like a fresh emulator, has none). */
    fun writableCalendar(ctx: Context): Pair<Long, String>? {
        val cols = arrayOf(
            CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.IS_PRIMARY,
        )
        val where = "${CalendarContract.Calendars.VISIBLE}=1 AND " +
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=${CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR}"
        var best: Pair<Long, String>? = null
        runCatching {
            ctx.contentResolver.query(CalendarContract.Calendars.CONTENT_URI, cols, where, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val row = c.getLong(0) to (c.getString(1) ?: "Calendar")
                    if (best == null || c.getInt(2) == 1) best = row
                    if (c.getInt(2) == 1) break
                }
            }
        }
        return best ?: makeLocalCalendar(ctx)
    }

    private fun makeLocalCalendar(ctx: Context): Pair<Long, String>? = runCatching {
        val uri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, "Glyf")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            .build()
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, "Glyf")
            put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(CalendarContract.Calendars.NAME, "Glyf")
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, "Glyf")
            put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFF7C5CFF.toInt())
            put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, "Glyf")
            put(CalendarContract.Calendars.VISIBLE, 1)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
        }
        val made = ctx.contentResolver.insert(uri, values) ?: return@runCatching null
        android.content.ContentUris.parseId(made) to "Glyf"
    }.getOrNull()

    /** Saves the event; the added event and its calendar's name, or null.
     *  A call link goes in as the location, where Calendar shows it. */
    fun add(ctx: Context, title: String, start: Long, end: Long, allDay: Boolean,
            location: String? = null, notes: String? = null): Pair<Event, String>? {
        if (!canAdd(ctx)) return null
        val (calendarId, name) = writableCalendar(ctx) ?: return null
        return runCatching {
            val values = android.content.ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendarId)
                put(CalendarContract.Events.TITLE, title)
                if (!location.isNullOrEmpty()) put(CalendarContract.Events.EVENT_LOCATION, location)
                if (!notes.isNullOrEmpty()) put(CalendarContract.Events.DESCRIPTION, notes)
                if (allDay) {
                    // All-day events live on UTC midnights.
                    put(CalendarContract.Events.DTSTART, localDayToUtc(start))
                    put(CalendarContract.Events.DTEND, localDayToUtc(end))
                    put(CalendarContract.Events.ALL_DAY, 1)
                    put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
                } else {
                    put(CalendarContract.Events.DTSTART, start)
                    put(CalendarContract.Events.DTEND, maxOf(end, start))
                    put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                }
            }
            val uri = ctx.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values) ?: return@runCatching null
            Event(title, start, maxOf(end, start), allDay, location = location?.takeIf { it.isNotEmpty() },
                id = android.content.ContentUris.parseId(uri)) to name
        }.getOrNull()
    }

    /** A repeating event's own row: its calendar, whether a sync adapter
     *  knows it, and what it already leaves out. */
    private class Series(val calendarId: Long, val syncId: String?, val exdate: String?, val dtstart: Long,
                         val duration: String?, val rrule: String?, val location: String?, val notes: String?)

    private fun series(ctx: Context, id: Long): Series? = runCatching {
        val cols = arrayOf(CalendarContract.Events.CALENDAR_ID, CalendarContract.Events._SYNC_ID,
            CalendarContract.Events.EXDATE, CalendarContract.Events.DTSTART, CalendarContract.Events.DURATION,
            CalendarContract.Events.RRULE, CalendarContract.Events.EVENT_LOCATION, CalendarContract.Events.DESCRIPTION)
        ctx.contentResolver.query(android.content.ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id),
            cols, null, null, null)?.use { c ->
            if (!c.moveToFirst()) null
            else Series(c.getLong(0), c.getString(1), c.getString(2), c.getLong(3), c.getString(4),
                c.getString(5), c.getString(6), c.getString(7))
        }
    }.getOrNull()

    /** Leaves one occurrence out of a series the phone keeps itself. Android
     *  only honours exceptions to synced series (an unsynced one loses every
     *  occurrence), so the date goes in EXDATE, and the rule is put again so
     *  the occurrences are drawn anew. */
    private fun skip(ctx: Context, id: Long, s: Series, begin: Long): Boolean {
        val stamp = SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }.format(begin)
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.EXDATE, listOfNotNull(s.exdate?.takeIf { it.isNotBlank() }, stamp).joinToString(","))
            put(CalendarContract.Events.DTSTART, s.dtstart)
            s.duration?.let { put(CalendarContract.Events.DURATION, it) }
            s.rrule?.let { put(CalendarContract.Events.RRULE, it) }
        }
        return ctx.contentResolver.update(android.content.ContentUris.withAppendedId(
            CalendarContract.Events.CONTENT_URI, id), values, null, null) > 0
    }

    /** Deletes the event, this occurrence only for a repeating one. Null
     *  when done. */
    fun remove(ctx: Context, e: Event): Change? {
        val id = e.id ?: return Change.NOT_FOUND
        if (!e.writable) return Change.READ_ONLY
        if (!canAdd(ctx)) return Change.FAILED
        return runCatching {
            if (e.repeats) {
                val begin = e.begin ?: return Change.NOT_FOUND
                val s = series(ctx, id) ?: return Change.NOT_FOUND
                if (s.syncId == null) return if (skip(ctx, id, s, begin)) null else Change.FAILED
                // A synced series keeps a cancelled exception for it.
                val values = android.content.ContentValues().apply {
                    put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, begin)
                    put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CANCELED)
                }
                ctx.contentResolver.insert(android.content.ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_EXCEPTION_URI, id), values) ?: return Change.FAILED
                null
            } else {
                val gone = ctx.contentResolver.delete(android.content.ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_URI, id), null, null)
                if (gone > 0) null else Change.NOT_FOUND
            }
        }.getOrElse { Change.FAILED }
    }

    /** The event's title and times changed in place (this occurrence only,
     *  for a repeating one). The event as the list shows it now, or why not. */
    fun update(ctx: Context, e: Event, title: String, start: Long, end: Long,
               allDay: Boolean): Pair<Event?, Change?> {
        val id = e.id ?: return null to Change.NOT_FOUND
        if (!e.writable) return null to Change.READ_ONLY
        if (!canAdd(ctx)) return null to Change.FAILED
        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.TITLE, title)
            if (allDay) {
                // All-day events live on UTC midnights, the end day not included.
                put(CalendarContract.Events.DTSTART, localDayToUtc(start))
                put(CalendarContract.Events.DTEND, localDayToUtc(if (end > start) end else start + 86_400_000L))
                put(CalendarContract.Events.ALL_DAY, 1)
                put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
            } else {
                put(CalendarContract.Events.DTSTART, start)
                put(CalendarContract.Events.DTEND, maxOf(end, start))
                put(CalendarContract.Events.ALL_DAY, 0)
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            }
        }
        val done = runCatching {
            if (e.repeats) {
                val begin = e.begin ?: return null to Change.NOT_FOUND
                val s = series(ctx, id) ?: return null to Change.NOT_FOUND
                if (s.syncId == null) {
                    // The phone's own series: the date is left out of it and
                    // the changed occurrence stands on its own.
                    if (!skip(ctx, id, s, begin)) return null to Change.FAILED
                    values.put(CalendarContract.Events.CALENDAR_ID, s.calendarId)
                    s.location?.let { values.put(CalendarContract.Events.EVENT_LOCATION, it) }
                    s.notes?.let { values.put(CalendarContract.Events.DESCRIPTION, it) }
                    return@runCatching ctx.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values) != null
                }
                // One occurrence is an exception to the series, which takes a
                // length, not an end ("Exceptions can't overwrite dtend").
                val from = values.getAsLong(CalendarContract.Events.DTSTART)
                val to = values.getAsLong(CalendarContract.Events.DTEND)
                values.remove(CalendarContract.Events.DTEND)
                values.put(CalendarContract.Events.DURATION, if (allDay) "P${maxOf(1L, (to - from) / 86_400_000L)}D"
                    else "PT${maxOf(0L, (to - from) / 1000)}S")
                values.put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, begin)
                ctx.contentResolver.insert(android.content.ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_EXCEPTION_URI, id), values) != null
            } else {
                ctx.contentResolver.update(android.content.ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_URI, id), values, null, null) > 0
            }
        }.getOrDefault(false)
        if (!done) return null to Change.FAILED
        return e.copy(title = title, start = start, end = maxOf(end, start), allDay = allDay) to null
    }

    private fun localDayToUtc(ms: Long): Long {
        val local = Calendar.getInstance().apply { timeInMillis = ms }
        return Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis
    }

    private fun utcDayToLocal(ms: Long): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = ms }
        return Calendar.getInstance().apply {
            clear()
            set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis
    }

    /** The tour's practice day (the investor chat, here and on tryglyf.com):
     *  three plain events and an open evening, so 10 PM is free. Nothing is
     *  read from the phone and nothing is ever written. */
    fun practiceDay(now: Long = System.currentTimeMillis(), tz: TimeZone = TimeZone.getDefault()): List<Event> {
        val day = startOfDay(now, tz)
        fun at(h: Int, m: Int) = Calendar.getInstance(tz).apply {
            timeInMillis = day; set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
        }.timeInMillis
        return listOf(
            Event("Standup", at(10, 0), at(10, 15), false),
            Event("Lunch with Sam", at(13, 0), at(14, 0), false),
            Event("Gym", at(18, 30), at(19, 30), false),
        )
    }

    fun startOfDay(ms: Long, tz: TimeZone = TimeZone.getDefault()): Long =
        Calendar.getInstance(tz).apply {
            timeInMillis = ms
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    private fun addDays(ms: Long, days: Int, tz: TimeZone): Long =
        Calendar.getInstance(tz).apply { timeInMillis = ms; add(Calendar.DAY_OF_MONTH, days) }.timeInMillis

    /** Everything that touches the day, all-day events first. */
    fun on(day: Long, all: List<Event>, tz: TimeZone = TimeZone.getDefault()): List<Event> {
        val start = startOfDay(day, tz)
        val end = addDays(start, 1, tz)
        return all.filter { it.start < end && (it.end > start || (it.end == it.start && it.start >= start)) }
            .sortedWith(compareBy({ if (it.allDay) 0 else 1 }, { it.start }))
    }

    /** "Wed, Sep 30": iOS's template ("EEE d MMM") in the phone's own order. */
    fun dayLabel(day: Long, tz: TimeZone = TimeZone.getDefault(), locale: Locale = Locale.getDefault()): String {
        // The plain pattern where Android's pattern generator isn't there (JVM tests).
        val pattern = runCatching { android.text.format.DateFormat.getBestDateTimePattern(locale, "EEEdMMM") }
            .getOrNull() ?: "EEE d MMM"
        return SimpleDateFormat(pattern, locale).apply { timeZone = tz }.format(day)
    }

    fun clock(ms: Long, tz: TimeZone = TimeZone.getDefault(), locale: Locale = Locale.getDefault()): String =
        (DateFormat.getTimeInstance(DateFormat.SHORT, locale) as SimpleDateFormat).apply { timeZone = tz }.format(ms)

    fun range(start: Long, end: Long, tz: TimeZone = TimeZone.getDefault(), locale: Locale = Locale.getDefault()): String {
        val a = clock(start, tz, locale)
        val b = clock(end, tz, locale)
        val suffix = listOf(" AM", " PM", " AM", " PM", " am", " pm", " am", " pm")
            .firstOrNull { a.endsWith(it) && b.endsWith(it) }
        return if (suffix != null) "${a.dropLast(suffix.length)}–$b" else "$a–$b"
    }

    /** "📅 Design review · Thu 18 Sep, 3:00–4:00 PM · Studio" */
    fun insert(e: Event, tz: TimeZone = TimeZone.getDefault(), locale: Locale = Locale.getDefault()): String {
        val day = dayLabel(e.start, tz, locale)
        val whenText = if (e.allDay) day else "$day, ${range(e.start, e.end, tz, locale)}"
        return listOfNotNull("📅 ${e.title}", whenText, e.location).joinToString(" · ")
    }

    /** When the day has room, between 9 AM and 9 PM, in a sentence. Today
     *  starts from now, at the next half hour. */
    fun freeTime(
        day: Long, all: List<Event>, tz: TimeZone = TimeZone.getDefault(),
        locale: Locale = Locale.getDefault(), fromHour: Int = 9, toHour: Int = 21,
        now: Long = System.currentTimeMillis(),
    ): String {
        val label = dayLabel(day, tz, locale)
        val dayStart = startOfDay(day, tz)
        var open = dayStart + fromHour * 3_600_000L
        val close = dayStart + toHour * 3_600_000L
        var startsNow = false
        if (startOfDay(now, tz) == dayStart && now > open) {
            startsNow = true
            val half = 1_800_000L
            open = dayStart + ((now - dayStart + half - 1) / half) * half
            if (open >= close) return "I'm done for today"
        }
        val busy = on(day, all, tz)
        if (busy.any { it.allDay }) return "I'm busy all day $label"
        val gaps = mutableListOf<Pair<Long, Long>>()
        var cursor = open
        for (e in busy.sortedBy { it.start }) {
            val s = maxOf(e.start, open)
            val f = minOf(e.end, close)
            if (f <= s) continue
            if (s - cursor >= 1_800_000L) gaps += cursor to s
            cursor = maxOf(cursor, f)
        }
        if (close - cursor >= 1_800_000L) gaps += cursor to close
        if (gaps.isEmpty()) return "I'm booked $label"
        if (!startsNow && gaps.size == 1 && gaps[0].first == open && gaps[0].second == close) return "I'm free all day $label"
        val parts = gaps.map { range(it.first, it.second, tz, locale) }
        val list = if (parts.size > 1) parts.dropLast(1).joinToString(", ") + " and " + parts.last() else parts[0]
        return "I'm free $label, $list"
    }
}
