package com.arpit.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Sends to a .sol name, read as the iPhone's TradeIntentTests read them,
 *  and the strip's Send chip once the name is looked up. */
class NameSendTest {
    private val owner = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"

    @Test fun aSendToASolNameIsRead() {
        assertEquals(NameSend.Ask("arpit.sol", "1.5", "SOL"), NameSend.parse("send 1.5 sol to Arpit.SOL"))
        assertEquals(NameSend.Ask("arpit.sol", "5", "USDC"), NameSend.parse("pay arpit.sol 5 usdc"))
        assertEquals(NameSend.Ask("pay.arpit.sol", "20", "USDC"), NameSend.parse("ok done. pls transfer 20 usdc to pay.arpit.sol"))
        assertEquals(NameSend.Ask("arpit.sol", "1000", "USDC"), NameSend.parse("send 1,000 usdc to arpit.sol"))
    }

    @Test fun whatSendCantPayIsNotRead() {
        for (text in listOf("send usdc to arpit.sol", "send 5 usdt to arpit.sol", "send 5 usdc to arpit.eth",
                            "send 0 sol to arpit.sol", "I'll send 5 usdc to arpit.sol later", "arpit.sol")) {
            assertNull(text, NameSend.parse(text))
        }
    }

    @Test fun theLookupSaysTheAddressOrWhyNot() {
        val found = JSONObject().put("ok", true).put("found", true)
            .put("addresses", JSONObject().put("solana", owner))
        assertEquals(NameSend.Lookup.Found(owner), NameSend.answer("arpit.sol", 200, found))
        assertEquals(NameSend.Lookup.Missing("nobody.sol isn’t registered"),
            NameSend.answer("nobody.sol", 404, JSONObject().put("ok", false).put("found", false)))
        assertEquals(NameSend.Lookup.Missing("Couldn’t look up arpit.sol"),
            NameSend.answer("arpit.sol", 503, JSONObject().put("ok", false)))
        assertEquals(NameSend.Lookup.Missing("arpit.sol has no Solana address"),
            NameSend.answer("arpit.sol", 200, JSONObject().put("addresses", JSONObject().put("solana", "0x12"))))
    }

    @Test fun theStripShowsTheAddressBeforeSend() {
        val names = mapOf("arpit.sol" to NameSend.Lookup.Found(owner),
                          "nobody.sol" to NameSend.Lookup.Missing("nobody.sol isn’t registered"))
        val chip = Smart.chip("send 1.5 sol to arpit.sol", emptyList(), names = names)
        assertEquals(Smart.Chip.Pay(owner, "1.5", "SOL", name = "arpit.sol"), chip)
        assertEquals("arpit.sol", Smart.key(chip!!))
        assertEquals("1.5 SOL to 7xKX…gAsU", Smart.display(chip))
        assertEquals("Send", Smart.verb(chip))
        // Not looked up yet: nothing, until the lookup lands.
        assertNull(Smart.chip("send 1.5 sol to other.sol", emptyList(), names = names))
        // Your own wallet is not someone to pay.
        assertNull(Smart.chip("send 1.5 sol to arpit.sol", emptyList(), ownWallet = owner, names = names))
        val missing = Smart.chip("pay nobody.sol 5 usdc", emptyList(), names = names)!!
        assertEquals("nobody.sol isn’t registered", Smart.display(missing))
        assertEquals("OK", Smart.verb(missing))
    }
}
