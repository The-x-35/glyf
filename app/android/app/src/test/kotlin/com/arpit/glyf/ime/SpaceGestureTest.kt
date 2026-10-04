package com.arpit.glyf.ime

import com.arpit.glyf.ime.SpaceGesture.Effect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors the space-gesture cases in RunnerTests/GlyfEngineTests.swift. */
class SpaceGestureTest {

    @Test fun tapTypesASpace() {
        val g = SpaceGesture(100f, 20f, 0)
        assertEquals(listOf(Effect.TypeSpace), g.ended(120))
    }

    @Test fun holdingStillLaunchesTheAiWithTheFingerDown() {
        val g = SpaceGesture(100f, 20f, 0)
        assertEquals(emptyList<Effect>(), g.moved(103f, 20f, 200))
        assertEquals(listOf(Effect.OpenBar), g.holdElapsed())
        // Moving after the launch never glides; lifting adds nothing.
        assertEquals(emptyList<Effect>(), g.moved(180f, 20f, 700))
        assertEquals(emptyList<Effect>(), g.ended(800))
    }

    @Test fun swipeGlidesTheCursor() {
        val g = SpaceGesture(100f, 20f, 0)
        assertEquals(listOf(Effect.BeginGlide), g.moved(112f, 20f, 40))
        val moves = g.moved(112f + 18f, 20f, 200) // slow: 1× gain, 18dp = 2 chars
        assertEquals(listOf(Effect.MoveCursor(2)), moves)
        assertEquals(listOf(Effect.EndGlide), g.ended(260))
    }

    @Test fun lateTimerStillLaunchesByTouchClock() {
        val g = SpaceGesture(100f, 20f, 0)
        // The timer never ran, but the lift arrives after HOLD_MS: that was a hold.
        assertEquals(listOf(Effect.OpenBar), g.ended(SpaceGesture.HOLD_MS + 40))
    }

    @Test fun slideOffCancelsOnlyWhileUndecided() {
        val g = SpaceGesture(100f, 20f, 0)
        assertTrue(g.isUndecided(100))
        g.holdElapsed()
        assertTrue(!g.isUndecided(100))
    }

    @Test fun fastFlicksCoverMoreText() {
        assertEquals(1f, SpaceGesture.gain(100f))
        assertEquals(2.6f, SpaceGesture.gain(5000f))
    }
}
