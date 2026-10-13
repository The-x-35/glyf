package com.arpit.glyf.ime

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Today's and tomorrow's weather where the phone last was, from Open-Meteo
 *  (free, keyless, already the server's weather source): "is it going to
 *  rain", "weather tomorrow". The twin of Smart.swift's weather answers and
 *  WeatherStore.swift; same wording, same thresholds. */
object Weather {
    data class Snapshot(
        val at: Long, val fahrenheit: Boolean, val nowTemp: Double, val nowCode: Int, val nowRain: Double,
        val high: List<Double>, val low: List<Double>, val rainChance: List<Int>, val code: List<Int>,
    )
    data class Ask(val day: Int, val rain: Boolean, val now: Boolean, val source: String)

    @Volatile var snapshot: Snapshot? = null
    private const val TTL = 30 * 60 * 1000L
    @Volatile private var loading = false
    private val pool = Executors.newSingleThreadExecutor()

    private val general = Regex("""^(?:hows|how's|how\s+is|whats|what's|what\s+is)?\s*(?:the\s+)?(?:weather|forecast)(?:\s+like)?(?:\s+(today|tonight|now|tomorrow|tmrw))?\s*\??$""", RegexOption.IGNORE_CASE)
    private val rainy = Regex("""^(?:is\s+it|will\s+it|is\s+it\s+going\s+to|gonna|does\s+it\s+look\s+like\s+it'?s?\s+going\s+to)\s+(rain|raining|snow|snowing)(?:\s+(today|tonight|tomorrow|tmrw|later))?\s*\??$""", RegexOption.IGNORE_CASE)

    fun ask(text: String): Ask? {
        val s = (text.split(Regex("""[.!\n]""")).lastOrNull { it.isNotBlank() } ?: text).trim()
        general.find(s)?.let { m ->
            val tomorrow = m.groupValues[1].lowercase() in setOf("tomorrow", "tmrw")
            return Ask(if (tomorrow) 1 else 0, rain = false, now = false, source = m.value.trim())
        }
        rainy.find(s)?.let { m ->
            val tomorrow = m.groupValues[2].lowercase() in setOf("tomorrow", "tmrw")
            val lower = s.lowercase()
            val now = (m.groupValues[1].lowercase().endsWith("ing") && m.groupValues[2].isEmpty() && lower.startsWith("is it raining")) ||
                lower.startsWith("is it snowing")
            return Ask(if (tomorrow) 1 else 0, rain = true, now = now, source = m.value.trim())
        }
        return null
    }

    fun words(code: Int): String = when (code) {
        0 -> "clear"; 1 -> "mostly clear"; 2 -> "partly cloudy"; 3 -> "cloudy"
        45, 48 -> "fog"; in 51..57 -> "drizzle"; in 61..67 -> "rain"; in 71..77 -> "snow"
        in 80..82 -> "showers"; 85, 86 -> "snow showers"; in 95..99 -> "thunderstorms"
        else -> "mixed"
    }

    fun answer(text: String, w: Snapshot?): Smart.Conversions? {
        val a = ask(text) ?: return null
        w ?: return null
        val d = a.day
        if (w.high.size <= d || w.low.size <= d || w.rainChance.size <= d || w.code.size <= d) return null
        fun deg(v: Double) = "${Math.round(v)}°"
        val range = "H ${deg(w.high[d])} L ${deg(w.low[d])}"
        val said = when {
            a.now -> if (w.nowRain > 0 || w.nowCode in 51..99) "Yes, ${words(w.nowCode)} now · ${deg(w.nowTemp)}"
                     else "Not now · ${words(w.nowCode)}, ${deg(w.nowTemp)}"
            a.rain -> {
                val whenSaid = if (d == 1) "tomorrow" else "today"
                val p = w.rainChance[d]
                when {
                    p >= 40 -> "Rain likely $whenSaid ($p%)"
                    p >= 20 -> "Some chance of rain $whenSaid ($p%)"
                    else -> "No rain expected $whenSaid ($p%)"
                }
            }
            d == 1 -> "Tomorrow: ${words(w.code[1])}${if (w.rainChance[1] >= 30) " ${w.rainChance[1]}%" else ""} · $range"
            else -> "${deg(w.nowTemp)}, ${words(w.nowCode)} · $range"
        }
        return Smart.Conversions(a.source, listOf(said))
    }

    fun parse(obj: JSONObject, fahrenheit: Boolean, at: Long = System.currentTimeMillis()): Snapshot? {
        val current = obj.optJSONObject("current") ?: return null
        val daily = obj.optJSONObject("daily") ?: return null
        fun doubles(k: String) = daily.optJSONArray(k)?.let { arr -> (0 until arr.length()).map { arr.optDouble(it) } } ?: emptyList()
        if (!current.has("temperature_2m")) return null
        val high = doubles("temperature_2m_max")
        if (high.isEmpty()) return null
        return Snapshot(at, fahrenheit, current.optDouble("temperature_2m"), current.optInt("weather_code"),
            current.optDouble("precipitation", 0.0), high, doubles("temperature_2m_min"),
            doubles("precipitation_probability_max").map { Math.round(it).toInt() }, doubles("weather_code").map { it.toInt() })
    }

    /** Fetches when missing or stale; `then` runs on the fetching thread. */
    fun ensure(lat: Double, lon: Double, fahrenheit: Boolean, then: () -> Unit) {
        val w = snapshot
        if (w != null && System.currentTimeMillis() - w.at < TTL && w.fahrenheit == fahrenheit) return
        if (loading) return
        loading = true
        pool.execute {
            try {
                // About a kilometre, as the privacy policy says, and no more.
                val url = "https://api.open-meteo.com/v1/forecast?latitude=${"%.2f".format(java.util.Locale.US, lat)}" +
                    "&longitude=${"%.2f".format(java.util.Locale.US, lon)}&current=temperature_2m,weather_code,precipitation" +
                    "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code" +
                    "&timezone=auto&forecast_days=2" + if (fahrenheit) "&temperature_unit=fahrenheit" else ""
                val conn = (URL(url).openConnection() as HttpURLConnection).apply { connectTimeout = 5000; readTimeout = 6000 }
                try {
                    if (conn.responseCode == 200) {
                        parse(JSONObject(conn.inputStream.bufferedReader().readText()), fahrenheit)?.let { snapshot = it; then() }
                    }
                } finally { conn.disconnect() }
            } catch (_: Exception) {
            } finally { loading = false }
        }
    }
}
