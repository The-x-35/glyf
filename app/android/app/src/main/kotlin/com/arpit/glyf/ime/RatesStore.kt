package com.arpit.glyf.ime

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
 * The rates behind the money chip (twin of RatesStore.swift): fetched
 * straight from the ECB's daily rates (Frankfurter) and Jupiter, with the
 * server (which caches both for everyone) as the fallback. The dollar table
 * is kept on disk so a cold keyboard has yesterday's before its first request
 * lands. Fiat is asked for once an hour; a token once a minute, and only the
 * ticker on screen.
 */
object RatesStore {
    @Volatile private var fiat: Map<String, Double> = emptyMap()
    @Volatile private var fiatAt = 0L
    private val crypto = ConcurrentHashMap<String, Double>()

    /** A token's last dollar price ("SOL"), when one has been fetched. */
    fun cryptoUsd(symbol: String): Double? = crypto[symbol]
    /** The token behind each cashtag, so Buy knows what to buy. */
    private val mints = ConcurrentHashMap<String, String>()

    /** Whether a tokenized stock (xStocks, Ondo) may be bought. Not in the
     *  Solana dApp Store build: its policy counts stocks as regulated
     *  financial services (docs/SOLANA-DAPP-STORE.md). The price still
     *  shows; only Buy goes. */
    val stockBuys = com.arpit.glyf.BuildConfig.FLAVOR != "dappStore"
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
        fun keep(r: JSONObject?) {
            r ?: return
            val table = r.keys().asSequence().associateWith { r.optDouble(it) }.filterValues { it > 0 }
            if (table.isEmpty()) return
            fiat = table + ("USD" to 1.0)
            fiatAt = System.currentTimeMillis()
            save()
            main.post(then)
        }
        // Straight from Frankfurter (the ECB's daily rates, free and keyless,
        // the server's own source); the server only when that fails
        // (SERVER-INVENTORY.md, 2026-10-14).
        if (!inFlight.add("fiat-direct")) return
        pool.execute {
            val direct = try {
                val conn = (URL(FRANKFURTER).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"; connectTimeout = 5000; readTimeout = 6000
                }
                try {
                    if (conn.responseCode == 200) JSONObject(conn.inputStream.bufferedReader().readText()).optJSONObject("rates") else null
                } finally { conn.disconnect() }
            } catch (e: Exception) { null }
            inFlight.remove("fiat-direct")
            if (direct != null && direct.length() > 0) keep(direct)
            else fetch(backendURL, "/rates/fiat", "fiat") { obj -> keep(obj.optJSONObject("rates")) }
        }
    }

    private const val FRANKFURTER = "https://api.frankfurter.dev/v1/latest?base=USD"

    /** The dollar price of one token, refreshed after a minute. A miss is
     *  remembered too, so a made-up ticker is one request. */
    fun ensureToken(backendURL: String, symbol: String, then: () -> Unit) {
        val at = cryptoAt[symbol]
        if (at != null && System.currentTimeMillis() - at < TOKEN_TTL) return
        fun keep(usd: Double, mint: String, ticker: String, stock: Boolean) {
            cryptoAt[symbol] = System.currentTimeMillis()
            if (!usd.isNaN() && usd > 0) {
                crypto[symbol] = usd
                // No mint, no Buy: a stock where stocks can't be bought.
                if (mint.isNotEmpty() && (stockBuys || !stock)) mints[symbol] = mint else mints.remove(symbol)
                if (ticker.isNotEmpty()) tickers[symbol] = ticker else tickers.remove(symbol)
            } else {
                crypto.remove(symbol)
                mints.remove(symbol)
                tickers.remove(symbol)
            }
            main.post(then)
        }
        // Straight from Jupiter (keyless, the server's own source, with the
        // server's picking ported: TokenLookup.kt); the server only when
        // Jupiter can't be asked (SERVER-INVENTORY.md, 2026-10-14).
        direct("token-direct:$symbol", { it.quote(symbol) }) { result ->
            result.onSuccess { q ->
                keep(q?.usd ?: Double.NaN, q?.mint.orEmpty(),
                    q?.let { it.ticker ?: TokenLookup.tickerOf(symbol) ?: symbol }.orEmpty(), q?.stock == true)
            }.onFailure {
                fetch(backendURL, "/rates/crypto?symbols=$symbol", "token:$symbol") { obj ->
                    val quote = obj.optJSONObject("quotes")?.optJSONObject(symbol)
                    keep(quote?.optDouble("usd") ?: Double.NaN, quote?.optString("mint").orEmpty(),
                        quote?.optString("ticker").orEmpty(), quote?.optBoolean("stock") == true)
                }
            }
        }
    }

    /** Jupiter's lookups, one at a time on this store's own thread (each
     *  blocks on its request). */
    private val lookup = TokenLookup()

    private fun <T> direct(key: String, ask: (TokenLookup) -> T, done: (Result<T>) -> Unit) {
        if (!inFlight.add(key)) return
        pool.execute {
            val result = try { Result.success(ask(lookup)) } catch (e: Exception) {
                android.util.Log.w("GlyfKB", "jupiter $key: $e")
                Result.failure(e)
            }
            inFlight.remove(key)
            done(result)
        }
    }

    /** Whether an address is a token's (and which) or someone's wallet.
     *  Asked once per address; when the answer can't be had it counts as a
     *  wallet, and the app checks again before any money moves. */
    fun ensureAddress(backendURL: String, address: String, then: () -> Unit) {
        if (addresses.containsKey(address)) return
        // Jupiter first, as for a ticker; the server when it can't be asked.
        direct("address-direct:$address", { it.tokenAt(address) }) { result ->
            result.onSuccess { token ->
                addresses[address] = if (token == null) Smart.AddressKind.Wallet
                    else Smart.AddressKind.Token(token.symbol, token.usd, buy = stockBuys || !token.stock)
                main.post(then)
            }.onFailure { askServerAboutAddress(backendURL, address, then) }
        }
    }

    private fun askServerAboutAddress(backendURL: String, address: String, then: () -> Unit) {
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
