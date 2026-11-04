import AVFoundation
import Speech
import UIKit
import os.log

/// The app's half of voice typing (VoiceLink has the protocol). The keyboard
/// can't use the microphone, so Glyf listens for it: glyf://voice starts a
/// session that keeps AVAudioEngine's input running in the background
/// (UIBackgroundModes audio, the orange dot), throws the sound away while
/// idle, and feeds Apple's on-device recognizer between the keyboard's start
/// and stop. Five idle minutes (VoiceLink.idleLifetime) end it.
final class VoiceHost {
    static let shared = VoiceHost()
    private let log = Logger(subsystem: "so.glyf.app", category: "voice")

    private var machine = VoiceMachine(now: Date().timeIntervalSince1970)
    private let engine = AVAudioEngine()
    private var tapOn = false
    private var heartbeat: Timer?
    private var recognizer: VoiceRecognizer?
    /// The utterance the recognizer above belongs to.
    private var recognizing: String?
    /// The DictationTranscriber's format once its model is on the phone
    /// (iOS 26+); nil means SFSpeechRecognizer.
    private var analyzerFormat: AVAudioFormat?
    private var observers: [NSObjectProtocol] = []

    /// Touched from the audio thread: where buffers go, and when one came.
    private let lock = NSLock()
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var lastBufferAt: Double = 0
    /// A short ring of the last idle buffers, so the first syllable said
    /// right after the tap is not lost while the keyboard's note travels.
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollFrames: AVAudioFrameCount = 0
    private var level: Float = 0
    /// The level, about 16 times a second (VoiceLink.levelEvery), for the
    /// keyboard's wave and the listening screen's.
    private var levelTimer: Timer?
    /// Words from earlier stretches of this utterance: a recognizer that
    /// ends by itself after a long pause is followed by a new one, and the
    /// person keeps talking until ✓ (Wispr Flow does the same).
    private var carried = ""
    private var restarts: [Double] = []

    private var overlay: VoiceOverlay?

    /// DEBUG: a recording fed instead of the microphone (simulator tests).
    private var debugFile: URL?
    private var debugFeed: DispatchSourceTimer?

    private static var now: Double { Date().timeIntervalSince1970 }

    private init() {
        DarwinBus.shared.observe(VoiceLink.commandNote) { [weak self] in self?.commandArrived() }
        // Back in their chat: the screen goes, the session stays.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.overlay?.dismiss() }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--glyf-voice-file"), i + 1 < args.count {
            debugFile = URL(fileURLWithPath: args[i + 1])
        } else if let dir = AppGroupStore.bridgeDir {
            let f = dir.appendingPathComponent("voice-test.aiff")
            if FileManager.default.fileExists(atPath: f.path) { debugFile = f }
        }
        #endif
        // A state file left by a session that died with the app says so.
        if let s = VoiceLink.readState(), s.phase != .off {
            VoiceLink.publish(.off(now: Self.now))
        }
    }

    /// Wakes the host up so it hears the keyboard's commands.
    func boot() {}

    // MARK: Opening

    /// glyf://voice[?u=<utterance>] from the keyboard's mic.
    func open(_ url: URL, scene: UIWindowScene?) {
        let u = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "u" }?.value
        showOverlay(in: scene)
        overlay?.show(.starting)
        start(listenNow: u)
    }

    private func start(listenNow: String?) {
        requestPermissions { [weak self] ok, why in
            guard let self else { return }
            guard ok else {
                self.overlay?.show(.denied(why))
                VoiceLink.publish({ var s = VoiceLink.State.off(now: Self.now); s.error = why; return s }())
                return
            }
            self.prepareRecognizer {
                if !self.machine.isOn {
                    do {
                        try self.startAudio()
                    } catch {
                        self.log.error("GLYF_VOICE audio failed \(error.localizedDescription, privacy: .public)")
                        #if DEBUG
                        // The simulator's input can fail; a test file still runs.
                        if self.debugFile == nil {
                            self.overlay?.show(.failed("Microphone unavailable"))
                            return
                        }
                        #else
                        self.overlay?.show(.failed("Microphone unavailable"))
                        return
                        #endif
                    }
                }
                #if DEBUG && targetEnvironment(simulator)
                let engineName = "simulator-script"
                #else
                let engineName = self.debugFile != nil ? "file"
                    : self.analyzerFormat != nil ? "dictation" : "speech"
                #endif
                self.run(self.machine.open(session: UUID().uuidString, now: Self.now,
                                           listenNow: listenNow, engine: engineName))
                self.overlay?.show(.listening)
                self.startHeartbeat()
            }
        }
    }

    // MARK: Permissions

    private func requestPermissions(_ done: @escaping (Bool, String) -> Void) {
        let mic: (@escaping (Bool) -> Void) -> Void = { cb in
            AVAudioApplication.requestRecordPermission { ok in DispatchQueue.main.async { cb(ok) } }
        }
        mic { micOK in
            guard micOK else { done(false, "Allow the microphone in Settings › Glyf"); return }
            let status = SFSpeechRecognizer.authorizationStatus()
            if status == .authorized { done(true, ""); return }
            guard status == .notDetermined else {
                done(false, "Allow Speech Recognition in Settings › Glyf"); return
            }
            SFSpeechRecognizer.requestAuthorization { st in
                DispatchQueue.main.async {
                    st == .authorized ? done(true, "")
                        : done(false, "Allow Speech Recognition in Settings › Glyf")
                }
            }
        }
    }

    // MARK: Recognizer choice

    /// SFSpeechRecognizer on the phone wherever it can (English and the
    /// other big languages on every iPhone Glyf runs on). Where it can't,
    /// iOS 26's DictationTranscriber, also on the phone, once its model is
    /// installed (fetched the first time it is missing).
    private func prepareRecognizer(_ then: @escaping () -> Void) {
        let onDevice = SFSpeechRecognizer()?.supportsOnDeviceRecognition == true
        guard #available(iOS 26, *), !onDevice || ProcessInfo.processInfo.arguments.contains("--glyf-voice-analyzer")
        else {
            analyzerFormat = nil
            then(); return
        }
        Task { @MainActor in
            let format = await AnalyzerRecognizer.readyFormat()
            self.analyzerFormat = format
            self.log.log("GLYF_VOICE analyzer ready=\(format != nil)")
            then()
        }
    }

    // MARK: Audio

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        // Mixable: music keeps playing while Glyf listens (Wispr does the same).
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        try installTapAndStart()
        observeSession()
        log.log("GLYF_VOICE audio on")
    }

    private func installTapAndStart() throws {
        let input = engine.inputNode
        if tapOn { input.removeTap(onBus: 0); tapOn = false }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "GlyfVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input"])
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.heard(buffer, fromMic: true)
        }
        tapOn = true
        engine.prepare()
        try engine.start()
    }

    /// Audio thread.
    private func heard(_ buffer: AVAudioPCMBuffer, fromMic: Bool) {
        lock.lock()
        lastBufferAt = Self.now
        level = Self.rms(buffer)
        // While a test file plays, the microphone only keeps the app alive.
        if fromMic && debugFeed != nil { lock.unlock(); return }
        if let sink {
            lock.unlock()
            sink(buffer)
            return
        }
        preRoll.append(buffer)
        preRollFrames += buffer.frameLength
        let keep = AVAudioFrameCount(buffer.format.sampleRate * 0.4)
        while preRollFrames > keep, let first = preRoll.first {
            preRollFrames -= first.frameLength
            preRoll.removeFirst()
        }
        lock.unlock()
    }

    private static func rms(_ b: AVAudioPCMBuffer) -> Float {
        guard let ch = b.floatChannelData?[0], b.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(b.frameLength) { sum += ch[i] * ch[i] }
        return (sum / Float(b.frameLength)).squareRoot()
    }

    private func stopAudio() {
        stopDebugFeed()
        if engine.isRunning { engine.stop() }
        if tapOn { engine.inputNode.removeTap(onBus: 0); tapOn = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        log.log("GLYF_VOICE audio off")
    }

    private func observeSession() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: nil, queue: .main) { [weak self] note in
            self?.interrupted(note)
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                                        object: engine, queue: .main) { [weak self] _ in
            // A headset came or went: the input's format changed under the tap.
            guard let self, self.machine.isOn else { return }
            do { try self.installTapAndStart() } catch { self.lost("Microphone changed") }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.lost("Voice stopped")
        })
    }

    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // A call or Siri: what was heard so far stands.
            if let u = machine.state.utterance, machine.state.phase == .listening {
                run(machine.handle(.init(id: UUID().uuidString, verb: .stop, at: Self.now,
                                         utterance: u), now: Self.now))
            }
        case .ended:
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try installTapAndStart()
            } catch {
                lost("Voice stopped: another app has the microphone")
            }
        @unknown default:
            break
        }
    }

    private func lost(_ why: String) {
        var fx = machine.shutDown(now: Self.now)
        fx.removeAll { $0 == .publish }
        run(fx)
        var s = machine.state
        s.error = why
        VoiceLink.publish(s)
    }

    // MARK: Heartbeat

    private func startHeartbeat() {
        startLevels()
        guard heartbeat == nil else { return }
        let t = Timer(timeInterval: VoiceLink.heartbeatEvery, repeats: true) { [weak self] _ in
            self?.beat()
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeat = t
    }

    private func beat() {
        lock.lock()
        let flowing = Self.now - lastBufferAt < 2 || debugFeed != nil
        lock.unlock()
        run(machine.tick(now: Self.now, audioFlowing: flowing))
        if !machine.isOn { heartbeat?.invalidate(); heartbeat = nil }
    }

    private func startLevels() {
        guard levelTimer == nil else { return }
        let t = Timer(timeInterval: VoiceLink.levelEvery, repeats: true) { [weak self] _ in
            self?.levelTick()
        }
        RunLoop.main.add(t, forMode: .common)
        levelTimer = t
    }

    private func stopLevels() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func levelTick() {
        guard machine.isOn else { stopLevels(); return }
        lock.lock()
        let rms = level
        lock.unlock()
        let v = recognizer?.simulatedLevel ?? VoiceLink.normalizedLevel(rms: rms)
        overlay?.setLevel(v)
        run(machine.level(v))
    }

    // MARK: Commands

    private func commandArrived() {
        guard let c = VoiceLink.readCommand() else { return }
        log.log("GLYF_VOICE command \(c.verb.rawValue, privacy: .public)")
        run(machine.handle(c, now: Self.now))
    }

    /// The person ended it (the overlay's Turn off).
    func end() {
        run(machine.shutDown(now: Self.now))
        overlay?.dismiss()
    }

    // MARK: Effects

    private func run(_ effects: [VoiceMachine.Effect]) {
        for e in effects {
            switch e {
            case .beginCapture(let u): beginCapture(u)
            case .endCapture(let u): endCapture(u)
            case .abortCapture: abortCapture()
            case .shutDown:
                heartbeat?.invalidate(); heartbeat = nil
                stopLevels()
                stopAudio()
            case .publish:
                VoiceLink.publish(machine.state)
            }
        }
    }

    private func beginCapture(_ u: String) {
        abortCapture()
        carried = ""
        restarts = []
        overlay?.setWords("")
        let r = startRecognizer(u)
        lock.lock()
        let early = preRoll
        preRoll = []
        preRollFrames = 0
        lock.unlock()
        if debugFile != nil {
            startDebugFeed()
        } else {
            for b in early { r.append(b) }
        }
        log.log("GLYF_VOICE listening")
    }

    private func makeRecognizer() -> VoiceRecognizer {
        #if DEBUG && targetEnvironment(simulator)
        return ScriptRecognizer()
        #else
        if #available(iOS 26, *), let format = analyzerFormat {
            return AnalyzerRecognizer(format: format)
        }
        return SpeechRecognizer()
        #endif
    }

    /// A recognizer for one stretch of utterance `u`, fed from the sink.
    @discardableResult
    private func startRecognizer(_ u: String) -> VoiceRecognizer {
        let r = makeRecognizer()
        r.onPartial = { [weak self] text in
            guard let self, self.recognizing == u else { return }
            let all = VoiceLink.joined(self.carried, text)
            self.overlay?.setWords(VoiceLink.live(all))
            self.run(self.machine.partial(all, utterance: u))
        }
        r.onFinal = { [weak self] text in
            guard let self, self.recognizing == u else { return }
            let all = VoiceLink.joined(self.carried, text)
            self.recognizing = nil
            self.recognizer = nil
            // Still listening: the recognizer stopped by itself after a
            // pause. The words carry on into a new stretch.
            if self.machine.continues(utterance: u), self.mayRestart() {
                self.log.log("GLYF_VOICE stretch ended, listening on")
                self.carried = all
                self.startRecognizer(u)
                return
            }
            self.log.log("GLYF_VOICE final chars=\(all.count)")
            self.run(self.machine.finished(all, utterance: u, now: Self.now))
        }
        r.onError = { [weak self] message in
            guard let self, self.recognizing == u else { return }
            self.log.error("GLYF_VOICE error \(message, privacy: .public)")
            self.recognizing = nil
            self.recognizer = nil
            // A quiet stretch ("no speech") mid-utterance is not the end.
            if self.machine.continues(utterance: u), self.mayRestart() {
                self.carried = self.machine.state.partial
                self.startRecognizer(u)
                return
            }
            self.run(self.machine.failed(message, utterance: u, now: Self.now))
        }
        recognizer = r
        recognizing = u
        r.begin()
        lock.lock()
        sink = { [weak r] b in r?.append(b) }
        lock.unlock()
        return r
    }

    /// At most four new stretches in eight seconds: a recognizer that keeps
    /// failing at once ends the utterance instead of spinning.
    private func mayRestart() -> Bool {
        let now = Self.now
        restarts = restarts.filter { now - $0 < 8 }
        guard restarts.count < 4 else { return false }
        restarts.append(now)
        return true
    }

    private func endCapture(_ u: String) {
        guard recognizing == u else { return }
        lock.lock(); sink = nil; lock.unlock()
        stopDebugFeed()
        recognizer?.finish()
    }

    private func abortCapture() {
        carried = ""
        lock.lock(); sink = nil; lock.unlock()
        stopDebugFeed()
        recognizer?.cancel()
        recognizer = nil
        recognizing = nil
    }

    // MARK: DEBUG: a recording in place of the microphone

    /// Plays `debugFile` into the sink at real-time pace.
    private func startDebugFeed() {
        guard let url = debugFile, let file = try? AVAudioFile(forReading: url) else { return }
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 4096
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "glyf.voice.file"))
        let every = Double(chunk) / format.sampleRate
        timer.schedule(deadline: .now(), repeating: every)
        timer.setEventHandler { [weak self] in
            guard let self, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
            if (try? file.read(into: buf, frameCount: chunk)) == nil || buf.frameLength == 0 {
                // The file is over: silence, as a person who stopped talking.
                buf.frameLength = chunk
                if let ch = buf.floatChannelData {
                    for c in 0..<Int(format.channelCount) { memset(ch[c], 0, Int(chunk) * 4) }
                }
            }
            self.heard(buf, fromMic: false)
        }
        lock.lock(); debugFeed = timer; lock.unlock()
        timer.resume()
        log.log("GLYF_VOICE feeding \(url.lastPathComponent, privacy: .public)")
    }

    private func stopDebugFeed() {
        lock.lock()
        let t = debugFeed
        debugFeed = nil
        lock.unlock()
        t?.cancel()
    }

    // MARK: Overlay

    private func showOverlay(in scene: UIWindowScene?) {
        let scene = scene ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        if overlay == nil {
            overlay = VoiceOverlay(scene: scene, onEnd: { [weak self] in self?.end() })
        }
        overlay?.present()
    }
}

// MARK: - Recognizers

/// One utterance's recognizer. `append` comes from the audio thread; the
/// callbacks arrive on main.
class VoiceRecognizer {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?
    /// A stand-in loudness (the simulator's script), else nil: the mic's.
    var simulatedLevel: Float? { nil }
    func begin() {}
    func append(_ buffer: AVAudioPCMBuffer) {}
    func finish() {}
    func cancel() {}
}

/// SFSpeechRecognizer, on the phone whenever it can be.
final class SpeechRecognizer: VoiceRecognizer {
    private let recognizer = SFSpeechRecognizer()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var done = false

    override func begin() {
        guard let recognizer, recognizer.isAvailable else {
            onError?("Speech recognition isn't available"); return
        }
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        #if targetEnvironment(simulator)
        // The simulator has no on-device speech models (kLSRErrorDomain 300
        // "Failed to initialize recognizer"; SpeechAnalyzer lists no audio
        // formats), so a simulator build hears through Apple's servers.
        let onDevice = false
        #else
        let onDevice = recognizer.supportsOnDeviceRecognition
        #endif
        if onDevice {
            request.requiresOnDeviceRecognition = true
        } else {
            // The usage strings promise speech stays on the iPhone. Only a
            // debug build (the simulator) may use Apple's servers.
            #if !DEBUG
            onError?("Voice typing isn't available in this language yet"); return
            #endif
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, !self.done else { return }
                if let result {
                    self.latest = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.done = true
                        self.onFinal?(self.latest)
                    } else {
                        self.onPartial?(self.latest)
                    }
                } else if let error {
                    self.done = true
                    let e = error as NSError
                    Logger(subsystem: "so.glyf.app", category: "voice")
                        .error("GLYF_VOICE speech error \(e.domain, privacy: .public) \(e.code) \(e.localizedDescription, privacy: .public)")
                    // "No speech detected" after stop is an empty result, not a failure.
                    self.latest.isEmpty ? self.onError?("Didn't catch that") : self.onFinal?(self.latest)
                }
            }
        }
    }

    override func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
    override func finish() { request.endAudio() }
    override func cancel() {
        done = true
        task?.cancel()
        request.endAudio()
    }
}

#if DEBUG && targetEnvironment(simulator)
/// The simulator has no speech models: SFSpeechRecognizer fails with
/// kLSRErrorDomain 300 "Failed to initialize recognizer" (on-device and
/// server alike) and SpeechAnalyzer lists no audio formats (iOS 26.5
/// runtime, 2026-11-04). So a simulator build "hears" a script, a word at
/// a time at a speaking pace with pauses after each sentence, punctuated as
/// a recognizer with addsPunctuation writes it, and a loudness that rises
/// and falls with the words. The microphone, the background session and
/// the keyboard round trip stay real. The script is bridge/voice-test.txt in
/// the App Group when present ("#silence" hears nothing).
final class ScriptRecognizer: VoiceRecognizer {
    private var timer: Timer?
    private var said: [String] = []
    private var queue: [String] = []
    private var wait = 0
    private var talking = false
    private let born = CACurrentMediaTime()

    static let standard = "Hey, are you free for dinner on Friday? I was thinking we could try "
        + "that new Thai place downtown. Let me know what works for you!"

    static var script: [String] {
        let custom = AppGroupStore.bridgeDir
            .flatMap { try? String(contentsOf: $0.appendingPathComponent("voice-test.txt"), encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if custom == "#silence" { return [] }
        let text = (custom?.isEmpty == false ? custom! : standard)
        return text.split(separator: " ").map(String.init)
    }

    override var simulatedLevel: Float? {
        guard talking else { return 0.04 + Float.random(in: 0...0.03) }
        let t = CACurrentMediaTime() - born
        let syllables = 0.5 + 0.5 * sin(t * 13.0)
        let phrase = 0.65 + 0.35 * sin(t * 2.9)
        return Float(min(1, 0.22 + 0.7 * syllables * phrase + Double.random(in: -0.06...0.06)))
    }

    override func begin() {
        queue = Self.script
        // Ticks of 0.1 s: a word every three, a breath after a sentence.
        wait = 4
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        guard !queue.isEmpty else { talking = false; return }
        if wait > 0 {
            wait -= 1
            if wait <= 2 { talking = true }
            return
        }
        let word = queue.removeFirst()
        said.append(word)
        onPartial?(said.joined(separator: " "))
        if let last = word.last, ".?!".contains(last) {
            wait = 8; talking = false
        } else if word.hasSuffix(",") {
            wait = 4
        } else {
            wait = 2
        }
    }

    override func finish() {
        timer?.invalidate()
        talking = false
        var text = said.joined(separator: " ")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            guard !text.isEmpty else { self.onError?("Didn't catch that"); return }
            if let last = text.last, !".?!".contains(last) { text += "." }
            self.onFinal?(text.prefix(1).uppercased() + text.dropFirst())
        }
    }

    override func cancel() { timer?.invalidate(); talking = false }
}
#endif

/// iOS 26's SpeechAnalyzer with a DictationTranscriber: on the phone, with
/// punctuation, and no one-minute cap.
@available(iOS 26, *)
final class AnalyzerRecognizer: VoiceRecognizer {
    private let format: AVAudioFormat
    private let transcriber: DictationTranscriber
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var finalized = ""
    private var volatile = ""
    private var cancelled = false

    private static var locale: Locale { Locale.current }

    /// Long, progressive dictation with the recognizer's own punctuation.
    private static var preset: DictationTranscriber.Preset {
        var p = DictationTranscriber.Preset.progressiveLongDictation
        p.transcriptionOptions.insert(.punctuation)
        return p
    }

    /// The analyzer's audio format when the dictation model for this
    /// phone's language is installed; otherwise asks for it (for next time)
    /// and answers nil.
    static func readyFormat() async -> AVAudioFormat? {
        let log = Logger(subsystem: "so.glyf.app", category: "voice")
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Self.locale) else {
            log.log("GLYF_VOICE analyzer: \(Self.locale.identifier, privacy: .public) unsupported")
            return nil
        }
        let module = DictationTranscriber(locale: locale, preset: preset)
        let status = await AssetInventory.status(forModules: [module])
        log.log("GLYF_VOICE analyzer: \(locale.identifier, privacy: .public) status=\(String(describing: status), privacy: .public)")
        guard status == .installed else {
            guard status == .supported else { return nil }
            Task.detached {
                do {
                    if let req = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                        try await req.downloadAndInstall()
                    }
                    log.log("GLYF_VOICE analyzer model installed")
                } catch {
                    log.error("GLYF_VOICE analyzer install failed \(error.localizedDescription, privacy: .public)")
                }
            }
            return nil
        }
        if let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) {
            return best
        }
        let formats = await module.availableCompatibleAudioFormats
        log.log("GLYF_VOICE analyzer: no best format, \(formats.count) compatible: \(formats.map(\.description).joined(separator: " | "), privacy: .public)")
        return formats.first
    }

    init(format: AVAudioFormat) {
        self.format = format
        transcriber = DictationTranscriber(locale: Self.locale, preset: Self.preset)
        analyzer = SpeechAnalyzer(modules: [transcriber])
        (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        super.init()
    }

    override func begin() {
        let transcriber = self.transcriber
        Task { [weak self] in
            do {
                for try await r in transcriber.results {
                    let text = String(r.text.characters)
                    await MainActor.run {
                        guard let self, !self.cancelled else { return }
                        if r.isFinal {
                            self.finalized = Self.join(self.finalized, text)
                            self.volatile = ""
                        } else {
                            self.volatile = text
                        }
                        self.onPartial?(Self.join(self.finalized, self.volatile))
                    }
                }
                await MainActor.run {
                    guard let self, !self.cancelled else { return }
                    self.onFinal?(Self.join(self.finalized, self.volatile))
                }
            } catch {
                await MainActor.run {
                    guard let self, !self.cancelled else { return }
                    let heard = Self.join(self.finalized, self.volatile)
                    heard.isEmpty ? self.onError?("Didn't catch that") : self.onFinal?(heard)
                }
            }
        }
        let analyzer = self.analyzer, input = self.input, format = self.format
        Task {
            do {
                try await analyzer.prepareToAnalyze(in: format)
                try await analyzer.start(inputSequence: input)
            } catch {
                await MainActor.run { [weak self] in self?.onError?("Speech recognition isn't available") }
            }
        }
    }

    private static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespaces), b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    override func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        feed.yield(AnalyzerInput(buffer: converted))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    override func finish() {
        feed.finish()
        let analyzer = self.analyzer
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    }

    override func cancel() {
        cancelled = true
        feed.finish()
        let analyzer = self.analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

// MARK: - The screen the mic opens

/// One line and a way to turn it off, over whatever the app was showing,
/// in the keyboard panel's glass: a frosted sheet with a violet bloom and
/// the same ribbon moving with the voice. The person goes back with iOS's
/// "◀ Messages" (or a swipe along the bottom edge); since iOS 26.4 no app can
/// take them back by itself.
final class VoiceOverlay {
    enum Mode {
        case starting, listening
        case denied(String)
        case failed(String)
    }

    private let window: UIWindow
    private let blur = UIVisualEffectView(effect: nil)
    private let wash = CAGradientLayer()
    private let ribbon = VoiceRibbon()
    private let line = UILabel()
    private let words = UILabel()
    private let button = UIButton(type: .custom)
    private let onEnd: () -> Void
    private var mode: Mode = .starting
    private static let violet = UIColor(red: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255, alpha: 1)

    init(scene: UIWindowScene, onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let vc = OverlayController()
        window.rootViewController = vc
        let root = vc.view!
        root.backgroundColor = .clear
        root.accessibilityIdentifier = "voice:overlay"
        vc.onTraits = { [weak self] in self?.applyPalette() }

        blur.effect = UIBlurEffect(style: .systemThickMaterial)
        blur.contentView.layer.addSublayer(wash)
        wash.type = .radial
        wash.startPoint = CGPoint(x: 0.5, y: 0.42)
        wash.endPoint = CGPoint(x: 1.25, y: 0.95)

        line.font = .systemFont(ofSize: 19, weight: .semibold)
        line.textAlignment = .center
        line.numberOfLines = 2
        line.textColor = .label
        line.accessibilityIdentifier = "voice:line"
        words.font = .systemFont(ofSize: 17, weight: .regular)
        words.textColor = .secondaryLabel
        words.textAlignment = .center
        words.numberOfLines = 3
        words.lineBreakMode = .byTruncatingHead
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.layer.cornerRadius = 26
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0.5
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = 12
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 34, bottom: 0, right: 34)
        button.accessibilityIdentifier = "voice:button"
        button.addAction(UIAction { [weak self] _ in self?.buttonTapped() }, for: .touchUpInside)

        for v in [blur, ribbon, line, words, button] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: root.topAnchor),
            blur.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ribbon.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -70),
            ribbon.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            ribbon.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ribbon.heightAnchor.constraint(equalToConstant: 140),
            line.topAnchor.constraint(equalTo: ribbon.bottomAnchor, constant: 28),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            words.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 14),
            words.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            words.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            button.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            button.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            button.heightAnchor.constraint(equalToConstant: 52),
        ])
        vc.onLayout = { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.wash.frame = root.bounds
            CATransaction.commit()
        }
        applyPalette()
    }

    private func applyPalette() {
        let dark = window.traitCollection.userInterfaceStyle == .dark
        wash.colors = [Self.violet.withAlphaComponent(dark ? 0.30 : 0.16).cgColor,
                       Self.violet.withAlphaComponent(0).cgColor]
        ribbon.colors = dark
            ? [UIColor(red: 0.80, green: 0.73, blue: 1, alpha: 1), UIColor(red: 0.58, green: 0.45, blue: 1, alpha: 1),
               UIColor(red: 0.40, green: 0.60, blue: 1, alpha: 1)]
            : [UIColor(red: 0.66, green: 0.55, blue: 1, alpha: 1), Self.violet,
               UIColor(red: 0.30, green: 0.50, blue: 1, alpha: 1)]
        styleButton()
    }

    private func styleButton() {
        let dark = window.traitCollection.userInterfaceStyle == .dark
        let primary: Bool = { if case .denied = mode { return true }; return false }()
        button.backgroundColor = primary ? Self.violet
            : (dark ? UIColor.white.withAlphaComponent(0.14) : UIColor.white.withAlphaComponent(0.85))
        button.setTitleColor(primary ? .white : .label, for: .normal)
        button.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.14)
                                         : UIColor.black.withAlphaComponent(0.06)).cgColor
        button.layer.shadowOpacity = primary ? 0.35 : (dark ? 0.3 : 0.08)
        button.layer.shadowColor = (primary ? Self.violet : UIColor.black).cgColor
    }

    func present() {
        window.isHidden = false
        words.text = nil
        applyPalette()
    }

    func dismiss() {
        window.isHidden = true
    }

    func show(_ mode: Mode) {
        self.mode = mode
        switch mode {
        case .starting:
            line.text = "Starting…"
            button.setTitle(nil, for: .normal)
        case .listening:
            line.text = "Listening is on · go back to keep typing"
            button.setTitle("Turn off", for: .normal)
        case .denied(let why), .failed(let why):
            line.text = why
            button.setTitle(nil, for: .normal)
            if case .denied = mode { button.setTitle("Open Settings", for: .normal) }
        }
        button.isHidden = button.title(for: .normal) == nil
        let live: Bool = { if case .listening = mode { return true }; return false }()
        ribbon.calm = !live
        ribbon.alpha = live ? 1 : 0.4
        if !live { ribbon.level = 0 }
        styleButton()
    }

    func setWords(_ text: String) {
        words.text = text
    }

    func setLevel(_ level: Float) {
        guard !window.isHidden else { return }
        if case .listening = mode { ribbon.level = level }
    }

    private func buttonTapped() {
        switch mode {
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            onEnd()
        }
    }
}

/// Tells the overlay when its size or appearance changed.
private final class OverlayController: UIViewController {
    var onLayout: (() -> Void)?
    var onTraits: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        onTraits?()
    }
}
