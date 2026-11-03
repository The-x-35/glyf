package com.arpit.glyf.ime

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.arpit.glyf.MicPermissionActivity

/**
 * Voice typing heard by the keyboard itself (Arpit, 2026-10-06: "the mic
 * should work inside keyboard"), not handed to another keyboard or the app:
 * the phone's speech recognizer, the on-device one where the phone has it
 * (Android 12+), else its usual one. One go: it ends when the person stops
 * talking (the recognizer's own end-of-speech) or taps Done. The states and
 * what each callback does live in [VoiceMachine]; this carries the steps out.
 * Main thread only, as SpeechRecognizer asks.
 *
 * [onEnd] gets the words heard (null for none) and, when there are none, a
 * short note for the keyboard's notice (null to say nothing).
 *
 * [script] (debug builds, the DEBUG_TOOL "voicefake"): no recognizer; the
 * words arrive one at a time as a recognizer's partial results do, for an
 * emulator with no speech service.
 */
class Dictation(
    private val ctx: Context,
    private val onWords: (String) -> Unit,
    private val onLevel: (Float) -> Unit,
    private val onReady: () -> Unit,
    private val onStopping: () -> Unit,
    private val onEnd: (heard: String?, note: String?) -> Unit,
    private val script: String? = null,
) {
    private val main = Handler(Looper.getMainLooper())
    private val machine = VoiceMachine(
        hasOnDevice = script != null ||
            (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)),
        hasDefault = script == null && SpeechRecognizer.isRecognitionAvailable(ctx))
    private var recognizer: SpeechRecognizer? = null

    /** The newest words heard: what Done keeps if no final answer comes. */
    val heard: String get() = machine.heard

    /** The recognizer used the phone's own model (false: its usual one). */
    val onDevice: Boolean get() = machine.onDevice

    fun start() = run(machine.start())

    /** Done: stop listening and keep what was said. The final words follow
     *  in a moment; never wait on them long. */
    fun stop() = run(machine.stopTapped())

    /** ✕, or the keyboard went: nothing goes in. */
    fun cancel() {
        machine.cancel()
        release()
    }

    private val giveUp = Runnable { run(machine.giveUp()) }

    private fun run(step: VoiceMachine.Step) {
        when (step) {
            is VoiceMachine.Step.Listen -> if (script != null) playScript() else listen(step.onDevice)
            VoiceMachine.Step.Ready -> onReady()
            is VoiceMachine.Step.Words -> onWords(step.text)
            VoiceMachine.Step.Stop -> {
                onStopping()
                if (script == null) runCatching { recognizer?.stopListening() }
                else main.postDelayed({ run(machine.results(null)) }, 350)
                main.postDelayed(giveUp, 2000)
            }
            VoiceMachine.Step.Finishing -> onStopping()
            is VoiceMachine.Step.End -> {
                release()
                if (step.askMic) MicPermissionActivity.ask(ctx)
                onEnd(step.heard, step.note)
            }
            VoiceMachine.Step.None -> {}
        }
    }

    private fun listen(local: Boolean) {
        release()
        val r = runCatching {
            if (local && Build.VERSION.SDK_INT >= 31) SpeechRecognizer.createOnDeviceSpeechRecognizer(ctx)
            else SpeechRecognizer.createSpeechRecognizer(ctx)
        }.getOrNull() ?: return run(machine.couldNotStart())
        recognizer = r
        r.setRecognitionListener(listenerFor(r))
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, ctx.packageName)
            // The privacy policy says dictation is turned into text on the
            // phone: the phone's usual recognizer is asked to stay offline too.
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        if (Build.VERSION.SDK_INT >= 33) {
            // Commas, full stops and capitals where the recognizer writes them
            // (the formatted text is the first of what it returns).
            intent.putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
            intent.putExtra(RecognizerIntent.EXTRA_HIDE_PARTIAL_TRAILING_PUNCTUATION, true)
        }
        if (runCatching { r.startListening(intent) }.isFailure) run(machine.couldNotStart())
    }

    private fun listenerFor(r: SpeechRecognizer) = object : RecognitionListener {
        private fun live() = r === recognizer
        override fun onReadyForSpeech(params: Bundle?) { if (live()) run(machine.ready()) }
        override fun onBeginningOfSpeech() { if (live()) run(machine.ready()) }
        override fun onRmsChanged(rmsdB: Float) {
            if (live() && machine.phase != VoiceMachine.Phase.STOPPING) onLevel(rmsdB)
        }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() { if (live()) run(machine.speechEnded()) }
        override fun onPartialResults(partialResults: Bundle?) {
            if (live()) run(machine.partial(first(partialResults)))
        }
        override fun onResults(results: Bundle?) {
            if (live()) run(machine.results(first(results)))
        }
        override fun onError(error: Int) {
            if (live()) run(machine.error(VoiceMachine.faultOf(error), MicPermissionActivity.granted(ctx)))
        }
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun first(b: Bundle?): String? =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull { it.isNotBlank() }?.trim()

    /** Debug builds: [script]'s words as a recognizer would give them, a
     *  word every 260ms with a voice level to match, then the end of speech. */
    private fun playScript() {
        val words = script.orEmpty().trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val gen = Any()
        playing = gen
        main.postDelayed({ if (playing === gen) run(machine.ready()) }, 300)
        words.forEachIndexed { i, _ ->
            main.postDelayed({
                if (playing !== gen) return@postDelayed
                onLevel(4f + (i % 3) * 3f)
                run(machine.partial(words.take(i + 1).joinToString(" ")))
            }, 600L + 260L * i)
        }
        val end = 600L + 260L * words.size + 500L
        main.postDelayed({ if (playing === gen) run(machine.speechEnded()) }, end)
        main.postDelayed({ if (playing === gen) run(machine.results(script)) }, end + 400)
    }

    private var playing: Any? = null

    private fun release() {
        main.removeCallbacks(giveUp)
        playing = null
        val r = recognizer ?: return
        recognizer = null
        runCatching { r.cancel() }
        // Not from inside its own callback.
        main.post { runCatching { r.destroy() } }
    }
}
