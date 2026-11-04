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

    /// How long the microphone stays open after an utterance ends (or is
    /// cancelled) before the app lets it go: the orange dot goes with it
    /// (Arpit, 2026-11-04: "having it open in the background is a very bad
    /// way ... just open it only when the user asks for voice typing"). The
    /// next mic tap opens Glyf again for a moment. Earlier: forever, an
    /// hour, 5 minutes.
    static let idleLifetime: TimeInterval? = 2
    /// `State.expiresAt` of a session with no idle end (2100-01-01): kept a
    /// plain number so the file reads the same for every app version.
    static let never: Double = 4_102_444_800

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

    /// glyf://voice?u=<utterance>&h=<host bundle id>. `h` is the app the
    /// keyboard was typing in, when the keyboard could tell (HostAppID):
    /// the app goes back to it once listening is on (`returnURL`).
    static func openURL(utterance: String?, host: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "glyf"
        c.host = "voice"
        var q: [URLQueryItem] = []
        if let utterance { q.append(URLQueryItem(name: "u", value: utterance)) }
        if let host, !host.isEmpty { q.append(URLQueryItem(name: "h", value: host)) }
        if !q.isEmpty { c.queryItems = q }
        return c.url!
    }

    // MARK: Back to the app the keyboard was in

    /// An app the voice link can send the person back to: its own URL
    /// scheme opens it where it was (public `UIApplication.open`, no
    /// LSApplicationQueriesSchemes needed to open). Safari is left out on
    /// purpose: every Safari URL opens a new page rather than the tab the
    /// person was typing in, so Safari gets the "go back" line instead.
    struct ReturnApp: Equatable {
        let name: String
        let url: URL
    }

    /// Bundle id → (display name, URL that opens it).
    static let returnApps: [String: (name: String, url: String)] = [
        "com.apple.MobileSMS": ("Messages", "sms:"),
        "com.apple.mobilemail": ("Mail", "message:"),
        "com.apple.mobilenotes": ("Notes", "mobilenotes://"),
        "com.apple.mobilecal": ("Calendar", "calshow://"),
        "com.apple.reminders": ("Reminders", "x-apple-reminderkit://"),
        "com.apple.Maps": ("Maps", "maps://"),
        "net.whatsapp.WhatsApp": ("WhatsApp", "whatsapp://"),
        "net.whatsapp.WhatsAppSMB": ("WhatsApp Business", "whatsapp-smb://"),
        "ph.telegra.Telegraph": ("Telegram", "tg://"),
        "org.whispersystems.signal": ("Signal", "sgnl://"),
        "com.facebook.Messenger": ("Messenger", "fb-messenger://"),
        "com.facebook.Facebook": ("Facebook", "fb://"),
        "com.burbn.instagram": ("Instagram", "instagram://"),
        "com.burbn.barcelona": ("Threads", "barcelona://"),
        "com.atebits.Tweetie2": ("X", "twitter://"),
        "xyz.blueskyweb.app": ("Bluesky", "bluesky://"),
        "com.toyopagroup.picaboo": ("Snapchat", "snapchat://"),
        "com.reddit.Reddit": ("Reddit", "reddit://"),
        "com.linkedin.LinkedIn": ("LinkedIn", "linkedin://"),
        "com.hammerandchisel.discord": ("Discord", "discord://"),
        "com.tinyspeck.chatlyio": ("Slack", "slack://"),
        "com.microsoft.skype.teams": ("Teams", "msteams://"),
        "com.microsoft.Office.Outlook": ("Outlook", "ms-outlook://"),
        "com.google.Gmail": ("Gmail", "googlegmail://"),
        "com.google.chrome.ios": ("Chrome", "googlechrome://"),
        "com.google.GoogleMobile": ("Google", "google://"),
        "notion.id": ("Notion", "notion://"),
        "jp.naver.line": ("LINE", "line://"),
        "com.viber": ("Viber", "viber://"),
    ]

    /// Where to send the person after Glyf opened for voice, or nil: the
    /// app shows its one "go back" line instead.
    static func returnApp(forHost bundleID: String?) -> ReturnApp? {
        guard let id = bundleID?.trimmingCharacters(in: .whitespaces), !id.isEmpty,
              let entry = returnApps[id], let url = URL(string: entry.url)
        else { return nil }
        return ReturnApp(name: entry.name, url: url)
    }

    /// The voice link's two values: the utterance to hear at once and the
    /// host app's bundle id.
    static func parseOpenURL(_ url: URL) -> (utterance: String?, host: String?) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        return (value("u"), value("h"))
    }

    /// Glyf goes back once listening is on: at least `returnAfter` after
    /// the link came (the person sees the app take it), and only once audio
    /// is coming in. With no audio by `returnGiveUp`, it stays (Wispr Flow
    /// does the same at about 2 s) and shows the line.
    static let returnAfter: TimeInterval = 0.6
    static let returnGiveUp: TimeInterval = 2.0

    /// Whether to go back now, wait, or give up.
    enum ReturnStep: Equatable { case wait, go, stay }

    static func returnStep(sinceOpen: TimeInterval, audioFlowing: Bool) -> ReturnStep {
        if sinceOpen >= returnGiveUp { return audioFlowing ? .go : .stay }
        guard sinceOpen >= returnAfter else { return .wait }
        return audioFlowing ? .go : .wait
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
        /// The microphone's loudness, 0…1 (`normalizedLevel`), written about
        /// 16 times a second while listening so the keyboard's wave moves
        /// with the voice. Nil from an app that predates it.
        var level: Float?

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

    // MARK: Level

    /// How often the app writes `State.level` while listening.
    static let levelEvery: TimeInterval = 1.0 / 16
    /// A level that moved less than this is not worth a write.
    static let levelStep: Float = 0.03

    /// A buffer's RMS as 0…1 on a decibel scale: -55 dB (a quiet room) is
    /// nothing, -12 dB (speaking close) is full.
    static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0, rms.isFinite else { return 0 }
        let db = 20 * log10(rms)
        let v = (db + 55) / 43
        return min(1, max(0, v))
    }

    // MARK: Style (the panel's pill)

    /// How the words read when ✓ puts them in. As spoken is the
    /// recognizer's own text; the rest run one existing server glyf on ✓.
    enum Style: String, CaseIterable, Codable {
        case asSpoken, clean, formal, casual, excited

        static let standard: Style = .asSpoken

        /// The pill's word.
        var title: String {
            switch self {
            case .asSpoken: return "As spoken"
            case .clean: return "Clean"
            case .formal: return "Formal"
            case .casual: return "Casual"
            case .excited: return "Excited"
            }
        }

        /// The menu's row, written the way it reads (Wispr's menu does this).
        var menuTitle: String {
            switch self {
            case .formal: return "Formal."
            case .excited: return "Excited!"
            default: return title
            }
        }

        /// The server glyf and its vars, or nil: nothing is sent.
        var run: (glyfId: String, vars: [String: String])? {
            switch self {
            case .asSpoken: return nil
            case .clean: return ("dictation.clean", [:])
            case .formal: return ("dictation.formal", [:])
            case .casual: return ("rewrite.tone", ["tone": "casual, relaxed, like a text to a friend"])
            case .excited: return ("rewrite.tone", ["tone": "excited, upbeat and warm"])
            }
        }

        /// A stored value, or the default for anything unknown.
        static func from(_ raw: String?) -> Style {
            raw.flatMap(Style.init(rawValue:)) ?? standard
        }
    }

    /// The model's text in place of what was said: no quotes or labels it
    /// wrapped the answer in, and nothing when it gave back nothing.
    static func polished(original: String, cleaned: String) -> String {
        var t = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["Cleaned text:", "Rewritten text:", "Rewritten:", "Message:", "Transcript:"]
        where t.hasPrefix(label) {
            t = String(t.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
        for (open, close) in pairs where t.count >= 2 && t.first == open && t.last == close {
            let inner = t.dropFirst().dropLast()
            // Only quotes around the whole answer, not a quote inside it.
            if !inner.contains(open) && !inner.contains(close) {
                t = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return t.isEmpty ? original : t
    }

    // MARK: Spoken punctuation

    // Gboard's spoken punctuation (support.google.com/gboard/answer/2781851),
    // the same list Android's VoiceText reads: period or full stop, comma,
    // question mark, exclamation point or mark, new line, new paragraph.
    private static let spoken: [(NSRegularExpression, String)] = [
        ("[ ]*\\bnew paragraph\\b[ ]*", "\n\n"),
        ("[ ]*\\bnew line\\b[ ]*", "\n"),
        ("[ ]*\\b(?:period|full stop)\\b", "."),
        ("[ ]*\\bcomma\\b", ","),
        ("[ ]*\\bquestion mark\\b", "?"),
        ("[ ]*\\bexclamation (?:point|mark)\\b", "!"),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1) }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                           withTemplate: template)
    }

    /// "see you soon period" → "see you soon.". Read only when the
    /// recognizer wrote no marks of its own: one that punctuates
    /// (addsPunctuation, DictationTranscriber) already turned a said
    /// "period" into "." and left the word where it was meant.
    static func spokenPunctuation(_ text: String) -> String {
        guard !text.contains(where: { ".,!?;:".contains($0) }) else { return text }
        var out = text
        for (re, mark) in spoken {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: mark))
        }
        guard out != text else { return text }
        // A space after a mark that runs into a word, none before one.
        out = replace("([.,!?])(?=[^\\s.,!?])", in: out, with: "$1 ")
        out = replace(" +", in: out, with: " ")
        out = replace(" *\\n *", in: out, with: "\n")
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        // A capital after each sentence's end inside what was said.
        return capitalizeSentences(out)
    }

    static func capitalizeSentences(_ text: String) -> String {
        var out = ""
        var upNext = false
        for ch in text {
            if upNext, ch.isLetter {
                out += ch.uppercased()
                upNext = false
                continue
            }
            out.append(ch)
            if ".!?\n".contains(ch) { upNext = true }
            else if !ch.isWhitespace { upNext = false }
        }
        return out
    }

    /// The words as the panel shows them while they are heard: spoken
    /// punctuation read, the first letter a capital.
    static func live(_ heard: String) -> String {
        let t = spokenPunctuation(heard.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let first = t.first else { return "" }
        return first.uppercased() + t.dropFirst()
    }

    /// Two stretches the recognizer heard one after the other, as one.
    static func joined(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespaces), b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
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
    /// How long the microphone stays open with nothing being heard
    /// (`VoiceLink.idleLifetime`); nil: until Turn off.
    var idleLifetime: TimeInterval?
    let maxUtterance: TimeInterval

    init(now: Double, idleLifetime: TimeInterval? = VoiceLink.idleLifetime,
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
                                    expiresAt: expiry(now), engine: engine)
        } else {
            state.expiresAt = expiry(now)
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
            state.level = 0
            return [.endCapture(u), .publish]
        case .cancel:
            guard state.phase == .listening || state.phase == .finishing else { return [] }
            state.phase = .ready
            state.partial = ""
            state.level = 0
            state.final = nil
            state.since = nil
            state.expiresAt = expiry(now)
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

    /// The microphone's level (0…1) while an utterance is heard. Published
    /// only when it moved by `levelStep`, and back to 0 when it stops.
    mutating func level(_ value: Float) -> [Effect] {
        guard state.phase == .listening else {
            guard let old = state.level, old != 0 else { return [] }
            state.level = 0
            return [.publish]
        }
        let v = min(1, max(0, value))
        if let old = state.level, abs(old - v) < VoiceLink.levelStep { return [] }
        state.level = v
        return [.publish]
    }

    /// The recognizer ended a stretch by itself (a long pause) while the
    /// person is still talking: the utterance keeps listening, and what was
    /// heard carries into the next stretch. True when it carries on.
    func continues(utterance: String) -> Bool {
        state.utterance == utterance && state.phase == .listening
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
        let last = state
        state = .off(now: now)
        state.session = last.session
        // The words just heard are still the keyboard's to type.
        if last.final != nil {
            state.utterance = last.utterance
            state.final = last.final
            state.partial = last.partial
            state.finishedAt = last.finishedAt
        }
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
        state.expiresAt = VoiceLink.never   // a voice being heard keeps it
        return [.beginCapture(u)]
    }

    private mutating func settle(_ text: String, now: Double) {
        state.phase = .ready
        state.level = 0
        state.final = text
        state.partial = text
        state.finishedAt = now
        state.since = nil
        state.heartbeat = now
        state.expiresAt = expiry(now)
    }

    /// When an idle session ends, counted from `now`.
    func expiry(_ now: Double) -> Double {
        idleLifetime.map { now + $0 } ?? VoiceLink.never
    }

    private mutating func remember(_ id: String) {
        handled.append(id)
        if handled.count > 32 { handled.removeFirst(handled.count - 32) }
    }
}
