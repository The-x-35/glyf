import Foundation

/// §6.15 — tone learning, v1. ON DEVICE ONLY: compact preference counters,
/// never transcripts (§11.11). Learns from accepted (Replace) vs discarded
/// rewrites and feeds llm steps a one-line hint. Fully inspectable and
/// deletable from the app.
struct ToneCounts: Codable, Equatable {
    /// tone bucket → accepted count. Buckets: concise, warm, formal, playful.
    var accepted: [String: Int] = [:]
    var discarded: [String: Int] = [:]
}

enum ToneProfile {
    static let fileName = "tone-profile.json"

    /// Which bucket a glyf's acceptance teaches us about.
    static func bucket(for glyfId: String) -> String? {
        switch glyfId {
        case "rewrite.tighten", "glyf.summarize": return "concise"
        case "rewrite.polite", "social.reply": return "warm"
        case "rewrite.professional", "desi.formalhindi": return "formal"
        case "rewrite.emoji", "social.hook", "social.xreply": return "playful"
        default: return nil
        }
    }

    static func load() -> ToneCounts {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)),
              let counts = try? JSONDecoder().decode(ToneCounts.self, from: data)
        else { return ToneCounts() }
        return counts
    }

    static func save(_ counts: ToneCounts) {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
    }

    static func record(glyfId: String, accepted: Bool) {
        guard let bucket = bucket(for: glyfId) else { return }
        var counts = load()
        if accepted {
            counts.accepted[bucket, default: 0] += 1
        } else {
            counts.discarded[bucket, default: 0] += 1
        }
        save(counts)
    }

    static func reset() {
        save(ToneCounts())
    }

    /// Pure, testable: the hint line for llm prompts, or "" with no signal.
    /// Requires ≥3 net accepts before it says anything (don't over-fit).
    static func hint(from counts: ToneCounts) -> String {
        var best: (bucket: String, net: Int)?
        for (bucket, acc) in counts.accepted {
            let net = acc - (counts.discarded[bucket] ?? 0)
            if net >= 3, net > (best?.net ?? 0) {
                best = (bucket, net)
            }
        }
        guard let best else { return "" }
        let phrase: String
        switch best.bucket {
        case "concise": phrase = "brief and to the point"
        case "warm": phrase = "warm and personable"
        case "formal": phrase = "polished and formal"
        case "playful": phrase = "light and playful"
        default: return ""
        }
        return " The user tends to prefer writing that is \(phrase)."
    }

    static func currentHint() -> String {
        hint(from: load())
    }
}
