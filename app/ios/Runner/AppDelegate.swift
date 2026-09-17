import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // UI-test hooks (no effect in normal launches).
    let args = ProcessInfo.processInfo.arguments
    if args.contains("--glyf-skip-onboarding"), let dir = AppGroupStore.bridgeDir {
      let done = #"{"done": true, "pack": "writer"}"#
      try? done.data(using: .utf8)?.write(
        to: dir.appendingPathComponent("onboarding.json"), options: .atomic)
    }
    if args.contains("--glyf-reset-onboarding"), let dir = AppGroupStore.bridgeDir {
      try? FileManager.default.removeItem(
        at: dir.appendingPathComponent("onboarding.json"))
    }
    if args.contains("--glyf-dump-vault"), let dir = AppGroupStore.bridgeDir {
      // DEBUG ONLY (test forensics): decrypted vault snapshot.
      let v = VaultStore.shared.load()
      if let data = try? JSONEncoder().encode(v) {
        try? data.write(to: dir.appendingPathComponent("vault-debug.json"))
      }
    }
    if args.contains("--glyf-seed-vault") {
      let store = VaultStore.shared
      if store.load().fields.isEmpty {
        _ = store.upsertField(id: nil, kind: "address", label: "Home",
                              value: "42 Glass Lane, Indiranagar, Bengaluru 560038")
        _ = store.upsertField(id: nil, kind: "upi", label: "UPI", value: "arpit@okbank")
      }
      // Refreshed every launch: a seed must be deterministic even when an
      // older vault is already on disk (upsert keys off the trigger).
      _ = store.upsertSnippet(trigger: ";sig", text: "— Arpit · tryglyf.com")
    }
    if args.contains("--glyf-reset-typing"), let dir = AppGroupStore.bridgeDir {
      // Forget learned words through the same edit log "My words" uses, so
      // autocorrect tests start from a keyboard that has learned nothing.
      let at = Date().timeIntervalSince1970 * 1000
      let edits = #"{"edits": [{"op": "reset", "word": "", "at": \#(at)}]}"#
      try? edits.data(using: .utf8)?.write(
        to: dir.appendingPathComponent("typing-edits.json"), options: .atomic)
    }
    if args.contains("--glyf-screenshots-on") {
      SettingsStore.update { s in s.clipboardScreenshots = true }
    }
    if args.contains("--glyf-clear-tour") {
      SettingsStore.update { s in s.tourHint = nil }
    }
    if args.contains("--glyf-seed-bindings") {
      // Gate tests exercise the full §6.13 key map; shipping presets are
      // deliberately smaller, so tests seed the rest explicitly.
      SettingsStore.update { s in
        for (k, v) in ["t": "surface:translate-hud", "s": "surface:vault",
                       "r": "surface:tones", "c": "connector:mockcal",
                       "j": "rewrite.emoji", "p": "glyf.proofread",
                       "e": "social.emotion", "x": "social.xreply",
                       "w": "keyless.weather", "q": "keyless.quote"]
        where s.bindings[k] == nil {
          s.bindings[k] = v
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlyfBridge") {
      GlyfBridge.shared.attach(messenger: registrar.messenger())
    }
  }
}
