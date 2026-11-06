import UIKit

/// Everything the typing engine knows on this iPhone, loaded once per
/// keyboard process and saved as it learns:
///  · the base dictionary, memory-mapped from the extension bundle
///  · the vocabulary packs switched on in the app
///  · what this person types (PersonalLexicon) — never leaves the device and
///    is excluded from iCloud backup
///  · iOS's supplementary lexicon: contact names and text replacements
///
/// Learned words live in the shared App Group when Full Access is on (so
/// the app can show "My words"), otherwise in the extension's own container.
final class TypingStore {

    static let shared = TypingStore()

    /// The letter rows on screen (LetterLayout.rows), so the corrector's key
    /// distances are the keys the person actually sees.
    var letterRows: [String] = KeyGeometry.rows {
        didSet {
            guard letterRows != oldValue else { return }
            engine?.geometry = KeyGeometry(rows: letterRows)
        }
    }

    private(set) var engine: TypingEngine?
    /// iOS Text Replacements: shortcut (lowercased) → phrase.
    private(set) var replacements: [String: String] = [:]

    private static let lexiconFile = "typing-memory.json"
    private static let editsFile = "typing-edits.json"
    private static let customPacksFile = "vocab-custom.json"

    private var packSignature = ""
    private var hasFullAccess = false
    private var saveWork: DispatchWorkItem?
    private var loading = false
    private var waiting: [(TypingEngine) -> Void] = []
    private let io = DispatchQueue(label: "so.glyf.typing", qos: .userInitiated)

    /// Calls `ready` on the main queue once the engine exists — immediately
    /// on every appearance after the first.
    func prepare(hasFullAccess: Bool, lexicon: @escaping (@escaping (UILexicon) -> Void) -> Void,
                 ready: @escaping (TypingEngine) -> Void) {
        self.hasFullAccess = hasFullAccess
        if let engine {
            refreshPacks()
            applyAppEdits()
            ready(engine)
            return
        }
        waiting.append(ready)
        guard !loading else { return }
        loading = true
        let full = hasFullAccess
        io.async {
            let base = Bundle.main.path(forResource: "en", ofType: "glyd").flatMap(GlydTrie.mapped(path:))
            var personal = Self.readLexicon(hasFullAccess: full)
            personal.expire(today: TypingText.day())
            DispatchQueue.main.async {
                let engine = TypingEngine(base: base, personal: personal,
                                          geometry: KeyGeometry(rows: self.letterRows))
                self.engine = engine
                self.loading = false
                self.refreshPacks()
                self.applyAppEdits()
                lexicon { [weak self] lex in self?.adopt(lex) }
                let callbacks = self.waiting
                self.waiting = []
                callbacks.forEach { $0(engine) }
            }
        }
    }

    // MARK: Packs

    /// Re-reads the switched-on packs when the app changed them.
    func refreshPacks() {
        guard let engine else { return }
        let enabled = SettingsStore.current.vocabPacks ?? Self.defaultPacks()
        let custom = AppGroupStore.readJSON(name: Self.customPacksFile)
        let signature = enabled.joined(separator: ",") + "|" + String((custom?["updatedAt"] as? Double) ?? 0)
        guard signature != packSignature else { return }
        packSignature = signature
        var words: [String] = []
        var phrases: [String] = []
        let ids = Set(enabled)
        var packs: [[String: Any]] = []
        if let url = Bundle.main.url(forResource: "packs", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            packs += root["packs"] as? [[String: Any]] ?? []
        }
        packs += custom?["packs"] as? [[String: Any]] ?? []
        for pack in packs where ids.contains(pack["id"] as? String ?? "") {
            for entry in pack["words"] as? [String] ?? [] {
                // "Google Docs" is two words the keyboard should know.
                words += entry.split(separator: " ").map(String.init)
                if entry.contains(" ") { phrases.append(entry) }
            }
            for phrase in pack["phrases"] as? [String] ?? [] {
                words += phrase.split(separator: " ").map(String.init)
                phrases.append(phrase)
            }
        }
        engine.setPackWords(words)
        engine.setPackPhrases(phrases)
    }

    /// Before anyone picks packs: Hinglish for phones set to India, where
    /// "yaar" and "kal" are words, not typos. Mirrored in the app's
    /// Vocabulary screen and the Android keyboard.
    static func defaultPacks(region: String? = Locale.current.regionCode) -> [String] {
        region == "IN" ? ["local.hinglish"] : []
    }

    // MARK: Contacts and text replacements

    private func adopt(_ lexicon: UILexicon) {
        var names: [String] = []
        var shortcuts: [String: String] = [:]
        for entry in lexicon.entries {
            if entry.userInput == entry.documentText {
                names.append(entry.documentText)
            } else if !entry.userInput.isEmpty {
                shortcuts[entry.userInput.lowercased()] = entry.documentText
            }
        }
        replacements = shortcuts
        // The contacts the app already synced for Contacts search (Profile;
        // no new permission) are names too, never to be autocorrected.
        names += AppGroupStore.readContacts().map(\.name)
        engine?.setContacts(names.flatMap { $0.split(separator: " ").map(String.init) })
    }

    // MARK: Edits made in the app ("My words")

    /// The app can't write the keyboard's file safely, so it appends edits;
    /// the keyboard applies the ones newer than its own record. The record
    /// lives in the same file as the words, so the two never disagree.
    func applyAppEdits() {
        guard let engine, let edits = AppGroupStore.readJSON(name: Self.editsFile)?["edits"] as? [[String: Any]] else { return }
        let applied = engine.personal.editsAppliedAt
        var latest = applied
        for edit in edits.sorted(by: { ($0["at"] as? Double ?? 0) < ($1["at"] as? Double ?? 0) }) {
            guard let at = edit["at"] as? Double, at > applied else { continue }
            let word = edit["word"] as? String ?? ""
            switch edit["op"] as? String {
            case "add": engine.add(word)
            case "forget": engine.forget(word)
            // "<context>\t<emoji run>", from My words › Emoji.
            case "forgetEmoji":
                let parts = word.components(separatedBy: "\t")
                if parts.count == 2 { engine.forgetEmoji(context: parts[0], run: parts[1]) }
            case "reset": engine.replacePersonal(PersonalLexicon())
            default: break
            }
            latest = max(latest, at)
        }
        guard latest > applied else { return }
        engine.markEditsApplied(latest)
        scheduleSave()
    }

    // MARK: Saving

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard let engine else { return }
        let json = engine.personal.json()
        let full = hasFullAccess
        io.async { Self.writeLexicon(json, hasFullAccess: full) }
    }

    private static func lexiconURL(hasFullAccess: Bool) -> URL? {
        if hasFullAccess, let dir = AppGroupStore.bridgeDir {
            return dir.appendingPathComponent(lexiconFile)
        }
        return localURL(lexiconFile)
    }

    private static func localURL(_ name: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private static func readLexicon(hasFullAccess: Bool) -> PersonalLexicon {
        let candidates = [lexiconURL(hasFullAccess: hasFullAccess), localURL(lexiconFile)].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return PersonalLexicon(json: json)
            }
        }
        return PersonalLexicon()
    }

    private static func writeLexicon(_ json: [String: Any], hasFullAccess: Bool) {
        guard var url = lexiconURL(hasFullAccess: hasFullAccess),
              let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        do {
            try data.write(to: url, options: [.atomic])
            // Typing data stays on this device: never in an iCloud backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            // No writable container (no Full Access and a locked-down
            // extension sandbox): keep learning in memory for this session.
        }
    }

}
