import Foundation

/// Watches the temp address while the keyboard shows: asks mail.tm on
/// TempMailRules' beat, reads each new mail once and keeps it in memory, and
/// says when one lands. The account lives in the App Group (tempmail.json),
/// so a watch goes on in the next app; a mail's words never touch the disk,
/// and nothing here ever logs an address, a sender, a subject or a code.
final class TempMailWatcher {
    static let shared = TempMailWatcher()
    /// Posted when the address, the watch or the inbox changed.
    static let changed = Notification.Name("glyf.tempmail.changed")
    private static let file = "tempmail.json"

    private(set) var state: TempMailState?
    /// Newest first. Memory only.
    private(set) var messages: [TempMailMessage] = []
    /// The mail the panel has open.
    var openedId: String?
    /// A mail landed while watching, the panel closed: the strip offers it.
    var onNewMail: ((TempMailMessage) -> Void)?
    /// What to tell the person.
    var onNotice: ((String) -> Void)?
    /// The panel is open: it shows new mail itself, and asks every 8 s.
    var panelOpen = false {
        didSet { if panelOpen != oldValue { reschedule() } }
    }
    /// Without Full Access a keyboard has no network: nothing to ask.
    var fullAccess = true
    /// Making an address.
    private(set) var busy = false
    private var visible = false
    private var asking = false
    private var timer: Timer?
    /// Checks in a row that got no answer (429, no connection).
    private var misses = 0

    /// mail.tm, or the stand-in a test names in settings (`tempMailBase`).
    private var mailTM: MailTM {
        _ = SettingsStore.reloadIfChanged()
        return MailTM(base: SettingsStore.current.tempMailBase)
    }

    init() {
        state = Self.load()
    }

    private static func load() -> TempMailState? {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(TempMailState.self, from: data)
    }

    private func save() {
        guard let dir = AppGroupStore.bridgeDir else { return }
        let url = dir.appendingPathComponent(Self.file)
        if let state, let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    /// The address, while it is offered.
    var address: String? {
        guard let s = state, now() < s.expiresAt else { return nil }
        return s.address
    }

    var isWatching: Bool {
        state.map { TempMailRules.watching(now: now(), state: $0, panelOpen: panelOpen) } ?? false
    }

    /// What is left of this watch, in ms.
    var watchLeft: Double { state.map { max(0, $0.watchUntil - now()) } ?? 0 }

    var openedMail: TempMailMessage? { messages.first { $0.id == openedId } }

    /// The keyboard came up, or went away: watching happens only on screen.
    func setVisible(_ on: Bool) {
        visible = on
        guard on else {
            timer?.invalidate()
            timer = nil
            return
        }
        // Another app's keyboard may have made, watched or ended it since.
        let disk = Self.load()
        if disk?.address != state?.address {
            messages = []
            openedId = nil
        }
        state = disk
        if endIfExpired() { return }
        look()
    }

    /// A fresh 15 minutes: on making the address, inserting it and opening
    /// the panel.
    func restartWatch() {
        guard var s = state, address != nil else { return }
        s.watchUntil = now() + TempMailRules.watch
        s.codeAt = nil
        state = s
        save()
        changedNow()
        look()
    }

    /// A new address (New replaces the one there): watched from now.
    func create(done: @escaping (String?) -> Void) {
        guard !busy else { return done(nil) }
        guard fullAccess else {
            onNotice?("Turn on Full Access to use temp mail")
            changedNow()
            return done(nil)
        }
        busy = true
        changedNow()
        mailTM.create { [weak self] result in
            guard let self else { return }
            self.busy = false
            switch result {
            case .failure(let failure):
                self.onNotice?(Self.notice(failure.status))
                self.changedNow()
                done(nil)
            case .success(let made):
                let old = self.state
                let at = self.now()
                self.state = TempMailState(address: made.address, password: made.password, token: made.token,
                                           accountId: made.id, createdAt: at, watchUntil: at + TempMailRules.watch)
                self.messages = []
                self.openedId = nil
                self.misses = 0
                self.save()
                // The one it replaces is done with.
                if let old { self.forget(old) }
                self.changedNow()
                self.look()
                done(made.address)
            }
        }
    }

    /// What to say when mail.tm didn't make one.
    private static func notice(_ status: Int) -> String {
        switch status {
        case 0: return "Couldn't reach temp mail. Check the connection"
        case 429: return "Temp mail is busy. Try again in a minute"
        default: return "Temp mail didn't answer. Try again in a moment"
        }
    }

    /// Ends the address: gone here at once, and at mail.tm.
    func delete() {
        guard let s = state else { return }
        state = nil
        messages = []
        openedId = nil
        save()
        timer?.invalidate()
        timer = nil
        forget(s)
        changedNow()
    }

    private func forget(_ s: TempMailState) {
        mailTM.authed("DELETE", "/accounts/\(s.accountId)", address: s.address, password: s.password,
                      token: s.token) { _, _, _ in }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard visible, fullAccess, !asking, let s = state,
              let wait = TempMailRules.interval(now: now(), state: s, panelOpen: panelOpen) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            self?.look()
        }
    }

    /// Asks for the inbox now, then again on the beat.
    private func look() {
        guard visible, fullAccess, !asking, let s = state else { return }
        if endIfExpired() { return }
        guard TempMailRules.watching(now: now(), state: s, panelOpen: panelOpen) else {
            changedNow()   // the line turns to Stopped
            return
        }
        // Paused after three misses: the timer waits it out.
        if let paused = s.blockedUntil, now() < paused { return reschedule() }
        asking = true
        timer?.invalidate()
        timer = nil
        ask(s, "GET", "/messages?page=1") { [weak self] reply in
            guard let self else { return }
            guard let reply, reply.status == 200, let list = reply.list else {
                self.asking = false
                if reply != nil { self.missed() }
                return self.reschedule()
            }
            self.misses = 0
            let ids = list.compactMap { $0["id"] as? String }
            let known = Set(self.messages.map(\.id))
            // A mail is read once, when it first shows up; a new keyboard
            // (its memory empty) reads the newest again.
            let unread = Array(ids.filter { !known.contains($0) }.prefix(20))
            self.read(unread, of: s, into: []) { fetched in
                self.asking = false
                guard self.state?.address == s.address else { return self.reschedule() }
                self.take(ids: ids, fetched: fetched)
                self.reschedule()
            }
        }
    }

    /// A call with the address's token; nil when there is nothing to ask
    /// about any more (ended, or replaced while asking). A second 401 ends
    /// the address.
    private func ask(_ s: TempMailState, _ method: String, _ path: String,
                     done: @escaping (MailTM.Reply?) -> Void) {
        let current = state ?? s
        mailTM.authed(method, path, address: current.address, password: current.password,
                      token: current.token) { [weak self] reply, gone, fresh in
            guard let self, self.state?.address == s.address else { return done(nil) }
            if gone {
                self.end(notice: "That address has expired")
                return done(nil)
            }
            if let fresh {
                self.state?.token = fresh
                self.save()
            }
            done(reply)
        }
    }

    /// Reads each mail in turn (mail.tm counts requests); one that doesn't
    /// come is asked for again on the next look.
    private func read(_ ids: [String], of s: TempMailState, into got: [TempMailMessage],
                      done: @escaping ([TempMailMessage]) -> Void) {
        guard let id = ids.first else { return done(got) }
        ask(s, "GET", "/messages/\(id)") { [weak self] reply in
            guard let self, let reply else { return done(got) }
            switch reply.status {
            case 200:
                let mail = reply.object.flatMap(TempMailMessage.init(mailTM:))
                self.read(Array(ids.dropFirst()), of: s, into: got + [mail].compactMap { $0 }, done: done)
            case 404:
                // Deleted since the list: nothing to read.
                self.read(Array(ids.dropFirst()), of: s, into: got, done: done)
            default:
                self.missed()
                done(got)
            }
        }
    }

    /// A check with no answer (429, no connection): skipped, and three in a
    /// row pause checking for a minute.
    private func missed() {
        misses += 1
        guard misses >= TempMailRules.missesToPause else { return }
        misses = 0
        state?.blockedUntil = now() + TempMailRules.pause
        save()
    }

    /// The inbox as mail.tm lists it, each mail read once.
    private func take(ids: [String], fetched: [TempMailMessage]) {
        var byId = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for mail in fetched { byId[mail.id] = mail }
        let sorted = ids.compactMap { byId[$0] }.sorted { $0.receivedAt > $1.receivedAt }
        let changed = sorted.map(\.id) != messages.map(\.id)
        messages = sorted
        guard var s = state else { return }
        let fresh = sorted.filter { !s.seenIds.contains($0.id) }
        if !fresh.isEmpty {
            s.seenIds = Array((s.seenIds + fresh.map(\.id)).suffix(200))
            if s.codeAt == nil, fresh.contains(where: { $0.code != nil }) { s.codeAt = now() }
            state = s
            save()
            // The panel shows new mail itself; otherwise the strip offers the newest.
            if !panelOpen, let newest = fresh.first { onNewMail?(newest) }
        }
        if changed || !fresh.isEmpty { changedNow() }
    }

    /// Gone at mail.tm (a second 401), or its day is over: the panel goes
    /// back to Create.
    private func end(notice: String) {
        state = nil
        messages = []
        openedId = nil
        save()
        timer?.invalidate()
        timer = nil
        onNotice?(notice)
        changedNow()
    }

    /// An address whose day is over ends, said once. The panel asks every
    /// second too: nothing else looks once the watch is over.
    @discardableResult
    func endIfExpired() -> Bool {
        guard let s = state, now() >= s.expiresAt else { return false }
        end(notice: "That address has expired")
        return true
    }

    private func changedNow() {
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
