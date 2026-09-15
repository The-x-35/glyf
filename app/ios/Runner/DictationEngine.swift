import AVFoundation
import Foundation
import Speech

/// §6.6 in-app capture: AVAudioEngine + on-device SFSpeechRecognizer with
/// LIVE partial results — by the time the user taps stop, the raw transcript
/// is already there (that's how the <4s gate is met).
/// Privacy (§11): `requiresOnDeviceRecognition` whenever supported — audio
/// never leaves the device; only the TEXT goes to the backend for cleanup,
/// and only when the user picks Clean/Formal.
///
/// Fake mode (--glyf-fake-dictation, or when speech is unavailable, e.g.
/// simulator runtimes without the speech stack) streams a canned transcript
/// so the full flow stays testable.
final class DictationEngine: NSObject {
    static let shared = DictationEngine()

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var fakeTimer: Timer?
    private(set) var transcript = ""
    private(set) var isFake = false
    private var startedAt: Date?

    /// Partial transcripts, delivered on the main queue.
    var onPartial: ((String) -> Void)?

    static let fakeScript =
        "hello um so this is the glyf dictation test you know it should um clean this right up"

    private var forceFake: Bool {
        ProcessInfo.processInfo.arguments.contains("--glyf-fake-dictation")
    }

    // MARK: - Start

    func start(completion: @escaping (_ ok: Bool, _ fake: Bool, _ error: String?) -> Void) {
        stopEverything()
        transcript = ""
        startedAt = Date()

        let recognizer = SFSpeechRecognizer()
        if forceFake || recognizer == nil || recognizer?.isAvailable == false {
            startFake()
            completion(true, true, nil)
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self else { return }
                guard auth == .authorized else {
                    completion(false, false, "Speech recognition permission denied")
                    return
                }
                Self.requestMicPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            completion(false, false, "Microphone permission denied")
                            return
                        }
                        do {
                            try self.startReal(recognizer: recognizer!)
                            completion(true, false, nil)
                        } catch {
                            // Simulator audio stacks fail in odd ways — keep the
                            // flow alive in fake mode rather than dead-ending.
                            self.startFake()
                            completion(true, true, nil)
                        }
                    }
                }
            }
        }
    }

    private static func requestMicPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    private func startReal(recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        isFake = false

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            DispatchQueue.main.async {
                self.transcript = result.bestTranscription.formattedString
                self.onPartial?(self.transcript)
            }
        }
    }

    private func startFake() {
        isFake = true
        let words = Self.fakeScript.split(separator: " ").map(String.init)
        var i = 0
        fakeTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            guard i < words.count else { t.invalidate(); return }
            self.transcript += (self.transcript.isEmpty ? "" : " ") + words[i]
            i += 1
            self.onPartial?(self.transcript)
        }
    }

    // MARK: - Stop / cancel

    /// Returns the final raw transcript plus capture latency (ms after stop).
    func stop(completion: @escaping (String, Int) -> Void) {
        let stopBegan = Date()
        if isFake {
            stopEverything()
            completion(transcript, 0)
            return
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // Live partials mean the transcript is already current; give the
        // recognizer a short grace window for the final segment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            let final = self.transcript
            self.stopEverything()
            completion(final, Int(Date().timeIntervalSince(stopBegan) * 1000))
        }
    }

    func cancel() {
        stopEverything()
        transcript = ""
    }

    private func stopEverything() {
        fakeTimer?.invalidate()
        fakeTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }
}
