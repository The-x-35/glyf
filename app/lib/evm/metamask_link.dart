import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kReleaseMode;

import '../core/bridge.dart';

/// MetaMask's own deeplink protocol, the one its iOS SDK spoke (the SDK is
/// archived; MetaMask Mobile still answers it, DeeplinkProtocolService.ts):
/// Glyf builds the request, opens MetaMask on it, the person approves there,
/// and MetaMask opens glyf://mmsdk?message=… with the answer. No server, no
/// page, no key: nothing in between but the two apps.
///
/// The messages are base64 JSON, not encrypted, and MetaMask can't tell who
/// sent one, so every answer is checked by the caller (EvmSigner) before it
/// counts: who signed, who sent, that it landed.
abstract final class MetaMaskLink {
  static const _dappScheme = 'glyf';

  /// Opens MetaMask on whatever it's showing: the screen's "Open MetaMask"
  /// while it waits. Never the request again, which MetaMask would queue twice.
  static const home = 'metamask://';
  static const _originator = {
    'title': 'Glyf',
    'url': 'https://tryglyf.com',
    'icon': 'https://tryglyf.com/icon.png',
    'dappId': 'tryglyf.com',
    'platform': 'ios',
    'apiVersion': '0.8.10',
  };

  /// One channel for this install; MetaMask keeps the connection under it.
  static String? _channel;

  /// The chain MetaMask last said it was on ("0x2105"), from its answers.
  static String? walletChain;

  static final Map<String, Completer<MetaMaskReply>> _waiting = {};
  static int _lastId = 0;

  static Future<String> _channelId() async {
    if (_channel != null) return _channel!;
    final s = await GlyfBridge.sharedSettings();
    var id = s['mmChannel'] as String?;
    if (id == null) {
      final r = Random.secure();
      final b = List<int>.generate(16, (_) => r.nextInt(256));
      b[6] = (b[6] & 0x0f) | 0x40;
      b[8] = (b[8] & 0x3f) | 0x80;
      final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      id = '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
      final saved = id;
      await GlyfBridge.updateSharedSettings((s) => s..['mmChannel'] = saved);
    }
    return _channel = id;
  }

  /// Numeric ids: MetaMask parses a batch's id as a number.
  static String _nextId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastId = now > _lastId ? now : _lastId + 1;
    return '$_lastId';
  }

  static String _b64(Object json) => base64.encode(utf8.encode(jsonEncode(json)));

  static String hexChain(int chainId) => '0x${chainId.toRadixString(16)}';

  /// UTF-8 text as 0x hex, the way personal_sign takes a message.
  static String hexText(String s) =>
      '0x${utf8.encode(s).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  /// The link that connects and signs [message] in one trip: MetaMask asks
  /// to connect, then to sign; the answer names the account.
  static Future<(String id, String url)> connectLink(String message) async {
    final id = _nextId();
    final request = jsonEncode({'id': id, 'method': 'metamask_connectSign', 'params': [hexText(message)]});
    final url = 'metamask://connect?scheme=$_dappScheme'
        '&channelId=${await _channelId()}&comm=deeplinking'
        '&originatorInfo=${Uri.encodeComponent(_b64(_originator))}'
        '&request=${Uri.encodeComponent(request)}';
    return (id, url);
  }

  /// The link for one request (or a metamask_batch) from [account] on
  /// [chainId]. MetaMask refuses one whose account or chain isn't the one it
  /// has selected, except a chain switch, so callers lead with one.
  static Future<(String id, String url)> requestLink(String method, List<Object?> params,
      {required String account, required int chainId}) async {
    final id = _nextId();
    final message = _b64({'id': id, 'jsonrpc': '2.0', 'method': method, 'params': params});
    final url = 'metamask://mmsdk?scheme=$_dappScheme'
        '&message=${Uri.encodeComponent(message)}'
        '&channelId=${await _channelId()}'
        '&account=$account@${hexChain(chainId)}';
    return (id, url);
  }

  /// Opens [url] in MetaMask and waits for its answer to [id].
  static Future<MetaMaskReply> send(String id, String url, {required Future<void> stop}) async {
    final done = _waiting[id] = Completer<MetaMaskReply>();
    try {
      final opened = await _stand(url) || await GlyfBridge.openMetaMask(url);
      if (!opened) throw const MetaMaskError(-1, 'Install MetaMask to sign with it');
      return await Future.any([
        done.future,
        stop.then<MetaMaskReply>((_) => throw const MetaMaskError(4001, 'Stopped')),
      ]).timeout(const Duration(minutes: 10),
          onTimeout: () => throw const MetaMaskError(-2, 'MetaMask didn’t answer'));
    } finally {
      _waiting.remove(id);
    }
  }

  /// Scenarios have no MetaMask on the simulator: with
  /// `--glyf-test-metamask` (never in a release build) the request lands in
  /// Documents/metamask-request.txt, and qa/fake-metamask.mjs answers it
  /// with glyf://mmsdk the way MetaMask does.
  static Future<bool> _stand(String url) async {
    if (kReleaseMode || !(await GlyfBridge.launchArgs()).contains('--glyf-test-metamask')) return false;
    final dir = await GlyfBridge.documentsPath();
    if (dir == null) return false;
    await File('$dir/metamask-request.txt').writeAsString(url);
    return true;
  }

  /// glyf://mmsdk?message=… — MetaMask answering. Returns false for anything
  /// that isn't one of its answers.
  static bool handle(Uri uri) {
    if (uri.host != 'mmsdk') return false;
    final raw = uri.queryParameters['message'];
    if (raw == null) return true;
    final Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(jsonDecode(utf8.decode(base64.decode(base64.normalize(raw)))) as Map);
    } catch (_) {
      return true;
    }
    if (json['type'] == 'terminate') {
      for (final c in _waiting.values) {
        if (!c.isCompleted) c.completeError(const MetaMaskError(4900, 'MetaMask ended the connection'));
      }
      return true;
    }
    final data = json['data'];
    if (data is! Map) return true; // "ready" and the like
    final reply = MetaMaskReply.from(Map<String, dynamic>.from(data));
    if (reply.chainId != null) walletChain = reply.chainId;
    final waiter = _waiting[reply.id];
    if (waiter != null && !waiter.isCompleted) waiter.complete(reply);
    return true;
  }
}

/// One answer from MetaMask: the request's id, its result or error, and the
/// account and chain MetaMask is on now.
class MetaMaskReply {
  const MetaMaskReply({required this.id, this.result, this.error, this.accounts = const [], this.chainId});

  factory MetaMaskReply.from(Map<String, dynamic> d) {
    final e = d['error'];
    return MetaMaskReply(
      id: '${d['id'] ?? ''}',
      result: d['result'],
      error: e is Map ? MetaMaskError((e['code'] as num?)?.toInt() ?? -1, '${e['message'] ?? 'MetaMask said no'}') : null,
      accounts: [for (final a in (d['accounts'] as List? ?? const [])) '$a'],
      chainId: d['chainId'] as String?,
    );
  }

  final String id;
  final Object? result;
  final MetaMaskError? error;
  final List<String> accounts;
  final String? chainId;
}

class MetaMaskError implements Exception {
  const MetaMaskError(this.code, this.message);
  final int code;
  final String message;

  /// The person said no in MetaMask (EIP-1193 4001), or Stop here.
  bool get refused => code == 4001;

  /// MetaMask's account or chain isn't the one asked for (-32602).
  bool get changed => code == -32602;

  /// MetaMask forgot this channel (reinstalled, disconnected): connect again.
  bool get unauthorized => code == 4100 || message.toLowerCase().contains('unauthorized');

  @override
  String toString() => message;
}
