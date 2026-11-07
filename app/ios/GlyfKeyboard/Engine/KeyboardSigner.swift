import Foundation
import JavaScriptCore
import Security

/// Trades signed and sent from the keyboard itself, with the Glyf wallet's
/// key (Arpit, 2026-11-07, for the ETHGlobal demo: "we can have private keys
/// inside the keyboard ... Everything should happen inside the keyboard. It
/// should not switch the app"). viem runs in JavaScriptCore (SignerScript);
/// Glyf's API is its node and its Uniswap and Flash. Base and the other EVM
/// chains, Glyf wallet only; Solana, MetaMask and Phantom still go to the app.
final class KeyboardSigner {
    static let shared = KeyboardSigner()

    /// The Glyf wallet's recovery phrase, kept by the app in the Keychain
    /// group the keyboard shares (WalletSecrets, "glyf-phrase").
    static func phrase() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "so.glyf.wallet",
                                kSecAttrAccount as String: "glyf-phrase",
                                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let phrase = String(data: data, encoding: .utf8), phrase.split(separator: " ").count >= 12 else { return nil }
        return phrase
    }

    /// Whether this trade can be signed here: an EVM trade, the Glyf wallet
    /// switched on, its phrase on this phone.
    static func canSign(_ q: [String: String]) -> Bool {
        guard let chain = q["chain"], chain != "solana", chain != "whitechain-sepolia",
              q["kind"] != "send", q["kind"] != "request", q["kind"] != "bridge",
              SettingsStore.current.walletMode != "external" else { return false }
        return phrase() != nil
    }

    private var context: JSContext?
    private var busy = false

    /// Runs the trade; `step` hears each stage ("Swapping…"), `done` the
    /// outcome: ok, and the tx `url`, or the `error`.
    func run(_ q: [String: String], step: @escaping (String) -> Void, done: @escaping ([String: Any]) -> Void) {
        guard !busy, let phrase = Self.phrase() else { done(["ok": false, "error": "No Glyf wallet on this phone"]); return }
        guard let ctx = makeContext(step: step, done: { [weak self] out in self?.busy = false; done(out) }) else {
            done(["ok": false, "error": "The signer didn't start"]); return
        }
        busy = true
        context = ctx
        let json = (try? JSONSerialization.data(withJSONObject: q)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ctx.objectForKeyedSubscript("GlyfSigner")?.objectForKeyedSubscript("run")?.call(withArguments: [phrase, json])
    }

    private func makeContext(step: @escaping (String) -> Void, done: @escaping ([String: Any]) -> Void) -> JSContext? {
        guard let data = Data(base64Encoded: SignerScript.base64), let src = String(data: data, encoding: .utf8),
              let ctx = JSContext() else { return nil }
        var finished = false
        let finish: ([String: Any]) -> Void = { out in
            DispatchQueue.main.async { guard !finished else { return }; finished = true; done(out) }
        }
        ctx.exceptionHandler = { _, e in finish(["ok": false, "error": e?.toString() ?? "The signer stopped"]) }
        let native = JSValue(newObjectIn: ctx)!
        let resolve: (Int, Bool, String?) -> Void = { [weak ctx] id, ok, json in
            DispatchQueue.main.async {
                ctx?.objectForKeyedSubscript("__resolve")?.call(withArguments: [id, ok, json ?? NSNull()])
            }
        }
        let post: @convention(block) (String, String, Int) -> Void = { path, body, id in
            DispatchQueue.main.async {
                let obj = body.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
                _ = BackendClient.shared.evmJSONResult(path: path, body: obj ?? (body.isEmpty ? nil : [:])) { _, reply in
                    guard let reply, let d = try? JSONSerialization.data(withJSONObject: reply) else {
                        resolve(id, false, "No answer from Glyf"); return
                    }
                    resolve(id, true, String(data: d, encoding: .utf8))
                }
            }
        }
        let timer: @convention(block) (Int, Int) -> Void = { ms, id in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, ms))) { resolve(id, true, nil) }
        }
        let random: @convention(block) (Int) -> [UInt8] = { n in
            var bytes = [UInt8](repeating: 0, count: max(0, n))
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return bytes
        }
        let stepBlock: @convention(block) (String) -> Void = { s in DispatchQueue.main.async { step(s) } }
        let doneBlock: @convention(block) (String) -> Void = { json in
            let out = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? ["ok": false]
            finish(out)
        }
        native.setObject(post, forKeyedSubscript: "post" as NSString)
        native.setObject(timer, forKeyedSubscript: "timer" as NSString)
        native.setObject(random, forKeyedSubscript: "random" as NSString)
        native.setObject(stepBlock, forKeyedSubscript: "step" as NSString)
        native.setObject(doneBlock, forKeyedSubscript: "done" as NSString)
        ctx.setObject(native, forKeyedSubscript: "__native" as NSString)
        ctx.evaluateScript(src)
        return ctx
    }
}
