package com.arpit.glyf.store

import android.content.Context

/**
 * What the person let Glyf do with their Google account: make Meet links and
 * add events to their Google Calendar (whose guests Google emails). Google
 * Play services holds the grant itself; this only remembers which account and
 * what for, so the keyboard knows what to offer. No token is kept: the
 * keyboard asks Play services for a fresh one each time, and nothing reaches
 * Glyf's server. The twin of GoogleAccess.swift.
 */
object GoogleAccess {
    /** Events on calendars the person owns: the narrowest write scope, and
     *  the one that also makes a Meet link for an event. */
    const val CALENDAR = "https://www.googleapis.com/auth/calendar.events.owned"
    /** Meet links on their own (Meet REST API, spaces the app created). */
    const val MEET = "https://www.googleapis.com/auth/meetings.space.created"
    val SCOPES = listOf(CALENDAR, MEET)

    data class Grant(
        val email: String?,
        val scopes: Set<String>,
        /** Debug builds only: a stand-in for Google's APIs (qa/fake-google.mjs). */
        val fakeBase: String? = null,
    )

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("glyf", Context.MODE_PRIVATE)

    fun load(ctx: Context): Grant? {
        val p = prefs(ctx)
        val scopes = p.getString("googleScopes", "").orEmpty().split(' ').filter { it in SCOPES }.toSet()
        if (scopes.isEmpty()) return null
        return Grant(p.getString("googleEmail", null), scopes, p.getString("googleFakeBase", null))
    }

    fun save(ctx: Context, grant: Grant) {
        prefs(ctx).edit()
            .putString("googleEmail", grant.email)
            .putString("googleScopes", grant.scopes.joinToString(" "))
            .putString("googleFakeBase", grant.fakeBase)
            .commit()
    }

    fun clear(ctx: Context) {
        // At once, not later: a sign-out or a test run can end the process
        // right after, and a grant that outlives it would still be used.
        prefs(ctx).edit().remove("googleEmail").remove("googleScopes").remove("googleFakeBase").commit()
    }

    fun hasCalendar(ctx: Context) = load(ctx)?.scopes?.contains(CALENDAR) == true
    fun hasMeet(ctx: Context) = load(ctx)?.scopes?.contains(MEET) == true
}
