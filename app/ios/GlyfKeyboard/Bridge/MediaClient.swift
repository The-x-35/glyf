import Foundation
import UIKit
import UniformTypeIdentifiers

/// One GIF or sticker, whichever source found it: a small preview for the
/// grid and the file that is sent.
struct MediaItem: Codable, Equatable {
    let id: String
    let title: String?
    /// Small image for the grid: an animated GIF (KLIPY) or a still (Noto).
    let preview: String
    let pw: Double?
    let ph: Double?
    /// The file that goes on the pasteboard, sized for a message.
    let url: String
    let w: Double?
    let h: Double?
    /// KLIPY's slug, for its share count and recents. Nil for Noto.
    var slug: String?

    /// Width over height, for the grid's layout. Square when unknown.
    var aspect: CGFloat {
        let width = pw ?? w ?? 1, height = ph ?? h ?? 1
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(min(max(width / height, 0.4), 3))
    }
}

/// A page of results and the cursor for the next one.
struct MediaPage {
    let items: [MediaItem]
    let next: String?
    /// The credit the source asks to be shown with its results.
    let attribution: String?
}

enum MediaKind: String {
    case gifs, stickers
}

/// Where a feed comes from. KLIPY's terms keep its results in grids of
/// their own, so the two sources are never mixed in one grid.
enum MediaSource {
    /// KLIPY: GIFs and stickers, called from this phone (its terms ask for
    /// that; our server only hands out the key).
    case klipy
    /// Google's Noto Animated Emoji (CC BY 4.0), listed by our server.
    case noto
}

/// GIFs and stickers for the emoji board.
///
/// KLIPY is the free GIF API that replaced Tenor's (closed 2026-06-30). Its
/// terms want API calls and file loads to come from the person's device, not
/// a proxy, so the keyboard calls it directly with the app key our server
/// hands a signed-in phone (`/media/config`) — the key is never in the app.
/// Stickers also come from Noto Animated Emoji, listed by our server, which
/// needs no key at all. Kept small on purpose: a keyboard extension lives on
/// a fraction of an app's memory.
final class MediaClient {

    static let shared = MediaClient()

    struct Config {
        struct Klipy {
            let key: String
            let base: String
            let contentFilter: String
        }
        let klipy: Klipy?
        let emojiStickers: Bool
    }

    private(set) var config: Config?
    private var configAt: Date?
    private var configWaiting: [(Config?) -> Void] = []

    /// Downloaded previews, by URL. Bounded by bytes, dropped on a memory
    /// warning; a miss is only a re-download. Previews only, on this phone,
    /// which is the one thing KLIPY's terms allow to be kept.
    private let cache = NSCache<NSString, NSData>()
    private var waiting: [String: [(Data?) -> Void]] = [:]

    private init() {
        cache.totalCostLimit = 12 * 1024 * 1024
        cache.countLimit = 90
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cache.removeAllObjects() }
    }

    enum Failure: Error {
        /// Nothing to fetch from: no KLIPY key on the server yet.
        case unavailable
        case offline
    }

    /// A random id for this install, which KLIPY uses for its "recent"
    /// list. Not the person, not the Glyf account: only this keyboard.
    static var customerId: String {
        let key = "glyf.media.customerId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private static var language: String {
        let first = Locale.preferredLanguages.first ?? "en"
        return String(first.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
    }

    // MARK: Config

    /// What the server says is available. Fetched once an hour at most;
    /// completion on the main queue.
    func loadConfig(_ completion: @escaping (Config?) -> Void) {
        if let config, let at = configAt, Date().timeIntervalSince(at) < 3600 {
            completion(config); return
        }
        configWaiting.append(completion)
        guard configWaiting.count == 1 else { return }
        let s = SettingsStore.current
        guard let url = URL(string: "\(s.backendURL)/media/config") else { finishConfig(nil); return }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            var parsed: Config?
            if (response as? HTTPURLResponse)?.statusCode == 200, let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var klipy: Config.Klipy?
                if let k = obj["klipy"] as? [String: Any], let key = k["key"] as? String,
                   let base = k["base"] as? String, !key.isEmpty {
                    klipy = .init(key: key, base: base,
                                  contentFilter: k["contentFilter"] as? String ?? "high")
                }
                parsed = Config(klipy: klipy, emojiStickers: obj["emojiStickers"] as? Bool ?? true)
            }
            DispatchQueue.main.async { self?.finishConfig(parsed) }
        }.resume()
    }

    private func finishConfig(_ parsed: Config?) {
        if let parsed { config = parsed; configAt = Date() }
        let waiting = configWaiting
        configWaiting = []
        for block in waiting { block(parsed ?? config) }
    }

    // MARK: Feeds

    /// Trending when `query` is empty. Completion on the main queue.
    @discardableResult
    func page(_ kind: MediaKind, source: MediaSource, query: String, page: String? = nil,
              completion: @escaping (Result<MediaPage, Failure>) -> Void) -> URLSessionDataTask? {
        switch source {
        case .noto: return notoPage(query: query, page: page, completion: completion)
        case .klipy: return klipyPage(kind, path: query.isEmpty ? "trending" : "search",
                                      query: query, page: page, completion: completion)
        }
    }

    /// KLIPY's own record of what this install sent recently.
    @discardableResult
    func recent(_ kind: MediaKind, page: String? = nil,
                completion: @escaping (Result<MediaPage, Failure>) -> Void) -> URLSessionDataTask? {
        klipyPage(kind, path: "recent/\(Self.customerId)", query: "", page: page, completion: completion)
    }

    private func klipyPage(_ kind: MediaKind, path: String, query: String, page: String?,
                           completion: @escaping (Result<MediaPage, Failure>) -> Void) -> URLSessionDataTask? {
        guard let klipy = config?.klipy,
              var comps = URLComponents(string: "\(klipy.base)\(klipy.key)/\(kind.rawValue)/\(path)")
        else { completion(.failure(.unavailable)); return nil }
        var items = [
            URLQueryItem(name: "page", value: page ?? "1"),
            URLQueryItem(name: "per_page", value: "24"),
            URLQueryItem(name: "customer_id", value: Self.customerId),
            URLQueryItem(name: "locale", value: Self.language),
            URLQueryItem(name: "content_filter", value: klipy.contentFilter),
            URLQueryItem(name: "format_filter", value: kind == .gifs ? "gif" : "gif,png"),
        ]
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: String(query.prefix(80)))) }
        comps.queryItems = items
        guard let url = comps.url else { completion(.failure(.offline)); return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: req) { data, response, err in
            DispatchQueue.main.async {
                if let err = err as NSError?, err.code == NSURLErrorCancelled { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let page = Self.parseKlipy(data, kind: kind)
                else { completion(.failure(.offline)); return }
                completion(.success(page))
            }
        }
        task.resume()
        return task
    }

    /// KLIPY's envelope: {result, data: {data: [items], current_page,
    /// has_next}}; each item has `file.{hd,md,sm,xs}.{gif,webp,png,jpg}`.
    /// Ads (type "ad") are skipped: this keyboard shows none.
    static func parseKlipy(_ data: Data, kind: MediaKind) -> MediaPage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["result"] as? Bool != false,
              let body = obj["data"] as? [String: Any],
              let list = body["data"] as? [[String: Any]] else { return nil }
        func variant(_ file: [String: Any], _ sizes: [String], _ formats: [String])
            -> (url: String, w: Double?, h: Double?)? {
            for size in sizes {
                guard let set = file[size] as? [String: Any] else { continue }
                for format in formats {
                    if let f = set[format] as? [String: Any], let url = f["url"] as? String {
                        return (url, (f["width"] as? NSNumber)?.doubleValue,
                                (f["height"] as? NSNumber)?.doubleValue)
                    }
                }
            }
            return nil
        }
        let items: [MediaItem] = list.compactMap { raw in
            if (raw["type"] as? String) == "ad" || raw["content"] != nil { return nil }
            guard let file = raw["file"] as? [String: Any] else { return nil }
            let slug = raw["slug"] as? String ?? (raw["id"].map { "\($0)" } ?? "")
            // The grid animates small GIFs; the message gets a medium one.
            // A sticker that has no GIF is a still, sent as a PNG.
            let formats = kind == .gifs ? ["gif"] : ["gif", "png"]
            guard let preview = variant(file, ["sm", "xs", "md"], formats),
                  let full = variant(file, ["md", "hd", "sm"], formats) else { return nil }
            return MediaItem(id: "klipy:\(slug)", title: raw["title"] as? String,
                             preview: preview.url, pw: preview.w, ph: preview.h,
                             url: full.url, w: full.w, h: full.h, slug: slug)
        }
        let hasNext = body["has_next"] as? Bool ?? false
        let current = (body["current_page"] as? NSNumber)?.intValue ?? 1
        return MediaPage(items: items, next: hasNext ? String(current + 1) : nil,
                         attribution: "Powered by KLIPY")
    }

    private func notoPage(query: String, page: String?,
                          completion: @escaping (Result<MediaPage, Failure>) -> Void) -> URLSessionDataTask? {
        let s = SettingsStore.current
        guard var comps = URLComponents(string: "\(s.backendURL)/media/emoji-stickers") else {
            completion(.failure(.offline)); return nil
        }
        comps.queryItems = [URLQueryItem(name: "page", value: page ?? "1")]
            + (query.isEmpty ? [] : [URLQueryItem(name: "q", value: String(query.prefix(60)))])
        guard let url = comps.url else { completion(.failure(.offline)); return nil }
        var req = URLRequest(url: url)
        req.glyfSession()
        req.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: req) { data, response, err in
            DispatchQueue.main.async {
                if let err = err as NSError?, err.code == NSURLErrorCancelled { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let list = obj["items"] as? [[String: Any]],
                      let json = try? JSONSerialization.data(withJSONObject: list),
                      let items = try? JSONDecoder().decode([MediaItem].self, from: json)
                else { completion(.failure(.offline)); return }
                completion(.success(MediaPage(items: items, next: obj["next"] as? String,
                                              attribution: obj["attribution"] as? String)))
            }
        }
        task.resume()
        return task
    }

    /// Search terms that complete what has been typed ("ca" → cat, cats…),
    /// from KLIPY. Nothing when KLIPY is not set up.
    @discardableResult
    func suggest(query: String, completion: @escaping ([String]) -> Void) -> URLSessionDataTask? {
        guard let klipy = config?.klipy, !query.isEmpty,
              let encoded = query.prefix(50).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var comps = URLComponents(string: "\(klipy.base)\(klipy.key)/autocomplete/\(encoded)")
        else { completion([]); return nil }
        comps.queryItems = [URLQueryItem(name: "limit", value: "6"),
                            URLQueryItem(name: "locale", value: Self.language)]
        guard let url = comps.url else { completion([]); return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err = err as NSError?, err.code == NSURLErrorCancelled { return }
                completion(data.map(Self.parseTerms) ?? [])
            }
        }
        task.resume()
        return task
    }

    /// Autocomplete answers as a list of words, however KLIPY wraps it.
    static func parseTerms(_ data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        func strings(_ any: Any?) -> [String]? {
            if let list = any as? [String] { return list }
            if let list = any as? [[String: Any]] {
                return list.compactMap { $0["query"] as? String ?? $0["term"] as? String ?? $0["name"] as? String }
            }
            return nil
        }
        if let list = strings(obj) { return list }
        guard let dict = obj as? [String: Any] else { return [] }
        if let list = strings(dict["data"]) { return list }
        if let inner = dict["data"] as? [String: Any], let list = strings(inner["data"]) { return list }
        return []
    }

    /// Tells KLIPY one was sent: it counts toward its trending and this
    /// install's recent list. Fire and forget.
    func reportShare(_ item: MediaItem, kind: MediaKind, query: String?) {
        guard let klipy = config?.klipy, let slug = item.slug,
              let url = URL(string: "\(klipy.base)\(klipy.key)/\(kind.rawValue)/share/\(slug)")
        else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["customer_id": Self.customerId]
        if let query, !query.isEmpty { body["q"] = query }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: Files

    /// A preview's bytes, cached. Completion on the main queue, once.
    func previewData(_ urlString: String, completion: @escaping (Data?) -> Void) {
        if let hit = cache.object(forKey: urlString as NSString) {
            completion(hit as Data); return
        }
        guard let url = URL(string: urlString), url.scheme == "https" || url.host == "127.0.0.1" else {
            completion(nil); return
        }
        if waiting[urlString] != nil { waiting[urlString]?.append(completion); return }
        waiting[urlString] = [completion]
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let body = ok ? data : nil
            DispatchQueue.main.async {
                guard let self else { return }
                if let body { self.cache.setObject(body as NSData, forKey: urlString as NSString,
                                                   cost: body.count) }
                for block in self.waiting.removeValue(forKey: urlString) ?? [] { block(body) }
            }
        }.resume()
    }

    /// The file to send. Not cached: it is bigger, and used once.
    func fullData(_ urlString: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: urlString), url.scheme == "https" || url.host == "127.0.0.1" else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async { completion(ok ? data : nil) }
        }.resume()
    }

    /// Puts a GIF (animated; stickers keep their transparency) or a PNG on
    /// the pasteboard as the one thing there, the way Gboard for iPhone hands
    /// a GIF over: a keyboard can type text but never an image, so the person
    /// pastes it. Only the image type is offered, so no app pastes a link
    /// instead of the picture.
    static func copyToPasteboard(_ data: Data) -> Bool {
        guard data.count > 8 else { return false }
        let type: UTType
        if data.prefix(3) == Data("GIF".utf8) {
            type = .gif
        } else if data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) {
            type = .png
        } else {
            return false
        }
        UIPasteboard.general.setItems([[type.identifier: data]], options: [:])
        return UIPasteboard.general.types.contains(type.identifier)
    }
}

/// Noto stickers sent recently, newest first, in the App Group so the board
/// shows them the next time it opens. KLIPY keeps its own list (its terms
/// allow storing nothing of its content here), so only Noto lands in this.
enum MediaRecents {

    private static func file(_ kind: MediaKind) -> URL? {
        AppGroupStore.bridgeDir?.appendingPathComponent("media-recents-\(kind.rawValue).json")
    }

    static func load(_ kind: MediaKind) -> [MediaItem] {
        guard let url = file(kind), let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([MediaItem].self, from: data)
        else { return [] }
        return list
    }

    static func push(_ item: MediaItem, kind: MediaKind) {
        guard item.slug == nil else { return }   // KLIPY's are kept by KLIPY
        var list = load(kind).filter { $0.id != item.id }
        list.insert(item, at: 0)
        guard let url = file(kind),
              let data = try? JSONEncoder().encode(Array(list.prefix(30))) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Emoticons sent recently, like the emoji board's Frequently Used.
enum EmoticonRecents {
    private static var file: URL? {
        AppGroupStore.bridgeDir?.appendingPathComponent("emoticon-recents.json")
    }

    static func load() -> [String] {
        guard let url = file, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    static func push(_ e: String) {
        var list = load().filter { $0 != e }
        list.insert(e, at: 0)
        guard let url = file, let data = try? JSONEncoder().encode(Array(list.prefix(24))) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
