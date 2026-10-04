package com.arpit.glyf.ime

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * The space bar's three gestures on one key — the Android mirror of
 * Engine/SpaceGesture.swift (unit-tested there). Keep thresholds and
 * outcomes identical on both platforms:
 *
 *  · tap                                  → a space
 *  · glide at any point while holding     → the cursor follows the finger
 *    (Gboard's straight swipe, Apple's press-pause-glide)
 *  · hold still for HOLD_MS               → the AI launches right then,
 *                                           finger still down
 *
 * Nothing waits for the lift. Once the AI has launched, later movement is
 * ignored. Distances are in dp, times in ms.
 */
class SpaceGesture(val startX: Float, val startY: Float, private val startTime: Long) {

    enum class Phase { PENDING, GLIDING, LAUNCHED, FINISHED }

    sealed interface Effect {
        data object BeginGlide : Effect
        data class MoveCursor(val graphemes: Int) : Effect
        data object EndGlide : Effect
        data object OpenBar : Effect
        data object TypeSpace : Effect
    }

    companion object {
        /** Still this long with no glide → the AI launches. The platform
         *  long-press length; the space key's charge ring fills over it. */
        const val HOLD_MS = 500L
        const val SWIPE_SLOP = 10f
        const val DP_PER_CHARACTER = 9f

        /** 1× at 250dp/s ramping to 2.6× at 1050dp/s: slow drags stay exact. */
        fun gain(speedDpPerSecond: Float): Float =
            1f + min(max((speedDpPerSecond - 250f) / 500f, 0f), 1.6f)
    }

    var phase = Phase.PENDING
        private set
    private var lastX = startX
    private var lastTime = startTime
    private var accumulated = 0f

    /** Not yet gliding and not yet held long enough, by the touch clock —
     *  the only state in which sliding off the bar cancels the key. */
    fun isUndecided(timeMs: Long): Boolean =
        phase == Phase.PENDING && timeMs - startTime < HOLD_MS

    /** The hold timer fired with the finger still down and unmoved. */
    fun holdElapsed(): List<Effect> {
        if (phase != Phase.PENDING) return emptyList()
        phase = Phase.LAUNCHED
        return listOf(Effect.OpenBar)
    }

    /** Decided by the touches' own timestamps, not the timer alone: on a busy
     *  main thread a move or the lift can arrive before a late timer runs. */
    private fun catchUp(timeMs: Long): List<Effect> =
        if (phase == Phase.PENDING && timeMs - startTime >= HOLD_MS) holdElapsed() else emptyList()

    fun moved(x: Float, @Suppress("UNUSED_PARAMETER") y: Float, timeMs: Long): List<Effect> {
        val launch = catchUp(timeMs)
        return when (phase) {
            Phase.PENDING ->
                if (abs(x - startX) > SWIPE_SLOP) {
                    phase = Phase.GLIDING
                    lastX = x
                    lastTime = timeMs
                    accumulated = 0f
                    listOf(Effect.BeginGlide)
                } else emptyList()
            Phase.GLIDING -> {
                val dx = x - lastX
                val dt = max(timeMs - lastTime, 1L) / 1000f
                lastX = x
                lastTime = timeMs
                accumulated += dx * gain(abs(dx) / dt)
                val steps = (accumulated / DP_PER_CHARACTER).toInt()
                if (steps == 0) emptyList() else {
                    accumulated -= steps * DP_PER_CHARACTER
                    listOf(Effect.MoveCursor(steps))
                }
            }
            Phase.LAUNCHED, Phase.FINISHED -> launch
        }
    }

    fun ended(timeMs: Long): List<Effect> {
        val launch = catchUp(timeMs)
        val effects = when (phase) {
            Phase.PENDING -> listOf(Effect.TypeSpace)
            Phase.GLIDING -> listOf(Effect.EndGlide)
            Phase.LAUNCHED -> launch
            Phase.FINISHED -> emptyList()
        }
        phase = Phase.FINISHED
        return effects
    }

    fun cancelled(): List<Effect> {
        val effects = if (phase == Phase.GLIDING) listOf(Effect.EndGlide) else emptyList()
        phase = Phase.FINISHED
        return effects
    }
}

/** A glide moves by what the user SEES: whole grapheme clusters (👍🏽 is 4
 *  UTF-16 units, a flag 4, a ZWJ family 11), turned into the UTF-16 distance
 *  InputConnection positions use. Clamped to the text supplied, so an edge
 *  reads as 0 — the caller must then send nothing. */
object CursorMath {
    fun utf16Distance(graphemes: Int, before: String, after: String): Int {
        val bi = android.icu.text.BreakIterator.getCharacterInstance()
        return if (graphemes < 0) {
            bi.setText(before)
            var idx = before.length
            repeat(-graphemes) {
                val prev = bi.preceding(idx)
                if (prev != android.icu.text.BreakIterator.DONE) idx = prev
            }
            idx - before.length
        } else {
            bi.setText(after)
            var idx = 0
            repeat(graphemes) {
                val next = bi.following(idx)
                if (next != android.icu.text.BreakIterator.DONE) idx = next
            }
            idx
        }
    }
}
