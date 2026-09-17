import 'dart:convert';

import 'package:flutter/services.dart';

/// Dart side of the `so.glyf/bridge` MethodChannel — the ONLY door to native.
abstract final class GlyfBridge {
  static const _ch = MethodChannel('so.glyf/bridge');

  static void Function(String)? _deepLinkHandler;
  static void Function(String)? _dictationHandler;
  static bool _dispatcherSet = false;

  static void _ensureDispatcher() {
    if (_dispatcherSet) return;
    _dispatcherSet = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDeepLink':
          _deepLinkHandler?.call(call.arguments as String);
        case 'onDictation':
          _dictationHandler?.call(call.arguments as String);
      }
      return null;
    });
  }

  static void onDeepLink(void Function(String) handler) {
    _ensureDispatcher();
    _deepLinkHandler = handler;
  }

  static void onDictationPartial(void Function(String) handler) {
    _ensureDispatcher();
    _dictationHandler = handler;
  }

  static Future<T?> _call<T>(String method, [dynamic args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> groupPath() => _call<String>('groupPath');

  static Future<Map<String, dynamic>?> keyboardPing() async {
    final raw = await _call<String>('readKeyboardPing');
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<bool> keyboardEnabled() async =>
      await _call<bool>('keyboardEnabled') ?? false;

  /// Android: is Glyf the CURRENT input method (step 2 of setup there).
  static Future<bool> keyboardSelected() async =>
      await _call<bool>('keyboardSelected') ?? false;

  /// Android: system input-method picker sheet.
  static Future<void> showImePicker() => _call<void>('showImePicker');

  static Future<void> openSettings() => _call<void>('openSettings');

  /// Opens an https URL in the browser (OAuth consent).
  static Future<bool> openURL(String url) async =>
      await _call<bool>('openURL', {'url': url}) ?? false;

  static Future<String?> documentsPath() => _call<String>('documentsPath');

  static Future<List<String>> launchArgs() async =>
      (await _call<List<Object?>>('launchArgs'))?.whereType<String>().toList() ??
      const [];

  static Future<String?> lastDeepLink() => _call<String>('lastDeepLink');

  // Signing in (SignIn.swift / SignIn.kt): `idToken` on success (with `name`
  // and `email` when the provider shares them), `error` otherwise.

  static Future<Map<String, dynamic>> signInApple(String nonce) async =>
      Map<String, dynamic>.from(
          await _call<Map>('signInApple', {'nonce': nonce}) ?? const {'error': 'failed'});

  static Future<Map<String, dynamic>> signInGoogle({required String clientId, required String nonce}) async =>
      Map<String, dynamic>.from(await _call<Map>('signInGoogle', {'clientId': clientId, 'nonce': nonce}) ??
          const {'error': 'failed'});

  static Future<void> signOutProviders() => _call<bool>('signOutProviders');

  /// The Glyf session, kept in the Keychain (iOS) or encrypted with a
  /// Keystore key (Android).
  static Future<String?> sessionLoad() => _call<String>('sessionLoad');

  static Future<bool> sessionSave(String json) async =>
      await _call<bool>('sessionSave', {'json': json}) ?? false;

  static Future<void> sessionClear() => _call<bool>('sessionClear');

  static Future<void> writeAppPong(String message) =>
      _call<void>('writeAppPong', {'message': message});

  static Future<Map<String, dynamic>> sharedSettings() async {
    final raw = await _call<String>('readSharedSettings');
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> updateSharedSettings(
      Map<String, dynamic> Function(Map<String, dynamic>) mutate) async {
    final current = await sharedSettings();
    final next = mutate(Map<String, dynamic>.from(current));
    await _call<bool>('writeSharedSettings', {'json': jsonEncode(next)});
  }

  static Future<Map<String, dynamic>> onboardingState() async {
    final raw = await _call<String>('readOnboardingState');
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveOnboardingState(Map<String, dynamic> state) =>
      _call<bool>('writeOnboardingState', {'json': jsonEncode(state)});

  // §6.6 dictation

  static Future<String?> dictationPendingIntent() =>
      _call<String>('dictationPending');

  static Future<bool> dictationConsume(String id) async =>
      await _call<bool>('dictationConsume', {'id': id}) ?? false;

  static Future<({bool ok, bool fake, String? error})> dictationStart() async {
    final res = await _call<Map<Object?, Object?>>('dictationStart');
    if (res == null) return (ok: false, fake: false, error: 'bridge unavailable');
    return (
      ok: res['ok'] == true,
      fake: res['fake'] == true,
      error: res['error'] as String?,
    );
  }

  static Future<String> dictationStop() async {
    final res = await _call<Map<Object?, Object?>>('dictationStop');
    return (res?['transcript'] as String?) ?? '';
  }

  static Future<void> dictationCancel() => _call<bool>('dictationCancel');

  static Future<bool> dictationResult(
          String intentId, String transcript, String mode) async =>
      await _call<bool>('dictationResult', {
        'intentId': intentId,
        'transcript': transcript,
        'mode': mode,
      }) ??
      false;

  // §6.7 vault

  static Future<String?> vaultList() => _call<String>('vaultList');

  static Future<({bool ok, String? error})> _okCall(
      String method, Map<String, Object?> args) async {
    final res = await _call<Map<Object?, Object?>>(method, args);
    if (res == null) return (ok: false, error: 'bridge unavailable');
    return (ok: res['ok'] == true, error: res['error'] as String?);
  }

  static Future<({bool ok, String? error})> vaultUpsertField({
    String? id,
    required String kind,
    required String label,
    required String value,
  }) =>
      _okCall('vaultUpsertField',
          {'id': id, 'kind': kind, 'label': label, 'value': value});

  static Future<void> vaultDeleteField(String id) =>
      _call<bool>('vaultDeleteField', {'id': id});

  static Future<({bool ok, String? error})> vaultUpsertCombo({
    String? id,
    required String label,
    required List<String> fieldIds,
  }) =>
      _okCall('vaultUpsertCombo', {'id': id, 'label': label, 'fieldIds': fieldIds});

  static Future<void> vaultDeleteCombo(String id) =>
      _call<bool>('vaultDeleteCombo', {'id': id});

  static Future<({bool ok, String? error})> vaultUpsertSnippet({
    required String trigger,
    required String text,
  }) =>
      _okCall('vaultUpsertSnippet', {'trigger': trigger, 'text': text});

  static Future<void> vaultDeleteSnippet(String trigger) =>
      _call<bool>('vaultDeleteSnippet', {'trigger': trigger});

  // Notes (written here, inserted from the keyboard shell)

  static Future<List<Map<String, dynamic>>> notesList() async {
    final raw = await _call<String>('notesList');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<({bool ok, String? error})> notesUpsert(
          {String? id, required String text}) =>
      _okCall('notesUpsert', {'id': id, 'text': text});

  static Future<void> notesDelete(String id) =>
      _call<bool>('notesDelete', {'id': id});

  // §6.15 tone profile

  /// {accepted: {bucket: n}, discarded: {...}, hint: 'brief sentence' | ''}.
  // ---- Typing engine: "My words", edits, AI-made packs --------------------

  /// The keyboard's learned words (shared/typing/FORMAT.md JSON), or null
  /// before the keyboard has learned anything.
  static Future<Map<String, dynamic>?> typingWords() async {
    final raw = await _call<String>('typingWords');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// `add`, `forget` or `reset` — applied by the keyboard next time it opens.
  static Future<bool> typingEdit(String op, [String word = '']) async =>
      await _call<bool>('typingEdit', {'op': op, 'word': word}) ?? false;

  static Future<Map<String, dynamic>> vocabCustom() async {
    final raw = await _call<String>('vocabCustomRead');
    if (raw == null) return {'packs': []};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {'packs': []};
    }
  }

  static Future<void> saveVocabCustom(Map<String, dynamic> json) =>
      _call<bool>('vocabCustomWrite', {'json': jsonEncode(json)});

  static Future<Map<String, dynamic>> toneProfile() async {
    final raw = await _call<String>('toneProfile');
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> toneReset() => _call<bool>('toneReset');

  // Contacts search (Gboard parity) — permission + sync live natively.
  static Future<Map<String, dynamic>> contactsStatus() async {
    final raw = await _call<String>('contactsStatus');
    if (raw == null) return const {'enabled': false, 'permission': 'denied'};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> contactsEnable() async {
    final raw = await _call<String>('contactsEnable');
    if (raw == null) return const {'ok': false, 'error': 'unavailable'};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> contactsDisable() => _call<bool>('contactsDisable');

  // The phone's calendar for the keyboard's Calendar panel.
  static Future<Map<String, dynamic>> calendarStatus() async {
    final raw = await _call<String>('calendarStatus');
    if (raw == null) return const {'enabled': false, 'permission': 'denied'};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> calendarEnable() async {
    final raw = await _call<String>('calendarEnable');
    if (raw == null) return const {'ok': false, 'error': 'unavailable'};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> calendarDisable() => _call<bool>('calendarDisable');

  /// Android: photo access for screenshots in the clipboard. True once granted.
  static Future<bool> screenshotAccess() async =>
      (await _call<bool>('screenshotAccess')) ?? false;

  // "Near me" searches. The app owns the permission and caches a coarse fix
  // in shared settings; the keyboard only reads it.
  static Future<Map<String, dynamic>> locationStatus() async {
    final raw = await _call<String>('locationStatus');
    if (raw == null) return const {'enabled': false, 'permission': 'denied'};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> locationEnable() async {
    final raw = await _call<String>('locationEnable');
    if (raw == null) return const {'ok': false, 'error': 'unavailable'};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> locationDisable() => _call<bool>('locationDisable');
}
