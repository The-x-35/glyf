package com.arpit.glyf.ime

import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.roundToLong
import kotlin.math.sin

/** Sunrise, sunset and golden hour, worked out on the phone where it last
 *  was (the app shares it; nothing here asks for location). The twin of
 *  Smart.swift's sunAnswer and the server's sun.ts (NOAA, within a minute). */
object SunAnswer {
    @Volatile var lastLocation: Pair<Double, Double>? = null

    /** Epoch millis of sunrise, sunset and golden hour; nulls in a polar day or night. */
    fun sunTimes(lat: Double, lon: Double, atMs: Long): Triple<Long?, Long?, Long?> {
        val rad = Math.PI / 180
        val j2000 = 2451545.0
        fun julian(ms: Long) = ms / 86_400_000.0 + 2440587.5
        fun fromJulian(j: Double) = ((j - 2440587.5) * 86_400_000.0).roundToLong()
        val n = Math.round(julian(atMs) - j2000 - 0.0009 + lon / 360).toDouble()
        val noon = n + 0.0009 - lon / 360
        val m = (357.5291 + 0.98560028 * noon) % 360
        val c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
        val lambda = (m + c + 180 + 102.9372) % 360
        val transit = j2000 + noon + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
        val decl = asin(sin(lambda * rad) * sin(23.4397 * rad))
        fun hourAngle(altitude: Double): Double? {
            val cosO = (sin(altitude * rad) - sin(lat * rad) * sin(decl)) / (cos(lat * rad) * cos(decl))
            if (cosO < -1 || cosO > 1) return null
            return acos(cosO) / rad
        }
        val o = hourAngle(-0.833) ?: return Triple(null, null, null)
        val golden = hourAngle(6.0)?.let { fromJulian(transit + it / 360) }
        return Triple(fromJulian(transit - o / 360), fromJulian(transit + o / 360), golden)
    }

    private val pattern = Regex(
        """^\s*(?:(?:what\s+time\s+is|when\s+is|when'?s|whens|what'?s|whats|what\s+is)\s+)?(?:the\s+)?(sunset|sunrise|golden\s+hour)(?:\s+time)?(?:\s+(today|tonight|tomorrow|tmrw))?\s*\??\s*$""",
        RegexOption.IGNORE_CASE)

    fun answer(text: String, now: java.time.Instant = java.time.Instant.now(),
               here: java.time.ZoneId = java.time.ZoneId.systemDefault()): Smart.Conversions? {
        val (lat, lon) = lastLocation ?: return null
        val sentence = text.split(Regex("""[.!?\n]""")).lastOrNull { it.isNotBlank() } ?: text
        val m = pattern.find(sentence) ?: return null
        val kind = m.groupValues[1].lowercase()
        val tomorrow = m.groupValues[2].lowercase() in setOf("tomorrow", "tmrw")
        val day = now.atZone(here).toLocalDate().plusDays(if (tomorrow) 1 else 0)
        val noon = day.atTime(12, 0).atZone(here).toInstant().toEpochMilli()
        val (rise, set, golden) = sunTimes(lat, lon, noon)
        val (label, whenMs) = when {
            kind.startsWith("sunrise") -> "Sunrise" to rise
            kind.startsWith("sunset") -> "Sunset" to set
            else -> "Golden hour" to golden
        }
        whenMs ?: return null
        val clock = java.time.format.DateTimeFormatter.ofPattern("h:mm a", java.util.Locale.US)
            .format(java.time.Instant.ofEpochMilli(whenMs).atZone(here))
        return Smart.Conversions(m.value.trim(), listOf("$label $clock" + if (tomorrow) " tomorrow" else ""))
    }
}
