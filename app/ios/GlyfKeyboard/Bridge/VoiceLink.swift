import Foundation

/// Voice typing across the keyboard ↔ app line (docs/APPS.md, "Voice typing
/// on the iPhone"). Compiled into the keyboard, the app and RunnerTests.
///
/// iOS keeps the microphone from every keyboard, so the app listens for it:
/// the mic opens Glyf once (glyf://voice), Glyf asks for the microphone,
/// starts listening and keeps an audio session alive in the background (the
/// orange dot), and the person swipes back. From then on the keyboard's mic
/// starts and stops capture through a Darwin notification plus a command
/// file in the App Group; the app writes what it hears (partial, then final)
/// to a state file and posts back. A heartbeat in that file tells the
/// keyboard the app is still there.
enum VoiceLink {

    // MARK: Constants

    /// Keyboard → app: a new command is in `commandFile`.
    static let commandNote = "com.arpit.glyf.voice.command"
    /// App → keyboard: `stateFile` changed.
    static let stateNote = "com.arpit.glyf.voice.state"
    static let stateFile = "voice-state.json"
    static let commandFile = "voice-command.json"
    /// The last utterance the keyboard put in a field (insert once).
    static let takenFile = "voice-taken.json"

    /// How long a session lives with nothing said before the app lets the
    /// microphone go (Wispr Flow's default is also 5 minutes).
    static let idleLifetime: TimeInterval = 5 * 60
    /// One utterance stops by itself after this long.
    static let maxUtterance: TimeInterval = 5 * 60
    /// The app writes its heartbeat this often while the microphone runs.
    static let heartbeatEvery: TimeInterval = 1
    /// A heartbeat older than this means the app is gone (killed, or iOS
    /// took the microphone): the keyboard opens the app again.
    static let staleAfter: TimeInterval = 4
    /// After stop, the recognizer gets this long to finish the last words;
    /// then the words heard so far are the result.
    static let finishTimeout: TimeInterval = 4
    /// A final older than this is not typed into whatever field is open now.
    static let deliverWithin: TimeInterval = 60

    static func openURL(utterance: String?) -> URL {
        var c = URLComponents()
        c.scheme = "glyf"
        c.host = "voice"
        if let utterance { c.queryItems = [URLQueryItem(name: "u", value: utterance)] }
        return c.url!
    }

    // MARK: Wire types

    enum Phase: String, Codable {
        /// No session: the app is not listening for the keyboard.
        case off
        /// Session alive, microphone open, words thrown away.
        case ready
        /// Capturing an utterance.
        case listening
        /// Stopped; the recognizer is finishing the last words.
        case finishing
    }

    struct State: Codable, Equatable {
        var session: String
        var phase: Phase
        /// Seconds since 1970; written every `heartbeatEvery` while alive.
        var heartbeat: Double
        /// When the session lets the microphone go if nothing is said.
        var expiresAt: Double
        /// The utterance being heard, or the last one heard.
        var utterance: String?
        /// When listening (or finishing) began, for the length cap.
        var since: Double?
        var partial: String = ""
        /// The finished words of `utterance`; nil until it is done.
        var final: String?
        var finishedAt: Double?
        /// One short line for the keyboard when something went wrong.
        var error: String?
        /// Which recognizer is in use ("dictation", "speech", "file").
        var engine: String?

        static func off(now: Double) -> State {
            State(session: "", phase: .off, heartbeat: now, expiresAt: now)
        }
    }

    struct Command: Codable, Equatable {
        enum Verb: String, Codable { case start, stop, cancel, end }
        var id: String
        var verb: Verb
        var at: Double
        /// The utterance a stop or cancel is about (start: `id` is it).
        var utterance: String?
    }

    // MARK: Liveness (keyboard side)

    /// The app is listening for the keyboard right now.
    static func alive(_ s: State?, now: Double) -> Bool {
        guard let s, s.phase != .off else { return false }
        return now - s.heartbeat < staleAfter && now < s.expiresAt + staleAfter
    }

    enum TapAction: Equatable {
        /// No Full Access: the keyboard can't reach the app or the App Group.
        case needsFullAccess
        /// No live session: open the app, which starts listening at once.
        case openApp
        case start
        case stop
    }

    /// What a tap on the mic does. While anything is being heard — this
    /// keyboard's utterance or one the app began when the mic opened it —
    /// the tap ends it.
    static func tapAction(state: State?, now: Double, fullAccess: Bool) -> TapAction {
        guard fullAccess else { return .needsFullAccess }
        guard alive(state, now: now), let s = state else { return .openApp }
        return s.phase == .listening || s.phase == .finishing ? .stop : .start
    }

    /// The finished words of an utterance, once, while still fresh.
    static func deliverable(_ s: State?, taken: String?, now: Double) -> (utterance: String, text: String)? {
        guard let s, let u = s.utterance, u != taken,
              let text = s.final?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let at = s.finishedAt, now - at < deliverWithin
        else { return nil }
        return (u, text)
    }

    // MARK: Words into a field

    /// Heard words as typed ones: spaced from the text either side, a
    /// capital where a sentence starts and none mid-sentence (the
    /// recognizer capitalizes every utterance's first word).
    static func fitted(_ heard: String, before: String, after: String) -> String {
        var text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        let startsSentence = trimmedBefore.isEmpty
            || trimmedBefore.hasSuffix("\n")
            || [".", "!", "?"].contains(where: { trimmedBefore.hasSuffix($0) })
        if startsSentence {
            text = text.prefix(1).uppercased() + text.dropFirst()
        } else if let first = text.split(separator: " ").first {
            let word = String(first)
            let keep = word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’")
                || (word.count > 1 && word.dropFirst().contains(where: \.isUppercase))
            if !keep { text = text.prefix(1).lowercased() + text.dropFirst() }
            // Mid-sentence words end without the full stop the recognizer
            // put on them when the sentence carries on after the cursor.
            if let next = after.first, next.isLetter || next.isNumber, text.hasSuffix(".") {
                text.removeLast()
            }
        }
        if let last = before.last, !last.isWhitespace,
           !["(", "[", "\"", "“", "'"].contains(String(last)) {
            text = " " + text
        }
        if let next = after.first, next.isLetter || next.isNumber {
            text += " "
        }
        return text
    }

    // MARK: Files

    private static func url(_ name: String) -> URL? {
        AppGroupStore.bridgeDir?.appendingPathComponent(name)
    }

    private static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let u = url(name), let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private static func write<T: Encodable>(_ value: T, _ name: String) -> Bool {
        guard let u = url(name), let data = try? JSONEncoder().encode(value) else { return false }
        return (try? data.write(to: u, options: .atomic)) != nil
    }

    static func readState() -> State? { read(State.self, stateFile) }

    /// App side: the new state, then the note that says so.
    static func publish(_ s: State) {
        write(s, stateFile)
        post(stateNote)
    }

    static func readCommand() -> Command? { read(Command.self, commandFile) }

    /// Keyboard side: the command, then the note that wakes the app.
    @discardableResult
    static func send(_ c: Command) -> Bool {
        guard write(c, commandFile) else { return false }
        post(commandNote)
        return true
    }

    static func readTaken() -> String? {
        read([String: String].self, takenFile)?["utterance"]
    }

    static func markTaken(_ utterance: String) {
        write(["utterance": utterance], takenFile)
    }

    // MARK: Darwin notifications

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// Darwin notifications carry no payload and take a C callback, so one
/// object owns the observers and hands each note to its handler on main.
final class DarwinBus {
    static let shared = DarwinBus()
    private var handlers: [String: () -> Void] = [:]

    func observe(_ name: String, _ handler: @escaping () -> Void) {
        let first = handlers[name] == nil
        handlers[name] = handler
        guard first else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let bus = Unmanaged<DarwinBus>.fromOpaque(observer).takeUnretainedValue()
                let key = name.rawValue as String
                DispatchQueue.main.async { bus.handlers[key]?() }
            },
            name as CFString, nil, .deliverImmediately)
    }

    func stop(_ name: String) {
        guard handlers.removeValue(forKey: name) != nil else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString), nil)
    }
}

/// The app's side of a session as a pure state machine: commands, recognizer
/// results and clock ticks in, the state to publish and what to do with the
/// microphone out. VoiceHost (Runner) runs the effects; RunnerTests drive it
/// with a fake clock.
struct VoiceMachine {

    enum Effect: Equatable {
        /// Start feeding the recognizer for this utterance.
        case beginCapture(String)
        /// Stop feeding it and let it finish.
        case endCapture(String)
        /// Throw the utterance away.
        case abortCapture
        /// Session over: stop the engine, let the microphone go.
        case shutDown
        /// Write `state` and post `stateNote`.
        case publish
    }

    private(set) var state: VoiceLink.State
    /// Commands already acted on (a note can arrive twice for one file).
    private var handled: [String] = []
    let idleLifetime: TimeInterval
    let maxUtterance: TimeInterval

    init(now: Double, idleLifetime: TimeInterval = VoiceLink.idleLifetime,
         maxUtterance: TimeInterval = VoiceLink.maxUtterance) {
        state = .off(now: now)
        self.idleLifetime = idleLifetime
        self.maxUtterance = maxUtterance
    }

    var isOn: Bool { state.phase != .off }

    /// The app came up for the keyboard (or the person opened a session).
    /// `listenNow`: the mic tap that opened the app is the first utterance.
    mutating func open(session: String, now: Double, listenNow: String?, engine: String?) -> [Effect] {
        var fx: [Effect] = []
        if state.phase == .off {
            state = VoiceLink.State(session: session, phase: .ready, heartbeat: now,
                                    expiresAt: now + idleLifetime, engine: engine)
        } else {
            state.expiresAt = now + idleLifetime
            state.heartbeat = now
        }
        if let u = listenNow, state.phase == .ready, !handled.contains(u) {
            remember(u)
            fx += begin(u, now: now)
        }
        return fx + [.publish]
    }

    mutating func handle(_ c: VoiceLink.Command, now: Double) -> [Effect] {
        guard !handled.contains(c.id) else { return [] }
        remember(c.id)
        guard state.phase != .off else { return [] }
        state.heartbeat = now
        switch c.verb {
        case .start:
            guard state.phase == .ready else { return [] }
            return begin(c.id, now: now) + [.publish]
        case .stop:
            guard state.phase == .listening, c.utterance == nil || c.utterance == state.utterance,
                  let u = state.utterance else { return [] }
            state.phase = .finishing
            state.since = now
            return [.endCapture(u), .publish]
        case .cancel:
            guard state.phase == .listening || state.phase == .finishing else { return [] }
            state.phase = .ready
            state.partial = ""
            state.final = nil
            state.since = nil
            state.expiresAt = now + idleLifetime
            return [.abortCapture, .publish]
        case .end:
            return shutDown(now: now)
        }
    }

    mutating func partial(_ text: String, utterance: String) -> [Effect] {
        guard state.utterance == utterance,
              state.phase == .listening || state.phase == .finishing,
              text != state.partial else { return [] }
        state.partial = text
        return [.publish]
    }

    mutating func finished(_ text: String, utterance: String, now: Double) -> [Effect] {
        guard state.utterance == utterance,
              state.phase == .listening || state.phase == .finishing else { return [] }
        settle(text, now: now)
        return [.publish]
    }

    mutating func failed(_ message: String, utterance: String?, now: Double) -> [Effect] {
        guard state.phase != .off else { return [] }
        if let utterance, state.utterance != utterance { return [] }
        let heard = state.partial
        settle(heard, now: now)
        state.error = heard.isEmpty ? message : nil
        return [.abortCapture, .publish]
    }

    /// Every heartbeat. `audioFlowing`: buffers arrived lately — a session
    /// whose microphone went quiet (iOS took it) stops claiming to be alive.
    mutating func tick(now: Double, audioFlowing: Bool = true) -> [Effect] {
        guard state.phase != .off else { return [] }
        switch state.phase {
        case .ready where now >= state.expiresAt:
            return shutDown(now: now)
        case .listening where now - (state.since ?? now) >= maxUtterance:
            let u = state.utterance ?? ""
            state.phase = .finishing
            state.since = now
            state.heartbeat = now
            return [.endCapture(u), .publish]
        case .finishing where now - (state.since ?? now) >= VoiceLink.finishTimeout:
            // The recognizer never said it was done: what it heard stands.
            settle(state.partial, now: now)
            state.heartbeat = now
            return [.abortCapture, .publish]
        default:
            break
        }
        guard audioFlowing else { return [] }
        state.heartbeat = now
        return [.publish]
    }

    /// The person (or the app) ends the session.
    mutating func shutDown(now: Double) -> [Effect] {
        guard state.phase != .off else { return [] }
        let session = state.session
        state = .off(now: now)
        state.session = session
        return [.abortCapture, .shutDown, .publish]
    }

    private mutating func begin(_ u: String, now: Double) -> [Effect] {
        state.phase = .listening
        state.utterance = u
        state.since = now
        state.partial = ""
        state.final = nil
        state.finishedAt = nil
        state.error = nil
        state.expiresAt = now + idleLifetime
        return [.beginCapture(u)]
    }

    private mutating func settle(_ text: String, now: Double) {
        state.phase = .ready
        state.final = text
        state.partial = text
        state.finishedAt = now
        state.since = nil
        state.heartbeat = now
        state.expiresAt = now + idleLifetime
    }

    private mutating func remember(_ id: String) {
        handled.append(id)
        if handled.count > 32 { handled.removeFirst(handled.count - 32) }
    }
}
