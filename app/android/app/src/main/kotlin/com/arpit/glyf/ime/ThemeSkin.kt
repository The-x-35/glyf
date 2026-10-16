package com.arpit.glyf.ime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.sin

/**
 * What a keyboard theme (docs/THEMES.md, KeyboardThemes) brings besides its
 * colours: the key-face font, the painted board with its texture, and the
 * key sounds. None of it changes a size: fonts draw at today's sizes, the
 * board sits behind the keys, sounds only play.
 */
object ThemeFonts {
    private val faces = HashMap<String, Typeface?>()

    /** The theme's face, loaded the first time it is asked for (from the
     *  same flutter_assets copy the app's previews use); null keeps Inter. */
    fun face(ctx: Context, font: KeyboardThemes.Font?): Typeface? {
        font ?: return null
        val key = font.asset + "|" + font.weight
        if (faces.containsKey(key)) return faces[key]
        val face = try {
            Typeface.Builder(ctx.assets, font.asset).apply {
                if (font.variable) setFontVariationSettings("'wght' ${font.weight}")
            }.build()
        } catch (_: Exception) { null }
        faces[key] = face
        return face
    }
}

/**
 * The theme's sounds (§4.3), from res/raw (tools/gen_theme_sounds.py):
 * theme_<pack>_<role>.wav for letter, space, delete and return. A role the
 * pack lacks plays its letter; a pack without a letter (sonar) leaves the
 * letters to the system click, which the caller plays when [play] is false.
 */
class ThemeSound(private val ctx: Context) {
    private var pack = "system"
    private var pool: android.media.SoundPool? = null
    private val ids = HashMap<String, Int>()
    private val ready = HashSet<Int>()

    fun use(newPack: String) {
        if (newPack == pack) return
        release()
        pack = newPack
        if (newPack == "system") return
        val p = android.media.SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build())
            .build()
        p.setOnLoadCompleteListener { _, id, status -> if (status == 0) ready += id }
        for (role in ROLES) {
            val res = ctx.resources.getIdentifier("theme_${newPack}_$role", "raw", ctx.packageName)
            if (res != 0) ids[role] = p.load(ctx, res, 1)
        }
        pool = p
    }

    /** True when a theme sample played; false means "play today's click". */
    fun play(role: String): Boolean {
        val p = pool ?: return false
        val id = ids[role] ?: ids["letter"] ?: return false
        if (id !in ready) return false
        return p.play(id, 1f, 1f, 1, 0, 1f) != 0
    }

    fun release() {
        pool?.release()
        pool = null
        ids.clear()
        ready.clear()
        pack = "system"
    }

    companion object {
        val ROLES = listOf("letter", "space", "delete", "return")
    }
}

/**
 * The painted board (§3, Android only): the theme's colour or two-stop
 * gradient, then its texture, drawn once into a bitmap the size of the
 * keyboard and reused until the size or the theme changes.
 */
class ThemeBackdrop(
    private val theme: KeyboardThemes.Theme,
    private val dark: Boolean,
    private val density: Float,
) : Drawable() {
    private val v = theme.variant(dark)
    private var cache: Bitmap? = null
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (b.width() <= 0 || b.height() <= 0) return
        var bmp = cache
        if (bmp == null || bmp.width != b.width() || bmp.height != b.height()) {
            bmp?.recycle()
            bmp = Bitmap.createBitmap(b.width(), b.height(), Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            try {
                ThemeTextures.paintBoard(c, b.width().toFloat(), b.height().toFloat(), theme, dark, density)
            } catch (e: Exception) {
                // A texture must never take the keyboard down: the plain board.
                android.util.Log.w("GlyfKB", "theme texture ${theme.id}: $e")
                c.drawColor(v.board[0])
            }
            cache = bmp
        }
        canvas.drawBitmap(bmp, b.left.toFloat(), b.top.toFloat(), paint)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = PixelFormat.OPAQUE
    /** The board's first stop, for anything that needs one colour. */
    val boardColor get() = v.board[0]
}

/** The 20 board textures and Marble's key veins, each made from the
 *  spec's recipe (§6), seeded so a theme looks the same every time. */
object ThemeTextures {

    fun paintBoard(c: Canvas, w: Float, h: Float, theme: KeyboardThemes.Theme, dark: Boolean, d: Float) {
        val v = theme.variant(dark)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        if (v.board.size >= 2) {
            // CSS angles: 0 points up, clockwise; the line spans the box.
            val a = Math.toRadians((v.boardAngle ?: 180f).toDouble())
            val dx = sin(a).toFloat(); val dy = -cos(a).toFloat()
            val half = (abs(w * dx) + abs(h * dy)) / 2f
            p.shader = LinearGradient(w / 2 - dx * half, h / 2 - dy * half, w / 2 + dx * half, h / 2 + dy * half,
                v.board[0], v.board[1], Shader.TileMode.CLAMP)
        } else p.color = v.board[0]
        c.drawRect(0f, 0f, w, h, p)
        val amp = theme.texture?.amplitude ?: return
        if (theme.texture.android == "none") return
        val ink = v.stripText
        val rng = java.util.Random(theme.id.hashCode().toLong() * 31 + if (dark) 1 else 0)
        // The texture library, by kind (the JSON's texture.kind; a theme
        // without one names its own id, the legacy spelling of each kind
        // below). An unknown kind paints no texture: the board alone.
        val kind = LEGACY[theme.texture.kind]?.let { if (dark) it.second else it.first } ?: theme.texture.kind
        when (kind) {
            "paper" -> tile(c, w, h, grain(128, ink, amp, 0.005f, 3, 6, rng))
            "washi" -> tile(c, w, h, grain(128, ink, amp, 0.008f, 6, 14, rng))
            "brushed" -> tile(c, w, h, brushed(ink, amp, rng))
            "leatherette" -> tile(c, w, h, leatherette(ink, amp, rng))
            "woodgrain" -> tile(c, w, h, walnut(if (dark) Color.WHITE else ink, if (dark) 0.08f else amp, rng))
            "marble" -> tile(c, w, h, veins(256, if (dark) Color.WHITE else ink, amp * 2f, rng))
            "retrogrid" -> synthwave(c, w, h, d, amp)
            "scanlines" -> tile(c, w, h, scanlines())
            "fanfold" -> tile(c, w, h, fanfold())
            "petals" -> { tile(c, w, h, grain(128, ink, 0.02f, 0.005f, 3, 6, rng)); petals(c, w, h, d, ink) }
            "caustics" -> tile(c, w, h, caustics(if (dark) Color.WHITE else ink, amp, rng))
            "ripples" -> tile(c, w, h, ripples(ink, amp, rng))
            "speckle" -> moss(c, w, h, v.returnPrimary.fill, amp, rng)
            "tweed" -> { tile(c, w, h, tweed(ink, rng)); vignette(c, w, h) }
            "engraving" -> wonderland(c, w, h, d, ink)
            "lattice" -> lattice(c, w, h, d)
            "rivets" -> rivets(c, w, d)
            "chart" -> tile(c, w, h, contours(ink, rng))
            "sunburst" -> sunburst(c, w, h, d)
            "velvet" -> { tile(c, w, h, velvet(rng)); tracery(c, w, d) }
            "skyline" -> { tile(c, w, h, rain(rng)); skyline(c, w, h, d) }
            "flecks" -> tile(c, w, h, flecks(rng))
            "circuit" -> tile(c, w, h, traces(rng))
            "stars" -> stars(c, w, h, d, if (dark) Color.WHITE else ink, rng)
            "blinds" -> blinds(c, w, h, d)
        }
    }

    /** Texture kinds spelt as the theme ids of the first themes.json
     *  (no "kind" field yet): light kind, dark kind. */
    val LEGACY = mapOf(
        "typewriter" to ("paper" to "paper"), "rangefinder" to ("brushed" to "leatherette"),
        "walnut" to ("woodgrain" to "woodgrain"), "marble" to ("marble" to "marble"),
        "synthwave" to ("retrogrid" to "retrogrid"), "terminal" to ("fanfold" to "scanlines"),
        "sakura" to ("petals" to "petals"), "ocean" to ("caustics" to "caustics"),
        "sahara" to ("ripples" to "ripples"), "moss" to ("speckle" to "speckle"),
        "baker" to ("tweed" to "tweed"), "wonderland" to ("engraving" to "engraving"),
        "emerald" to ("lattice" to "lattice"), "nautilus" to ("chart" to "rivets"),
        "gatsby" to ("sunburst" to "sunburst"), "dracula" to ("velvet" to "velvet"),
        "rooftop" to ("skyline" to "skyline"), "samurai" to ("washi" to "flecks"),
        "overclock" to ("circuit" to "circuit"), "orbit" to ("stars" to "stars"),
        "noir" to ("blinds" to "blinds"),
    )

    /** Every kind the library paints (a JSON texture.kind names one). */
    val KINDS = setOf("paper", "washi", "brushed", "leatherette", "woodgrain", "marble", "retrogrid",
        "scanlines", "fanfold", "petals", "caustics", "ripples", "speckle", "tweed", "engraving", "lattice",
        "rivets", "chart", "sunburst", "velvet", "skyline", "flecks", "circuit", "stars", "blinds")

    /** Marble's veins over its letter keys: the key text's colour at 3%. */
    fun keyVeins(ink: Int): Bitmap = veins(256, ink, 0.03f, java.util.Random(7))

    // MARK: helpers

    private val gold = Color.rgb(0xC9, 0xA4, 0x4C)

    private fun tile(c: Canvas, w: Float, h: Float, bmp: Bitmap) {
        val p = Paint().apply { shader = BitmapShader(bmp, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT) }
        c.drawRect(0f, 0f, w, h, p)
        bmp.recycle()
    }

    private fun argb(a: Float, c: Int) =
        Color.argb((a.coerceIn(0f, 1f) * 255).toInt(), Color.red(c), Color.green(c), Color.blue(c))

    /** Tileable value noise on a [cells]-wide lattice, 0..1. */
    private class Noise(val cells: Int, rng: java.util.Random) {
        private val g = FloatArray(cells * cells) { rng.nextFloat() }
        fun at(x: Float, y: Float): Float {
            val x0 = floor(x).toInt(); val y0 = floor(y).toInt()
            val fx = x - x0; val fy = y - y0
            fun v(i: Int, j: Int) = g[Math.floorMod(j, cells) * cells + Math.floorMod(i, cells)]
            val sx = fx * fx * (3 - 2 * fx); val sy = fy * fy * (3 - 2 * fy)
            val a = v(x0, y0) + (v(x0 + 1, y0) - v(x0, y0)) * sx
            val b = v(x0, y0 + 1) + (v(x0 + 1, y0 + 1) - v(x0, y0 + 1)) * sx
            return a + (b - a) * sy
        }
    }

    /** Fractal noise over a [size] tile: [octaves] lattices of 4, 8, 16... */
    private fun fbm(size: Int, octaves: Int, rng: java.util.Random): (Int, Int) -> Float {
        val layers = (0 until octaves).map { Noise(4 shl it, rng) }
        return { x, y ->
            var sum = 0f; var amp = 0.5f; var norm = 0f
            for ((i, n) in layers.withIndex()) {
                val cells = (4 shl i).toFloat()
                sum += amp * n.at(x * cells / size, y * cells / size)
                norm += amp; amp *= 0.5f
            }
            sum / norm
        }
    }

    private fun pixels(w: Int, h: Int, f: (Int, Int) -> Int): Bitmap {
        val px = IntArray(w * h)
        for (y in 0 until h) for (x in 0 until w) px[y * w + x] = f(x, y)
        // Mutable: some tiles draw fibres or flecks over their noise.
        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply { setPixels(px, 0, w, 0, 0, w, h) }
    }

    /** Paper or washi: value noise at 1px plus a few longer fibres. */
    private fun grain(size: Int, ink: Int, amp: Float, fibreShare: Float, minLen: Int, maxLen: Int,
                      rng: java.util.Random): Bitmap {
        val n = Noise(size, rng)
        val bmp = pixels(size, size) { x, y -> argb(amp * n.at(x.toFloat(), y.toFloat()), ink) }
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(amp * 1.6f, ink); strokeWidth = 1f }
        repeat((size * size * fibreShare).toInt()) {
            val x = rng.nextFloat() * size; val y = rng.nextFloat() * size
            val len = minLen + rng.nextFloat() * (maxLen - minLen)
            val a = rng.nextFloat() * Math.PI.toFloat()
            val ex = x + cos(a) * len; val ey = y + sin(a) * len
            // Drawn at each wrap so the tile stays seamless.
            for (ox in intArrayOf(-size, 0, size)) for (oy in intArrayOf(-size, 0, size))
                c.drawLine(x + ox, y + oy, ex + ox, ey + oy, p)
        }
        return bmp
    }

    private fun brushed(ink: Int, amp: Float, rng: java.util.Random): Bitmap {
        val w = 256; val h = 32
        val rows = FloatArray(h) { 0.02f + rng.nextFloat() * 0.04f }
        val raw = Array(h) { y -> FloatArray(w) { rows[y] * (0.7f + 0.6f * rng.nextFloat()) } }
        return pixels(w, h) { x, y ->
            val blur = (raw[y][Math.floorMod(x - 1, w)] + raw[y][x] + raw[y][(x + 1) % w]) / 3f
            argb(blur * amp / 0.04f * 0.6f, ink)
        }
    }

    /** Cellular noise's edges (F2 - F1) in a tileable [size] square. */
    private fun cellular(size: Int, cell: Float, rng: java.util.Random): (Int, Int) -> Float {
        val n = (size / cell).toInt().coerceAtLeast(2)
        val step = size.toFloat() / n
        val pts = Array(n * n) { floatArrayOf(rng.nextFloat(), rng.nextFloat()) }
        return { x, y ->
            val gx = (x / step).toInt(); val gy = (y / step).toInt()
            var f1 = Float.MAX_VALUE; var f2 = Float.MAX_VALUE
            for (j in -1..1) for (i in -1..1) {
                val cx = gx + i; val cy = gy + j
                val pt = pts[Math.floorMod(cy, n) * n + Math.floorMod(cx, n)]
                val px = (cx + pt[0]) * step; val py = (cy + pt[1]) * step
                val dd = hypot(px - x, py - y)
                if (dd < f1) { f2 = f1; f1 = dd } else if (dd < f2) f2 = dd
            }
            (f2 - f1) / step
        }
    }

    private fun leatherette(ink: Int, amp: Float, rng: java.util.Random): Bitmap {
        val e = cellular(96, 4f, rng)
        return pixels(96, 96) { x, y ->
            val edge = (1f - (e(x, y) / 0.25f).coerceIn(0f, 1f))
            argb(edge * amp, Color.BLACK)
        }
    }

    private fun walnut(ink: Int, amp: Float, rng: java.util.Random): Bitmap {
        val w = 512; val h = 64
        val n = Noise(8, rng); val n2 = Noise(16, rng)
        val period = 7f + rng.nextFloat() * 4f
        return pixels(w, h) { x, y ->
            val warp = 3f * (n.at(x * 8f / w, y * 8f / h * 0.2f) + 0.5f * n2.at(x * 16f / w, y * 16f / h * 0.2f))
            val band = 0.5f + 0.5f * sin((2 * Math.PI * (y / period + warp)).toFloat())
            argb(band * amp, ink)
        }
    }

    private fun veins(size: Int, ink: Int, amp: Float, rng: java.util.Random): Bitmap {
        val f = fbm(size, 4, rng)
        return pixels(size, size) { x, y ->
            val t = abs(sin((2 * Math.PI * 2 * x / size).toFloat() + 6f * f(x, y)))
            val line = (1f - t / 0.09f).coerceIn(0f, 1f)
            argb(line * amp, ink)
        }
    }

    private fun scanlines(): Bitmap = pixels(1, 3) { _, y -> if (y == 0) argb(0.25f, Color.BLACK) else 0 }

    private fun fanfold(): Bitmap = pixels(1, 48) { _, y -> if (y < 24) Color.rgb(0xDD, 0xEB, 0xD9) else 0 }

    private fun caustics(ink: Int, amp: Float, rng: java.util.Random): Bitmap {
        val e = cellular(256, 32f, rng)
        return pixels(256, 256) { x, y ->
            val t = (e(x, y) / 0.08f).coerceIn(0f, 1f)
            val s = 1f - t * t * (3 - 2 * t)
            argb(s * amp, ink)
        }
    }

    private fun ripples(ink: Int, amp: Float, rng: java.util.Random): Bitmap {
        val w = 256; val h = 128
        val n = Noise(4, rng)
        val raw = Array(h) { y -> FloatArray(w) { x ->
            val v = sin((2 * Math.PI * 4 * x / w).toFloat() + 2 * Math.PI.toFloat() * y / h + 3f * n.at(y * 4f / h, 0.5f))
            maxOf(0f, -v)
        } }
        // A 2px blur, wrapping.
        return pixels(w, h) { x, y ->
            var s = 0f
            for (j in -2..2) for (i in -2..2) s += raw[Math.floorMod(y + j, h)][Math.floorMod(x + i, w)]
            argb(s / 25f * amp, ink)
        }
    }

    private fun moss(c: Canvas, w: Float, h: Float, green: Int, amp: Float, rng: java.util.Random) {
        val f = fbm(128, 3, rng)
        val specks = pixels(128, 128) { x, y -> if (f(x, y) > 0.55f) argb(amp, green) else 0 }
        val layer = c.saveLayer(0f, 0f, w, h, null)
        tile(c, w, h, specks)
        val mask = Paint().apply {
            shader = LinearGradient(0f, 0f, 0f, h, Color.TRANSPARENT, Color.BLACK, Shader.TileMode.CLAMP)
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        }
        c.drawRect(0f, 0f, w, h, mask)
        c.restoreToCount(layer)
    }

    private fun tweed(ink: Int, rng: java.util.Random): Bitmap = pixels(16, 16) { x, y ->
        // A 2/2 twill that turns every 8 columns: herringbone.
        val on = if (x < 8) ((x + y) / 2) % 2 == 0 else ((x - y + 16) / 2) % 2 == 0
        argb((if (on) 0.03f else 0f) + 0.02f * rng.nextFloat(), ink)
    }

    private fun vignette(c: Canvas, w: Float, h: Float) {
        val p = Paint().apply {
            shader = RadialGradient(0f, 0f, maxOf(w, h) * 0.7f, argb(0.06f, Color.rgb(0xFF, 0xB5, 0x5A)),
                Color.TRANSPARENT, Shader.TileMode.CLAMP)
        }
        c.drawRect(0f, 0f, w, h, p)
    }

    private fun wonderland(c: Canvas, w: Float, h: Float, d: Float, ink: Int) {
        val hatch = pixels(12, 12) { x, y -> if (x == y || x == 11 - y) argb(0.05f, ink) else 0 }
        val layer = c.saveLayer(0f, 0f, w, h, null)
        tile(c, w, h, hatch)
        val mask = Paint().apply {
            shader = RadialGradient(w / 2, h / 2, hypot(w, h) / 2, Color.TRANSPARENT, Color.BLACK, Shader.TileMode.CLAMP)
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        }
        c.drawRect(0f, 0f, w, h, mask)
        c.restoreToCount(layer)
        // The four suits, small, in the corners.
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.10f, ink) }
        val s = 9f * d; val m = 6f * d
        pip(c, "heart", m, m, s, p)
        pip(c, "spade", w - m - s, m, s, p)
        pip(c, "diamond", m, h - m - s, s, p)
        pip(c, "club", w - m - s, h - m - s, s, p)
    }

    private fun pip(c: Canvas, suit: String, x: Float, y: Float, s: Float, p: Paint) {
        val path = Path()
        when (suit) {
            "diamond" -> { path.moveTo(x + s / 2, y); path.lineTo(x + s * 0.9f, y + s / 2)
                path.lineTo(x + s / 2, y + s); path.lineTo(x + s * 0.1f, y + s / 2); path.close() }
            "heart" -> { path.moveTo(x + s / 2, y + s)
                path.cubicTo(x - s * 0.2f, y + s * 0.45f, x + s * 0.2f, y - s * 0.1f, x + s / 2, y + s * 0.28f)
                path.cubicTo(x + s * 0.8f, y - s * 0.1f, x + s * 1.2f, y + s * 0.45f, x + s / 2, y + s); path.close() }
            "spade" -> { path.moveTo(x + s / 2, y)
                path.cubicTo(x + s * 1.2f, y + s * 0.55f, x + s * 0.8f, y + s * 0.95f, x + s / 2, y + s * 0.65f)
                path.cubicTo(x + s * 0.2f, y + s * 0.95f, x - s * 0.2f, y + s * 0.55f, x + s / 2, y); path.close()
                path.addRect(x + s * 0.44f, y + s * 0.6f, x + s * 0.56f, y + s, Path.Direction.CW) }
            else -> { val r = s * 0.22f
                path.addCircle(x + s / 2, y + r, r, Path.Direction.CW)
                path.addCircle(x + s / 2 - r * 1.1f, y + s * 0.5f, r, Path.Direction.CW)
                path.addCircle(x + s / 2 + r * 1.1f, y + s * 0.5f, r, Path.Direction.CW)
                path.addRect(x + s * 0.44f, y + s * 0.5f, x + s * 0.56f, y + s, Path.Direction.CW) }
        }
        c.drawPath(path, p)
    }

    private fun lattice(c: Canvas, w: Float, h: Float, d: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.05f, gold); strokeWidth = 0.75f * d }
        val dw = 18f * d; val dh = 30f * d
        val slope = dh / dw
        // Lines both ways through every diamond's corners.
        var x0 = -h / slope
        while (x0 < w + h / slope) {
            c.drawLine(x0, 0f, x0 + h / slope, h, p)
            c.drawLine(x0, h, x0 + h / slope, 0f, p)
            x0 += dw
        }
        p.style = Paint.Style.FILL
        var row = 0
        var y = 0f
        while (y <= h + dh) {
            var x = if (row % 2 == 0) 0f else dw / 2
            while (x <= w + dw) { c.drawCircle(x, y, 0.9f * d, p); x += dw }
            y += dh / 2; row++
        }
    }

    private fun synthwave(c: Canvas, w: Float, h: Float, d: Float, amp: Float) {
        val cyan = Color.rgb(0x3C, 0xF0, 0xFF)
        val y0 = h * 0.66f
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeWidth = maxOf(1f, d * 0.5f)
            shader = LinearGradient(0f, y0, 0f, h, Color.TRANSPARENT, argb(0.10f, cyan), Shader.TileMode.CLAMP)
        }
        for (i in 0 until 12) {
            val t = (i + 0.5f) / 12f
            c.drawLine(w / 2, y0, -w + t * 3 * w, h, p)
        }
        for (i in 1..6) {
            val t = i / 6f
            val y = y0 + (h - y0) * t * t
            c.drawLine(0f, y, w, y, p)
        }
        // The sun behind the bottom row, a half disc with five gaps.
        val cx = w / 2; val cy = h * 0.86f; val r = minOf(w * 0.22f, 90f * d)
        val layer = c.saveLayer(0f, 0f, w, h, null)
        val sun = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(cx, cy, r, argb(0.18f, Color.rgb(0xFF, 0x4F, 0xD8)),
                Color.TRANSPARENT, Shader.TileMode.CLAMP)
        }
        c.drawArc(RectF(cx - r, cy - r, cx + r, cy + r), 180f, 180f, true, sun)
        val cut = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR) }
        for (i in 1..5) {
            val y = cy - r * i / 6f
            c.drawRect(cx - r, y - d * (0.6f + i * 0.25f), cx + r, y, cut)
        }
        c.restoreToCount(layer)
    }

    private fun petals(c: Canvas, w: Float, h: Float, d: Float, ink: Int) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = d * 0.75f; color = argb(0.06f, ink)
        }
        val ox = w - 240f * d; val oy = h - 120f * d
        val spots = listOf(floatArrayOf(40f, 30f, 20f), floatArrayOf(110f, 18f, -35f), floatArrayOf(170f, 52f, 60f),
            floatArrayOf(205f, 20f, 15f), floatArrayOf(85f, 80f, -70f), floatArrayOf(150f, 98f, 110f))
        for (s in spots) {
            c.save()
            c.translate(ox + s[0] * d, oy + s[1] * d)
            c.rotate(s[2])
            val k = 7f * d
            // A cherry petal: round at the tip, notched, narrowing to its base.
            val path = Path().apply {
                moveTo(0f, k)
                cubicTo(-k * 1.1f, k * 0.2f, -k * 0.8f, -k * 0.9f, -k * 0.2f, -k)
                lineTo(0f, -k * 0.75f)
                lineTo(k * 0.2f, -k)
                cubicTo(k * 0.8f, -k * 0.9f, k * 1.1f, k * 0.2f, 0f, k)
                close()
            }
            c.drawPath(path, p)
            c.restore()
        }
    }

    private fun contours(navy: Int, rng: java.util.Random): Bitmap {
        val f = fbm(256, 3, rng)
        val levels = floatArrayOf(0.3f, 0.4f, 0.5f, 0.6f, 0.7f)
        return pixels(256, 256) { x, y ->
            val v = f(x, y)
            val near = levels.minOf { abs(v - it) }
            if (near < 0.004f) argb(0.05f, navy) else 0
        }
    }

    private fun rivets(c: Canvas, w: Float, d: Float) {
        val hi = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.06f, Color.WHITE) }
        val lo = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.06f, Color.BLACK) }
        var x = 7f * d
        while (x < w) {
            c.drawCircle(x, 6f * d + 0.5f * d, d, lo)
            c.drawCircle(x, 6f * d, d, hi)
            x += 14f * d
        }
        val line = Paint().apply { color = argb(0.03f, Color.WHITE); strokeWidth = 1f }
        for (y in floatArrayOf(14f, 15.5f)) c.drawLine(0f, y * d, w, y * d, line)
    }

    private fun sunburst(c: Canvas, w: Float, h: Float, d: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = argb(0.06f, gold); strokeWidth = 0.75f * d; style = Paint.Style.STROKE
        }
        val cx = w / 2; val cy = h + 20f * d
        val far = hypot(w, h) * 1.2f
        for (i in 0 until 21) {
            val a = Math.PI + Math.PI * (i + 0.5) / 21
            c.drawLine(cx, cy, cx + (cos(a) * far).toFloat(), cy + (sin(a) * far).toFloat(), p)
        }
        for (k in 1..3) {
            val r = h * 0.28f * k
            c.drawArc(RectF(cx - r, cy - r, cx + r, cy + r), 180f, 180f, false, p)
        }
    }

    private fun velvet(rng: java.util.Random): Bitmap {
        val f = fbm(128, 2, rng)
        return pixels(128, 128) { x, y ->
            val v = (f(x, y) - 0.5f) * 2f
            if (v > 0) argb(0.04f * v, Color.WHITE) else argb(-0.04f * v, Color.BLACK)
        }
    }

    private fun tracery(c: Canvas, w: Float, d: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = argb(0.05f, gold); style = Paint.Style.STROKE; strokeWidth = 0.75f * d
        }
        val aw = 40f * d; val ah = 40f * d
        var x = 0f
        while (x < w) {
            // A lancet: two arcs meeting in a point, on straight sides.
            val path = Path().apply {
                moveTo(x + aw * 0.1f, ah)
                lineTo(x + aw * 0.1f, ah * 0.55f)
                quadTo(x + aw * 0.1f, ah * 0.12f, x + aw / 2, 2f * d)
                quadTo(x + aw * 0.9f, ah * 0.12f, x + aw * 0.9f, ah * 0.55f)
                lineTo(x + aw * 0.9f, ah)
            }
            c.drawPath(path, p)
            x += aw
        }
    }

    private fun rain(rng: java.util.Random): Bitmap {
        val bmp = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.04f, Color.WHITE); strokeWidth = 1f }
        repeat(6) {
            val x = rng.nextFloat() * 64; val y = rng.nextFloat() * 64
            val len = 8f + rng.nextFloat() * 6f
            for (ox in intArrayOf(-64, 0, 64)) for (oy in intArrayOf(-64, 0, 64))
                c.drawLine(x + ox, y + oy, x + ox - len * 0.35f, y + oy + len, p)
        }
        return bmp
    }

    private fun skyline(c: Canvas, w: Float, h: Float, d: Float) {
        // 400 by 48 units: roofs, two water towers, a fire escape, one mast.
        val k = w / 400f
        val base = h
        val top = h - 48f * k
        fun y(u: Float) = top + u * k
        val path = Path().apply {
            moveTo(0f, base)
            val roofs = listOf(0f to 30f, 34f to 22f, 70f to 34f, 96f to 18f, 140f to 28f, 176f to 12f,
                210f to 26f, 248f to 20f, 290f to 32f, 318f to 16f, 360f to 27f, 400f to 27f)
            for (i in 0 until roofs.size - 1) {
                val (x0, r) = roofs[i]
                lineTo(x0 * k, y(r)); lineTo(roofs[i + 1].first * k, y(r))
            }
            lineTo(w, base); close()
            // Water towers on legs.
            for (tx in floatArrayOf(46f, 262f)) {
                val roof = if (tx < 100) 22f else 20f
                addRect(tx * k, y(roof - 9f), (tx + 10f) * k, y(roof - 3f), Path.Direction.CW)
                moveTo(tx * k, y(roof - 9f)); lineTo((tx + 5f) * k, y(roof - 13f)); lineTo((tx + 10f) * k, y(roof - 9f)); close()
                addRect((tx + 1f) * k, y(roof - 3f), (tx + 2f) * k, y(roof), Path.Direction.CW)
                addRect((tx + 8f) * k, y(roof - 3f), (tx + 9f) * k, y(roof), Path.Direction.CW)
            }
            // The mast.
            addRect(182f * k, y(0f), 183.2f * k, y(12f), Path.Direction.CW)
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.30f, Color.BLACK) }
        c.drawPath(path, fill)
        // A fire escape's zigzag on one face.
        val esc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = argb(0.30f, Color.BLACK); style = Paint.Style.STROKE; strokeWidth = maxOf(1f, 0.6f * k)
        }
        for (i in 0 until 3) {
            val yy = y(36f + i * 4f)
            c.drawLine(300f * k, yy, 312f * k, yy, esc)
            c.drawLine(300f * k, yy, 312f * k, yy + 4f * k, esc)
        }
    }

    private fun flecks(rng: java.util.Random): Bitmap {
        val n = Noise(160, rng)
        val bmp = pixels(160, 160) { x, y -> argb(0.01f * n.at(x.toFloat(), y.toFloat()), Color.WHITE) }
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.18f, gold) }
        repeat(14) {
            val cx = rng.nextFloat() * 160; val cy = rng.nextFloat() * 160
            val r = 0.5f + rng.nextFloat()
            val path = Path()
            val sides = 3 + rng.nextInt(3)
            for (i in 0 until sides) {
                val a = 2 * Math.PI * i / sides + rng.nextFloat()
                val rr = r * (0.6f + rng.nextFloat() * 0.8f)
                val px = cx + (cos(a) * rr).toFloat(); val py = cy + (sin(a) * rr).toFloat()
                if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
            }
            path.close()
            c.drawPath(path, p)
        }
        return bmp
    }

    private fun traces(rng: java.util.Random): Bitmap {
        val bmp = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val cyan = Color.rgb(0x00, 0xE5, 0xFF)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = argb(0.05f, cyan); strokeWidth = 1f; style = Paint.Style.STROKE
        }
        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(0.05f, cyan) }
        val dirs = listOf(1 to 0, 1 to 1, 0 to 1, -1 to 1, -1 to 0, -1 to -1, 0 to -1, 1 to -1)
        repeat(8) {
            var x = rng.nextInt(16) * 8f; var y = rng.nextInt(16) * 8f
            var dir = rng.nextInt(8)
            val path = Path().apply { moveTo(x, y) }
            val start = floatArrayOf(x, y)
            repeat(4 + rng.nextInt(5)) {
                val (dx, dy) = dirs[dir]
                x += dx * 8f; y += dy * 8f
                path.lineTo(x, y)
                // Turns of 45 degrees only.
                dir = Math.floorMod(dir + rng.nextInt(3) - 1, 8)
            }
            for (ox in intArrayOf(-128, 0, 128)) for (oy in intArrayOf(-128, 0, 128)) {
                c.save(); c.translate(ox.toFloat(), oy.toFloat())
                c.drawPath(path, p)
                c.drawCircle(start[0], start[1], 1f, dot)
                c.drawCircle(x, y, 1f, dot)
                c.restore()
            }
        }
        return bmp
    }

    private fun stars(c: Canvas, w: Float, h: Float, d: Float, ink: Int, rng: java.util.Random) {
        val count = (w / d * h / d / 900f).toInt()
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        repeat(count) {
            p.color = argb(0.15f + rng.nextFloat() * 0.30f, ink)
            val s = if (rng.nextFloat() < 0.03f) 2f * d else d
            val x = rng.nextFloat() * w; val y = rng.nextFloat() * h
            c.drawRect(x, y, x + s, y + s, p)
        }
    }

    private fun blinds(c: Canvas, w: Float, h: Float, d: Float) {
        c.save()
        c.rotate(-18f, w / 2, h / 2)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val start = w * 0.18f
        for (i in 0 until 7) {
            val x = start + i * 24f * d
            // A 10dp band with a 4dp soft edge either side: four layers
            // of 1% stack to 4% in the middle.
            for (k in 0..3) {
                p.color = argb(0.01f, Color.WHITE)
                val e = (4 - k) * d
                c.drawRect(x - e, -h, x + 10f * d + e, 2 * h, p)
            }
        }
        c.restore()
    }
}
