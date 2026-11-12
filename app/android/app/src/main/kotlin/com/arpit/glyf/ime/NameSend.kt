package com.arpit.glyf.ime

import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** A send to an SNS name at the end of a message ("send 1 sol to
 *  arpit.sol", "pay arpit.sol 5 usdc"): the name is looked up on Glyf's
 *  server (GET /names/resolve, SNS) and the strip's Send chip shows the
 *  address it points at, shortened, before the existing Send panel opens
 *  with it; Phantom signs, the keyboard holds no key. A name that points
 *  nowhere says so and sends nothing (Arpit, 2026-11-12: "I feel you can
 *  add sending to .eth and .sol, ENS and SNS").
 *
 *  Only .sol here, in SOL or USDC (what Send pays in): the iPhone keyboard
 *  also sends to .eth names, signed in MetaMask, which this keyboard has no
 *  way to open yet. The words are read as TradeIntent.swift reads a send. */
object NameSend {

    data class Ask(val name: String, val amount: String, val token: String)

    sealed class Lookup {
        data class Found(val address: String) : Lookup()
        data class Missing(val why: String) : Lookup()
    }

    private const val START = """(?:^|[.!?\n]\s*|\b(?:pls|please|glyf|hey glyf)[,:]?\s+)"""
    private const val NUM = """(\d+(?:[.,]\d+)?)"""
    private const val SYM = """\$?(sol|solana|usdc)"""
    private const val NAME = """([a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.sol)"""
    private const val END = """\s*[.!]?\s*$"""
    private val amountFirst = Regex("""$START(?:send|pay|transfer)\s+$NUM\s+$SYM\s+to\s+$NAME$END""", RegexOption.IGNORE_CASE)
    private val nameFirst = Regex("""$START(?:send|pay)\s+$NAME\s+$NUM\s+$SYM$END""", RegexOption.IGNORE_CASE)

    /** The send the message ends on, or null. */
    fun parse(text: String): Ask? {
        val t = text.takeLast(200)
        if (t.length < 12 || !t.contains(".sol", ignoreCase = true)) return null
        val (amount, symbol, name) = amountFirst.findAll(t).lastOrNull()?.groupValues?.let { Triple(it[1], it[2], it[3]) }
            ?: nameFirst.findAll(t).lastOrNull()?.groupValues?.let { Triple(it[2], it[3], it[1]) }
            ?: return null
        val token = if (symbol.lowercase() == "usdc") "USDC" else "SOL"
        val value = amount(amount) ?: return null
        return Ask(name.lowercase(), value, token)
    }

    /** "1.5" and "1,5" as 1.5; "1,000" is a thousand. Nil for zero. */
    fun amount(raw: String): String? {
        var s = raw
        s = if (s.contains(',') && s.substringAfterLast(',').length == 3) s.replace(",", "") else s.replace(',', '.')
        val v = s.toDoubleOrNull() ?: return null
        if (v <= 0) return null
        return if (v == Math.floor(v) && v < 1e15) v.toLong().toString() else s
    }

    /** What GET /names/resolve said about [name]: its Solana address, or
     *  why there is none. [status] is the HTTP status, [obj] the body. */
    fun answer(name: String, status: Int, obj: JSONObject?): Lookup {
        if (status == 404 || obj?.optBoolean("found", true) == false) return Lookup.Missing("$name isn’t registered")
        if (status !in 200..299 || obj == null) return Lookup.Missing("Couldn’t look up $name")
        val address = obj.optJSONObject("addresses")?.optString("solana").orEmpty()
        if (!Regex("""^[1-9A-HJ-NP-Za-km-z]{32,44}$""").matches(address)) return Lookup.Missing("$name has no Solana address")
        return Lookup.Found(address)
    }

    /** Names looked up this session, by name. */
    val looked = ConcurrentHashMap<String, Lookup>()
    private val inFlight = ConcurrentHashMap.newKeySet<String>()
    private val pool = Executors.newSingleThreadExecutor()
    private val main by lazy { Handler(Looper.getMainLooper()) }

    /** Looks [name] up once; [then] runs on the main thread when it lands. */
    fun ensure(backendURL: String, name: String, then: () -> Unit) {
        if (looked.containsKey(name) || backendURL.isEmpty() || !inFlight.add(name)) return
        pool.execute {
            var conn: HttpURLConnection? = null
            var lookup: Lookup
            try {
                val q = URLEncoder.encode(name, "UTF-8")
                conn = (URL("$backendURL/names/resolve?name=$q").openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 5000
                    readTimeout = 12000
                    BackendClient.bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
                }
                val status = conn.responseCode
                val body = (if (status in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText()
                lookup = answer(name, status, body?.let { runCatching { JSONObject(it) }.getOrNull() })
            } catch (e: Exception) {
                android.util.Log.w("GlyfKB", "names: $e")
                lookup = Lookup.Missing("Couldn’t look up $name")
            } finally {
                conn?.disconnect()
            }
            // Names and addresses stay out of the log, as on the server. A
            // lookup that failed (not a name that's missing) is said once
            // and asked again after 30 s.
            looked[name] = lookup
            inFlight.remove(name)
            if (lookup == Lookup.Missing("Couldn’t look up $name")) main.postDelayed({ looked.remove(name, lookup) }, 30_000)
            main.post(then)
        }
    }
}
