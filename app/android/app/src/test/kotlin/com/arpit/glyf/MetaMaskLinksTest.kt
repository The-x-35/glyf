package com.arpit.glyf

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The bridge opens MetaMask's own links in MetaMask, and nothing else. */
class MetaMaskLinksTest {
    @Test fun onlyMetaMasksSchemeIsOpened() {
        assertTrue(MetaMaskLinks.accepts("metamask://connect?scheme=glyf&channelId=x&comm=deeplinking"))
        assertTrue(MetaMaskLinks.accepts("metamask://mmsdk?scheme=glyf&message=eyJ9&account=0xabc@0x2105"))
        assertTrue(MetaMaskLinks.accepts("metamask://"))
        assertFalse(MetaMaskLinks.accepts(null))
        assertFalse(MetaMaskLinks.accepts("https://metamask.app.link/dapp/evil.example"))
        assertFalse(MetaMaskLinks.accepts("glyf://mmsdk?message=x"))
        assertFalse(MetaMaskLinks.accepts("intent://metamask#Intent;end"))
        assertFalse(MetaMaskLinks.accepts("metamask://" + "a".repeat(64_000)))
    }

    @Test fun itOpensInMetaMaskByItsPackage() {
        assertEquals("io.metamask", MetaMaskLinks.PACKAGE)
    }
}
