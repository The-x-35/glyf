package com.demo.glyf.ime

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
    )

    fun granted(ctx: Context): Boolean =
        ctx.checkSelfPermission(android.Manifest.permission.READ_CALENDAR) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    /** Allowed, and turned on in the app's Connected tools. */
    fun connected(ctx: Context): Boolean =
        granted(ctx) && ctx.getSharedPreferences("glyf", Context.MODE_PRIVATE).getBoolean("calendarOn", false)

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
            CalendarContract.Instances.EVENT_ID,
        )
        val out = mutableListOf<Event>()
        runCatching {
            ctx.contentResolver.query(uri, cols, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
                while (c.moveToNext() && out.size < 1500) {
                    val allDay = c.getInt(3) == 1
                    var start = c.getLong(1)
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

    fun dayLabel(day: Long, tz: TimeZone = TimeZone.getDefault(), locale: Locale = Locale.getDefault()): String =
        SimpleDateFormat("EEE d MMM", locale).apply { timeZone = tz }.format(day)

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
