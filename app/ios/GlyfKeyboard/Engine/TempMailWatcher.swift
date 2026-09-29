import Foundation

/// Watches the temp address while the keyboard shows: asks the server on
/// TempMailRules' beat, keeps the mails in memory, and says when a new one
/// lands. The state lives in the App Group (tempmail.json), so a watch goes
/// on in the next app; a mail's words never touch the disk, and nothing here
/// ever logs an address, a sender, a subject or a code.
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
    /// What to tell the person: the server's own words when it has them.
    var onNotice: ((String) -> Void)?
    /// The panel is open: it shows new mail itself, and asks every 8 s.
    var panelOpen = false {
        didSet { if panelOpen != oldValue { reschedule() } }
    }
    /// Without Full Access a keyboard has no network: nothing to ask.
    var fullAccess = true
    /// Making or ending an address.
    private(set) var busy = false
    private var visible = false
    private var asking = false
    private var timer: Timer?
    /// The server's words when it turned the day's checks away.
    private var blockedNotice: String?

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

    /// The address, while it still exists.
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
    /// the panel. Checks turned away for today stay away.
    func restartWatch() {
        guard var s = state, address != nil else { return }
        s.watchUntil = now() + TempMailRules.watch
        s.codeAt = nil
        state = s
        save()
        changedNow()
        if let blocked = s.blockedUntil, now() < blocked {
            onNotice?(blockedNotice ?? "Try again tomorrow")
            return
        }
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
        let old = state
        BackendClient.shared.tempMail("", body: [:]) { [weak self] reply in
            guard let self else { return }
            self.busy = false
            guard reply.status == 200, reply.json?["ok"] as? Bool == true,
                  let address = reply.json?["address"] as? String,
                  let token = reply.json?["token"] as? String else {
                self.onNotice?(reply.notice)
                self.changedNow()
                return done(nil)
            }
            let expires = (reply.json?["expiresAt"] as? NSNumber)?.doubleValue ?? self.now() + 3_600_000
            var fresh = TempMailState(address: address, token: token, expiresAt: expires,
                                      watchUntil: self.now() + TempMailRules.watch)
            fresh.blockedUntil = old?.blockedUntil
            self.state = fresh
            self.messages = []
            self.openedId = nil
            self.save()
            // The one it replaces is done with.
            if let old { self.forget(old) }
            self.changedNow()
            self.look()
            done(address)
        }
    }

    /// Ends the address: gone here at once, and on the server.
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
        BackendClient.shared.tempMail("/delete", body: ["address": s.address, "token": s.token]) { _ in }
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
        asking = true
        timer?.invalidate()
        timer = nil
        BackendClient.shared.tempMail("/messages", body: ["address": s.address, "token": s.token]) { [weak self] reply in
            guard let self else { return }
            self.asking = false
            // Ended or replaced while asking: this answer is about nothing now.
            guard self.state?.address == s.address else { return self.reschedule() }
            switch reply.status {
            case 200:
                let list = (reply.json?["messages"] as? [[String: Any]] ?? [])
                    .compactMap(TempMailMessage.init(json:))
                self.take(list)
            case 403, 410:
                self.end(notice: reply.error ?? "That address has expired")
                return
            case 429:
                // No more checks today: not here, and not from another app.
                self.blockedNotice = reply.error
                self.state?.blockedUntil = TempMailRules.nextMidnight(after: Date()).timeIntervalSince1970 * 1000
                self.save()
                self.onNotice?(reply.error ?? "Try again tomorrow")
                self.changedNow()
            default:
                break   // a blip: the next look tries again
            }
            self.reschedule()
        }
    }

    private func take(_ list: [TempMailMessage]) {
        let sorted = list.sorted { $0.receivedAt > $1.receivedAt }
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

    /// Gone on the server (403, 410): the panel goes back to Create.
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

    /// An address that has run its time ends, said once. The panel asks
    /// every second too: nothing else looks once the watch is over.
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
