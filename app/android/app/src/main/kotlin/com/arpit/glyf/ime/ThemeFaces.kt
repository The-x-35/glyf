package com.arpit.glyf.ime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.util.LongSparseArray
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * A theme's key faces, legends' inks and ornaments (shared/themes/styles.py),
 * drawn the way tools/theme_mock.py draws them (the reference the founder
 * judges by): fill (or fill to fill2), the texture tiled at one image pixel
 * per device pixel, sheen, metal bands, gloss, a 1px top highlight, all
 * inside the key's rounded rect; Typewriter's round keycaps in their chrome
 * bezel; then the theme's ornament. Nothing here moves or resizes a key.
 *
 * Per frame it only draws: everything that depends on a key's size is baked
 * once into a bitmap per (key kind, size, fill), the textures are shaders in
 * the view's coordinates (so neighbouring keys show different grain, as in
 * the mock), and the caches empty when the theme or its mode changes.
 */
class ThemeFaces(private val ctx: Context, private val density: Float) {
    private fun dp(v: Float) = v * density

    private var forTheme: KeyboardThemes.Theme? = null
    private var forDark = false
    private val bitmaps = LongSparseArray<Bitmap>()
    private val foils = LongSparseArray<Shader>()

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val texPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bmpPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    /** Call before drawing a frame's keys: a new theme or mode starts the
     *  caches again. */
    fun use(theme: KeyboardThemes.Theme?, dark: Boolean) {
        if (theme === forTheme && dark == forDark) return
        forTheme = theme
        forDark = dark
        // Dropped, never recycled: a frame already recorded may still draw them.
        bitmaps.clear()
        foils.clear()
    }

    /** The texture's shader, tiled from the view's origin, or null. */
    fun texture(name: String?): Shader? = name?.let { ThemeTextureTiles.shader(ctx, it) }

    /**
     * A key's face at [r]. [on] is what ornaments name the key by (letter,
     * space, return, shift, delete, or anything else for the other function
     * keys); [cls] its class (letter, function, space, return).
     */
    fun drawKey(c: Canvas, r: RectF, radius: Float, f: KeyboardThemes.Face, fill: Int, v: KeyboardThemes.Variant,
                cls: String, on: String, font: Typeface?) {
        val w = ceil(r.width()).toInt().coerceIn(1, 4095)
        val h = ceil(r.height()).toInt().coerceIn(1, 4095)
        val onIx = onIndex(on)
        if (f.round) {
            val cx = r.centerX(); val cy = r.centerY()
            val R = min(r.width(), r.height()) / 2f
            val ri = R - dp(2.4f)
            // The keycap's drop shadow and chrome bezel (a fill of its own).
            bitmap(key(0, onIx, w, h, f.ring ?: 0)) { roundUnder(w, h, r.width(), r.height(), f) }
                ?.let { c.drawBitmap(it, r.left, r.top, bmpPaint) }
            fillPaint.color = fill
            c.drawCircle(cx, cy, ri, fillPaint)
            texture(f.texture)?.let {
                texPaint.shader = it
                texPaint.alpha = (f.textureAlpha * 255).toInt().coerceIn(0, 255)
                c.drawCircle(cx, cy, ri, texPaint)
            }
        } else {
            if (f.fill2 != null) {
                bitmap(key(1, onIx, w, h, fill)) { fill2(w, h, r.width(), r.height(), radius, fill, f.fill2) }
                    ?.let { c.drawBitmap(it, r.left, r.top, bmpPaint) }
            } else {
                fillPaint.color = fill
                c.drawRoundRect(r, radius, radius, fillPaint)
            }
            texture(f.texture)?.let {
                texPaint.shader = it
                texPaint.alpha = (f.textureAlpha * 255).toInt().coerceIn(0, 255)
                c.drawRoundRect(r, radius, radius, texPaint)
            }
        }
        // Sheen, metal, gloss and highlight (or the round cap's dome), then
        // the ornaments: one transparent bitmap over the face.
        bitmap(key(2, onIx, w, h, fill)) { over(w, h, r.width(), r.height(), radius, f, fill, v, cls, on, font) }
            ?.let { c.drawBitmap(it, r.left, r.top, bmpPaint) }
    }

    /** The press callout's path in the letter face: its fill, then its
     *  texture (never round). */
    fun drawCallout(c: Canvas, path: Path, f: KeyboardThemes.Face, fill: Int) {
        fillPaint.color = fill
        c.drawPath(path, fillPaint)
        texture(f.texture)?.let {
            texPaint.shader = it
            texPaint.alpha = (f.textureAlpha * 255).toInt().coerceIn(0, 255)
            c.drawPath(path, texPaint)
        }
    }

    /** Foil's three-stop leaf over a glyph from [top] to [bottom] (view
     *  coordinates), made once per position. */
    fun foil(top: Float, bottom: Float, stops: IntArray): Shader {
        val t = top.toInt(); val b = max(bottom.toInt(), t + 1)
        val k = (t.toLong() shl 32) or (b.toLong() and 0xFFFFFFFFL)
        foils.get(k)?.let { return it }
        val s = LinearGradient(0f, t.toFloat(), 0f, b.toFloat(), stops, floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP)
        foils.put(k, s)
        return s
    }

    // MARK: caches

    private fun onIndex(on: String) = when (on) {
        "letter" -> 0; "space" -> 2; "return" -> 3; "shift" -> 4; "delete" -> 5; else -> 1
    }

    /** kind 2 bits, on 3, width 12, height 12, a colour 32. */
    private fun key(kind: Int, on: Int, w: Int, h: Int, color: Int): Long =
        (kind.toLong() shl 59) or (on.toLong() shl 56) or (w.toLong() shl 44) or (h.toLong() shl 32) or
            (color.toLong() and 0xFFFFFFFFL)

    private inline fun bitmap(k: Long, make: () -> Bitmap?): Bitmap? {
        bitmaps.get(k)?.let { return it }
        // A keyboard has a dozen kinds of key; a runaway cache starts over.
        if (bitmaps.size() > 96) bitmaps.clear()
        val b = try { make() } catch (e: Exception) {
            android.util.Log.w("GlyfKB", "theme face: $e"); null
        } ?: return null
        bitmaps.put(k, b)
        return b
    }

    // MARK: baking (the mock's drawFace and ornaments, in a key's own box)

    private fun rr(x: Float, y: Float, w: Float, h: Float, r: Float) =
        Path().apply { addRoundRect(RectF(x, y, x + w, y + h), r, r, Path.Direction.CW) }

    private fun white(a: Float) = Color.argb((a.coerceIn(0f, 1f) * 255).toInt(), 255, 255, 255)
    private fun black(a: Float) = Color.argb((a.coerceIn(0f, 1f) * 255).toInt(), 0, 0, 0)

    private fun fill2(w: Int, h: Int, rw: Float, rh: Float, radius: Float, fill: Int, fill2: Int): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = LinearGradient(0f, 0f, rw, rh, fill, fill2, Shader.TileMode.CLAMP)
        c.drawRoundRect(RectF(0f, 0f, rw, rh), radius, radius, p)
        return bmp
    }

    /** The round cap's shadow (1.4 below, darker at night) and its chrome
     *  bezel: light on top, the ring colour, a dark band, light again. */
    private fun roundUnder(w: Int, h: Int, rw: Float, rh: Float, f: KeyboardThemes.Face): Bitmap {
        val bmp = Bitmap.createBitmap(w, h + ceil(dp(3f)).toInt(), Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val cx = rw / 2f; val cy = rh / 2f; val R = min(rw, rh) / 2f
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.color = black(if (forDark) 0.6f else 0.30f)
        c.drawCircle(cx, cy + dp(1.4f), R, p)
        p.color = Color.BLACK
        p.shader = LinearGradient(0f, cy - R, 0f, cy + R,
            intArrayOf(0xFFF4F4F2.toInt(), f.ring ?: 0xFFA9A9A4.toInt(), 0xFF6E6E6A.toInt(), 0xFFD8D8D4.toInt()),
            floatArrayOf(0f, 0.45f, 0.55f, 1f), Shader.TileMode.CLAMP)
        c.drawCircle(cx, cy, R, p)
        return bmp
    }

    private fun over(w: Int, h: Int, rw: Float, rh: Float, radius: Float, f: KeyboardThemes.Face, fill: Int,
                     v: KeyboardThemes.Variant, cls: String, on: String, font: Typeface?): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        if (f.round) dome(bmp, rw, rh, f) else flat(c, rw, rh, radius, f)
        ornaments(c, rw, rh, radius, v, cls, on, fill, font)
        return bmp
    }

    /** The flat key's light: sheen, metal bands, gloss, the 1px highlight. */
    private fun flat(c: Canvas, w: Float, h: Float, radius: Float, f: KeyboardThemes.Face) {
        c.save()
        c.clipPath(rr(0f, 0f, w, h, radius))
        val p = Paint()
        if (f.sheenTop > 0f || f.sheenBottom > 0f) {
            p.shader = LinearGradient(0f, 0f, 0f, h,
                intArrayOf(white(f.sheenTop), white(0f), black(0f), black(f.sheenBottom)),
                floatArrayOf(0f, 0.5f, 0.5f, 1f), Shader.TileMode.CLAMP)
            c.drawRect(0f, 0f, w, h, p)
        }
        if (f.metal > 0f) {
            for ((at, s) in METAL) {
                val y0 = h * (at - s); val y1 = h * (at + s)
                p.shader = LinearGradient(0f, y0, 0f, y1, intArrayOf(white(0f), white(f.metal), white(0f)),
                    floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
                c.drawRect(0f, y0, w, y1, p)
            }
        }
        if (f.gloss > 0f) {
            p.shader = LinearGradient(0f, 0f, 0f, h * 0.48f, white(f.gloss), white(0f), Shader.TileMode.CLAMP)
            c.drawRect(0f, 0f, w, h * 0.48f, p)
        }
        if (f.highlight > 0f) {
            p.shader = null
            p.color = white(f.highlight)
            c.drawRect(0f, 0f, w, 1f, p)
        }
        c.restore()
    }

    /**
     * The round cap's dome inside the bezel: the mock's two-circle radial
     * gradient (from a small circle a third up to the cap's edge), white at
     * the gloss fading out by 70%, then the sheen's shade at the rim, worked
     * out per pixel (Android's own two-point gradient needs API 31).
     */
    private fun dome(bmp: Bitmap, rw: Float, rh: Float, f: KeyboardThemes.Face) {
        val cx = rw / 2f; val cy = rh / 2f
        val ri = min(rw, rh) / 2f - dp(2.4f)
        if (ri <= 1f) return
        val c0y = cy - ri * 0.35f; val r0 = ri * 0.1f
        val dyc = cy - c0y; val dr = ri - r0
        val a = dyc * dyc - dr * dr
        val rim = (f.sheenBottom + 0.06f).coerceIn(0f, 1f)
        val w = bmp.width; val h = bmp.height
        val px = IntArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            val fx = x + 0.5f - cx; val fy = y + 0.5f - cy
            val d = sqrt(fx * fx + fy * fy)
            val cover = (ri - d + 0.5f).coerceIn(0f, 1f)
            if (cover <= 0f) continue
            // |p - c(t)| = r(t), c(t) = c0 + t(c1 - c0), r(t) = r0 + t dr.
            val pdy = y + 0.5f - c0y
            val b = pdy * dyc + r0 * dr
            val cc = fx * fx + pdy * pdy - r0 * r0
            val disc = b * b - a * cc
            var t = 0f
            if (disc >= 0f) {
                val s = sqrt(disc)
                val t1 = (b + s) / a; val t2 = (b - s) / a
                t = when {
                    r0 + max(t1, t2) * dr >= 0f -> max(t1, t2)
                    else -> min(t1, t2)
                }
            }
            t = t.coerceIn(0f, 1f)
            // Stops (0, white at gloss), (0.7, white clear), (1, black at rim),
            // interpolated unpremultiplied as canvas and Skia do.
            val r: Float; val al: Float
            if (t <= 0.7f) { r = 255f; al = f.gloss * (1f - t / 0.7f) }
            else { val u = (t - 0.7f) / 0.3f; r = 255f * (1f - u); al = rim * u }
            val alpha = (al * cover * 255f).toInt().coerceIn(0, 255)
            if (alpha == 0) continue
            val g = r.toInt().coerceIn(0, 255)
            px[y * w + x] = (alpha shl 24) or (g shl 16) or (g shl 8) or g
        }
        bmp.setPixels(px, 0, w, 0, 0, w, h)
    }

    private fun roleColor(role: String, v: KeyboardThemes.Variant, cls: String, fill: Int): Int {
        if (role.startsWith("#")) return try { Color.parseColor(role) } catch (_: Exception) { v.keyText }
        return when (role) {
            "ink" -> if (cls == "function") v.functionGlyph else v.keyText
            "fnInk" -> v.functionGlyph
            "accent" -> v.returnPrimary.fill
            "accentInk" -> v.returnPrimary.glyph
            "fill" -> fill
            else -> v.keyText
        }
    }

    /** The theme's details on this key, in key-height units from the anchor
     *  and the key's top, clipped to the key. */
    private fun ornaments(c: Canvas, w: Float, h: Float, radius: Float, v: KeyboardThemes.Variant, cls: String,
                          on: String, fill: Int, font: Typeface?) {
        val list = v.style.ornaments.filter { it.on == on || (it.on == "function" && cls == "function" && on != "return") }
        if (list.isEmpty()) return
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
        val tp = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
        for (o in list) {
            val ax = when (o.anchor) { "left" -> 0f; "right" -> w; else -> w / 2f }
            fun X(u: Float) = ax + u * h
            fun Y(u: Float) = u * h
            c.save()
            c.clipPath(rr(0f, 0f, w, h, radius))
            for (op in o.ops) {
                val col = roleColor(op.color ?: o.color, v, cls, fill)
                // An op's own hex stays nearly solid (the mock's rule).
                val alpha = if (op.color?.startsWith("#") == true && o.alpha < 0.9f) max(o.alpha, 0.9f) else o.alpha
                val argb = Color.argb((alpha * Color.alpha(col)).toInt().coerceIn(0, 255),
                    Color.red(col), Color.green(col), Color.blue(col))
                p.color = argb
                val q = op.p
                when (op.t) {
                    "line" -> {
                        p.style = Paint.Style.STROKE; p.strokeWidth = op.w * h
                        c.drawLine(X(q[0]), Y(q[1]), X(q[2]), Y(q[3]), p)
                    }
                    "poly" -> {
                        val path = Path()
                        var i = 0
                        while (i + 1 < q.size) {
                            if (i == 0) path.moveTo(X(q[i]), Y(q[i + 1])) else path.lineTo(X(q[i]), Y(q[i + 1]))
                            i += 2
                        }
                        path.close()
                        p.style = Paint.Style.FILL
                        c.drawPath(path, p)
                    }
                    "circle" -> {
                        if (op.w > 0f) { p.style = Paint.Style.STROKE; p.strokeWidth = op.w * h } else p.style = Paint.Style.FILL
                        c.drawCircle(X(q[0]), Y(q[1]), q[2] * h, p)
                    }
                    "rect" -> {
                        if (op.w > 0f) { p.style = Paint.Style.STROKE; p.strokeWidth = op.w * h } else p.style = Paint.Style.FILL
                        val rad = max(0.01f, q[4] * h)
                        c.drawRoundRect(RectF(X(q[0]), Y(q[1]), X(q[0]) + q[2] * h, Y(q[1]) + q[3] * h), rad, rad, p)
                    }
                    "text" -> {
                        val base = when (op.font) {
                            "mono" -> Typeface.MONOSPACE
                            "theme" -> font ?: Typeface.DEFAULT
                            else -> Typeface.DEFAULT
                        }
                        tp.typeface = Typeface.create(base, op.weight.coerceIn(1, 1000), false)
                        tp.textSize = op.size * h
                        tp.letterSpacing = op.tracking
                        tp.color = argb
                        val fm = tp.fontMetrics
                        // Centred on its point, as canvas's middle baseline.
                        c.drawText(textStyle(op.s ?: ""), X(q[0]), Y(q[1]) - (fm.ascent + fm.descent) / 2f, tp)
                    }
                }
            }
            c.restore()
        }
    }

    /** Card suits and the other dingbats in their text form (U+FE0E after
     *  each): Android otherwise draws them as colour emoji, in their own
     *  colours and larger than the mock's. */
    private fun textStyle(s: String): String {
        if (s.none { it.code in 0x2600..0x27BF }) return s
        val b = StringBuilder()
        for (ch in s) { b.append(ch); if (ch.code in 0x2600..0x27BF) b.append('\uFE0E') }
        return b.toString()
    }

    companion object {
        /** Brushed metal's three bands: centre and half-height, in key heights. */
        private val METAL = listOf(0.22f to 0.10f, 0.58f to 0.16f, 0.84f to 0.08f)

        /** Relative luminance (sRGB), the mock's lum(). */
        fun luminance(c: Int): Double {
            fun ch(v: Int): Double { val s = v / 255.0; return if (s <= 0.04045) s / 12.92 else Math.pow((s + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(Color.red(c)) + 0.7152 * ch(Color.green(c)) + 0.0722 * ch(Color.blue(c))
        }

        /** Canvas's shadowBlur is twice the blur's sigma; Android's shadow
         *  radius r has sigma 0.57735 r + 0.5 (px). */
        fun shadowRadius(canvasBlurPx: Float) = max(0.01f, (canvasBlurPx / 2f - 0.5f) / 0.57735f)
    }
}

/**
 * The finish textures (shared/themes/textures, shipped in the app's assets
 * at assets/themes/textures and read here from flutter_assets, as the theme
 * fonts are): 256x256 grey and alpha tiles, each a repeating shader at one
 * image pixel per device pixel. Loaded the first time a theme asks.
 */
object ThemeTextureTiles {
    const val DIR = "flutter_assets/assets/themes/textures/"
    private val shaders = HashMap<String, Shader?>()

    fun shader(ctx: Context, name: String): Shader? {
        if (shaders.containsKey(name)) return shaders[name]
        val s = try {
            ctx.assets.open("$DIR$name.png").use { input ->
                val o = BitmapFactory.Options().apply { inScaled = false; inPreferredConfig = Bitmap.Config.ARGB_8888 }
                BitmapFactory.decodeStream(input, null, o)
            }?.let { BitmapShader(it, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT) }
        } catch (e: Exception) {
            android.util.Log.w("GlyfKB", "theme texture $name: $e"); null
        }
        shaders[name] = s
        return s
    }
}
