package com.demo.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    @Test fun moneyWhereYouAreAndNeverAGuess() {
        val rates = Smart.RatesSnapshot(
            fiat = mapOf("USD" to 1.0, "INR" to 95.88, "EUR" to 0.8726),
            crypto = mapOf("SOL" to 111.77), local = "INR")
        assertEquals(Smart.Chip.Money("$13 = ₹1,246.44", " = ₹1,246.44"), Smart.chip("it costs $13", vault, rates = rates))
        assertEquals(Smart.Chip.Money("₹500 = $5.21", " = $5.21"), Smart.chip("₹500", vault, rates = rates))
        assertEquals("€20 = ₹2,197.57", Smart.display(Smart.chip("about 20 euros", vault, rates = rates)!!))
        assertEquals(Smart.Chip.Money("1 SOL = $111.77", " = $111.77"), Smart.chip("buying \$sol", vault, rates = rates))
        assertNull(Smart.chip("\$13", vault))
        assertEquals(true, Smart.looksLikeMoney("\$13"))
        assertEquals(false, Smart.looksLikeMoney("flight AI 2021"))
        assertEquals("SOL", Smart.cashtag("send \$sol"))
        assertNull(Smart.cashtag("\$13"))
        // A name works too, for whoever doesn't know the ticker.
        assertNull(Smart.cashtag("whats \$apple at"))
        assertEquals("BITCOIN", Smart.cashtag("how is \$bitcoin"))
        assertEquals("MICROSOFT", Smart.cashtag("\$microsoft"))
        assertNull(Smart.chip("\$usdc", vault, rates = rates))
        assertEquals(Smart.Chip.Calc("$30", false), Smart.chip("\$10*3", vault, rates = rates))
        val home = Smart.RatesSnapshot(fiat = mapOf("USD" to 1.0, "INR" to 95.88), local = "USD")
        assertNull(Smart.chip("\$13", vault, rates = home))
    }

    @Test fun bookingPages() {
        assertEquals("cal.com/sam/intro", Smart.bookingLink("grab a slot: cal.com/sam/intro"))
        assertEquals("https://calendly.com/ria", Smart.bookingLink("book me here https://calendly.com/ria"))
        assertEquals("physics.cal.com/rick/15min", Smart.bookingLink("physics.cal.com/rick/15min?x=1"))
        assertNull(Smart.bookingLink("mail sam@cal.com"))
        // The person's own page is theirs to send, not to book.
        assertNull(Smart.bookingLink("cal.com/me/15min", own = "https://cal.com/me"))
        assertEquals("A time on calendly.com/ria", Smart.display(Smart.Chip.Booking("https://calendly.com/ria")))
        assertEquals(Smart.Chip.Booking("cal.com/sam/intro"), Smart.chip("grab a slot: cal.com/sam/intro", vault))
    }

    @Test fun modelSuggestion() {
        // A sparkle marks it: its words are the action, and a tap types nothing.
        val chip = Smart.Chip.Action("Tidy this up", "ya ok will send the deck", "rewrite")
        assertNull(Smart.verb(chip))
        assertEquals("Tidy this up", Smart.display(chip))
        assertEquals("", Smart.insert(chip))
    }

    @Test fun notSums() {
        // Not a sum; a plan, which the calendar offers to add instead.
        assertTrue(Smart.chip("call me at 5", vault) is Smart.Chip.Event)
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
        val bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
        // Not known yet: no chip, and the keyboard is told what to look up.
        assertNull(Smart.chip("send 25 usdc to $addr", vault))
        assertEquals(addr, Smart.addressToCheck("send 25 usdc to $addr", Smart.RatesSnapshot.EMPTY))
        val rates = Smart.RatesSnapshot(addresses = mapOf(addr to Smart.AddressKind.Wallet,
            bonk to Smart.AddressKind.Token("Bonk", 0.0000036)))
        assertNull(Smart.addressToCheck("send 25 usdc to $addr", rates))

        val chip = Smart.chip("send 25 usdc to $addr", vault, rates = rates) as Smart.Chip.Pay
        assertEquals(Smart.Chip.Pay(addr, "25", "USDC"), chip)
        assertEquals("Wallet", Smart.key(chip))
        assertEquals("25 USDC to 7xKX…gAsU", Smart.display(chip))
        assertEquals("Send", Smart.verb(chip))
        assertEquals(Smart.Chip.Pay(addr, "0.5", "SOL"), Smart.chip("0.5 sol to $addr pls", vault, rates = rates))
        assertEquals(Smart.Chip.Pay(addr), Smart.chip("₹500 to $addr", vault, rates = rates))
        // Your own wallet is one you are sharing, not paying.
        assertNull(Smart.chip("here $addr", vault, rates = rates, ownWallet = addr))

        val buy = Smart.chip("ape this $bonk", vault, rates = rates)
        assertEquals(Smart.Chip.Buy(bonk, "Bonk", "$0.0000036"), buy)
        assertEquals("Bonk", Smart.key(buy!!))
        assertEquals("$0.0000036", Smart.display(buy))
        assertEquals("Buy", Smart.verb(buy))
        assertNull(Smart.payment("thisisaverylongsentencewithoutanydigitsatall"))
    }

    @Test fun aTickersPriceOffersBuyWhenItCanBeBought() {
        val sol = "So11111111111111111111111111111111111111112"
        val rates = Smart.RatesSnapshot(crypto = mapOf("SOL" to 111.77, "BONK" to 0.0000036), mints = mapOf("SOL" to sol))
        assertEquals(Smart.Chip.Money("1 SOL = $111.77", " = $111.77", sol), Smart.chip("buying \$sol", vault, rates = rates))
        assertEquals(Smart.Chip.Money("1 BONK = $0.0000036", " = $0.0000036"), Smart.chip("\$bonk", vault, rates = rates))
        assertEquals("$0.50", Smart.price(0.5))
        assertEquals("$0.0823", Smart.price(0.08234))
        assertEquals("$1,234.50", Smart.price(1234.5))
        assertEquals("$0.00000364", Smart.price(0.00000364))
    }
}
