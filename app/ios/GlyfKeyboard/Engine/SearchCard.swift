import Foundation

/// §6.12 — one result in the search suite.
///
/// Mirrors `server/src/lib/searchcards.ts` field for field, and the Kotlin
/// `BackendClient.SearchCard`. One struct rather than an enum: `kind` decides
/// which fields a cell reads, and a server that grows a field must never fail
/// an older client's decode.
///
/// Lives in Engine (not Bridge) so the pure paste logic is unit-testable
/// without dragging URLSession into the test target.
struct GlyfKeyboardSearchCard: Decodable {
    var kind: String            // "answer" | "link" | "video" | "place" | "contact"
    var id: String
    var title: String
    var url: String
    /// Prefix for the title line when pasting title+link. Gboard uses 🎥 for
    /// videos and 📍 for places, and nothing for a plain web link.
    var emoji: String?
    /// Optional third paste line — the street address on a place card.
    var extra: String?
    /// An answer is sent as the answer ("Sunset's at 6:24 PM 🌇"); when set,
    /// a tap inserts exactly this.
    var say: String?

    // answer
    var value: String?
    var sub: String?
    var art: String?
    var source: String?

    // link
    var snippet: String?
    var domain: String?
    var thumb: String?

    // video
    var channel: String?
    var duration: String?
    var live: Bool?
    var videoId: String?

    // place
    var address: String?
    var rating: Double?
    var ratingCount: Int?
    var openNow: Bool?
    var distance: String?
    /// Present on place cards from every maps provider — the act surface
    /// snapshots a map around it.
    var lat: Double?
    var lon: Double?

    /// What a tap puts in the host field.
    ///
    /// Duplicated from the server's `composeInsert` so a paste never needs a
    /// round trip; the two are locked together by identical tests on both
    /// sides. Format (Gboard parity):
    ///
    ///     <url>
    ///     <emoji> <title>
    ///     <extra>
    func insertText(style: String) -> String {
        if let say = say?.trimmingCharacters(in: .whitespacesAndNewlines), !say.isEmpty {
            return say
        }
        if style == "linkOnly" || title.trimmingCharacters(in: .whitespaces).isEmpty {
            return url
        }
        var lines = [url, "\(emoji.map { "\($0) " } ?? "")\(title)"]
        if let extra = extra?.trimmingCharacters(in: .whitespaces), !extra.isEmpty {
            lines.append(extra)
        }
        return lines.joined(separator: "\n")
    }
}

struct GlyfKeyboardSearchResult: Decodable {
    var vertical: String
    var query: String?
    var cards: [GlyfKeyboardSearchCard]
    var provider: String
}
