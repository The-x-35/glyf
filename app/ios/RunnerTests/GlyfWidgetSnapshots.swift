import SwiftUI
import WidgetKit
import XCTest
@testable import Runner

/// Draws every widget in each size, light and dark, at the iPhone 17 Pro's
/// widget sizes. It always checks that each one renders; with
/// TEST_RUNNER_GLYF_SNAPSHOT_DIR set it also writes the PNGs there (the
/// screenshots in docs/WIDGETS-AND-ISLAND.md).
@MainActor
final class GlyfWidgetSnapshots: XCTestCase {
    private static let small = CGSize(width: 170, height: 170)
    private static let medium = CGSize(width: 364, height: 170)
    private static let large = CGSize(width: 364, height: 382)
    private static let rectangular = CGSize(width: 172, height: 76)

    private var dir: URL? {
        ProcessInfo.processInfo.environment["GLYF_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    /// A widget as the Home Screen shows it: the system's content margins,
    /// the rounded tile, on a plain wallpaper.
    private func tile<V: View>(_ view: V, _ size: CGSize, dark: Bool, accessory: Bool = false) -> some View {
        let face = view
            .padding(accessory ? 0 : 16)
            .frame(width: size.width, height: size.height)
            .background(accessory ? AnyShapeStyle(Color.white.opacity(0.18)) : AnyShapeStyle(Color(uiColor: .systemBackground)))
            .clipShape(RoundedRectangle(cornerRadius: accessory ? 12 : 23, style: .continuous))
            .foregroundStyle(accessory ? Color.white : Color.primary)
        return face
            .padding(20)
            .background(accessory ? Color(red: 0.12, green: 0.16, blue: 0.30) : (dark ? Color(white: 0.08) : Color(red: 0.87, green: 0.9, blue: 0.95)))
            .environment(\.colorScheme, dark || accessory ? .dark : .light)
    }

    private func snap<V: View>(_ name: String, _ view: V, _ size: CGSize, accessory: Bool = false) throws {
        for dark in accessory ? [true] : [false, true] {
            let renderer = ImageRenderer(content: tile(view, size, dark: dark, accessory: accessory))
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, "\(name) didn't render")
            XCTAssertGreaterThan(image.size.width, size.width)
            if let dir, let png = image.pngData() {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try png.write(to: dir.appendingPathComponent("widget-\(name)\(accessory ? "" : dark ? "-dark" : "-light").png"))
            }
        }
    }

    func testEveryWidgetRendersInEverySize() throws {
        let e = GlyfEntry.sample
        try snap("watchlist-small", WatchlistView(entry: e, size: .systemSmall), Self.small)
        try snap("watchlist-medium", WatchlistView(entry: e, size: .systemMedium), Self.medium)
        try snap("watchlist-lock", WatchlistView(entry: e, size: .accessoryRectangular), Self.rectangular, accessory: true)
        try snap("quick-small", QuickGlyfsView(entry: e, size: .systemSmall), Self.small)
        try snap("quick-medium", QuickGlyfsView(entry: e, size: .systemMedium), Self.medium)
        try snap("next-event-medium", NextEventView(entry: e, size: .systemMedium), Self.medium)
        try snap("next-event-lock", NextEventView(entry: e, size: .accessoryRectangular), Self.rectangular, accessory: true)
        try snap("glyf-medium", AllInOneView(entry: e, size: .systemMedium), Self.medium)
        try snap("glyf-large", AllInOneView(entry: e, size: .systemLarge), Self.large)
    }

    func testEmptyStatesRenderTheirOneLine() throws {
        let e = GlyfEntry.empty
        try snap("watchlist-medium-empty", WatchlistView(entry: e, size: .systemMedium), Self.medium)
        try snap("next-event-medium-empty", NextEventView(entry: e, size: .systemMedium), Self.medium)
        try snap("glyf-large-empty", AllInOneView(entry: e, size: .systemLarge), Self.large)
    }
}
