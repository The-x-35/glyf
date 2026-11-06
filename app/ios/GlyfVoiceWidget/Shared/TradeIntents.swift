import AppIntents
import Foundation

/// Cancel on a placed Flash order's Live Activity. Flash's cancel is a
/// message the funding wallet signs (lib/evm/flash_orders.dart), so it
/// can't happen in the background: the intent brings Glyf forward on that
/// order's cancel, which asks the wallet as the order list's Cancel does.
/// Compiled into the app and the widget extension (whose button names it);
/// LiveActivityIntent runs perform() in the app's process.
@available(iOS 17.0, *)
struct CancelFlashOrderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Flash Order"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Order")
    var orderId: String

    init() {}
    init(orderId: String) { self.orderId = orderId }

    func perform() async throws -> some IntentResult {
        #if !GLYF_WIDGET
        await MainActor.run { TradeActivityHost.shared.cancelRequested(orderId: orderId) }
        #endif
        return .result()
    }
}
