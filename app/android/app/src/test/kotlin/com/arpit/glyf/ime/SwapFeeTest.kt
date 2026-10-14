package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Glyf's 0.5% on a buy (docs/SWAP-FEE.md), the twin of the iOS and
 *  Flutter tests: sent only when a referral account is set. */
class SwapFeeTest {
    private val sol = "So11111111111111111111111111111111111111112"
    private val bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    private val referral = "18LeLp3B8yGctKtWKAXXqdB6Lf1GxmEa2fRL5xxa1ta"

    @Test fun shipsOffSoTheBuyQuoteIsAskedAsBefore() {
        assertEquals("", SwapFee.REFERRAL_ACCOUNT)
        assertEquals("https://api.jup.ag/swap/v2/order?inputMint=$sol&outputMint=$bonk&amount=100000000",
            SwapFee.orderUrl(sol, bonk, 100_000_000))
    }

    @Test fun aReferralAccountAddsItAndFiftyBps() {
        val url = SwapFee.orderUrl(sol, bonk, 5, referral)
        assertTrue(url.endsWith("&amount=5&referralAccount=$referral&referralFee=50"))
        assertTrue(SwapFee.BPS in 50..255)
    }

    @Test fun theFeeShowsOnlyWhenJupiterAppliedIt() {
        // Recorded from /swap/v2/order, 2026-10-14.
        assertNull(SwapFee.applied(JSONObject().put("feeBps", 10).put("feeMint", sol)))
        assertNull(SwapFee.applied(JSONObject().put("feeBps", 10).put("referralAccount", JSONObject.NULL)))
        assertEquals(50, SwapFee.applied(JSONObject().put("feeBps", 50).put("referralAccount", referral)))
        assertEquals("Fee 0.5%", SwapFee.label(50))
        assertEquals("Fee 1%", SwapFee.label(100))
        assertEquals("Fee 2.55%", SwapFee.label(255))
    }
}
