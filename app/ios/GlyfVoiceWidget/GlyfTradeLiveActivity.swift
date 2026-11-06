import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// A trade in flight (GlyfTradeAttributes): the Island's compact, minimal
/// and expanded views and the Lock Screen's, in Glyf's black and white.
struct GlyfTradeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlyfTradeAttributes.self) { context in
            TradeLockScreen(attrs: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(GlyfTradeActivity.openURL(kind: context.attributes.kind, chain: context.attributes.chain))
        } dynamicIsland: { context in
            let a = context.attributes, s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlyfTile(size: 36, dark: true)
                        .padding(.leading, 6)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(GlyfTradeActivity.kindLabel(a.kind)) · \(a.chain)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(a.pair)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseBadge(state: s)
                        .padding(.trailing, 6)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        TradeFacts(attrs: a, state: s)
                        TradeButtons(attrs: a, state: s)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                GlyfMarkView(letter: .white)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 2)
            } compactTrailing: {
                CompactStatus(state: s)
            } minimal: {
                MinimalStatus(state: s)
            }
            .keylineTint(GlyfStyle.violet)
            .widgetURL(GlyfTradeActivity.openURL(kind: a.kind, chain: a.chain))
        }
    }
}

/// The phase's symbol and colour on black.
private extension GlyfTradeAttributes.Phase {
    var symbol: String {
        switch self {
        case .placing: return "arrow.triangle.2.circlepath"
        case .waiting: return "signature"
        case .placed: return "checkmark.circle.fill"
        case .submitted: return "clock.fill"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .placing, .waiting: return GlyfStyle.violet
        case .placed, .confirmed: return GlyfStyle.up
        case .submitted: return .white
        case .failed: return GlyfStyle.down
        }
    }
}

private struct CompactStatus: View {
    let state: GlyfTradeAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.phase.symbol)
                .foregroundStyle(state.phase.tint)
                .font(.system(size: 12, weight: .semibold))
            Text(GlyfTradeActivity.status(state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 76)
        }
        .padding(.trailing, 2)
    }
}

private struct MinimalStatus: View {
    let state: GlyfTradeAttributes.ContentState

    var body: some View {
        if state.phase.inFlight {
            GlyfMarkView(letter: .white).frame(width: 16, height: 16)
        } else {
            Image(systemName: state.phase.symbol).foregroundStyle(state.phase.tint)
        }
    }
}

private struct PhaseBadge: View {
    let state: GlyfTradeAttributes.ContentState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.phase.symbol).font(.system(size: 12, weight: .bold))
            Text(GlyfTradeActivity.status(state))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(state.phase.tint)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

/// Amount and trigger, then what is happening in one line.
private struct TradeFacts: View {
    let attrs: GlyfTradeAttributes
    let state: GlyfTradeAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            ForEach([attrs.amount, attrs.trigger].compactMap { $0 }, id: \.self) { fact in
                Text(fact)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(line)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    /// The screen's own words while it works, then the result.
    private var line: String {
        switch state.phase {
        case .placing, .waiting: return state.title
        case .failed: return state.detail ?? state.title
        default: return state.detail ?? GlyfTradeActivity.headline(state, chain: attrs.chain)
        }
    }
}

/// Cancel (a placed Flash order), Open, and the explorer.
private struct TradeButtons: View {
    let attrs: GlyfTradeAttributes
    let state: GlyfTradeAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if state.phase == .placed, attrs.cancellable, let id = state.orderId {
                Button(intent: CancelFlashOrderIntent(orderId: id)) {
                    Text("Cancel").islandButton(primary: false)
                }
                .buttonStyle(.plain)
            }
            Link(destination: GlyfTradeActivity.openURL(kind: attrs.kind, chain: attrs.chain)) {
                Text("Open").islandButton(primary: true)
            }
            if let link = state.link, let url = URL(string: link) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(GlyfTradeActivity.linkLabel(link))
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    }
                    .islandButton(primary: false)
                }
            }
        }
    }
}

private extension View {
    func islandButton(primary: Bool) -> some View {
        self
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.14)))
    }
}

/// The Lock Screen: the mark, the pair and what's happening, the facts,
/// and the buttons.
struct TradeLockScreen: View {
    let attrs: GlyfTradeAttributes
    let state: GlyfTradeAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                GlyfTile(size: 34, dark: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(GlyfTradeActivity.kindLabel(attrs.kind)) · \(attrs.pair)")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(state.phase == .failed ? state.title : GlyfTradeActivity.headline(state, chain: attrs.chain))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                PhaseBadge(state: state)
            }
            HStack(spacing: 6) {
                ForEach([attrs.amount, attrs.trigger].compactMap { $0 }, id: \.self) { fact in
                    Text(fact)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                Spacer(minLength: 0)
                Text(state.updated, style: .time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.85))
            if state.phase == .placed || state.link != nil {
                TradeButtons(attrs: attrs, state: state)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

// MARK: Previews

extension GlyfTradeAttributes {
    static let preview = GlyfTradeAttributes(
        tradeId: "preview", kind: "stop-loss", pair: "SOL → USDC", amount: "2 SOL",
        trigger: "at $172", chain: "Base", cancellable: true)
}

extension GlyfTradeAttributes.ContentState {
    static let waiting = Self(phase: .waiting, title: "Sign the stop-loss in Phantom", detail: nil,
                              wallet: "Phantom", link: nil, orderId: nil, updated: .now)
    static let placed = Self(phase: .placed, title: "Stop-loss set", detail: "Sells 2 SOL if it falls to $172",
                             wallet: "Phantom", link: "https://app.definitive.fi/orders/8f3c2a91",
                             orderId: "8f3c2a91", updated: .now)
}

#Preview("Lock Screen", as: .content, using: GlyfTradeAttributes.preview) {
    GlyfTradeLiveActivity()
} contentStates: {
    GlyfTradeAttributes.ContentState.waiting
    GlyfTradeAttributes.ContentState.placed
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: GlyfTradeAttributes.preview) {
    GlyfTradeLiveActivity()
} contentStates: {
    GlyfTradeAttributes.ContentState.placed
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: GlyfTradeAttributes.preview) {
    GlyfTradeLiveActivity()
} contentStates: {
    GlyfTradeAttributes.ContentState.waiting
}
