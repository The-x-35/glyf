package com.arpit.glyf.ime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.view.View
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

/**
 * A token's logo in the trade panel, the twin of TradeSurface.swift's
 * TokenLogo: the picture Uniswap's token list names (GET /uniswap/tokens'
 * logoURI), fetched once, shrunk to 64 px and kept in a small cache; until
 * it comes, or when there is none, the token's first letter on a colour
 * picked from its symbol, the same each time. Only https pictures are
 * fetched, never with Glyf's session.
 */
object TokenLogo {

    /** iOS's six placeholder colours, in its order (opaque ARGB). */
    val placeholderColors = listOf(
        0xFF617DFA.toInt(), 0xFF299E8F.toInt(), 0xFFED7333.toInt(),
        0xFF9E5CDB.toInt(), 0xFFD94D78.toInt(), 0xFF338CD9.toInt(),
    )

    /** The placeholder's colour for [symbol]: the sum of its characters picks it. */
    fun placeholderColor(symbol: String): Int =
        placeholderColors[symbol.codePoints().toArray().sum() % placeholderColors.size]

    /** The placeholder's letter. */
    fun letter(symbol: String): String = symbol.take(1).uppercase(Locale.US)

    /** Only a picture on https is fetched (no ipfs://, no http://, nothing local). */
    fun usable(url: String?): Boolean = url != null && url.startsWith("https://") && url.length > 8

    /** A picture's sample size so its longer side comes to at least [side]
     *  pixels without decoding a big list image whole. */
    fun sampleSize(width: Int, height: Int, side: Int = 64): Int {
        var sample = 1
        while (maxOf(width, height) / (sample * 2) >= side) sample *= 2
        return sample
    }

    private val cache = object : LruCache<String, Bitmap>(512) {
        override fun sizeOf(key: String, value: Bitmap) = maxOf(1, value.byteCount / 1024)
    }
    private val waiting = mutableMapOf<String, MutableList<(Bitmap?) -> Unit>>()
    private val pool = Executors.newFixedThreadPool(3)
    private val main by lazy { Handler(Looper.getMainLooper()) }

    /** The picture at [url], on the main thread; null when there is none. */
    fun load(url: String?, done: (Bitmap?) -> Unit) {
        if (!usable(url)) { done(null); return }
        val key = url!!
        cache.get(key)?.let { done(it); return }
        waiting[key]?.let { it.add(done); return }
        waiting[key] = mutableListOf(done)
        pool.execute {
            val bmp = try {
                (URL(key).openConnection() as HttpURLConnection).run {
                    connectTimeout = 6000
                    readTimeout = 10000
                    try { inputStream.use { it.readBytes() } } finally { disconnect() }
                }.let { bytes ->
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
                        BitmapFactory.Options().apply { inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight) })
                    decoded?.let { if (it.width > 64 || it.height > 64) Bitmap.createScaledBitmap(it, 64, 64, true) else it }
                }
            } catch (_: Exception) { null }
            main.post {
                if (bmp != null) cache.put(key, bmp)
                waiting.remove(key)?.forEach { it(bmp) }
            }
        }
    }
}

/** A token's round logo: the placeholder letter until the picture lands. */
class TokenLogoView(ctx: Context, private val symbol: String, private val url: String?) : View(ctx) {
    private var bitmap: Bitmap? = null
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = TokenLogo.placeholderColor(symbol) }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        typeface = Typeface.DEFAULT_BOLD
        textAlign = Paint.Align.CENTER
    }
    private val image = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        TokenLogo.load(url) { b -> if (b != null) { bitmap = b; invalidate() } }
    }

    override fun onDraw(c: Canvas) {
        val d = minOf(width, height).toFloat()
        val cx = width / 2f
        val cy = height / 2f
        val b = bitmap
        if (b != null) {
            val shader = BitmapShader(b, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            val scale = d / minOf(b.width, b.height)
            shader.setLocalMatrix(Matrix().apply {
                setScale(scale, scale)
                postTranslate(cx - b.width * scale / 2, cy - b.height * scale / 2)
            })
            image.shader = shader
            c.drawCircle(cx, cy, d / 2, image)
            return
        }
        c.drawCircle(cx, cy, d / 2, fill)
        text.textSize = d * 0.47f
        c.drawText(TokenLogo.letter(symbol), cx, cy - (text.descent() + text.ascent()) / 2, text)
    }
}
