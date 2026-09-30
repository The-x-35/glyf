package com.demo.glyf.ime

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.widget.TextView

/**
 * The iPhone keyboard's design tokens (app/ios/GlyfKeyboard/Design/
 * GlassTokens.swift), for everything the Android keyboard draws on its
 * board: the same colours, type, radii and strokes on both phones (Arpit,
 * 2026-09-30: "i need it similar in everything as a brand identity it is").
 * Inter stands in for SF, at SF's sizes and weights.
 *
 * [dark] is the keyboard's own light or dark, set whenever it comes up, so a
 * surface built after that reads the right side of every pair.
 */
object Glass {

    /** The keyboard is dark (iOS `Glass.chromeDark`). */
    var dark = false

    // MARK: text

    /** Text on the board and on cards (iOS textPrimary). */
    val textPrimary get() = if (dark) Color.WHITE else gray(0.07f)
    /** Quieter words: labels, ages, placeholders (iOS textSecondary). */
    val textSecondary get() = if (dark) gray(0.63f) else gray(0.42f)
    /** The brand keycap's ink, the same either way. */
    val brandInk = gray(0.07f)

    // MARK: fills

    /** Cards inside the keyboard's surfaces: Apple's key colour, #FFFFFF on
     *  the light sheet and #404041 on the dark one. */
    val surfaceCard get() = if (dark) Color.rgb(0x40, 0x40, 0x41) else Color.WHITE
    /** A field or a neutral button's ground (iOS fillField). */
    val fillField get() = if (dark) rgbf(0.17f, 0.17f, 0.18f) else rgbf(0.93f, 0.94f, 0.96f)
    /** A soft chip over the board (the website's --kb-soft). */
    val fillSoft get() = if (dark) white(0.08f) else white(0.6f)
    /** Dims a panel behind a menu. */
    val scrim get() = if (dark) black(0.55f) else white(0.62f)

    // MARK: strokes

    val strokeHairline get() = if (dark) white(0.10f) else black(0.08f)
    /** Between two rows of a grouped list: firmer than a card's hairline. */
    val strokeSeparator get() = if (dark) white(0.14f) else black(0.16f)
    val strokeFocus get() = withAlpha(accentPrimary, 0.60f)
    /** iOS draws hairlines at half a point. */
    const val HAIRLINE_DP = 0.5f

    // MARK: accent and status

    val accentPrimary = Color.rgb(0x7C, 0x5C, 0xFF)
    /** Purple words on a strip chip, lighter than the accent. */
    val chipAccent get() = if (dark) Color.rgb(0xC3, 0xB4, 0xFF) else Color.rgb(0x8A, 0x6C, 0xFF)
    val accentSuccess = Color.rgb(0x32, 0xD5, 0x83)
    val accentWarning = Color.rgb(0xB7, 0x79, 0x09)
    val accentDanger = Color.rgb(0xF0, 0x44, 0x38)
    /** A switch or segment that is on: ink in light, a light track in dark. */
    val controlOn get() = if (dark) gray(0.86f) else Color.rgb(0x17, 0x18, 0x1C)
    val controlOnText get() = if (dark) Color.rgb(0x17, 0x18, 0x1C) else Color.WHITE

    // MARK: radii (points on iOS, dp here)

    const val RADIUS_KEY = 9.5f
    const val RADIUS_CARD = 18f

    // MARK: type

    /** SF's weights, as Inter's wght axis. */
    const val REGULAR = 400
    const val MEDIUM = 500
    const val SEMIBOLD = 600
    const val BOLD = 700

    private val faces = HashMap<Int, Typeface>()

    /** Inter at [weight], from the font the app bundles (the key faces use
     *  it too). The system font when it can't be read, so nothing breaks. */
    fun font(ctx: Context, weight: Int = REGULAR): Typeface {
        faces[weight]?.let { return it }
        val face = try {
            Typeface.Builder(ctx.assets, "flutter_assets/assets/fonts/Inter-Variable.ttf")
                .setFontVariationSettings("'wght' $weight")
                .build()
        } catch (_: Exception) {
            null
        } ?: Typeface.create(Typeface.DEFAULT, if (weight >= SEMIBOLD) Typeface.BOLD else Typeface.NORMAL)
        faces[weight] = face
        return face
    }

    /** A label the way iOS sets one: Inter at [size] points and [weight],
     *  in [color], with no extra font padding above and below. */
    fun style(view: TextView, size: Float, weight: Int = REGULAR, color: Int = textPrimary) {
        view.setTextSize(TypedValue.COMPLEX_UNIT_DIP, size)
        view.typeface = font(view.context, weight)
        view.setTextColor(color)
        view.includeFontPadding = false
    }

    /** A card's ground: [fill] with [radius] dp corners, and a hairline edge
     *  when [stroke] is given. */
    fun card(ctx: Context, fill: Int = surfaceCard, radius: Float = 12f, stroke: Int? = null,
             strokeDp: Float = HAIRLINE_DP) = GradientDrawable().apply {
        val d = ctx.resources.displayMetrics.density
        cornerRadius = radius * d
        setColor(fill)
        stroke?.let { setStroke(maxOf(1, (strokeDp * d).toInt()), it) }
    }

    /** A pill (fully round ends) of [fill]. */
    fun pill(fill: Int) = GradientDrawable().apply {
        cornerRadius = 1000f
        setColor(fill)
    }

    /** [text] with [icon] after it, [gapPx] apart and centred on the words'
     *  capitals (iOS's "Insert ↑", the arrow a symbol beside the title). */
    fun withTrailingIcon(text: String, icon: android.graphics.drawable.Drawable, gapPx: Int): CharSequence {
        val out = android.text.SpannableString("$text\u00A0")
        out.setSpan(object : android.text.style.ReplacementSpan() {
            override fun getSize(paint: android.graphics.Paint, t: CharSequence?, start: Int, end: Int,
                                 fm: android.graphics.Paint.FontMetricsInt?) = icon.intrinsicWidth + gapPx
            override fun draw(c: android.graphics.Canvas, t: CharSequence?, start: Int, end: Int,
                              x: Float, top: Int, y: Int, bottom: Int, paint: android.graphics.Paint) {
                val fm = paint.fontMetricsInt
                val mid = y + (fm.ascent + fm.descent) / 2f
                val l = (x + gapPx).toInt()
                val tp = (mid - icon.intrinsicHeight / 2f).toInt()
                icon.setBounds(l, tp, l + icon.intrinsicWidth, tp + icon.intrinsicHeight)
                icon.draw(c)
            }
        }, text.length, text.length + 1, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return out
    }

    // MARK: colour helpers

    fun gray(v: Float) = Color.rgb((v * 255).toInt(), (v * 255).toInt(), (v * 255).toInt())
    private fun rgbf(r: Float, g: Float, b: Float) =
        Color.rgb((r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt())
    fun white(a: Float) = Color.argb((a * 255).toInt(), 255, 255, 255)
    fun black(a: Float) = Color.argb((a * 255).toInt(), 0, 0, 0)
    fun withAlpha(c: Int, a: Float) = Color.argb((a * 255).toInt(), Color.red(c), Color.green(c), Color.blue(c))
}
