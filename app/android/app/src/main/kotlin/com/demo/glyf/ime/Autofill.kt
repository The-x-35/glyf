package com.demo.glyf.ime

import android.view.inputmethod.EditorInfo
import org.json.JSONObject

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
                "emailAddress", "username" -> return "email"
                "phone", "phoneNumber", "phoneNational" -> return "phone"
                "postalAddress", "postalAddressRegion", "postalAddressLocality",
                "streetAddress", "postalCode" -> return "address"
                "name", "personName", "personGivenName", "personFamilyName" -> return "name"
            }
        }
        val words = listOfNotNull(
            info.hintText?.toString(),
            info.label?.toString(),
        ).joinToString(" ")
        kindFromWords(words)?.let { return it }
        return when (info.inputType and EditorInfo.TYPE_MASK_VARIATION) {
            EditorInfo.TYPE_TEXT_VARIATION_EMAIL_ADDRESS -> "email"
            EditorInfo.TYPE_TEXT_VARIATION_POSTAL_ADDRESS -> "address"
            EditorInfo.TYPE_TEXT_VARIATION_PERSON_NAME -> "name"
            EditorInfo.TYPE_TEXT_VARIATION_URI -> "link"
            else -> if (info.inputType and EditorInfo.TYPE_MASK_CLASS ==
                        EditorInfo.TYPE_CLASS_PHONE) "phone" else null
        }
    }

    /** Same wording table as Smart.FieldHint on iOS. */
    fun kindFromWords(raw: String): String? {
        val h = raw.lowercase()
        fun has(vararg words: String) = words.any { h.contains(it) }
        return when {
            has("e-mail", "email", "mail id") -> "email"
            has("phone", "mobile", "contact number", "whatsapp") -> "phone"
            has("address", "street", "flat", "house", "city", "pincode",
                "postal", "zip", "delivery") -> "address"
            has("full name", "your name", "first name", "last name", "name") -> "name"
            has("upi", "vpa", "gpay", "phonepe", "paytm") -> "upi"
            has("website", "url", "link", "portfolio") -> "link"
            has("company", "organisation", "organization", "employer") -> "company"
            has("instagram", "twitter", "linkedin", "handle", "social") -> "social"
            else -> null
        }
    }

    /** The saved value for this field, or null. */
    fun match(info: EditorInfo?, vault: JSONObject): String? {
        val kind = kind(info) ?: return null
        val fields = vault.optJSONArray("fields") ?: return null
        for (i in 0 until fields.length()) {
            val f = fields.optJSONObject(i) ?: continue
            if (f.optString("kind") == kind) {
                val value = f.optString("value")
                if (value.isNotBlank()) return value
            }
        }
        return null
    }
}
