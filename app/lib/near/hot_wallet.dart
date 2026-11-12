import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../wallet/base58.dart';

/// HOT Wallet (NEAR) through HOT's own public relay, spoken exactly as
/// near-connect's HOT module speaks it (near-wallets/src/hotwallet/index.ts
/// in github.com/azbang/near-connect, 7 Nov 2026; the same code HOT serves
/// as near-selector's repository/hotwallet.js):
///
/// 1. The request is `{method, request, deadline, id, $hot: true, origin}`
///    as JSON, base58 of its UTF-8 bytes (the `query`); its id is the
///    SHA-1 of that base58 text, in hex. `deadline` is HOT's clock
///    (GET api0.herewallet.app/api/v1/web/time) plus 60 s, in ms.
/// 2. POST h4n.app/{id}/request `{"data": query}`.
/// 3. Open https://app.hot-labs.org/link?hotcall-{id}: a universal link,
///    so the iPhone opens HOT's app on it (Safari when HOT isn't there).
/// 4. GET h4n.app/{id}/response every 3 s: `{"data": null}` until HOT
///    answers, then `{"data": "<JSON text>"}` of `{success, payload}`.
///
/// No SDK, no key, nothing of Glyf's in between: HOT signs and sends. The
/// relay can't tell who asked, so what comes back is checked by the caller
/// (who signed, which contract) before it counts.
class HotRelay {
  HotRelay({HotHttp? http, this.pollEvery = const Duration(seconds: 3), this.origin = 'https://tryglyf.com'})
      : http = http ?? _ioHttp;

  static const relay = 'https://h4n.app';
  static const appLink = 'https://app.hot-labs.org/link';
  static const timeUrl = 'https://api0.herewallet.app/api/v1/web/time';

  final HotHttp http;
  final Duration pollEvery;

  /// What HOT shows as the asker; near-connect sends the dApp page's URL.
  final String origin;

  /// HOT's clock minus ours, once it's known (the deadline is checked
  /// against HOT's time). Our clock until then.
  int? _offsetMs;

  static String linkFor(String id) => '$appLink?hotcall-$id';

  /// HOT's time in ms. Its answer is `{"ts": "<10^-12 s>"}`.
  Future<int> now() async {
    if (_offsetMs == null) {
      try {
        final (status, body) = await http('GET', Uri.parse(timeUrl));
        final ts = status == 200 ? BigInt.tryParse('${(jsonDecode(body) as Map)['ts']}') : null;
        if (ts != null) _offsetMs = (ts ~/ BigInt.from(10).pow(12)).toInt() * 1000 - DateTime.now().millisecondsSinceEpoch;
      } catch (_) {
        // Our own clock, as near-connect falls back to.
      }
    }
    return DateTime.now().millisecondsSinceEpoch + (_offsetMs ?? 0);
  }

  /// The request as HOT reads it, and its id.
  @visibleForTesting
  static HotCall encode(String method, Object request, {required int deadline, required String uuid, required String origin}) {
    final json = jsonEncode({'method': method, 'request': request, 'deadline': deadline, 'id': uuid, r'$hot': true, 'origin': origin});
    final query = Base58.encode(utf8.encode(json));
    final id = sha1.convert(utf8.encode(query)).toString();
    return HotCall(id: id, query: query, link: linkFor(id));
  }

  /// Leaves the request at the relay; HOT picks it up when the link opens.
  Future<HotCall> create(String method, Object request) async {
    final call = encode(method, request, deadline: await now() + 60000, uuid: _uuid4(), origin: origin);
    final (status, body) = await http('POST', Uri.parse('$relay/${call.id}/request'), body: jsonEncode({'data': call.query}));
    if (status < 200 || status >= 300) throw HotError('HOT Wallet’s relay said no${body.isEmpty ? '' : ': ${_short(body)}'}');
    return call;
  }

  /// HOT's answer to [call]: its `payload` on success. Asked every
  /// [pollEvery] (and at once when the app comes back, [wake]) until
  /// [timeout]; a dropped answer is asked again.
  Future<Object?> wait(HotCall call, {Duration timeout = const Duration(minutes: 3), Future<void>? stop}) async {
    final end = DateTime.now().add(timeout);
    var stopped = false;
    stop?.then((_) => stopped = true);
    Completer<void>? pause;
    final woke = _wake.stream.listen((_) {
      final p = pause;
      if (p != null && !p.isCompleted) p.complete();
    });
    try {
      while (true) {
        final p = pause = Completer<void>();
        final timer = Timer(pollEvery, () => p.isCompleted ? null : p.complete());
        await Future.any([p.future, ?stop]);
        timer.cancel();
        if (stopped) throw const HotError('Stopped', stopped: true);
        final answer = await _answer(call.id);
        if (answer != null) {
          if (answer['success'] == true) return answer['payload'];
          throw HotError.refused(answer['payload']);
        }
        if (DateTime.now().isAfter(end)) throw const HotError('HOT Wallet didn’t answer', timedOut: true);
      }
    } finally {
      await woke.cancel();
    }
  }

  Future<Map<String, dynamic>?> _answer(String id) async {
    try {
      final (status, body) = await http('GET', Uri.parse('$relay/$id/response'));
      if (status != 200) return null;
      final data = (jsonDecode(body) as Map)['data'];
      final parsed = data is String ? jsonDecode(data) : data;
      return parsed is Map ? Map<String, dynamic>.from(parsed) : null;
    } catch (_) {
      return null;
    }
  }

  static final _wake = StreamController<void>.broadcast();

  /// The app is back in front (HOT doesn't open Glyf again by itself): ask
  /// the relay now rather than at the next tick.
  static void wake() => _wake.add(null);

  static String _uuid4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String _short(String s) => s.length <= 80 ? s : '${s.substring(0, 77)}…';

  static Future<(int, String)> _ioHttp(String method, Uri url, {String? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.openUrl(method, url).timeout(const Duration(seconds: 10));
      req.headers.contentType = ContentType.json;
      if (body != null) req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 15));
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }
}

/// One HTTP exchange: (status, body). Tests stand in for the relay with it.
typedef HotHttp = Future<(int, String)> Function(String method, Uri url, {String? body});

/// A request left at the relay: its id and the link that opens HOT on it.
class HotCall {
  const HotCall({required this.id, required this.query, required this.link});
  final String id;
  final String query;
  final String link;
}

class HotError implements Exception {
  const HotError(this.message, {this.refused = false, this.timedOut = false, this.stopped = false});

  /// `{success: false, payload}`: HOT's own words when it gave any.
  factory HotError.refused(Object? payload) {
    final text = payload is String
        ? payload
        : payload is Map
            ? '${payload['message'] ?? payload['error'] ?? ''}'
            : '';
    return HotError(text.trim().isEmpty ? 'Cancelled in HOT Wallet' : text.trim(), refused: true);
  }

  final String message;

  /// The person said no in HOT (or HOT couldn't do it).
  final bool refused;
  final bool timedOut;
  final bool stopped;

  @override
  String toString() => message;
}

/// The NEAR account HOT signed in with: its id and the public key HOT
/// gave for it ("ed25519:…").
class HotAccount {
  const HotAccount(this.accountId, this.publicKey);
  final String accountId;
  final String? publicKey;
}

/// One NEAR transaction as HOT's relay takes it: the receiver and
/// near-connect's JSON actions (no borsh: HOT builds and signs it).
class NearTransaction {
  const NearTransaction(this.receiverId, this.actions);
  final String receiverId;
  final List<Map<String, Object?>> actions;

  Map<String, Object?> toJson() => {'receiverId': receiverId, 'actions': actions};

  static final tgas = BigInt.from(10).pow(12);
  static final yoctoPerNear = BigInt.from(10).pow(24);

  /// A NEP-145 registration on wrap.near and NEAR's USDC (both
  /// storage_balance_bounds 0.00125 NEAR); registration_only gives back
  /// anything over it, and all of it to an account already registered.
  static final storageDeposit = BigInt.parse('1250000000000000000000');

  static Map<String, Object?> transfer(BigInt yocto) => {
        'type': 'Transfer',
        'params': {'deposit': '$yocto'},
      };

  static Map<String, Object?> functionCall(String methodName, Map<String, Object?> args,
          {required BigInt gas, required BigInt deposit}) =>
      {
        'type': 'FunctionCall',
        'params': {'methodName': methodName, 'args': args, 'gas': '$gas', 'deposit': '$deposit'},
      };

  /// NEAR itself from the signer to [receiverId].
  static NearTransaction nearTransfer(String receiverId, BigInt yocto) => NearTransaction(receiverId, [transfer(yocto)]);

  /// [amount] of the NEP-141 token at [token] to [receiverId]: registered
  /// there first (a fresh implicit account, like 1Click's deposit
  /// addresses, isn't), and wrapped first when it's wNEAR paid from NEAR.
  static NearTransaction ftTransfer({required String token, required String receiverId, required BigInt amount,
      bool register = true, bool wrap = false}) {
    return NearTransaction(token, [
      if (register)
        functionCall('storage_deposit', {'account_id': receiverId, 'registration_only': true},
            gas: tgas * BigInt.from(30), deposit: storageDeposit),
      if (wrap) functionCall('near_deposit', {}, gas: tgas * BigInt.from(10), deposit: amount),
      functionCall('ft_transfer', {'receiver_id': receiverId, 'amount': '$amount'}, gas: tgas * BigInt.from(30), deposit: BigInt.one),
    ]);
  }

  /// [receiverId]'s contract method [method], for a DAO's add_proposal or
  /// act_proposal and the like.
  static NearTransaction call(String receiverId, String method, Map<String, Object?> args,
          {BigInt? gas, BigInt? deposit}) =>
      NearTransaction(receiverId, [
        functionCall(method, args, gas: gas ?? tgas * BigInt.from(100), deposit: deposit ?? BigInt.zero),
      ]);
}

/// What HOT says it sent: the transaction's hash, who signed it, its
/// receiver, and whether NEAR ran it (a FinalExecutionOutcome's status).
class NearSent {
  const NearSent({required this.hash, this.signer, this.receiver, this.failure});
  final String hash;
  final String? signer;
  final String? receiver;

  /// NEAR's reason when it failed (status.Failure), else null.
  final String? failure;

  static String explorer(String hash) => 'https://nearblocks.io/txns/$hash';

  static NearSent? fromJson(Object? j) {
    if (j is String && j.isNotEmpty) return NearSent(hash: j);
    if (j is! Map) return null;
    final tx = j['transaction'], to = j['transaction_outcome'], status = j['status'];
    final hash = tx is Map && tx['hash'] is String
        ? tx['hash'] as String
        : to is Map && to['id'] is String
            ? to['id'] as String
            : j['hash'] is String
                ? j['hash'] as String
                : null;
    if (hash == null) return null;
    final failure = status is Map && status.containsKey('Failure') ? jsonEncode(status['Failure']) : null;
    return NearSent(
      hash: hash,
      signer: tx is Map ? tx['signer_id'] as String? : null,
      receiver: tx is Map ? tx['receiver_id'] as String? : null,
      failure: failure,
    );
  }
}

/// The person's HOT Wallet: Connect (near:signIn) keeps the NEAR account
/// and its public key in the shared settings (`nearAccount`,
/// `nearPublicKey`) beside MetaMask's and Phantom's, never over them;
/// transactions go through near:signAndSendTransactions.
abstract final class HotWallet {
  @visibleForTesting
  static HotRelay relay = HotRelay();

  /// Opens a link: the universal link to HOT. A test (or the simulator,
  /// with no HOT app) sees it.
  @visibleForTesting
  static Future<bool> Function(String url) open = GlyfBridge.openURL;

  static final account = ValueNotifier<HotAccount?>(null);

  static const name = 'HOT Wallet';

  static Completer<void>? _stop;

  /// The account kept on this phone, if HOT was connected.
  static Future<HotAccount?> load() async {
    final s = await GlyfBridge.sharedSettings();
    final id = (s['nearAccount'] as String?)?.trim();
    final a = id == null || id.isEmpty ? null : HotAccount(id, s['nearPublicKey'] as String?);
    account.value = a;
    return a;
  }

  /// Leaves [method] at the relay and opens HOT on it.
  static Future<HotCall> start(String method, Object request) async {
    final call = await relay.create(method, request);
    if (!await open(call.link)) throw const HotError('Couldn’t open HOT Wallet');
    return call;
  }

  static Future<Object?> finish(HotCall call, {Duration timeout = const Duration(minutes: 3)}) {
    final stop = _stop = Completer<void>();
    return relay.wait(call, timeout: timeout, stop: stop.future).whenComplete(() {
      if (identical(_stop, stop)) _stop = null;
    });
  }

  /// The screen's Stop while HOT is up.
  static void stopWaiting() {
    final s = _stop;
    if (s != null && !s.isCompleted) s.complete();
  }

  /// Sign in with HOT: the NEAR account it names, kept. [opened] hears the
  /// link (for the screen's "Open HOT Wallet" while it waits).
  static Future<HotAccount> connect({void Function(String link)? opened}) async {
    final call = await start('near:signIn', <String, Object?>{});
    opened?.call(call.link);
    final payload = await finish(call);
    final m = payload is Map ? payload : const {};
    final id = '${m['accountId'] ?? ''}'.trim();
    if (!_isAccount(id)) throw const HotError('HOT Wallet sent an answer Glyf can’t read');
    final key = m['publicKey'] is String ? m['publicKey'] as String : null;
    await GlyfBridge.updateSharedSettings((s) {
      s['nearAccount'] = id;
      if (key != null) {
        s['nearPublicKey'] = key;
      } else {
        s.remove('nearPublicKey');
      }
      s['nearWallet'] = 'hot';
      return s;
    });
    return account.value = HotAccount(id, key);
  }

  /// Forgets HOT on this phone; MetaMask and Phantom stay as they are.
  static Future<void> disconnect() async {
    await GlyfBridge.updateSharedSettings((s) => s
      ..remove('nearAccount')
      ..remove('nearPublicKey')
      ..remove('nearWallet'));
    account.value = null;
  }

  /// Opens HOT to sign and send [transactions] (in order) from the
  /// connected account. The answer is [sent].
  static Future<HotCall> signAndSend(List<NearTransaction> transactions) =>
      start('near:signAndSendTransactions', {'transactions': [for (final t in transactions) t.toJson()]});

  /// HOT's answer to [signAndSend]: one NearSent per transaction, checked
  /// against what was asked (who signed, which receiver).
  static Future<List<NearSent>> sent(HotCall call, List<NearTransaction> asked, {required String signer}) async {
    final payload = await finish(call);
    final rows = payload is Map ? payload['transactions'] : payload;
    final out = [for (final r in (rows is List ? rows : const [])) ?NearSent.fromJson(r)];
    if (out.length != asked.length) throw const HotError('HOT Wallet sent an answer Glyf can’t read');
    for (var i = 0; i < out.length; i++) {
      final s = out[i];
      if ((s.signer != null && s.signer != signer) || (s.receiver != null && s.receiver != asked[i].receiverId)) {
        throw const HotError('That isn’t what Glyf asked HOT Wallet to send');
      }
    }
    return out;
  }

  /// A NEAR account id: a named one (alice.near, sub.alice.near) or an
  /// implicit one (64 hex), as NEAR validates them.
  static bool _isAccount(String id) =>
      id.length >= 2 && id.length <= 64 && RegExp(r'^(([a-z\d]+[-_])*[a-z\d]+\.)*([a-z\d]+[-_])*[a-z\d]+$').hasMatch(id);

  static bool isAccount(String id) => _isAccount(id);

  /// The account's NEAR (in yocto), from NEAR's RPC; null when it can't be read.
  static Future<BigInt?> balance(String accountId, {HotHttp? http}) async {
    try {
      final (status, body) = await (http ?? HotRelay._ioHttp)('POST', Uri.parse('https://rpc.mainnet.near.org'),
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 'glyf',
            'method': 'query',
            'params': {'request_type': 'view_account', 'finality': 'final', 'account_id': accountId},
          }));
      if (status != 200) return null;
      final amount = ((jsonDecode(body) as Map)['result'] as Map?)?['amount'];
      return amount is String ? BigInt.tryParse(amount) : null;
    } catch (_) {
      return null;
    }
  }

  /// yocto as NEAR, at most [digits] decimals, no trailing zeros.
  static String format(BigInt yocto, {int digits = 4}) {
    final whole = yocto ~/ NearTransaction.yoctoPerNear;
    final frac = (yocto % NearTransaction.yoctoPerNear).toString().padLeft(24, '0').substring(0, digits);
    final f = frac.replaceFirst(RegExp(r'0+$'), '');
    return f.isEmpty ? '$whole' : '$whole.$f';
  }
}
