package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * A cashtag's price and a copied address's token, asked of Jupiter's
 * keyless lite API from the phone (twin of TokenLookup.swift): the server's
 * lookup (server/src/lib/rates.ts, `tokenQuote`, `tokenAt`, `pickToken`,
 * `pickStock`, the name list) ported as it is, so `$sol`, `$aapl` and a
 * copied mint work without our server (docs/SERVER-INVENTORY.md,
 * 2026-10-14). GET /rates/crypto and /rates/token stay as the fallback.
 *
 * Synchronous: `search` blocks, so RatesStore runs this on its own single
 * thread and tests hand in a stand-in. Not thread-safe; one thread only.
 */
class TokenLookup(
    private val search: (String) -> List<JSONObject> = ::liveSearch,
    private val now: () -> Long = System::currentTimeMillis,
) {
    data class Quote(
        val symbol: String,
        val name: String,
        val mint: String,
        val usd: Double,
        /** Priced through a tokenized share (xStocks, Ondo) rather than a token. */
        val stock: Boolean = false,
        /** Percent over the last day, when Jupiter has it. */
        val change24h: Double? = null,
        /** A coin the ecosystem tags major (SOL): it keeps its ticker even
         *  where a stock shares it. */
        val major: Boolean = false,
        /** The market's own ticker, whatever was typed. */
        val ticker: String? = null,
    )

    /** A token found by its address. `usd` is null for one too new to have a price. */
    data class MintQuote(val mint: String, val symbol: String, val name: String, val decimals: Int,
                         val usd: Double?, val verified: Boolean,
                         /** A tokenized stock (xStocks, Ondo), by Jupiter's tags. */
                         val stock: Boolean = false)

    class Unavailable(why: String) : Exception(why)

    private data class Hit<T>(val value: T?, val at: Long)
    private val tokens = HashMap<String, Hit<Quote>>()
    private val mints = HashMap<String, Hit<MintQuote>>()

    /** The dollar price of the verified token behind a ticker. A miss is
     *  remembered for a minute too, so "$lol" typed letter by letter is one
     *  lookup, not five. Throws when Jupiter can't be asked (the server is
     *  asked then), where the server would keep what it had. */
    fun quote(raw: String): Quote? {
        val symbol = tickerOf(raw) ?: return null
        // "$apple" is Apple: a known name goes straight to its ticker, so a
        // coin that took the name never answers for the company.
        val known = NAMES[symbol]
        if (known != null && known != symbol) {
            val q = quote(known) ?: return null
            // Bitcoin trades here as WBTC, but people read BTC.
            return q.copy(symbol = symbol, ticker = if (known == "WBTC") "BTC" else q.ticker ?: known)
        }
        tokens[symbol]?.let { if (now() - it.at < TTL) return it.value }
        val list = search(symbol)
        val token = pickToken(symbol, list)
        // A stock beats a coin that merely shares its ticker (a verified meme
        // coin called NVDA is not Nvidia); only a major coin keeps its name.
        var stock = pickStock(symbol, list)
        if (stock == null && token?.major != true && !symbol.endsWith("X")) stock = pickStock(symbol, search("${symbol}x"))
        var found = if (token?.major == true) token else stock ?: token
        // Any other company typed by name ("$pfizer"): its tokenized share.
        if (found == null && symbol.length >= 3) found = pickStockByName(symbol, list)
        // Half a name, or the usual slip ("$appl" on the way to "$apple").
        if (found == null && symbol.length >= 4) found = pickStockByPrefix(symbol, list)
        tokens[symbol] = Hit(found, now())
        return found
    }

    /** The token at a Solana address, or null when Jupiter has none there (a
     *  wallet, in a chat). Throws when Jupiter can't be asked: "not a token"
     *  is never said on a guess. */
    fun tokenAt(address: String): MintQuote? {
        if (!isAddress(address)) return null
        mints[address]?.let { if (now() - it.at < TTL) return it.value }
        val t = search(address).firstOrNull { str(it, "id") == address }
        val symbol = t?.let { str(it, "symbol") }
        val decimals = t?.let { num(it, "decimals") }
        val token = if (t != null && symbol != null && decimals != null) MintQuote(
            address, symbol, str(t, "name") ?: symbol, decimals.toInt(),
            num(t, "usdPrice")?.takeIf { it > 0 }, t.opt("isVerified") == true, stockTagged(t),
        ) else null
        mints[address] = Hit(token, now())
        return token
    }

    companion object {
        const val JUP_SEARCH = "https://lite-api.jup.ag/tokens/v2/search?query="
        const val TTL = 60 * 1000L

        /** Jupiter's token search, blocking; throws when Jupiter can't be asked. */
        fun liveSearch(query: String): List<JSONObject> {
            val conn = (URL(JUP_SEARCH + URLEncoder.encode(query, "UTF-8")).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"; connectTimeout = 5000; readTimeout = 5000
            }
            try {
                if (conn.responseCode !in 200..299) throw Unavailable("jup ${conn.responseCode}")
                val body = org.json.JSONTokener(conn.inputStream.bufferedReader().readText()).nextValue()
                val arr = body as? JSONArray ?: return emptyList()
                return (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }
            } finally { conn.disconnect() }
        }

        /** "$sol" / "SOL" → "SOL", "$apple" → "APPLE"; anything that is not a
         *  ticker or a name → null. */
        fun tickerOf(raw: String): String? {
            val t = raw.trim().removePrefix("$").uppercase()
            // Letters with maybe digits ("SOL", "W3D"); a bare number is an amount.
            return if (TICKER.matches(t)) t else null
        }
        private val TICKER = Regex("^(?=.*[A-Z])[A-Z0-9]{2,14}$")

        /** Base58, 32 to 44 characters: the shape of every Solana address. */
        fun isAddress(s: String): Boolean = ADDRESS.matches(s)
        private val ADDRESS = Regex("^[1-9A-HJ-NP-Za-km-z]{32,44}$")

        /** Names people type instead of tickers. */
        val NAMES: Map<String, String> = mapOf(
            "APPLE" to "AAPL", "TESLA" to "TSLA", "NVIDIA" to "NVDA", "MICROSOFT" to "MSFT", "GOOGLE" to "GOOGL",
            "ALPHABET" to "GOOGL", "AMAZON" to "AMZN", "FACEBOOK" to "META", "NETFLIX" to "NFLX", "COINBASE" to "COIN",
            "MICROSTRATEGY" to "MSTR", "PALANTIR" to "PLTR", "ROBINHOOD" to "HOOD", "GAMESTOP" to "GME", "INTEL" to "INTC",
            "BROADCOM" to "AVGO", "ORACLE" to "ORCL", "SALESFORCE" to "CRM", "ADOBE" to "ADBE", "DISNEY" to "DIS",
            "NIKE" to "NKE", "WALMART" to "WMT", "COSTCO" to "COST", "MCDONALDS" to "MCD", "COCACOLA" to "KO",
            "PEPSI" to "PEP", "JPMORGAN" to "JPM", "SP500" to "SPY", "NASDAQ" to "QQQ",
            "BITCOIN" to "WBTC", "BTC" to "WBTC", "ETHEREUM" to "ETH", "ETHER" to "ETH", "SOLANA" to "SOL", "JUPITER" to "JUP",
        )

        // org.json answers its own NULL for a JSON null: read by type, as the
        // server's `typeof x === "string"` / `"number"` do.
        private fun str(o: JSONObject, k: String): String? = o.opt(k) as? String
        private fun num(o: JSONObject, k: String): Double? =
            (o.opt(k) as? Number)?.toDouble()?.takeIf { it.isFinite() }
        private fun tags(o: JSONObject): List<String> = o.optJSONArray("tags")?.let { a ->
            (0 until a.length()).mapNotNull { a.opt(it) as? String }
        } ?: emptyList()
        private fun liquidity(o: JSONObject) = num(o, "liquidity") ?: 0.0
        private fun change(o: JSONObject) = o.optJSONObject("stats24h")?.let { num(it, "priceChange") }

        /** Verified, priced above zero, with an id: the server's common gate. */
        private fun priced(t: JSONObject) =
            t.opt("isVerified") == true && (num(t, "usdPrice") ?: 0.0) > 0 && str(t, "id") != null

        private fun stockTagged(t: JSONObject) = tags(t).any { it == "stocks" || it == "equities" || it == "xstocks" }

        /** Higher rank, then deeper liquidity, then Jupiter's own order (a stable sort, as JavaScript's). */
        private fun ranked(list: List<JSONObject>, rank: (JSONObject) -> Int): List<JSONObject> =
            list.sortedWith(compareByDescending<JSONObject> { rank(it) }.thenByDescending { liquidity(it) })

        /** The verified token that IS the ticker, never a staked or wrapped
         *  cousin whose symbol merely contains it (SOL must not become JupSOL). */
        fun pickToken(symbol: String, list: List<JSONObject>): Quote? {
            val exact = list.filter { priced(it) && (str(it, "symbol") ?: "").uppercase() == symbol }
            val t = ranked(exact) { (if ("major" in tags(it)) 2 else 0) + (if ("strict" in tags(it)) 1 else 0) }
                .firstOrNull() ?: return null
            return Quote(symbol, str(t, "name") ?: symbol, str(t, "id")!!, num(t, "usdPrice")!!,
                major = "major" in tags(t), ticker = symbol)
        }

        /** A share's own ticker: AAPLx and AAPLon are both AAPL. */
        fun shareTicker(symbol: String?, fallback: String): String {
            val s = (symbol ?: "").let { if (it.endsWith("x")) it.dropLast(1) else if (it.endsWith("on")) it.dropLast(2) else it }
            return if (Regex("^[A-Za-z0-9.]{1,10}$").matches(s)) s.uppercase() else fallback
        }

        /** A company half typed or misspelt: the first verified share, in
         *  Jupiter's order, whose company name starts with what was typed. */
        fun pickStockByPrefix(prefix: String, list: List<JSONObject>): Quote? {
            val want = prefix.lowercase()
            val t = list.firstOrNull { priced(it) && stockTagged(it) && (str(it, "name") ?: "").lowercase().startsWith(want) }
                ?: return null
            return Quote(prefix, str(t, "name") ?: prefix, str(t, "id")!!, num(t, "usdPrice")!!, stock = true,
                change24h = change(t), ticker = shareTicker(str(t, "symbol"), prefix))
        }

        /** A stock by its tokenized share: the verified xStock ("AAPLx") first,
         *  then Ondo's ("AAPLon"), then the deepest. Only tokens Jupiter tags
         *  as stocks count, so a meme coin called AAPLX never prices Apple. */
        fun pickStock(symbol: String, list: List<JSONObject>): Quote? {
            val shares = list.filter {
                val sym = (str(it, "symbol") ?: "").uppercase()
                priced(it) && (sym == "${symbol}X" || sym == "${symbol}ON") && stockTagged(it)
            }
            val t = ranked(shares) { if ((str(it, "symbol") ?: "").uppercase() == "${symbol}X") 1 else 0 }
                .firstOrNull() ?: return null
            return Quote(symbol, str(t, "name") ?: symbol, str(t, "id")!!, num(t, "usdPrice")!!, stock = true,
                change24h = change(t), ticker = symbol)
        }

        private val COMPANY_SUFFIX = Regex("\\s*(xstock|\\(ondo tokenized\\)|-.*)$")
        private val NAME_BREAK = Regex("[\\s,.]+")

        /** A company typed by name ("PFIZER"): the verified tokenized share
         *  whose name is that company ("Pfizer xStock"), xStock first. */
        fun pickStockByName(name: String, list: List<JSONObject>): Quote? {
            val want = name.lowercase()
            val shares = list.filter { t ->
                if (!priced(t) || !stockTagged(t)) return@filter false
                val company = COMPANY_SUFFIX.replaceFirst((str(t, "name") ?: "").lowercase(), "").trim()
                company == want || company.split(NAME_BREAK)[0] == want
            }
            val t = ranked(shares) { if ((str(it, "symbol") ?: "").endsWith("x")) 1 else 0 }.firstOrNull() ?: return null
            return Quote(name, str(t, "name") ?: name, str(t, "id")!!, num(t, "usdPrice")!!, stock = true,
                change24h = change(t), ticker = shareTicker(str(t, "symbol"), name))
        }
    }
}
