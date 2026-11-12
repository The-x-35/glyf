package com.arpit.glyf.ime

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.view.View
import kotlin.math.min

/**
 * SVG path data ("M0,101.12c0-34.64…z") as drawing steps: move, line,
 * horizontal, vertical, cubic, smooth cubic, quadratic and close, absolute
 * and relative, with repeated arguments. The twin of iOS's SVGPath
 * (ChainLogo.swift); pure, so its reading is tested, and [path] turns the
 * steps into an android.graphics.Path.
 */
object SvgPath {

    /** One step, in absolute coordinates: "M" x y, "L" x y, "C" x1 y1 x2 y2 x y,
     *  "Q" x1 y1 x y, "Z". */
    data class Op(val cmd: Char, val v: List<Float> = emptyList())

    fun ops(d: String): List<Op> {
        val tokens = mutableListOf<Any>()
        val number = StringBuilder()
        fun flush() {
            if (number.isNotEmpty()) TradeIntent.number(number.toString())?.let { tokens.add(it.toFloat()) }
            number.setLength(0)
        }
        var prev = ' '
        for (ch in d) {
            when {
                ch.isLetter() && ch != 'e' && ch != 'E' -> { flush(); tokens.add(ch) }
                ch == '-' && !(prev == 'e' || prev == 'E') -> { flush(); number.append('-') }
                ch == '.' && number.contains('.') -> { flush(); number.append('.') }
                ch == ',' || ch == ' ' || ch == '\n' || ch == '\t' -> flush()
                else -> number.append(ch)
            }
            prev = ch
        }
        flush()
        val out = mutableListOf<Op>()
        var i = 0
        var cmd = 'M'
        var cx = 0f; var cy = 0f; var sx = 0f; var sy = 0f
        var lastC: Pair<Float, Float>? = null
        fun n(): Float? { val v = tokens.getOrNull(i) as? Float ?: return null; i++; return v }
        while (i < tokens.size) {
            (tokens[i] as? Char)?.let { cmd = it; i++ }
            val rel = cmd.isLowerCase()
            val ox = if (rel) cx else 0f
            val oy = if (rel) cy else 0f
            when (cmd) {
                'M', 'm' -> {
                    val x = n(); val y = n()
                    if (x == null || y == null) { i++; continue }
                    cx = ox + x; cy = oy + y; sx = cx; sy = cy
                    out.add(Op('M', listOf(cx, cy)))
                    cmd = if (rel) 'l' else 'L'
                    lastC = null
                }
                'L', 'l' -> {
                    val x = n(); val y = n()
                    if (x == null || y == null) { i++; continue }
                    cx = ox + x; cy = oy + y
                    out.add(Op('L', listOf(cx, cy))); lastC = null
                }
                'H', 'h' -> {
                    val x = n() ?: run { i++; null } ?: continue
                    cx = (if (rel) cx else 0f) + x
                    out.add(Op('L', listOf(cx, cy))); lastC = null
                }
                'V', 'v' -> {
                    val y = n() ?: run { i++; null } ?: continue
                    cy = (if (rel) cy else 0f) + y
                    out.add(Op('L', listOf(cx, cy))); lastC = null
                }
                'C', 'c' -> {
                    val v = (0 until 6).map { n() }
                    if (v.any { it == null }) { i++; continue }
                    val (x1, y1, x2, y2) = v.take(4).map { it!! }
                    val x = v[4]!!; val y = v[5]!!
                    val c2x = ox + x2; val c2y = oy + y2
                    cx = ox + x; cy = oy + y
                    out.add(Op('C', listOf(ox + x1, oy + y1, c2x, c2y, cx, cy))); lastC = c2x to c2y
                }
                'S', 's' -> {
                    val v = (0 until 4).map { n() }
                    if (v.any { it == null }) { i++; continue }
                    val c1 = lastC?.let { (2 * cx - it.first) to (2 * cy - it.second) } ?: (cx to cy)
                    val c2x = ox + v[0]!!; val c2y = oy + v[1]!!
                    cx = ox + v[2]!!; cy = oy + v[3]!!
                    out.add(Op('C', listOf(c1.first, c1.second, c2x, c2y, cx, cy))); lastC = c2x to c2y
                }
                'Q', 'q' -> {
                    val v = (0 until 4).map { n() }
                    if (v.any { it == null }) { i++; continue }
                    val qx = ox + v[0]!!; val qy = oy + v[1]!!
                    cx = ox + v[2]!!; cy = oy + v[3]!!
                    out.add(Op('Q', listOf(qx, qy, cx, cy))); lastC = null
                }
                'Z', 'z' -> { out.add(Op('Z')); cx = sx; cy = sy; lastC = null }
                else -> i++
            }
        }
        return out
    }

    fun path(d: String, evenOdd: Boolean = false): Path {
        val p = Path()
        if (evenOdd) p.fillType = Path.FillType.EVEN_ODD
        for (op in ops(d)) {
            val v = op.v
            when (op.cmd) {
                'M' -> p.moveTo(v[0], v[1])
                'L' -> p.lineTo(v[0], v[1])
                'C' -> p.cubicTo(v[0], v[1], v[2], v[3], v[4], v[5])
                'Q' -> p.quadTo(v[0], v[1], v[2], v[3])
                'Z' -> p.close()
            }
        }
        return p
    }
}

/**
 * Each chain's own mark, drawn from the vector files its team publishes, so
 * a chain reads at a glance on the trade panel, its picker and the sponsor
 * panels; nothing is fetched at run time. The same marks and sources as iOS's
 * ChainLogo.swift (Base's brand kit, Arbitrum's docs, the Solana Foundation,
 * Uniswap's Unichain icon, ethereum.org's diamond, OP Mainnet's red disc).
 */
object ChainMarks {

    data class Layer(val d: String, val fill: Int,
                     /** A sweep of colours (Solana's), in place of [fill]. */
                     val gradient: List<Pair<Double, Int>>? = null,
                     /** x0 y0 x1 y1 in the mark's own units. */
                     val line: FloatArray? = null)

    data class Mark(val w: Float, val h: Float, val layers: List<Layer>,
                    /** Drawn on a white disc (the diamond is dark on dark sheets otherwise). */
                    val disc: Boolean = false,
                    val inset: Float = 0f,
                    /** Drawn as a red disc with these letters (Optimism's mark is lettering). */
                    val lettering: String? = null)

    val marks: Map<String, Mark> = mapOf(
        "base" to Mark(1280f, 1280f, listOf(
            Layer("M0,101.12c0-34.64,0-51.95,6.53-65.28,6.25-12.76,16.56-23.07,29.32-29.32C49.17,0,66.48,0,101.12,0h1077.76c34.63,0,51.96,0,65.28,6.53,12.75,6.25,23.06,16.56,29.32,29.32,6.52,13.32,6.52,30.64,6.52,65.28v1077.76c0,34.63,0,51.96-6.52,65.28-6.26,12.75-16.57,23.06-29.32,29.32-13.32,6.52-30.65,6.52-65.28,6.52H101.12c-34.64,0-51.95,0-65.28-6.52-12.76-6.26-23.07-16.57-29.32-29.32-6.53-13.32-6.53-30.65-6.53-65.28V101.12Z", 0x0000FF)
        )),
        "arbitrum" to Mark(1080f, 1218.5f, listOf(
            Layer("M41,370.4v477.7c0,30.5,16.3,58.7,42.7,73.9l413.7,238.9c26.4,15.2,58.9,15.2,85.3,0L996.4,922 c26.4-15.2,42.7-43.4,42.7-73.9V370.4c0-30.5-16.3-58.7-42.7-73.9L582.7,57.6c-26.4-15.2-58.9-15.2-85.3,0L83.6,296.5 C57.2,311.7,41,339.9,41,370.4z", 0x213147),
            Layer("M630.3,701.9l-59,161.8c-1.6,4.5-1.6,9.4,0,13.9L672.8,1156l117.4-67.8L649.3,701.9 C646.1,693,633.5,693,630.3,701.9z", 0x12AAFF),
            Layer("M748.6,429.8c-3.2-8.9-15.8-8.9-19,0l-59,161.8c-1.6,4.5-1.6,9.4,0,13.9l166.3,455.8l117.4-67.8 L748.6,429.8z", 0x12AAFF),
            Layer("M540,75.5c2.9,0,5.8,0.8,8.4,2.2l447.7,258.5c5.2,3,8.4,8.6,8.4,14.5v516.9c0,6-3.2,11.5-8.4,14.5 l-447.7,258.5c-2.5,1.5-5.5,2.2-8.4,2.2c-2.9,0-5.8-0.8-8.4-2.2L83.9,882.3c-5.2-3-8.4-8.6-8.4-14.5V350.8c0-6,3.2-11.5,8.4-14.5 L531.6,77.8C534.2,76.3,537.1,75.5,540,75.5 M540,0c-15.9,0-31.9,4.1-46.2,12.4L46.2,270.8c-28.6,16.5-46.2,47-46.2,80v516.9 c0,33,17.6,63.5,46.2,80l447.7,258.5c14.3,8.2,30.2,12.4,46.2,12.4c15.9,0,31.9-4.1,46.2-12.4l447.7-258.5 c28.6-16.5,46.2-47,46.2-80V350.8c0-33-17.6-63.5-46.2-80L586.2,12.4C571.9,4.1,555.9,0,540,0L540,0z", 0x9DCCED),
            Layer("M243.9,1061.9 L285.1,949.1 L368,1018 L290.5,1088.8 Z", 0x213147),
            Layer("M502.3,313.8H388.8c-8.5,0-16.1,5.3-19,13.3l-243.3,667l117.4,67.8l267.9-734.5 C514.3,320.8,509.4,313.8,502.3,313.8z", 0xFFFFFF),
            Layer("M700.9,313.8H587.4c-8.5,0-16.1,5.3-19,13.3l-277.8,761.6l117.4,67.8l302.4-829.1 C712.8,320.8,707.9,313.8,700.9,313.8z", 0xFFFFFF)
        )),
        "solana" to Mark(120f, 99f, listOf(
            Layer("M119.37 78.0655L99.5477 97.658C98.6753 98.508 97.4637 99 96.2036 99H2.27787C1.01777 99 0 98.0159 0 96.8529C0 96.3161 0.242326 95.824 0.630048 95.4215L20.4039 75.8289C21.2763 74.979 22.4879 74.487 23.748 74.487H117.674C118.934 74.487 120 75.3816 120 76.5447C120 77.0814 119.806 77.6182 119.37 78.0208M99.5477 38.5226C98.6753 37.6727 97.4637 37.1807 96.2036 37.1807H2.27787C1.01777 37.2254 0 38.1648 0 39.3278C0 39.8646 0.242326 40.3566 0.630048 40.7592L20.4039 60.3965C21.2763 61.2464 22.4879 61.7384 23.748 61.7384H117.674C118.934 61.7384 119.952 60.7543 119.952 59.5913C119.952 59.0545 119.709 58.5625 119.321 58.1599L99.5477 38.5226ZM2.27787 24.4769H96.1551C97.4152 24.4769 98.6268 23.9848 99.4992 23.1349L119.37 3.54238C120.242 2.69248 120.194 1.35052 119.273 0.545352C119.176 0.455888 119.079 0.366425 118.934 0.321693C118.546 0.0980342 118.11 -0.0361611 117.674 0.00857069H23.748C22.4879 0.00857069 21.2763 0.50062 20.4039 1.35052L0.630048 20.943C-0.242326 21.7929 -0.193861 23.1349 0.775444 23.9401C1.21163 24.2979 1.74475 24.5216 2.32633 24.5216", 0x9945FF, listOf(0.08 to 0x9945FF, 0.3 to 0x8752F3, 0.5 to 0x5497D5, 0.6 to 0x43B4CA, 0.72 to 0x28E0B9, 0.97 to 0x19FB9B), floatArrayOf(10.1292f, 101.371f, 99.8282f, -8.25607f))
        ), inset = 0.08f),
        "unichain" to Mark(25f, 25f, listOf(
            Layer("M24.7441 11.9143C18.2397 11.9143 12.9725 6.6417 12.9725 0.142578H12.5159V11.9143H0.744141V12.3709C7.24858 12.3709 12.5159 17.6435 12.5159 24.1426H12.9725V12.3709H24.7441V11.9143Z", 0xF50DB4)
        )),
        "ethereum" to Mark(256f, 417f, listOf(
            Layer("M127.961 0l-2.795 9.5v275.668l2.795 2.79 127.962-75.638z", 0x343434),
            Layer("M127.962 0L0 212.32l127.962 75.639V154.158z", 0x8C8C8C),
            Layer("M127.961 312.187l-1.575 1.92v98.199l1.575 4.6L256 236.587z", 0x3C3C3B),
            Layer("M127.962 416.905v-104.72L0 236.585z", 0x8C8C8C),
            Layer("M127.961 287.958l127.96-75.637-127.96-58.162z", 0x141414),
            Layer("M0 212.32l127.96 75.638v-133.8z", 0x393939)
        ), disc = true, inset = 0.2f),
        "optimism" to Mark(1f, 1f, listOf(
            
        ), lettering = "OP"),
    )

    /** The mark for a chain key ("op" is "optimism"); null for one without a mark. */
    fun mark(chain: String): Mark? = marks[if (chain == "op") "optimism" else chain]

    fun rgb(c: Int) = Color.rgb((c shr 16) and 0xFF, (c shr 8) and 0xFF, c and 0xFF)
}

/** A chain's mark as a view, [chain] centred in its box. */
class ChainMarkView(ctx: Context, chain: String) : View(ctx) {
    var chain: String = chain
        set(value) { field = value; paths = null; invalidate() }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var paths: List<Path>? = null

    override fun onDraw(c: Canvas) {
        val mark = ChainMarks.mark(chain) ?: return
        val side = min(width, height).toFloat()
        val left = (width - side) / 2f
        val top = (height - side) / 2f
        paint.shader = null
        mark.lettering?.let { letters ->
            paint.color = ChainMarks.rgb(0xFF0420)
            c.drawOval(RectF(left, top, left + side, top + side), paint)
            paint.color = Color.WHITE
            paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD_ITALIC)
            paint.textSize = side * 0.40f
            paint.textAlign = Paint.Align.CENTER
            val fm = paint.fontMetrics
            c.drawText(letters, left + side / 2, top + side / 2 - (fm.ascent + fm.descent) / 2, paint)
            return
        }
        if (mark.disc) {
            paint.color = Color.WHITE
            c.drawOval(RectF(left, top, left + side, top + side), paint)
        }
        val boxSide = side * (1 - 2 * mark.inset)
        val scale = min(boxSide / mark.w, boxSide / mark.h)
        val w = mark.w * scale
        val h = mark.h * scale
        val ps = paths ?: mark.layers.map { SvgPath.path(it.d) }.also { paths = it }
        c.save()
        c.translate(left + (side - w) / 2f, top + (side - h) / 2f)
        c.scale(scale, scale)
        for ((k, layer) in mark.layers.withIndex()) {
            val g = layer.gradient
            val line = layer.line
            if (g != null && line != null) {
                paint.shader = LinearGradient(line[0], line[1], line[2], line[3],
                    g.map { ChainMarks.rgb(it.second) }.toIntArray(), g.map { it.first.toFloat() }.toFloatArray(),
                    Shader.TileMode.CLAMP)
            } else {
                paint.shader = null
                paint.color = ChainMarks.rgb(layer.fill)
            }
            c.drawPath(ps[k], paint)
        }
        paint.shader = null
        c.restore()
    }
}

/**
 * The g menu's sponsor marks, drawn from the partners' own artwork so no
 * image ships and nothing is fetched (iOS SponsorMarks.swift):
 * - Uniswap: the unicorn from github.com/Uniswap/brand-assets
 *   (Uniswap_icon_white.svg, 400x434), white on Uniswap pink #F50DB4.
 * - Definitive: the triangle from docs.definitive.fi (Logos & Media Kit,
 *   "Definitive Triangle"), white on black.
 */
class SponsorMarkView(ctx: Context, private val sponsor: SponsorMenu.Sponsor) : View(ctx) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val unicorn by lazy { UNICORN.map { (evenOdd, d) -> SvgPath.path(d, evenOdd) } }

    override fun onDraw(c: Canvas) {
        val size = min(width, height).toFloat()
        c.save()
        c.translate((width - size) / 2f, (height - size) / 2f)
        val face = if (sponsor == SponsorMenu.Sponsor.UNISWAP) UNISWAP_PINK else Color.BLACK
        paint.color = face
        c.drawRoundRect(RectF(0f, 0f, size, size), size * 0.26f, size * 0.26f, paint)
        paint.color = Color.WHITE
        when (sponsor) {
            SponsorMenu.Sponsor.UNISWAP -> {
                // 400x434 art, 64% of the tile tall, centred.
                val h = size * 0.64f
                val s = h / 434f
                c.save()
                c.translate((size - 400 * s) / 2f, (size - h) / 2f - size * 0.01f)
                c.scale(s, s)
                for (p in unicorn) c.drawPath(p, paint)
                c.restore()
            }
            SponsorMenu.Sponsor.DEFINITIVE -> {
                // An equilateral triangle with a triangular window, a little above centre.
                val p = Path().apply {
                    fillType = Path.FillType.EVEN_ODD
                    moveTo(0.5f * size, 0.17f * size); lineTo(0.87f * size, 0.81f * size); lineTo(0.13f * size, 0.81f * size); close()
                    moveTo(0.5f * size, 0.445f * size); lineTo(0.628f * size, 0.672f * size); lineTo(0.372f * size, 0.672f * size); close()
                }
                c.drawPath(p, paint)
            }
        }
        c.restore()
    }

    companion object {
        val UNISWAP_PINK = Color.rgb(0xF5, 0x0D, 0xB4)
        private val UNICORN: List<Pair<Boolean, String>> = listOf(
        false to "M325.144 65.7698C325.727 55.5419 327.119 48.7957 329.918 42.6348C331.025 40.1962 332.063 38.2003 332.223 38.2003C332.383 38.2003 331.902 40.0003 331.153 42.1999C329.118 48.1791 328.784 56.3572 330.186 65.872C331.965 77.9447 332.976 79.6866 345.782 92.7278C351.788 98.8446 358.775 106.559 361.307 109.871L365.912 115.894L361.307 111.59C355.676 106.327 342.724 96.0618 339.863 94.5945C337.945 93.6104 337.66 93.6274 336.477 94.801C335.387 95.8823 335.157 97.5072 335.005 105.189C334.77 117.16 333.132 124.845 329.18 132.528C327.042 136.684 326.705 135.797 328.64 131.106C330.084 127.604 330.231 126.064 330.22 114.475C330.198 91.1888 327.424 85.5906 311.153 76.0005C307.032 73.5711 300.24 70.0674 296.062 68.2141C291.883 66.3608 288.564 64.7467 288.685 64.6261C289.146 64.1691 305.013 68.7839 311.399 71.2318C320.899 74.8731 322.467 75.3449 323.621 74.9057C324.394 74.6113 324.768 72.367 325.144 65.7698Z",
        false to "M124.431 31.8931C118.795 31.0236 118.557 30.9216 121.209 30.5162C126.292 29.7389 138.292 30.7983 146.562 32.754C165.867 37.3182 183.434 49.0103 202.186 69.7754L207.168 75.2919L214.295 74.1524C244.318 69.3537 274.861 73.1675 300.407 84.9049C307.435 88.134 318.516 94.5618 319.9 96.2136C320.341 96.7401 321.151 100.129 321.699 103.745C323.597 116.255 322.647 125.843 318.8 133.005C316.707 136.903 316.59 138.138 317.997 141.473C319.121 144.135 322.253 146.105 325.355 146.1C331.703 146.092 338.536 135.885 341.702 121.683L342.96 116.042L345.452 118.849C359.117 134.248 369.85 155.248 371.694 170.196L372.174 174.093L369.877 170.55C365.924 164.454 361.952 160.303 356.866 156.956C347.697 150.922 338.002 148.868 312.327 147.523C289.139 146.307 276.015 144.337 263.002 140.117C240.861 132.937 229.699 123.375 203.399 89.0559C191.717 73.8123 184.497 65.3784 177.314 58.5864C160.994 43.1536 144.958 35.0599 124.431 31.8931Z",
        false to "M135.377 105.713C123.937 90.0473 116.858 66.0289 118.391 48.0742L118.864 42.518L121.469 42.9906C126.359 43.8778 134.791 46.9992 138.739 49.3844C149.574 55.9291 154.265 64.5458 159.037 86.6722C160.435 93.1531 162.269 100.487 163.113 102.97C164.472 106.967 169.605 116.302 173.779 122.365C176.785 126.731 174.788 128.8 168.143 128.204C157.994 127.293 144.246 117.856 135.377 105.713Z",
        false to "M311.254 222.301C257.789 200.891 238.958 182.307 238.958 150.95C238.958 146.336 239.118 142.56 239.313 142.56C239.507 142.56 241.576 144.083 243.909 145.945C254.751 154.593 266.891 158.287 300.501 163.164C320.279 166.034 331.408 168.352 341.675 171.738C374.308 182.502 394.497 204.345 399.312 234.098C400.711 242.743 399.891 258.955 397.623 267.5C395.832 274.248 390.367 286.413 388.918 286.879C388.516 287.009 388.122 285.477 388.019 283.393C387.469 272.221 381.793 261.345 372.26 253.197C361.421 243.934 346.859 236.559 311.254 222.301Z",
        false to "M273.719 231.195C273.049 227.231 271.888 222.168 271.138 219.944L269.773 215.901L272.307 218.73C275.814 222.645 278.585 227.654 280.933 234.325C282.726 239.417 282.927 240.932 282.914 249.206C282.9 257.33 282.676 259.032 281.021 263.616C278.411 270.843 275.172 275.967 269.737 281.468C259.971 291.354 247.415 296.828 229.295 299.098C226.145 299.492 216.965 300.157 208.895 300.574C188.556 301.626 175.17 303.8 163.142 308C161.412 308.605 159.868 308.972 159.711 308.816C159.225 308.334 167.414 303.479 174.178 300.238C183.716 295.668 193.211 293.175 214.484 289.651C224.992 287.91 235.844 285.799 238.6 284.958C264.624 277.023 278.001 256.544 273.719 231.195Z",
        false to "M298.228 274.486C291.125 259.299 289.493 244.635 293.385 230.959C293.802 229.498 294.471 228.302 294.874 228.302C295.276 228.302 296.953 229.203 298.598 230.305C301.872 232.496 308.437 236.188 325.928 245.672C347.754 257.507 360.198 266.672 368.66 277.142C376.071 286.312 380.658 296.755 382.865 309.49C384.115 316.704 383.383 334.061 381.521 341.325C375.653 364.229 362.015 382.22 342.562 392.718C339.712 394.256 337.153 395.519 336.876 395.524C336.599 395.53 337.638 392.904 339.184 389.688C345.728 376.083 346.473 362.849 341.526 348.118C338.496 339.099 332.32 328.094 319.849 309.493C305.35 287.868 301.795 282.113 298.228 274.486Z",
        false to "M97.4084 356.432C117.249 339.771 141.935 327.934 164.422 324.301C174.113 322.735 190.257 323.357 199.231 325.641C213.616 329.302 226.484 337.503 233.176 347.273C239.716 356.823 242.522 365.144 245.443 383.659C246.596 390.962 247.849 398.296 248.228 399.957C250.422 409.552 254.691 417.222 259.982 421.074C268.385 427.191 282.854 427.571 297.087 422.049C299.503 421.111 301.6 420.464 301.748 420.61C302.264 421.12 295.097 425.892 290.04 428.404C283.237 431.784 277.827 433.09 270.638 433.09C257.602 433.09 246.779 426.495 237.748 413.046C235.971 410.399 231.976 402.471 228.871 395.429C219.336 373.799 214.628 367.21 203.556 359.998C193.922 353.723 181.496 352.599 172.148 357.158C159.87 363.146 156.444 378.752 165.238 388.642C168.733 392.573 175.251 395.964 180.581 396.623C190.552 397.856 199.121 390.312 199.121 380.299C199.121 373.798 196.609 370.088 190.284 367.249C181.646 363.372 172.36 367.904 172.405 375.975C172.424 379.417 173.931 381.578 177.4 383.139C179.625 384.14 179.677 384.22 177.862 383.845C169.936 382.21 168.079 372.707 174.452 366.398C182.103 358.824 197.924 362.166 203.357 372.504C205.64 376.847 205.905 385.495 203.915 390.717C199.461 402.405 186.475 408.552 173.302 405.207C164.333 402.93 160.681 400.464 149.867 389.386C131.077 370.135 123.782 366.405 96.6926 362.198L91.5016 361.393L97.4084 356.432Z",
        true to "M9.2415 11.8782C71.9927 87.6272 115.213 118.88 120.016 125.483C123.981 130.935 122.489 135.836 115.695 139.678C111.917 141.813 104.15 143.977 100.261 143.977C95.8623 143.977 94.3522 142.29 94.3522 142.29C91.8018 139.884 90.3654 140.305 77.2685 117.183C59.0858 89.1221 43.8693 65.8442 43.4542 65.4545C42.4943 64.5531 42.5108 64.5836 75.4146 123.138C80.7309 135.342 76.472 139.822 76.472 141.56C76.472 145.096 75.5021 146.955 71.1164 151.82C63.8053 159.933 60.537 169.047 58.1777 187.911C55.5328 209.058 48.0957 223.995 27.485 249.56C15.4202 264.526 13.446 267.269 10.4018 273.3C6.56722 280.896 5.51286 285.15 5.08553 294.742C4.63386 304.883 5.51354 311.434 8.62869 321.13C11.3559 329.619 14.2026 335.224 21.4801 346.435C27.7605 356.109 31.3768 363.299 31.3768 366.111C31.3768 368.349 31.8063 368.352 41.5383 366.166C64.8282 360.936 83.7395 351.736 94.3756 340.462C100.958 333.483 102.503 329.63 102.554 320.067C102.587 313.812 102.365 312.503 100.665 308.904C97.898 303.048 92.8603 298.178 81.7568 290.629C67.2082 280.737 60.9944 272.774 59.2779 261.822C57.8699 252.836 59.5033 246.496 67.5518 229.719C75.8822 212.353 77.9466 204.953 79.3431 187.449C80.245 176.141 81.4941 171.681 84.761 168.101C88.1682 164.368 91.2354 163.104 99.6675 161.958C113.414 160.09 122.168 156.552 129.363 149.958C135.605 144.238 138.217 138.725 138.618 130.427L138.922 124.138L135.434 120.093C122.802 105.445 0.782165 0.363281 0.00480791 0.363281C-0.161257 0.363281 3.99542 5.54535 9.2415 11.8782ZM38.4675 306.217C41.3235 301.186 39.8061 294.719 35.0288 291.56C30.515 288.574 23.503 289.98 23.503 293.87C23.503 295.057 24.163 295.921 25.6504 296.683C28.155 297.965 28.3368 299.406 26.3662 302.352C24.3705 305.335 24.5316 307.958 26.8207 309.741C30.5099 312.614 35.7324 311.034 38.4675 306.217Z",
        true to "M147.597 165.257C141.144 167.228 134.87 174.031 132.928 181.164C131.744 185.515 132.416 193.149 134.19 195.506C137.057 199.314 139.829 200.317 147.336 200.264C162.033 200.162 174.809 193.893 176.294 186.056C177.512 179.632 171.901 170.729 164.172 166.82C160.183 164.804 151.701 164.004 147.597 165.257ZM164.778 178.619C167.044 175.416 166.053 171.954 162.198 169.613C154.858 165.155 143.757 168.844 143.757 175.741C143.757 179.174 149.546 182.92 154.852 182.92C158.384 182.92 163.217 180.825 164.778 178.619Z"
        )
    }
}

/**
 * The trade panels' line glyphs, in the strip tools' own stroke (ToolIcon's
 * look), standing in for the SF Symbols iOS uses on the sponsor panels and
 * the trade panel: swap arrows, a target, up and down arrows, a falling
 * line, a clock with an arrow, a cursor, a list.
 */
class TradeGlyph(ctx: Context, private val kind: String, tint: Int) : View(ctx) {
    private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND; color = tint
    }
    var scale = 1f
    private fun dp(v: Float) = v * resources.displayMetrics.density * scale

    override fun onDraw(c: Canvas) {
        p.strokeWidth = dp(1.7f)
        val cx = width / 2f
        val cy = height / 2f
        fun line(x0: Float, y0: Float, x1: Float, y1: Float) = c.drawLine(cx + dp(x0), cy + dp(y0), cx + dp(x1), cy + dp(y1), p)
        fun head(x: Float, y: Float, dx: Float, dy: Float) {
            // An arrowhead at (x, y) pointing along (dx, dy).
            val len = Math.hypot(dx.toDouble(), dy.toDouble()).toFloat().coerceAtLeast(0.001f)
            val ux = dx / len; val uy = dy / len
            line(x, y, x - 3.2f * ux + 2.6f * uy, y - 3.2f * uy - 2.6f * ux)
            line(x, y, x - 3.2f * ux - 2.6f * uy, y - 3.2f * uy + 2.6f * ux)
        }
        when (kind) {
            "swaparrows" -> {
                line(-6.5f, -3f, 6.5f, -3f); head(6.5f, -3f, 1f, 0f)
                line(6.5f, 3f, -6.5f, 3f); head(-6.5f, 3f, -1f, 0f)
            }
            "scope" -> {
                c.drawCircle(cx, cy, dp(6.5f), p)
                c.drawCircle(cx, cy, dp(2.2f), p)
                line(0f, -8.5f, 0f, -5f); line(0f, 5f, 0f, 8.5f); line(-8.5f, 0f, -5f, 0f); line(5f, 0f, 8.5f, 0f)
            }
            "arrowupright" -> { line(-5f, 5f, 5f, -5f); line(5f, -5f, -1f, -5f); line(5f, -5f, 5f, 1f) }
            "arrowdownright" -> { line(-5f, -5f, 5f, 5f); line(5f, 5f, -1f, 5f); line(5f, 5f, 5f, -1f) }
            "updown" -> { line(0f, -7f, 0f, 7f); head(0f, -7f, 0f, -1f); head(0f, 7f, 0f, 1f) }
            "downtrend" -> {
                val path = Path().apply {
                    moveTo(cx - dp(7f), cy - dp(5f)); lineTo(cx - dp(2f), cy); lineTo(cx + dp(1f), cy - dp(2.5f))
                    lineTo(cx + dp(7f), cy + dp(4f))
                }
                c.drawPath(path, p)
                line(-7f, 7.5f, 7f, 7.5f)
            }
            "clockarrow" -> {
                c.drawArc(RectF(cx - dp(7f), cy - dp(7f), cx + dp(7f), cy + dp(7f)), -60f, 300f, false, p)
                head(3.5f, -6.06f, 0.87f, 0.5f)
                line(0f, -3.5f, 0f, 0f); line(0f, 0f, 2.8f, 1.8f)
            }
            "textcursor" -> { line(0f, -7f, 0f, 7f); line(-2.6f, -7f, 2.6f, -7f); line(-2.6f, 7f, 2.6f, 7f) }
            "list" -> {
                for (y in listOf(-5f, 0f, 5f)) { c.drawCircle(cx - dp(6f), cy + dp(y), dp(0.9f), p); line(-3f, y, 7f, y) }
            }
            "chevrondown" -> { line(-4f, -2f, 0f, 2f); line(0f, 2f, 4f, -2f) }
            else -> c.drawCircle(cx, cy, dp(6f), p)
        }
    }
}
