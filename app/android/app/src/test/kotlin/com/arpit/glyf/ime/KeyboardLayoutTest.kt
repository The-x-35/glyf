package com.arpit.glyf.ime

import com.arpit.glyf.ime.typing.KeyGeometry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Layout settings (Keyboard › Layout), RunnerTests'
 *  KeyboardLayoutChoiceTests twin: the defaults are today's keyboard, every
 *  letter layout fits today's grid, and the comma and period keys sit beside
 *  the space bar only on a text field's letters. */
class KeyboardLayoutTest {

    private val contexts = listOf(KContext.TEXT, KContext.EMAIL, KContext.URL, KContext.WEB_SEARCH)

    @Test fun defaultsAreTodaysKeyboard() {
        assertEquals(LetterLayout.QWERTY, LetterLayout.of(null))
        assertEquals(LetterLayout.QWERTY, LetterLayout.of("dvorak"))
        assertEquals(LetterLayout.AZERTY, LetterLayout.of("azerty"))
        for (context in contexts) for (mode in Mode.entries) {
            assertEquals(KeyboardLayout.rows(mode, false, context),
                KeyboardLayout.rows(mode, false, context, LetterLayout.of(null), comma = false, period = false))
        }
        assertEquals(listOf(
            "qwertyuiop".map { it.toString() },
            "asdfghjkl".map { it.toString() },
            listOf("shift") + "zxcvbnm".map { it.toString() } + listOf("delete"),
            listOf("mode:123", "emojikey", "space", "return"),
        ), KeyboardLayout.rows(Mode.LETTERS, false, KContext.TEXT).map { r -> r.map { it.id } })
    }

    /** iOS's rows, layout for layout (LetterLayout in KeyboardLayout.swift). */
    @Test fun sameLayoutsAsTheIPhone() {
        assertEquals(listOf("qwerty", "qwertz", "azerty", "colemak"), LetterLayout.entries.map { it.id })
        assertEquals(listOf("qwertzuiop", "asdfghjkl", "yxcvbnm"), LetterLayout.QWERTZ.rows)
        assertEquals(listOf("azertyuiop", "qsdfghjklm", "wxcvbn'"), LetterLayout.AZERTY.rows)
        assertEquals(listOf("qwfpgjluy'", "arstdhneio", "zxcvbkm"), LetterLayout.COLEMAK.rows)
    }

    /** All 26 letters once; every row adds up to ten columns of today's
     *  units, so no key changes size; shift, delete and the bottom row stay. */
    @Test fun everyLayoutFitsTodaysGrid() {
        val qwerty = KeyboardLayout.rows(Mode.LETTERS, false, KContext.TEXT)
        for (letters in LetterLayout.entries) {
            val rows = KeyboardLayout.rows(Mode.LETTERS, false, KContext.TEXT, letters)
            val found = rows.flatten().mapNotNull { it.char }.filter { it.length == 1 && it[0] in 'a'..'z' }
            assertEquals(letters.id, ('a'..'z').map { it.toString() }, found.sorted())
            for (row in rows.dropLast(1)) {
                assertTrue(letters.id, row.sumOf { it.units.toDouble() } <= 10.0)
                for (k in row) if (k.char != null) assertEquals(1f, k.units)
            }
            assertEquals(qwerty[2].first(), rows[2].first())
            assertEquals(qwerty[2].last(), rows[2].last())
            assertEquals(qwerty.last(), rows.last())
        }
    }

    @Test fun commaAndPeriodBesideSpace() {
        fun bottom(comma: Boolean, period: Boolean) =
            KeyboardLayout.rows(Mode.LETTERS, false, KContext.TEXT, comma = comma, period = period).last()
        assertEquals(listOf("mode:123", "emojikey", ",", "space", ".", "return"), bottom(true, true).map { it.id })
        assertEquals(listOf("mode:123", "emojikey", ",", "space", "return"), bottom(true, false).map { it.id })
        assertEquals(listOf("mode:123", "emojikey", "space", ".", "return"), bottom(false, true).map { it.id })
        // As wide as the emoji key, taken from the space bar.
        val row = bottom(true, true)
        assertEquals(1.25f, row[2].units)
        assertEquals(1.25f, row[4].units)
        assertEquals(10f, row.filter { it.units > 0 }.sumOf { it.units.toDouble() }.toFloat() + 2.5f)
        assertEquals(",", row[2].char)
        assertEquals(".", row[4].char)
        // Never on the symbols pages, nor in fields with rows of their own.
        for (mode in listOf(Mode.SYMBOLS1, Mode.SYMBOLS2)) {
            assertEquals(KeyboardLayout.rows(mode, false, KContext.TEXT),
                KeyboardLayout.rows(mode, false, KContext.TEXT, comma = true, period = true))
        }
        for (context in contexts.drop(1) + listOf(KContext.NUMBER_PAD, KContext.PHONE_PAD)) {
            assertEquals(KeyboardLayout.rows(Mode.LETTERS, false, context),
                KeyboardLayout.rows(Mode.LETTERS, false, context, comma = true, period = true))
        }
    }

    /** The corrector's grid follows the picked layout, column for column. */
    @Test fun keyGeometryFollowsTheLayout() {
        val q = KeyGeometry()
        val same = KeyGeometry(rows = LetterLayout.QWERTY.rows)
        for (c in 97..122) {
            assertEquals(q.centerX(c), same.centerX(c))
            assertEquals(q.centerY(c), same.centerY(c))
        }
        assertEquals(0.5f, q.centerX('q'.code)); assertEquals(1.0f, q.centerX('a'.code)); assertEquals(2.0f, q.centerX('z'.code))
        for (letters in LetterLayout.entries) {
            val g = KeyGeometry(rows = letters.rows)
            letters.rows.forEachIndexed { r, row ->
                val offset = if (r == 2) 1.5f else (10 - row.length) / 2f
                row.forEachIndexed { k, ch ->
                    if (ch !in 'a'..'z') return@forEachIndexed
                    assertEquals("${letters.id} $ch", k + 0.5f + offset, g.centerX(ch.code), 1e-4f)
                    assertEquals((r + 0.5f) * g.rowPitch, g.centerY(ch.code), 1e-4f)
                }
            }
        }
        val az = KeyGeometry(rows = LetterLayout.AZERTY.rows)
        assertTrue(az.isNear(az.centerX('a'.code), az.centerY('a'.code), 'z'.code))
        assertFalse(q.isNear(q.centerX('a'.code), q.centerY('a'.code), 'p'.code))
    }
}
