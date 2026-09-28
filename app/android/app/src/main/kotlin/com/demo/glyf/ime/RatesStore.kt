package com.demo.glyf.ime

import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * The rates behind the money chip (twin of RatesStore.swift): fetched from
 * the server, which caches the ECB and Jupiter for everyone. The dollar table
 * is kept on disk so a cold keyboard has yesterday's before its first request
 * lands. Fiat is asked for once an hour; a token once a minute, and only the
 * ticker on screen.
 */
object RatesStore {
    @Volatile private var fiat: Map<String, Double> = emptyMap()
    @Volatile private var fiatAt = 0L
    private val crypto = ConcurrentHashMap<String, Double>()
    /** The token behind each cashtag, so Buy knows what to buy. */
    private val mints = ConcurrentHashMap<String, String>()
    /** The market's ticker for what was typed ("APPL" → "AAPL"). */
    private val tickers = ConcurrentHashMap<String, String>()
    private val cryptoAt = ConcurrentHashMap<String, Long>()
    /** Copied or typed addresses: a wallet, or the token at that address. */
    private val addresses = ConcurrentHashMap<String, Smart.AddressKind>()
    private val inFlight: MutableSet<String> = Collections.synchronizedSet(mutableSetOf())
    private val pool = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var file: File? = null

    private const val FIAT_TTL = 60 * 60 * 1000L
    private const val TOKEN_TTL = 60 * 1000L

    private val regionCurrency = mapOf(
        "IN" to "INR", "US" to "USD", "GB" to "GBP", "JP" to "JPY", "SG" to "SGD", "AU" to "AUD",
        "CA" to "CAD", "AE" to "AED", "CH" to "CHF", "CN" to "CNY", "HK" to "HKD", "KR" to "KRW",
        "DE" to "EUR", "FR" to "EUR", "ES" to "EUR", "IT" to "EUR", "NL" to "EUR", "IE" to "EUR",
        "PT" to "EUR", "AT" to "EUR", "BE" to "EUR", "FI" to "EUR", "GR" to "EUR",
    )

    /** Once, with the app's files dir: reads the saved table. */
    fun attach(filesDir: File) {
        if (file != null) return
        file = File(filesDir, "rates.json")
        runCatching {
            val f = file ?: return
            if (!f.exists()) return
            val o = JSONObject(f.readText())
            val r = o.optJSONObject("fiat") ?: return
            fiat = r.keys().asSequence().associateWith { r.optDouble(it) }.filterValues { it > 0 }
            fiatAt = o.optLong("fiatAt")
        }
    }

    private fun save() {
        val f = file ?: return
        runCatching { f.writeText(JSONObject().put("fiat", JSONObject(fiat)).put("fiatAt", fiatAt).toString()) }
    }

    /** The currency money converts into: the one the person chose in the
     *  app ("INR", "USD", …), else where the phone is — the region the app
     *  recorded, then the locale. */
    fun local(region: String?, chosen: String? = null): String {
        val pick = chosen?.uppercase()?.takeIf { it != "AUTO" && it.length == 3 }
        if (pick != null) return pick
        return regionCurrency[region?.uppercase() ?: ""]
            ?: runCatching { java.util.Currency.getInstance(java.util.Locale.getDefault()).currencyCode }.getOrNull()
            ?: "USD"
    }

    fun snapshot(region: String?, chosen: String? = null) =
        Smart.RatesSnapshot(fiat, crypto.toMap(), local(region, chosen), mints.toMap(), addresses.toMap(),
            tickers.toMap())

    /** What an address turned out to be, or null when not yet asked. */
    fun addressKind(address: String): Smart.AddressKind? = addresses[address]

    /** Fetches the dollar table when missing or stale; `then` runs on the
     *  main thread once something new is in hand. */
    fun ensureFiat(backendURL: String, then: () -> Unit) {
        if (fiat.isNotEmpty() && System.currentTimeMillis() - fiatAt < FIAT_TTL) return
        fetch(backendURL, "/rates/fiat", "fiat") { obj ->
            val r = obj.optJSONObject("rates") ?: return@fetch
            val table = r.keys().asSequence().associateWith { r.optDouble(it) }.filterValues { it > 0 }
            if (table.isEmpty()) return@fetch
            fiat = table
            fiatAt = System.currentTimeMillis()
            save()
            main.post(then)
        }
    }

    /** The dollar price of one token, refreshed after a minute. A miss is
     *  remembered too, so a made-up ticker is one request. */
    fun ensureToken(backendURL: String, symbol: String, then: () -> Unit) {
        val at = cryptoAt[symbol]
        if (at != null && System.currentTimeMillis() - at < TOKEN_TTL) return
        fetch(backendURL, "/rates/crypto?symbols=$symbol", "token:$symbol") { obj ->
            cryptoAt[symbol] = System.currentTimeMillis()
            val quote = obj.optJSONObject("quotes")?.optJSONObject(symbol)
            val usd = quote?.optDouble("usd") ?: Double.NaN
            if (!usd.isNaN() && usd > 0) {
                crypto[symbol] = usd
                val mint = quote?.optString("mint").orEmpty()
                if (mint.isNotEmpty()) mints[symbol] = mint else mints.remove(symbol)
                val ticker = quote?.optString("ticker").orEmpty()
                if (ticker.isNotEmpty()) tickers[symbol] = ticker else tickers.remove(symbol)
            } else {
                crypto.remove(symbol)
                mints.remove(symbol)
                tickers.remove(symbol)
            }
            main.post(then)
        }
    }

    /** Whether an address is a token's (and which) or someone's wallet.
     *  Asked once per address; when the answer can't be had it counts as a
     *  wallet, and the app checks again before any money moves. */
    fun ensureAddress(backendURL: String, address: String, then: () -> Unit) {
        if (addresses.containsKey(address)) return
        fetch(backendURL, "/rates/token?mint=$address", "address:$address", failed = {
            addresses[address] = Smart.AddressKind.Wallet
            main.post(then)
        }) { obj ->
            val token = obj.optJSONObject("token")
            val symbol = token?.optString("symbol").orEmpty()
            addresses[address] = if (symbol.isEmpty()) Smart.AddressKind.Wallet else
                Smart.AddressKind.Token(symbol, token?.optDouble("usd")?.takeIf { !it.isNaN() && it > 0 })
            main.post(then)
        }
    }

    private fun fetch(backendURL: String, path: String, key: String, failed: (() -> Unit)? = null,
                      done: (JSONObject) -> Unit) {
        if (!inFlight.add(key)) return
        pool.execute {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL("$backendURL$path").openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 5000
                    readTimeout = 8000
                    BackendClient.bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
                }
                val obj = JSONObject(conn.inputStream.bufferedReader().readText())
                if (obj.optBoolean("ok")) done(obj) else failed?.invoke()
            } catch (e: Exception) {
                android.util.Log.w("GlyfKB", "rates $path: $e")
                failed?.invoke()
            } finally {
                conn?.disconnect()
                inFlight.remove(key)
            }
        }
    }
}
