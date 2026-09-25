package com.demo.glyf.ime

/**
 * The keyboard's two games as plain rules: Snake, and Chomp (a maze of
 * pellets and ghosts after the arcade classic; the name is ours). Both move
 * one cell a tick on a grid sized to the keyboard's panel, so the views only
 * draw and the tests can play them. iOS's Engine/Games.swift is the same
 * rules, written twice: change one, change both.
 */
object Games {
    data class Cell(val x: Int, val y: Int)

    /** The order ties are broken in, as in the arcade: up, left, down, right. */
    enum class Dir(val dx: Int, val dy: Int) {
        UP(0, -1), LEFT(-1, 0), DOWN(0, 1), RIGHT(1, 0);

        val opposite: Dir get() = when (this) {
            UP -> DOWN
            DOWN -> UP
            LEFT -> RIGHT
            RIGHT -> LEFT
        }
    }

    /** A small seeded generator: the same numbers as iOS for a seed. */
    class Random(seed: Long) {
        private var state = seed
        fun next(n: Int): Int {
            state = state * 6364136223846793005L + 1442695040888963407L
            return if (n <= 1) 0 else ((state ushr 33) % n).toInt()
        }
    }

    fun seed(): Long = java.util.Random().nextLong() or 1L
}

class SnakeGame(
    val cols: Int = 22,
    val rows: Int = 11,
    seed: Long = Games.seed(),
    /** Head first, heading right; for tests. A game starts three long on the left. */
    body: List<Games.Cell>? = null,
) {
    enum class Event { MOVED, ATE, CRASHED, WON }

    val body: MutableList<Games.Cell> = body?.toMutableList()
        ?: (rows / 2).let { y -> mutableListOf(Games.Cell(5, y), Games.Cell(4, y), Games.Cell(3, y)) }
    var heading = Games.Dir.RIGHT
        private set
    var score = 0
        private set
    var over = false
        private set
    /** Swipes waiting for their step: two, so a quick up-then-left lands both. */
    private val turns = ArrayDeque<Games.Dir>()
    private val random = Games.Random(seed)
    var food: Games.Cell = placeFood()
        private set

    /** Where the head goes next; never straight back into the body. */
    fun turn(d: Games.Dir) {
        val last = turns.lastOrNull() ?: heading
        if (d == last || d == last.opposite || turns.size >= 2) return
        turns.addLast(d)
    }

    /** A step every 150ms, a little quicker every four bites, never under 70ms. */
    val intervalMs: Long get() = maxOf(70L, 150L - (score / 4) * 10L)

    fun step(): Event {
        if (over) return Event.CRASHED
        turns.removeFirstOrNull()?.let { heading = it }
        val head = body[0]
        // No walls: the board wraps, which is kinder on a keyboard-sized field.
        val next = Games.Cell((head.x + heading.dx + cols) % cols, (head.y + heading.dy + rows) % rows)
        val eats = next == food
        // The tail moves out of the way this step, unless the snake grows.
        val blocking = if (eats) body else body.subList(0, body.size - 1)
        if (next in blocking) {
            over = true
            return Event.CRASHED
        }
        body.add(0, next)
        if (!eats) {
            body.removeAt(body.size - 1)
            return Event.MOVED
        }
        score += 1
        if (body.size == cols * rows) {
            over = true
            return Event.WON
        }
        food = placeFood()
        return Event.ATE
    }

    private fun placeFood(): Games.Cell {
        val taken = body.toHashSet()
        var k = random.next(cols * rows - body.size)
        for (y in 0 until rows) for (x in 0 until cols) {
            val c = Games.Cell(x, y)
            if (c in taken) continue
            if (k == 0) return c
            k -= 1
        }
        return body[0]
    }
}

class ChompGame(seed: Long = Games.seed()) {
    sealed class Event {
        object Pellet : Event()
        object Power : Event()
        data class Ghost(val points: Int) : Event()
        object Caught : Event()
        object Cleared : Event()
        object Over : Event()
    }

    sealed class GhostState {
        /** In the pen; leaves after this many more ticks. */
        data class Home(val wait: Int) : GhostState()
        /** On its way out through the door. */
        object Leaving : GhostState()
        object Roaming : GhostState()
    }

    data class Ghost(
        val id: Int,
        var at: Games.Cell,
        /** Where it was a tick ago, so the view can slide it across. */
        var from: Games.Cell,
        var dir: Games.Dir = Games.Dir.UP,
        var state: GhostState,
        /** Blue and running: a power pellet was eaten while it was out. */
        var scared: Boolean = false,
    )

    companion object {
        /** 21 by 11, wide and short like the keyboard. # wall, . pellet,
         *  o power pellet, - the pen's door, G the pen, P where Chomp starts.
         *  The middle row runs off both edges and back on the other side. */
        val MAP = listOf(
            "#####################",
            "#o........#........o#",
            "#.###.###.#.###.###.#",
            "#...................#",
            "#.###.#.##-##.#.###.#",
            "......#.#GGG#.#......",
            "#.###.#.#####.#.###.#",
            "#.........P.........#",
            "#.###.###.#.###.###.#",
            "#o........#........o#",
            "#####################",
        )
    }

    val cols = 21
    val rows = 11
    val walls = HashSet<Games.Cell>()
    var door = Games.Cell(10, 4)
        private set
    val pen = ArrayList<Games.Cell>()
    var start = Games.Cell(10, 7)
        private set
    /** The first cell outside the door. */
    val exit: Games.Cell get() = Games.Cell(door.x, door.y - 1)

    val pellets = HashSet<Games.Cell>()
    val powers = HashSet<Games.Cell>()
    var player = start
        private set
    var playerFrom = start
        private set
    var heading = Games.Dir.LEFT
        private set
    /** The last swipe, kept until the maze lets Chomp take it. */
    var wanted: Games.Dir? = null
    val ghosts = ArrayList<Ghost>()
    var score = 0
        private set
    var lives = 3
        private set
    var level = 1
        private set
    /** Ticks left of the power pellet's fright. */
    var frightened = 0
        private set
    /** Ticks everything holds still after a catch or a cleared maze. */
    var pause = 0
        private set
    var over = false
        private set
    var tick = 0
        private set
    private var combo = 0
    private val random = Games.Random(seed)

    init {
        MAP.forEachIndexed { y, row ->
            row.forEachIndexed { x, ch ->
                val c = Games.Cell(x, y)
                when (ch) {
                    '#' -> walls.add(c)
                    '-' -> door = c
                    'G' -> pen.add(c)
                    'P' -> start = c
                }
            }
        }
        fillMaze()
        placeActors()
    }

    /** A step every 140ms on the first maze, quicker on each one after. */
    val intervalMs: Long get() = maxOf(110L, 140L - (level - 1) * 10L)
    private val frightTicks: Int get() = maxOf(20, 45 - (level - 1) * 5)

    fun next(c: Games.Cell, d: Games.Dir) =
        Games.Cell((c.x + d.dx + cols) % cols, (c.y + d.dy).coerceIn(0, rows - 1))

    /** Chomp and roaming ghosts keep to the corridors: not a wall, not the pen. */
    fun open(c: Games.Cell) = c !in walls && c != door && c !in pen

    fun step(): List<Event> {
        if (over) return emptyList()
        tick += 1
        playerFrom = player
        ghosts.forEach { it.from = it.at }
        if (pause > 0) {
            pause -= 1
            return emptyList()
        }
        val events = ArrayList<Event>()

        // Chomp: turn when the maze allows the last swipe, then run on.
        wanted?.let { w ->
            if (open(next(player, w))) {
                heading = w
                wanted = null
            }
        }
        val ahead = next(player, heading)
        if (open(ahead)) player = ahead
        if (pellets.remove(player)) {
            score += 10
            events.add(Event.Pellet)
        }
        if (powers.remove(player)) {
            score += 50
            frightened = frightTicks
            combo = 0
            // Every ghost that is out turns tail; the ones in the pen don't care.
            for (g in ghosts) {
                if (g.state is GhostState.Home) continue
                g.scared = true
                if (g.state == GhostState.Roaming) g.dir = g.dir.opposite
            }
            events.add(Event.Power)
        }
        if (collide(events)) return events

        ghosts.indices.forEach { moveGhost(it) }
        if (frightened > 0) {
            frightened -= 1
            if (frightened == 0) {
                combo = 0
                ghosts.forEach { it.scared = false }
            }
        }
        if (collide(events)) return events

        if (pellets.isEmpty() && powers.isEmpty()) {
            level += 1
            fillMaze()
            placeActors()
            pause = 12
            events.add(Event.Cleared)
        }
        return events
    }

    private fun moveGhost(i: Int) {
        val g = ghosts[i]
        when (val state = g.state) {
            is GhostState.Home -> g.state = if (state.wait > 0) GhostState.Home(state.wait - 1) else GhostState.Leaving
            GhostState.Leaving -> {
                // Along the pen to the door's column, then up and out.
                g.dir = when {
                    g.at.x < door.x -> Games.Dir.RIGHT
                    g.at.x > door.x -> Games.Dir.LEFT
                    else -> Games.Dir.UP
                }
                g.at = Games.Cell(g.at.x + g.dir.dx, g.at.y + g.dir.dy)
                if (g.at == exit) {
                    g.state = GhostState.Roaming
                    g.dir = if (random.next(2) == 0) Games.Dir.LEFT else Games.Dir.RIGHT
                }
            }
            GhostState.Roaming -> {
                // Scared ghosts go at half pace; the rest skip one tick in
                // five on the first maze, one in ten from the third.
                val skip = if (g.scared) tick % 2 == 0 else tick % (if (level >= 3) 10 else 5) == 0
                if (skip) return
                var options = Games.Dir.values().filter { it != g.dir.opposite && open(next(g.at, it)) }
                if (options.isEmpty()) options = listOf(g.dir.opposite)
                val dir = if (g.scared || (options.size > 1 && random.next(if (level >= 3) 10 else 6) == 0)) {
                    options[random.next(options.size)]
                } else {
                    val t = target(g)
                    options.minByOrNull { distance(next(g.at, it), t) }!!
                }
                g.dir = dir
                g.at = next(g.at, dir)
            }
        }
    }

    /** The first heads straight at Chomp, the second a few cells ahead of
     *  it, the third at it from afar and to its corner up close. */
    private fun target(g: Ghost): Games.Cell = when (g.id) {
        0 -> player
        1 -> Games.Cell(player.x + heading.dx * 3, player.y + heading.dy * 3)
        else -> if (distance(g.at, player) > 25) player else Games.Cell(0, rows - 1)
    }

    private fun distance(a: Games.Cell, b: Games.Cell) = (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)

    /** A ghost and Chomp on one cell, or passing through each other. True
     *  when Chomp was caught (the rest of the tick is off). */
    private fun collide(events: MutableList<Event>): Boolean {
        for (i in ghosts.indices) {
            val g = ghosts[i]
            if (g.state != GhostState.Roaming) continue
            val met = g.at == player || (g.at == playerFrom && g.from == player)
            if (!met) continue
            if (g.scared) {
                val points = 200 shl minOf(combo, 3)
                combo += 1
                score += points
                val home = pen[g.id % pen.size]
                ghosts[i] = Ghost(g.id, home, home, state = GhostState.Home(15))
                events.add(Event.Ghost(points))
                continue
            }
            lives -= 1
            events.add(Event.Caught)
            if (lives == 0) {
                over = true
                events.add(Event.Over)
            } else {
                placeActors()
                pause = 10
            }
            return true
        }
        return false
    }

    /** For tests: Chomp at [p], the first ghost out in the maze at [ghost]
     *  (the others kept in the pen), and optionally only [left] to eat. */
    fun stage(p: Games.Cell, h: Games.Dir, ghost: Games.Cell? = null,
              ghostDir: Games.Dir = Games.Dir.LEFT, left: Set<Games.Cell>? = null) {
        player = p
        playerFrom = p
        heading = h
        wanted = null
        pause = 0
        if (ghost != null) {
            ghosts[0].at = ghost
            ghosts[0].from = ghost
            ghosts[0].dir = ghostDir
            ghosts[0].state = GhostState.Roaming
        }
        for (i in 1 until ghosts.size) ghosts[i].state = GhostState.Home(1000)
        if (left != null) {
            pellets.clear(); pellets.addAll(left)
            powers.clear()
        }
    }

    private fun fillMaze() {
        pellets.clear()
        powers.clear()
        MAP.forEachIndexed { y, row ->
            row.forEachIndexed { x, ch ->
                if (ch == '.') pellets.add(Games.Cell(x, y))
                if (ch == 'o') powers.add(Games.Cell(x, y))
            }
        }
    }

    private fun placeActors() {
        player = start
        playerFrom = start
        heading = Games.Dir.LEFT
        wanted = null
        frightened = 0
        combo = 0
        ghosts.clear()
        pen.forEachIndexed { i, c -> ghosts.add(Ghost(i, c, c, state = GhostState.Home(i * 12))) }
    }
}
