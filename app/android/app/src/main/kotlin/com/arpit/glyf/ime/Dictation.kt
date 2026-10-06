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
 * should work inside keyboard"), not handed to another keyboard: the phone's
 * speech recognizer, the on-device one where the phone has it, else its
 * usual one. One go: it ends when the person stops talking or taps Done.
 * Main thread only.
 *
 * [onEnd] gets the words heard (null for none) and, when there are none, a
 * short note for the keyboard's notice (null to say nothing).
 */
class Dictation(
    private val ctx: Context,
    private val onWords: (String) -> Unit,
    private val onLevel: (Float) -> Unit,
    private val onStopping: () -> Unit,
    private val onEnd: (heard: String?, note: String?) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var onDevice = false
    private var stopping = false
    private var ended = false

    /** The newest words heard: what Done keeps if no final answer comes. */
    var heard = ""
        private set

    fun start() {
        val local = Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)
        if (!local && !SpeechRecognizer.isRecognitionAvailable(ctx)) return finish(NO_VOICE)
        listen(local)
    }

    /** Done: stop listening and keep what was said. The final words follow
     *  in a moment; never wait on them long. */
    fun stop() {
        val r = recognizer ?: return
        if (ended || stopping) return
        stopping = true
        onStopping()
        runCatching { r.stopListening() }
        main.postDelayed(giveUp, 2000)
    }

    /** ✕, or the keyboard went: nothing goes in. */
    fun cancel() {
        ended = true
        release()
    }

    private val giveUp = Runnable { finish("Didn't catch that") }

    private fun listen(local: Boolean) {
        onDevice = local
        val r = runCatching {
            if (local && Build.VERSION.SDK_INT >= 31) SpeechRecognizer.createOnDeviceSpeechRecognizer(ctx)
            else SpeechRecognizer.createSpeechRecognizer(ctx)
        }.getOrNull() ?: return fallBack(NO_VOICE)
        recognizer = r
        r.setRecognitionListener(listenerFor(r))
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, ctx.packageName)
            // The privacy policy says dictation is turned into text on the
            // phone: the phone's own recognizer stays offline too.
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        if (Build.VERSION.SDK_INT >= 33) {
            // Commas, full stops and capitals where the recognizer writes them
            // (the formatted text is the first of what it returns).
            intent.putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
            intent.putExtra(RecognizerIntent.EXTRA_HIDE_PARTIAL_TRAILING_PUNCTUATION, true)
        }
        if (runCatching { r.startListening(intent) }.isFailure) fallBack(NO_VOICE)
    }

    /** The phone's own recognizer couldn't, before a word: its usual one,
     *  once, when it has one. */
    private fun fallBack(note: String) {
        if (onDevice && heard.isBlank() && !stopping && SpeechRecognizer.isRecognitionAvailable(ctx)) {
            release()
            listen(false)
        } else finish(note)
    }

    private fun listenerFor(r: SpeechRecognizer) = object : RecognitionListener {
        private fun live() = !ended && r === recognizer
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) { if (live() && !stopping) onLevel(rmsdB) }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {
            if (live() && !stopping) { stopping = true; onStopping() }
        }
        override fun onPartialResults(partialResults: Bundle?) {
            val text = first(partialResults) ?: return
            if (!live()) return
            heard = text
            onWords(text)
        }
        override fun onResults(results: Bundle?) {
            if (!live()) return
            first(results)?.let { heard = it }
            finish("Didn't catch that")
        }
        override fun onError(error: Int) {
            if (!live()) return
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> finish("Didn't catch that")
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    if (MicPermissionActivity.granted(ctx)) finish("Glyf can't use the microphone")
                    else { finish(null); MicPermissionActivity.ask(ctx) }
                SpeechRecognizer.ERROR_AUDIO -> finish("The microphone is busy")
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY, SpeechRecognizer.ERROR_TOO_MANY_REQUESTS ->
                    finish("Voice typing is busy")
                SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER ->
                    fallBack("Voice typing needs a connection")
                // Done before a word was said: nothing to say about it.
                else -> if (stopping) finish("Didn't catch that") else fallBack("Voice typing stopped")
            }
        }
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun first(b: Bundle?): String? =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull { it.isNotBlank() }?.trim()

    private fun finish(note: String?) {
        if (ended) return
        ended = true
        release()
        val words = heard.trim().ifEmpty { null }
        onEnd(words, if (words == null) note else null)
    }

    private fun release() {
        main.removeCallbacks(giveUp)
        val r = recognizer ?: return
        recognizer = null
        runCatching { r.cancel() }
        // Not from inside its own callback.
        main.post { runCatching { r.destroy() } }
    }

    private companion object {
        const val NO_VOICE = "No voice typing on this phone"
    }
}
