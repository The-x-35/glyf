package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.pow

/**
 * The generated theme table (tools/gen_themes_kotlin.py) against the spec,
 * docs/THEMES.md: all 24 load with both variants, every contrast rule of
 * §5.3 holds (the same sums as shared/themes/check_contrast.py), and the
 * fonts, sounds and textures they name ship, and every variant's style
 * (faces, legend, ornaments) is the JSON's and names only what the
 * keyboards draw.
 */
class KeyboardThemesTest {

    private fun channel(c: Int, shift: Int) = ((c shr shift) and 0xFF) / 255.0

    private fun lum(c: Int): Double {
        fun f(v: Double) = if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        return 0.2126 * f(channel(c, 16)) + 0.7152 * f(channel(c, 8)) + 0.0722 * f(channel(c, 0))
    }

    private fun ratio(a: Int, b: Int): Double {
        val x = lum(a); val y = lum(b)
        return (maxOf(x, y) + 0.05) / (minOf(x, y) + 0.05)
    }

    /** sRGB blend, rounded as the Python checker does. */
    private fun blend(a: Int, b: Int, t: Double): Int {
        fun ch(s: Int) = Math.round((channel(a, s) + (channel(b, s) - channel(a, s)) * t) * 255).toInt()
        return (0xFF shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
    }

    private val sheets = mapOf(
        false to intArrayOf(0xFFE2E4E8.toInt(), 0xFFD1D4D9.toInt()),
        true to intArrayOf(0xFF1B1B1D.toInt(), 0xFF292929.toInt()))

    private fun boundary(fill: Int, cls: String, bg: Int, v: KeyboardThemes.Variant): Double {
        var best = ratio(fill, bg)
        v.border?.let { if (cls in it.appliesTo) best = maxOf(best, ratio(it.color, bg)) }
        val s = v.shadow
        if (s.offsetY >= 1 && s.radius == 0 && s.alpha > 0f)
            best = maxOf(best, ratio(blend(bg, s.color, s.alpha.toDouble()), bg))
        return best
    }

    /** The unit tests run in app/android/app. */
    private val repo = File("../../..")

    @Test fun theTableIsTheJsonRegenerated() {
        // Ids, order, names and categories as shared/themes/themes.json has
        // them: a JSON edited without rerunning tools/gen_themes_kotlin.py fails.
        val json = org.json.JSONArray(File(repo, "shared/themes/themes.json").readText())
        val all = KeyboardThemes.ALL
        assertEquals(json.length(), all.size)
        assertEquals(all.size, all.map { it.id }.toSet().size)
        for (i in 0 until json.length()) {
            val j = json.getJSONObject(i)
            assertEquals(j.getString("id"), all[i].id)
            assertEquals(j.getString("name"), all[i].name)
            assertEquals(j.getString("category"), all[i].category)
            assertEquals(j.optString("tier", "free"), all[i].tier)
            for (mode in listOf("light", "dark")) {
                val v = all[i].variant(mode == "dark")
                val jv = j.getJSONObject("variants").getJSONObject(mode)
                assertEquals(jv.getJSONObject("letterKey").getString("fill"), hex(v.letter.fill))
                assertEquals(jv.getString("keyText"), hex(v.keyText))
                assertEquals(jv.getJSONObject("board").getJSONArray("colors").getString(0), hex(v.board[0]))
            }
        }
    }

    @Test fun everyTextureKindIsInTheLibrary() {
        // A kind the library doesn't paint would leave a bare board quietly.
        for (t in KeyboardThemes.ALL) {
            val tex = t.texture ?: continue
            if (tex.android == "none") continue
            assertTrue("${t.id}: texture kind ${tex.kind}",
                tex.kind in ThemeTextures.KINDS || tex.kind in ThemeTextures.LEGACY)
        }
    }

    private fun hex(c: Int) = "#%06X".format(c and 0xFFFFFF)

    @Test fun everyThemeLoadsBothVariants() {
        for (t in KeyboardThemes.ALL) {
            assertNotNull(KeyboardThemes.byId(t.id))
            for (dark in listOf(false, true)) {
                val v = t.variant(dark)
                assertTrue("${t.id} board", v.board.size in 1..2)
                if (v.board.size == 2) assertNotNull("${t.id} angle", v.boardAngle)
                for (c in listOf(v.letter.fill, v.function.fill, v.space.fill, v.keyText, v.popupFill, v.chipFace))
                    assertEquals("${t.id} opaque", 0xFF, (c ushr 24) and 0xFF)
                assertTrue(v.shadow.offsetY in 0..1)
                assertTrue(v.shadow.radius == 0 || v.shadow.radius in 2..4)
                v.border?.let { b ->
                    assertEquals(1, b.width)
                    assertTrue(b.appliesTo.all { it in setOf("letter", "function", "space", "return") })
                }
            }
            assertTrue(t.glyphStyle in setOf("standard", "light", "bold"))
        }
        KeyboardThemes.ALL.forEach { assertNotSame(it.light, it.dark) }
    }

    @Test fun anUnknownOrEmptyIdIsTodaysLook() {
        assertNull(KeyboardThemes.byId(""))
        assertNull(KeyboardThemes.byId(null))
        assertNull(KeyboardThemes.byId("no-such-theme"))
        assertNull(KeyboardThemes.byId("site"))
        assertNull(KeyboardThemes.byId("glass"))
    }

    @Test fun contrastHoldsInEveryVariant() {
        val fails = mutableListOf<String>()
        for (t in KeyboardThemes.ALL) for (dark in listOf(false, true)) {
            val v = t.variant(dark)
            fun need(what: String, value: Double, min: Double) {
                if (value < min - 1e-9) fails += "${t.id} ${if (dark) "dark" else "light"}: $what %.2f < $min".format(value)
            }
            val tex = t.texture
            val amp = if (tex != null && (tex.ios == "keys" || "keys" in tex.android)) tex.amplitude.toDouble() else 0.0
            need("key text", ratio(v.keyText, blend(v.letter.fill, v.keyText, amp)), 4.5)
            need("function glyph", ratio(v.functionGlyph, v.function.fill), 4.5)
            listOfNotNull(v.shift, v.delete).forEach { need("override glyph", ratio(it.glyph, it.fill), 4.5) }
            need("return text", ratio(v.returnPrimary.glyph, v.returnPrimary.fill), 4.5)
            need("popup text", ratio(v.popupText, v.popupFill), 4.5)
            val strip = v.stripBackground?.let { intArrayOf(it) } ?: v.board
            need("strip text", strip.minOf { ratio(v.stripText, it) }, 4.5)
            need("chip accent", ratio(v.chipAccent, v.chipFace), 4.5)
            need("bound dot", ratio(v.boundDot, v.letter.fill), 3.0)
            val keys = mutableListOf("letter" to v.letter.fill, "function" to v.function.fill,
                "space" to v.space.fill, "return" to v.returnPrimary.fill)
            listOfNotNull(v.shift, v.delete).forEach { keys += "function" to it.fill }
            for ((where, bgs) in listOf("board" to v.board, "iPhone sheet" to sheets.getValue(dark)))
                for ((cls, fill) in keys)
                    need("$cls key vs $where", bgs.minOf { boundary(fill, cls, it, v) }, 1.15)  // check_contrast.py KEY_EDGE: Apple-like keys, not 3:1 slabs
            // Android only: the strip's ink on the cards the panels draw
            // (KeyPalette.fromSkin: a shade off the board), and the pad's
            // capless keys, drawn in the strip ink on the board.
            val card = if (dark) blend(v.board[0], 0xFFFFFFFF.toInt(), 0.08) else blend(v.board[0], 0xFFFFFFFF.toInt(), 0.72)
            need("strip ink on panel card", ratio(v.stripText, card), 4.5)
        }
        assertTrue(fails.joinToString("\n"), fails.isEmpty())
    }

    private val appRoot = File("../..")

    @Test fun theFontsTheyNameShipWithTheirLicences() {
        for (t in KeyboardThemes.ALL) {
            val f = t.font ?: continue
            val file = File(appRoot, f.asset.removePrefix("flutter_assets/"))
            assertTrue("${t.id}: $file", file.isFile && file.length() > 10_000)
            val ofl = File(file.parentFile, f.family.replace(" ", "") + "-OFL.txt")
            assertTrue("${t.id}: $ofl", ofl.isFile)
            // A Reserved Font Name ships unmodified; only those stay variable.
            if (f.variable) assertTrue(f.rfn)
        }
    }

    @Test fun everyPackHasItsSoundsUnder30KB() {
        val raw = File("src/main/res/raw")
        for (t in KeyboardThemes.ALL) {
            if (t.soundPack == "system") continue
            val files = ThemeSound.ROLES.map { File(raw, "theme_${t.soundPack}_$it.wav") }.filter { it.isFile }
            assertTrue("${t.id}: no samples for ${t.soundPack}", files.isNotEmpty())
            // A pack plays its letter for a role it lacks; only sonar leaves
            // the letters to the system click.
            if (t.soundPack != "sonar") assertTrue(File(raw, "theme_${t.soundPack}_letter.wav").isFile)
            files.forEach { assertTrue("$it", it.length() < 30_000) }
        }
    }

    @Test fun everyVariantsStyleIsTheJsonsAndValid() {
        // The faces, legend and ornaments as shared/themes/themes.json has
        // them (tools/gen_themes_kotlin.py), and every name they use known.
        val json = org.json.JSONArray(File(repo, "shared/themes/themes.json").readText())
        val textures = File(repo, "shared/themes/textures").list()!!.map { it.removeSuffix(".png") }.toSet()
        for (i in 0 until json.length()) {
            val j = json.getJSONObject(i)
            val t = KeyboardThemes.ALL[i]
            for (mode in listOf("light", "dark")) {
                val where = "${t.id} $mode"
                val st = t.variant(mode == "dark").style
                val js = j.getJSONObject("variants").getJSONObject(mode).getJSONObject("style")
                val faces = js.getJSONObject("faces")
                for (cls in listOf("letter", "function", "space", "return")) {
                    val f = st.face(cls)
                    val jf = faces.getJSONObject(cls)
                    val tex = if (jf.isNull("texture")) null else jf.getString("texture")
                    assertEquals("$where $cls texture", tex, f.texture)
                    if (tex != null) assertTrue("$where $cls: no texture $tex", tex in textures)
                    assertEquals("$where $cls alpha", jf.getDouble("textureAlpha"), f.textureAlpha.toDouble(), 1e-4)
                    assertEquals(jf.getJSONArray("sheen").getDouble(0), f.sheenTop.toDouble(), 1e-4)
                    assertEquals(jf.getJSONArray("sheen").getDouble(1), f.sheenBottom.toDouble(), 1e-4)
                    assertEquals(jf.getDouble("highlight"), f.highlight.toDouble(), 1e-4)
                    assertEquals(jf.getDouble("gloss"), f.gloss.toDouble(), 1e-4)
                    assertEquals(jf.getDouble("metal"), f.metal.toDouble(), 1e-4)
                    assertEquals("$where $cls fill2", jf.isNull("fill2"), f.fill2 == null)
                    assertEquals("$where $cls shape", jf.getString("shape") == "round", f.round)
                    assertTrue("$where $cls shape", jf.getString("shape") in setOf("key", "round"))
                    if (f.round) assertNotNull("$where: a round cap needs its ring", f.ring)
                    for (a in listOf(f.textureAlpha, f.sheenTop, f.sheenBottom, f.highlight, f.gloss, f.metal))
                        assertTrue("$where $cls: $a", a in 0f..1f)
                }
                val lg = js.getJSONObject("legend")
                assertEquals(lg.getString("style"), st.legend.style)
                // The return's glyph is never foil or glow (gold on gold vanished).
                assertEquals("$where return legend", js.optJSONObject("returnLegend")?.getString("style") ?: "engraved",
                    st.returnLegend.style)
                assertTrue("$where return legend", st.returnLegend.style in setOf("ink", "engraved", "letterpress"))
                assertTrue("$where legend ${st.legend.style}", st.legend.style in KeyboardThemes.LEGENDS)
                if (st.legend.style == "foil") assertEquals("$where foil stops", 3, st.legend.foil?.size)
                if (st.legend.style == "glow") assertNotNull("$where glow", st.legend.glow)
                val orns = js.getJSONArray("ornaments")
                assertEquals("$where ornaments", orns.length(), st.ornaments.size)
                for ((k, o) in st.ornaments.withIndex()) {
                    val jo = orns.getJSONObject(k)
                    assertEquals(jo.getString("on"), o.on)
                    assertEquals(jo.getJSONArray("ops").length(), o.ops.size)
                    assertTrue("$where on ${o.on}", o.on in KeyboardThemes.ORNAMENT_KEYS)
                    assertTrue("$where anchor ${o.anchor}", o.anchor in KeyboardThemes.ANCHORS)
                    assertTrue("$where alpha ${o.alpha}", o.alpha in 0f..1f)
                    for (c in listOfNotNull(o.color) + o.ops.mapNotNull { it.color })
                        assertTrue("$where colour $c", c in KeyboardThemes.COLOR_ROLES || Regex("#[0-9A-Fa-f]{6}").matches(c))
                    for (op in o.ops) {
                        assertTrue("$where op ${op.t}", op.t in KeyboardThemes.OPS)
                        val n = when (op.t) { "line" -> 4; "circle" -> 3; "rect" -> 5; "text" -> 2; else -> -1 }
                        if (n > 0) assertEquals("$where ${op.t} points", n, op.p.size)
                        else assertTrue("$where poly", op.p.size >= 6 && op.p.size % 2 == 0)
                        if (op.t == "line") assertTrue("$where line width", op.w > 0f)
                        if (op.t == "text") {
                            assertTrue("$where text", !op.s.isNullOrEmpty() && op.size > 0f)
                            assertTrue("$where font ${op.font}", op.font in KeyboardThemes.OP_FONTS)
                        }
                    }
                }
            }
        }
    }

    @Test fun everyTextureShipsInTheAppsAssets() {
        // The IME reads them from flutter_assets/assets/themes/textures (and
        // the picker from the same files): each the shared copy, byte for byte.
        val shared = File(repo, "shared/themes/textures")
        val app = File(appRoot, "assets/themes/textures")
        val names = KeyboardThemes.ALL.flatMap { t -> listOf(t.light, t.dark) }
            .flatMap { v -> listOf("letter", "function", "space", "return").mapNotNull { v.style.face(it).texture } }
            .toSet()
        assertTrue(names.isNotEmpty())
        for (n in names) {
            val a = File(app, "$n.png")
            assertTrue("missing $a", a.isFile)
            assertTrue("$a differs from shared/themes/textures", a.readBytes().contentEquals(File(shared, "$n.png").readBytes()))
        }
        assertTrue(File(appRoot, "pubspec.yaml").readText().contains("- assets/themes/textures/"))
        assertEquals("flutter_assets/assets/themes/textures/", ThemeTextureTiles.DIR)
    }

    private fun assertNotSame(a: Any, b: Any) = assertTrue(a !== b)
}
