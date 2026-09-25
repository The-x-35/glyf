import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'auth.dart';
import 'bridge.dart';

/// The privacy policy, on the website (App Store 5.1.1 wants it in the app too).
const privacyPolicyURL = 'https://www.tryglyf.com/privacy';

/// The app's own client for POST /glyf/run (SSE). The APP may talk to the
/// backend freely; the keyboard has its own Swift client behind Full Access.
abstract final class GlyfApi {
  /// Matches the native stores: dev talks to the Mac, shipped talks to
  /// tryglyf.com. Only used when shared settings carry no value yet.
  static const productionBackend = 'https://api.tryglyf.com';
  static String get _fallbackBase =>
      kReleaseMode ? productionBackend : 'http://127.0.0.1:8787';

  static Future<String> _baseUrl() async {
    final s = await GlyfBridge.sharedSettings();
    return (s['backendURL'] as String?) ?? _fallbackBase;
  }

  static Future<String> _deviceId() async {
    final s = await GlyfBridge.sharedSettings();
    return (s['deviceId'] as String?) ?? 'app-anon-device';
  }

  /// Runs a glyf, streaming tokens via [onToken]; resolves with final text.
  static Future<String> run({
    required String glyfId,
    required String input,
    Map<String, String> vars = const {},
    void Function(String token)? onToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final settings = await GlyfBridge.sharedSettings();
    final base =
        (settings['backendURL'] as String?) ?? _fallbackBase;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse('$base/glyf/run'));
      req.headers.contentType = ContentType.json;
      _signIn(req);
      req.headers.set('Accept', 'text/event-stream');
      req.write(jsonEncode({
        'glyfId': glyfId,
        'input': input,
        'vars': vars,
        'deviceId': (settings['deviceId'] as String?) ?? 'app-anon-device',
        'pro': settings['proUnlocked'] == true,
        'plan': (settings['plan'] as String?) ?? 'free', // §6.16
      }));
      final res = await req.close().timeout(timeout);

      final completer = Completer<String>();
      var full = '';
      var event = 'message';
      final sub = res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final data = jsonDecode(line.substring(5).trim());
          switch (event) {
            case 'token':
              final t = (data['t'] as String?) ?? '';
              full += t;
              onToken?.call(t);
            case 'done':
              if (!completer.isCompleted) {
                completer.complete((data['text'] as String?) ?? full);
              }
            case 'error':
              if (!completer.isCompleted) {
                completer.completeError(
                    GlyfApiException((data['message'] as String?) ?? 'failed'));
              }
          }
        }
      }, onDone: () {
        if (!completer.isCompleted) {
          full.isEmpty
              ? completer.completeError(GlyfApiException('empty stream'))
              : completer.complete(full);
        }
      }, onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      });

      return await completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
        throw GlyfApiException('timed out');
      });
    } finally {
      client.close(force: false);
    }
  }

  /// The server turns away anyone without a session, so every call carries
  /// the one from signing in.
  static void _signIn(HttpClientRequest req) {
    final token = Auth.bearer;
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
  }

  // ---- JSON helpers ------------------------------------------------------

  static Future<Map<String, dynamic>> _postJson(
      String path, Map<String, Object?> body,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final base = await _baseUrl();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse('$base$path'));
      req.headers.contentType = ContentType.json;
      _signIn(req);
      req.write(jsonEncode(body));
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      final obj = jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw GlyfApiException(
            (obj['error'] as String?) ?? 'HTTP ${res.statusCode}');
      }
      return obj;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> _getJson(String path,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final base = await _baseUrl();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('$base$path'));
      _signIn(req);
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      final obj = jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw GlyfApiException(
            (obj['error'] as String?) ?? 'HTTP ${res.statusCode}');
      }
      return obj;
    } finally {
      client.close();
    }
  }

  static Future<String> _delete(String path) async {
    final base = await _baseUrl();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.deleteUrl(Uri.parse('$base$path'));
      _signIn(req);
      final res = await req.close().timeout(const Duration(seconds: 8));
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  // ---- §6.8 Builder ------------------------------------------------------

  /// Plain English → validated Builder-format def (strict, fail-closed).
  /// Generation can take a while on the smart tier.
  static Future<Map<String, dynamic>> builderGenerate(String description) async {
    final obj = await _postJson('/builder/generate', {
      'description': description,
      'deviceId': await _deviceId(),
    }, timeout: const Duration(seconds: 90));
    return (obj['def'] as Map).cast<String, dynamic>();
  }

  /// Test-drive a (possibly edited) def against sample input.
  static Future<String> builderTest(
      Map<String, dynamic> def, String input) async {
    final obj = await _postJson('/builder/test', {
      'def': def,
      'input': input,
      'deviceId': await _deviceId(),
    }, timeout: const Duration(seconds: 90));
    return (obj['text'] as String?) ?? '';
  }

  /// Save to my library; server assigns the `user.<hex>` id + moderates.
  static Future<Map<String, dynamic>> saveGlyf(Map<String, dynamic> def) async {
    final obj = await _postJson('/glyfs', {
      'def': def,
      'deviceId': await _deviceId(),
    });
    return (obj['def'] as Map?)?.cast<String, dynamic>() ?? obj;
  }

  static Future<List<Map<String, dynamic>>> myGlyfs() async {
    final obj = await _getJson('/glyfs?deviceId=${await _deviceId()}');
    return (obj['glyfs'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<void> deleteGlyf(String id) async =>
      _delete('/glyfs/$id?deviceId=${await _deviceId()}');

  // ---- §6.9 Hub ----------------------------------------------------------

  static Future<void> hubPublish(String glyfId) async =>
      _postJson('/hub/publish',
          {'glyfId': glyfId, 'deviceId': await _deviceId()});

  // ---- Vocabulary: words for the keyboard from a description -------------

  /// {name, words, phrases} for the user to review before saving. Only the
  /// description is sent — never anything typed.
  static Future<Map<String, dynamic>> vocabGenerate(String description) async {
    final settings = await GlyfBridge.sharedSettings();
    return _postJson('/vocab/generate', {
      'description': description,
      'deviceId': await _deviceId(),
      'plan': (settings['plan'] as String?) ?? 'free',
    }, timeout: const Duration(seconds: 120)); // free models can take a minute
  }

  // ---- Skills browser (shipped + community) ----------------------------

  /// {categories: [...], skills: [{id,name,icon,category,author,official,
  /// installs,discloses,version}]} — install counts are real, per device.
  static Future<Map<String, dynamic>> skills() async => _getJson('/skills');

  static Future<List<Map<String, dynamic>>> skillCreators() async {
    final obj = await _getJson('/skills/creators');
    return (obj['creators'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Adds a skill: shipped ones are counted, community ones version-pinned.
  static Future<Map<String, dynamic>> skillGet(String glyfId) async =>
      _postJson('/skills/get',
          {'glyfId': glyfId, 'deviceId': await _deviceId()});

  static Future<void> setDisplayName(String name) async => _postJson(
      '/account/name', {'deviceId': await _deviceId(), 'displayName': name});

  static Future<Map<String, dynamic>> creatorStats() async =>
      _getJson('/account/${await _deviceId()}/creator');

  // ---- §6.11/§6.12 connectors -------------------------------------------

  /// {providers: [{id,label,configured,connected,scopes,email}], mock: {…}}.
  static Future<Map<String, dynamic>> connectorsStatus() async =>
      _getJson('/connectors/status?deviceId=${await _deviceId()}');

  /// Consent URL for the Google code flow with the USER-chosen scopes
  /// (comma list of: calendar, gmail, meet). Throws GlyfApiException with
  /// the unconfigured message until credentials land server-side.
  static Future<String> googleStartUrl(List<String> scopes) async {
    final obj = await _getJson(
        '/oauth/google/start?deviceId=${await _deviceId()}'
        '&scopes=${scopes.join(",")}');
    return obj['url'] as String;
  }

  static Future<void> disconnect(String provider) async =>
      _postJson('/connectors/disconnect',
          {'deviceId': await _deviceId(), 'provider': provider});

  // ---- §6.16 meter -------------------------------------------------------

  static Future<int?> meterRemaining() async => (await meterStatus())?.remaining;

  /// What the server is enforcing: runs left today, on which plan, out of
  /// how many. The plan card shows this, never the phone's own claim.
  static Future<({int remaining, String plan, int perDay})?> meterStatus() async {
    try {
      final obj = await _getJson('/meter/${await _deviceId()}');
      final remaining = obj['remaining'] as int?;
      if (remaining == null) return null;
      return (
        remaining: remaining,
        plan: (obj['plan'] as String?) ?? 'free',
        perDay: (obj['perDay'] as int?) ?? 40,
      );
    } catch (_) {
      return null;
    }
  }

  /// POST /me/plan — the paywall's pick. The server decides whether it may
  /// (self-serve is a dev/TestFlight switch); the answer is what we keep.
  static Future<Map<String, dynamic>> setPlan(String plan) =>
      _postJson('/me/plan', {'plan': plan}, timeout: const Duration(seconds: 10));

  // ---- §12 telemetry sink ------------------------------------------------

  static Future<bool> telemetryPost(List<Map<String, dynamic>> events) async {
    try {
      await _postJson('/telemetry', {
        'deviceId': await _deviceId(),
        'events': events,
      }, timeout: const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// GET /wallet/config — the public Privy ids, so no id ships in the app.
  static Future<Map<String, dynamic>?> walletConfig() async {
    try {
      final base = await _baseUrl();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(Uri.parse('$base/wallet/config'));
      _signIn(req);
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// POST /wallet/transfer — an unsigned private payment for Privy to sign.
  static Future<Map<String, dynamic>?> buildTransfer({
    required String from,
    required String to,
    required String amount,
    String mint = 'USDC',
  }) async {
    try {
      final base = await _baseUrl();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(Uri.parse('$base/wallet/transfer'));
      req.headers.contentType = ContentType.json;
      _signIn(req);
      req.write(jsonEncode({
        'from': from, 'to': to, 'amount': amount, 'mint': mint, 'private': true,
      }));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': 'Could not reach the Glyf server.'};
    }
  }

  /// GET /health — powers the backend status dot.
  static Future<bool> healthy() async {
    try {
      final base = await _baseUrl();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('$base/health'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      client.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class GlyfApiException implements Exception {
  GlyfApiException(this.message);
  final String message;

  /// §6.16: the daily free cap — the paywall moment.
  bool get capHit => message.contains('free runs used up');

  @override
  String toString() => message;
}
