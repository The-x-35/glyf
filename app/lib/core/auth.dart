import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:privy_flutter/privy_flutter.dart';

import 'bridge.dart';
import 'glyf_api.dart';

/// Signing in, once, for the whole app: Apple or Google, through Privy (the
/// same account the wallet uses).
///
/// After a sign-in the server is told who this is and which phone they are on
/// (POST /me); keyboard settings and app events follow. The vault never
/// leaves the phone: only which KINDS of detail were saved are sent.
abstract final class Auth {
  /// The scheme Privy returns to after Google or Apple. Kept apart from the
  /// app's own glyf:// links so the two never compete for a URL.
  static const oauthScheme = 'glyfauth';

  static Privy? _privy;
  static Future<Privy?>? _starting;
  static PrivyUser? _user;

  static PrivyUser? get user => _user;
  static bool _testSignedIn = false;
  static bool get signedIn => _user != null || _testSignedIn;

  /// Privy, started with the public ids the server hands out. Null when the
  /// server cannot be reached or sign-in is not set up there.
  static Future<Privy?> privy() {
    if (_privy != null) return Future.value(_privy);
    return _starting ??= () async {
      // The ids are public; kept on the phone so a saved session opens
      // offline too.
      final s = await GlyfBridge.sharedSettings();
      var appId = s['privyAppId'] as String?;
      var clientId = s['privyAppClientId'] as String?;
      final cfg = await GlyfApi.walletConfig();
      if (cfg != null && cfg['ready'] == true) {
        appId = cfg['privyAppId'] as String;
        clientId = cfg['privyAppClientId'] as String;
        if (s['privyAppId'] != appId || s['privyAppClientId'] != clientId) {
          await GlyfBridge.updateSharedSettings((m) => m
            ..['privyAppId'] = appId
            ..['privyAppClientId'] = clientId);
        }
      }
      if (appId == null || appId.isEmpty || clientId == null || clientId.isEmpty) {
        _starting = null;
        return null;
      }
      final p = Privy.init(
        config: PrivyConfig(
          appId: appId,
          appClientId: clientId,
          logLevel: PrivyLogLevel.error,
        ),
      );
      _privy = p;
      return p;
    }();
  }

  /// Whether someone is signed in on this phone. Works offline from Privy's
  /// stored session.
  static Future<bool> restore() async {
    // UI tests reach the screens behind sign-in without a real account.
    // Never in a release build.
    if (!kReleaseMode && (await GlyfBridge.launchArgs()).contains('--glyf-test-signed-in')) {
      _testSignedIn = true;
      return true;
    }
    final p = await privy();
    if (p == null) return false;
    try {
      final state = await p.getAuthState();
      if (state is Authenticated) {
        _user = state.user;
        return true;
      }
    } catch (_) {}
    _user = null;
    return false;
  }

  static Future<String?> signInWithGoogle() => _oauth(OAuthProvider.google);
  static Future<String?> signInWithApple() => _oauth(OAuthProvider.apple);

  /// Null on success, otherwise what to tell the person.
  static Future<String?> _oauth(OAuthProvider provider) async {
    final p = await privy();
    if (p == null) return 'Sign-in is unavailable right now. Try again in a moment.';
    try {
      final res = await p.oAuth.login(provider: provider, appUrlScheme: oauthScheme);
      String? error;
      res.fold(
        onSuccess: (u) => _user = u,
        onFailure: (e) => error = _friendly(e.message),
      );
      if (error == null) await _afterSignIn(provider.name);
      return error;
    } on PlatformException catch (e) {
      return _friendly(e.message ?? '');
    } catch (e) {
      return _friendly('$e');
    }
  }

  static String _friendly(String raw) {
    if (!kReleaseMode) debugPrint('glyf sign-in: $raw');
    final m = raw.toLowerCase();
    if (m.contains('native_app_id') || m.contains('allowed app identifier')) {
      return 'Sign-in is not set up for this app yet.';
    }
    if (m.contains('cancel')) return 'Sign-in was cancelled.';
    if (m.contains('network') || m.contains('internet')) return 'No connection. Try again when you are online.';
    if (m.contains('not allowed') || m.contains('not enabled') || m.contains('scheme')) {
      return 'That sign-in option is not available yet.';
    }
    return 'Sign-in did not finish. Try again.';
  }

  /// The email and name the account came with, for filling in the vault.
  static ({String? email, String? name}) identity() {
    final u = _user;
    if (u == null) return (email: null, name: null);
    String? email;
    String? name;
    for (final a in u.linkedAccounts) {
      switch (a) {
        case EmailAccount(:final emailAddress):
          email ??= emailAddress;
        case GoogleOAuthAccount(email: final e, name: final n):
          email ??= e;
          name ??= n;
        case AppleOAuthAccount(email: final e):
          email ??= e;
        default:
          break;
      }
    }
    return (email: email, name: name);
  }

  static Future<void> signOut() async {
    final p = await privy();
    try {
      await p?.logout();
    } catch (_) {}
    _user = null;
  }

  // ── what the server learns ──────────────────────────────────────────────

  static Future<String?> _token() async {
    final u = _user;
    if (u == null) return null;
    try {
      final res = await u.getAccessToken();
      String? token;
      res.fold(onSuccess: (t) => token = t, onFailure: (_) {});
      return token;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _afterSignIn(String method) async {
    await GlyfBridge.updateSharedSettings((s) => s..['signedInWith'] = method);
    unawaited(syncProfile());
  }

  /// Who is signed in, on which phone. Called after sign-in and at launch.
  static Future<void> syncProfile() async {
    final token = await _token();
    if (token == null) return;
    final locale = Platform.localeName.replaceAll('_', '-');
    await _post('/me', token, {
      'platform': Platform.isIOS ? 'ios' : 'android',
      'appVersion': '1.0.0',
      'locale': locale,
      'region': locale.contains('-') ? locale.split('-').last : null,
      'timezone': DateTime.now().timeZoneName,
    });
  }

  /// Keyboard settings, and which kinds of detail the vault holds (never the
  /// details themselves). The server keeps only settings it lists.
  static Future<void> syncPrefs() async {
    final token = await _token();
    if (token == null) return;
    final s = await GlyfBridge.sharedSettings();
    final prefs = Map<String, dynamic>.from(s)
      ..remove('privyAppId')
      ..remove('privyAppClientId')
      ..remove('backendURL')
      ..remove('deviceId')
      ..remove('lastLat')
      ..remove('lastLon');
    try {
      final raw = await GlyfBridge.vaultList();
      if (raw != null) {
        final vault = jsonDecode(raw) as Map;
        prefs['vaultKinds'] = [
          for (final f in (vault['fields'] as List? ?? const []))
            if (f is Map && f['kind'] is String) f['kind'],
        ];
        prefs['shorthandCount'] = (vault['snippets'] as List?)?.length ?? 0;
      }
      final notes = await GlyfBridge.notesList();
      prefs['noteCount'] = notes.length;
    } catch (_) {}
    await _post('/me/prefs', token, {'prefs': prefs});
  }

  /// App events (names, counts, ids; never text), when someone is signed in.
  static Future<bool> sendEvents(List<Map<String, dynamic>> events) async {
    final token = await _token();
    if (token == null) return false;
    return _post('/me/events', token, {
      'events': [
        for (final e in events)
          {
            'name': e['event'],
            'at': e['ts'],
            'props': {
              for (final entry in e.entries)
                if (entry.key != 'event' && entry.key != 'ts') entry.key: entry.value,
            },
          },
      ],
    });
  }

  static Future<bool> _post(String path, String token, Map<String, Object?> body) async {
    try {
      final s = await GlyfBridge.sharedSettings();
      final base = (s['backendURL'] as String?) ?? 'http://127.0.0.1:8787';
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.postUrl(Uri.parse('$base$path'));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $token');
        req.write(jsonEncode(body));
        final res = await req.close().timeout(const Duration(seconds: 10));
        await res.drain<void>();
        return res.statusCode < 400;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }
}
