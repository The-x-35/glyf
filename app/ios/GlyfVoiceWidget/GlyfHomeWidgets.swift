import AppIntents
import SwiftUI
import WidgetKit
// The snapshot tests compile this file too (GlyfWidgetSnapshots); there the
// shared types come from the app.
#if !GLYF_WIDGET
@testable import Runner
#endif

// Glyf's Home Screen and Lock Screen widgets: Watchlist, Quick glyfs,
// Next event and the all-in-one Glyf widget. One timeline for all of them
// (GlyfProvider): prices from Jupiter (TokenLookup, the keyboard's own
// lookup) kept in the App Group, the next event from the calendars the app
// keeps for the keyboard, saved glyfs and runs left from settings.

// MARK: Timeline

struct GlyfEntry: TimelineEntry {
    var date: Date
    var tickers: [GlyfWidgetData.Ticker]
    var pricesAt: Date?
    var event: GlyfWidgetData.Event?
    var glyfs: [GlyfWidgetData.QuickGlyf]
    var saved: [String]
    var meet: GlyfWidgetData.MeetLink?
    var runsLeft: Int?

    static let sample = GlyfEntry(
        date: .now, tickers: GlyfWidgetData.sample, pricesAt: .now,
        event: .init(title: "Design review with Mia", start: .now.addingTimeInterval(14 * 60),
                     end: .now.addingTimeInterval(44 * 60), location: nil,
                     join: URL(string: "https://meet.google.com/abc-defg-hij")),
        glyfs: GlyfWidgetData.quickGlyfs(settings: nil), saved: ["Send my Meet link", "Standup notes"],
        meet: nil, runsLeft: 42)

    static let empty = GlyfEntry(date: .now, tickers: [], pricesAt: nil, event: nil,
                                 glyfs: GlyfWidgetData.quickGlyfs(settings: nil), saved: [], meet: nil, runsLeft: nil)
}

struct GlyfProvider: TimelineProvider {
    /// Prices younger than this are drawn as they are.
    static let fresh: TimeInterval = 10 * 60

    func placeholder(in context: Context) -> GlyfEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (GlyfEntry) -> Void) {
        if context.isPreview { return completion(.sample) }
        DispatchQueue.global(qos: .userInitiated).async { completion(load(fetch: false)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlyfEntry>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let entry = load(fetch: true)
            // Again in 15 minutes, or when the next event starts or ends.
            var next = Date().addingTimeInterval(15 * 60)
            if let e = entry.event {
                for t in [e.start, e.end] where t > Date() && t < next { next = t.addingTimeInterval(1) }
            }
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func load(fetch: Bool) -> GlyfEntry {
        let settings = GlyfWidgetData.readObject("settings.json")
        let symbols = GlyfWidgetData.watchlist(settings: settings)
        var prices = GlyfWidgetData.read(GlyfWidgetData.Prices.self, GlyfWidgetData.pricesFile)
        let stale = prices.map { Date().timeIntervalSince($0.at) > Self.fresh
            || Set($0.tickers.map(\.symbol)) != Set(symbols) } ?? true
        if fetch, stale, let fetched = Self.fetch(symbols) {
            prices = fetched
            GlyfWidgetData.write(fetched, GlyfWidgetData.pricesFile)
        }
        return GlyfEntry(
            date: .now, tickers: prices?.tickers ?? [], pricesAt: prices?.at,
            event: GlyfWidgetData.loadNextEvent(),
            glyfs: GlyfWidgetData.quickGlyfs(settings: settings),
            saved: GlyfWidgetData.savedGlyfs(settings: settings).map(\.title),
            meet: GlyfWidgetData.recentMeet(), runsLeft: GlyfWidgetData.runsLeft())
    }

    /// Jupiter, through the keyboard's TokenLookup; nil when nothing came back.
    static func fetch(_ symbols: [String]) -> GlyfWidgetData.Prices? {
        let lookup = TokenLookup()
        let rows: [GlyfWidgetData.Ticker] = symbols.compactMap { s in
            guard let q = try? lookup.quote(s) else { return nil }
            let name = q.stock ? q.name.replacingOccurrences(of: " xStock", with: "") : q.name
            return .init(symbol: s, name: s == "BTC" ? "Bitcoin" : name, usd: q.usd, change24h: q.change24h, stock: q.stock)
        }
        return rows.isEmpty ? nil : .init(at: Date(), tickers: rows)
    }
}

// MARK: Pieces

private struct TickerRow: View {
    let t: GlyfWidgetData.Ticker
    var showName = true
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(t.symbol)
                    .font(.system(size: compact ? 13 : 14, weight: .semibold))
                if showName {
                    Text(t.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(GlyfWidgetData.price(t.usd))
                    .font(.system(size: compact ? 13 : 14, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(GlyfWidgetData.change(t.change24h))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(GlyfStyle.changeColor(t.change24h))
                    .widgetAccentable()
            }
            .layoutPriority(1)
        }
    }
}

private struct EmptyLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
    }
}

/// A quick glyf as a square button: its intent in place, else a link.
private struct GlyfButton: View {
    let g: GlyfWidgetData.QuickGlyf
    var label = true
    var height: CGFloat = 56

    var body: some View {
        switch g.action {
        case .meet: Button(intent: NewMeetLinkIntent()) { face }.buttonStyle(.plain)
        case .voice:
            if #available(iOS 18.0, *) {
                Button(intent: StartGlyfVoiceIntent()) { face }.buttonStyle(.plain)
            } else {
                Link(destination: GlyfWidgetData.glyfs) { face }
            }
        case .link: Link(destination: g.url ?? GlyfWidgetData.glyfs) { face }
        }
    }

    private var face: some View {
        VStack(spacing: 5) {
            Image(systemName: g.symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(height: 22)
                .widgetAccentable()
            if label {
                Text(g.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
        .contentShape(Rectangle())
    }
}

private struct EventBlock: View {
    let event: GlyfWidgetData.Event?
    var meet: GlyfWidgetData.MeetLink?
    var compact = false

    var body: some View {
        if let e = event {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                HStack(spacing: 6) {
                    Circle().fill(GlyfStyle.violet).frame(width: 6, height: 6).widgetAccentable()
                    Text(GlyfWidgetData.when(e))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GlyfStyle.violet)
                        .widgetAccentable()
                    Text(e.start, style: .time).font(.system(size: 12)).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(e.title)
                    .font(.system(size: compact ? 14 : 16, weight: .semibold))
                    .lineLimit(compact ? 1 : 2)
                HStack(spacing: 8) {
                    if let join = e.join {
                        Link(destination: join) { PillLabel(title: "Join", symbol: "video.fill") }
                    }
                    Button(intent: NewMeetLinkIntent()) {
                        PillLabel(title: meet.map { GlyfWidgetData.shortLink($0.url) } ?? "New Meet link",
                                  symbol: meet == nil ? "plus" : "doc.on.doc", primary: e.join == nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No events this week")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button(intent: NewMeetLinkIntent()) {
                    PillLabel(title: meet.map { GlyfWidgetData.shortLink($0.url) } ?? "New Meet link",
                              symbol: meet == nil ? "plus" : "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
            .frame(maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

private func updated(_ at: Date?) -> String? {
    guard let at else { return nil }
    return at.formatted(date: .omitted, time: .shortened)
}

// MARK: Watchlist

struct WatchlistWidget: Widget {
    static let kind = "com.arpit.glyf.watchlist"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlyfProvider()) { entry in
            WatchlistView(entry: entry).glyfWidgetBackground()
        }
        .configurationDisplayName("Watchlist")
        .description("Coins and stocks with their 24-hour change.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct WatchlistView: View {
    let entry: GlyfEntry
    /// Set by the snapshot tests; the widget's own family otherwise.
    var size: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { size ?? envFamily }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let t = entry.tickers.first {
                Text("\(t.symbol) \(GlyfWidgetData.price(t.usd)) \(GlyfWidgetData.change(t.change24h))")
            } else {
                Text("Glyf watchlist")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if entry.tickers.isEmpty {
                    Text("Watchlist").font(.headline)
                    Text("Prices load soon").font(.caption)
                }
                ForEach(entry.tickers.prefix(3)) { t in
                    HStack {
                        Text(t.symbol).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(GlyfWidgetData.price(t.usd)).font(.system(size: 13)).monospacedDigit()
                        Text(GlyfWidgetData.change(t.change24h)).font(.system(size: 11, weight: .semibold))
                            .monospacedDigit().widgetAccentable()
                    }
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Watchlist", trailing: updated(entry.pricesAt))
                if entry.tickers.isEmpty {
                    EmptyLine(text: "Prices show once Glyf is online")
                } else {
                    let rows = Array(entry.tickers.prefix(4))
                    Grid(horizontalSpacing: 16, verticalSpacing: 10) {
                        ForEach(0..<((rows.count + 1) / 2), id: \.self) { r in
                            GridRow {
                                TickerRow(t: rows[r * 2])
                                if r * 2 + 1 < rows.count { TickerRow(t: rows[r * 2 + 1]) } else { Color.clear }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(GlyfWidgetData.wallet)
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "Watchlist")
                if entry.tickers.isEmpty {
                    EmptyLine(text: "Prices show once Glyf is online")
                } else {
                    ForEach(entry.tickers.prefix(3)) { TickerRow(t: $0, showName: false, compact: true) }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(GlyfWidgetData.wallet)
        }
    }
}

// MARK: Quick glyfs

struct QuickGlyfsWidget: Widget {
    static let kind = "com.arpit.glyf.quick"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlyfProvider()) { entry in
            QuickGlyfsView(entry: entry).glyfWidgetBackground()
        }
        .configurationDisplayName("Quick glyfs")
        .description("A Meet link and voice in one tap; your wallet and vault.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickGlyfsView: View {
    let entry: GlyfEntry
    /// Set by the snapshot tests; the widget's own family otherwise.
    var size: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { size ?? envFamily }

    var body: some View {
        let g = Array(entry.glyfs.prefix(4))
        if family == .systemSmall {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { GlyfButton(g: g[0], height: 64); GlyfButton(g: g[1], height: 64) }
                GridRow { GlyfButton(g: g[2], height: 64); GlyfButton(g: g[3], height: 64) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Glyf", trailing: entry.meet.map { GlyfWidgetData.shortLink($0.url) }
                    ?? entry.runsLeft.map { "\($0) runs left" })
                HStack(spacing: 8) {
                    ForEach(g) { GlyfButton(g: $0, height: 74) }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: Next event

struct NextEventWidget: Widget {
    static let kind = "com.arpit.glyf.next-event"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlyfProvider()) { entry in
            NextEventView(entry: entry).glyfWidgetBackground()
        }
        .configurationDisplayName("Next event")
        .description("Your next meeting, with Join and a fresh Meet link.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct NextEventView: View {
    let entry: GlyfEntry
    /// Set by the snapshot tests; the widget's own family otherwise.
    var size: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { size ?? envFamily }

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                if let e = entry.event {
                    Text(GlyfWidgetData.when(e)).font(.system(size: 12, weight: .semibold)).widgetAccentable()
                    Text(e.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                } else {
                    Text("Calendar").font(.headline)
                    Text("No events this week").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(entry.event?.join)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Next event", trailing: entry.event.map { $0.start.formatted(.dateTime.weekday(.abbreviated).day()) })
                EventBlock(event: entry.event, meet: entry.meet)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

// MARK: All in one

struct GlyfAllInOneWidget: Widget {
    static let kind = "com.arpit.glyf.all"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlyfProvider()) { entry in
            AllInOneView(entry: entry).glyfWidgetBackground()
        }
        .configurationDisplayName("Glyf")
        .description("Prices, quick glyfs and your next meeting together.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct AllInOneView: View {
    let entry: GlyfEntry
    /// Set by the snapshot tests; the widget's own family otherwise.
    var size: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { size ?? envFamily }

    var body: some View {
        let g = Array(entry.glyfs.prefix(4))
        if family == .systemLarge {
            VStack(alignment: .leading, spacing: 12) {
                WidgetHeader(title: "Glyf", trailing: entry.runsLeft.map { "\($0) runs left" })
                if entry.tickers.isEmpty {
                    EmptyLine(text: "Prices show once Glyf is online").frame(height: 70)
                } else {
                    let rows = Array(entry.tickers.prefix(4))
                    Grid(horizontalSpacing: 16, verticalSpacing: 10) {
                        ForEach(0..<((rows.count + 1) / 2), id: \.self) { r in
                            GridRow {
                                TickerRow(t: rows[r * 2])
                                if r * 2 + 1 < rows.count { TickerRow(t: rows[r * 2 + 1]) } else { Color.clear }
                            }
                        }
                    }
                    .widgetURL(GlyfWidgetData.wallet)
                }
                Divider()
                HStack(spacing: 8) { ForEach(g) { GlyfButton(g: $0, height: 62) } }
                Divider()
                EventBlock(event: entry.event, meet: entry.meet)
                Spacer(minLength: 0)
                if !entry.saved.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.saved.prefix(3), id: \.self) { title in
                            Link(destination: GlyfWidgetData.glyfs) {
                                Text(title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    WidgetHeader(title: "Glyf")
                    if entry.tickers.isEmpty {
                        EmptyLine(text: "Prices soon")
                    } else {
                        ForEach(entry.tickers.prefix(3)) { TickerRow(t: $0, showName: false, compact: true) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .widgetURL(GlyfWidgetData.wallet)
                VStack(spacing: 8) {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow { GlyfButton(g: g[0], height: 46); GlyfButton(g: g[1], height: 46) }
                        GridRow { GlyfButton(g: g[2], height: 46); GlyfButton(g: g[3], height: 46) }
                    }
                    if let e = entry.event {
                        Link(destination: e.join ?? URL(string: "calshow://")!) {
                            HStack(spacing: 6) {
                                Circle().fill(GlyfStyle.violet).frame(width: 6, height: 6).widgetAccentable()
                                Text("\(GlyfWidgetData.when(e)) · \(e.title)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if e.join != nil {
                                    Text("Join").font(.system(size: 11, weight: .bold)).foregroundStyle(GlyfStyle.violet)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: Previews

#Preview("Watchlist", as: .systemSmall) { WatchlistWidget() } timeline: { GlyfEntry.sample; GlyfEntry.empty }
#Preview("Watchlist medium", as: .systemMedium) { WatchlistWidget() } timeline: { GlyfEntry.sample }
#Preview("Watchlist lock", as: .accessoryRectangular) { WatchlistWidget() } timeline: { GlyfEntry.sample }
#Preview("Quick glyfs", as: .systemMedium) { QuickGlyfsWidget() } timeline: { GlyfEntry.sample }
#Preview("Next event", as: .systemMedium) { NextEventWidget() } timeline: { GlyfEntry.sample; GlyfEntry.empty }
#Preview("Glyf medium", as: .systemMedium) { GlyfAllInOneWidget() } timeline: { GlyfEntry.sample }
#Preview("Glyf large", as: .systemLarge) { GlyfAllInOneWidget() } timeline: { GlyfEntry.sample; GlyfEntry.empty }
