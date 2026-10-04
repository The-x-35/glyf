package com.arpit.glyf.ime

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * A plan read out of a line, the way people type one: "Lunch with Sam
 * tomorrow 1pm" is a title ("Lunch with Sam"), a day and a time. The New
 * Event title and the strip's Add to calendar chip both use it. English, plus
 * the Hinglish people type in India ("kal 5 baje"). The twin of
 * EventParse.swift: EventParseTest runs the same cases as the iOS tests.
 */
object EventParse {

    data class Plan(
        /** What is left once the day and the time are taken out. */
        val title: String,
        val start: Long,
        val end: Long,
        val allDay: Boolean,
        /** Whether the text named a day, a time. A line with neither is only a title. */
        val hasDay: Boolean,
        val hasTime: Boolean,
    )

    private val cache = HashMap<String, Regex>()
    private fun re(pattern: String): Regex =
        synchronized(cache) { cache.getOrPut(pattern) { Regex(pattern, RegexOption.IGNORE_CASE) } }

    /** The line being read. Each piece taken out is blanked where it stood,
     *  so later patterns can't reuse it and what remains is the title. */
    private class Work(s: String) {
        val text = StringBuilder(s)

        /** The first match's groups, lowercased ("" for a missing group), and
         *  the match blanked out; null when nothing matches. */
        fun take(pattern: String): List<String>? {
            val m = re(pattern).find(text) ?: return null
            val groups = m.groups.map { it?.value?.lowercase(Locale.ROOT) ?: "" }
            for (i in m.range) text.setCharAt(i, ' ')
            return groups
        }

        fun title(): String {
            var t = text.toString().replace(Regex("\\s+"), " ")
            val greeting = "^\\s*(?:hey|hi|so|ok|okay|yo|good morning|good evening|gm)[,!.]*\\s+"
            t = t.replace(re(greeting), "")
            val lead = "^\\s*(?:(?:let[’']?s|lets|let us|shall we|should we|can we|could we|we should|how about|what about|maybe|pls|please|remind me to|reminder to|reminder:?)\\s+)+"
            t = t.replace(re(lead), "")
            val dangling = "(?:\\s+(?:at|on|for|from|by|around|in|this|next|the|and|,|-|–))+\\s*$"
            repeat(3) {
                t = t.replace(re(dangling), "")
                t = t.trim(' ', ',', '.', ';', ':', '!', '?', '-', '–')
            }
            t = t.replace(re("^(?:on|at|by)\\s+"), "")
            t = t.replace(Regex("\\s+([,.!?])"), "$1")
            if (t.isEmpty()) return ""
            return t.substring(0, 1).uppercase(Locale.getDefault()) + t.substring(1)
        }
    }

    /** `dayFirst` reads 5/10 as 5 October (India, Britain); false reads it as
     *  May 10 (the US). The keyboard passes the phone's region. */
    fun parse(
        text: String,
        now: Long = System.currentTimeMillis(),
        tz: TimeZone = TimeZone.getDefault(),
        dayFirst: Boolean = true,
        firstDayOfWeek: Int = Calendar.getInstance().firstDayOfWeek,
    ): Plan {
        val w = Work(text)
        var allDay = false
        var dayOffset: Int? = null
        var ymd: Triple<Int?, Int, Int>? = null
        var weekday: Triple<Int, Boolean, Boolean>? = null   // weekday, next, this
        var minutes: Int? = null
        var endMinutes: Int? = null
        var bareHour: Pair<Int, Int>? = null
        var duration: Int? = null
        var relative: Int? = null
        var part: Int? = null
        var pm: Boolean? = null

        if (w.take("\\b(all[ -]?day|whole day|full day|poora din)\\b") != null) allDay = true

        w.take("\\bin\\s+(\\d+(?:\\.\\d+)?|an?|half an?)\\s*(minutes?|mins?|hours?|hrs?|h)\\b")?.let {
            relative = amount(it[1], it[2])
        }
        w.take("\\bfor\\s+(\\d+(?:\\.\\d+)?|an?|half an?)\\s*(minutes?|mins?|hours?|hrs?|h)\\b")?.let {
            duration = amount(it[1], it[2])
        }

        // Parts of the day: a time of their own, and whether 8 means 8 PM.
        // "Good morning" is a greeting and "last night" is gone: neither is a plan.
        w.take("(?<!good )(?<!gud )(?<!last )\\b(?:this\\s+|in the\\s+)?(morning|afternoon|evening|tonight|night|subah|dopahar|shaam|sham|raat)\\b")?.let {
            when (it[1]) {
                "morning", "subah" -> { part = 9 * 60; pm = false }
                "afternoon" -> { part = 15 * 60; pm = true }
                "dopahar" -> { part = 14 * 60; pm = true }
                "evening", "shaam", "sham" -> { part = 18 * 60; pm = true }
                else -> { part = 20 * 60; pm = true }
            }
            if (it[1] == "tonight") dayOffset = 0
        }

        // Times: a range first ("5-6pm", "from 5 to 7"), then one time.
        val hm = "(\\d{1,2})(?:[:.](\\d{2}))?"
        val range1 = "\\b(?:from\\s+)?$hm\\s*(am|pm)?\\s*(?:-|–|to|till|until)\\s*$hm\\s*(am|pm)\\b"
        val range2 = "\\bfrom\\s+$hm\\s*(am|pm)?\\s*(?:-|–|to|till|until)\\s*$hm\\s*(am|pm)?\\b"
        (w.take(range1) ?: w.take(range2))?.let { m ->
            val endMer = m[6].ifEmpty { null }
            val startMer = m[3].ifEmpty { endMer }
            val s = clock(m[1], m[2], startMer, pm)
            val e = clock(m[4], m[5], endMer, pm)
            if (s != null && e != null) {
                minutes = s
                endMinutes = e
                // "11-1pm": the start is the morning before an afternoon end.
                if (m[3].isEmpty() && s > e && s >= 12 * 60) minutes = s - 12 * 60
            }
        }
        if (minutes == null) {
            w.take("\\b(?:at\\s+|@\\s*|around\\s+|by\\s+)?$hm\\s*(am|pm|a\\.m\\.?|p\\.m\\.?)(?![a-z])")?.let {
                minutes = clock(it[1], it[2], if (it[3].startsWith("p")) "pm" else "am", pm)
            }
        }
        if (minutes == null) {
            w.take("\\b(?:at\\s+|@\\s*|around\\s+|by\\s+)?(\\d{1,2}):(\\d{2})\\b")?.let {
                val h = it[1].toIntOrNull() ?: 0
                val mm = it[2].toIntOrNull() ?: 0
                if (h in 13..23 || h == 0) minutes = h * 60 + mm else if (h <= 12) bareHour = h to mm
            }
        }
        if (minutes == null && bareHour == null) {
            w.take("\\b$hm\\s*baje\\b")?.let { bareHour = (it[1].toIntOrNull() ?: 0) to (it[2].toIntOrNull() ?: 0) }
        }
        if (minutes == null && bareHour == null) {
            w.take("\\b(?:at|@|around)\\s+(\\d{1,2})(?:[:.](\\d{2}))?\\b(?!\\s*(?:%|/|st\\b|nd\\b|rd\\b|th\\b|people|persons|pax|mins?|minutes|hours?|hrs?))")?.let {
                bareHour = (it[1].toIntOrNull() ?: 0) to (it[2].toIntOrNull() ?: 0)
            }
        }
        if (minutes == null && bareHour == null) {
            // "brunch sunday 11", "dinner friday 8": an hour straight after the
            // day is its time ("sunday 11th" stays a date).
            w.take("(?<=\\b(?:mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday|sun|sunday|today|tomorrow|tmrw|tonight)\\s)(\\d{1,2})(?:[:.](\\d{2}))?\\b(?!\\s*(?:%|/|st\\b|nd\\b|rd\\b|th\\b|people|persons|pax|mins?|minutes|hours?|hrs?))")?.let {
                bareHour = (it[1].toIntOrNull() ?: 0) to (it[2].toIntOrNull() ?: 0)
            }
        }
        if (minutes == null && bareHour == null) {
            w.take("\\b(noon|midday|midnight)\\b")?.let {
                if (it[1] == "midnight") { minutes = 0; dayOffset = (dayOffset ?: 0) + 1 } else minutes = 12 * 60
            }
        }
        // Dinner at 8 is 8 in the evening; breakfast at 8 is the morning.
        if (pm == null && bareHour != null) {
            val lower = text.lowercase(Locale.ROOT)
            if (Regex("\\b(dinner|drinks|party|movie|club)\\b").containsMatchIn(lower)) pm = true
            if (Regex("\\b(breakfast)\\b").containsMatchIn(lower)) pm = false
        }
        bareHour?.let { (h0, m0) ->
            if (h0 in 1..12 && m0 < 60) {
                var h = h0
                val isPM = pm ?: (h <= 7 || h == 12)
                if (isPM && h < 12) h += 12
                if (!isPM && h == 12) h = 0
                minutes = h * 60 + m0
            }
        }

        // Days.
        if (w.take("\\b(day after (?:tomorrow|tmrw)|parso|parson)\\b") != null) dayOffset = 2
        if (w.take("\\b(tomorrow|tomorow|tmrw|tmr|tmrrw|tomo|2moro|2morrow|kal)\\b") != null) dayOffset = 1
        if (w.take("\\b(today|aaj)\\b") != null) dayOffset = 0
        val full = "(monday|tuesday|wednesday|thursday|friday|saturday|sunday)"
        val short = "(mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat|sun)"
        val a = w.take("\\b(?:(this|next|coming|on)\\s+)?$full\\b")
        if (a != null) {
            weekday = Triple(index(a[2]), a[1] == "next", a[1] == "this")
        } else {
            val b = w.take("\\b(this|next|coming|on|by)\\s+$short\\b")
            if (b != null) {
                weekday = Triple(index(b[2]), b[1] == "next", b[1] == "this")
            } else {
                w.take("\\b$short(?=\\s*(?:\\d|at\\b|@|morning|evening|night|afternoon))")?.let {
                    weekday = Triple(index(it[1]), false, false)
                }
            }
        }
        if (weekday == null && dayOffset == null && w.take("\\bnext week\\b") != null) dayOffset = 7
        if (weekday == null && dayOffset == null && w.take("\\b(?:this\\s+)?weekend\\b") != null) {
            weekday = Triple(Calendar.SATURDAY, false, true)
        }

        val cal = Calendar.getInstance(tz).apply { this.firstDayOfWeek = firstDayOfWeek; timeInMillis = now }
        val months = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
        val d1 = w.take("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?$months\\b")
        if (d1 != null) {
            ymd = Triple(null, month(d1[2]), d1[1].toIntOrNull() ?: 0)
        } else {
            val d2 = w.take("\\b$months\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b")
            if (d2 != null) {
                ymd = Triple(null, month(d2[1]), d2[2].toIntOrNull() ?: 0)
            } else {
                val d3 = w.take("\\b(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?\\b")
                if (d3 != null) {
                    val x = d3[1].toIntOrNull() ?: 0
                    val y2 = d3[2].toIntOrNull() ?: 0
                    val year = d3[3].toIntOrNull()?.let { if (it < 100) 2000 + it else it }
                    ymd = if (dayFirst) Triple(year, y2, x) else Triple(year, x, y2)
                } else {
                    w.take("\\b(?:on\\s+)?the\\s+(\\d{1,2})(?:st|nd|rd|th)\\b")?.let {
                        // This month's, or next month's once it has gone.
                        val n = it[1].toIntOrNull() ?: 0
                        val c = (cal.clone() as Calendar).apply { startOfDay(this) }
                        if (n in 1..c.getActualMaximum(Calendar.DAY_OF_MONTH)) {
                            val today = c.timeInMillis
                            c.set(Calendar.DAY_OF_MONTH, n)
                            if (c.timeInMillis < today) c.add(Calendar.MONTH, 1)
                            ymd = Triple(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
                        }
                    }
                }
            }
        }

        // Resolve the day.
        val today = (cal.clone() as Calendar).apply { startOfDay(this) }
        var day: Calendar? = null
        val r = relative
        val x = ymd
        val wd = weekday
        if (r != null) {
            val at = (cal.clone() as Calendar).apply { add(Calendar.MINUTE, r) }
            minutes = at.get(Calendar.HOUR_OF_DAY) * 60 + at.get(Calendar.MINUTE)
            day = (at.clone() as Calendar).apply { startOfDay(this) }
        } else if (x != null && x.second in 1..12 && x.third in 1..31) {
            val d = (today.clone() as Calendar).apply {
                set(Calendar.DAY_OF_MONTH, 1)
                set(Calendar.YEAR, x.first ?: get(Calendar.YEAR))
                set(Calendar.MONTH, x.second - 1)
            }
            if (x.third <= d.getActualMaximum(Calendar.DAY_OF_MONTH)) {
                d.set(Calendar.DAY_OF_MONTH, x.third)
                if (x.first == null && d.timeInMillis < today.timeInMillis) d.add(Calendar.YEAR, 1)
                day = d
            }
        } else if (wd != null) {
            val todayWd = today.get(Calendar.DAY_OF_WEEK)
            var ahead = (wd.first - todayWd + 7) % 7
            if (ahead == 0 && !wd.third) ahead = 7
            val d = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, ahead) }
            if (wd.second && sameWeek(d, today, firstDayOfWeek)) d.add(Calendar.DAY_OF_MONTH, 7)
            day = d
        } else if (dayOffset != null) {
            day = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, dayOffset!!) }
        }
        val hasDay = day != null
        // A clock time counts; a part of the day counts once a day is named.
        val hasTime = !allDay && (minutes != null || (part != null && hasDay))
        if (minutes == null) part?.let { minutes = it }

        val title = w.title()
        // A meal says when it is, when nothing else does.
        if (!hasTime && !allDay) {
            val lower = title.lowercase(Locale.ROOT)
            val meals = listOf("breakfast" to 9 * 60, "brunch" to 11 * 60, "lunch" to 13 * 60, "dinner" to 20 * 60)
            meals.firstOrNull { Regex("\\b${it.first}\\b").containsMatchIn(lower) }?.let { minutes = it.second }
        }

        val startDay = day ?: today
        val start = (startDay.clone() as Calendar)
        val m = minutes
        if (allDay) {
            // the day itself
        } else if (m != null) {
            start.add(Calendar.MINUTE, m)
            // A time with no day is the next time it comes round.
            if (!hasDay && start.timeInMillis <= now) start.add(Calendar.DAY_OF_MONTH, 1)
        } else if (hasDay && startDay.timeInMillis != today.timeInMillis) {
            start.add(Calendar.HOUR_OF_DAY, 9)
        } else {
            // Nothing said when: the next whole hour, like Calendar's own New Event.
            start.timeInMillis = now
            start.set(Calendar.MINUTE, 0); start.set(Calendar.SECOND, 0); start.set(Calendar.MILLISECOND, 0)
            start.add(Calendar.HOUR_OF_DAY, 1)
        }

        val end = (start.clone() as Calendar)
        val e = endMinutes
        if (allDay) {
            end.add(Calendar.DAY_OF_MONTH, 1)
        } else if (e != null) {
            startOfDay(end)
            end.add(Calendar.MINUTE, e)
            if (end.timeInMillis <= start.timeInMillis) end.add(Calendar.DAY_OF_MONTH, 1)
        } else {
            end.add(Calendar.MINUTE, duration ?: 60)
        }
        return Plan(title, start.timeInMillis, end.timeInMillis, allDay, hasDay, hasTime)
    }

    /** Whether a message reads like a plan worth offering to put in the
     *  calendar: a time, and either a day or a word that makes it a plan. */
    fun looksLikePlan(
        text: String,
        now: Long = System.currentTimeMillis(),
        tz: TimeZone = TimeZone.getDefault(),
        dayFirst: Boolean = regionDayFirst,
        firstDayOfWeek: Int = Calendar.getInstance().firstDayOfWeek,
    ): Plan? {
        // What the calendar itself put in the message is already in the
        // calendar: an event ("📅 Lunch · Fri…") or free time ("I'm free…").
        if (text.contains("📅") || re("\\bI[’']?m (free|busy|booked|done)\\b").containsMatchIn(text)) return null
        // "Call me in 5 minutes" is a countdown, not something for the calendar.
        if (re("\\bin\\s+(?:\\d+|an?|a few|few|couple of)\\s*(?:minutes?|mins?)\\b").containsMatchIn(text)) return null
        val p = parse(text, now, tz, dayFirst, firstDayOfWeek)
        if (!p.hasTime) return null
        if (p.hasDay) return p
        val intent = "\\b(let[’']?s|lets|shall we|should we|can we|could we|meet|meeting|call|catch up|see you|see u|dinner|lunch|breakfast|brunch|coffee|drinks|party|appointment|interview|standup|sync|review|demo|class|session|gym|workout|yoga|movie|movies|film|concert|flight|dentist|doctor|haircut|game|match|pick (?:me|you|us|him|her|them) up|pickup|milte|milenge)\\b"
        return if (re(intent).containsMatchIn(text)) p else null
    }

    /** "Sam Lee sam@x.com, ria@y.com": a name and the email addresses on one
     *  line, the way the keyboard's who field takes them. The first address
     *  is the person, the rest their guests. */
    fun people(line: String): Pair<String, List<String>> {
        val re = re("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}")
        val emails = re.findAll(line).map { it.value.lowercase(Locale.ROOT) }.distinct().toList()
        val name = line.replace(re, " ").replace(Regex("[,;<>()]"), " ").trim().split(Regex("\\s+"))
            .filter { it.isNotEmpty() }.joinToString(" ")
        return name to emails
    }

    /** 5/10 is 5 October in India and Britain, May 10 in the US. */
    val regionDayFirst: Boolean
        get() = Locale.getDefault().country !in setOf("US", "PH", "CA", "FM", "MH", "PW")

    /** "Dinner · Fri 8:00 PM", "Call · Today 5:00 PM": the strip chip's words. */
    fun summary(p: Plan, now: Long = System.currentTimeMillis()): String {
        val day = when {
            CalendarText.startOfDay(p.start) == CalendarText.startOfDay(now) -> "Today"
            CalendarText.startOfDay(p.start) == CalendarText.startOfDay(now + 86_400_000L) -> "Tomorrow"
            else -> CalendarText.dayLabel(p.start)
        }
        val `when` = if (p.allDay) day else "$day ${CalendarText.clock(p.start)}"
        return if (p.title.isEmpty()) `when` else "${p.title} · $`when`"
    }

    private fun amount(n: String, unit: String): Int {
        val value = when (n) {
            "a", "an" -> 1.0
            "half a", "half an" -> 0.5
            else -> n.toDoubleOrNull() ?: 0.0
        }
        return Math.round(if (unit.startsWith("h")) value * 60 else value).toInt()
    }

    /** Minutes after midnight for "5", "5:30", with a meridiem when one was
     *  given; a bare hour leans on the part of the day, then on habit. */
    private fun clock(h: String, m: String, meridiem: String?, pm: Boolean?): Int? {
        var hour = h.toIntOrNull() ?: return null
        if (hour > 23) return null
        val minute = m.toIntOrNull() ?: 0
        if (minute >= 60) return null
        if (meridiem != null) {
            if (hour !in 1..12) return null
            if (meridiem == "pm" && hour < 12) hour += 12
            if (meridiem == "am" && hour == 12) hour = 0
        } else if (hour <= 12) {
            val isPM = pm ?: (hour <= 7 || hour == 12)
            if (isPM && hour < 12) hour += 12
        }
        return hour * 60 + minute
    }

    /** Calendar's weekday numbers: Sunday 1 to Saturday 7. */
    private fun index(name: String): Int = when (name.take(3)) {
        "sun" -> Calendar.SUNDAY
        "mon" -> Calendar.MONDAY
        "tue" -> Calendar.TUESDAY
        "wed" -> Calendar.WEDNESDAY
        "thu" -> Calendar.THURSDAY
        "fri" -> Calendar.FRIDAY
        else -> Calendar.SATURDAY
    }

    private fun month(name: String): Int =
        listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
            .indexOf(name.take(3)) + 1

    private fun startOfDay(c: Calendar) {
        c.set(Calendar.HOUR_OF_DAY, 0); c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
    }

    /** Whether two days fall in the same week, weeks starting on `first`. */
    private fun sameWeek(a: Calendar, b: Calendar, first: Int): Boolean {
        fun weekStart(c: Calendar): Long {
            val s = (c.clone() as Calendar).apply { startOfDay(this) }
            val back = (s.get(Calendar.DAY_OF_WEEK) - first + 7) % 7
            s.add(Calendar.DAY_OF_MONTH, -back)
            return s.timeInMillis
        }
        return weekStart(a) == weekStart(b)
    }
}
