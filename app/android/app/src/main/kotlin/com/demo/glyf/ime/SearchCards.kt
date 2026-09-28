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

    private fun rounded(colour: Int, radiusPx: Int) = GradientDrawable().apply {
        cornerRadius = radiusPx.toFloat()
        setColor(colour)
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
            "query" -> queryCard(ctx, c, t)
            "answer" -> answerCard(ctx, c, t)
            "video" -> videoCard(ctx, c, t)
            "place" -> placeCard(ctx, c, t, backendURL)
            else -> linkCard(ctx, c, t)
        }
        v.isClickable = true
        v.setOnClickListener { onTap(c) }
        return v
    }

    private fun answerCard(ctx: Context, c: BackendClient.SearchCard, t: Theme): View {
        val painted = c.art == "sun" || c.art == "weather"
        val row = object : LinearLayout(ctx) {
            override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
                super.onSizeChanged(w, h, ow, oh)
                if (!painted || w == 0) return
                // The site's dusk gradient, left-bottom to right-top.
                background = GradientDrawable().apply {
                    cornerRadius = t.dp(15).toFloat()
                    colors = intArrayOf(
                        Color.rgb(47, 48, 71),
                        Color.rgb(107, 74, 124),
                        Color.rgb(201, 111, 106))
                    orientation = GradientDrawable.Orientation.BL_TR
                }
            }
        }.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(15), t.dp(12), t.dp(12), t.dp(12))
            background = rounded(if (painted) Color.rgb(47, 48, 71) else t.card, t.dp(15))
        }
        val fg = if (painted) Color.WHITE else t.ink
        val sub = if (painted) Color.argb(200, 255, 255, 255) else t.soft

        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        val long = (c.value ?: "").length > 12
        text.addView(TextView(ctx).apply {
            this.text = c.value ?: c.title
            textSize = if (long) 20f else 30f
            setTextColor(fg)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            maxLines = 1
        })
        (c.sub ?: c.source)?.let {
            text.addView(TextView(ctx).apply {
                this.text = it
                textSize = 12.5f
                setTextColor(sub)
                maxLines = if (c.art == "define") 3 else 2
                setPadding(0, t.dp(3), 0, 0)
            })
        }
        row.addView(text, LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        if (c.art == "sun") {
            row.addView(SunArcView(ctx),
                LinearLayout.LayoutParams(t.dp(96), t.dp(44)))
        }
        return row
    }

    /** A suggestion row: clock for the user's own history, trend arrow for
     *  what's popular — the two icons Gboard uses. */
    private fun queryCard(ctx: Context, c: BackendClient.SearchCard, t: Theme): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(12), t.dp(11), t.dp(12), t.dp(11))
            background = rounded(t.card, t.dp(15))
        }
        row.addView(TextView(ctx).apply {
            text = if (c.source == "recent") "\u2941" else "\u2197"
            textSize = 15f
            setTextColor(t.soft)
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(t.dp(28), t.dp(28)).apply { rightMargin = t.dp(10) })
        row.addView(TextView(ctx).apply {
            text = c.title
            textSize = 14.5f
            setTextColor(t.ink)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    private fun linkCard(ctx: Context, c: BackendClient.SearchCard, t: Theme): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(12), t.dp(10), t.dp(12), t.dp(10))
            background = rounded(t.card, t.dp(15))
        }
        val chip = ImageView(ctx).apply {
            background = rounded(Color.argb(36, 128, 128, 128), t.dp(10))
            scaleType = ImageView.ScaleType.CENTER_CROP
            setPadding(t.dp(8), t.dp(8), t.dp(8), t.dp(8))
        }
        if (!c.thumb.isNullOrEmpty()) {
            loadThumb(c.thumb, chip) { chip.setImageDrawable(GoogleMark()) }
        } else {
            chip.setImageDrawable(if (c.kind == "contact") PinMark() else GoogleMark())
            if (c.kind == "contact") chip.setImageDrawable(null)
        }
        row.addView(chip, LinearLayout.LayoutParams(t.dp(36), t.dp(36)).apply {
            rightMargin = t.dp(12)
        })
        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        text.addView(TextView(ctx).apply {
            this.text = c.title
            textSize = 14.5f
            setTextColor(t.ink)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        val detail = if (c.kind == "contact") c.snippet else (c.domain ?: c.snippet)
        if (!detail.isNullOrBlank()) text.addView(TextView(ctx).apply {
            this.text = detail
            textSize = 12.5f
            setTextColor(t.soft)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(0, t.dp(2), 0, 0)
        })
        row.addView(text, LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    private fun videoCard(ctx: Context, c: BackendClient.SearchCard, t: Theme): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(10), t.dp(9), t.dp(12), t.dp(9))
            background = rounded(t.card, t.dp(15))
        }
        // The badge overlaps the thumbnail's bottom-right, as on YouTube.
        val art = android.widget.FrameLayout(ctx)
        val thumb = ImageView(ctx).apply {
            // YouTube's policies forbid altering a thumbnail, so it is fitted
            // inside the frame rather than cropped to fill it.
            scaleType = ImageView.ScaleType.FIT_CENTER
            background = rounded(Color.argb(46, 128, 128, 128), t.dp(9))
            clipToOutline = true
            outlineProvider = roundOutline(t.dp(9))
        }
        art.addView(thumb, android.widget.FrameLayout.LayoutParams(t.dp(94), t.dp(54)))
        if (!c.thumb.isNullOrEmpty()) loadThumb(c.thumb, thumb)
        val badgeText = if (c.live) "LIVE" else c.duration
        if (!badgeText.isNullOrEmpty()) {
            art.addView(TextView(ctx).apply {
                text = badgeText
                textSize = 9.5f
                setTextColor(Color.WHITE)
                setPadding(t.dp(4), t.dp(1), t.dp(4), t.dp(1))
                background = rounded(
                    if (c.live) Color.rgb(255, 0, 51) else Color.argb(184, 0, 0, 0),
                    t.dp(4))
            }, android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                bottomMargin = t.dp(4); rightMargin = t.dp(4)
            })
        }
        row.addView(art, LinearLayout.LayoutParams(t.dp(94), t.dp(54)).apply {
            rightMargin = t.dp(12)
        })
        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        text.addView(TextView(ctx).apply {
            this.text = c.title
            textSize = 14f
            setTextColor(t.ink)
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        // YouTube requires its mark on EVERY card showing its content — a
        // single header attribution is explicitly not sufficient when results
        // from several sources share one surface.
        val byline = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, t.dp(3), 0, 0)
        }
        byline.addView(ImageView(ctx).apply {
            setImageDrawable(YouTubeMark())
        }, LinearLayout.LayoutParams(t.dp(14), t.dp(14)).apply { rightMargin = t.dp(5) })
        byline.addView(TextView(ctx).apply {
            this.text = c.channel ?: "YouTube"
            textSize = 12.5f
            setTextColor(t.soft)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        text.addView(byline)
        row.addView(text, LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    private fun placeCard(
        ctx: Context, c: BackendClient.SearchCard, t: Theme, backendURL: String,
    ): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(t.dp(10), t.dp(9), t.dp(12), t.dp(9))
            background = rounded(t.card, t.dp(15))
        }
        val art = ImageView(ctx).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = rounded(Color.rgb(232, 240, 233), t.dp(9))
            clipToOutline = true
            outlineProvider = roundOutline(t.dp(9))
            setImageDrawable(PinMark())
            setPadding(t.dp(24), t.dp(14), t.dp(24), t.dp(14))
        }
        val thumb = c.thumb
        if (!thumb.isNullOrEmpty()) {
            val own = !thumb.startsWith("http")
            val map = own && thumb.startsWith("/search/staticmap")
            // A place with no photo shows its map, drawn dark on a dark board,
            // cropped to the middle above the credit along its bottom (the
            // list credits the maps once). The pin stays until it comes.
            val url = if (own) backendURL + thumb + (if (map && t.dark) "&dark=1" else "") else thumb
            // Half of Geoapify's 600px is still more than the 74dp art
            // needs, and a quarter of the memory in the 3 MB cache.
            loadThumb(url, art, maxWidth = 320, signed = own,
                crop = if (map) android.graphics.RectF(0f, 0.14f, 1f, 0.84f) else null, keep = true,
                onLoaded = { art.setPadding(0, 0, 0, 0) })
        }
        row.addView(art, LinearLayout.LayoutParams(t.dp(74), t.dp(52)).apply {
            rightMargin = t.dp(12)
        })
        val text = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        text.addView(TextView(ctx).apply {
            this.text = c.title
            textSize = 14.5f
            setTextColor(t.ink)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        val bits = mutableListOf<String>()
        c.distance?.let { bits.add(it) }
        c.openNow?.let { bits.add(if (it) "Open" else "Closed") }
        c.rating?.let { r ->
            bits.add(if (c.ratingCount != null) "%.1f ★ (%d)".format(r, c.ratingCount)
                     else "%.1f ★".format(r))
        }
        if (bits.isEmpty()) c.address?.let { bits.add(it) }
        if (bits.isNotEmpty()) text.addView(TextView(ctx).apply {
            this.text = bits.joinToString(" · ")
            textSize = 12.5f
            setTextColor(t.soft)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(0, t.dp(2), 0, 0)
        })
        row.addView(text, LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return row
    }

    private fun roundOutline(radiusPx: Int) = object : android.view.ViewOutlineProvider() {
        override fun getOutline(view: View, outline: android.graphics.Outline) {
            outline.setRoundRect(0, 0, view.width, view.height, radiusPx.toFloat())
        }
    }
}
