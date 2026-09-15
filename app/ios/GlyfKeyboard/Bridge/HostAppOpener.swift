import UIKit
import os.log

/// Spike A (SPEC §4.1): keyboard extensions cannot call `UIApplication.shared.open()`.
/// Swaps, sends, and dictation all depend on the extension being able to foreground
/// the container app. This tries every known strategy in order and logs which one
/// worked; the empirical result on the target OS goes into docs/SPIKES.md.
///
/// Shipped fallback if every strategy fails on some OS release: an
/// "Open Glyf to continue" card in the keyboard. The intent is already in the
/// App Group before any open attempt, so the app can pick it up on manual launch
/// regardless of how it was foregrounded.
enum HostAppOpener {
    private static let log = Logger(subsystem: "so.glyf.keyboard", category: "spikeA")

    enum Strategy: String {
        /// `NSExtensionContext.open` — the documented API; historically only honored
        /// for Today widgets, but it has a completion callback so it is tried first.
        case extensionContextOpen
        /// Responder-chain `UIApplication` + legacy `openURL:` (gone on iOS 18+).
        case responderApplication
        /// Responder-chain `UIApplication` + modern `openURL:options:completionHandler:`
        /// invoked through a C function pointer (perform() can't pass 3 args).
        case responderApplicationModern
        /// Any other responder in the chain that answers `openURL:`.
        case responderSelector
        /// Everything failed — fallback card UX required.
        case none
    }

    /// `strategy` reports the first path that *claimed* success. Delivery of the
    /// message only proves the call was made — the real verification is the app
    /// foregrounding and receiving the deep link.
    static func open(_ url: URL, from vc: UIInputViewController,
                     completion: @escaping (Strategy) -> Void) {
        guard let context = vc.extensionContext else {
            DispatchQueue.main.async { completion(walkResponderChain(url, from: vc)) }
            return
        }
        context.open(url) { success in
            log.info("GLYF_SPIKE_A extensionContext.open success=\(success)")
            // Completion thread is unspecified; the responder walk must run on main.
            DispatchQueue.main.async {
                completion(success ? .extensionContextOpen : walkResponderChain(url, from: vc))
            }
        }
    }

    private static func walkResponderChain(_ url: URL, from vc: UIInputViewController) -> Strategy {
        let legacy = sel_registerName("openURL:")
        let modern = sel_registerName("openURL:options:completionHandler:")
        var responder: UIResponder? = vc
        while let r = responder {
            // UIApplication is compile-time unavailable in extensions
            // (NS_EXTENSION_UNAVAILABLE), but an instance is still reachable
            // through the responder chain at runtime.
            if let app = r as? UIApplication {
                if app.responds(to: legacy), app.perform(legacy, with: url) != nil {
                    log.info("GLYF_SPIKE_A responderApplication delivered=true")
                    return .responderApplication
                }
                log.info("GLYF_SPIKE_A responderApplication legacy openURL: unavailable")
                if app.responds(to: modern) {
                    typealias OpenFn = @convention(c) (
                        NSObject, Selector, NSURL, NSDictionary, UnsafeRawPointer?) -> Void
                    let fn = unsafeBitCast(app.method(for: modern), to: OpenFn.self)
                    fn(app, modern, url as NSURL, [:] as NSDictionary, nil)
                    log.info("GLYF_SPIKE_A responderApplicationModern invoked")
                    return .responderApplicationModern
                }
                log.info("GLYF_SPIKE_A responderApplicationModern selector missing")
            } else if r.responds(to: legacy), !(r is UIInputViewController) {
                let delivered = r.perform(legacy, with: url) != nil
                let kind = String(describing: type(of: r))
                log.info("GLYF_SPIKE_A responderSelector responder=\(kind, privacy: .public) delivered=\(delivered)")
                if delivered { return .responderSelector }
            }
            responder = r.next
        }
        log.info("GLYF_SPIKE_A exhausted — no strategy delivered")
        return .none
    }
}
