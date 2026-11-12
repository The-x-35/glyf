package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The search's Shorts tab (2026-11-06): the same assertions as
 *  GlyfEngineTests' Shorts cases and server/test/shorts.test.ts. */
class ShortsTest {

    @Test fun aShortPastesLikeAVideo() {
        val short = BackendClient.SearchCard(kind = "short", id = "s", title = "Ranking Chaotic Cat Moments",
            url = "https://www.youtube.com/shorts/GVES6-kBzRE", emoji = "🎥")
        assertEquals("https://www.youtube.com/shorts/GVES6-kBzRE\n🎥 Ranking Chaotic Cat Moments",
            short.insertText("titleAndLink"))
        assertEquals("https://www.youtube.com/shorts/GVES6-kBzRE", short.insertText("linkOnly"))
    }

    /** The server's shorts response, as it crosses the wire. */
    @Test fun theShortsResponseDecodes() {
        val json = JSONObject("""
        {"ok":true,"vertical":"shorts","query":"cats","provider":"youtube-data-api","cards":[
          {"kind":"short","id":"vert1","videoId":"vert1","title":"Cat water","channel":"Catzilla",
           "duration":"0:20","seconds":20,"portrait":true,"emoji":"🎥",
           "thumb":"https://i.ytimg.com/vi/vert1/sddefault.jpg",
           "url":"https://www.youtube.com/shorts/vert1"},
          {"kind":"short","id":"nodim","videoId":"nodim","title":"Clip","channel":"C",
           "duration":"0:15","seconds":15,"emoji":"🎥","url":"https://www.youtube.com/shorts/nodim"},
          {"kind":"link","id":"tail","title":"More Shorts on YouTube","domain":"youtube.com",
           "url":"https://www.youtube.com/results?search_query=cats%20%23shorts"}]}
        """.trimIndent())
        val cards = BackendClient.parseCards(json)
        assertEquals(listOf("short", "short", "link"), cards.map { it.kind })
        val first = cards[0]
        assertEquals(20, first.seconds)
        assertEquals(true, first.portrait)
        assertEquals("0:20", first.duration)
        assertEquals("Catzilla", first.channel)
        assertEquals("https://www.youtube.com/shorts/vert1\n🎥 Cat water", first.insertText("titleAndLink"))
        assertNull(cards[1].portrait)
    }

    /** A vertical video's thumbnail is its 9:16 frame centred on YouTube's
     *  filler: the card shows the frame. Anything else is shown whole. */
    @Test fun theThumbShowsTheVerticalFrame() {
        assertEquals(ShortsThumb.Frame(185, 0, 270, 480), ShortsThumb.frame(640, 480, true))
        assertEquals(ShortsThumb.Frame(138, 0, 203, 360), ShortsThumb.frame(480, 360, true))
        assertEquals(ShortsThumb.Frame(437, 0, 405, 720), ShortsThumb.frame(1280, 720, true))
        // Landscape or unknown: never cropped.
        assertEquals(ShortsThumb.Frame(0, 0, 640, 480), ShortsThumb.frame(640, 480, false))
        // An image already narrower than 9:16 stays whole.
        assertEquals(ShortsThumb.Frame(0, 0, 100, 400), ShortsThumb.frame(100, 400, true))
        assertEquals(126, ShortsThumb.cardWidth(224))
    }

    /** Six tabs fit the strip: 35dp each on a wide phone, narrower on others. */
    @Test fun theTabsNarrowToLeaveTheQueryRoom() {
        assertEquals(30, SearchCards.tabWidth(402, 6))
        assertEquals(35, SearchCards.tabWidth(440, 6))
        assertEquals(28, SearchCards.tabWidth(360, 6))
        assertEquals(35, SearchCards.tabWidth(411, 5))
    }
}
