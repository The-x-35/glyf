package com.arpit.glyf.ime

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
        // The strip reads the whole sum: "2+5 = 7".
        assertEquals("2+5 = 7", Smart.display(Smart.chip("2+5", vault)!!))
        assertEquals("12 * 12 = 144", Smart.display(Smart.chip("what is 12 * 12", vault)!!))
    }

    /** iOS GlyfEngineTests.testMoneyShowsBothCentsPlacesOrNone: "₹1,919.6"
     *  read as a typo. */
    @Test fun moneyShowsBothCentsPlacesOrNone() {
        assertEquals("₹1,919.60", Smart.format(1919.6, "INR"))
        assertEquals("₹1,919", Smart.format(1919.0, "INR"))
        assertEquals("$20", Smart.format(20.0, "USD"))
        assertEquals("$12.50", Smart.format(12.5, "USD"))
        assertEquals("$1", Smart.format(0.999, "USD"))
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

    /** "$sol" is SOL's price, never your wallet (SmartTest twin of
     *  testACashtagIsAPriceNeverYourWallet). */
    @Test fun aCashtagIsAPriceNeverYourWallet() {
        val wallet = listOf(Smart.Field("wallet", "Solana", "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"))
        assertNull(Smart.chip("\$sol", wallet))
        assertNull(Smart.chip("whats \$solana at", wallet))
        val rates = Smart.RatesSnapshot(crypto = mapOf("SOL" to 117.66, "APPL" to 339.43),
            tickers = mapOf("SOL" to "SOL", "APPL" to "AAPL"))
        assertEquals(Smart.Chip.Money("1 SOL = \$117.66", " = \$117.66"), Smart.chip("\$sol", wallet, rates = rates))
        assertEquals("1 AAPL = \$339.43", Smart.display(Smart.chip("\$appl", wallet, rates = rates)!!))
        assertEquals(Smart.Chip.Vault(wallet[0]), Smart.chip("my sol address is", wallet))
        assertEquals(Smart.Chip.Vault(wallet[0]), Smart.chip("solana wallet:", wallet))
        assertEquals(Smart.Chip.Vault(wallet[0]), Smart.chip("send it to my wallet", wallet))
        assertNull(Smart.chip("i bought some sol", wallet))
        assertNull(Smart.chip("is usdc", wallet))
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
        // A flight number, not a sum: its status link (Smart.flight).
        assertEquals(listOf("Air India 2021 status"),
            (Smart.chip("flight AI 2021", vault) as? Smart.Chip.Convert)?.answer?.results)
        assertNull(Smart.chip("4/0", vault))
        assertNull(Smart.evaluate("2+abc"))
    }

    /** Every maths symbol answers in the strip (Arpit, 2026-09-29: "not
     *  working on 2-3 ... work for all maths symbols"); only phone numbers,
     *  whole dates, counts and a "<3" heart stay quiet (Smart.swift twin). */
    @Test fun everyOperatorAnswersButPhoneNumbersAndDatesDoNot() {
        val sums = listOf("2-3" to "-1", "3-2" to "1", "10-11" to "-1", "9-5" to "4", "150-45" to "105",
            "5 - 2" to "3", "-5+3" to "-2", "7−2" to "5", "2x3" to "6", "2 x 3" to "6", "2**10" to "1,024",
            "2^10" to "1,024", "√16" to "4", "√2*√2" to "2", "π*2" to "6.28", "10 mod 3" to "1",
            "24/7" to "3.43", "20% of 150" to "30", "the room is 10 x 12" to "120")
        for ((t, want) in sums) assertEquals(t, want, Smart.calc(t, indianGrouping = false)?.first)
        assertEquals("true" to false, Smart.calc("5>3"))
        assertEquals("false" to false, Smart.calc("2 < 1"))
        assertEquals("true" to false, Smart.calc("10 >= 10"))
        assertEquals("7" to true, Smart.calc("10-3="))
        assertEquals("2-3 = -1", Smart.display(Smart.chip("2-3", vault)!!))
        for (t in listOf("call me at 555-1234", "555-1234", "555-123-4567", "+1-555-123-4567", "98765-43210",
            "born 29/09/2024", "2024/09/29", "2024-09-29", "29-09-2024", "exp 09/2026", "page 2 of 10",
            "episode 4 of 8", "love u 2 <3", "its 50%", "we won 3")) {
            assertNull(t, Smart.calc(t))
        }
    }

    /** Whole dates are numbers over numbers, not sums; a percentage added or
     *  taken off is a share of the left side (Smart.swift twin). */
    @Test fun datesAreNotSumsAndPercentagesAreShares() {
        assertNull(Smart.calc("see you 29/09/2024"))
        // A score or a range at the end of a sentence is no sum (2026-10-14).
        assertNull(Smart.calc("the score was 3-1"))
        assertNull(Smart.calc("pick a number 1-10"))
        assertEquals("7" to false, Smart.calc("whats 10-3"))
        assertEquals("8" to false, Smart.calc("10-2"))
        assertNull(Smart.calc("due 2026/09/28"))
        assertNull(Smart.chip("card expires 09/2026", vault) as? Smart.Chip.Calc)
        // Asked for with "=", or with bigger numbers, it is still a sum.
        assertEquals("3" to true, Smart.calc("12/4 ="))
        assertEquals("870" to false, Smart.calc("3480/4"))
        assertEquals(Smart.Chip.Calc("220", false), Smart.chip("200 + 10%", vault))
        assertEquals(Smart.Chip.Calc("180", false), Smart.chip("200 - 10%", vault))
        assertEquals(Smart.Chip.Calc("441", false), Smart.chip("18% of 2450", vault))
        // Only a bare percentage is a share: 10% / 4 is a number like any other.
        assertEquals(20.025, Smart.evaluate("20+10%/4")!!, 1e-9)
    }

    /** The detail the sentence names: an email address is an email, an IP
     *  or web address is nobody's home, and an account or card number is
     *  not a phone (Smart.swift twin). */
    /** A saved detail only where the sentence leads into it (2026-09-28
     *  audit: "wrong address", "can you email" and "i lost my phone" offered
     *  yours). GlyfEngineTests.testADetailOnlyWhereTheSentenceLeadsIntoIt. */
    @Test fun aDetailOnlyWhereTheSentenceLeadsIntoIt() {
        val all = listOf(
            Smart.Field("address", "Home", "123 Market St"),
            Smart.Field("email", "Email", "me@example.com"),
            Smart.Field("phone", "Mobile", "+1 415 555 0100"),
            Smart.Field("wallet", "Wallet address", "4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA"),
            Smart.Field("social", "Instagram", "@me"),
            Smart.Field("upi", "UPI", "me@okbank"))
        val asks = listOf(
            "my email is" to "email", "Email ID:" to "email", "you can email me at" to "email",
            // The word alone asks for it (Arpit, 2026-10-01: "when i type email
            // it should show my email id from vault").
            "email" to "email", "send it to my email" to "email", "email id" to "email",
            "gmail" to "email", "mail id" to "email", "ok, email" to "email",
            "address:" to "address", "our office address:" to "address", "ship it to" to "address",
            "my number is" to "phone", "phone:" to "phone", "reach me at" to "phone",
            "my wallet" to "wallet", "sol address:" to "wallet", "follow me on insta" to "social",
            "upi id:" to "upi")
        for ((text, kind) in asks) assertEquals(text, kind, Smart.vaultMatch(text, all)?.kind)
        // "email" the verb is about sending one, not yours.
        for (text in listOf("can you email", "i'll email", "please email", "pls email", "we'll email",
                "could u email", "can you email the deck", "hotmail", "voicemail", "what's the address", "wrong address",
                "the address is", "ip address:", "i lost my phone", "my phone is dead",
                "phantom wallet is down", "saw it on insta", "i use paytm", "this is great",
                "my linkedin is")) {
            assertNull(text, Smart.vaultMatch(text, all))
        }
    }

    /** The first letters of a saved detail offer all of it (Arpit,
     *  2026-10-06: "as soon person enters first 2-4 letters of any details in
     *  vault show that"): GlyfEngineTests' testTheFirstLettersOfADetailOfferIt. */
    @Test fun theFirstLettersOfADetailOfferIt() {
        val mail = Smart.Field("email", "Email", "alex@example.com")
        val name = Smart.Field("name", "Name", "Alex Kim")
        val cell = Smart.Field("phone", "Mobile", "+1 (415) 555-0134")
        val home = Smart.Field("address", "Home", "123 Market St, San Francisco, CA 94103")
        val all = listOf(mail, name, cell, home)
        assertEquals(Smart.Chip.Details(listOf(mail, name), temp = false, typed = "al"), Smart.chip("al", all))
        assertEquals(Smart.Chip.Details(listOf(mail), temp = false, typed = "Alex@"), Smart.chip("write to Alex@", all))
        assertEquals(Smart.Chip.Details(listOf(cell), temp = false, typed = "415"), Smart.chip("call 415", all))
        assertEquals(Smart.Chip.Details(listOf(cell), temp = false, typed = "+1 (415"), Smart.chip("+1 (415", all))
        assertEquals(Smart.Chip.Details(listOf(home), temp = false, typed = "123 Mar"), Smart.chip("ship to 123 Mar", all))
        // One letter, two digits, a finished word, a whole detail: nothing.
        for (text in listOf("a", "41", "al ", "alex@example.com", "hello")) {
            assertEquals(text, null, Smart.chip(text, all))
        }
    }

    /** Two saved emails show both (Arpit, 2026-10-01: "if i added 2 mail ids
     *  i should see both"), in the vault's order; one shows the one chip it
     *  always did; a question for someone else shows none. */
    @Test fun everySavedValueOfTheKindTheSentenceAsksFor() {
        val work = Smart.Field("email", "Work", "alex.rivera@example.com")
        val home = Smart.Field("address", "Home", "123 Market St")
        val personal = Smart.Field("email", "Personal", "alex@gmail.com")
        val mobile = Smart.Field("phone", "Mobile", "+1 415 555 0100")
        val office = Smart.Field("phone", "Office", "+1 415 555 0199")
        val vault = listOf(work, home, personal, mobile, office)
        val both = Smart.Chip.Details(listOf(work, personal), temp = false)
        for (text in listOf("my email is", "email", "send it to my email", "Email ID:", "gmail", "email id")) {
            assertEquals(text, both, Smart.chip(text, vault))
        }
        assertEquals(listOf(work, personal), Smart.vaultMatches("my email is", vault))
        // One saved: the single chip, as before.
        assertEquals(Smart.Chip.Vault(work), Smart.chip("my email is", listOf(work, home)))
        assertEquals(Smart.Chip.Vault(work), Smart.chip("email", listOf(work, home)))
        // Someone else's, or the verb: nothing.
        for (text in listOf("your email", "what's your email", "send me ur email", "can you email",
                "i'll email", "please email")) {
            assertNull(text, Smart.chip(text, vault))
        }
        // A phone number, two saved: both.
        assertEquals(Smart.Chip.Details(listOf(mobile, office), temp = false), Smart.chip("my number is", vault))
        assertEquals(Smart.Chip.Details(listOf(mobile, office), temp = false), Smart.chip("call me at", vault))
        // At most three; a value saved twice shows once.
        val many = listOf(work, personal, Smart.Field("email", "Old", "a@b.co"), Smart.Field("email", "", "c@d.co"),
            Smart.Field("email", "Again", "alex@gmail.com"))
        assertEquals(listOf(work, personal, many[2]), (Smart.chip("email", many) as Smart.Chip.Details).fields)
        // A handle stays the platform's own.
        val handles = listOf(Smart.Field("social", "Instagram", "@alex"), Smart.Field("social", "LinkedIn", "in/alex"))
        assertEquals(Smart.Chip.Vault(handles[0]), Smart.chip("my insta is", handles))
        // An empty form field asking for a kind we hold: every value of it.
        assertEquals(both, Smart.chip("", vault, fieldKind = "email"))
        assertEquals(Smart.Chip.Vault(home), Smart.chip("", vault, fieldKind = "address"))
        assertNull(Smart.chip("", vault, fieldKind = "upi"))
        assertNull(Smart.chip("", vault))
        // What the chip says and does: each part is its own action.
        assertEquals("alex.rivera@example.com · alex@gmail.com", Smart.display(both))
        assertNull(Smart.verb(both))
        assertEquals("", Smart.insert(both))
    }

    /** An email chip gets Temp mail beside your emails (two at most); any
     *  other chip stays as it is. */
    @Test fun emailsComeWithATempAddress() {
        val work = Smart.Field("email", "Work", "alex.rivera@example.com")
        val personal = Smart.Field("email", "Personal", "alex@gmail.com")
        val old = Smart.Field("email", "Old", "a@b.co")
        val phone = Smart.Field("phone", "Mobile", "+1 415 555 0100")
        assertEquals(Smart.Chip.Details(listOf(work), temp = true), Smart.withTempMail(Smart.Chip.Vault(work)))
        assertEquals(Smart.Chip.Details(listOf(work, personal), temp = true),
            Smart.withTempMail(Smart.Chip.Details(listOf(work, personal, old), temp = false)))
        assertEquals(Smart.Chip.Details(listOf(work, personal), temp = true),
            Smart.withTempMail(Smart.chip("email", listOf(work, personal, phone))))
        assertEquals(Smart.Chip.Vault(phone), Smart.withTempMail(Smart.Chip.Vault(phone)))
        val phones = Smart.Chip.Details(listOf(phone, phone.copy(value = "+1 415 555 0199")), temp = false)
        assertEquals(phones, Smart.withTempMail(phones))
        assertNull(Smart.withTempMail(null))
        assertEquals("alex.rivera@example.com · Temp mail",
            Smart.display(Smart.Chip.Details(listOf(work), temp = true)))
    }

    /** A saved detail typed after a word gets a space before it ("email" +
     *  a tap is "email alex@…", never "emailalex@…"). */
    @Test fun aDetailIsSpacedFromTheWordBeforeIt() {
        assertEquals(" a@b.co", Smart.spaced("a@b.co", "email"))
        assertEquals(" a@b.co", Smart.spaced("a@b.co", "Email:"))
        assertEquals("a@b.co", Smart.spaced("a@b.co", "my email is "))
        assertEquals("a@b.co", Smart.spaced("a@b.co", "line one\n"))
        assertEquals("a@b.co", Smart.spaced("a@b.co", ""))
        assertEquals("a@b.co", Smart.spaced("a@b.co", null))
    }

    /** "I lost 5 pounds" is weight; a conversion the chip put in is not
     *  converted back. GlyfEngineTests.testPoundsOfWeightAndInsertedAnswersAreNotMoney. */
    @Test fun poundsOfWeightAndInsertedAnswersAreNotMoney() {
        val usd = Smart.RatesSnapshot(fiat = mapOf("USD" to 1.0, "GBP" to 0.75), local = "USD")
        assertEquals("£5 = \$6.67", Smart.display(Smart.chip("it costs 5 pounds", emptyList(), rates = usd, region = "US")!!))
        // Weight, never money: kilograms where pounds are weight (the US),
        // nothing where they are money.
        assertEquals(Smart.Chip.Convert(Smart.Conversions("5 pounds", listOf("2.27 kg", "2,268 g", "80 oz"))),
            Smart.chip("I lost 5 pounds", emptyList(), rates = usd, region = "US"))
        assertNull(Smart.chip("I lost 5 pounds", emptyList(), rates = usd, region = "GB"))
        assertEquals(Smart.Chip.Convert(Smart.Conversions("100 pounds", listOf("45.4 kg", "7.14 stone"))),
            Smart.chip("bench press 100 pounds", emptyList(), rates = usd, region = "US"))
        val india = Smart.RatesSnapshot(fiat = mapOf("USD" to 1.0, "INR" to 95.88),
            crypto = mapOf("SOL" to 111.77), local = "INR")
        assertNull(Smart.chip("it costs \$13 = ₹1,246.44", emptyList(), rates = india))
        assertNull(Smart.chip("buying \$sol = \$111.77", emptyList(), rates = india))
        assertEquals("₹1,200 = \$12.52", Smart.display(Smart.chip("the total is ₹1,200", emptyList(), rates = india)!!))
    }

    /** The server's unit cases (server/test/units.test.ts; GlyfEngineTests
     *  too): all three convert alike. */
    @Test fun unitsConvertOnThePhone() {
        val cases = listOf(
            "5 km in miles" to "5 km is 3.107 miles",
            "convert 100 miles to km" to "100 miles is 160.9 km",
            "100 miles to m" to "100 miles is 160,934 m",
            "what is 6 ft in cm" to "6 feet is 182.9 cm",
            "5 in in cm" to "5 inches is 12.7 cm",
            "how many cm in an inch" to "1 inch is 2.54 cm",
            "how many feet in a mile?" to "1 mile is 5,280 feet",
            "100f to c" to "100°F is 37.78°C",
            "37 c in f" to "37°C is 98.6°F",
            "-40 celsius to fahrenheit" to "-40°C is -40°F",
            "70 kg in lbs" to "70 kg is 154.3 lb",
            "5 pounds in kg" to "5 lb is 2.268 kg",
            "2 cups in ml" to "2 cups is 473.2 ml",
            "how many ml are in 2 cups" to "2 cups is 473.2 ml",
            "1 gallon to liters" to "1 gallon is 3.785 litres",
            "60 mph in km/h" to "60 mph is 96.56 km/h",
            "3 hours in minutes" to "3 hours is 180 minutes",
            "1 acre in sq ft" to "1 acre is 43,560 sq ft",
            "5 feet 10 inches in cm" to "5 ft 10 in is 177.8 cm",
            "5'10 in cm" to "5 ft 10 in is 177.8 cm",
            "178 cm in feet" to "178 cm is 5 ft 10 in",
            "2 m in ft" to "2 m is 6 ft 7 in",
            "100 m in feet" to "100 m is 328.1 feet",
        )
        for ((asked, said) in cases) assertEquals(asked, said, Smart.convertUnits(asked)?.say)
        for (text in listOf("5 pounds in dollars", "5 k in miles", "meet in 5 min", "i have 2 hours in the office",
                "5 km", "km to miles", "5 kg in km")) {
            assertNull(text, Smart.convertUnits(text))
        }
    }

    /** Hold space on "2+5" answers on the phone, at once: no server, no run
     *  (user, 2026-09-29: "i wanna do math 2+5 its taking long, we dont need
     *  ai for this"). GlyfEngineTests.testHoldSpaceAnswersSumsMoneyAndTheClockOnThePhone. */
    @Test fun holdSpaceAnswersSumsMoneyAndTheClockOnThePhone() {
        assertEquals("2+5 = 7", Smart.instantAnswer("2+5")?.say)
        assertEquals("144", Smart.instantAnswer("what is 12*12?")?.value)
        assertEquals("18% of 2450 is 441", Smart.instantAnswer("18% of 2450")?.say)
        assertEquals("870", Smart.instantAnswer("3480/4 =")?.value)
        assertEquals("3", Smart.instantAnswer("9/3")?.value)
        assertEquals("5 km is 3.107 miles", Smart.instantAnswer("5 km in miles")?.say)
        val rates = Smart.RatesSnapshot(fiat = mapOf("USD" to 1.0, "INR" to 95.88), local = "INR")
        assertEquals("\$100 = ₹9,588", Smart.instantAnswer("100 usd to inr", rates)?.say)
        assertEquals("₹500 = \$5.21", Smart.instantAnswer("₹500 in dollars", rates)?.say)
        // No rates in hand yet: the server answers it.
        assertNull(Smart.instantAnswer("100 usd to inr"))
        val at = 1790614680_000L   // 28 Sep 2026, 10:28 PM in India
        val india = java.time.ZoneId.of("Asia/Kolkata")
        assertEquals("It's 10:28 PM",
            Smart.instantAnswer("what time is it", now = at, zone = india, locale = java.util.Locale.US)?.say)
        assertEquals("It's Monday, September 28",
            Smart.instantAnswer("whats the date?", now = at, zone = india, locale = java.util.Locale.US)?.say)
        // A tip, and the days until a day everyone counts to (answers.ts).
        assertEquals("15% tip on 64 is 9.60 (73.60 in all)", Smart.instantAnswer("15% tip on 64")?.say)
        val sept28 = 1790614680_000L
        val ny = java.time.ZoneId.of("America/New_York")
        fun days(q: String) = Smart.instantAnswer(q, now = sept28, zone = ny, locale = java.util.Locale.US)
        assertEquals("88 days until Christmas", days("how many days until christmas")?.say)
        assertEquals("Friday, December 25", days("how many days until christmas")?.sub)
        assertEquals("95 days until New Year's Day", days("days till new years")?.say)
        assertEquals("33 days until Halloween", days("how long until halloween?")?.say)
        assertEquals("88 days until Dec 25", days("how many days until dec 25")?.say)
        assertEquals("8 weeks and 3 days until Thanksgiving", days("how many weeks until thanksgiving")?.say)
        // Messages and questions for the web stay with the server.
        for (text in listOf("hey 2+5 people coming", "split is 3480/4", "call me at 5", "who won the match", "5",
                "time in tokyo", "how long until the bus comes")) {
            assertNull(text, Smart.instantAnswer(text))
        }
    }

    @Test fun theSentenceNamesTheDetail() {
        val home = vault[0]
        val email = Smart.Field("email", "Email", "a@b.co")
        val phone = Smart.Field("phone", "Mobile", "+1 415 555 0100")
        val all = listOf(home, email, phone)
        assertEquals(Smart.Chip.Vault(email), Smart.chip("my email address is", all))
        assertEquals(Smart.Chip.Vault(email), Smart.chip("e-mail address:", all))
        assertEquals(Smart.Chip.Vault(email), Smart.chip("my gmail address is", all))
        // No email saved: nothing, never the home address.
        assertNull(Smart.chip("my email address is", listOf(home, phone)))
        assertNull(Smart.chip("the ip address is", all))
        assertNull(Smart.chip("our website address is", all))
        assertEquals(Smart.Chip.Vault(home), Smart.chip("my address is", all))
        assertEquals(Smart.Chip.Vault(phone), Smart.chip("my phone number is", all))
        assertEquals(Smart.Chip.Vault(phone), Smart.chip("whatsapp number:", all))
        for (other in listOf("account", "card", "order", "gst", "tracking", "flight",
                             "booking", "policy", "pan", "aadhaar")) {
            assertNull(other, Smart.chip("the $other number is", all))
            assertNull(other, Smart.chip("my $other number is", all))
        }
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
        // A number being typed is finished from the vault; typed out, nothing.
        val typing = Smart.chip("my number is 98765", more) as Smart.Chip.Details
        assertEquals("98765", typing.typed)
        assertEquals(listOf("+91 98765 43210"), typing.fields.map { it.value })
        assertNull(Smart.completions("my number is 98765 43210", more))
        assertNull(Smart.completions("my number is +91 98765 43210", more))
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
