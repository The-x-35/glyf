package com.arpit.glyf.ime

import com.arpit.glyf.ime.VoiceMachine.Fault
import com.arpit.glyf.ime.VoiceMachine.Phase
import com.arpit.glyf.ime.VoiceMachine.Step
import org.junit.Assert.assertEquals
import org.junit.Test

/** One go of voice typing, callback by callback (VoiceMachine). */
class VoiceMachineTest {

    private fun listening(onDevice: Boolean = true, default: Boolean = true) =
        VoiceMachine(onDevice, default).also { it.start(); it.ready() }

    @Test fun thePhonesOwnRecognizerComesFirst() {
        val m = VoiceMachine(hasOnDevice = true, hasDefault = true)
        assertEquals(Step.Listen(onDevice = true), m.start())
        assertEquals(Phase.STARTING, m.phase)
    }

    @Test fun itsUsualOneWhenThereIsNoOnDeviceOne() =
        assertEquals(Step.Listen(onDevice = false), VoiceMachine(false, true).start())

    @Test fun noRecognizerAtAllSaysSoAndEnds() {
        val m = VoiceMachine(false, false)
        assertEquals(Step.End(null, VoiceMachine.NO_VOICE), m.start())
        assertEquals(Phase.ENDED, m.phase)
    }

    @Test fun aSecondStartDoesNothing() {
        val m = VoiceMachine(true, true)
        m.start()
        assertEquals(Step.None, m.start())
    }

    @Test fun wordsStreamThenTheFinalOnesGoIn() {
        val m = VoiceMachine(true, true)
        m.start()
        assertEquals(Step.Ready, m.ready())
        assertEquals(Phase.LISTENING, m.phase)
        assertEquals(Step.Words("see you"), m.partial("see you"))
        assertEquals(Step.Words("see you at five"), m.partial(" see you at five "))
        assertEquals(Step.Finishing, m.speechEnded())
        assertEquals(Phase.STOPPING, m.phase)
        assertEquals(Step.End("See you at five.", null), m.results("See you at five."))
        assertEquals(Phase.ENDED, m.phase)
    }

    @Test fun wordsBeforeReadyStillCount() {
        val m = VoiceMachine(true, true)
        m.start()
        assertEquals(Step.Words("hi"), m.partial("hi"))
        assertEquals(Phase.LISTENING, m.phase)
    }

    @Test fun blankPartialsShowNothing() = assertEquals(Step.None, listening().partial("  "))

    @Test fun doneStopsAndKeepsTheLastWordsIfNoFinalComes() {
        val m = listening()
        m.partial("call mom")
        assertEquals(Step.Stop, m.stopTapped())
        assertEquals(Step.None, m.stopTapped())
        assertEquals(Step.End("call mom", null), m.giveUp())
    }

    @Test fun aFinalWithNothingKeepsThePartials() {
        val m = listening()
        m.partial("call mom")
        assertEquals(Step.End("call mom", null), m.results(null))
    }

    @Test fun nothingHeardSaysSo() =
        assertEquals(Step.End(null, VoiceMachine.MISSED), listening().results(null))

    @Test fun cancelPutsNothingIn() {
        val m = listening()
        m.partial("never mind")
        assertEquals(Step.End(null, null), m.cancel())
        assertEquals(Step.None, m.results("never mind"))
        assertEquals(Step.None, m.cancel())
    }

    @Test fun lateCallbacksAfterTheEndDoNothing() {
        val m = listening()
        m.results("done")
        assertEquals(Step.None, m.partial("more"))
        assertEquals(Step.None, m.error(Fault.OTHER, true))
        assertEquals(Step.None, m.speechEnded())
        assertEquals(Step.None, m.giveUp())
    }

    @Test fun silenceAndNoMatchAreMisses() {
        assertEquals(Step.End(null, VoiceMachine.MISSED), listening().error(Fault.SILENCE, true))
        assertEquals(Step.End(null, VoiceMachine.MISSED), listening().error(Fault.NO_MATCH, true))
    }

    @Test fun noMicrophoneYetAsksTheAppOnce() =
        assertEquals(Step.End(null, null, askMic = true), listening().error(Fault.PERMISSION, micGranted = false))

    @Test fun aMicrophoneAllowedButRefusedSaysSo() =
        assertEquals(Step.End(null, VoiceMachine.MIC_REFUSED), listening().error(Fault.PERMISSION, micGranted = true))

    @Test fun theOnDeviceOneFailingFallsBackToTheUsualOneOnce() {
        val m = listening()
        assertEquals(Step.Listen(onDevice = false), m.error(Fault.LANGUAGE, true))
        assertEquals(false, m.onDevice)
        m.ready()
        // The usual one failing too: no third try.
        assertEquals(Step.End(null, VoiceMachine.OFFLINE), m.error(Fault.NETWORK, true))
    }

    @Test fun noFallBackWithoutAUsualRecognizer() =
        assertEquals(Step.End(null, VoiceMachine.NO_LANGUAGE), listening(default = false).error(Fault.LANGUAGE, true))

    @Test fun noFallBackOnceWordsWereHeard() {
        val m = listening()
        m.partial("half a")
        assertEquals(Step.End("half a", null), m.error(Fault.NETWORK, true))
    }

    @Test fun anErrorAfterDoneIsAMissNotAFallBack() {
        val m = listening()
        m.stopTapped()
        assertEquals(Step.End(null, VoiceMachine.MISSED), m.error(Fault.OTHER, true))
    }

    @Test fun couldNotStartTriesTheUsualOne() {
        val m = VoiceMachine(true, true)
        m.start()
        assertEquals(Step.Listen(onDevice = false), m.couldNotStart())
        assertEquals(Step.End(null, VoiceMachine.NO_VOICE), m.couldNotStart())
    }

    @Test fun busyAndAudioEndWithTheirNote() {
        assertEquals(Step.End(null, VoiceMachine.BUSY), listening().error(Fault.BUSY, true))
        assertEquals(Step.End(null, VoiceMachine.MIC_BUSY), listening().error(Fault.AUDIO, true))
    }

    @Test fun recognizerErrorCodes() {
        assertEquals(Fault.NO_MATCH, VoiceMachine.faultOf(7))
        assertEquals(Fault.SILENCE, VoiceMachine.faultOf(6))
        assertEquals(Fault.PERMISSION, VoiceMachine.faultOf(9))
        assertEquals(Fault.NETWORK, VoiceMachine.faultOf(2))
        assertEquals(Fault.LANGUAGE, VoiceMachine.faultOf(13))
        assertEquals(Fault.BUSY, VoiceMachine.faultOf(10))
        assertEquals(Fault.OTHER, VoiceMachine.faultOf(11))
    }
}
