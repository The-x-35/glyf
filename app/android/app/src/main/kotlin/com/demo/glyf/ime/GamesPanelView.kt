package com.demo.glyf.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * g menu → Games: Snake and Chomp in the keyboard's panel, as on iOS. A
 * picker first, then the game over the panel: swipe to steer, tap to pause.
 * Best scores stay on this phone. The rules live in Games.kt.
 */
@SuppressLint("ViewConstructor")
class GamesPanelView(ctx: Context, private val palette: GlyfKeyboardView.KeyPalette) : FrameLayout(ctx) {

    private val prefs = ctx.getSharedPreferences("glyf", Context.MODE_PRIVATE)
    private val picker = LinearLayout(ctx)
    private val bar = LinearLayout(ctx)
    private val title = TextView(ctx)
    private val lives = TextView(ctx)
    private val score = TextView(ctx)
    private var board: GameBoardView? = null

    private fun dp(v: Float) = v * resources.displayMetrics.density
    private fun dpi(v: Int) = (v * resources.displayMetrics.density).toInt()

    init {
        picker.orientation = LinearLayout.HORIZONTAL
        picker.setPadding(dpi(12), dpi(12), dpi(12), dpi(12))
        for (game in listOf("snake", "chomp")) {
            picker.addView(card(game), LinearLayout.LayoutParams(0, LayoutParams.MATCH_PARENT, 1f).apply {
                if (game == "chomp") leftMargin = dpi(10)
            })
        }
        addView(picker, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        bar.orientation = LinearLayout.HORIZONTAL
        bar.gravity = Gravity.CENTER_VERTICAL
        bar.addView(TextView(ctx).apply {
            text = "‹"; textSize = 24f; setTextColor(palette.ink)
            gravity = Gravity.CENTER
            setTag(com.demo.glyf.R.id.qa_id, "games:back")
            contentDescription = "All games"
            setOnClickListener { showPicker() }
        }, LinearLayout.LayoutParams(dpi(40), LayoutParams.MATCH_PARENT))
        title.textSize = 15f
        title.typeface = Typeface.DEFAULT_BOLD
        title.setTextColor(palette.ink)
        bar.addView(title, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        lives.textSize = 12f
        lives.letterSpacing = 0.25f
        lives.setTextColor(GameBoardView.CHOMP_YELLOW)
        bar.addView(lives, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            rightMargin = dpi(12)
        })
        score.textSize = 14f
        score.setTextColor(Color.argb(170, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink)))
        score.setTag(com.demo.glyf.R.id.qa_id, "games:score")
        bar.addView(score, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            rightMargin = dpi(12)
        })
        addView(bar, LayoutParams(LayoutParams.MATCH_PARENT, dpi(32), Gravity.TOP))
        showPicker()
    }

    fun best(game: String) = prefs.getInt("games.best.$game", 0)

    private fun record(game: String, s: Int) {
        if (s > best(game)) prefs.edit().putInt("games.best.$game", s).apply()
    }

    /** The panel is going away: stop the clock. */
    fun stop() = board?.stop()

    private fun card(game: String): View = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            cornerRadius = dp(16f); setColor(palette.card)
        }
        setTag(com.demo.glyf.R.id.qa_id, "games:$game")
        contentDescription = if (game == "snake") "Snake" else "Chomp"
        addView(object : View(context) {
            override fun onDraw(c: Canvas) = GameBoardView.drawPreview(c, game, width.toFloat(), height.toFloat(), palette.ink)
        }, LinearLayout.LayoutParams(dpi(96), dpi(52)))
        addView(TextView(context).apply {
            text = if (game == "snake") "Snake" else "Chomp"
            textSize = 17f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(palette.ink); gravity = Gravity.CENTER
            setPadding(0, dpi(10), 0, 0)
        })
        addView(TextView(context).apply {
            tag = "best:$game"
            textSize = 13f; gravity = Gravity.CENTER
            setTextColor(Color.argb(150, Color.red(palette.ink), Color.green(palette.ink), Color.blue(palette.ink)))
        })
        setOnClickListener { play(game) }
    }

    private fun showPicker() {
        board?.stop()
        board?.let { removeView(it) }
        board = null
        for (game in listOf("snake", "chomp")) {
            picker.findViewWithTag<TextView>("best:$game")?.text = best(game).let { if (it > 0) "Best $it" else "New" }
        }
        picker.visibility = View.VISIBLE
        bar.visibility = View.GONE
    }

    private fun play(game: String) {
        picker.visibility = View.GONE
        bar.visibility = View.VISIBLE
        title.text = if (game == "snake") "Snake" else "Chomp"
        val b = GameBoardView(context, game, palette.ink, onChange = { refreshBar() }, onOver = { s -> record(game, s) })
        addView(b, 0, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply { topMargin = dpi(32) })
        board = b
        refreshBar()
    }

    private fun refreshBar() {
        val b = board ?: return
        val best = best(b.game)
        score.text = if (best > 0) "${b.score}  ·  Best ${max(best, b.score)}" else "${b.score}"
        score.contentDescription = "Score ${b.score}"
        lives.text = b.lives?.let { "●".repeat(max(0, it)) } ?: ""
    }
}

/** Draws either game, runs its clock and reads the swipes. Positions slide
 *  between cells over each tick, so a 140ms step still moves smoothly. */
@SuppressLint("ViewConstructor")
class GameBoardView(
    ctx: Context,
    val game: String,
    private val ink: Int,
    private val onChange: () -> Unit,
    private val onOver: (Int) -> Unit,
) : View(ctx) {

    companion object {
        val CHOMP_YELLOW = Color.rgb(255, 199, 61)
        val VIOLET = GlyfMark.VIOLET
        private val GHOSTS = intArrayOf(Color.rgb(255, 90, 95), Color.rgb(62, 199, 240), Color.rgb(255, 159, 67))
        private val SCARED = Color.rgb(71, 87, 255)
        private val FOOD = Color.rgb(255, 90, 95)
        private val LEAF = Color.rgb(52, 199, 89)
        private val DOOR = Color.rgb(255, 184, 222)

        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)

        fun drawGhost(c: Canvas, cx: Float, cy: Float, r: Float, color: Int, dir: Games.Dir, scared: Boolean) {
            val bottom = cy + r * 0.92f
            val path = Path().apply {
                moveTo(cx - r, bottom)
                lineTo(cx - r, cy)
                arcTo(RectF(cx - r, cy - r, cx + r, cy + r), 180f, 180f)
                lineTo(cx + r, bottom)
                // Three little feet along the hem.
                val step = r * 2 / 6
                for (k in 0 until 6) lineTo(cx + r - step * (k + 1), if (k % 2 == 0) bottom - r * 0.28f else bottom)
                close()
            }
            fill.color = color
            c.drawPath(path, fill)
            if (scared) {
                fill.color = Color.WHITE
                for (k in listOf(-1f, 1f)) c.drawCircle(cx + k * r * 0.34f, cy - r * 0.08f, r * 0.12f, fill)
                return
            }
            for (k in listOf(-1f, 1f)) {
                val ex = cx + k * r * 0.36f
                val ey = cy - r * 0.12f
                fill.color = Color.WHITE
                c.drawOval(RectF(ex - r * 0.26f, ey - r * 0.3f, ex + r * 0.26f, ey + r * 0.3f), fill)
                fill.color = Color.rgb(31, 36, 102)
                c.drawCircle(ex + dir.dx * r * 0.12f, ey + dir.dy * r * 0.14f, r * 0.13f, fill)
            }
        }

        fun drawChomper(c: Canvas, cx: Float, cy: Float, r: Float, facing: Float, mouth: Float) {
            fill.color = CHOMP_YELLOW
            val deg = Math.toDegrees(mouth.toDouble()).toFloat()
            c.drawArc(RectF(cx - r, cy - r, cx + r, cy + r), facing + deg / 2, 360f - deg, true, fill)
        }

        /** The picker's little picture of each game. */
        fun drawPreview(c: Canvas, game: String, w: Float, h: Float, ink: Int) {
            val d = w / 96f
            if (game == "snake") {
                val cells = listOf(1 to 3, 2 to 3, 3 to 3, 3 to 2, 4 to 2, 5 to 2)
                cells.forEachIndexed { i, (x, y) ->
                    val t = 0.45f * (1 - i.toFloat() / (cells.size - 1))
                    fill.color = mix(VIOLET, Color.WHITE, t)
                    c.drawRoundRect(RectF(x * 12 * d, (y * 12 - 8) * d, (x * 12 + 10) * d, (y * 12 + 2) * d), 3.5f * d, 3.5f * d, fill)
                }
                fill.color = FOOD
                c.drawOval(RectF(84 * d, 17 * d, 93 * d, 26 * d), fill)
            } else {
                val mid = h / 2
                fill.color = Color.argb(140, Color.red(ink), Color.green(ink), Color.blue(ink))
                for (k in 0 until 3) c.drawCircle((36 + k * 11) * d, mid, 2 * d, fill)
                drawChomper(c, 18 * d, mid, 13 * d, 180f, 0.8f)
                drawGhost(c, 78 * d, mid, 12 * d, GHOSTS[0], Games.Dir.LEFT, false)
            }
        }

        /** [a] moved [t] of the way to [b], opaque. */
        fun mix(a: Int, b: Int, t: Float): Int = Color.rgb(
            (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
            (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
            (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt())
    }

    enum class Phase { READY, PLAYING, PAUSED, OVER }

    private var snake: SnakeGame? = null
    private var chomp: ChompGame? = null
    var phase = Phase.READY
        private set
    val score: Int get() = snake?.score ?: chomp?.score ?: 0
    val lives: Int? get() = chomp?.lives

    private var running = false
    private var lastNanos = 0L
    private var carryMs = 0.0
    private var clock = 0.0
    private var downX = 0f
    private var downY = 0f
    private var anchorX = 0f
    private var anchorY = 0f
    private var moved = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val hintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT_BOLD
        textSize = 15 * resources.displayMetrics.scaledDensity
    }

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(now: Long) {
            if (!running) return
            val dt = min((now - lastNanos) / 1e6, 250.0)
            lastNanos = now
            clock += dt / 1000
            if (phase == Phase.PLAYING) advance(dt)
            invalidate()
            if (running) Choreographer.getInstance().postFrameCallback(this)
        }
    }

    init {
        setTag(com.demo.glyf.R.id.qa_id, "games:board")
        newGame()
    }

    private fun newGame() {
        if (game == "snake") snake = SnakeGame() else chomp = ChompGame()
        carryMs = 0.0
        phase = Phase.READY
        describe()
        onChange()
        invalidate()
    }

    private val intervalMs: Long get() = snake?.intervalMs ?: chomp?.intervalMs ?: 140L

    private fun advance(dt: Double) {
        carryMs += dt
        while (carryMs >= intervalMs) {
            carryMs -= intervalMs
            snake?.let {
                if (it.step() == SnakeGame.Event.ATE) onChange()
                if (it.over) { finish(); return }
            }
            chomp?.let {
                if (it.step().isNotEmpty()) onChange()
                if (it.over) { finish(); return }
            }
        }
        describe()
    }

    private fun start() {
        if (running) return
        running = true
        lastNanos = System.nanoTime()
        Choreographer.getInstance().postFrameCallback(frame)
    }

    fun stop() {
        running = false
        Choreographer.getInstance().removeFrameCallback(frame)
        if (phase == Phase.PLAYING) { phase = Phase.PAUSED; describe(); invalidate() }
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    private fun finish() {
        onOver(score)
        phase = Phase.OVER
        running = false
        describe()
        onChange()
        invalidate()
    }

    private fun describe() {
        val parts = mutableListOf(phase.name.lowercase(), "score $score")
        snake?.let { parts.add("heading ${it.heading.name.lowercase()}"); parts.add("length ${it.body.size}") }
        chomp?.let { parts.add("lives ${it.lives}"); parts.add("level ${it.level}") }
        contentDescription = parts.joinToString(", ")
    }

    // MARK: input

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x; downY = e.y; anchorX = e.x; anchorY = e.y; moved = false
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = e.x - anchorX
                val dy = e.y - anchorY
                // One turn per 14dp of travel, so a single drag can take a
                // corner and then another.
                if (max(abs(dx), abs(dy)) > 14 * resources.displayMetrics.density) {
                    moved = true
                    anchorX = e.x; anchorY = e.y
                    steer(if (abs(dx) > abs(dy)) (if (dx > 0) Games.Dir.RIGHT else Games.Dir.LEFT)
                          else (if (dy > 0) Games.Dir.DOWN else Games.Dir.UP))
                }
            }
            MotionEvent.ACTION_UP -> if (!moved) tapped()
        }
        return true
    }

    private fun tapped() {
        when (phase) {
            Phase.READY, Phase.PAUSED -> { phase = Phase.PLAYING; start() }
            Phase.PLAYING -> stop()
            Phase.OVER -> newGame()
        }
        describe()
        invalidate()
    }

    private fun steer(d: Games.Dir) {
        if (phase == Phase.OVER) return
        snake?.turn(d)
        chomp?.wanted = d
        if (phase != Phase.PLAYING) { phase = Phase.PLAYING; start() }
        describe()
    }

    // MARK: drawing

    private fun grid(cols: Int, rows: Int): Triple<Float, Float, Float> {
        val inset = 8 * resources.displayMetrics.density
        val cell = floor(min((width - inset * 2) / cols, (height - inset * 2) / rows))
        return Triple(cell, (width - cell * cols) / 2, (height - cell * rows) / 2)
    }

    override fun onDraw(c: Canvas) {
        val progress = if (phase == Phase.PLAYING) min(1.0, carryMs / intervalMs).toFloat() else 1f
        snake?.let { drawSnake(c, it) }
        chomp?.let { drawChomp(c, it, progress) }
        val hint = when (phase) {
            Phase.READY -> "Swipe to start"
            Phase.PAUSED -> "Paused. Tap to go on"
            Phase.OVER -> "Game over. Tap to play again"
            Phase.PLAYING -> null
        } ?: return
        val d = resources.displayMetrics.density
        hintPaint.color = ink
        val w = hintPaint.measureText(hint) + 32 * d
        val box = RectF(width / 2f - w / 2, height / 2f - 15 * d, width / 2f + w / 2, height / 2f + 15 * d)
        paint.color = if (Color.red(ink) > 128) Color.rgb(44, 44, 46) else Color.WHITE
        c.drawRoundRect(box, 14 * d, 14 * d, paint)
        c.drawText(hint, width / 2f, box.centerY() + hintPaint.textSize * 0.35f, hintPaint)
    }

    private fun drawSnake(c: Canvas, s: SnakeGame) {
        val (cell, ox, oy) = grid(s.cols, s.rows)
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(13, Color.red(ink), Color.green(ink), Color.blue(ink))
        c.drawRoundRect(RectF(ox - 3, oy - 3, ox + cell * s.cols + 3, oy + cell * s.rows + 3), 10f * resources.displayMetrics.density,
            10f * resources.displayMetrics.density, paint)
        fun cx(cl: Games.Cell) = ox + (cl.x + 0.5f) * cell
        fun cy(cl: Games.Cell) = oy + (cl.y + 0.5f) * cell
        // The apple: red, with a leaf.
        paint.color = FOOD
        c.drawCircle(cx(s.food), cy(s.food), cell * 0.34f, paint)
        paint.color = LEAF
        c.drawOval(RectF(cx(s.food), oy + s.food.y * cell + cell * 0.04f, cx(s.food) + cell * 0.28f, oy + s.food.y * cell + cell * 0.22f), paint)
        // One body, lightening towards the tail, broken where it wraps.
        val n = s.body.size
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = cell * 0.7f
        paint.strokeCap = Paint.Cap.ROUND
        for (i in n - 2 downTo 0) {
            val a = s.body[i]; val b = s.body[i + 1]
            if (abs(a.x - b.x) + abs(a.y - b.y) != 1) continue
            paint.color = mix(VIOLET, Color.WHITE, 0.45f * (i + 1) / max(n - 1, 1))
            c.drawLine(cx(b), cy(b), cx(a), cy(a), paint)
        }
        paint.style = Paint.Style.FILL
        paint.color = VIOLET
        val head = s.body[0]
        c.drawCircle(cx(head), cy(head), cell * 0.42f, paint)
        // Eyes, looking where it goes.
        paint.color = Color.WHITE
        val d = s.heading
        for (k in listOf(-1f, 1f)) {
            c.drawCircle(cx(head) + d.dx * cell * 0.16f - d.dy * k * cell * 0.2f,
                cy(head) + d.dy * cell * 0.16f + d.dx * k * cell * 0.2f, cell * 0.1f, paint)
        }
    }

    private fun drawChomp(c: Canvas, g: ChompGame, progress: Float) {
        val (cell, ox, oy) = grid(g.cols, g.rows)
        fun cx(cl: Games.Cell) = ox + (cl.x + 0.5f) * cell
        fun cy(cl: Games.Cell) = oy + (cl.y + 0.5f) * cell
        fun slide(from: Games.Cell, to: Games.Cell): Pair<Float, Float> {
            // Through the side tunnel: no slide across the whole maze.
            if (abs(from.x - to.x) > 1) return cx(to) to cy(to)
            return (cx(from) + (cx(to) - cx(from)) * progress) to (cy(from) + (cy(to) - cy(from)) * progress)
        }
        // Walls: rounded tubes joining neighbouring wall cells.
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = cell * 0.34f
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.argb(204, Color.red(VIOLET), Color.green(VIOLET), Color.blue(VIOLET))
        paint.strokeJoin = Paint.Join.ROUND
        // One path, one stroke: separate see-through segments darken where
        // they overlap and the tubes come out beaded.
        val tubes = Path()
        for (w in g.walls) {
            for (n in listOf(Games.Cell(w.x + 1, w.y), Games.Cell(w.x, w.y + 1))) {
                if (n in g.walls) { tubes.moveTo(cx(w), cy(w)); tubes.lineTo(cx(n), cy(n)) }
            }
        }
        c.drawPath(tubes, paint)
        // The pen's door.
        paint.strokeWidth = cell * 0.12f
        paint.strokeCap = Paint.Cap.BUTT
        paint.color = DOOR
        c.drawLine(cx(g.door) - cell / 2, cy(g.door), cx(g.door) + cell / 2, cy(g.door), paint)
        // Pellets, and the four that bite back, pulsing.
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(140, Color.red(ink), Color.green(ink), Color.blue(ink))
        for (p in g.pellets) c.drawCircle(cx(p), cy(p), cell * 0.1f, paint)
        paint.color = Color.argb(217, Color.red(ink), Color.green(ink), Color.blue(ink))
        val pulse = 0.75f + 0.25f * sin(clock * 6).toFloat()
        for (p in g.powers) c.drawCircle(cx(p), cy(p), cell * 0.24f * pulse, paint)
        // Ghosts.
        for (gh in g.ghosts) {
            val (x, y) = slide(gh.from, gh.at)
            val blink = g.frightened < 12 && (clock * 6).toInt() % 2 == 0
            val color = if (gh.scared) (if (blink) Color.WHITE else SCARED) else GHOSTS[gh.id % GHOSTS.size]
            drawGhost(c, x, y, cell * 0.44f, color, gh.dir, gh.scared)
        }
        // Chomp: the mouth works while it moves.
        val (px, py) = slide(g.playerFrom, g.player)
        val moving = phase == Phase.PLAYING && g.playerFrom != g.player
        val mouth = if (moving) ((0.5 + 0.5 * sin(clock * 22)) * 0.9).toFloat() else 0.55f
        val facing = when (g.heading) {
            Games.Dir.RIGHT -> 0f
            Games.Dir.DOWN -> 90f
            Games.Dir.LEFT -> 180f
            Games.Dir.UP -> 270f
        }
        drawChomper(c, px, py, cell * 0.46f, facing, mouth)
    }
}
