import ActivityKit
import UIKit
import os.log

/// The trade-in-flight Live Activity (GlyfTradeAttributes), driven by the
/// trade screen over the bridge (`liveActivity.start/update/end`): one
/// activity per trade, updated on every step, ended when it is done (a
/// placed Flash order stays, with its Cancel). While the person is away
/// signing in Phantom or MetaMask the app asks for background time, so the
/// step that comes back can still update the Island.
final class TradeActivityHost {
    static let shared = TradeActivityHost()
    private let log = Logger(subsystem: "so.glyf.app", category: "trade-activity")
    private var background: UIBackgroundTaskIdentifier = .invalid

    private func activity(_ id: String) -> Activity<GlyfTradeAttributes>? {
        Activity<GlyfTradeAttributes>.activities.first { $0.attributes.tradeId == id }
    }

    /// Starts the trade's activity, or updates it when it runs already.
    /// `payload`: {id, query{…}, state, title, detail?, wallet?, link?, orderId?, reopen?}.
    func show(_ payload: [String: Any]) -> Bool {
        guard let id = payload["id"] as? String, !id.isEmpty else { return false }
        let query = (payload["query"] as? [String: Any] ?? [:]).compactMapValues { "\($0)" }
        let attrs = GlyfTradeActivity.attributes(id: id, query: query)
        let state = GlyfTradeActivity.content(
            kind: attrs.kind,
            state: payload["state"] as? String ?? "working",
            title: payload["title"] as? String ?? "One moment…",
            detail: payload["detail"] as? String,
            wallet: payload["wallet"] as? String
                ?? GlyfTradeActivity.wallet(in: payload["title"] as? String ?? "", chain: attrs.chain)
                ?? activity(id)?.content.state.wallet,
            link: payload["link"] as? String,
            orderId: payload["orderId"] as? String,
            reopen: payload["reopen"] as? Bool ?? false)
        holdBackground(state.phase.inFlight)
        let content = ActivityContent(state: state, staleDate: state.phase.inFlight ? Date().addingTimeInterval(600) : nil)
        if let running = activity(id) {
            Task {
                if let after = GlyfTradeActivity.dismissal(state.phase) {
                    await running.end(content, dismissalPolicy: .after(Date().addingTimeInterval(after)))
                } else {
                    await running.update(content)
                }
            }
            return true
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.log("GLYF_TRADE live activity: turned off for Glyf")
            return false
        }
        // A trade that fails before it ever showed needs no Island.
        if state.phase == .failed { return false }
        do {
            _ = try Activity.request(attributes: attrs, content: content, pushType: nil)
            log.log("GLYF_TRADE live activity on kind=\(attrs.kind, privacy: .public)")
            return true
        } catch {
            log.error("GLYF_TRADE live activity failed \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Ends one trade's activity (or all of them with no id) at once.
    func end(id: String?) {
        for a in Activity<GlyfTradeAttributes>.activities where id == nil || a.attributes.tradeId == id {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        holdBackground(false)
    }

    /// The Island's Cancel (CancelFlashOrderIntent): Glyf comes forward on
    /// Flash's cancel for the order; the activity goes once it's cancelled.
    func cancelRequested(orderId: String) {
        guard let url = GlyfTradeActivity.cancelURL(orderId: orderId) else { return }
        GlyfBridge.shared.handleDeepLink(url)
    }

    /// Ends the activity of a cancelled order.
    func orderCancelled(_ orderId: String) {
        for a in Activity<GlyfTradeAttributes>.activities where a.content.state.orderId == orderId {
            var s = a.content.state
            s.phase = .failed
            s.title = "Order cancelled"
            s.detail = nil
            s.updated = Date()
            Task { await a.end(ActivityContent(state: s, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(120))) }
        }
    }

    #if DEBUG
    /// `--glyf-demo-trade`: a stop-loss on Base walks through every phase
    /// (Placing, Waiting for MetaMask, Placed with Cancel) for the simulator,
    /// where no wallet app signs. Never in a release build.
    func demo() {
        let q: [String: Any] = ["kind": "stop-loss", "sell": "ETH", "buy": "USDC", "amount": "0.5",
                                "price": "3400", "chain": "base"]
        let id = "demo-\(Int(Date().timeIntervalSince1970))"
        let steps: [(TimeInterval, [String: Any])] = [
            (0, ["state": "working", "title": "Asking Flash…"]),
            (3, ["state": "working", "title": "Sign the stop-loss: confirm in MetaMask", "reopen": true]),
            (14, ["state": "working", "title": "Placing the order…"]),
            (17, ["state": "done", "title": "Stop-loss set", "detail": "Sells 0.5 ETH if it falls to $3,400",
                  "link": "https://app.definitive.fi/orders/8f3c2a91", "orderId": "8f3c2a91"]),
        ]
        for (at, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                var p = step
                p["id"] = id
                p["query"] = q
                p["wallet"] = "MetaMask"
                _ = self.show(p)
            }
        }
    }
    #endif

    /// Background time while the wallet has the person: iOS gives about 30 s
    /// once the app is behind, enough for the answer to land and the step
    /// after it to show.
    private func holdBackground(_ on: Bool) {
        DispatchQueue.main.async {
            if on, self.background == .invalid {
                self.background = UIApplication.shared.beginBackgroundTask(withName: "glyf.trade") { [weak self] in
                    self?.holdBackground(false)
                }
            } else if !on, self.background != .invalid {
                UIApplication.shared.endBackgroundTask(self.background)
                self.background = .invalid
            }
        }
    }
}
