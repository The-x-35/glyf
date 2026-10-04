package com.arpit.glyf.store

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SecretScannerTest {
    private val keys = "Keys and tokens can't be saved"

    @Test fun keysAndTokensAreRefused() {
        // Found on a real clipboard (2026-09-24): a 38-character webhook
        // signing secret went into history under the old rules.
        assertEquals(keys, SecretScanner.scan("whsec_Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4z"))
        assertEquals(keys, SecretScanner.scan("github_pat_11ABCDEFG0123456789_abcdefghij"))
        assertEquals(keys, SecretScanner.scan("AIzaSyA1b2C3d4E5f6G7h8I9j0KlMnOpQrStUvW"))
        assertEquals(keys, SecretScanner.scan("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcdefghijklmnop"))
        assertEquals(keys, SecretScanner.scan("Zq8Lr2Tx5Vm9Kc3Pw7Jd1Hs6Gf4Nb0Ya"))
        assertEquals(keys, SecretScanner.scan("sk-or-v1-aaaaaaaaaaaaaaaaaaaa"))
        assertEquals(keys, SecretScanner.scan("-----BEGIN PRIVATE KEY-----\nxx"))
    }

    @Test fun ordinaryCopiesStay() {
        assertNull(SecretScanner.scan("See you at Sunset Boulevard at 7pm"))
        assertNull(SecretScanner.scan("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        assertNull(SecretScanner.scan("sk-"))
        // Wallet addresses are for sharing (the pay chip reads a copied one).
        assertNull(SecretScanner.scan("8QvSMrFfYYo2RwoDN6bNpS2d3F8JKTzN8Cw2vAh3tNqP"))
        assertNull(SecretScanner.scan("0x52908400098527886E0F7030069857D2E4169EE7"))
        assertNull(SecretScanner.scan("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"))
    }
}
