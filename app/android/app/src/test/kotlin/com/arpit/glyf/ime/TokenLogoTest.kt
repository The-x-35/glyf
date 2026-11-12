package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The trade panel's token search and logos (TradeSurface.swift's search
 *  mode and TokenLogo): what is asked, what is listed, and the placeholder
 *  a token without a picture gets. */
class TokenLogoTest {

    @Test fun onlyHttpsPicturesAreFetched() {
        assertTrue(TokenLogo.usable("https://assets.coingecko.com/coins/images/6319/small/usdc.png"))
        for (url in listOf(null, "", "https://", "http://x/usdc.png", "ipfs://QmXyz", "file:///sdcard/a.png")) {
            assertFalse("$url", TokenLogo.usable(url))
        }
    }

    @Test fun thePlaceholderIsTheSameEachTime() {
        // iOS: the sum of the symbol's characters picks one of six colours.
        assertEquals(TokenLogo.placeholderColors[("USDC".sumOf { it.code }) % 6],
            TokenLogo.placeholderColor("USDC"))
        assertEquals(TokenLogo.placeholderColor("PEPE"), TokenLogo.placeholderColor("PEPE"))
        assertEquals(6, TokenLogo.placeholderColors.size)
        assertEquals(0xFF617DFA.toInt(), TokenLogo.placeholderColors[0])
        assertEquals("P", TokenLogo.letter("pepe"))
        assertEquals("", TokenLogo.letter(""))
    }

    @Test fun aBigPictureIsDecodedSmall() {
        assertEquals(1, TokenLogo.sampleSize(64, 64))
        assertEquals(1, TokenLogo.sampleSize(100, 100))
        assertEquals(2, TokenLogo.sampleSize(128, 128))
        assertEquals(8, TokenLogo.sampleSize(512, 300))
        assertEquals(4, TokenLogo.sampleSize(300, 256))
        assertEquals(1, TokenLogo.sampleSize(0, 0))
    }

    @Test fun aTypedSearchAsksUniswapsList() {
        assertEquals("/uniswap/tokens?chain=base&q=pepe&limit=40", TradeQuote.tokenSearchPath("base", " pepe "))
        assertEquals("/uniswap/tokens?chain=arbitrum&q=wrapped+btc&limit=40", TradeQuote.tokenSearchPath("arbitrum", "wrapped btc"))
        assertNull(TradeQuote.tokenSearchPath("base", "  "))
        // Solana's tokens are the phone's short list.
        assertNull(TradeQuote.tokenSearchPath("solana", "bonk"))
    }

    @Test fun aSearchListsWhatMatchesOnceWithTheServersLogos() {
        val phone = TradeEdit.builtIn("base")
        // What Uniswap's list answers for each search.
        val pepeAnswer = listOf(TokenPick("PEPE", "Pepe", "0x6982508145454ce325ddbe47a25d4ec3d2311933", 18, "https://x/pepe.png"))
        val usdAnswer = listOf(TokenPick("USDC", "USD Coin", "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", 6, "https://x/usdc.png"),
            TokenPick("USDbC", "USD Base Coin", "0xd9aaec86b65d86f6a7b5b1b0c42ffa531710b6ca", 6, null))
        val pepe = TradeQuote.searchRows(phone, pepeAnswer, "pepe")
        assertEquals(listOf("PEPE"), pepe.map { it.symbol })
        assertEquals("https://x/pepe.png", pepe.first().logo)
        // The phone's own USDC first, once, with the logo the server sent.
        val usd = TradeQuote.searchRows(phone, usdAnswer, "usd")
        assertEquals(listOf("USDC", "USDbC"), usd.map { it.symbol })
        assertEquals("https://x/usdc.png", usd.first().logo)
        assertTrue(TradeQuote.searchRows(phone, emptyList(), "zzz").isEmpty())
    }
}
