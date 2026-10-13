package com.arpit.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

/** The answers the iOS probe of 170 everyday messages found missing (iOS
 *  GlyfEngineTests.testEverydayAnswersFromTheProbe, 2026-10-07). */
class SmartProbeTest {
    private val rates = Smart.RatesSnapshot(
        fiat = mapOf("USD" to 1.0, "INR" to 83.5, "EUR" to 0.92),
        crypto = mapOf("SOL" to 120.0, "BTC" to 65000.0),
        local = "USD",
        mints = mapOf("SOL" to "So11111111111111111111111111111111111111112"))

    private fun shown(text: String): String? =
        (Smart.chip(text, emptyList(), indianGrouping = false, rates = rates, region = "US") as? Smart.Chip.Money)?.shown

    @Test fun currenciesAndCoins() {
        assertEquals("$100 = ₹8,350", shown("100 usd to inr"))
        assertEquals("$50 = ₹4,175", shown("50 dollars in rupees"))
        assertEquals("$20 = €18.40", shown("$20 in euros"))
        assertEquals("₹5,000 = $59.88", shown("₹5000 to usd"))
        assertEquals("INR", Smart.currencyPair("100 usd to inr")?.third)
        assertNull(Smart.currencyPair("100 usd to"))
        assertNull(Smart.currencyPair("2 to 3"))
        assertEquals("1 SOL = $120.00", shown("1 sol"))
        assertEquals("0.5 BTC = $32,500.00", shown("0.5 btc"))
        assertNotNull((Smart.chip("2 sol", emptyList(), rates = rates, region = "US") as? Smart.Chip.Money)?.buy)
        assertNull(Smart.coinAmount("2 link"))
        assertNull(Smart.coinAmount("$2 sol"))
    }

    @Test fun sumsInWords() {
        fun v(t: String) = Smart.calcMatch(t, indianGrouping = false)?.first
        assertEquals("175", v("half of 350"))
        assertEquals("30", v("a third of 90"))
        assertEquals("25", v("quarter of 100"))
        assertEquals("50", v("double 25"))
        assertEquals("80", v("twice 40"))
        assertEquals("9", v("sqrt 81"))
        assertEquals("12", v("square root of 144"))
        assertEquals("half of 350", Smart.calcMatch("half of 350")?.third)
        assertNull(v("page 2 of 10"))
    }

    @Test fun timeSomewhereElseAndUntil() {
        val noon = Instant.parse("2026-10-07T12:00:00Z")
        val ny = ZoneId.of("America/New_York")
        assertEquals(listOf("9 PM Tokyo"), Smart.cityTime("what time is it in tokyo", noon, ny, "US")?.results)
        assertEquals(listOf("9 PM Tokyo"), Smart.cityTime("tokyo time", noon, ny, "US")?.results)
        assertEquals(listOf("1 PM London"), Smart.cityTime("time in london?", noon, ny, "US")?.results)
        assertEquals(listOf("5:30 PM IST"), Smart.cityTime("whats the time in ist", noon, ny, "US")?.results)
        assertNull(Smart.cityTime("time in new york", noon, ny, "US"))
        assertNull(Smart.cityTime("dinner time", noon, ny, "US"))
        assertNull(Smart.cityTime("what time", noon, ny, "US"))

        val afternoon = Instant.parse("2026-10-07T14:45:00Z")
        val utc = ZoneId.of("UTC")
        assertEquals(listOf("in 2h 15m"), Smart.untilTime("how long until 5pm", afternoon, utc)?.results)
        assertEquals(listOf("in 3h 45m"), Smart.untilTime("till 6:30pm", afternoon, utc)?.results)
        assertEquals(listOf("in 18h 15m"), Smart.untilTime("until 9am", afternoon, utc)?.results)
        assertEquals(listOf("in 1h"), Smart.untilTime("until 15:45", afternoon, utc)?.results)
        assertNull(Smart.untilTime("until 5", afternoon, utc))
        assertEquals(listOf("in 2h 15m"), Smart.quickAnswer("how long until 5pm", afternoon, utc, "US")?.results)
    }

    @Test fun listsAndPolls() {
        val list = Smart.quickAnswer("need: milk, eggs, bread", region = "US")
        assertEquals(listOf("• List", "1. List"), list?.results)
        assertEquals("need:\n• milk\n• eggs\n• bread", list?.inserts?.first())
        assertEquals("need:\n1. milk\n2. eggs\n3. bread", list?.inserts?.last())
        assertEquals("todo:\n• call bank\n• gym\n• book flight", Smart.listMaker("todo: call bank, gym and book flight")?.inserts?.first())
        assertEquals("• milk\n• eggs\n• bread", Smart.listMaker("get milk, eggs, bread")?.inserts?.first())
        assertNull(Smart.listMaker("need: milk, eggs"))
        assertNull(Smart.listMaker("lets meet at 7: pizza, drinks, games"))
        assertNull(Smart.listMaker("i love you, miss you, see you"))

        val poll = Smart.pollMaker("pizza, burgers or pasta?")
        assertEquals(listOf("Make it a poll"), poll?.results)
        assertEquals("pizza, burgers or pasta?\n1️⃣ pizza\n2️⃣ burgers\n3️⃣ pasta\nreply with a number", poll?.inserts?.first())
        assertEquals("1️⃣ coffee", Smart.pollMaker("do you guys want coffee, tea or juice?")?.inserts?.first()?.split("\n")?.get(1))
        assertEquals("3️⃣ 8pm", Smart.pollMaker("6, 7 or 8pm?")?.inserts?.first()?.split("\n")?.get(3))
        assertNull(Smart.pollMaker("sat or sun?"))
        assertNull(Smart.pollMaker("are you coming or not?"))
        assertNull(Smart.pollMaker("pizza, burgers or pasta"))
        assertEquals(listOf("Make it a poll"), Smart.quickAnswer("lunch at 1? pizza, burgers or pasta?", region = "US")?.results)
    }

    @Test fun bookingCallAndAddressParts() {
        val own = "https://cal.com/alex/30min"
        for (text in listOf("when are you free?", "send me your calendar link", "can we book a time", "lets schedule a call",
                            "what time works for you")) {
            assertEquals(text, own, (Smart.chip(text, emptyList(), ownBooking = own) as? Smart.Chip.Vault)?.field?.value)
        }
        assertNull(Smart.chip("when are you free?", emptyList(), ownBooking = null))
        assertNull(Smart.chip("free pizza", emptyList(), ownBooking = own))
        for (text in listOf("can we hop on a quick call?", "lets call", "send me the meet link", "free to talk?", "zoom?")) {
            assertTrue(text, Smart.asksToCall(text))
        }
        for (text in listOf("call me", "i called her", "the meeting is at 3")) assertFalse(text, Smart.asksToCall(text))

        assertEquals("San Francisco" to "CA", Smart.cityState("123 Market St, San Francisco, CA 94103"))
        assertEquals("London" to null, Smart.cityState("10 Downing St, London SW1A 2AA"))
        assertEquals("Bengaluru", Smart.cityState("12 MG Road, Indiranagar, Bengaluru 560038")?.first)
        assertEquals("Austin", Smart.cityState("42 Glass Lane, Austin, TX, 78701")?.first)
        assertNull(Smart.cityState("42 Glass Lane"))
        val home = Smart.Field("address", "Home", "123 Market St, San Francisco, CA 94103")
        assertEquals(listOf("San Francisco"), Smart.detailsFor("city", listOf(home)).map { it.value })
        assertEquals(listOf("CA"), Smart.detailsFor("state", listOf(home)).map { it.value })
        assertEquals(listOf("San Francisco, CA"), Smart.detailsFor("cityState", listOf(home)).map { it.value })
        assertEquals("city", Autofill.kindFromWords("City"))
        assertEquals("state", Autofill.kindFromWords("State / Province"))
        assertEquals("address", Autofill.kindFromWords("Street address"))
    }

    private val noon = Instant.parse("2026-10-07T12:00:00Z")
    private val newYork = ZoneId.of("America/New_York")
    private fun q(text: String, region: String = "US"): List<String>? = Smart.quickAnswer(text, noon, newYork, region)?.results

    /** iOS GlyfEngineTests.testEverydayAnswersFromTheSecondProbe (2026-10-08). */
    @Test fun everydayAnswersFromTheSecondProbe() {
        // bugs the probe found
        assertNull(Smart.calc("my order number is 112-3456789-1234567"))
        assertEquals("8", Smart.calc("10-2")?.first)
        val mail = Smart.Field("email", "Email", "alex@example.com")
        assertTrue(Smart.vaultMatches("per my last email", listOf(mail)).isEmpty())
        assertEquals("alex@example.com", Smart.vaultMatches("send it to my email", listOf(mail)).firstOrNull()?.value)
        assertNull(EventParse.looksLikePlan("what are you doing tonight"))
        assertNotNull(EventParse.looksLikePlan("dinner tonight at 8?"))
        // new answers
        assertEquals(listOf("London is 5h ahead"), q("whats the time difference with london"))
        assertEquals(listOf("Tokyo is 13h ahead"), q("how far ahead is tokyo"))
        assertEquals(listOf("37.8°C"), q("100f in c"))
        assertEquals(listOf("86°F"), q("30 c to f"))
        assertEquals(listOf("178 cm", "1.78 m"), q("whats 5'10 in cm"))
        assertEquals(listOf("188 cm", "1.88 m"), q("hes 6'2"))
        assertEquals(listOf("BMI 22.9"), q("bmi 70kg 175cm"))
        assertEquals(listOf("BMI 25.8"), q("my bmi at 180 lbs and 5'10"))
        assertEquals(listOf("8:15 AM"), q("ill be there in 15"))
        assertEquals(listOf("8:05 AM"), q("call you back in 5"))
        assertNull(q("chapter 3 in 15"))
        assertEquals(listOf("-25%", "save 20"), q("was 80 now 60"))
        assertEquals(listOf("-25%", "save $30"), q("was $120, now $90"))
        assertEquals(listOf("4.33 each"), q("3 pack for 12.99"))
        assertEquals(listOf("6/kg"), q("1.5kg for 9"))
        assertEquals(listOf("11.52 tip", "75.52 total"), q("add 18% tip to 64"))
        assertEquals(2, q("monthly emi 500000 at 9% 5 years")?.size)
        assertEquals(listOf("Friday"), q("what day is 25 december 2026"))
        assertEquals(listOf("Week 41"), q("what week is it"))
        assertEquals(listOf("MMXXVI"), q("roman numeral 2026"))
        assertEquals(listOf("2026"), q("MMXXVI in numbers"))
        assertEquals("#FF5733", q("rgb 255 87 51")?.firstOrNull())
        assertEquals(listOf("aGVsbG8="), q("base64 hello"))
        assertEquals(listOf("hello"), q("base64 decode aGVsbG8="))
        assertEquals(36, q("uuid")?.firstOrNull()?.length)
        assertEquals("the same while the words stay", q("uuid"), q("uuid"))
        assertEquals(listOf("USPS tracking"), q("tracking number 9400111899223344556677"))
        assertEquals(listOf("999 · UK"), q("emergency number uk"))
        assertEquals(listOf("110 police · 119 ambulance · Japan"), q("emergency number in japan"))
        assertEquals(listOf("911"), q("emergency number"))
        assertNull(q("emergency number in atlantis"))
        assertEquals(listOf("not gonna lie"), q("what does ngl mean"))
        assertEquals(listOf("if you know, you know"), q("iykyk meaning"))
        assertNull(q("what does love mean"))
        assertEquals(listOf("Add a map link"), q("lets meet at starbucks on main st"))
        assertEquals("https://www.google.com/maps/search/?api=1&query=starbucks%20on%20main%20st",
            Smart.mapLink("lets meet at starbucks on main st")?.inserts?.firstOrNull())
        assertEquals("central park", Smart.mapLink("im at central park")?.source)
        assertEquals("blue bottle", Smart.mapLink("meet me at blue bottle at 5pm")?.source)
        assertEquals("starbucks", Smart.mapLink("meet me at starbucks")?.source)
        assertNull(Smart.mapLink("meet me at the airport"))
        assertNull(Smart.mapLink("lets meet at 7"))
        assertNull(Smart.mapLink("im at work"))
        assertNull(Smart.mapLink("im at peace"))
        assertNull(Smart.mapLink("im at my moms"))
    }

    /** iOS GlyfEngineTests.testAnswersFromTheResearchPass (2026-10-08). */
    @Test fun answersFromTheResearchPass() {
        assertEquals(listOf("86%"), q("got 43/50 on the quiz"))
        assertEquals(listOf("72%"), q("scored 18 out of 25"))
        assertNull(q("3 out of 5"))
        val score = Smart.chip("scored 43/50", emptyList(), region = "US")
        assertTrue("scored 43/50 should be a score", score is Smart.Chip.Convert)
        assertEquals(listOf("86%"), (score as Smart.Chip.Convert).answer.results)
        assertEquals(listOf("85 avg", "median 85"), q("avg of 85, 92, 78"))
        assertEquals(listOf("14.5 avg", "median 13.5"), q("average 12 15 9 22"))
        assertEquals(listOf("50"), q("sum of 12, 30 and 8"))
        assertNull(q("total 1,250"))
        assertEquals(listOf("$57.60", "28% off"), q("extra 10% off 20% off $80"))
        assertEquals(listOf("$57.60", "28% off"), q("20% + 10% off $80"))
        assertEquals(listOf("$8 each"), q("buy 2 get 1 free $12 each"))
        assertEquals(listOf("$5 each"), q("bogo $10"))
        assertEquals("$86,542", q("save $500/mo for 10 yrs at 7%")?.firstOrNull())
        assertEquals(listOf("4 h 37 min"), q("300 miles at 65 mph"))
        assertEquals(listOf("1 h 30 min"), q("120 km at 80 km/h"))
        assertEquals(listOf("Sun, Nov 1 · back 1 h"), q("when do the clocks change"))
        assertEquals(listOf("Zone 2: 112–130 bpm", "Max HR 186"), q("zone 2 heart rate age 34"))
        assertEquals("Max HR 186 bpm", q("max heart rate im 34")?.firstOrNull())
        assertNull(q("heart rate is up"))
        assertEquals(listOf("x²"), q("x^2"))
        assertEquals(listOf("α"), q("\\alpha"))
        assertEquals(listOf("x = 6"), q("solve 2x+5=17"))
        assertEquals(listOf("x = 5"), q("3x - 4 = 11"))
        assertEquals(listOf("x = 2, 3"), q("x^2-5x+6=0"))
        assertNull(q("x = 5"))
        assertEquals(listOf("165°F · 74°C"), q("chicken internal temp"))
        assertEquals(listOf("160°F · 71°C"), q("safe temp for ground beef"))
        assertEquals(listOf("1 cup milk + 1 tbsp lemon juice"), q("substitute for buttermilk"))
        assertNull(q("we're out of milk"))
        assertEquals(listOf("OOO reply · Mon, Oct 12"), q("ooo until monday"))
        assertEquals("I'm out of the office until Wed 14 Oct and will reply when I'm back.",
            Smart.outOfOffice("ooo until 14 oct", noon, newYork, "GB")?.inserts?.firstOrNull())
        val name = Smart.Field("name", "Name", "Alex Kim")
        val signed = Smart.chip("Hi Sam,\nSee you then.\nBest,", listOf(name), region = "US")
        assertTrue("sign-off", signed is Smart.Chip.Convert)
        assertEquals(listOf("Sign as Alex Kim"), (signed as Smart.Chip.Convert).answer.results)
        assertEquals(listOf("Best,\nAlex Kim"), signed.answer.inserts)
        assertEquals(listOf("482913"), Smart.pieces("Your verification code is 482913. Don't share it."))
        assertEquals(listOf("~105 kcal (medium)"), q("how many calories in a banana"))
        assertEquals(listOf("~144 kcal (2 × large)"), q("calories in 2 eggs"))
        assertEquals(listOf("~285 kcal (cheese)"), q("cals in a slice of pizza"))
        assertEquals(listOf("~590 kcal (each)"), q("big mac calories"))
        assertNull(q("calories in a spaceship"))
        assertNull(q("burned 300 calories"))
    }

    /** iOS GlyfEngineTests.testThirdProbeFixesAndAnswers (2026-10-14). */
    @Test fun thirdProbeFixesAndAnswers() {
        // fixes
        assertTrue("not the time now", q("3pm london time in new york")?.firstOrNull()?.startsWith("Wed") != true)
        assertNull(EventParse.looksLikePlan("in 2 hours what time"))
        assertEquals(listOf("10 AM"), q("in 2 hours what time"))
        assertEquals(listOf("8:15 AM"), q("whats 15 min from now"))
        assertNotNull(EventParse.looksLikePlan("reminder to take meds at 9pm"))
        assertEquals("Call", EventParse.looksLikePlan("call at 9am est what time for me")?.title)
        assertEquals("olive garden", EventParse.looksLikePlan("lets do 7pm at olive garden")?.title?.lowercase())
        assertTrue("reminder first", Smart.chip("remind me to pay rent on the 1st", emptyList(), region = "US") is Smart.Chip.Event)
        // answers
        assertEquals("Thu, Nov 26", q("when is thanksgiving")?.firstOrNull())
        assertEquals("Sun, Mar 28, 2027", q("when is easter 2027")?.firstOrNull())
        assertEquals(listOf("176.7°C"), q("350f oven in c"))
        assertEquals(listOf("9.50 tip", "57 total"), q("tip 20 on 47.50"))
        assertEquals(listOf("8 each"), q("split the uber 32 between 4"))
        assertEquals(true, q("salary 85k per year hourly")?.firstOrNull()?.endsWith("/hr"))
        assertEquals(true, q("50 per hour annually")?.firstOrNull()?.endsWith("/yr"))
        assertNotNull(q("compound 10000 7% 20 years"))
        assertEquals(listOf("72.25"), q("85 minus 15%"))
        assertEquals(listOf("1.5 h"), q("90 minutes in hours"))
        assertEquals(listOf("165 min"), q("2 hours 45 minutes in minutes"))
        assertEquals(listOf("473 ml"), q("16 oz in ml"))
        assertEquals(listOf("237 ml"), q("a cup in ml"))
        assertEquals(listOf("IST is 12h 30m ahead of PST"), q("pst to ist"))
        assertEquals(true, q("is it affect or effect")?.firstOrNull()?.startsWith("affect:"))
        assertEquals(true, q("their there or they're")?.firstOrNull()?.startsWith("their:"))
        assertEquals(listOf("ran · run"), q("past tense of run"))
        assertEquals(listOf("cacti (or cactuses)"), q("whats the plural of cactus"))
        assertEquals("1,024", Smart.calc("2 to the power of 10", indianGrouping = false)?.first)
        assertEquals("144", Smart.calc("square of 12", indianGrouping = false)?.first)
        assertEquals("3", Smart.calc("cube root of 27", indianGrouping = false)?.first)
        assertEquals("2", Smart.calc("log 100", indianGrouping = false)?.first)
        assertEquals("3,628,800", Smart.calc("10 factorial", indianGrouping = false)?.first)
        assertEquals("3.14159", Smart.calc("pi to 5 digits", indianGrouping = false)?.first)
        assertEquals("BTC", Smart.coinAmount("1 btc in usd")?.third)
        assertEquals("ETH", Smart.coinAmount("price of eth")?.third)
        assertNull(Smart.coinAmount("price of milk"))
    }

    @Test fun emojiWords() {
        assertEquals("🎂", EmojiWords.emoji("birthday"))
        assertEquals("🍕", EmojiWords.emoji("Pizzas"))
        assertNull(EmojiWords.emoji("the"))
    }
}
