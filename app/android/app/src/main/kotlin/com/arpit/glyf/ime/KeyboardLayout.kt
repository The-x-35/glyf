package com.arpit.glyf.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo

/** Port of the Swift KeyboardLayout — same rows, units, ids, contexts. */
data class Key(
    val id: String,          // char, or shift/delete/space/return/globe/mode:x/emojikey
    val char: String? = null,
    val units: Float = 1f,   // -1 = fill (space bar)
    /** shift, delete and the third row's mode key: they keep their one and
     *  a half columns but are drawn at 1.35 letters, which leaves the wider
     *  gap iOS draws between them and the letters. */
    val sideKey: Boolean = false,
    /** Which side the air is on (delete keeps its right edge). */
    val gapLeading: Boolean = false,
    /** A digit-pad key: Apple's pad typography (22pt digits, their letters
     *  under them) and no press balloon. */
    val pad: Boolean = false,
    /** The letters under a pad digit ("ABC"). */
    val subtitle: String? = null,
    /** Drawn without a key cap, like the function keys on Apple's pads. */
    val bare: Boolean = false,
    /** Shown instead of what the key types ("pause" types a comma). */
    val title: String? = null,
    /** Greyed and inert: the digits under the phone pad's symbols page,
     *  and the number pad's empty corner. */
    val disabled: Boolean = false,
)

enum class Mode { LETTERS, SYMBOLS1, SYMBOLS2 }

/** What the focused field asked for (iOS KeyboardContext): plain text, the
 *  keys an email, web address or search field needs on the space row, or a
 *  digit pad for number, decimal and phone fields. */
enum class KContext { TEXT, EMAIL, URL, WEB_SEARCH, NUMBER_PAD, DECIMAL_PAD, PHONE_PAD;

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
                        // A browser's address bar takes searches too (its
                        // action is go or search): it keeps a space bar, as
                        // Safari's does on the iPhone.
                        InputType.TYPE_TEXT_VARIATION_URI -> {
                            val action = info.imeOptions and EditorInfo.IME_MASK_ACTION
                            // (info is the field that asked: never null here)
                            if (action == EditorInfo.IME_ACTION_GO || action == EditorInfo.IME_ACTION_SEARCH)
                                WEB_SEARCH else URL
                        }
                        else -> TEXT
                    }
                else -> TEXT
            }
        }
    }
}

object KeyboardLayout {

    /** shift, delete and the third row's mode key: one and a half columns. */
    const val SIDE_UNITS = 1.5f

    /** What a held key offers after itself: iOS's table, key for key
     *  (KeyboardLayout.swift), so both keyboards reach the same accents. */
    val accents: Map<String, List<String>> = mapOf(
        "a" to listOf("à", "á", "â", "ä", "æ", "ã", "å", "ā"),
        "e" to listOf("è", "é", "ê", "ë", "ē", "ė", "ę"),
        "i" to listOf("î", "ï", "í", "ī", "į", "ì"),
        "o" to listOf("ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"),
        "u" to listOf("û", "ü", "ù", "ú", "ū"),
        "c" to listOf("ç", "ć", "č"),
        "n" to listOf("ñ", "ń"),
        "s" to listOf("ß", "ś", "š"),
        "y" to listOf("ÿ"),
        "z" to listOf("ž", "ź", "ż"),
        "l" to listOf("ł"),
        "0" to listOf("°"),
        "-" to listOf("–", "—", "•"),
        "/" to listOf("\\"),
        "$" to listOf("₹", "€", "£", "¥", "₩"),
        "&" to listOf("§"),
        "\"" to listOf("„", "“", "”", "«", "»"),
        "'" to listOf("‘", "’", "‚", "`"),
        "!" to listOf("¡"),
        "?" to listOf("¿"),
        "." to listOf("…"),
        // The long press on .com, like Apple's.
        ".com" to listOf(".net", ".org", ".edu", ".io", ".co"),
    )

    private fun ch(c: String) = Key(id = c, char = c)
    /** (10 - two 1.5 side keys) / 5 punctuation keys, Apple-style stretch. */
    private fun wide(c: String) = Key(id = c, char = c, units = 1.4f)
    private fun side(id: String, leading: Boolean = false) =
        Key(id, units = SIDE_UNITS, sideKey = true, gapLeading = leading)

    fun rows(mode: Mode, numberRow: Boolean, context: KContext): List<List<Key>> {
        if (context.isPad) return padRows(context, mode)
        val out = mutableListOf<List<Key>>()
        when (mode) {
            Mode.LETTERS -> {
                if (numberRow) out.add("1234567890".map { ch(it.toString()) })
                out.add("qwertyuiop".map { ch(it.toString()) })
                out.add("asdfghjkl".map { ch(it.toString()) })
                out.add(listOf(side("shift")) +
                        "zxcvbnm".map { ch(it.toString()) } +
                        listOf(side("delete", leading = true)))
                out.add(bottomRow("123", context))
            }
            Mode.SYMBOLS1 -> {
                out.add("1234567890".map { ch(it.toString()) })
                out.add(listOf("-", "/", ":", ";", "(", ")", "$", "&", "@", "\"").map { ch(it) })
                out.add(listOf(side("mode:#+=")) +
                        listOf(".", ",", "?", "!", "'").map { wide(it) } +
                        listOf(side("delete", leading = true)))
                out.add(bottomRow("ABC", context))
            }
            Mode.SYMBOLS2 -> {
                out.add(listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "=").map { ch(it) })
                out.add(listOf("_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•").map { ch(it) })
                out.add(listOf(side("mode:123")) +
                        listOf(".", ",", "?", "!", "'").map { wide(it) } +
                        listOf(side("delete", leading = true)))
                out.add(bottomRow("ABC", context))
            }
        }
        return out
    }

    /** iOS's space row for each field type (KeyboardLayout.swift, measured
     *  against Apple's keyboard), ten columns:
     *
     *      text        123 · emoji · space · return
     *      email       123 · emoji · space · @ · . · return
     *      web address 123 · emoji · . · / · .com (sharing what is left) · return
     *      search bar  123 · emoji · space · . (1) · return (1.75)
     */
    private fun bottomRow(modeLabel: String, context: KContext): List<Key> {
        val row = mutableListOf(Key("mode:$modeLabel", units = 1.25f), Key("emojikey", units = 1.25f))
        val dot = Key(".", ".", units = 1.25f)
        when (context) {
            KContext.EMAIL -> {
                row.add(Key("space", units = -1f))
                row.add(Key("@", "@", units = 1.25f))
                row.add(dot)
            }
            KContext.URL -> {
                // No space bar: a web address has no spaces.
                row.add(Key(".", ".", units = -1f))
                row.add(Key("/", "/", units = -1f))
                row.add(Key(".com", ".com", units = -1f))
            }
            KContext.WEB_SEARCH -> {
                row.add(Key("space", units = -1f))
                row.add(Key(".", ".", units = 1f))
                row.add(Key("return", units = 1.75f))
                return row
            }
            else -> row.add(Key("space", units = -1f))
        }
        row.add(Key("return", units = 2.5f))
        return row
    }

    /** The letters under each digit, as on Apple's pads. */
    private val padLetters = mapOf("2" to "ABC", "3" to "DEF", "4" to "GHI", "5" to "JKL",
        "6" to "MNO", "7" to "PQRS", "8" to "TUV", "9" to "WXYZ")

    /** Apple's digit pad for number, phone and decimal fields: three wide
     *  keys a row, the corner and delete drawn bare. The number pad's corner
     *  is empty, the decimal pad's is the separator, and the phone pad's
     *  opens a second page (pause, wait, *, #, +) over greyed digits. */
    private fun padRows(context: KContext, mode: Mode): List<List<Key>> {
        fun digit(d: String, disabled: Boolean = false) =
            Key(d, d, pad = true, subtitle = padLetters[d], disabled = disabled)
        fun symbol(c: String, title: String? = null) = Key(c, c, pad = true, title = title)
        val delete = Key("delete", pad = true, bare = true)
        if (context == KContext.PHONE_PAD && mode != Mode.LETTERS) {
            return listOf(
                listOf(digit("1", true), digit("2", true), digit("3", true)),
                listOf(symbol(",", "pause"), digit("5", true), symbol(";", "wait")),
                listOf(symbol("*"), digit("8", true), symbol("#")),
                listOf(Key("mode:123", pad = true, bare = true), symbol("+"), delete),
            )
        }
        val corner = when (context) {
            KContext.DECIMAL_PAD -> {
                val sep = java.text.DecimalFormatSymbols.getInstance().decimalSeparator.toString()
                Key(sep, sep, pad = true, bare = true)
            }
            KContext.PHONE_PAD -> Key("mode:+*#", pad = true, bare = true)
            else -> Key("padcorner", "", pad = true, bare = true, disabled = true)
        }
        return listOf(
            listOf(digit("1"), digit("2"), digit("3")),
            listOf(digit("4"), digit("5"), digit("6")),
            listOf(digit("7"), digit("8"), digit("9")),
            listOf(corner, digit("0"), delete),
        )
    }
}
