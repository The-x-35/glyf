package com.demo.glyf.ime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.util.LruCache
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.net.URL
import java.util.concurrent.Executors

/**
 * Result cards for the search suite — the same four designs as the iOS
 * keyboard and tryglyf.com: an answer card with the sun arc, web links with an
 * icon chip, YouTube rows with a thumbnail and duration badge, and places with
 * distance / open-now / rating.
 *
 * Everything is drawn rather than shipped as assets, so the IME apk stays
 * small and the marks scale with the row.
 */
object SearchCards {

    // ── thumbnails ────────────────────────────────────────────────────────

    /** An IME is memory-constrained, so this stays deliberately small and is
     *  sized in kilobytes rather than entries. */
    private val cache = object : LruCache<String, Bitmap>(3 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount / 1024
    }
    /** Six at a time, as a browser fetches from one server: every card on
     *  screen gets its picture at once (a map takes Geoapify seconds to draw),
     *  where two at a time filled a list of nine over fifteen seconds. */
    private val pool = Executors.newFixedThreadPool(6)

    /** `maxWidth` caps decoded pixels: 320 for row thumbnails, wider for a
     *  full-width map. `signed`: the picture is our own server's (a place's
     *  photo, its map), behind the sign-in like every other call; nobody
     *  else ever gets the session. */
    fun loadThumb(url: String, into: ImageView, maxWidth: Int = 320, signed: Boolean = false,
                  crop: android.graphics.RectF? = null, keep: Boolean = false,
                  onLoaded: (() -> Unit)? = null, onMiss: (() -> Unit)? = null) {
        into.tag = url
        cache.get(url)?.let { into.setImageBitmap(it); onLoaded?.invoke(); return }
        // `keep`: whatever is showing (a pin) stays until the picture comes.
        if (!keep) into.setImageBitmap(null)
        pool.execute {
            val bmp = try {
                (URL(url).openConnection() as java.net.HttpURLConnection).apply {
                    connectTimeout = 6000
                    readTimeout = 8000
                    if (signed) BackendClient.bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
                }.inputStream.use { stream ->
                    // Decode bounds first so a 1280x720 thumbnail never
                    // becomes 3.6MB of live pixels for a 94dp row.
                    val bytes = stream.readBytes()
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    var sample = 1
                    while (bounds.outWidth / sample > maxWidth) sample *= 2
                    val full = BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
                        BitmapFactory.Options().apply { inSampleSize = sample })
                    // Part of the picture: a map's middle, above the credit
                    // printed along its bottom.
                    if (full != null && crop != null) {
                        val x = (crop.left * full.width).toInt()
                        val y = (crop.top * full.height).toInt()
                        val w = (crop.width() * full.width).toInt().coerceAtMost(full.width - x)
                        val h = (crop.height() * full.height).toInt().coerceAtMost(full.height - y)
                        if (w > 0 && h > 0) android.graphics.Bitmap.createBitmap(full, x, y, w, h) else full
                    } else full
                }
            } catch (_: Exception) { null }
            into.post {
                if (into.tag != url) return@post           // row was recycled
                if (bmp != null) {
                    cache.put(url, bmp)
                    into.setImageBitmap(bmp)
                    onLoaded?.invoke()
                } else onMiss?.invoke()
            }
        }
    }

    // ── brand marks ───────────────────────────────────────────────────────

    class GoogleMark : Drawable() {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun draw(canvas: Canvas) {
            val b = bounds
            val r = minOf(b.width(), b.height()) * 0.38f
            val cx = b.exactCenterX(); val cy = b.exactCenterY()
            p.strokeWidth = r * 0.62f
            val oval = RectF(cx - r, cy - r, cx + r, cy + r)
            val arcs = listOf(
                Color.rgb(66, 133, 244) to (-17f to 31f),
                Color.rgb(52, 168, 83) to (31f to 77f),
                Color.rgb(251, 188, 5) to (77f to 123f),
                Color.rgb(234, 67, 53) to (123f to 169f))
            for ((colour, span) in arcs) {
                p.color = colour
                canvas.drawArc(oval, span.first, span.second - span.first, false, p)
            }
            fill.color = Color.rgb(66, 133, 244)
            canvas.drawRect(cx, cy - r * 0.26f, cx + r * 1.2f, cy + r * 0.26f, fill)
        }
        override fun setAlpha(alpha: Int) {}
        override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
        @Deprecated("deprecated in API 29")
        override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    class YouTubeMark : Drawable() {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun draw(canvas: Canvas) {
            val b = bounds
            val h = b.height() * 0.68f
            val box = RectF(b.left.toFloat(), b.exactCenterY() - h / 2,
                b.right.toFloat(), b.exactCenterY() + h / 2)
            p.color = Color.rgb(255, 0, 51)
            canvas.drawRoundRect(box, box.width() * 0.22f, box.width() * 0.22f, p)
            p.color = Color.WHITE
            val tri = Path().apply {
                moveTo(box.left + box.width() * 0.38f, box.top + box.height() * 0.26f)
                lineTo(box.left + box.width() * 0.38f, box.bottom - box.height() * 0.26f)
                lineTo(box.left + box.width() * 0.66f, box.centerY())
                close()
            }
            canvas.drawPath(tri, p)
        }
        override fun setAlpha(alpha: Int) {}
        override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
        @Deprecated("deprecated in API 29")
        override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    class PinMark : Drawable() {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun draw(canvas: Canvas) {
            val b = bounds
            val w = b.width().toFloat(); val h = b.height().toFloat()
            p.color = Color.rgb(234, 67, 53)
            val head = RectF(b.left + w * 0.16f, b.top + h * 0.04f,
                b.left + w * 0.84f, b.top + h * 0.72f)
            canvas.drawOval(head, p)
            val tail = Path().apply {
                moveTo(b.left + w * 0.28f, b.top + h * 0.55f)
                lineTo(b.exactCenterX(), b.top + h * 0.98f)
                lineTo(b.left + w * 0.72f, b.top + h * 0.55f)
                close()
            }
            canvas.drawPath(tail, p)
            p.color = Color.WHITE
            canvas.drawCircle(b.exactCenterX(), b.top + h * 0.37f, w * 0.14f, p)
        }
        override fun setAlpha(alpha: Int) {}
        override fun setColorFilter(cf: android.graphics.ColorFilter?) {}
        @Deprecated("deprecated in API 29")
        override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    /** The dashed arc with the sun on it, from the site's answer card. */
    class SunArcView(context: Context) : View(context) {
        private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.argb(140, 255, 255, 255)
            pathEffect = DashPathEffect(floatArrayOf(4f, 7f), 0f)
        }
        private val sun = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(255, 211, 110)
        }
        override fun onDraw(canvas: Canvas) {
            if (width < 40) return
            line.strokeWidth = height * 0.05f
            val path = Path().apply {
                moveTo(width * 0.04f, height * 0.92f)
                quadTo(width * 0.5f, -height * 0.34f, width * 0.96f, height * 0.92f)
            }
            canvas.drawPath(path, line)
            canvas.drawCircle(width * 0.74f, height * 0.30f, height * 0.13f, sun)
        }
    }

    // ── card construction ─────────────────────────────────────────────────

    class Theme(
        val ink: Int,
        val card: Int,
        val soft: Int,
        val dp: (Int) -> Int,
        /** A dark board: a place's map is drawn dark to match. */
        val dark: Boolean = false,
    )

    /** iOS's row heights less the 4dp above and below each card. */
    fun height(kind: String): Int = when (kind) {
        "query" -> 50
        "answer" -> 96
        "video" -> 74
        "place" -> 70
        else -> 58
    }

    private fun rounded(colour: Int, radiusPx: Int) = GradientDrawable().apply {
        cornerRadius = radiusPx.toFloat()
        setColor(colour)
    }

    /** The site's .ss-card, as iOS draws it: the key colour, 15 corners, a
     *  1pt hairline border. */
    private fun cardFace(ctx: Context, t: Theme) = GradientDrawable().apply {
        cornerRadius = t.dp(15).toFloat()
        setColor(t.card)
        setStroke(maxOf(1, t.dp(1)), Glass.strokeHairline)
    }

    private fun label(ctx: Context, text: String?, size: Float, weight: Int, color: Int, lines: Int = 1) =
        TextView(ctx).apply {
            this.text = text
            Glass.style(this, size, weight, color)
            maxLines = lines
            ellipsize = android.text.TextUtils.TruncateAt.END
        }

    /** Builds the right view for a card's `kind`. */
    fun view(
        ctx: Context,
        c: BackendClient.SearchCard,
        t: Theme,
        backendURL: String,
        onTap: (BackendClient.SearchCard) -> Unit,
    ): View {
        val v = when (c.kind) {
            "answer" -> answerCard(ctx, c, t)
            "video" -> videoCard(ctx, c, t)
            "place" -> placeCard(ctx, c, t, backendURL)
            else -> linkCard(ctx, c, t)
        }
        v.isClickable = true
        v.setOnClickListener { onTap(c) }
        return v
    }

    /** The big answer. Sun and weather get the site's dusk gradient; the
     *  rest stay on the card so they read as text, not as a banner. */
    private fun answerCard(ctx: Context, c: BackendClient.SearchCard, t: Theme): View {
        val painted = c.art == "sun" || c.art == "weather"
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            setPadding(t.dp(15), t.dp(14), t.dp(14), t.dp(8))
            background = if (painted) GradientDrawable(GradientDrawable.Orientation.BL_TR, intArrayOf(
                Color.rgb(47, 48, 71), Color.rgb(107, 74, 124), Color.rgb(201, 111, 106))).apply {
                cornerRadius = t.dp(15).toFloat()
            } else cardFace(ctx, t)
            clipToOutline = true
        }
        val fg = if (painted) Color.WHITE else t.ink
        val sub = if (painted) Color.argb(199, 255, 255, 255) else t.soft
        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        // A definition's headline is the word; a time or a temperature is big.
        val long = (c.value ?: "").length > 12
        text.addView(label(ctx, c.value ?: c.title, if (long) 22f else 34f, Glass.BOLD, fg).apply {
            setAutoSizeTextTypeUniformWithConfiguration(14, if (long) 22 else 34, 1, android.util.TypedValue.COMPLEX_UNIT_DIP)
            gravity = Gravity.CENTER_VERTICAL
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, t.dp(40)))
        (c.sub ?: c.source)?.let {
            text.addView(label(ctx, it, 12.5f, Glass.REGULAR, sub, if (c.art == "define") 3 else 2),
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = t.dp(2) })
        }
        row.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        if (c.art == "sun") {
            row.addView(SunArcView(ctx), LinearLayout.LayoutParams(t.dp(130), t.dp(48)).apply {
                topMargin = t.dp(10)
            })
        }
        return row
    }

    /** A web result, a suggestion or a contact: a 36dp chip (the page's
     *  picture, or a grey mark), the title over its detail. */
    private fun linkCard(ctx: Context, c: BackendClient.SearchCard, t: Theme): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(12), 0, t.dp(14), 0)
            background = cardFace(ctx, t)
        }
        val glyph = when (c.kind) {
            "contact" -> if (c.url.contains("@")) "envelope" else "phone"
            "query" -> if (c.source == "recent") "clock" else "trend"
            else -> "search"
        }
        val chip = android.widget.FrameLayout(ctx).apply {
            background = rounded(Color.argb(36, 128, 128, 128), t.dp(10))
            clipToOutline = true
        }
        val mark = ToolIcon(ctx, glyph, t.soft).apply { solid = true; weight = 1.7f; scale = 0.85f }
        chip.addView(mark, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT, android.widget.FrameLayout.LayoutParams.MATCH_PARENT))
        if (!c.thumb.isNullOrEmpty()) {
            val pic = ImageView(ctx).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
            chip.addView(pic, android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT, android.widget.FrameLayout.LayoutParams.MATCH_PARENT))
            loadThumb(c.thumb, pic, maxWidth = 120, onLoaded = { mark.visibility = View.GONE })
        }
        row.addView(chip, LinearLayout.LayoutParams(t.dp(36), t.dp(36)).apply { rightMargin = t.dp(12) })
        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        text.addView(label(ctx, c.title, 14.5f, Glass.MEDIUM, t.ink))
        val detail = when (c.kind) {
            "contact" -> c.snippet
            "query" -> null   // a suggestion is one line
            else -> c.domain ?: c.snippet
        }
        if (!detail.isNullOrBlank()) text.addView(label(ctx, detail, 12.5f, Glass.REGULAR, t.soft),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = t.dp(3) })
        row.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    /** A YouTube result: its thumbnail fitted (never cropped: YouTube's
     *  rule) with a duration badge, the title over the channel, and
     *  YouTube's mark on every card. */
    private fun videoCard(ctx: Context, c: BackendClient.SearchCard, t: Theme): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(10), 0, t.dp(12), 0)
            background = cardFace(ctx, t)
        }
        val art = android.widget.FrameLayout(ctx)
        val thumb = ImageView(ctx).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            background = rounded(Color.argb(46, 128, 128, 128), t.dp(9))
            clipToOutline = true
            outlineProvider = roundOutline(t.dp(9))
        }
        art.addView(thumb, android.widget.FrameLayout.LayoutParams(t.dp(94), t.dp(54)))
        val play = PlayMark(ctx).apply { visibility = View.GONE }
        art.addView(play, android.widget.FrameLayout.LayoutParams(t.dp(94), t.dp(54)))
        if (!c.thumb.isNullOrEmpty()) loadThumb(c.thumb, thumb, onLoaded = { play.visibility = View.VISIBLE })
        val badgeText = if (c.live) "LIVE" else c.duration
        if (!badgeText.isNullOrEmpty()) {
            art.addView(TextView(ctx).apply {
                text = badgeText
                Glass.style(this, 10f, Glass.SEMIBOLD, Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(t.dp(4), 0, t.dp(4), 0)
                background = rounded(
                    if (c.live) Color.argb(242, 255, 0, 51) else Color.argb(184, 0, 0, 0), t.dp(4))
            }, android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT, t.dp(14)).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                bottomMargin = t.dp(4); rightMargin = t.dp(5)
            })
        }
        row.addView(art, LinearLayout.LayoutParams(t.dp(94), t.dp(54)).apply { rightMargin = t.dp(12) })
        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        text.addView(label(ctx, c.title, 14f, Glass.MEDIUM, t.ink, 2))
        val byline = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        byline.addView(ImageView(ctx).apply { setImageDrawable(YouTubeMark()) },
            LinearLayout.LayoutParams(t.dp(13), t.dp(13)).apply { rightMargin = t.dp(5) })
        byline.addView(label(ctx, c.channel ?: "YouTube", 12.5f, Glass.REGULAR, t.soft))
        text.addView(byline, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = t.dp(4) })
        row.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    /** iOS's play.circle.fill over a loaded thumbnail. */
    private class PlayMark(ctx: Context) : View(ctx) {
        private val disc = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(235, 255, 255, 255) }
        private val tri = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(200, 0, 0, 0) }
        override fun onDraw(c: Canvas) {
            val d = resources.displayMetrics.density
            val cx = width / 2f; val cy = height / 2f
            c.drawCircle(cx, cy, 11f * d, disc)
            val p = Path().apply {
                moveTo(cx - 3.2f * d, cy - 5f * d); lineTo(cx - 3.2f * d, cy + 5f * d)
                lineTo(cx + 5f * d, cy); close()
            }
            c.drawPath(p, tri)
        }
    }

    /** A Maps result: its photo (or a drawn map, the pin holding the corner
     *  until it comes), the name, then distance · open · rating. */
    private fun placeCard(
        ctx: Context, c: BackendClient.SearchCard, t: Theme, backendURL: String,
    ): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(10), 0, t.dp(12), 0)
            background = cardFace(ctx, t)
        }
        val art = ImageView(ctx).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = rounded(Color.rgb(232, 240, 233), t.dp(9))
            clipToOutline = true
            outlineProvider = roundOutline(t.dp(9))
            setImageDrawable(PinMark())
            setPadding(t.dp(26), t.dp(15), t.dp(26), t.dp(15))
        }
        val thumb = c.thumb
        if (!thumb.isNullOrEmpty()) {
            val own = !thumb.startsWith("http")
            val map = own && thumb.startsWith("/search/staticmap")
            val url = if (own) backendURL + thumb + (if (map && t.dark) "&dark=1" else "") else thumb
            loadThumb(url, art, maxWidth = 320, signed = own,
                crop = if (map) android.graphics.RectF(0f, 0.14f, 1f, 0.84f) else null, keep = true,
                onLoaded = { art.setPadding(0, 0, 0, 0) })
        }
        row.addView(art, LinearLayout.LayoutParams(t.dp(74), t.dp(52)).apply { rightMargin = t.dp(12) })
        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        text.addView(label(ctx, c.title, 14.5f, Glass.MEDIUM, t.ink))
        val bits = mutableListOf<String>()
        c.distance?.let { bits.add(it) }
        c.openNow?.let { bits.add(if (it) "Open" else "Closed") }
        c.rating?.let { r ->
            bits.add(if (c.ratingCount != null) "%.1f ★ (%d)".format(r, c.ratingCount)
                     else "%.1f ★".format(r))
        }
        if (bits.isEmpty()) c.address?.let { bits.add(it) }
        if (bits.isNotEmpty()) text.addView(label(ctx, bits.joinToString(" · "), 12.5f, Glass.REGULAR, t.soft),
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = t.dp(3) })
        row.addView(text, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    private fun roundOutline(radiusPx: Int) = object : android.view.ViewOutlineProvider() {
        override fun getOutline(view: View, outline: android.graphics.Outline) {
            outline.setRoundRect(0, 0, view.width, view.height, radiusPx.toFloat())
        }
    }
}
