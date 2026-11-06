import Foundation

/// The pure halves of Glyf's App Intents: what the server's answers mean,
/// and what an intent says when it can't. Unit tested (GlyfWidgetDataTests).
enum GlyfIntentParsing {
    /// The body of POST /act's rewrite, as a version: `style` when the
    /// server wrote it, else the first.
    static func pickRewrite(_ json: [String: Any], style: String) throws -> String {
        if json["ok"] as? Bool == false {
            throw GlyfIntentError.failed(json["error"] as? String ?? "Couldn't rewrite that right now")
        }
        let options = json["options"] as? [[String: Any]] ?? []
        if let hit = options.first(where: { $0["id"] as? String == style })?["text"] as? String, !hit.isEmpty { return hit }
        if let first = options.first?["text"] as? String, !first.isEmpty { return first }
        if let text = json["text"] as? String, !text.isEmpty { return text }
        throw GlyfIntentError.failed("Couldn't rewrite that right now")
    }

    /// Run Glyf from a Shortcuts tile has no text yet: the built-ins that
    /// work on text (rewrites, Proofread, Translate) ask for it first, so
    /// they never run on nothing. Saved glyfs may need none, so they don't.
    static func asksForText(glyfId: String, input: String) -> Bool {
        guard input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return glyfId.hasPrefix("rewrite.") || glyfId == "glyf.proofread" || glyfId == "glyf.translate"
    }

    /// The text of POST /glyf/run's event stream: its `done`, else the
    /// tokens; an `error` event throws its message.
    static func streamText(_ body: String) throws -> String {
        var tokens = ""
        for event in body.components(separatedBy: "\n\n") {
            var type = "message", payload = ""
            for line in event.split(separator: "\n") {
                if line.hasPrefix("event:") { type = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
                if line.hasPrefix("data:") { payload += line.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            }
            guard let obj = payload.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
            else { continue }
            switch type {
            case "token": tokens += obj["t"] as? String ?? ""
            case "done": if let t = obj["text"] as? String, !t.isEmpty { return t }
            case "error": throw GlyfIntentError.failed(obj["message"] as? String ?? "Something went wrong")
            default: break
            }
        }
        guard !tokens.isEmpty else { throw GlyfIntentError.failed("The glyf wrote nothing") }
        return tokens
    }

}

enum GlyfIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, meetNotConnected, reconnectGoogle, failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: return "Sign in to Glyf first"
        case .meetNotConnected: return "Connect Google Meet in Glyf › Connected tools"
        case .reconnectGoogle: return "Connect Google again in Glyf › Connected tools"
        case .failed(let why): return "\(why)"
        }
    }
}
