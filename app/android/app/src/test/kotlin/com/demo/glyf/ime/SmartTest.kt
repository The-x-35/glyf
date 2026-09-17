package com.demo.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The same cases as the iOS Smart tests: both strips must agree. */
class SmartTest {
    private val vault = listOf(
        Smart.Field("address", "Home", "42 Glass Lane, Indiranagar, Bengaluru 560038"),
        Smart.Field("upi", "UPI", "arpit@okbank"),
        Smart.Field("handle", "Insta", "@arpit"),
    )

    @Test fun sumsInASentence() {
        assertEquals(Smart.Chip.Calc("870", false), Smart.chip("split is 3480/4", vault))
        assertEquals(" = 870", Smart.insert(Smart.chip("split is 3480/4", vault)!!))
        assertEquals(Smart.Chip.Calc("441", false), Smart.chip("18% of 2450", vault))
        assertEquals(Smart.Chip.Calc("₹1,23,456", true), Smart.chip("₹123456*1 =", vault))
        assertEquals("123,456", Smart.format(123456.0, indian = false))
        assertEquals("12.5", Smart.format(12.5, indian = true))
        assertEquals(Smart.Chip.Calc("7", false), Smart.chip("(2+5)", vault))
    }

    @Test fun notSums() {
        assertNull(Smart.chip("call me at 5", vault))
        assertNull(Smart.chip("flight AI 2021", vault))
        assertNull(Smart.chip("4/0", vault))
        assertNull(Smart.evaluate("2+abc"))
    }

    @Test fun detailsInEverydayWords() {
        val more = vault + listOf(Smart.Field("phone", "Mobile", "+91 98765 43210"), Smart.Field("email", "Email", "a@b.co"))
        assertEquals("upi", Smart.chip("just gpay me on", more).let { (it as Smart.Chip.Vault).field.kind })
        assertEquals("address", (Smart.chip("haan ship it to", more) as Smart.Chip.Vault).field.kind)
        assertEquals("phone", (Smart.chip("ok here's my number:", more) as Smart.Chip.Vault).field.kind)
        assertEquals("email", (Smart.chip("you can email me at", more) as Smart.Chip.Vault).field.kind)
        // Asking someone else, or already typed, or nothing saved of that kind.
        assertNull(Smart.chip("what's your address?", more))
        assertNull(Smart.chip("send me ur upi", more))
        assertNull(Smart.chip("my number is 98765", more))
        assertNull(Smart.chip("my wallet address", more))
    }

    @Test fun detailsTheSentenceAsksFor() {
        assertEquals("42 Glass Lane, Indiranagar, Bengaluru 560038",
            (Smart.chip("sure my address is ", vault) as Smart.Chip.Vault).field.value)
        assertEquals("arpit@okbank", (Smart.chip("my upi is", vault) as Smart.Chip.Vault).field.value)
        assertEquals("arpit@okbank", (Smart.chip("pay me at ", vault) as Smart.Chip.Vault).field.value)
        assertEquals("@arpit", (Smart.chip("my insta is ", vault) as Smart.Chip.Vault).field.value)
        assertNull(Smart.chip("my email is ", vault))
        assertNull(Smart.chip("the address was wrong yesterday", vault))
    }

    @Test fun paymentAddresses() {
        val addr = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
        val chip = Smart.chip("send 25 usdc to $addr", vault) as Smart.Chip.Pay
        assertEquals(addr, chip.address)
        assertEquals("25", chip.amount)
        assertNull(Smart.payment("thisisaverylongsentencewithoutanydigitsatall"))
    }
}
