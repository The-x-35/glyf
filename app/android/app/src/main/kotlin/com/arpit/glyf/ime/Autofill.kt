package com.arpit.glyf.ime

import android.view.inputmethod.EditorInfo

/**
 * What the focused field is asking for, and what the vault has for it.
 *
 * Android hands a keyboard the field's own words — the hint ("Delivery
 * address"), the autofill hints the app declared, and the input type — so a
 * form can be filled from what someone already saved, with one tap and no
 * typing. The iOS twin is Smart.FieldHint, which has less to work with.
 */
object Autofill {

    /** Vault kind for this field, or null when it gives nothing away. */
    fun kind(info: EditorInfo?): String? {
        if (info == null) return null
        // EditorInfo carries the app's declared autofill hints in its extras
        // on every release that supports them.
        val declared = info.extras?.getStringArray("androidx.autofill.hints")
            ?: info.extras?.getStringArray("autofillHints")
        for (hint in declared.orEmpty()) {
            when (hint) {
                "emailAddress", "username", "newUsername" -> return "email"
                "phone", "phoneNumber", "phoneNational" -> return "phone"
                // A postcode field wants the postcode in the address, a first
                // name field the first word of the name (Smart.detailsFor).
                "postalCode" -> return "postcode"
                "postalAddress", "postalAddressRegion", "postalAddressLocality",
                "streetAddress" -> return "address"
                "personGivenName" -> return "givenName"
                "personFamilyName" -> return "familyName"
                "name", "personName" -> return "name"
            }
        }
        // The field's own words: its hint, its label, and the name the app
        // gave it ("zip_code", "firstName"), said as words.
        val words = listOfNotNull(
            info.hintText?.toString(),
            info.label?.toString(),
            info.fieldName?.replace(Regex("([a-z])([A-Z])"), "\$1 \$2")?.replace(Regex("[_.-]+"), " "),
        ).joinToString(" ")
        kindFromWords(words)?.let { return it }
        return kindFromInputType(info.inputType)
    }

    /** What the input type alone says. A variation means something only on
     *  a text field (a time field's variation is an email's number), and
     *  Chrome marks <input type=email> as a web email address. */
    fun kindFromInputType(type: Int): String? {
        val cls = type and EditorInfo.TYPE_MASK_CLASS
        if (cls == EditorInfo.TYPE_CLASS_PHONE) return "phone"
        if (cls != EditorInfo.TYPE_CLASS_TEXT) return null
        return when (type and EditorInfo.TYPE_MASK_VARIATION) {
            EditorInfo.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            EditorInfo.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> "email"
            EditorInfo.TYPE_TEXT_VARIATION_POSTAL_ADDRESS -> "address"
            EditorInfo.TYPE_TEXT_VARIATION_PERSON_NAME -> "name"
            EditorInfo.TYPE_TEXT_VARIATION_URI -> "link"
            else -> null
        }
    }

    /** Same wording table as Smart.FieldHint on iOS. */
    fun kindFromWords(raw: String): String? {
        val h = raw.lowercase()
        fun has(vararg words: String) = words.any { h.contains(it) }
        return when {
            has("e-mail", "email", "mail id", "username", "user name", "login") -> "email"
            has("phone", "mobile", "contact number", "whatsapp") -> "phone"
            has("zip", "pincode", "pin code", "postcode", "post code", "postal code") -> "postcode"
            has("address", "street", "flat", "house", "city", "postal", "delivery") -> "address"
            has("first name", "given name", "firstname", "givenname") -> "givenName"
            has("last name", "surname", "family name", "lastname", "familyname") -> "familyName"
            has("full name", "your name", "name") -> "name"
            has("upi", "vpa", "gpay", "phonepe", "paytm") -> "upi"
            has("website", "url", "link", "portfolio") -> "link"
            has("company", "organisation", "organization", "employer") -> "company"
            has("instagram", "twitter", "linkedin", "handle", "social") -> "social"
            else -> null
        }
    }
    // What the vault has for the field: Smart.chip("", fields, fieldKind = kind),
    // every saved value of that kind (a details chip when there are more).
}
