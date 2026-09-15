import Contacts
import Flutter
import UIKit

/// Native side of the `so.glyf/bridge` MethodChannel.
/// Owns App Group I/O for the Flutter app, deep links, and the funnel
/// signals onboarding needs (keyboard enabled? full access granted?).
final class GlyfBridge {
    static let shared = GlyfBridge()
    private init() {}

    private var channel: FlutterMethodChannel?
    private(set) var lastDeepLink: String?

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "so.glyf/bridge", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        self.channel = channel
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "glyf" else { return }
        lastDeepLink = url.absoluteString
        channel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "groupPath":
            result(AppGroupStore.containerURL?.path)
        case "readKeyboardPing":
            result(jsonString(AppGroupStore.readKeyboardPing()))
        case "writeAppPong":
            let args = call.arguments as? [String: Any]
            result(AppGroupStore.writeAppPong(message: args?["message"] as? String ?? "pong"))
        case "lastDeepLink":
            result(lastDeepLink)
        // §6.18 funnel signals
        case "keyboardEnabled":
            // Derived, not hardcoded — survives bundle-id changes (device
            // personal-team builds use com.demo.glyf, the sim so.glyf.app).
            let kbId = (Bundle.main.bundleIdentifier ?? "so.glyf.app") + ".keyboard"
            let enabled = UITextInputMode.activeInputModes.contains {
                $0.value(forKey: "identifier") as? String == kbId
            }
            result(enabled)
        case "openSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            result(true)
        case "openURL":
            // https links only (OAuth consent in the user's browser).
            if let s = (call.arguments as? [String: Any])?["url"] as? String,
               let url = URL(string: s), url.scheme == "https" {
                UIApplication.shared.open(url)
                result(true)
            } else {
                result(false)
            }
        case "documentsPath":
            result(FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first?.path)
        case "launchArgs":
            result(ProcessInfo.processInfo.arguments)
        // Shared keyboard settings (App Group settings.json).
        // Served through SettingsStore.load() so the app always sees the
        // MIGRATED view — §6.13 defaults appear even before the keyboard's
        // first run, and new fields carry their defaults.
        case "readSharedSettings":
            if let data = try? JSONEncoder().encode(SettingsStore.load()),
               let json = String(data: data, encoding: .utf8) {
                result(json)
            } else {
                result(readBridgeFile("settings.json"))
            }
        case "writeSharedSettings":
            if let args = call.arguments as? [String: Any],
               let json = args["json"] as? String,
               let dir = AppGroupStore.bridgeDir,
               let data = json.data(using: .utf8) {
                try? data.write(to: dir.appendingPathComponent("settings.json"), options: .atomic)
                result(true)
            } else {
                result(false)
            }
        case "readOnboardingState":
            result(readBridgeFile("onboarding.json"))
        // §6.6 dictation (intent handoff per §7)
        case "dictationPending":
            if let intent = IntentStore.shared.pendingIntent(), intent.kind == "dictation",
               !IntentStore.shared.isConsumed(intent.id) {
                result(intent.id)
            } else {
                result(nil)
            }
        case "dictationConsume":
            let id = (call.arguments as? [String: Any])?["id"] as? String ?? ""
            result(IntentStore.shared.consume(id: id) != nil)
        case "dictationStart":
            DictationEngine.shared.onPartial = { [weak self] text in
                self?.channel?.invokeMethod("onDictation", arguments: text)
            }
            DictationEngine.shared.start { ok, fake, error in
                result(["ok": ok, "fake": fake, "error": error as Any])
            }
        case "dictationStop":
            DictationEngine.shared.stop { transcript, latencyMs in
                result(["transcript": transcript, "latencyMs": latencyMs])
            }
        case "dictationCancel":
            DictationEngine.shared.cancel()
            result(true)
        case "dictationResult":
            let args = call.arguments as? [String: Any]
            let id = args?["intentId"] as? String ?? ""
            let transcript = args?["transcript"] as? String ?? ""
            let mode = args?["mode"] as? String ?? "raw"
            result(IntentStore.shared.writeResult(
                intentId: id, status: "success",
                payload: ["transcript": transcript, "mode": mode]))
        case "writeOnboardingState":
            if let args = call.arguments as? [String: Any],
               let json = args["json"] as? String,
               let dir = AppGroupStore.bridgeDir,
               let data = json.data(using: .utf8) {
                try? data.write(to: dir.appendingPathComponent("onboarding.json"), options: .atomic)
                result(true)
            } else {
                result(false)
            }
        // §6.7 vault — add/edit is app-only; validation runs native-side.
        case "vaultList":
            let v = VaultStore.shared.load()
            if let data = try? JSONEncoder().encode(v),
               let json = String(data: data, encoding: .utf8) {
                result(json)
            } else {
                result(nil)
            }
        case "vaultUpsertField":
            let a = call.arguments as? [String: Any]
            let error = VaultStore.shared.upsertField(
                id: a?["id"] as? String,
                kind: a?["kind"] as? String ?? "custom",
                label: a?["label"] as? String ?? "",
                value: a?["value"] as? String ?? "")
            result(["ok": error == nil, "error": error as Any])
        case "vaultDeleteField":
            VaultStore.shared.deleteField(id: (call.arguments as? [String: Any])?["id"] as? String ?? "")
            result(true)
        case "vaultUpsertCombo":
            let a = call.arguments as? [String: Any]
            let error = VaultStore.shared.upsertCombo(
                id: a?["id"] as? String,
                label: a?["label"] as? String ?? "",
                fieldIds: (a?["fieldIds"] as? [String]) ?? [])
            result(["ok": error == nil, "error": error as Any])
        case "vaultDeleteCombo":
            VaultStore.shared.deleteCombo(id: (call.arguments as? [String: Any])?["id"] as? String ?? "")
            result(true)
        case "vaultUpsertSnippet":
            let a = call.arguments as? [String: Any]
            let error = VaultStore.shared.upsertSnippet(
                trigger: a?["trigger"] as? String ?? "",
                text: a?["text"] as? String ?? "")
            result(["ok": error == nil, "error": error as Any])
        case "vaultDeleteSnippet":
            VaultStore.shared.deleteSnippet(
                trigger: (call.arguments as? [String: Any])?["trigger"] as? String ?? "")
            result(true)
        // Notes — written in the app, inserted from the keyboard shell.
        case "notesList":
            NotesStore.shared.invalidate()
            let notes = NotesStore.shared.load()
            if let data = try? { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
                                 return try e.encode(notes) }(),
               let json = String(data: data, encoding: .utf8) {
                result(json)
            } else {
                result("[]")
            }
        case "notesUpsert":
            let a = call.arguments as? [String: Any]
            let error = NotesStore.shared.upsert(
                id: a?["id"] as? String, text: a?["text"] as? String ?? "")
            result(["ok": error == nil, "error": error as Any])
        case "notesDelete":
            NotesStore.shared.delete(
                id: (call.arguments as? [String: Any])?["id"] as? String ?? "")
            result(true)
        // Typing engine: the words the keyboard learned ("My words"), edits
        // the keyboard applies next time it opens, and AI-made packs.
        case "typingWords":
            result(readBridgeFile("typing-memory.json"))
        case "typingEdit":
            let args = call.arguments as? [String: Any] ?? [:]
            guard let op = args["op"] as? String, ["add", "forget", "reset"].contains(op) else {
                result(false)
                return
            }
            result(appendTypingEdit(op: op, word: args["word"] as? String ?? ""))
        case "vocabCustomRead":
            result(readBridgeFile("vocab-custom.json"))
        case "vocabCustomWrite":
            if let json = (call.arguments as? [String: Any])?["json"] as? String,
               let dir = AppGroupStore.bridgeDir, let data = json.data(using: .utf8) {
                try? data.write(to: dir.appendingPathComponent("vocab-custom.json"), options: .atomic)
                result(true)
            } else {
                result(false)
            }
        // §6.15 tone profile — inspectable + deletable from the app.
        case "toneProfile":
            let counts = ToneProfile.load()
            result(jsonString([
                "accepted": counts.accepted,
                "discarded": counts.discarded,
                "hint": ToneProfile.hint(from: counts)
                    .trimmingCharacters(in: .whitespaces),
            ]))
        case "toneReset":
            ToneProfile.reset()
            result(true)

        // §6.12 Contacts search (Gboard parity): the APP owns the permission
        // and syncs a minimal name/phone/email index into the App Group; the
        // keyboard only ever reads that local file.
        case "contactsStatus":
            let auth = CNContactStore.authorizationStatus(for: .contacts)
            let file = AppGroupStore.bridgeDir?
                .appendingPathComponent("contacts.json")
            let enabled = file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            result(jsonString([
                "enabled": enabled,
                "permission": auth == .authorized ? "granted"
                    : auth == .notDetermined ? "notDetermined" : "denied",
            ]))
        case "contactsEnable":
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard granted, let self else {
                        result(self?.jsonString(["ok": false, "error": "denied"]))
                        return
                    }
                    result(self.jsonString(self.syncContacts(store: store)))
                }
            }
        case "contactsDisable":
            if let url = AppGroupStore.bridgeDir?.appendingPathComponent("contacts.json") {
                try? FileManager.default.removeItem(at: url)
            }
            result(true)

        // §6.12 "near me": a keyboard extension cannot ask for location, so
        // the APP asks once, caches a COARSE fix in the App Group, and the
        // keyboard forwards it with place searches. Nothing is stored on the
        // server, and turning it off clears the cached coordinates.
        case "locationStatus":
            let auth = LocationOnce.shared.authorization
            let s = SettingsStore.current
            result(jsonString([
                "enabled": s.lastLat != nil && s.lastLon != nil,
                "permission": auth,
            ]))
        case "locationEnable":
            LocationOnce.shared.request { [weak self] outcome in
                switch outcome {
                case .denied:
                    result(self?.jsonString(["ok": false, "error": "denied"]))
                case .failed:
                    result(self?.jsonString(["ok": false, "error": "unavailable"]))
                case .fix(let lat, let lon):
                    SettingsStore.update {
                        $0.lastLat = lat
                        $0.lastLon = lon
                        $0.region = Locale.current.regionCode
                    }
                    result(self?.jsonString(["ok": true, "lat": lat, "lon": lon]))
                }
            }
        case "locationDisable":
            SettingsStore.update {
                $0.lastLat = nil
                $0.lastLon = nil
            }
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Fetches givenName/familyName + phones + emails and writes the shared
    /// index. Runs on the calling (main) thread over ≤2000 contacts.
    private func syncContacts(store: CNContactStore) -> [String: Any] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        ] as [CNKeyDescriptor]
        let req = CNContactFetchRequest(keysToFetch: keys)
        var rows: [[String: Any]] = []
        do {
            try store.enumerateContacts(with: req) { c, stop in
                let name = "\(c.givenName) \(c.familyName)"
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                rows.append([
                    "name": name,
                    "phones": c.phoneNumbers.map { $0.value.stringValue },
                    "emails": c.emailAddresses.map { String($0.value) },
                ])
                if rows.count >= 2000 { stop.pointee = true }
            }
        } catch {
            return ["ok": false, "error": "read failed"]
        }
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONSerialization.data(withJSONObject: rows)
        else { return ["ok": false, "error": "store failed"] }
        do {
            try data.write(to: dir.appendingPathComponent("contacts.json"),
                           options: .atomic)
        } catch { return ["ok": false, "error": "store failed"] }
        return ["ok": true, "count": rows.count]
    }

    /// Appends to the edit log the keyboard replays (TypingStore.applyAppEdits).
    /// Old entries are dropped once the keyboard has had a month to see them.
    private func appendTypingEdit(op: String, word: String) -> Bool {
        guard let dir = AppGroupStore.bridgeDir else { return false }
        let url = dir.appendingPathComponent("typing-edits.json")
        let now = Date().timeIntervalSince1970 * 1000
        var edits = ((try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["edits"] as? [[String: Any]]) ?? []
        edits = edits.filter { now - ($0["at"] as? Double ?? 0) < 30 * 86_400_000 }.suffix(400)
        edits.append(["op": op, "word": word, "at": now])
        guard let data = try? JSONSerialization.data(withJSONObject: ["edits": edits]) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    private func readBridgeFile(_ name: String) -> String? {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(name))
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func jsonString(_ dict: [String: Any]?) -> String? {
        guard let dict,
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
