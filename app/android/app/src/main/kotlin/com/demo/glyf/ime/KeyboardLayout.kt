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

    private fun ch(c: String) = Key(id = c, char = c)
    private fun wide(c: String) = Key(id = c, char = c, units = 1.44f)

    fun rows(mode: Mode, numberRow: Boolean, context: KContext): List<List<Key>> {
        if (context.isPad) return padRows(context)
        val out = mutableListOf<List<Key>>()
        when (mode) {
            Mode.LETTERS -> {
                if (numberRow) out.add("1234567890".map { ch(it.toString()) })
                out.add("qwertyuiop".map { ch(it.toString()) })
                out.add("asdfghjkl".map { ch(it.toString()) })
                out.add(listOf(Key("shift", units = 1.4f)) +
                        "zxcvbnm".map { ch(it.toString()) } +
                        listOf(Key("delete", units = 1.4f)))
                out.add(bottomRow("123", context))
            }
            Mode.SYMBOLS1 -> {
                out.add("1234567890".map { ch(it.toString()) })
                out.add(listOf("-", "/", ":", ";", "(", ")", "$", "&", "@", "\"").map { ch(it) })
                out.add(listOf(Key("mode:#+=", units = 1.4f)) +
                        listOf(".", ",", "?", "!", "'").map { wide(it) } +
                        listOf(Key("delete", units = 1.4f)))
                out.add(bottomRow("ABC", context))
            }
            Mode.SYMBOLS2 -> {
                out.add(listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "=").map { ch(it) })
                out.add(listOf("_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•").map { ch(it) })
                out.add(listOf(Key("mode:123", units = 1.4f)) +
                        listOf(".", ",", "?", "!", "'").map { wide(it) } +
                        listOf(Key("delete", units = 1.4f)))
                out.add(bottomRow("ABC", context))
            }
        }
        return out
    }

    private fun bottomRow(modeLabel: String, context: KContext): List<Key> {
        val row = mutableListOf(Key("mode:$modeLabel", units = 1.3f))
        when (context) {
            KContext.EMAIL -> {
                row.add(ch("@")); row.add(Key("space", units = -1f)); row.add(ch("."))
            }
            KContext.URL -> {
                row.add(ch(".")); row.add(Key("space", units = -1f)); row.add(ch("/"))
            }
            else -> {
                row.add(Key("emojikey", units = 1.1f))
                row.add(Key("space", units = -1f))
            }
        }
        row.add(Key("return", units = 2.2f))
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
