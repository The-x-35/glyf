import SwiftUI
import WidgetKit
// The snapshot tests compile this file too (GlyfWidgetSnapshots); there the
// shared types come from the app.
#if !GLYF_WIDGET
@testable import Runner
#endif

/// Glyf's look on the Home Screen, the Lock Screen and the Island: the app
/// icon's ink and white, its violet dot, SF with tabular numbers.
enum GlyfStyle {
    static let ink = Color(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1C / 255)
    static let violet = Color(red: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255)
    static let up = Color(red: 0x1F / 255, green: 0xA9 / 255, blue: 0x68 / 255)
    static let down = Color(red: 0xE0 / 255, green: 0x38 / 255, blue: 0x2C / 255)

    static func changeColor(_ pct: Double?) -> Color {
        guard let pct, (pct * 10).rounded() != 0 else { return .secondary }
        return pct > 0 ? up : down
    }
}

/// The app icon's mark: its g, and the violet dot above the right shoulder
/// (GlyfMark, the keyboard's outline), sharp at any size.
struct GlyfMarkView: View {
    var letter: Color = .primary
    var dot: Color = GlyfStyle.violet

    var body: some View {
        Canvas { ctx, size in
            let box = CGRect(origin: .zero, size: size)
            let l = GlyfMark.letter(centredIn: box, margin: 0)
            ctx.fill(Path(GlyfMark.gPath(in: l)), with: .color(letter))
            ctx.fill(Path(ellipseIn: GlyfMark.dot(for: l)), with: .color(dot))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Glyf")
    }
}

/// The icon as a tile: ink face and white g (white face and ink g in light
/// widgets, the way the strip's key follows the theme).
struct GlyfTile: View {
    var size: CGFloat = 22
    var dark: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(dark ? GlyfStyle.ink : .white)
            .overlay(GlyfMarkView(letter: dark ? .white : GlyfStyle.ink).padding(size * 0.17))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(dark ? 0.14 : 0), lineWidth: 0.5))
            .frame(width: size, height: size)
    }
}

/// A widget's title row: the mark and a small caps-free label.
struct WidgetHeader: View {
    var title: String
    var trailing: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            GlyfTile(size: 18, dark: scheme == .light)
                .widgetAccentable()
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// The black pill Glyf uses for its main button, white in dark.
struct PillLabel: View {
    var title: String
    var symbol: String?
    var primary = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .foregroundStyle(primary ? (scheme == .dark ? GlyfStyle.ink : .white) : .primary)
        .background(
            Capsule().fill(primary ? (scheme == .dark ? Color.white : GlyfStyle.ink) : Color.primary.opacity(0.08))
        )
    }
}

/// The widgets' background: the system's, so light, dark, tinted and
/// clear all look like they belong.
extension View {
    func glyfWidgetBackground() -> some View {
        containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}
