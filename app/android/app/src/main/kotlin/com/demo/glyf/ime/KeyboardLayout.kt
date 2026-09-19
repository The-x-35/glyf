package com.demo.glyf.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo

/** Port of the Swift KeyboardLayout — same rows, units, ids, contexts. */
data class Key(
    val id: String,          // char, or shift/delete/space/return/globe/mode:x/emojikey
    val char: String? = null,
    val units: Float = 1f,   // -1 = fill (space bar)
)

enum class Mode { LETTERS, SYMBOLS1, SYMBOLS2 }

enum class KContext { TEXT, EMAIL, URL, NUMBER_PAD, DECIMAL_PAD, PHONE_PAD;

    val isPad get() = this == NUMBER_PAD || this == DECIMAL_PAD || this == PHONE_PAD

    companion object {
        fun from(info: EditorInfo?): KContext {
            val it = info?.inputType ?: return TEXT
            return when (it and InputType.TYPE_MASK_CLASS) {
                InputType.TYPE_CLASS_NUMBER ->
                    if (it and InputType.TYPE_NUMBER_FLAG_DECIMAL != 0) DECIMAL_PAD
                    else NUMBER_PAD
                InputType.TYPE_CLASS_PHONE -> PHONE_PAD
                InputType.TYPE_CLASS_TEXT ->
                    when (it and InputType.TYPE_MASK_VARIATION) {
                        InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                        InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> EMAIL
                        InputType.TYPE_TEXT_VARIATION_URI -> URL
                        else -> TEXT
                    }
                else -> TEXT
            }
        }
    }
}

object KeyboardLayout {

    /** Measured off Gboard (427dp emulator): every row is ten columns, and
     *  shift, delete, the mode key and enter take one and a half of them. */
    const val SIDE_UNITS = 1.5f

    private fun ch(c: String) = Key(id = c, char = c)
    /** (10 - two 1.5 side keys) / 5 punctuation keys. */
    private fun wide(c: String) = Key(id = c, char = c, units = 1.4f)

    /** The currency on the number layer, where the system keyboards put the
     *  region's own: ₹ in India, £ in the UK, $ elsewhere. The IME sets it
     *  from the region the app recorded. */
    @Volatile var currencyKey: String = "$"

    fun currencyFor(region: String?): String = when (region?.uppercase()) {
        "IN" -> "₹"; "GB" -> "£"; "JP", "CN" -> "¥"; "KR" -> "₩"
        "DE", "FR", "ES", "IT", "NL", "IE", "PT", "AT", "BE", "FI", "GR" -> "€"
        else -> "$"
    }

    fun rows(mode: Mode, numberRow: Boolean, context: KContext): List<List<Key>> {
        if (context.isPad) return padRows(context)
        val out = mutableListOf<List<Key>>()
        when (mode) {
            Mode.LETTERS -> {
                if (numberRow) out.add("1234567890".map { ch(it.toString()) })
                out.add("qwertyuiop".map { ch(it.toString()) })
                out.add("asdfghjkl".map { ch(it.toString()) })
                out.add(listOf(Key("shift", units = SIDE_UNITS)) +
                        "zxcvbnm".map { ch(it.toString()) } +
                        listOf(Key("delete", units = SIDE_UNITS)))
                out.add(bottomRow("?123", context))
            }
            Mode.SYMBOLS1 -> {
                out.add("1234567890".map { ch(it.toString()) })
                out.add(listOf("-", "/", ":", ";", "(", ")", currencyKey, "&", "@", "\"").map { ch(it) })
                out.add(listOf(Key("mode:#+=", units = SIDE_UNITS)) +
                        listOf(".", ",", "?", "!", "'").map { wide(it) } +
                        listOf(Key("delete", units = SIDE_UNITS)))
                out.add(bottomRow("ABC", context))
            }
            Mode.SYMBOLS2 -> {
                out.add(listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "=").map { ch(it) })
                out.add(listOf("_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•").map { ch(it) })
                out.add(listOf(Key("mode:123", units = SIDE_UNITS)) +
                        listOf(".", ",", "?", "!", "'").map { wide(it) } +
                        listOf(Key("delete", units = SIDE_UNITS)))
                out.add(bottomRow("ABC", context))
            }
        }
        return out
    }

    /** Gboard's bottom row, measured on the 427dp emulator: ?123 1.5, the
     *  field's own key 1, emoji 1, space 4, period 1, enter 1.5. */
    private fun bottomRow(modeLabel: String, context: KContext): List<Key> {
        val row = mutableListOf(Key("mode:$modeLabel", units = SIDE_UNITS))
        when (context) {
            // Gboard keeps the emoji key in every context, with the field's
            // own key on the far side of the space bar.
            KContext.EMAIL -> {
                row.add(ch("@")); row.add(Key("emojikey"))
                row.add(Key("space", units = -1f)); row.add(ch("."))
            }
            KContext.URL -> {
                row.add(ch("/")); row.add(Key("emojikey"))
                row.add(Key("space", units = -1f)); row.add(ch("."))
            }
            else -> {
                row.add(ch(","))
                row.add(Key("emojikey"))
                row.add(Key("space", units = -1f))
                row.add(ch("."))
            }
        }
        row.add(Key("return", units = SIDE_UNITS))
        return row
    }

    private fun padRows(context: KContext): List<List<Key>> {
        val corner = when (context) {
            KContext.DECIMAL_PAD -> ch(".")
            KContext.PHONE_PAD -> ch("+")
            else -> Key("space")
        }
        return listOf(
            listOf(ch("1"), ch("2"), ch("3")),
            listOf(ch("4"), ch("5"), ch("6")),
            listOf(ch("7"), ch("8"), ch("9")),
            listOf(corner, ch("0"), Key("delete")),
        )
    }
}
