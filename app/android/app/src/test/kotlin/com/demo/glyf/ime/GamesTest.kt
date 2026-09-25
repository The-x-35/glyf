package com.demo.glyf.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same games as iOS's GlyfEngineTests: both keyboards must agree. */
class GamesTest {
    private fun c(x: Int, y: Int) = Games.Cell(x, y)

    @Test fun snakeTurnsWrapsAndNeverDoublesBack() {
        val game = SnakeGame(10, 5, seed = 7L)
        assertEquals(c(1, 2), game.food)                 // the same seeded food as iOS
        assertEquals(c(5, 2), game.body.first())
        game.step()
        assertEquals(c(6, 2), game.body.first())
        game.turn(Games.Dir.LEFT)                         // straight back: ignored
        game.turn(Games.Dir.UP)
        game.step()
        assertEquals(c(6, 1), game.body.first())
        game.step(); game.step()
        assertEquals("off the top, in at the bottom", c(6, 4), game.body.first())
        assertEquals(3, game.body.size)
    }

    @Test fun snakeGrowsWhenItEatsAndFoodNeverLandsOnIt() {
        val game = SnakeGame(12, 6, seed = 3L)
        var steps = 0
        while (game.score < 3 && steps < 400) {
            val head = game.body[0]; val food = game.food
            if (head.x != food.x) game.turn(if (food.x > head.x) Games.Dir.RIGHT else Games.Dir.LEFT)
            else if (head.y != food.y) game.turn(if (food.y > head.y) Games.Dir.DOWN else Games.Dir.UP)
            assertFalse(food in game.body)
            if (game.step() == SnakeGame.Event.CRASHED) break
            steps++
        }
        assertEquals(3, game.score)
        assertEquals(6, game.body.size)
    }

    @Test fun snakeEndsWhenItRunsIntoItself() {
        val game = SnakeGame(12, 6, seed = 1L, body = (0 until 6).map { c(6 - it, 3) })
        game.turn(Games.Dir.UP); game.step()
        game.turn(Games.Dir.LEFT); game.step()
        game.turn(Games.Dir.DOWN)
        assertEquals(SnakeGame.Event.CRASHED, game.step())
        assertTrue(game.over)
    }

    @Test fun chompMazeIsOneWholeMaze() {
        val game = ChompGame(seed = 1L)
        assertEquals(107, game.pellets.size)
        assertEquals(4, game.powers.size)
        val seen = hashSetOf(game.start)
        val queue = ArrayDeque(listOf(game.start))
        while (queue.isNotEmpty()) {
            val cell = queue.removeLast()
            for (d in Games.Dir.values()) {
                val n = game.next(cell, d)
                if (game.open(n) && seen.add(n)) queue.addLast(n)
            }
        }
        assertTrue(seen.containsAll(game.pellets))
        assertTrue(seen.containsAll(game.powers))
    }

    @Test fun chompEatsAsItRunsAndTurnsWhenTheMazeLetsIt() {
        val game = ChompGame(seed = 1L)
        game.wanted = Games.Dir.UP                        // a wall above the start: kept for later
        repeat(3) { game.step() }
        assertEquals(c(7, 7), game.player)
        assertEquals(30, game.score)
        game.step()
        assertEquals("turned up at the first opening", c(7, 6), game.player)
        assertEquals(Games.Dir.UP, game.heading)
    }

    @Test fun ghostsLeaveThePenThroughTheDoor() {
        val game = ChompGame(seed = 1L)
        var through = false
        repeat(6) {
            game.step()
            if (game.ghosts[0].at == game.door) through = true
        }
        assertTrue(through)
        assertEquals(ChompGame.GhostState.Roaming, game.ghosts[0].state)
        assertFalse("Chomp can't go in", game.open(game.door))
    }

    @Test fun aPowerPelletMakesGhostsEdible() {
        val game = ChompGame(seed = 1L)
        game.stage(c(2, 1), Games.Dir.LEFT, ghost = c(8, 1))
        assertEquals(listOf(ChompGame.Event.Power), game.step())
        assertTrue(game.ghosts[0].scared)
        assertTrue(game.frightened > 0)
        game.stage(c(1, 1), Games.Dir.RIGHT, ghost = c(2, 1))
        val events = game.step()
        assertTrue(events.contains(ChompGame.Event.Ghost(200)))
        assertEquals(50 + 10 + 200, game.score)
        assertEquals("an eaten ghost is back in the pen", game.pen[0], game.ghosts[0].at)
        assertTrue(game.ghosts[0].state is ChompGame.GhostState.Home)
    }

    @Test fun aGhostCostsALifeAndClearingTheMazeStartsTheNext() {
        val game = ChompGame(seed = 1L)
        game.stage(c(5, 3), Games.Dir.RIGHT, ghost = c(6, 3), ghostDir = Games.Dir.LEFT)
        assertTrue(game.step().contains(ChompGame.Event.Caught))
        assertEquals(2, game.lives)
        assertEquals(game.start, game.player)
        assertTrue(game.pause > 0)
        game.stage(c(2, 3), Games.Dir.LEFT, left = setOf(c(1, 3)))
        assertEquals(listOf(ChompGame.Event.Pellet, ChompGame.Event.Cleared), game.step())
        assertEquals(2, game.level)
        assertEquals(107, game.pellets.size)
        assertTrue(game.intervalMs < 140)
    }
}
