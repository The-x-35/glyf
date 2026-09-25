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
    if args.contains("--glyf-seed-calendar"), let dir = AppGroupStore.bridgeDir {
      // UI tests: a known day in the keyboard's calendar.
      CalendarSync.shared.keepSeed = true
      let cal = Calendar.current
      let iso = ISO8601DateFormatter()
      let today = cal.startOfDay(for: Date())
      func at(_ day: Int, _ h: Int, _ m: Int = 0) -> String {
        iso.string(from: cal.date(byAdding: .minute, value: day * 1440 + h * 60 + m, to: today)!)
      }
      let events: [[String: Any]] = [
        ["title": "Standup", "start": at(0, 10), "end": at(0, 10, 30), "allDay": false, "color": "#34C759"],
        ["title": "Design review", "start": at(0, 15), "end": at(0, 16), "allDay": false, "location": "Studio", "color": "#7C5CFF"],
        ["title": "Dinner with Zoya", "start": at(1, 20), "end": at(1, 22), "allDay": false, "color": "#FF9500"],
      ]
      if let data = try? JSONSerialization.data(withJSONObject: ["events": events]) {
        try? data.write(to: dir.appendingPathComponent("calendar.json"), options: .atomic)
      }
    }
    if args.contains("--glyf-screenshots-on") {
      SettingsStore.update { s in s.clipboardScreenshots = true }
    }
    if args.contains("--glyf-clear-tour") {
      SettingsStore.update { s in s.tourHint = nil }
    }
    if let i = args.firstIndex(of: "--glyf-booking-link"), i + 1 < args.count {
      // Scenario tests: the booking page Connected tools would save.
      let link = args[i + 1]
      SettingsStore.update { s in s.bookingLink = link.isEmpty ? nil : link }
    }
    #if DEBUG
    if let i = args.firstIndex(of: "--glyf-test-google"), i + 1 < args.count {
      // Scenario tests: Google Calendar and Meet as if connected, pointed at
      // the stand-in for Google's APIs (qa/fake-google.mjs); "" disconnects.
      let base = args[i + 1]
      // "--glyf-test-google-scopes meet" grants Meet alone, the way someone
      // who unticked Calendar on Google's page would have it.
      var scopes = GoogleAccess.scopes
      if let j = args.firstIndex(of: "--glyf-test-google-scopes"), j + 1 < args.count {
        scopes = args[j + 1] == "meet" ? [GoogleAccess.meetScope]
          : args[j + 1] == "calendar" ? [GoogleAccess.calendarScope] : scopes
      }
      if base.isEmpty {
        GoogleAccess.clear()
      } else {
        GoogleAccess.save(GoogleGrant(refreshToken: "fake-refresh", clientId: "fake.apps.googleusercontent.com",
                                      scopes: scopes, email: "sim@example.com", apiBase: base))
      }
    }
    if let i = args.firstIndex(of: "--glyf-bind"), i + 1 < args.count {
      // Scenario tests: "m=connector:meet" holds M for a Meet link; "m=" frees it.
      let pair = args[i + 1].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
      if pair.count == 2, pair[0].count == 1 {
        SettingsStore.update { s in s.bindings[pair[0]] = pair[1].isEmpty ? nil : pair[1] }
      }
    }
    #endif
    if args.contains("--glyf-seed-holds") {
      // Scenario tests: just the holds the keyboard ships with.
      SettingsStore.update { s in
        for (k, v) in ["t": "surface:translate-hud", "s": "surface:vault"] where s.bindings[k] == nil {
          s.bindings[k] = v
        }
      }
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
    // The keyboard's calendar is only as fresh as the last time the app ran.
    CalendarSync.shared.refreshIfEnabled()
    NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
    ) { _ in CalendarSync.shared.refreshIfEnabled() }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlyfBridge") {
      GlyfBridge.shared.attach(messenger: registrar.messenger())
    }
  }
}
