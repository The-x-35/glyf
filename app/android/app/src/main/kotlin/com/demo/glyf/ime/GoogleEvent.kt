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
