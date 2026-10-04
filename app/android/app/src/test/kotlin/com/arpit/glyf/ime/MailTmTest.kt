package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** The mail.tm client (shared/tempmail/RULES.md) against a local stand-in:
 *  a 401 takes a new token once and a second one ends the address, a read
 *  turned away stops the look and one gone is skipped, reads per look are
 *  capped, and create takes a public active domain and another name when
 *  one is taken. */
class MailTmTest {

    private lateinit var server: ServerSocket
    /** Each request as "METHOD path token". */
    private val calls = mutableListOf<String>()
    /** The token the inbox takes, and the one POST /token hands out. */
    private var accepted = "good"
    private var issued = "good"
    private var tokenStatus = 200
    private val accountStatuses = ArrayDeque<Int>()
    private val readStatus = mutableMapOf<String, Int>()
    private var inbox = listOf<String>()

    private val base get() = "http://127.0.0.1:${server.localPort}"
    private val box = TempBox("maple3f9a2c@glyf-temp.example", "p".repeat(20), "old", "acct1",
        System.currentTimeMillis(), System.currentTimeMillis() + TempMailRules.WATCH_MS, 0L, emptySet())

    /** A bare HTTP/1.1 stand-in (android.jar hides the JDK's HttpServer
     *  from unit tests): one request per connection, answered in turn. */
    @Before fun start() {
        server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        Thread {
            while (!server.isClosed) {
                val socket = runCatching { server.accept() }.getOrNull() ?: break
                socket.use { serve(it) }
            }
        }.apply { isDaemon = true }.start()
    }

    @After fun stop() = server.close()

    private fun serve(socket: java.net.Socket) {
        val input = socket.getInputStream().buffered()
        fun line(): String {
            val out = StringBuilder()
            while (true) {
                val c = input.read()
                if (c < 0 || c == '\n'.code) break
                if (c != '\r'.code) out.append(c.toChar())
            }
            return out.toString()
        }
        val (method, path) = line().split(" ").let { it[0] to it[1] }
        val headers = generateSequence { line().takeIf { it.isNotEmpty() } }
            .associate { h -> h.substringBefore(":").trim().lowercase() to h.substringAfter(":").trim() }
        repeat(headers["content-length"]?.toIntOrNull() ?: 0) { input.read() }
        val (status, body) = handle(method, path, headers["authorization"]?.removePrefix("Bearer "))
        val bytes = body.toByteArray()
        socket.getOutputStream().apply {
            write(("HTTP/1.1 $status X\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\n" +
                "Connection: close\r\n\r\n").toByteArray())
            write(bytes)
            flush()
        }
    }

    private fun mailJson(id: String, n: Int) = JSONObject().put("id", id)
        .put("from", JSONObject().put("address", "no-reply@acme.example").put("name", "Acme"))
        .put("subject", "Your Acme code").put("text", "Your verification code is 482913.")
        .put("html", JSONArray())
        .put("createdAt", Instant.parse("2026-09-30T10:00:00Z").plusSeconds(n.toLong()).toString())

    private fun handle(method: String, path: String, auth: String?): Pair<Int, String> {
        synchronized(calls) { calls.add(listOfNotNull(method, path, auth).joinToString(" ")) }
        return when {
            path == "/domains" -> 200 to """[{"id":"d0","domain":"private.example","isActive":true,"isPrivate":true},
                {"id":"d1","domain":"off.example","isActive":false,"isPrivate":false},
                {"id":"d2","domain":"glyf-temp.example","isActive":true,"isPrivate":false}]"""
            path == "/accounts" && method == "POST" -> (accountStatuses.removeFirstOrNull() ?: 201).let {
                it to if (it == 201) """{"id":"acct1"}""" else """{"detail":"This value is already used."}"""
            }
            path == "/token" -> tokenStatus to if (tokenStatus == 200) """{"token":"$issued","id":"acct1"}""" else "{}"
            auth != accepted -> 401 to """{"code":401,"message":"Expired JWT Token"}"""
            path == "/messages?page=1" -> 200 to JSONArray(inbox.map { JSONObject().put("id", it) }).toString()
            path.startsWith("/messages/") -> path.removePrefix("/messages/").let { id ->
                (readStatus[id] ?: 200).let { it to if (it == 200) mailJson(id, inbox.indexOf(id)).toString() else "{}" }
            }
            path == "/accounts/acct1" && method == "DELETE" -> 204 to ""
            else -> 404 to "{}"
        }
    }

    private class Look(val mails: List<TempMail>?, val status: Int, val box: TempBox)

    private fun look(from: TempBox, known: Map<String, TempMail> = emptyMap()): Look {
        val done = CountDownLatch(1)
        var got: Look? = null
        MailTm.check(base, from, known) { mails, status, used -> got = Look(mails, status, used); done.countDown() }
        assertTrue("no answer", done.await(10, TimeUnit.SECONDS))
        return got!!
    }

    private fun made(): Pair<TempBox?, Int> {
        val done = CountDownLatch(1)
        var got: Pair<TempBox?, Int>? = null
        MailTm.create(base) { b, status -> got = b to status; done.countDown() }
        assertTrue("no answer", done.await(10, TimeUnit.SECONDS))
        return got!!
    }

    @Test fun aStaleTokenIsRetakenOnceAndKept() {
        inbox = listOf("m1")
        val l = look(box)
        assertEquals(200, l.status)
        assertEquals("good", l.box.token)
        assertEquals("482913", l.mails!!.single().code)
        assertEquals(listOf("GET /messages?page=1 old", "POST /token", "GET /messages?page=1 good",
            "GET /messages/m1 good"), calls)
    }

    @Test fun aSecond401EndsTheAddress() {
        issued = "also-stale"
        val l = look(box)
        assertNull(l.mails)
        assertEquals(401, l.status)
        assertEquals(listOf("GET /messages?page=1 old", "POST /token", "GET /messages?page=1 also-stale"), calls)
    }

    @Test fun aPasswordRefusedEndsTheAddress() {
        tokenStatus = 401
        assertEquals(401, look(box).status)
    }

    @Test fun aTokenTurnedAwayIsOnlyASkip() {
        tokenStatus = 429
        val l = look(box)
        assertNull(l.mails)
        assertEquals(429, l.status)   // the watcher skips the look; only 401 ends it
        assertEquals("old", l.box.token)
    }

    @Test fun noAnswerIsZero() {
        val port = server.localPort
        server.close()
        val done = CountDownLatch(1)
        var status = -1
        MailTm.check("http://127.0.0.1:$port", box, emptyMap()) { _, s, _ -> status = s; done.countDown() }
        assertTrue(done.await(10, TimeUnit.SECONDS))
        assertEquals(0, status)
    }

    @Test fun aReadTurnedAwayStopsTheLookAndAGoneOneIsSkipped() {
        inbox = listOf("m1", "m2", "m3", "m4", "m5")
        readStatus["m3"] = 404
        readStatus["m4"] = 429
        val known = TempMailRules.mail(mailJson("m1", 0))!!
        val l = look(box.copy(token = "good"), mapOf("m1" to known))
        assertEquals(429, l.status)
        assertEquals(setOf("m1", "m2"), l.mails!!.map { it.id }.toSet())
        // m1 was known (not read again) and m5 waits for the next look.
        assertEquals(listOf("GET /messages?page=1 good", "GET /messages/m2 good", "GET /messages/m3 good",
            "GET /messages/m4 good"), calls)
    }

    @Test fun twentyReadsALookAtMost() {
        inbox = (1..25).map { "m$it" }
        val first = look(box.copy(token = "good"))
        assertEquals(200, first.status)
        assertEquals(20, first.mails!!.size)
        assertEquals(20, calls.count { it.startsWith("GET /messages/") })
        calls.clear()
        val second = look(first.box, first.mails.associateBy { it.id })
        assertEquals(25, second.mails!!.size)
        assertEquals(5, calls.count { it.startsWith("GET /messages/") })
        // Newest first.
        assertEquals("m25", second.mails.first().id)
    }

    @Test fun createTakesAPublicActiveDomainAndAnotherNameWhenTaken() {
        accountStatuses.addAll(listOf(422, 422))
        issued = "fresh"
        val (made, status) = made()
        assertEquals(200, status)
        assertNotNull(made)
        assertTrue(made!!.address, Regex("^[a-z]+[0-9a-f]{6}@glyf-temp\\.example$").matches(made.address))
        // The same sixteen words as iOS.
        assertTrue(made.address.substringBefore("@").dropLast(6) in setOf("amber", "maple", "cedar", "cobalt",
            "ember", "willow", "lunar", "harbor", "meadow", "orbit", "pebble", "river", "sable", "swift", "tidal", "quiet"))
        assertEquals(20, made.password.length)
        assertEquals("fresh", made.token)
        assertEquals("acct1", made.accountId)
        assertEquals(TempMailRules.WATCH_MS, made.watchUntil - made.createdAt)
        assertEquals(3, calls.count { it == "POST /accounts" })
    }

    @Test fun createGivesUpAfterThreeTakenNames() {
        accountStatuses.addAll(listOf(422, 422, 422))
        val (made, status) = made()
        assertNull(made)
        assertEquals(422, status)
        assertEquals(3, calls.count { it == "POST /accounts" })
        assertEquals("Temp mail didn't answer. Try again in a moment", MailTm.createNotice(status))
        assertEquals("Temp mail is busy. Try again in a minute", MailTm.createNotice(429))
        assertEquals("Couldn't reach temp mail. Check the connection", MailTm.createNotice(0))
    }

    @Test fun deleteRetakesAStaleTokenToo() {
        MailTm.delete(base, box)
        val until = System.currentTimeMillis() + 10_000
        while (synchronized(calls) { calls.size } < 3 && System.currentTimeMillis() < until) Thread.sleep(20)
        assertEquals(listOf("DELETE /accounts/acct1 old", "POST /token", "DELETE /accounts/acct1 good"),
            synchronized(calls) { calls.toList() })
    }
}
