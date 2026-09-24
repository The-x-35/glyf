import Foundation

/// In-app notes, reachable from the keyboard (like the vault, minus crypto):
/// quick snippets you save in the app and drop into any field from the shell.
/// Plain App Group JSON — notes are user content the user can already read;
/// the SecretScanner still refuses obvious secrets on save (§11.9 spirit).
struct GlyfNote: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var updatedAt: Date
}

final class NotesStore {
    static let shared = NotesStore()
    static let fileName = "notes.json"

    private var cached: [GlyfNote]?

    func load() -> [GlyfNote] {
        if let cached { return cached }
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(Self.fileName)),
              let notes = try? decoder.decode([GlyfNote].self, from: data)
        else { return [] }
        cached = notes
        return notes
    }

    func invalidate() { cached = nil }

    @discardableResult
    func save(_ notes: [GlyfNote]) -> Bool {
        cached = notes
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? encoder.encode(notes) else { return false }
        do {
            try data.write(to: dir.appendingPathComponent(Self.fileName), options: .atomic)
            return true
        } catch { return false }
    }

    /// Returns an error string when refused (secrets never become notes).
    func upsert(id: String?, text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Write something first" }
        if trimmed.count > 2000 { return "Notes max out at 2000 characters" }
        switch SecretScanner.scan(trimmed) {
        case .clean: break
        case .cardNumber: return "Card numbers can't be saved as notes"
        case .seedPhrase: return "Seed phrases can't be saved anywhere in Glyf"
        case .privateKeyOrToken: return "Keys and tokens can't be saved as notes"
        case .otpCode: return "One-time codes aren't worth a note"
        }
        var notes = load()
        let now = Date()
        if let id, let i = notes.firstIndex(where: { $0.id == id }) {
            notes[i].text = trimmed
            notes[i].updatedAt = now
        } else {
            notes.insert(GlyfNote(id: UUID().uuidString.lowercased(),
                                  text: trimmed, updatedAt: now), at: 0)
        }
        save(notes)
        return nil
    }

    func delete(id: String) {
        save(load().filter { $0.id != id })
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
