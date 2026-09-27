import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;

import 'bridge.dart';

/// Signing in, once, for the whole app: Sign in with Apple on the iPhone,
/// Google on both phones.
///
/// The phone signs in natively and gets an ID token from Apple or Google. The
/// Glyf server checks it against the provider's keys (POST /auth/session) and
/// hands back its own session, kept in the Keychain or behind a Keystore key.
/// After that the server hears which phone this is (POST /me), the keyboard
/// settings and app events. The vault never leaves the phone: only which
/// KINDS of detail were saved are sent.
abstract final class Auth {
  static _Account? _account;
  static bool _testSignedIn = false;

  /// The account a UI test says it is signed in with, for Profile to show.
  static ({String provider, String email})? _testAccount;

  static bool get signedIn => _account != null || _testSignedIn;

  /// Whether someone is signed in on this phone. Works offline: the session
  /// is on the phone and carries its own expiry.
  static Future<bool> restore() async {
    // UI tests reach the screens behind sign-in without a real account
    // (`--glyf-test-account=google:someone@example.com` names one).
    // Never in a release build.
    if (!kReleaseMode) {
      final args = await GlyfBridge.launchArgs();
      // `--glyf-test-session=<token>` seeds a real Glyf session (minted on the
      // server side with its SESSION_SECRET), so an end-to-end run on a
      // simulator can call the API as a signed-in user without anyone typing
      // Google or Apple credentials. Saved like a real sign-in, so the
      // keyboard sees it too.
      const seed = '--glyf-test-session=';
      final seeded = args.where((a) => a.startsWith(seed)).map((a) => a.substring(seed.length)).firstOrNull;
      if (seeded != null && seeded.isNotEmpty) {
        final account = _Account(
          token: seeded, id: 'sim-e2e', provider: 'google',
          email: 'sim-e2e@example.com', name: 'Sim Tester',
        );
        await GlyfBridge.sessionSave(account.toJson());
        _account = account;
        await GlyfBridge.updateSharedSettings((s) => s..['signedInWith'] = 'google');
        return true;
      }
      if (args.contains('--glyf-test-signed-in')) {
        _testSignedIn = true;
        const flag = '--glyf-test-account=';
        final named = args.where((a) => a.startsWith(flag)).map((a) => a.substring(flag.length)).firstOrNull;
        final split = named?.indexOf(':') ?? -1;
        if (named != null && split > 0) {
          _testAccount = (provider: named.substring(0, split), email: named.substring(split + 1));
        }
        return true;
      }
    }
    final raw = await GlyfBridge.sessionLoad();
    final account = raw == null ? null : _Account.fromJson(raw);
    if (account == null || account.expired) {
      if (raw != null) await GlyfBridge.sessionClear();
      _account = null;
      return false;
    }
    _account = account;
    return true;
  }

  /// Null once signed in, or when the person closed the sheet; otherwise
  /// what to tell them.
  static Future<String?> signInWithGoogle() async {
    final config = await _config();
    if (config == null) return _offline;
    final google = config['google'];
    final clientId = google is Map ? (Platform.isIOS ? google['iosClientId'] : google['webClientId']) : null;
    if (clientId is! String || clientId.isEmpty) return 'Google sign-in is not set up yet.';
    final nonce = _nonce();
    final error = await _finish('google', await GlyfBridge.signInGoogle(clientId: clientId, nonce: nonce), nonce);
    // Google Calendar and Meet come with signing in with Google: the
    // iPhone's Google page asked for them already, Android asks right after.
    if (error == null && Platform.isAndroid) {
      await GlyfBridge.googleConnect(loginHint: _account?.email);
    }
    return error;
  }

  /// Connected tools' Connect for Google Calendar and Meet. Null when it
  /// worked or the person closed Google's page; otherwise what to tell them.
  static Future<String?> connectGoogle() async {
    String? clientId;
    if (Platform.isIOS) {
      final config = await _config();
      if (config == null) return _offline;
      final google = config['google'];
      clientId = google is Map ? google['iosClientId'] as String? : null;
      if (clientId == null || clientId.isEmpty) return 'Google is not set up yet.';
    }
    final res = await GlyfBridge.googleConnect(
        clientId: clientId, loginHint: _account?.provider == 'google' ? _account?.email : null);
    final error = res['error'];
    if (error == null) return null;
    if (error == 'not_granted') return 'Calendar and Meet were left unticked.';
    return _friendly('$error');
  }

  static Future<String?> signInWithApple() async {
    final config = await _config();
    if (config == null) return _offline;
    if (config['apple'] != true) return 'Sign in with Apple is not set up yet.';
    final nonce = _nonce();
    return _finish('apple', await GlyfBridge.signInApple(nonce), nonce);
  }

  static const _offline = 'No connection. Try again when you are online.';

  /// The door App Review comes through: the password from App Store
  /// Connect, no Apple or Google account. The sign-in screen shows it only
  /// behind a triple-tap on the orb, as the review notes say. Null once
  /// signed in; otherwise what to say.
  static Future<String?> signInForReview(String password) async {
    final trimmed = password.trim();
    if (trimmed.isEmpty) return 'Enter the reviewer password.';
    final reply = await _send('POST', '/auth/review', body: {'password': trimmed});
    if (reply == null) return _offline;
    final body = reply.body;
    if (reply.status >= 400 || body?['ok'] != true || body?['token'] is! String) {
      return body?['error'] as String? ?? 'Sign-in did not finish. Try again.';
    }
    final user = body!['user'] is Map ? body['user'] as Map : const {};
    final account = _Account(
      token: body['token'] as String,
      id: '${user['id'] ?? ''}',
      provider: 'review',
      email: user['email'] as String?,
      name: user['name'] as String?,
    );
    await GlyfBridge.sessionSave(account.toJson());
    _account = account;
    // The month of Max the server put on the review account, kept the way
    // a purchase would leave it, so the paid features are on to review.
    final plan = body['plan'] as String? ?? 'free';
    await GlyfBridge.updateSharedSettings((s) => s
      ..['signedInWith'] = 'review'
      ..['plan'] = plan
      ..['proUnlocked'] = plan != 'free');
    unawaited(syncPrefs());
    return null;
  }

  /// The provider's token in, a Glyf session out.
  static Future<String?> _finish(String provider, Map<String, dynamic> res, String nonce) async {
    final idToken = res['idToken'];
    if (idToken is! String) return _friendly('${res['error'] ?? 'failed'}');
    final name = res['name'] is String ? res['name'] as String : null;
    final reply = await _send('POST', '/auth/session', body: {
      'provider': provider,
      'idToken': idToken,
      'nonce': nonce,
      'name': ?name,
      'device': _device(),
    });
    if (reply == null) return _offline;
    final body = reply.body;
    if (reply.status >= 400 || body?['ok'] != true || body?['token'] is! String) {
      return body?['error'] as String? ?? 'Sign-in could not be verified. Try again.';
    }
    final user = body!['user'] is Map ? body['user'] as Map : const {};
    final account = _Account(
      token: body['token'] as String,
      id: '${user['id'] ?? ''}',
      provider: provider,
      email: user['email'] as String? ?? res['email'] as String?,
      name: user['name'] as String? ?? name,
    );
    await GlyfBridge.sessionSave(account.toJson());
    _account = account;
    await GlyfBridge.updateSharedSettings((s) => s..['signedInWith'] = provider);
    unawaited(syncPrefs());
    return null;
  }

  static String? _friendly(String error) {
    if (!kReleaseMode) debugPrint('glyf sign-in: $error');
    switch (error) {
      case 'cancelled':
        return null;
      case 'not_configured':
        return 'Google sign-in is not set up yet.';
      case 'apple_unavailable':
        return 'Sign in with Apple is not available on this phone.';
      case 'no_account':
        return 'Add a Google account to this phone, then try again.';
      case 'network':
        return _offline;
    }
    final m = error.toLowerCase();
    if (m.contains('network') || m.contains('internet') || m.contains('offline')) return _offline;
    if (m.contains('invalid_client') || m.contains('unregistered') || m.contains('developer console')) {
      return 'Google sign-in is not set up yet.';
    }
    return 'Sign-in did not finish. Try again.';
  }

  /// The session to send with every call to the server. Null when nobody is
  /// signed in, which is also when the server will refuse.
  static String? get bearer => _account?.expired == false ? _account?.token : null;

  /// The email and name the account came with (for the vault and Profile),
  /// and whether it is a Google or an Apple account.
  static ({String? email, String? name, String? provider}) identity() => (
        email: _account?.email ?? _testAccount?.email,
        name: _account?.name,
        provider: _account?.provider ?? _testAccount?.provider,
      );

  static Future<void> signOut() async {
    await GlyfBridge.sessionClear();
    await GlyfBridge.signOutProviders();
    _account = null;
    _testSignedIn = false;
    _testAccount = null;
  }

  /// Deletes the account and everything the server keeps for it (DELETE
  /// /me: the account, its synced settings and its app events), then signs
  /// out. False when the server couldn't be reached or refused: nothing is
  /// signed out then, so it can be tried again. A session the server no
  /// longer knows (401) has nothing left to delete.
  static Future<bool> deleteAccount() async {
    final token = _account?.token;
    if (token != null) {
      final reply = await _send('DELETE', '/me', token: token);
      if (reply == null || (reply.status >= 400 && reply.status != 401)) return false;
    }
    await signOut();
    return true;
  }

  // ── what the server learns ──────────────────────────────────────────────

  static Map<String, Object?> _device() {
    final locale = Platform.localeName.replaceAll('_', '-');
    return {
      'platform': Platform.isIOS ? 'ios' : 'android',
      'appVersion': '1.0.0',
      'locale': locale,
      'region': locale.contains('-') ? locale.split('-').last : null,
      'timezone': DateTime.now().timeZoneName,
    };
  }

  /// Who is signed in, on which phone. Called at launch.
  static Future<void> syncProfile() async {
    final token = _account?.token;
    if (token == null) return;
    await _authed('/me', token, _device());
  }

  /// Keyboard settings, and which kinds of detail the vault holds (never the
  /// details themselves). The server keeps only settings it lists.
  static Future<void> syncPrefs() async {
    final token = _account?.token;
    if (token == null) return;
    final s = await GlyfBridge.sharedSettings();
    final prefs = Map<String, dynamic>.from(s)
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
    await _authed('/me/prefs', token, {'prefs': prefs});
  }

  /// App events (names, counts, ids; never text), when someone is signed in.
  static Future<bool> sendEvents(List<Map<String, dynamic>> events) async {
    final token = _account?.token;
    if (token == null) return false;
    return _authed('/me/events', token, {
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

  /// A call as the signed-in person. A session the server no longer accepts
  /// is dropped, so the next launch asks to sign in again.
  static Future<bool> _authed(String path, String token, Map<String, Object?> body) async {
    final reply = await _send('POST', path, body: body, token: token);
    if (reply == null) return false;
    if (reply.status == 401) {
      await GlyfBridge.sessionClear();
      _account = null;
    }
    return reply.status < 400;
  }

  static Future<Map<String, dynamic>?> _config() async {
    final reply = await _send('GET', '/auth/config');
    return reply != null && reply.status < 400 ? reply.body : null;
  }

  static Future<({int status, Map<String, dynamic>? body})?> _send(String method, String path,
      {Map<String, Object?>? body, String? token}) async {
    try {
      final s = await GlyfBridge.sharedSettings();
      final base = (s['backendURL'] as String?) ?? 'http://127.0.0.1:8787';
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.openUrl(method, Uri.parse('$base$path'));
        if (token != null) req.headers.set('Authorization', 'Bearer $token');
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final res = await req.close().timeout(const Duration(seconds: 15));
        final text = await res.transform(utf8.decoder).join();
        Map<String, dynamic>? json;
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) json = decoded;
        } catch (_) {}
        return (status: res.statusCode, body: json);
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  static String _nonce() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
  }
}

/// A Glyf session and who it belongs to, as kept on the phone.
class _Account {
  const _Account({required this.token, required this.id, required this.provider, this.email, this.name});

  final String token;
  final String id;
  final String provider;
  final String? email;
  final String? name;

  /// Read from the session's own claims; the server checks the signature.
  bool get expired {
    try {
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))));
      final exp = claims is Map ? claims['exp'] : null;
      return exp is! num || DateTime.now().millisecondsSinceEpoch / 1000 > exp;
    } catch (_) {
      return true;
    }
  }

  String toJson() => jsonEncode({'token': token, 'id': id, 'provider': provider, 'email': email, 'name': name});

  static _Account? fromJson(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final token = m['token'];
      if (token is! String || token.isEmpty) return null;
      return _Account(
        token: token,
        id: '${m['id'] ?? ''}',
        provider: '${m['provider'] ?? ''}',
        email: m['email'] as String?,
        name: m['name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
