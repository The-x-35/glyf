package com.arpit.glyf.ime

import com.arpit.glyf.store.ClipboardStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS VaultTests.testDetailsGoToTheAIAsStandIns, testCardsAndPasswordsShowMasked
 *  and GlyfEngineTests.testClipboardKeepsSecretsMaskedAndRefusesDuplicates. */
class StandInsTest {
    @Test fun detailsGoToTheAIAsStandIns() {
        val fields = listOf(
            Smart.Field("address", "Home", "123 Market St"),
            Smart.Field("email", "Work email", "sam@work.com"),
            Smart.Field("card", "Visa", "4242 4242 4242 4242"),
        )
        val table = StandIns.table(fields)
        assertEquals(setOf("home address", "work email", "visa card"), table.keys)
        assertEquals("Send it to 123 Market St. Mail me at sam@work.com, card 4242 4242 4242 4242.",
            StandIns.fill("Send it to {home address}. Mail me at {Work Email}, card {visa card}.", table))
        assertEquals("keep {this} and {unknown}", StandIns.fill("keep {this} and {unknown}", table))
    }

    @Test fun cardsAndPasswordsShowMasked() {
        assertEquals("Visa •••• 4242", StandIns.shown(Smart.Field("card", "Visa", "4242 4242 4242 4242")))
        assertEquals("Wi-Fi ••••••", StandIns.shown(Smart.Field("password", "Wi-Fi", "hunter2")))
        assertEquals("sam@example.com", StandIns.shown(Smart.Field("email", "Email", "sam@example.com")))
    }

    @Test fun clipboardKeepsSecretsMasked() {
        val items = listOf(ClipboardStore.Item("hello", 0L, false))
        val card = ClipboardStore.inserting("4242 4242 4242 4242", items, 1L)!!.first()
        assertTrue(card.sensitive)
        assertEquals("Card •••• 4242", card.shown)
        assertEquals("•••••••••••", ClipboardStore.inserting("hunter2pass", items, 1L, sensitive = true)!!.first().shown)
        assertFalse(ClipboardStore.inserting("world", items, 1L)!!.first().sensitive)
    }
}
