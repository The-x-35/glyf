package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** The Noto sticker search on the phone answers what the server's did
 *  (shared/stickers/noto-cases.json, recorded from server/src/routes/media.ts),
 *  and pages it the same way, plus the server's own cases (server/test/media.test.ts). */
class NotoStickersTest {

    private val cases by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/stickers/noto-cases.json").exists()) dir = dir.parentFile
        JSONObject(File(requireNotNull(dir), "shared/stickers/noto-cases.json").readText()).getJSONArray("cases")
    }

    @Test fun answersEveryRecordedSearchLikeTheServer() {
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val q = c.getString("q")
            val hits = NotoStickers.search(q).map { NotoStickers.item(it) }
            assertEquals("count for '$q'", c.getInt("count"), hits.size)
            val ids = c.getJSONArray("ids")
            assertEquals("order for '$q'", (0 until ids.length()).map { ids.getString(it) }, hits.map { it.id })
            val titles = c.getJSONArray("titles")
            assertEquals("titles for '$q'", (0 until titles.length()).map { titles.getString(it) }, hits.take(5).map { it.title })
        }
    }

    @Test fun bundlesTheCatalogueBaseEmojiOnlyMostPopularFirst() {
        val all = NotoStickers.catalogue
        assertTrue(all.size > 500)
        assertEquals("1f600", all[0].c)
        assertTrue(all.none { Regex("_1f3f[b-f]").containsMatchIn(it.c) })
    }

    @Test fun findsAFeelingThroughTheEmojiThatShowIt() {
        assertTrue(NotoStickers.search("laughing").take(3).any { it.c == "1f602" })
        assertTrue(NotoStickers.search("thank you").any { it.c == "1f64f" })
        assertTrue(NotoStickers.search("hello").any { it.c == "1f44b" })
        assertTrue(NotoStickers.search("wow").size > 2)
        assertEquals(emptyList<NotoStickers.Sticker>(), NotoStickers.search("zzzqqq"))
    }

    @Test fun previewsTheStillAndSendsTheAnimatedGif() {
        val item = NotoStickers.item(NotoStickers.Sticker("1f602", listOf("joy"), "smileys"))
        assertEquals("https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/128.png", item.preview)
        assertEquals("https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/512.gif", item.url)
        assertEquals("joy", item.title)
        assertEquals("noto:1f602", item.id)
        assertEquals("loudly crying", NotoStickers.item(NotoStickers.Sticker("1f62d", listOf("loudly-crying"), "smileys")).title)
    }

    @Test fun pagesThroughASearchAndCreditsGoogle() {
        val first = NotoStickers.page("", null)
        assertEquals(30, first.items.size)
        assertEquals("2", first.next)
        assertTrue(first.attribution!!.contains("CC BY 4.0"))
        val second = NotoStickers.page("", "2")
        assertTrue(second.items[0].id != first.items[0].id)
        assertEquals(NotoStickers.search("")[30].c, second.items[0].id.removePrefix("noto:"))
        assertTrue(NotoStickers.page("love", null).items.size > 3)
        // The last page says there is no next one; past the end is empty.
        val last = NotoStickers.page("", "21")
        assertEquals(NotoStickers.catalogue.size - 600, last.items.size)
        assertNull(last.next)
        assertEquals(0, NotoStickers.page("", "22").items.size)
        assertEquals(first, NotoStickers.page("", "nonsense"))
    }
}
