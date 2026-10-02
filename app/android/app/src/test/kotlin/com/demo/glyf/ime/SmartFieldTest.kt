package com.demo.glyf.ime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Runs shared/vault/field-cases.json (iOS runs the same file): an empty
 *  field of a known kind is offered what the vault holds for it, or the part
 *  of a detail it asks for (the postcode in an address, a first or last
 *  name), and Autofill reads a field's kind from its own words. */
class SmartFieldTest {

    private val root: JSONObject by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "shared/vault/field-cases.json").exists()) dir = dir.parentFile
        val file = File(requireNotNull(dir) { "shared/vault not found above ${System.getProperty("user.dir")}" },
            "shared/vault/field-cases.json")
        JSONObject(file.readText())
    }

    private fun strings(a: org.json.JSONArray) = (0 until a.length()).map { a.getString(it) }

    @Test fun aFieldOfAKnownKindIsOfferedItsDetailOrAPartOfIt() {
        val f = root.getJSONArray("fields")
        val fields = (0 until f.length()).map { f.getJSONObject(it) }
            .map { Smart.Field(it.getString("kind"), it.getString("label"), it.getString("value")) }
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() > 0)
        val failures = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { c ->
            val want = strings(c.getJSONArray("values"))
            val got = Smart.detailsFor(c.getString("kind"), fields).map { it.value }
            if (got == want) null else "${c.getString("kind")}: got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test fun thePostcodeIsReadFromTheAddress() {
        val cases = root.getJSONArray("postcodes")
        val failures = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { c ->
            val want = if (c.isNull("postcode")) null else c.getString("postcode")
            val got = Smart.postcode(c.getString("address"))
            if (got == want) null else "'${c.getString("address")}': got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test fun anEmptyFieldOffersOneDetailAsItsChipAndMoreAsARow() {
        val fields = listOf(
            Smart.Field("name", "Name", "Alex Rivera"),
            Smart.Field("address", "Home", "123 Market St, San Francisco, CA 94103"),
            Smart.Field("email", "Email", "alex@example.com"),
            Smart.Field("email", "Work", "alex@acme.example"),
        )
        val zip = Smart.chip("", fields, fieldKind = "postcode")
        assertTrue("$zip", zip is Smart.Chip.Vault && zip.field.value == "94103")
        val first = Smart.chip("", fields, fieldKind = "givenName")
        assertTrue("$first", first is Smart.Chip.Vault && first.field.value == "Alex")
        val mails = Smart.chip("", fields, fieldKind = "email")
        assertTrue("$mails", mails is Smart.Chip.Details && mails.fields.size == 2)
        assertEquals(null, Smart.chip("", fields, fieldKind = "link"))
    }

    @Test fun aFieldsInputTypeSaysWhatItWants() {
        val text = android.text.InputType.TYPE_CLASS_TEXT
        val cases = mapOf(
            (text or android.text.InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS) to "email",
            (text or android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS) to "email",
            (text or android.text.InputType.TYPE_TEXT_VARIATION_URI) to "link",
            (text or android.text.InputType.TYPE_TEXT_VARIATION_PERSON_NAME) to "name",
            android.text.InputType.TYPE_CLASS_PHONE to "phone",
            (android.text.InputType.TYPE_CLASS_DATETIME or android.text.InputType.TYPE_DATETIME_VARIATION_TIME) to null,
            text to null,
        )
        val failures = cases.mapNotNull { (type, want) ->
            val got = Autofill.kindFromInputType(type)
            if (got == want) null else "inputType 0x${type.toString(16)}: got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test fun aFieldsOwnWordsSayWhatItWants() {
        val words = mapOf(
            "ZIP code" to "postcode", "Postal code" to "postcode", "PIN code" to "postcode",
            "First name" to "givenName", "Given name" to "givenName",
            "Last name" to "familyName", "Surname" to "familyName",
            "Full name" to "name", "Email address" to "email", "Phone number" to "phone",
            "Street address" to "address", "Company" to "company", "Website" to "link",
            "Message" to null,
        )
        val failures = words.mapNotNull { (w, want) ->
            val got = Autofill.kindFromWords(w)
            if (got == want) null else "'$w': got $got, want $want"
        }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }
}
