package com.demo.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** The Google Calendar event a New Event becomes, in the API's own shape
 *  (events.insert). Pure, the twin of GoogleEvent.swift with the same cases. */
object GoogleEvent {
    /** events.insert's query: Google emails every guest, and makes the Meet
     *  call when one is asked for. */
    const val QUERY = "sendUpdates=all&conferenceDataVersion=1"

    /** The title, the times (a day for an all-day event, the end day not
     *  included, as Google counts them), the guests, and a Meet call. */
    /** events.list's answer as the keyboard's own events: each recurrence
     *  its own row (`singleEvents`), all-day ends exclusive the way Google
     *  counts them, cancelled instances left out. */
    fun eventsFromList(json: org.json.JSONObject,
                       zone: java.util.TimeZone = java.util.TimeZone.getDefault()): List<CalendarText.Event> {
        val items = json.optJSONArray("items") ?: return emptyList()
        val iso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US)
        val day = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).apply { timeZone = zone }
        fun moment(node: org.json.JSONObject?): Pair<Long, Boolean>? {
            if (node == null) return null
            node.optString("dateTime").takeIf { it.isNotEmpty() }?.let { s ->
                runCatching { iso.parse(s)?.time }.getOrNull()?.let { return it to false }
            }
            node.optString("date").takeIf { it.isNotEmpty() }?.let { s ->
                runCatching { day.parse(s)?.time }.getOrNull()?.let { return it to true }
            }
            return null
        }
        val out = mutableListOf<CalendarText.Event>()
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            if (item.optString("status") == "cancelled") continue
            val (start, allDay) = moment(item.optJSONObject("start")) ?: continue
            val end = moment(item.optJSONObject("end"))?.first ?: start
            val title = item.optString("summary").trim()
            out.add(CalendarText.Event(
                title = title.ifEmpty { "Busy" },
                start = start, end = maxOf(end, start), allDay = allDay,
                location = item.optString("location").takeIf { it.isNotEmpty() }))
        }
        return out
    }

    fun body(title: String, start: Long, end: Long, allDay: Boolean, guests: List<String>, video: Boolean,
             tz: TimeZone = TimeZone.getDefault(), requestId: String = UUID.randomUUID().toString()): JSONObject {
        val body = JSONObject().put("summary", title)
        if (allDay) {
            val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = tz }
            val last = if (end > start) end else start + 86_400_000L
            body.put("start", JSONObject().put("date", day.format(start)))
            body.put("end", JSONObject().put("date", day.format(last)))
        } else {
            val at = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply { timeZone = tz }
            body.put("start", JSONObject().put("dateTime", at.format(start)).put("timeZone", tz.id))
            body.put("end", JSONObject().put("dateTime", at.format(maxOf(end, start))).put("timeZone", tz.id))
        }
        if (guests.isNotEmpty()) body.put("attendees", JSONArray(guests.map { JSONObject().put("email", it) }))
        if (video) {
            body.put("conferenceData", JSONObject().put("createRequest", JSONObject()
                .put("requestId", requestId)
                .put("conferenceSolutionKey", JSONObject().put("type", "hangoutsMeet"))))
        }
        return body
    }
}
