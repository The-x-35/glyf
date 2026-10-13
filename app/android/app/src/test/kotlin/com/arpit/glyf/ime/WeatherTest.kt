package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS GlyfEngineTests.testWeatherAnswersFromAnOpenMeteoReply. */
class WeatherTest {
    @Test fun weatherAnswersFromAnOpenMeteoReply() {
        val reply = JSONObject("""{"current":{"temperature_2m":18.4,"weather_code":2,"precipitation":0},
            "daily":{"temperature_2m_max":[21.2,19.0],"temperature_2m_min":[12.1,11.4],
            "precipitation_probability_max":[10,80],"weather_code":[2,61]}}""")
        val w = Weather.parse(reply, fahrenheit = false)!!
        assertEquals(listOf("18°, partly cloudy · H 21° L 12°"), Weather.answer("whats the weather", w)?.results)
        assertEquals(listOf("Tomorrow: rain 80% · H 19° L 11°"), Weather.answer("weather tomorrow?", w)?.results)
        assertEquals(listOf("No rain expected today (10%)"), Weather.answer("is it going to rain", w)?.results)
        assertEquals(listOf("Rain likely tomorrow (80%)"), Weather.answer("will it rain tomorrow", w)?.results)
        assertEquals(listOf("Not now · partly cloudy, 18°"), Weather.answer("is it raining", w)?.results)
        assertNull(Weather.ask("the weather was great"))
        assertNull(Weather.answer("weather?", null))
    }
}
