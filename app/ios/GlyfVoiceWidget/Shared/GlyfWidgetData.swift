import Foundation

/// What Glyf's widgets show, read from the App Group: prices for the
/// watchlist (fetched from Jupiter by the widget itself and kept in
/// `widget-prices.json`), the next event from the calendars the app keeps
/// for the keyboard (`calendar.json`, `google-calendar.json`), saved glyfs
/// from settings, runs left, and the last Meet link a widget made. No
/// secrets: nothing from the vault, no keys, no addresses. Pure parts are
/// unit tested (GlyfWidgetDataTests). Compiled into the app, the widget
/// extension and the tests.
enum GlyfWidgetData {
    static let groupID = "group.com.arpit.glyf"
    static let pricesFile = "widget-prices.json"
    static let meetFile = "widget-meet.json"

    /// Coins first, then the stocks Glyf trades as xStocks.
    static let defaultWatchlist = ["BTC", "ETH", "SOL", "AAPL"]

    struct Ticker: Codable, Hashable, Identifiable {
        var symbol: String
        var name: String
        var usd: Double
        var change24h: Double?
        var stock: Bool = false
        var id: String { symbol }
    }

    struct Prices: Codable, Equatable {
        var at: Date
        var tickers: [Ticker]
    }

    struct Event: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var location: String?
        /// A video call to join (Meet, Zoom, Teams), when the event has one.
        var join: URL?
    }

    struct QuickGlyf: Codable, Hashable, Identifiable {
        enum Action: String, Codable { case meet, voice, link }
        var id: String
        var title: String
        /// An SF Symbol.
        var symbol: String
        var action: Action
        /// For `.link`: the app path it opens.
        var url: URL?
    }

    struct MeetLink: Codable, Equatable {
        var url: String
        var at: Date
    }

    // MARK: App Group files

    static var bridgeDir: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("bridge", isDirectory: true)
    }

    static func readObject(_ name: String) -> [String: Any]? {
        guard let url = bridgeDir?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = bridgeDir?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, _ name: String) -> Bool {
        guard let dir = bridgeDir, let data = try? encoder.encode(value) else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try? data.write(to: dir.appendingPathComponent(name), options: .atomic)) != nil
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: Watchlist

    /// The symbols to show: settings' `watchlist` when the app set one.
    static func watchlist(settings: [String: Any]?) -> [String] {
        let list = (settings?["watchlist"] as? [String])?
            .map { $0.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "$ ")) }
            .filter { !$0.isEmpty } ?? []
        return list.isEmpty ? defaultWatchlist : Array(list.prefix(6))
    }

    static func price(_ usd: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        if usd >= 10_000 {
            f.maximumFractionDigits = 0
        } else if usd >= 1 {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
        } else {
            f.minimumFractionDigits = 2
            f.maximumSignificantDigits = 3
            f.usesSignificantDigits = true
        }
        return f.string(from: NSNumber(value: usd)) ?? "$\(usd)"
    }

    static func change(_ pct: Double?) -> String {
        guard let pct, pct.isFinite else { return "–" }
        let r = (pct * 10).rounded() / 10
        if r == 0 { return "0.0%" }
        return String(format: "%@%.1f%%", r > 0 ? "+" : "−", abs(r))
    }

    /// Stand-in rows for the gallery and the redacted placeholder.
    static let sample: [Ticker] = [
        .init(symbol: "BTC", name: "Bitcoin", usd: 104_212, change24h: 1.8),
        .init(symbol: "ETH", name: "Ethereum", usd: 3_861.42, change24h: -0.7),
        .init(symbol: "SOL", name: "Solana", usd: 187.05, change24h: 3.2),
        .init(symbol: "AAPL", name: "Apple", usd: 241.10, change24h: 0.4, stock: true),
    ]

    // MARK: Next event

    /// The first link in an event's text that is a call: Meet, Zoom,
    /// Teams, Webex, FaceTime.
    static func joinURL(in text: String?) -> URL? {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]
        let range = NSRange(text.startIndex..., in: text)
        for m in detector.matches(in: text, range: range) {
            guard let url = m.url, url.scheme == "https", let host = url.host?.lowercased() else { continue }
            if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
        }
        return nil
    }

    /// Calendar rows ({title, start, end, allDay, location, meet}) as events,
    /// all-day ones left out.
    static func events(fromRows rows: [[String: Any]]) -> [Event] {
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ v: Any?) -> Date? {
            if let s = v as? String { return iso.date(from: s) ?? isoFrac.date(from: s) }
            if let n = v as? Double { return Date(timeIntervalSince1970: n) }
            return nil
        }
        return rows.compactMap { row in
            guard (row["allDay"] as? Bool) != true,
                  let start = date(row["start"]), let end = date(row["end"]) else { return nil }
            let title = (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Busy"
            let location = row["location"] as? String
            let join = (row["meet"] as? String).flatMap(URL.init(string:)) ?? joinURL(in: location)
                ?? joinURL(in: row["notes"] as? String)
            return Event(title: title, start: start, end: end,
                         location: join == nil ? location : nil, join: join)
        }
    }

    /// The event on now or next, within the coming week; the same event
    /// from the phone and from Google counts once.
    static func nextEvent(_ events: [Event], now: Date = Date()) -> Event? {
        let horizon = now.addingTimeInterval(7 * 86400)
        return events
            .filter { $0.end > now && $0.start < horizon }
            .sorted { $0.start != $1.start ? $0.start < $1.start : ($0.join != nil && $1.join == nil) }
            .first
    }

    /// Both calendars the app keeps for the keyboard.
    static func loadNextEvent(now: Date = Date()) -> Event? {
        let rows = ((readObject("calendar.json")?["events"] as? [[String: Any]]) ?? [])
            + ((readObject("google-calendar.json")?["events"] as? [[String: Any]]) ?? [])
            + ((readObject("google-added.json")?["events"] as? [[String: Any]]) ?? [])
        return nextEvent(events(fromRows: rows), now: now)
    }

    /// "in 12 min", "now", "2:30 PM", "Tue 9:00 AM".
    static func when(_ e: Event, now: Date = Date(), calendar: Calendar = .current) -> String {
        if e.start <= now { return "Now" }
        let mins = Int(e.start.timeIntervalSince(now) / 60)
        if mins < 60 { return "in \(max(1, mins)) min" }
        let time = e.start.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(e.start, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(e.start, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(e.start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    // MARK: Quick glyfs

    static let wallet = URL(string: "glyf://open?path=wallet")!
    static let evmWallet = URL(string: "glyf://open?path=evm-wallet")!
    static let vault = URL(string: "glyf://open?path=vault")!
    static let build = URL(string: "glyf://open?path=build")!
    static let glyfs = URL(string: "glyf://open?path=keys")!

    /// The four buttons: a Meet link and voice work in place (their intents
    /// run in the app's process); the wallet and the vault open Glyf.
    static func quickGlyfs(settings: [String: Any]?) -> [QuickGlyf] {
        [
            .init(id: "meet", title: "Meet link", symbol: "video.fill", action: .meet),
            .init(id: "voice", title: "Voice", symbol: "mic.fill", action: .voice),
            .init(id: "wallet", title: "Wallet", symbol: "wallet.bifold.fill", action: .link, url: wallet),
            .init(id: "vault", title: "Vault", symbol: "lock.fill", action: .link, url: vault),
        ]
    }

    /// Glyfs the person built (settings' customTitles): id and name.
    static func savedGlyfs(settings: [String: Any]?) -> [(id: String, title: String)] {
        let titles = settings?["customTitles"] as? [String: String] ?? [:]
        return titles.filter { !$0.value.isEmpty }
            .map { (id: $0.key, title: $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func runsLeft() -> Int? { readObject("runs-remaining.json")?["remaining"] as? Int }

    /// A Meet link made in the last 30 minutes, shown on the widget it came from.
    static func recentMeet(now: Date = Date()) -> MeetLink? {
        guard let m = read(MeetLink.self, meetFile), now.timeIntervalSince(m.at) < 30 * 60 else { return nil }
        return m
    }

    /// "meet.google.com/abc-defg-hij".
    static func shortLink(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }
}
