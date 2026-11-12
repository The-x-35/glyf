import Contacts
import Flutter
import Photos
import PhotosUI
import UIKit

/// Native side of the `so.glyf/bridge` MethodChannel.
/// Owns App Group I/O for the Flutter app, deep links, and the funnel
/// signals onboarding needs (keyboard enabled? full access granted?).
final class GlyfBridge {
    static let shared = GlyfBridge()
    private init() {}

    private var channel: FlutterMethodChannel?
    private(set) var lastDeepLink: String?
    /// Held only while the photo picker is up; it owns the reply.
    private var picking: ImagePickerCoordinator?

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "so.glyf/bridge", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        self.channel = channel
        // A renewal or a purchase finished elsewhere goes to the server too.
        Task { @MainActor in
            Billing.shared.start { [weak self] jws in
                self?.channel?.invokeMethod("onBillingUpdate", arguments: jws)
            }
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "glyf" else { return }
        lastDeepLink = url.absoluteString
        channel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // Plus and Max (Billing.swift): the store's prices, Apple's purchase
        // sheet, and the signed transactions the server checks.
        case "billingProducts":
            let ids = (call.arguments as? [String: Any])?["ids"] as? [String] ?? []
            Task { @MainActor in
                do {
                    result(try await Billing.shared.products(ids: ids))
                } catch {
                    result(FlutterError(code: "store", message: error.localizedDescription, details: nil))
                }
            }
        case "billingPurchase":
            let args = call.arguments as? [String: Any]
            let token = (args?["accountToken"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                result(await Billing.shared.purchase(id: args?["id"] as? String ?? "", accountToken: token))
            }
        case "billingEntitlements":
            Task { @MainActor in result(await Billing.shared.entitlements()) }
        case "billingRestore":
            Task { @MainActor in result(await Billing.shared.restore()) }
        case "groupPath":
            result(AppGroupStore.containerURL?.path)
        case "readKeyboardPing":
            result(jsonString(AppGroupStore.readKeyboardPing()))
        case "writeAppPong":
            let args = call.arguments as? [String: Any]
            result(AppGroupStore.writeAppPong(message: args?["message"] as? String ?? "pong"))
        case "lastDeepLink":
            // Taken once: the app reads it at start for the link that launched it.
            result(lastDeepLink)
            lastDeepLink = nil
        // §6.18 funnel signals
        case "keyboardEnabled":
            // Derived, not hardcoded: it survives bundle-id changes (the app
            // was so.glyf.app, then com.demo.glyf, and ships as com.arpit.glyf).
            let kbId = (Bundle.main.bundleIdentifier ?? "com.arpit.glyf") + ".keyboard"
            let enabled = UITextInputMode.activeInputModes.contains {
                $0.value(forKey: "identifier") as? String == kbId
            }
            result(enabled)
        case "openSettings":
            // The only supported way in. iOS shows the app's own page when the
            // app has one — which is why this app ships a Settings bundle.
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
        case "openMetaMask":
            // MetaMask's own deeplinks (lib/evm/metamask_link.dart): false
            // when MetaMask isn't installed to take one.
            if let s = (call.arguments as? [String: Any])?["url"] as? String,
               let url = URL(string: s), url.scheme == "metamask" {
                UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
            } else {
                result(false)
            }
        case "openPhantom":
            // Phantom's universal links, opened only by the Phantom app: false
            // when it isn't installed, never a detour through Safari.
            guard let s = (call.arguments as? [String: Any])?["url"] as? String,
                  let url = URL(string: s), url.host == "phantom.app" else { return result(false) }
            UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
                result(opened)
            }
        case "walletSecretLoad":
            let name = (call.arguments as? [String: Any])?["name"] as? String ?? ""
            result(name.isEmpty ? nil : WalletSecrets.load(name))
        case "walletSecretSave":
            let args = call.arguments as? [String: Any]
            let name = args?["name"] as? String ?? ""
            let value = args?["value"] as? String ?? ""
            result(!name.isEmpty && WalletSecrets.save(name, value))
        case "walletSecretClear":
            let name = (call.arguments as? [String: Any])?["name"] as? String ?? ""
            if !name.isEmpty { WalletSecrets.clear(name) }
            result(true)
        case "documentsPath":
            result(FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first?.path)
        case "launchArgs":
            result(ProcessInfo.processInfo.arguments)
        // Signing in (SignIn.swift): the provider's ID token comes back for the
        // server to check; the Glyf session it returns lives in the Keychain.
        case "signInApple":
            let nonce = (call.arguments as? [String: Any])?["nonce"] as? String ?? ""
            SignIn.shared.apple(nonce: nonce) { result($0) }
        case "signInGoogle":
            let args = call.arguments as? [String: Any]
            SignIn.shared.google(clientId: args?["clientId"] as? String ?? "",
                                 nonce: args?["nonce"] as? String ?? "") { result($0) }
        // Google Calendar and Meet for the keyboard (GoogleAccess): the grant
        // stays on the phone and the keyboard talks to Google itself.
        case "googleStatus":
            result(SignIn.googleStatus())
        case "googleConnect":
            let args = call.arguments as? [String: Any]
            SignIn.shared.connectGoogle(clientId: args?["clientId"] as? String ?? "",
                                        loginHint: args?["loginHint"] as? String) { result($0) }
        case "googleDisconnect":
            SignIn.shared.disconnectGoogle { result(true) }
        case "signOutProviders":
            // Signing out takes the Calendar and Meet grant with it, and the
            // keyboard's copy of that account's calendar.
            if let dir = AppGroupStore.bridgeDir {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("google-calendar.json"))
            }
            SignIn.shared.disconnectGoogle { result(true) }
        case "sessionLoad":
            result(SessionKeychain.load())
        case "sessionSave":
            let json = (call.arguments as? [String: Any])?["json"] as? String ?? ""
            result(!json.isEmpty && SessionKeychain.save(json))
        case "sessionClear":
            SessionKeychain.clear()
            result(true)
        // Delete account, on the phone (below).
        case "eraseLocalData":
            result(eraseLocalData())
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
                // The native store's cached copy is now stale; the next
                // native update must start from this file, not overwrite it.
                SettingsStore.invalidate()
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
        // Images live beside the fields, sealed with the same key but each in
        // its own file — the app sends raw bytes and gets raw bytes back.
        case "vaultAddImage":
            let a = call.arguments as? [String: Any]
            guard let data = (a?["bytes"] as? FlutterStandardTypedData)?.data else {
                result(["ok": false, "error": "No image data"])
                return
            }
            let error = VaultStore.shared.addImage(
                data: data, label: a?["label"] as? String ?? "Image")
            result(["ok": error == nil, "error": error as Any])
        case "vaultPickImage":
            pickImageIntoVault(label: (call.arguments as? [String: Any])?["label"] as? String
                                      ?? "Image", result: result)
        case "vaultImageData":
            let id = (call.arguments as? [String: Any])?["id"] as? String ?? ""
            if let data = VaultStore.shared.imageData(id: id) {
                result(FlutterStandardTypedData(bytes: data))
            } else {
                result(nil)
            }
        case "vaultDeleteImage":
            VaultStore.shared.deleteImage(
                id: (call.arguments as? [String: Any])?["id"] as? String ?? "")
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
        // Screenshots in the keyboard's clipboard: the app asks for Photos;
        // the keyboard then lists the last two days' screenshots.
        case "screenshotAccess":
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async { result(status == .authorized || status == .limited) }
            }
        // The phone's calendar for the keyboard's Calendar panel: the app asks,
        // keeps the coming weeks in the App Group, the keyboard reads them.
        case "calendarStatus":
            result(jsonString([
                "enabled": CalendarSync.shared.enabled,
                "permission": CalendarSync.shared.permission,
            ]))
        case "calendarEnable":
            CalendarSync.shared.enable { [weak self] outcome in
                result(self?.jsonString(outcome))
            }
        case "calendarDisable":
            CalendarSync.shared.disable()
            result(true)
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

// MARK: - Delete account: nothing of theirs left on the phone

extension GlyfBridge {
    /// Delete account's last step, after the server has deleted the account:
    ///
    /// - every Keychain item the app can reach, in its own group and the one
    ///   it shares with the keyboard: the Glyf session, the vault key (so a
    ///   vault file could never be opened again anyway), the Google grant,
    ///   the wallet's Phantom keys;
    /// - the App Group: settings.json, onboarding, the vault, notes,
    ///   clipboard history, learned words and phrases, the contacts index,
    ///   the calendar copy, voice and funnel files, and its defaults;
    /// - the app's own Documents, Application Support, tmp and defaults
    ///   (telemetry log, funnel marks);
    /// - in-memory copies here, and a "reset" edit for the learned words a
    ///   keyboard still running holds in memory: it replays the edit log
    ///   each time it opens (TypingStore.applyAppEdits).
    ///
    /// The keyboard extension's own defaults (game best scores) live in its
    /// sandbox, out of the app's reach. False when something could not be
    /// removed.
    func eraseLocalData() -> Bool {
        var ok = true
        for secClass in [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassKey,
                         kSecClassCertificate, kSecClassIdentity] {
            // No access group named: every group this app is entitled to.
            let query: [String: Any] = [
                kSecClass as String: secClass,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound { ok = false }
        }

        let fm = FileManager.default
        func empty(_ dir: URL?, keeping keep: Set<String> = []) {
            guard let dir,
                  let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { return }
            for item in items {
                let name = item.lastPathComponent
                // The system's own marker for the container stays.
                if keep.contains(name) || name.hasPrefix(".com.apple") { continue }
                do { try fm.removeItem(at: item) } catch { ok = false }
            }
        }
        if let group = AppGroupStore.containerURL {
            // bridge/ itself stays: AppGroupStore made it once for this run.
            empty(group, keeping: ["bridge", "Library"])
            empty(AppGroupStore.bridgeDir)
            empty(group.appendingPathComponent("Library/Caches"))
            empty(group.appendingPathComponent("Library/Application Support"))
        }
        UserDefaults(suiteName: AppGroupStore.groupID)?.removePersistentDomain(forName: AppGroupStore.groupID)
        for place in [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory] {
            empty(fm.urls(for: place, in: .userDomainMask).first)
        }
        empty(fm.temporaryDirectory)
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)

        SettingsStore.invalidate()
        VaultStore.shared.invalidate()
        NotesStore.shared.invalidate()
        if !appendTypingEdit(op: "reset", word: "") { ok = false }
        return ok
    }
}

// MARK: - Keeping a picture in the vault

extension GlyfBridge {
    /// Shows the system photo picker and seals whatever is chosen into the
    /// vault. `PHPickerViewController` runs in its own process and hands back
    /// only the picked image, so this needs NO photo-library permission and
    /// no Info.plist entry — the app never gets to see the library.
    func pickImageIntoVault(label: String, result: @escaping FlutterResult) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
        else {
            result(["ok": false, "error": "Nowhere to show the picker"])
            return
        }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        let coordinator = ImagePickerCoordinator(label: label) { [weak self] ok, error in
            self?.picking = nil
            result(["ok": ok, "error": error as Any])
        }
        picker.delegate = coordinator
        picking = coordinator
        root.present(picker, animated: true)
    }
}

/// PHPickerViewControllerDelegate needs an NSObject, which GlyfBridge is not.
final class ImagePickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    private let label: String
    private let done: (Bool, String?) -> Void

    init(label: String, done: @escaping (Bool, String?) -> Void) {
        self.label = label
        self.done = done
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            done(false, nil) // cancelled: nothing to report
            return
        }
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            done(false, "That image could not be read")
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [label, done] object, _ in
            // JPEG at 0.85 keeps a screenshot's text crisp and lands a photo
            // well under the vault's per-image cap, where a PNG often would not.
            guard let image = object as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85) else {
                DispatchQueue.main.async { done(false, "That image could not be read") }
                return
            }
            let error = VaultStore.shared.addImage(data: data, label: label)
            DispatchQueue.main.async { done(error == nil, error) }
        }
    }
}
